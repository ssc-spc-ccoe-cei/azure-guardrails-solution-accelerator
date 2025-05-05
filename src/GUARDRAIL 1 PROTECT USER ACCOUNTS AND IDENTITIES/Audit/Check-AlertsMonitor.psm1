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
        "SigninLogs | where UserPrincipalName == `"$($FirstBreakGlassUPN)`" or UserPrincipalName == `"$($SecondBreakGlassUPN)`"",
        "SigninLogs | where UserPrincipalName =~ `"$($FirstBreakGlassUPN)`" or UserPrincipalName =~ `"$($SecondBreakGlassUPN)`"",
        "SigninLogs | where UserPrincipalName == `"$($SecondBreakGlassUPN)`" or UserPrincipalName == `"$($FirstBreakGlassUPN)`"",
        "SigninLogs | where UserPrincipalName =~ `"$($SecondBreakGlassUPN)`" or UserPrincipalName =~ `"$($FirstBreakGlassUPN)`"",
        "SigninLogs | where UserPrincipalName in (`"$($FirstBreakGlassUPN)`",`"$($SecondBreakGlassUPN)`")",
        "SigninLogs | where UserPrincipalName has_any (`"$($FirstBreakGlassUPN)`",`"$($SecondBreakGlassUPN)`")"
    )

    $AuditLogsQueries = @(
        "AuditLogs | where OperationName in (`"Update conditional access policy`", `"Add conditional access policy`", `"Delete conditional access policy`")"
    )

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
            $IsCompliant = $false
            $Comments += $msgTable.signInlogsNotCollected + " Missing logs: $($missingSignInLogs -join ', ')"
        }
        if ($missingAuditLogs.Count -gt 0) {
            $IsCompliant = $false
            $Comments += $msgTable.auditlogsNotCollected + " Missing logs: $($missingSignInLogs -join ', ')"
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

    # Check signInLogs and auditLogs alerts and action groups for breakglass accounts
    # CONDITION: if alert rules present
    try{
        $alertRules = Get-AzScheduledQueryRule -ResourceGroupName $resourceGroupName
    }   
    catch {
        $IsCompliant = $false
        $Comments += $msgTable.noAlertRules -f $resourceGroupName
        $ErrorList += "Could not find alert rules for the resource group: $_"
    }
 
    if ($alertRules.Count -gt 0){

        $actionGroupID = @()
        $targetQuery = @()
        foreach($alertRule in $alertRules){
            # Find action group ID to retrieve action groups
            if ($alertRule.ActionGroup -and $alertRule.ActionGroup.Count -gt 0) { 
                $actionGroupID += $alertRule.ActionGroup 
            }
            # Extract relevant properties of alert rules
            if ($alertRule.CriterionAllOf -and $alertRule.CriterionAllOf.Count -gt 0) { 
                $targetQuery += $alertRule.CriterionAllOf.Query
            }
        }
        $targetQuery =  $targetQuery | ForEach-Object { $_.TrimEnd() }

        # Get unique targetQuery
        $hashTable = @{}
        foreach ($item in $targetQuery) {
            Write-Host $item
            $hashTable[$item] = $true
        }
        $targetQueryUnique = $hashTable.Keys

        # CONDITION: Find Matching Alert rule for BG SignIN and CAP Audit Log
        $stopBGAccLoop = $false
        # Check if the query in alert rule is matching with one of our queries
        foreach ($query in $BreakGlassAccountQueries){
            foreach ($targetqueryU in $targetQueryUnique){
                if($bgAcctQueriesMatching = CompareKQLQueries -query $query -targetQuery $targetqueryU){
                    Write-Host "targetquery: $targetqueryU and bgAcctQueriesMatching: $bgAcctQueriesMatching "
                    $stopBGAccLoop = $true
                    break
                }
            }
            if ($stopBGAccLoop) {break}
        }

        $stopAuditLoop = $false
        #Check if the query in alert rule is matching with one of our AuditLogs queries
        foreach ($auditQuery in $AuditLogsQueries){
            foreach ($targetqueryU in $targetQueryUnique){
                if($auditLogsQueriesMatching = CompareKQLQueries -query $auditQuery -targetQuery $targetQueryU){
                    Write-Host "targetquery: $targetqueryU and auditLogsQueriesMatching: $auditLogsQueriesMatching"
                    $stopAuditLoop = $true
                    break
                }
            }
            if ($stopAuditLoop) {break}
        }

        # CONDITION: If alert rule has one of the queries to check break glass account signin logs
        # Remove duplicate from actionGroup ID
        $actionGroupID = $actionGroupID | Where-Object { $_ -ne $null } | ForEach-Object{ $_.ToLower() } | Select-Object -Unique
        $actionGroupIDUnique = $actionGroupID | Where-Object { $_ -ne $null } | ForEach-Object{ $_.ToLower() } | Select-Object -Unique 

        if($bgAcctQueriesMatching) {
            # Get action groups associated with BG signIn alert rule
            $filterAlertRuleBGSignIn = $alertRules | Where-Object {$_.CriterionAllOf.Query -like "*SigninLogs*"}

            if ($null -ne $filterAlertRuleBGSignIn.ActionGroup){
                $uniqueActionGroupBGSignIn = $filterAlertRuleBGSignIn.ActionGroup | ForEach-Object{ $_.ToLower() } | Select-Object -Unique 
                
                try {
                    $actionGroups = Get-AzActionGroup | Where-Object {$actionGroupIDUnique -contains $_.Id.ToLower()}
                    $actionGroupIdsFromCmd = $actionGroups.Id | ForEach-Object { $_.ToLower() }
                    $allExistBG = $actionGroupIdsFromCmd | ForEach-Object {$uniqueActionGroupBGSignIn -contains $_}

                    if ($allExistBG -notcontains $false){
                        Write-Host "All action groups are in the unique SignIn list."
                        
                        $allReceiversWithValuesBG = Find-ReceiverValues($actionGroups)
                        # Action groups exist -> SignInLogs check flow is compliant!
                        if($allReceiversWithValuesBG.Count -gt 0){$signInLogsCompliance = $true}

                    }
                    else {
                        # Write-Host "Some action groups are not in the SignIn list."
                        if ($filterAlertRuleBGSignIn.ActionGroup.Count -eq ($allExistBG | Where-Object { $_ -eq $true }).Count){

                            $allReceiversWithValuesBG = Find-ReceiverValues($actionGroups)
                            # Action groups exist -> SignInLogs check flow is compliant!
                            if($allReceiversWithValuesBG.Count -gt 0){$signInLogsCompliance = $true}

                        }
                        else{
                            # Write-Host "Some action groups are missing from the SignIn list."
                            $signInLogsCompliance = $false
                            $Comments += $msgTable.noActionGroupsForBGaccts
                            $ErrorList += "Could not find action groups for the breakglass account alert rules for the resource group: $_"
                        }
                    }   
                }
                catch {
                    # catch Exception
                    $signInLogsCompliance = $false
                    $Comments += $msgTable.noActionGroupsForBGaccts
                    $ErrorList += "Could not find action groups for the breakglass account alert rules for the resource group: $_"
                }
            }
            else{
                # if no associated action group
                $signInLogsCompliance = $false
                $Comments += $msgTable.noActionGroupsForBGaccts
                $ErrorList += "Could not find action groups for the breakglass account alert rules for the resource group: $_"
            }  
        }
        else{
            # No matching alert rules in signin logs
            $IsCompliant = $false
            $Comments += $msgTable.noAlertRuleforBGaccts
        }

        # CONDITION: If alert rule has one of the queries to check audit logs
        if($auditLogsQueriesMatching) {

            # Get action groups associated with BG signIn alert rule
            $filterAlertRuleCAP = $alertRules | Where-Object {$_.CriterionAllOf.Query -like "*AuditLogs*"}

            if ($null -ne $filterAlertRuleCAP.ActionGroup){
                $uniqueActionGroupCAP= $filterAlertRuleCAP.ActionGroup | ForEach-Object{ $_.ToLower() } | Select-Object -Unique

                # Get action groups associated with our alert rule
                try {
                    $actionGroups = Get-AzActionGroup | Where-Object {$actionGroupIDUnique -contains $_.Id.ToLower()}
                    $actionGroupIdsFromCmdCAP = $actionGroups.Id | ForEach-Object { $_.ToLower() }
                    $allExistCAP = $actionGroupIdsFromCmdCAP | ForEach-Object {$uniqueActionGroupCAP -contains $_}

                    if ($allExistCAP -notcontains $false){
                        # Write-Host "All action groups are in the unique Audit list."
                        $allReceiversWithValuesCAP = Find-ReceiverValues($actionGroups)
                        # Action groups exist -> AuditLogs check flow is compliant!
                        if($allReceiversWithValuesCAP.Count -gt 0){$auditLogsCompliance = $true}

                    }
                    else {
                        Write-Host "Some action groups are not from the Audit list."
                        $countTrue = ($allExistCAP | Where-Object { $_ -eq $true }).Count

                        if ($filterAlertRuleCAP.ActionGroup.Count -eq $countTrue){
                            
                            if($actionGroups.Id -contains $filterAlertRuleCAP.ActionGroup){
                                $actionGroupsCAP = $actionGroups | where-object {$_.id -like $filterAlertRuleCAP.ActionGroup}
                                
                                Write-Host "Finding allReceiversWithValuesCAP for AuditLog alerts"

                                # Test and use function later for this use case
                                # $allReceiversWithValuesCAP = Find-ReceiverValues($actionGroupsCAP)

                                $allReceiversWithValuesCAP = @()
                                # Iterate through each action group
                                foreach ($actionGroup in $actionGroupsCAP) {
                                    # Filter the properties to find the receivers with values
                                    $receiversWithValues = $actionGroup.PSObject.properties | Where-Object {
                                        $_.Name -like "*Receiver*" -and $_.MemberType -eq 'Property' -and $null -ne $_.Value -and $_.Value.Count -gt 0
                                    }
                                    $allReceiversWithValuesCAP += [PSCustomObject]@{
                                        ActionGroupName = $actionGroup.Name
                                        Receivers = $receiversWithValues
                                    }
                                }
                                
                                # Action groups exist -> AuditLogs check flow is compliant!
                                if($allReceiversWithValuesCAP.Count -gt 0){$auditLogsCompliance = $true}
                            }

                        }
                        else{
                            $auditLogsCompliance = $false
                            $Comments += $msgTable.noActionGroupsForAuditLogs
                            $ErrorList += "Could not find action groups for the audit log alert rules for the resource group: $_"
                        }
                    } 
                }
                catch {
                    $auditLogsCompliance = $false
                    $Comments += $msgTable.noActionGroupsForAuditLogs
                    $ErrorList += "Could not find action groups for the audit log alert rules for the resource group: $_"
                }
            }
            else {
                # if no associated action group
                $auditLogsCompliance = $false
                $Comments += $msgTable.noActionGroupsForAuditLogs
                $ErrorList += "Could not find action groups for the audit log alert rules for the resource group: $_"
            }
        }
        else{
            # No matching alert rules in audit logs
            $IsCompliant = $false
            $Comments += $msgTable.NoAlertRuleforCaps

        }
       
        # CONDITION: If both checks are compliant then set the control as compliant
        if($signInLogsCompliance -and $auditLogsCompliance){
            $IsCompliant = $true
        }
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