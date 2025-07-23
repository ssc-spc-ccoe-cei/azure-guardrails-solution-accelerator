function Find-ReceiverValues{
    param (
        [Object[]] $actionGroups
    )

    # Write-Host "All action groups are in the unique SignIn/Audit list."
    $allReceiversWithValues = @()
    # Iterate through each action group
    foreach ($actionGroup in $actionGroups) {
        # Filter the properties to find the receivers with values
        $receiversWithValues = $actionGroup.PSObject.properties | Where-Object {
            $_.Name -like "*Receiver*" -and $_.MemberType -eq 'Property' -and $null -ne $_.Value -and $_.Value.Count -gt 0
        }
        $allReceiversWithValues += [PSCustomObject]@{
            ActionGroupName = $actionGroup.Name
            Receivers = $receiversWithValues
        }
    }
    
    return  $allReceiversWithValues
}

function CompareKQLQueryToPattern{
    param (
        [string] $pattern,
        [string] $targetQuery
    )

    #Fix the formatting of KQL query
    $normalizedTargetQuery = $targetQuery -replace '\|', ' | ' -replace '\s+', ' '

    return $normalizedTargetQuery -imatch $pattern
}

function Check-AlertsMonitor {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$LAWResourceId,
        [Parameter(Mandatory=$true)]
        [string]$FirstBreakGlassUPN,
        [Parameter(Mandatory=$true)]
        [string]$SecondBreakGlassUPN,
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
        $EnableMultiCloudProfiles # default to false
    )

    $IsCompliant = $false
    $signInLogsCompliance = $false
    $auditLogsCompliance = $false
    $Comments = ""
    $ErrorList = @()

    #Queries that will be used in alert rules
    $BreakGlassAccountQueries = @(
        "SigninLogs \| Where.*UserPrincipalName (?:==|=~|contains) `"($FirstBreakGlassUPN|$SecondBreakGlassUPN)`" or UserPrincipalName (?:==|=~|contains) `"(?!\1)($FirstBreakGlassUPN|$SecondBreakGlassUPN)`".*",
        "SigninLogs \| Where.*UserPrincipalName (?:in|has_any) \(`"($FirstBreakGlassUPN|$SecondBreakGlassUPN)`", `"(?!\1)($FirstBreakGlassUPN|$SecondBreakGlassUPN)`"\).*"
    )
    $BreakGlassAccountQueryMatchPattern = "`($($BreakGlassAccountQueries -join '|')`)"

    $AuditLogsQueries = @(
        "AuditLogs | Where.*(?:OperationName|ActivityDisplayName) in \(`"(Update|Add|Delete) conditional access policy`", `"(!\1)(Update|Add|Delete) conditional access policy`", `"(!\2)(Update|Add|Delete) conditional access policy`"\)"
    )
    $CAPQueryMatchPattern = "`($($AuditLogsQueries -join '|')`)"

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
        #Type of logs to check
        $SignInLogs = @('SignInLogs')
        $AuditLogs = @('AuditLogs')

        #Retrieve diagnostic settings to check for logs
        $diagnosticSettings = get-AADDiagnosticSettings
        $matchingSetting = $diagnosticSettings | Where-Object { $_.properties.workspaceId -eq $LAWResourceId } | Select-Object -First 1

        if($matchingSetting){
            $enabledLogs = $matchingSetting.properties.logs | Where-Object { $_.enabled -eq $true } | Select-Object -ExpandProperty category
            $missingSignInLogs = $SignInLogs | Where-Object { $_ -notin $enabledLogs }
            $missingAuditLogs = $AuditLogs | Where-Object { $_ -notin $enabledLogs }
        }
        else{
            $missingSignInLogs = $SignInLogs
            $missingAuditLogs = $AuditLogs
        }

        # Check missing logs for SignInLogs and AuditLogs
        if ($missingSignInLogs.Count -gt 0) {
            $Comments += $msgTable.signInlogsNotCollected + " Missing logs: $($missingSignInLogs -join ', ')"
        }

        if ($missingAuditLogs.Count -gt 0) {
            $Comments += $msgTable.auditlogsNotCollected + " Missing logs: $($missingAuditLogs -join ', ')"
        }
    }
    catch {
        if ($_.Exception.Message -like "*ResourceNotFound*") {
            $Comments += $msgTable.nonCompliantLaw -f $lawName
            $ErrorList += "Log Analytics Workspace not found: $_"
        }
        else {
            $ErrorList += "Error accessing Log Analytics Workspace: $_"
        }
    }

    # Check signInLogs and auditLogs alerts and action groups for breakglass accounts

    # Check alert rules exist
    try{
        $alertRules = Get-AzScheduledQueryRule -ResourceGroupName $resourceGroupName
    }   
    catch {
        $Comments += $msgTable.noAlertRules -f $resourceGroupName
        $ErrorList += "Get-AzScheduledQueryRule could not find alert rules for the resource group: $_"
    }
    if ($alertRules.Count -le 0) {
        $Comments += $msgTable.noAlertRules -f $resourceGroupName
    }

    # Check action groups exist.  Only keep action groups with configured receivers
    try {
        $actionGroups = Get-AzActionGroup -ResourceGroupName $resourceGroupName
        $receiversWithValues = Find-ReceiverValues $actionGroups
        $actionGroupsWithReceivers = $actionGroups | Where-Object { $_.Name -in $receiversWithValues.ActionGroupName }
        $actionGroupIds = $actionGroupsWithReceivers.Id | ForEach-Object{ $_.ToLower() }
    }
    catch {
        $Comments += $msgTable.noActionGroups -f $resourceGroupName
        $ErrorList += "Get-AzActionGroup could not find action groups for the resource group : $_"
    }
    if ($actionGroups.Count -le 0) {
        $Comments += $msgTable.noActionGroups -f $resourceGroupName
    }

    if ($alertRules.Count -gt 0 -and $actionGroups.Count -gt 0) {
        # check break glass compliance
        $signInLogsCompliance = $false
        # Select alert rules with a query that matches the pattern for break glass accounts
        $bgAlertRules = $alertRules | Where-Object {
            $_.CriterionAllOf -and
            $_.CriterionAllOf.Count -gt 0 -and
            (CompareKQLQueryToPattern -pattern $BreakGlassAccountQueryMatchPattern -targetQuery $_.CriterionAllOf.Query)
        }
        if ($bgAlertRules.Count -le 0) {
            $Comments += $msgTable.noAlertRuleforBGaccts
        }
        # Select the action groups of the BG alert rules if they are also in the list of action groups with receivers
        $bgActionGroupIds = ($bgAlertRules.ActionGroup).ToLower() | Where-Object { $_ -in $actionGroupIds }
        if ($bgActionGroupIds.Count -gt 0) {
            $signInLogsCompliance = $true # we found alert rules with a query that matches the BG query pattern and with action groups with configured receivers
        }
        else {
            $Comments += $msgTable.noActionGroupsForBGaccts
        }

        # check conditional access policy compliance
        $auditLogsCompliance = $false
        # Select alert rules with a query that matches the pattern for conditional access policies
        $capAlertRules = $alertRules | Where-Object {
            $_.CriterionAllOf -and
            $_.CriterionAllOf.Count -gt 0 -and
            (CompareKQLQueryToPattern -pattern $CAPQueryMatchPattern -targetQuery $_.CriterionAllOf.Query)
        }
        if ($capAlertRules.Count -le 0) {
            $Comments += $msgTable.noAlertRuleforCaps
        }
        # Select the action groups of the CAP alert rules if they are also in the list of action groups with receivers
        $capActionGroupIds = ($capAlertRules.ActionGroup).ToLower() | Where-Object { $_ -in $actionGroupIds }
        if ($capActionGroupIds.Count -gt 0) {
            $auditLogsCompliance = $true # we found alert rules with a query that matches the CAP query pattern and with action groups with configured receivers
        }
        else {
            $Comments += $msgTable.noActionGroupsForAuditLogs
        }
    }

    # CONDITION: If both checks are compliant then set the control as compliant
    if($signInLogsCompliance -and $auditLogsCompliance){
        $IsCompliant = $true
    }

    if($IsCompliant){
        $Comments = $msgTable.compliantAlerts
    }else{
        $Comments = $msgTable.isNotCompliant + ' ' + $Comments
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
        $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        if (!$evalResult.ShouldEvaluate) {
            if ($evalResult.Profile -gt 0) {
                $PsObject.ComplianceStatus = "Not Applicable"
                $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                $PsObject.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
            } else {
                $ErrorList.Add("Error occurred while evaluating profile configuration")
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