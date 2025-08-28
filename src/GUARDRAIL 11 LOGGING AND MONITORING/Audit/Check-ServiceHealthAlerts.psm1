function Validate-ActionGroups {
    param (
        [Object[]] $alerts,
        [Object[]] $subOwners
    )

    $actionGroupCompliant = $false

    #Retrieve action group IDs
    $actionGroupIds = $alerts | Select-Object -ExpandProperty ActionGroup | Select-Object -ExpandProperty Id
    if ($actionGroupIds -isnot [System.Collections.IEnumerable] -or $actionGroupIds -is [string]) {
        $actionGroupIds = @($actionGroupIds)
    }
    $actionGroupIdsArray = [System.Collections.ArrayList]@($actionGroupIds)

    foreach ($id in $actionGroupIdsArray){

        #Get sub id from action group
        $subscriptionId = ($id -split '/')[2]

        try{
            #Get the action group
            $actionGroups = Get-AzActionGroup -InputObject $id

            $emailAddresses = $actionGroups | ForEach-Object {
                if ($_.EmailReceiver) {
                    $_.EmailReceiver | Select-Object -ExpandProperty EmailAddress
                }
            } | Where-Object { $_ -ne $null } # Remove any null results

            $actionSubOwners += Get-AzRoleAssignment -Scope "/subscriptions/$subscriptionId" | Where-Object {
                $_.RoleDefinitionName -eq "Owner" 
            } | Select-Object -ExpandProperty SignInName

            #Find and collect all the matching owners of this sub
            $matchingOwners = $actionSubOwners | Where-Object {$subOwners -contains $_}
        }
        catch{
            $Comments += $msgTable.noServiceHealthActionGroups -f $subscription
            $ErrorList += "Error retrieving service health alerts for the following subscription: $_"
        }

        if($emailAddresses -ge 2){
            $actionGroupCompliant = $true
        }
        elseif($emailAddresses -eq 1 -and $matchingOwners -ge 1){
            $actionGroupCompliant = $true
        }
    }

    #Return compliance state of action group
    return $actionGroupCompliant
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
                    $actionGroupsCompliance = Validate-ActionGroups -alerts $filteredAlerts -subOwners $subOwners

                    # All action groups are compliant
                    if ($actionGroupsCompliance -notcontains $false -and $null -ne $actionGroupsCompliance){
                        $isCompliant = $true
                        $Comments = $msgTable.compliantServiceHealthAlerts
                    }
                    # Even if one is non-compliant
                    elseif ($actionGroupsCompliance -contains $false) {
                        $isCompliant = $false
                        $Comments = $msgTable.nonCompliantActionGroups
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