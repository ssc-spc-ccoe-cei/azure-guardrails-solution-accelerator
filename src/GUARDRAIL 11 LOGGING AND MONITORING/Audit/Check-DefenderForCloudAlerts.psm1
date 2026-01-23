
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
        Write-Host "Failed to get Defender pricings for subscription ${SubscriptionId}: $_"
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
        [Parameter (Mandatory)]
        [string] $subscriptionId,
        [Parameter(Mandatory)]
        [string] $SubscriptionName
    )

    $isCompliant = $true
    $Comments = ""

    $notificationSources = $apiResponse.properties.notificationsSources
    $notificationEmails  = $apiResponse.properties.emails
    $ownerRoles          = $apiResponse.properties.notificationsByRole.roles
    $ownerState          = $apiResponse.properties.notificationsByRole.state

    # Filter to get required notification types
    $alertNotification = $notificationSources | Where-Object { $_.sourceType -eq "Alert" -and $_.minimalSeverity -in @("Medium","Low") }
    $attackPathNotification = $notificationSources | Where-Object { $_.sourceType -eq "AttackPath" -and $_.minimalRiskLevel -in @("Medium","Low") }

    $emailCount = 0
    if ($notificationEmails) { $emailCount = ($notificationEmails -split ";").Count }

    $ownerConfigured = ($ownerState -eq "On") -and ($ownerRoles -contains "Owner")

    $ownerContactCount = 0
    if($ownerConfigured){
        #get the actual number of subscription owners
        try{
            $subsOwners = Get-AzRoleAssignment -RoleDefinitionName "Owner" -Scope "/subscriptions/$subscriptionId" -ErrorAction Stop
            if($null -ne $subsOwners ){
                $subsOwnerCount = $subsOwners.Count

                if ($subsOwnerCount -lt 1){
                    # No owners found, treat as not properly configured
                    $ownerConfigured = $false
                }
                # If only 1 subscription owner, counts as 1 contact; if more than 1 owner, counts as 2 contacts
                if ($subsOwnerCount -eq 1) {
                    $ownerContactCount = 1
                    Write-Verbose "Subscription has 1 owner, counting as 1 contact"
                }
                elseif ($subsOwnerCount -gt 1) {
                    $ownerContactCount = 2
                    Write-Verbose "Subscription has $ownerCount owners, counting as 2 contacts"
                }

            }
        }
        catch{
            Write-Verbose "Failed to get owner count for subscription $subscriptionName : $_"
            # If we can't get owner count, treat as if owner notification is not properly configured
            $ownerContactCount = 0
            # No owners found, treat as not properly configured
            $ownerConfigured = $false
        }
    }

    if($ownerContactCount -eq 2){
        Write-Verbose "Owner notification is properly configured with multiple owners for subscription $subscriptionName"
        $isCompliant = $true
    }
    else{
        # Calculate total contact count (emails + owner contact equivalent)
        $totalContactCount = $emailCount + $ownerContactCount

         # CONDITION: Check if there are at least 2 contacts total
        if ($totalContactCount -lt 2) {
            $isCompliant = $false
            $Comments = $msgTable.EmailsOrOwnerNotConfigured -f $SubscriptionName
        }

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
        # A) Subscription: Defender for Cloud coverage check
        # -------------------------
        $subRegisteredOk = $true
        $subRegisteredComment = $null
        $defenderPlansStandard = @()
        if (-not $authHeader) {
            $subRegisteredOk = $false
            $subRegisteredComment = "Unable to evaluate Defender for Cloud registration (missing auth token)."
        }
        else{  
            # Check if any Defender for Cloud Standard plan is enabled/registered for the subscription
            Write-Verbose "Checking Defender for Cloud registration for subscription: $subName ($subId)"

            $regUri = "https://management.azure.com/subscriptions/$subId/providers/Microsoft.Security?api-version=2020-01-01"
            try{
                $response = Invoke-RestMethod -Uri $regUri -Method Get -Headers $authHeader -ErrorAction Stop
                
                $subRegisteredOk = if($response.registrationState -eq "Registered"){ $true } else { $false }
                if($subRegisteredOk){
                    # Further check if any Standard plan is enabled
                    $defenderPlans = Get-AzSecurityPricing
                    $defenderPlansStandard = $defenderPlans | Where-Object {$_.PricingTier -eq 'Standard'}
                    if ($defenderPlansStandard.Count -eq 0 -or $null -eq $defenderPlansStandard) {
                        $subRegisteredOk = $false
                    }
                    else{
                        $subRegisteredOk = $true
                    }
                }
                else{
                    $subRegisteredOk = $false
                    
                }
            }
            catch{
                $subRegisteredOk = $false
                
            }

        }

        
        
        # If not registered, output non-compliant result and continue to next subscription
        if(-not $subRegisteredOk){
            Write-Host "Defender for Cloud (Microsoft.Security) is not registered for subscription $subName ($subId)."
            $C = [PSCustomObject]@{
                SubscriptionName = $subName
                ComplianceStatus = $false
                ControlName      = $ControlName
                Comments         = $msgTable.NotAllSubsHaveDefenderPlans
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
            continue
        }
        else{
            Write-Host "Defender for Cloud (Microsoft.Security) is registered and has Standard plans for subscription $subName ($subId)."
            # -------------------------
            # B) CWP Coverage check (ARG counts + ARM pricing)
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
            # C) Notifications / securityContacts check (ARM)
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
                    $r = Get-DFCAcheckComplianceStatus -apiResponse $response -msgTable $msgTable -subscriptionId $subId -SubscriptionName $subName
                    $notifOk = [bool]$r.isCompliant
                    $notifComment = $r.Comments
                }
                catch {
                    $restUri2 = "https://management.azure.com/subscriptions/$subId/providers/Microsoft.Security/securityContacts?api-version=2023-12-01-preview"
                    try {
                        $response2 = Invoke-RestMethod -Uri $restUri2 -Method Get -Headers $authHeader -ErrorAction Stop
                        if (-not $response2.value -or $response2.value.Count -eq 0) {
                            $notifOk = $false
                            $notifComment = $msgTable.DefenderEnabledNonCompliant
                            Write-Verbose "Notification alert default security contact is not configured properly for $($subName)"
                        }
                        else {
                            # Keeping else condition open to formally identify this probable use case
                            Write-Verbose "Identify use case requirement"
                            $notifOk = $false
                            $notifComment = $msgTable.DefenderEnabledNonCompliant
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
            $isCompliant = ($coverageOk -and $notifOk )

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
        
    }

    return [PSCustomObject]@{
        ComplianceResults = $PsObject
        Errors            = $ErrorList
    }
}
