
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
    $lawParts = $LAWResourceId -split '/'
    $subscriptionId = $lawParts[2]
    $resourceGroupName = $lawParts[4]
    $lawName = $lawParts[-1]

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

        # Check if Read-only lock is in place
        $lock = Get-AzResourceLock -ResourceGroupName $resourceGroupName -ResourceName $lawName -ResourceType "Microsoft.OperationalInsights/workspaces"
        if (-not $lock -or $lock.Properties.level -ne "ReadOnly") {
            $IsCompliant = $false
            $Comments += $msgTable.readOnlyLaw -f $lawName
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

    # Conditionally add the Profile field based on the feature flag
    if ($EnableMultiCloudProfiles) {
        $evalResult = Get-EvaluationProfile -SubscriptionId $subscriptionId -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        if (!$evalResult.ShouldEvaluate) {
            if(!$evalResult.ShouldAvailable ){
                if ($evalResult.Profile -gt 0) {
                    $PsObject.ComplianceStatus = "Not Available"
                    $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                    $PsObject.Comments = "Not available - Profile $($evalResult.Profile) not applicable for this guardrail"
                } else {
                    $ErrorList.Add("Error occurred while evaluating profile configuration availability")
                }
            } else {
                if ($evalResult.Profile -gt 0) {
                    $PsObject.ComplianceStatus = "Not Applicable"
                    $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                    $PsObject.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
                } else {
                    $ErrorList.Add("Error occurred while evaluating profile configuration")
                }
            }
        } else {
            
            $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
        }
    }

    $moduleOutput = [PSCustomObject]@{
        ComplianceResults = $PsObject
        Errors = $ErrorList
    }

    return $moduleOutput
}
