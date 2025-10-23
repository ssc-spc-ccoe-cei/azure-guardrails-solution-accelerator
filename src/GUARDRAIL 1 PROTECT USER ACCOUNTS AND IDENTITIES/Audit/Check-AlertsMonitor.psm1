function Find-ReceiverValues{
    param (
        [Object[]] $actionGroups
    )

    if ($null -eq $actionGroups -or $actionGroups.Count -eq 0) {
        Write-Error "No action groups provided to Find-ReceiverValues"
        return @()
    }

    $allReceiversWithValues = @()
    
    # Iterate through each action group
    foreach ($actionGroup in $actionGroups) {
        if ($null -eq $actionGroup) {
            Write-Verbose "Skipping null action group"
            continue
        }
        
        try {
            # Filter the properties to find the receivers with values
            $receiversWithValues = $actionGroup.PSObject.properties | Where-Object {
                $_.Name -like "*Receiver*" -and 
                $_.MemberType -eq 'Property' -and 
                $null -ne $_.Value -and 
                $_.Value.Count -gt 0
            }
            
            if ($receiversWithValues.Count -gt 0) {
                $allReceiversWithValues += [PSCustomObject]@{
                    ActionGroupName = $actionGroup.Name
                    Receivers = $receiversWithValues
                    ReceiverCount = $receiversWithValues.Count
                }
                Write-Verbose "Found $($receiversWithValues.Count) receivers in action group: $($actionGroup.Name)"
            }
            else {
                Write-Verbose "No configured receivers found in action group: $($actionGroup.Name)"
            }
        }
        catch {
            Write-Error "Error processing action group $($actionGroup.Name): $_"
        }
    }
    
    Write-Verbose "Total action groups with receivers: $($allReceiversWithValues.Count)"
    return $allReceiversWithValues
}

function CompareKQLQueryToPattern{
    param (
        [string] $pattern,
        [string] $targetQuery
    )

    if ([string]::IsNullOrWhiteSpace($pattern)) {
        Write-Warning "Pattern is null or empty"
        return $false
    }
    
    if ([string]::IsNullOrWhiteSpace($targetQuery)) {
        Write-Warning "Target query is null or empty"
        return $false
    }

    try {        
        $isMatch = $targetQuery -imatch $pattern
        
        Write-Verbose "Pattern matching: '$pattern' against '$normalizedTargetQuery' = $isMatch"
        
        return $isMatch
    }
    catch {
        Write-Error "Error in pattern matching: $_"
        return $false
    }
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
    # Escape UPNs to prevent regex injection
    $escapedFirstUPN = [regex]::Escape($FirstBreakGlassUPN)
    $escapedSecondUPN = [regex]::Escape($SecondBreakGlassUPN)
    
    $BreakGlassAccountQueries = @(
        # Pattern 1: Explicit OR conditions – only matches if *both* distinct UPNs are present
        "SigninLogs\s*\|\s*where.*UserPrincipalName\s*(?:==|=~|contains)\s+`"$escapedFirstUPN`"\s+or\s+UserPrincipalName\s*(?:==|=~|contains)\s+`"$escapedSecondUPN`".*"
        ,
        "SigninLogs\s*\|\s*where.*UserPrincipalName\s*(?:==|=~|contains)\s+`"$escapedSecondUPN`"\s+or\s+UserPrincipalName\s*(?:==|=~|contains)\s+`"$escapedFirstUPN`".*"
        ,
        # Pattern 2: IN/HAS_ANY clause – both UPNs must appear inside the list (order doesn’t matter)
        "SigninLogs\s*\|\s*where.*UserPrincipalName\s*(?:in|has_any)\s*\((?=[^)]*`"$escapedFirstUPN`")(?=[^)]*`"$escapedSecondUPN`")[^)]*\)"
    )
    $BreakGlassAccountQueryMatchPattern = "`($($BreakGlassAccountQueries -join '|')`)"

    $AuditLogsQueries = @(
        # 1) Single-value form (==, =~, contains) — flexible spaces
        'AuditLogs\s*\|\s*where\s+(?:OperationName|ActivityDisplayName)\s+(?:==|=~|contains)\s+"(?:Update|Add|Delete)\s+conditional access policy"\s*',

        # 2) in()/has_any() list form — order-agnostic, requires ALL THREE present somewhere in (...)
        (
            'AuditLogs\s*\|\s*where\s+(?:OperationName|ActivityDisplayName)\s+(?:in|has_any)\s*\(' +
            '(?=[^)]*"Update\s+conditional access policy")' +
            '(?=[^)]*"Add\s+conditional access policy")' +
            '(?=[^)]*"Delete\s+conditional access policy")' +
            '[^)]*\)'
        )
    )
    $CAPQueryMatchPattern = "`($($AuditLogsQueries -join '|')`)"

    # Parse LAW Resource ID
    $lawParts = $LAWResourceId -split '/'
    
    $subscriptionId = $lawParts[2]
    $resourceGroupName = $lawParts[4]
    $lawName = $lawParts[-1]
    
    Write-Verbose "Parsed LAW Resource ID: Subscription=$subscriptionId, ResourceGroup=$resourceGroupName, Workspace=$lawName"

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
        if ($alertRules.Count -le 0) {
            $Comments += $msgTable.noAlertRules -f $resourceGroupName
            $ErrorList += "No alert rules found in resource group: $resourceGroupName"
            Write-Error "No alert rules found in resource group: $resourceGroupName"
        }
        else {
            Write-Verbose "Found $($alertRules.Count) alert rules in resource group: $resourceGroupName"
        }
    }   
    catch {
        $Comments += $msgTable.noAlertRules -f $resourceGroupName
        $ErrorList += "Get-AzScheduledQueryRule could not find alert rules for the resource group: $_"
        Write-Error "Error retrieving alert rules: $_"
    }

    # Check action groups exist.  Only keep action groups with configured receivers
    try {
        $actionGroups = Get-AzActionGroup -ResourceGroupName $resourceGroupName
        if ($actionGroups.Count -le 0) {
            $Comments += $msgTable.noActionGroups -f $resourceGroupName
            $ErrorList += "No action groups found in resource group: $resourceGroupName"
        }
        else {
            $receiversWithValues = Find-ReceiverValues $actionGroups
            $actionGroupsWithReceivers = $actionGroups | Where-Object { $_.Name -in $receiversWithValues.ActionGroupName }
            $actionGroupIds = $actionGroupsWithReceivers.Id | ForEach-Object{ $_.ToLower() }
            
            if ($actionGroupsWithReceivers.Count -le 0) {
                $Comments += $msgTable.noActionGroupsForBGaccts
                $ErrorList += "No action groups with configured receivers found in resource group: $resourceGroupName"
            }
        }
    }
    catch {
        $Comments += $msgTable.noActionGroups -f $resourceGroupName
        $ErrorList += "Get-AzActionGroup could not find action groups for the resource group: $_"
        Write-Error "Error retrieving action groups: $_"
    }

    if ($alertRules.Count -gt 0 -and $actionGroups.Count -gt 0) {
        # check break glass compliance
        $signInLogsCompliance = $false
        
        try {
            # Select alert rules with a query that matches the pattern for break glass accounts
            $bgAlertRules = $alertRules | Where-Object {
                $_.CriterionAllOf -and
                $_.CriterionAllOf.Count -gt 0 -and
                (CompareKQLQueryToPattern -pattern $BreakGlassAccountQueryMatchPattern -targetQuery $_.CriterionAllOf.Query)
            }
            
            Write-Verbose "Found $($bgAlertRules.Count) alert rules matching break glass account patterns"
            
            if ($bgAlertRules.Count -le 0) {
                $Comments += $msgTable.noAlertRuleforBGaccts
                Write-Verbose "No alert rules found matching break glass account patterns"
            }
            else {
                # Normalize the action group IDs for BG alerts (guarding against null/empty values) so missing groups trigger the right comment
                $bgActionGroupIds = foreach ($rule in $bgAlertRules) {
                    foreach ($actionGroupId in @($rule.ActionGroup)) {
                        if ([string]::IsNullOrWhiteSpace($actionGroupId)) { continue }
                        $actionGroupId.ToLower()
                    }
                }
                $bgActionGroupIds = $bgActionGroupIds | Where-Object { $_ -in $actionGroupIds }
                
                Write-Verbose "Found $($bgActionGroupIds.Count) action groups with receivers for break glass alert rules"
                
                if ($bgActionGroupIds.Count -gt 0) {
                    $signInLogsCompliance = $true # we found alert rules with a query that matches the BG query pattern and with action groups with configured receivers
                    Write-Verbose "Break glass compliance: TRUE - Found alert rules with proper action groups"
                }
                else {
                    $Comments += $msgTable.noActionGroupsForBGaccts
                    Write-Verbose "Break glass compliance: FALSE - No action groups with receivers found"
                }
            }
        }
        catch {
            $ErrorList += "Error processing break glass alert rules: $_"
            Write-Error "Error processing break glass alert rules: $_"
        }

        # check conditional access policy compliance
        $auditLogsCompliance = $false
        
        try {
            # Select alert rules with a query that matches the pattern for conditional access policies
            $capAlertRules = $alertRules | Where-Object {
                $_.CriterionAllOf -and
                $_.CriterionAllOf.Count -gt 0 -and
                (CompareKQLQueryToPattern -pattern $CAPQueryMatchPattern -targetQuery $_.CriterionAllOf.Query)
            }
            
            Write-Verbose "Found $($capAlertRules.Count) alert rules matching conditional access policy patterns"
            
            if ($capAlertRules.Count -le 0) {
                $Comments += $msgTable.noAlertRuleforCaps
                Write-Verbose "No alert rules found matching conditional access policy patterns"
            }
            else {
                # Apply the same normalization for CAP alerts so missing action groups surface the expected comment
                $capActionGroupIds = foreach ($rule in $capAlertRules) {
                    foreach ($actionGroupId in @($rule.ActionGroup)) {
                        if ([string]::IsNullOrWhiteSpace($actionGroupId)) { continue }
                        $actionGroupId.ToLower()
                    }
                }
                $capActionGroupIds = $capActionGroupIds | Where-Object { $_ -in $actionGroupIds }
                
                Write-Verbose "Found $($capActionGroupIds.Count) action groups with receivers for conditional access policy alert rules"
                
                if ($capActionGroupIds.Count -gt 0) {
                    $auditLogsCompliance = $true # we found alert rules with a query that matches the CAP query pattern and with action groups with configured receivers
                    Write-Verbose "Conditional access policy compliance: TRUE - Found alert rules with proper action groups"
                }
                else {
                    $Comments += $msgTable.noActionGroupsForAuditLogs
                    Write-Verbose "Conditional access policy compliance: FALSE - No action groups with receivers found"
                }
            }
        }
        catch {
            $ErrorList += "Error processing conditional access policy alert rules: $_"
            Write-Error "Error processing conditional access policy alert rules: $_"
        }
    }

    # CONDITION: If both checks are compliant then set the control as compliant
    if($signInLogsCompliance -and $auditLogsCompliance){
        $IsCompliant = $true
    }

    Write-Verbose "=== Compliance Summary ==="
    Write-Verbose "Sign-in Logs Compliance: $signInLogsCompliance"
    Write-Verbose "Audit Logs Compliance: $auditLogsCompliance"
    Write-Verbose "Overall Compliance: $IsCompliant"
    Write-Verbose "Error Count: $($ErrorList.Count)"

    if($IsCompliant){
        $Comments = $msgTable.compliantAlerts
        Write-Verbose "Result: COMPLIANT - All alert monitoring requirements met"
    }else{
        $Comments = $msgTable.isNotCompliant + ' ' + $Comments
        Write-Verbose "Result: NON-COMPLIANT - Alert monitoring requirements not met"
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
        Write-Host "Compliance Output: $result"
    }

    $moduleOutput = [PSCustomObject]@{
        ComplianceResults = $PsObject
        Errors = $ErrorList
    }

    return $moduleOutput
}