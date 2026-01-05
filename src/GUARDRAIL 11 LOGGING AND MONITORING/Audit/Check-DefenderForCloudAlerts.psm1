
function Get-ResourceCountsFromARG {
    param(
        [AllowEmptyCollection()]
        [System.Collections.ArrayList]$ErrorList
    )

    # Returns: hashtable countsBySub[subscriptionId][resourceType] = count
    $countsBySub = @{}

    $query = @"
resources
| summarize c=count() by subscriptionId, type
"@

    try {
        Write-Verbose "ARG: counting resources by type across tenant..."
        $skipToken = $null
        $pageCount = 0

        do {
            $pageCount++
            if ($skipToken) {
                $results = Search-AzGraph -UseTenantScope -Query $query -First 1000 -SkipToken $skipToken -ErrorAction Stop
            } else {
                $results = Search-AzGraph -UseTenantScope -Query $query -First 1000 -ErrorAction Stop
            }

            foreach ($row in $results) {
                $sid = [string]$row.subscriptionId
                $rtype = [string]$row.type
                $cnt = [int]$row.c

                if (-not $countsBySub.ContainsKey($sid)) { $countsBySub[$sid] = @{} }
                $countsBySub[$sid][$rtype] = $cnt
            }

            $skipToken = $results.SkipToken
            Write-Verbose "ARG page $pageCount processed. HasSkipToken: $($null -ne $skipToken)"
        } while ($skipToken)

        return $countsBySub
    }
    catch {
        Write-Verbose "ARG resource count query failed: $_"
        if ($ErrorList) { [void]$ErrorList.Add("ARG resource count query failed: $_") }
        return @{}
    }
}


#ARM: Defender pricing per subscription
function Get-DefenderPricingBySubscription {
    param(
        [Parameter(Mandatory)]
        [string]$SubscriptionId,
        [Parameter(Mandatory)]
        [hashtable]$AuthHeader,
        [AllowEmptyCollection()]
        [System.Collections.ArrayList]$ErrorList
    )

    # Returns: hashtable pricingByPlan[planName] = pricingTier
    $pricingByPlan = @{}

    # Use stable API version
    $uri = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Security/pricings?api-version=2023-01-01"

    try {
        $resp = Invoke-RestMethod -Uri $uri -Method Get -Headers $AuthHeader -ErrorAction Stop
        if ($resp -and $resp.value) {
            foreach ($p in $resp.value) {
                $name = [string]$p.name
                $tier = $null
                if ($p.properties -and $p.properties.pricingTier) { $tier = [string]$p.properties.pricingTier }
                if ($name) { $pricingByPlan[$name] = $tier }
            }
        }
    }
    catch {
        if ($ErrorList) { [void]$ErrorList.Add("ARM Defender pricings failed for ${SubscriptionId}: $_") }
    }

    return $pricingByPlan
}



function Get-CwpCoverageForSubscription {
    param(
        [Parameter(Mandatory)]
        [string]$SubscriptionId,
        [Parameter(Mandatory)]
        [hashtable]$CountsBySub,      # output of Get-ResourceCountsFromARG
        [Parameter(Mandatory)]
        [hashtable]$TypeToPlanMap,    
        [Parameter(Mandatory)]
        [hashtable]$PricingByPlan,    # output of Get-DefenderPricingBySubscription
        [Parameter(Mandatory)]
        [hashtable]$msgTable
    )

    $requiredPlans = New-Object System.Collections.Generic.HashSet[string]
    $subCounts = $null
    if ($CountsBySub.ContainsKey($SubscriptionId)) { $subCounts = $CountsBySub[$SubscriptionId] }

    # Determine which plans are required based on resource presence
    foreach ($rtype in $TypeToPlanMap.Keys) {
        $cnt = 0
        if ($subCounts -and $subCounts.ContainsKey($rtype)) { $cnt = [int]$subCounts[$rtype] }

        if ($cnt -gt 0) {
            [void]$requiredPlans.Add([string]$TypeToPlanMap[$rtype])
        }
    }

    if ($requiredPlans.Count -eq 0) {
        return [PSCustomObject]@{
            coverageOk    = $true
            requiredPlans = @()
            missingPlans  = @()
            comment       = $msgTable.NoMappedResourcesOrMappingIncomplete
        }
    }

    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($plan in $requiredPlans) {
        $tier = $null
        if ($PricingByPlan.ContainsKey($plan)) { $tier = $PricingByPlan[$plan] }

        if (-not $tier -or ($tier.ToString().ToLower() -ne "standard")) {
            $missing.Add($plan) | Out-Null
        }
    }

    if ($missing.Count -gt 0) {
        return [PSCustomObject]@{
            coverageOk    = $false
            requiredPlans = @($requiredPlans)
            missingPlans  = @($missing)
            comment       = $msgTable.CwpPlansNotStandard -f ($missing -join ", ")
        }
    }

    return [PSCustomObject]@{
        coverageOk    = $true
        requiredPlans = @($requiredPlans)
        missingPlans  = @()
        comment       = $msgTable.CoverageOk
    }
}


#DFCA notification compliance
function Get-DFCAcheckComplianceStatus {
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $apiResponse,
        [Parameter(Mandatory)]
        [hashtable] $msgTable,
        [Parameter(Mandatory)]
        [string] $SubscriptionName
    )

    $isCompliant = $true
    $Comments = ""

    $notificationSources = $apiResponse.properties.notificationsSources
    $notificationEmails  = $apiResponse.properties.emails
    $ownerRoles          = $apiResponse.properties.notificationsByRole.roles
    $ownerState          = $apiResponse.properties.notificationsByRole.state


    $alertNotification = $notificationSources | Where-Object { $_.sourceType -eq "Alert" -and $_.minimalSeverity -in @("Medium","Low") }
    $attackPathNotification = $notificationSources | Where-Object { $_.sourceType -eq "AttackPath" -and $_.minimalRiskLevel -in @("Medium","Low") }

    $emailCount = 0
    if ($notificationEmails) { $emailCount = ($notificationEmails -split ";").Count }

    $ownerConfigured = ($ownerState -eq "On") -and ($ownerRoles -contains "Owner")

    if (($emailCount -lt 2) -or (-not $ownerConfigured)) {
        $isCompliant = $false
        $Comments = $msgTable.EmailsOrOwnerNotConfigured -f $SubscriptionName
    }

    if ($null -eq $alertNotification) {
        $isCompliant = $false
        $Comments = $msgTable.AlertNotificationNotConfigured
    }

    if ($null -eq $attackPathNotification) {
        $isCompliant = $false
        $Comments = $msgTable.AttackPathNotificationNotConfigured
    }

    if ($isCompliant) {
        $Comments = $msgTable.DefenderCompliant
    }

    return [PSCustomObject]@{
        Comments    = $Comments
        isCompliant = $isCompliant
    }
}


function Get-DefenderForCloudAlerts {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ControlName,
        [Parameter(Mandatory=$true)]
        [string]$ItemName,
        [Parameter(Mandatory=$true)]
        [string]$itsgcode,
        [Parameter(Mandatory=$true)]
        [hashtable]$msgTable,
        [Parameter(Mandatory=$true)]
        [string]$ReportTime,
        [string] $CloudUsageProfiles = "3",
        [string] $ModuleProfiles,
        [switch] $EnableMultiCloudProfiles
    )

    $PsObject  = New-Object System.Collections.ArrayList
    $ErrorList = New-Object System.Collections.ArrayList

    # -------------------------
    # 1) Get enabled subscriptions
    # -------------------------
    try {
        $subs = Get-AzSubscription -ErrorAction Stop | Where-Object { $_.State -eq "Enabled" }
    }
    catch {
        [void]$ErrorList.Add("Failed Get-AzSubscription. Verify Az.Resources + permissions. Error: $_")
        throw "Error: Failed Get-AzSubscription. Verify Az.Resources + permissions. Error: $_"
    }

    # -------------------------
    # 2) ARG: resource counts (tenant-wide)
    # -------------------------
    $countsBySub = Get-ResourceCountsFromARG -ErrorList $ErrorList

    # -------------------------
    # 3) Define mapping: resourceType -> Defender pricing planName
    # -------------------------
    $TypeToPlanMap = @{
        # Compute
        "microsoft.compute/virtualmachines" = "VirtualMachines"

        # Storage
        "microsoft.storage/storageaccounts" = "StorageAccounts"

        # SQL PaaS
        "microsoft.sql/servers" = "SqlServers"
        "microsoft.sql/managedinstances" = "SqlServers"

        # SQL on VMs
        "microsoft.sqlvirtualmachine/sqlvirtualmachines" = "SqlServerVirtualMachines"

        # Key Vault
        "microsoft.keyvault/vaults" = "KeyVaults"

        # AKS
        "microsoft.containerservice/managedclusters" = "KubernetesService"

        # ACR
        "microsoft.containerregistry/registries" = "ContainerRegistry"

        # App Service
        "microsoft.web/sites" = "AppServices"

        # Cosmos
        "microsoft.documentdb/databaseaccounts" = "CosmosDbs"

        # OSS DBs
        "microsoft.dbforpostgresql/flexibleservers" = "OpenSourceRelationalDatabases"
        "microsoft.dbformysql/flexibleservers" = "OpenSourceRelationalDatabases"
    }

    foreach ($sub in $subs) {
        $subId   = [string]$sub.SubscriptionId
        $subName = [string]$sub.Name

        Write-Verbose "Evaluating subscription: $subName ($subId)"

        try { Set-AzContext -SubscriptionId $subId -ErrorAction Stop | Out-Null } catch {}

        # Build auth header once per subscription context
        $authHeader = $null
        try {
            $azContext = Get-AzContext
            $token = Get-AzAccessToken -TenantId $azContext.Subscription.TenantId -ErrorAction Stop
            $authHeader = @{
                'Content-Type'  = 'application/json'
                'Authorization' = 'Bearer ' + $token.Token
            }
        }
        catch {
            [void]$ErrorList.Add("Failed to get access token for $subName ($subId): $_")
            $authHeader = $null
        }

        # -------------------------
        # A) CWP Coverage check (ARG counts + ARM pricing)
        # -------------------------
        $coverageOk = $true
        $coverageComment = $null

        if (-not $authHeader) {
            $coverageOk = $false
            $coverageComment = "Unable to evaluate CWP coverage (missing auth token)."
        }
        else {
            $pricingByPlan = Get-DefenderPricingBySubscription -SubscriptionId $subId -AuthHeader $authHeader -ErrorList $ErrorList
            $cov = Get-CwpCoverageForSubscription -SubscriptionId $subId -CountsBySub $countsBySub -TypeToPlanMap $TypeToPlanMap -PricingByPlan $pricingByPlan -msgTable $msgTable
            $coverageOk = [bool]$cov.coverageOk
            $coverageComment = $cov.comment
        }

        # -------------------------
        # B) Notifications / securityContacts check (ARM)
        # -------------------------
        $notifOk = $true
        $notifComment = $null

        if (-not $authHeader) {
            $notifOk = $false
            $notifComment = $msgTable.errorRetrievingNotifications
        }
        else {
            $restUri = "https://management.azure.com/subscriptions/$subId/providers/Microsoft.Security/securityContacts/default?api-version=2023-12-01-preview"
            try {
                $response = Invoke-RestMethod -Uri $restUri -Method Get -Headers $authHeader -ErrorAction Stop
                $r = Get-DFCAcheckComplianceStatus -apiResponse $response -msgTable $msgTable -SubscriptionName $subName
                $notifOk = [bool]$r.isCompliant
                $notifComment = $r.Comments
            }
            catch {
                $restUri2 = "https://management.azure.com/subscriptions/$subId/providers/Microsoft.Security/securityContacts?api-version=2023-12-01-preview"
                try {
                    $response2 = Invoke-RestMethod -Uri $restUri2 -Method Get -Headers $authHeader -ErrorAction Stop
                    if (-not $response2.value -or $response2.value.Count -eq 0) {
                        $notifOk = $false
                        $notifComment = $msgTable.DefenderNonCompliant
                    }
                    else {
                        
                        $notifOk = $false
                        $notifComment = $msgTable.DefenderNonCompliant
                    }
                }
                catch {
                    $notifOk = $false
                    $notifComment = $msgTable.errorRetrievingNotifications
                    [void]$ErrorList.Add("Error invoking securityContacts for $subName ($subId): $_")
                }
            }
        }

        # -------------------------
        # Final compliance (both must pass)
        # -------------------------
        $isCompliant = ($coverageOk -and $notifOk)

        $commentsList = New-Object System.Collections.Generic.List[string]
        if (-not $coverageOk -and $coverageComment) { $commentsList.Add($coverageComment) | Out-Null }
        if (-not $notifOk -and $notifComment) { $commentsList.Add($notifComment) | Out-Null }

        if ($isCompliant) {
            $commentsList.Add($msgTable.DefenderCompliant) | Out-Null
        }
        elseif ($commentsList.Count -eq 0) {
            $commentsList.Add($msgTable.DefenderNonCompliant) | Out-Null
        }

        $Comments = ($commentsList | Where-Object { $_ } | Select-Object -Unique) -join " | "

        $C = [PSCustomObject]@{
            SubscriptionName = $subName
            ComplianceStatus = $isCompliant
            ControlName      = $ControlName
            Comments         = $Comments
            ItemName         = $ItemName
            ReportTime       = $ReportTime
            itsgcode         = $itsgcode
        }

        if ($EnableMultiCloudProfiles) {
            $result = Add-ProfileInformation -Result $C -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subId -ErrorList $ErrorList
            [void]$PsObject.Add($result)
        } else {
            [void]$PsObject.Add($C)
        }

        Write-Verbose "Completed compliance output for subscription: $subName"
    }

    return [PSCustomObject]@{
        ComplianceResults = $PsObject
        Errors            = $ErrorList
    }
}
