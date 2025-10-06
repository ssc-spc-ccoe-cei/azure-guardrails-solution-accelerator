function Get-ActionGroupContactTokens {
    param (
        [Parameter(Mandatory=$true)]
        [Object[]] $ActionGroup
    )

    # Helper purpose:
    #   Gather every notification target for an action group so the caller can apply a simple count
    #   check. The output is a set of "contact tokens" (emails plus owner-role tokens).

    # Azure built-in Owner role ID (constant across all Azure tenants)
    # Used as fallback when RoleName property is not populated
    $ownerRoleId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'

    $emailTokens = @(
        $ActionGroup | ForEach-Object {
            if ($_.EmailReceiver) {
                $_.EmailReceiver | ForEach-Object { $_.EmailAddress }
            }
        } | Where-Object { $_ -is [string] -and $_.Trim().Length -gt 0 }
    ) | ForEach-Object { $_.Trim() } | Sort-Object -Unique

    $ownerTokens = @(
        $ActionGroup | ForEach-Object {
            if ($_.ArmRoleReceiver) {
                $_.ArmRoleReceiver | Where-Object {
                    $_.RoleName -eq 'Owner' -or $_.RoleId -eq $ownerRoleId
                } | ForEach-Object {
                    if ($_.Name -is [string] -and $_.Name.Trim().Length -gt 0) {
                        $_.Name.Trim()
                    }
                    elseif ($_.RoleId -is [string] -and $_.RoleId.Trim().Length -gt 0) {
                        $_.RoleId.Trim()
                    }
                }
            }
        } | Where-Object { $_ -is [string] -and $_.Trim().Length -gt 0 }
    ) | Sort-Object -Unique

    # Return array as single object (leading comma prevents PowerShell from unrolling the array)
    return ,(@($emailTokens) + ($ownerTokens | ForEach-Object { "Owner::" + $_ }))
}

function Validate-ActionGroups {
    param (
        [Object[]] $alerts,
        [Parameter(Mandatory=$true)][string] $SubscriptionName,
        [Parameter(Mandatory=$true)][hashtable] $MsgTable
    )

    # Evaluate each action group's contacts and return a boolean per group indicating whether the
    # "two distinct contacts" requirement is met.

    # Retrieve action group IDs
    $actionGroupIds = $alerts | Select-Object -ExpandProperty ActionGroup | Select-Object -ExpandProperty Id
    if ($actionGroupIds -isnot [System.Collections.IEnumerable] -or $actionGroupIds -is [string]) {
        $actionGroupIds = @($actionGroupIds)
    }
    $actionGroupIdsArray = [System.Collections.ArrayList]@($actionGroupIds)

    # Each collection captures the evaluation outcome so the caller can surface messages or errors as needed.
    $results = [System.Collections.ArrayList]::new()
    $comments = [System.Collections.ArrayList]::new()
    $errors = [System.Collections.ArrayList]::new()

    if ($actionGroupIdsArray.Count -eq 0) {
        $comments.Add($MsgTable.noServiceHealthActionGroups -f $SubscriptionName) | Out-Null
        $errors.Add("No action groups were returned for this Service Health alert evaluation.") | Out-Null
        $results.Add($false) | Out-Null
        return [PSCustomObject]@{
            Results = $results
            Comments = $comments
            Errors = $errors
        }
    }

    foreach ($id in $actionGroupIdsArray){
        # Build a list of distinct action-group contacts (emails + owner receivers) so caller logic
        # can inspect each group independently and continue to flag failures via "-contains $false".
        $contactTokens = @()

        try{
            # Retrieve action group details and extract all notification contacts (emails + owner receivers)
            $actionGroups = Get-AzActionGroup -InputObject $id
            $contactTokens = Get-ActionGroupContactTokens -ActionGroup $actionGroups
        }
        catch{
            # Surface the missing action group condition to the caller instead of relying on outer-scope variables.
            $comments.Add($MsgTable.noServiceHealthActionGroups -f $SubscriptionName) | Out-Null
            $errors.Add("Error retrieving service health alerts for the following subscription: $_") | Out-Null
        }

        $results.Add((@($contactTokens).Count -ge 2)) | Out-Null
    }

    # Return a structured payload so the caller can merge comments/log errors without extra ref parameters.
    return [PSCustomObject]@{
        Results = $results
        Comments = $comments
        Errors = $errors
    }
}


function Get-ServiceHealthAlerts {
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
        [string] 
        $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] 
        $EnableMultiCloudProfiles # feature flag, default to false
    )

    [PSCustomObject] $PsObject = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList

    # Get All the Subscriptions
    try {
        $subs = Get-AzSubscription -ErrorAction Stop | Where-Object {$_.State -eq "Enabled"} 
    }
    catch {
        $Errorlist.Add("Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_" )
        throw "Error: Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_"
    }

    foreach($subscription in $subs){
        # Initialize
        $isCompliant = $false
        $Comments = ""
        $actionGroupsCompliance = @()
        $checkActionGroupNext = $false

        # find subscription information
        $subId = $subscription.Id
        Set-AzContext -SubscriptionId $subId

        # Get subscription owners
        $subOwners = Get-AzRoleAssignment -Scope "/subscriptions/$subId" | Where-Object {
            $_.RoleDefinitionName -eq "Owner" 
        } | Select-Object -ExpandProperty SignInName

        try{
            # Get all service health alerts
            $alerts = Get-AzActivityLogAlert

            # Filter for Service Health Alerts with specific conditions
            $filteredAlerts = $alerts | Where-Object {
                # Check if any condition in ConditionAllOf matches the criteria
                $_.ConditionAllOf | Where-Object { 
                    $_.Field -eq "category" -and $_.Equal -eq "ServiceHealth" 
                }
            }

            # Condition: Non-compliant if no health alert found for any sub
            if($null -eq $filteredAlerts){
                $isCompliant = $false
                $Comments = $msgTable.NotAllSubsHaveAlerts
            }
            else{
                # Case: when all the alert event types are selected from the conditions/properties.incidentType
                $allAnyOfNullOrEmpty = $filteredAlerts.ConditionAllOf -notmatch '\S' -or ($filteredAlerts.ConditionAllOf | ForEach-Object {
                    if ($null -eq $_.AnyOf -or $_.AnyOf.Count -eq 0) {$true} else {$false}
                }) -notcontains $false

                #Filter again to make sure correct alert conditions are used; "Service Issue" -> Incident, "Health Advisories" -> Informational, "Security Advisory -> Security"
                $filteredAlertsContions = $filteredAlerts | Where-Object {
                    # Check if ConditionAllOf contains objects with AnyOf containing the required 3 conditions
                    ($_.ConditionAllOf | Where-Object {
                        $_.AnyOf | Where-Object { 
                            $_.Field -eq "properties.incidentType" -and $_.Equal -match "Security|Informational|ActionRequired|Incident"
                        }
                    }).Count -eq 1
                }

                if($allAnyOfNullOrEmpty -and ($null -eq $filteredAlertsContions)){
                    $checkActionGroupNext = $true  
                }
                # Check if event types not configured for any service health alert i.e. Condition: non-compliant if null
                elseif($null -eq $filteredAlertsContions.Count){
                    $isCompliant = $false
                    $Comments = $msgTable.EventTypeMissingForAlert -f $subscription.Name
                }
                else{
                    
                    $requiredFilteredAlerts = $filteredAlertsContions | where-object {
                        $_.ConditionAllOf | Where-Object {
                            $_.AnyOf | Where-Object { 
                                $_.Field -eq "properties.incidentType"
                        }}
                    }
                    $incidentTypes = $requiredFilteredAlerts | ForEach-Object {
                        $_.ConditionAllOf | ForEach-Object {
                            $_.AnyOf | Where-Object {
                                $_.Field -eq "properties.incidentType"
                            }
                        }
                    }

                    # Condition: non-compliant if alert conditions<3
                    if ($incidentTypes.Count -lt 3) {
                        $isCompliant = $false
                        $Comments = $msgTable.EventTypeMissingForAlert -f $subscription.Name
                    }
                    # Condition: if allAnyOfNullOrEmpty is true, means All ConditionAllOf.AnyOf are null or empty -> all 4 conditions are selected
                    elseif($allAnyOfNullOrEmpty -and $filteredAlerts.Count -eq 3){
                       $checkActionGroupNext = $true
                    }
                    # Condition: non-compliant if not meet the 3 requires alert conditions ("Service Issues" -> Incident, "Health Advisories" -> Informational, "Security Advisory -> Security")
                    elseif (($incidentTypes.Count -ge- 3) -and @("Security", "Informational", "Incident" | ForEach-Object { $_ -in $incidentTypes }) -notcontains "False") {
                        $checkActionGroupNext = $true
                    }
                    else{
                        # Condition: non-compliant if 3 correct alert conditions are not met
                        $isCompliant = $false
                        $Comments = $msgTable.EventTypeMissingForAlert -f $subscription.Name
                    }
                }
                
                if($checkActionGroupNext){
                    # Store compliance state of each action group
                    $evaluation = Validate-ActionGroups -alerts $filteredAlerts -SubscriptionName $subscription.Name -MsgTable $msgTable

                    if ($evaluation.Comments.Count -gt 0) {
                        # Merge any helper-supplied context (e.g., missing action group) with existing comments.
                        $Comments = ($Comments, $evaluation.Comments) -join "`n"
                        $Comments = $Comments.Trim()
                    }
                    foreach ($err in $evaluation.Errors) {
                        # Preserve detailed errors so downstream diagnostics remain intact.
                        $ErrorList.Add($err) | Out-Null
                    }
                    # All action groups are compliant
                    if ($evaluation.Results -notcontains $false -and $null -ne $evaluation.Results){
                        $isCompliant = $true
                        if ([string]::IsNullOrWhiteSpace($Comments)) {
                            $Comments = $msgTable.compliantServiceHealthAlerts
                        }
                    }
                    # Even if one is non-compliant
                    elseif ($evaluation.Results -contains $false) {
                        $isCompliant = $false
                        if ([string]::IsNullOrWhiteSpace($Comments)) {
                            $Comments = $msgTable.nonCompliantActionGroups
                        }
                    }
                }
            }
            
        }
        catch{
            $isCompliant = $false
            $Comments = $msgTable.noServiceHealthAlerts -f $subscription
            $ErrorList += "Error retrieving service health alerts for the following subscription: $_"
        }
        
        # Add evaluation info for each subscription
        $C = [PSCustomObject]@{
            SubscriptionName = $subscription.Name
            ComplianceStatus = $isCompliant
            ControlName = $ControlName
            Comments = $Comments
            ItemName = $ItemName
            ReportTime = $ReportTime
            itsgcode = $itsgcode
        }

        # Add profile information if MCUP feature is enabled
        if ($EnableMultiCloudProfiles) {
            $result = Add-ProfileInformation -Result $C -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId -ErrorList $ErrorList
            Write-Host "$result"
            $PsObject.Add($result) | Out-Null
        } else {
            $PsObject.Add($C) | Out-Null
        }

        continue
    }
    
    $moduleOutput = [PSCustomObject]@{
        ComplianceResults = $PsObject
        Errors = $ErrorList
    }

    return $moduleOutput
}