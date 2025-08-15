
    #------------------- Helper functions -------------------
    
    # Parse LAW Resource ID
function Get-ResourceIdInfo {
    param([string]$Id)
    $parts = $Id -split '/'
    [PSCustomObject]@{
        SubscriptionId    = $parts[2]
        ResourceGroupName = $parts[4]
        Name              = $parts[-1]
    }
}

function Test-SentinelTables {
    <#
        Checks if ANY Sentinel-only table exists by attempting a zero-row query per table.
        This works even when the table has no data: if table exists, the query compiles.
        If it doesn't exist, the API returns a semantic error which we catch.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Workspace  # object from Get-AzOperationalInsightsWorkspace
    )

    $sentinelTables = @(
        'SecurityIncident',
        'HuntingBookmark',
        'SentinelHealth'
    )

    $found   = New-Object System.Collections.Generic.List[string]
    $errors  = New-Object System.Collections.Generic.List[string]

    foreach ($t in $sentinelTables) {
        try {
            # Compiles if table exists (even with 0 rows). Fails with "does not exist" otherwise.
            $q = "$t | take 0"
            $null = Invoke-AzOperationalInsightsQuery -WorkspaceId $Workspace.CustomerId -Query $q -ErrorAction Stop
            $found.Add($t)
        } catch {
            # If this is a "does not exist" semantic error, ignore; else keep a note
            $msg = $_.Exception.Message
            if ($msg -notmatch "does not exist") {
                $errors.Add("$($t): $msg")
            }
        }
    }

    [PSCustomObject]@{
        HasAny  = ($found.Count -gt 0)
        Found   = $found
        Checked = $sentinelTables
        Errors  = $errors
    }
}  

function Check-UserAccountGCEventLogging {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$LAWResourceId,
        [Parameter(Mandatory=$true)]
        [int]$RequiredRetentionDays,
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
        [string] 
        $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] 
        $EnableMultiCloudProfiles # New feature flag, default to false
    )

    $IsCompliant = $true
    $Comments = ""
    $ErrorList = @()  


    # Parse LAW Resource ID
    $lawInfo = Get-ResourceIdInfo -Id $LAWResourceId
    $subscriptionId    = $lawInfo.SubscriptionId
    $resourceGroupName = $lawInfo.ResourceGroupName
    $lawName           = $lawInfo.Name

    try{
        Select-AzSubscription -Subscription $subscriptionId -ErrorAction Stop | Out-Null
    }
    catch {
        $ErrorList.Add("Failed to execute the 'Select-AzSubscription' command with subscription ID '$($subscription)'--`
            ensure you have permissions to the subscription, the ID is correct, and that it exists in this tenant; returned `
            error message: $_")
        #    ensure you have permissions to the subscription, the ID is correct, and that it exists in this tenant; returned `
        #    error message: $_"
        throw "Error: Failed to execute the 'Select-AzSubscription' command with subscription ID '$($subscription)'--ensure `
            you have permissions to the subscription, the ID is correct, and that it exists in this tenant; returned error message: $_"
    }


    try {
        # Get the Log Analytics Workspace
        $law = Get-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -Name $lawName -ErrorAction Stop

        # Check retention period
        if ($law.RetentionInDays -lt $RequiredRetentionDays) {
            $IsCompliant = $false
            $Comments += $msgTable.retentionNotMet -f $lawName
        }

        # # Check if required logs are enabled
        # 'AuditLogs', 'SignInLogs', 'NonInteractiveUserSignInLogs', 'ServicePrincipalSignInLogs', 'ManagedIdentitySignInLogs', 'ProvisioningLogs', 
        # 'ADFSSignInLogs', 'RiskyUsers','UserRiskEvents', 'NetworkAccessTrafficLogs', 'RiskyServicePrincipals',
        # 'ServicePrincipalRiskEvents', 'EnrichedOffice365AuditLogs', 'MicrosoftGraphActivityLogs','RemoteNetworkHealthLogs'
        $requiredLogs = @(
            'AuditLogs', 'SignInLogs', 'ManagedIdentitySignInLogs', 'RiskyUsers', 'MicrosoftGraphActivityLogs'
        )
        $diagnosticSettings = get-AADDiagnosticSettings

        $missingLogs = @()
        $matchingSetting = $diagnosticSettings | Where-Object { $_.properties.workspaceId -eq $LAWResourceId } | Select-Object -First 1

        if ($matchingSetting) {
            $enabledLogs = $matchingSetting.properties.logs | Where-Object { $_.enabled -eq $true } | Select-Object -ExpandProperty category
            $missingLogs = $requiredLogs | Where-Object { $_ -notin $enabledLogs }
        } else {
            $missingLogs = $requiredLogs
        }

        if ($missingLogs.Count -gt 0) {
            $IsCompliant = $false
            $Comments += $msgTable.logsNotCollected + " Missing logs: $($missingLogs -join ', ')"
        }

        # Step 1 : Check if the Log Analytics Workspace has a read-only lock or delete-only lock
        $lock = Get-AzResourceLock -ResourceGroupName $resourceGroupName -ResourceName $lawName -ResourceType "Microsoft.OperationalInsights/workspaces" -ErrorAction SilentlyContinue
        $hasApprovedLock = $false
        if ($lock) {
            $lvl = $lock.Properties.level
            if ($lvl -eq 'ReadOnly' -or $lvl -eq 'CanNotDelete') {
                $hasApprovedLock = $true
                $Comments += $msgTable.lockLevelApproved -f $lawName, $lvl
            } else {
                $Comments += $msgTable.lockLevelNotApproved -f $lawName, $lvl
            }
        }

        if (-not $hasApprovedLock) {
            # 2) No lock -> check tag
            $tagSentinelTrue = $false
            if ($law.Tags -and $law.Tags.ContainsKey("sentinel")) {
                $tagSentinelTrue = ($law.Tags["sentinel"].ToString().ToLower() -eq "true") #Check if tag sentinel=true exists
            }
            if ($tagSentinelTrue) {
                # Pass due to tag
                $Comments += $msgTable.tagSentinelTrue -f $lawName
            } else {
                # 3) No tag -> check Sentinel tables
                $tbl = Test-SentinelTables -Workspace $law
                if ($tbl.HasAny) {
                    # Pass and call it a mistag
                    $Comments += $msgTable.sentinelTablesFound -f $lawName
                } else {
                    # 4) Fail: no lock, no tag, no tables
                    $IsCompliant = $false
                    $Comments += $msgTable.noLockNoTagNoTables -f $lawName
                }
                if ($tbl.Errors.Count -gt 0) {
                    $Comments += "Table-check notes: $($tbl.Errors -join ' | '). "
                }
            }
        }
    }
    catch {
        if ($_.Exception.Message -like "*ResourceNotFound*") {
            $IsCompliant = $false
            $Comments += $msgTable.nonCompliantLaw -f $lawName
            $ErrorList += "Log Analytics Workspace not found: $_"
        }
        else {
            $IsCompliant = $false
            $ErrorList += "Error accessing Log Analytics Workspace: $_"
        }
    }

    if ($IsCompliant) {
        $Comments = $msgTable.gcEventLoggingCompliantComment
    }

    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName = $ControlName
        Comments = $Comments
        ItemName = $ItemName
        ReportTime = $ReportTime
        itsgcode = $itsgcode
    }

    # Add profile information if MCUP feature is enabled
    if ($EnableMultiCloudProfiles) {
        $result = Add-ProfileInformation -Result $PsObject -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId -ErrorList $ErrorList
        Write-Host "$result"
    }

    $moduleOutput = [PSCustomObject]@{
        ComplianceResults = $PsObject
        Errors = $ErrorList
    }

    return $moduleOutput
}
