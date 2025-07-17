function Validate-ActionGroups {
    param (
        [Object[]] $alerts,
        [Object[]] $subOwners
    )

    $actionGroupCompliant = $false

    #Retrieve action group IDs
    $actionGroupIds = $alerts | Select-Object -ExpandProperty ActionGroup | Select-Object -ExpandProperty Id

    foreach ($id in $actionGroupIds){

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
        $EnableMultiCloudProfiles # New feature flag, default to false
    )

    $isCompliant = $false
    $Comments = ""
    $ErrorList = @()

    try{
        #Get All the Subscriptions
        $subs = Get-AzSubscription -ErrorAction SilentlyContinue| Where-Object {$_.State -eq "Enabled"}

        foreach($subscription in $subs){
            $subId = $subscription.Id
            Set-AzContext -SubscriptionId $subId

            #Get subscription owners
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

                #Exit if no health alert found for any sub
                if($null -eq $filteredAlerts){
                    $Comments += $msgTable.NotAllSubsHaveAlerts
                    break
                }
                
                #Filter again to make sure correct alert conditions are used; "Service Issue" -> Incident, "Health Advisories" -> Informational, "Security Advisory -> Security"
                $filteredAlerts = $filteredAlerts | Where-Object {
                    # Check if ConditionAllOf contains objects with AnyOf containing the required conditions
                    ($_.ConditionAllOf | Where-Object {
                        $_.AnyOf | Where-Object { 
                            $_.Field -eq "properties.incidentType" -and $_.Equal -match "Security|Informational|ActionRequired|Incident"
                        }
                    }).Count -eq 1
                }

                #Check if event types not configured for any service health alert
                if($null -eq $filteredAlerts.Count){
                    $Comments += $msgTable.EventTypeMissingForAlert -f $subscription.Name
                    break
                }
            }
            catch{
                $isCompliant = $false
                $Comments += $msgTable.noServiceHealthAlerts -f $subscription
                $ErrorList += "Error retrieving service health alerts for the following subscription: $_"
            }
            #Store compliance state of each action group
            $actionGroupsCompliance += Validate-ActionGroups -alerts $filteredAlerts -subOwners $subOwners
        }

        #All action groups are compliant
        if ($actionGroupsCompliance -notcontains $false -and $null -ne $actionGroupsCompliance){
            $isCompliant = $true
        }
        #Even if one is non compliant
        elseif ($actionGroupsCompliance -contains $false) {
            $isCompliant = $false
            $Comments += $msgTable.nonCompliantActionGroups
        }
    }
    catch{
        $IsCompliant = $false
        $ErrorList += "Encountered an error retrieving subscriptions"
    }

    if($isCompliant){
        $Comments = $msgTable.compliantServiceHealthAlerts
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
            f(!$evalResult.ShouldAvailable ){
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