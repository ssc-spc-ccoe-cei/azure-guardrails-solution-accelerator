
function Get-SubscriptionRequiredRoleCount {
    <#
    .SYNOPSIS
        Returns the number of Owners/Monitoring role assignments (Contributor or Reader) assigned to the current subscription.
    .DESCRIPTION
        Queries Azure RBAC to count how many principals have the Owner/Monitoring roles
        (Contributor or Reader) at the subscription scope. This is used to determine how many contacts
        the "Owners"/"Monitoring" notification target actually represents excluding the service pricipals.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string] $requiredRoleId
    )

    try {
        $roleAssignments = Get-AzRoleAssignment -RoleDefinitionId $requiredRoleId -ErrorAction Stop | Where-Object { $_.ObjectType -ne 'ServicePrincipal' }
        return @($roleAssignments).Count
    }
    catch {
        Write-Output "Failed to retrieve subscription required role assignments: $_"
        return 0
    }
}


function Get-ActionGroupContactTokens {
    <#
    .SYNOPSIS
        Extracts contact tokens from an Azure Action Group.
    .DESCRIPTION
        Gathers all notification targets (email addresses and owner-role and ARM role receiver tokens)
        from the specified action group(s). Returns a unified set of "contact tokens"
        that can be used for counting unique contacts. Email addresses are returned
        as-is. Owner role receivers are prefixed with "Owner::" to distinguish
        them from direct email contacts, since the number of contacts they represent depends on actual number of subscription owners.
        Monitoring Contributor and Monitoring Reader role receivers -- also valid Action Group "Email Azure Resource Manager role" 
        targets -- are prefixed with "Role::" and, like email contacts, each unique receiver counts as a single contact.
    #>
    param (
        [Parameter(Mandatory=$true)]
        [Object[]] $ActionGroup
    )

    # Azure built-in role IDs (constant across all Azure tenants)
    # Used as fallback when RoleName property is not populated
    $ownerRoleId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
    $monitoringContributorRoleId = '749f88d5-cbae-40b8-bcfc-e573ddc772fa'
    $monitoringReaderRoleId = '43d0d8ad-25c7-4714-9337-8ba259a9fe05'

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

    # Monitoring Contributor / Monitoring Reader ARM role receivers are also valid
    $monitoringContributorRoleTokens = @(
        $ActionGroup | ForEach-Object {
            if ($_.ArmRoleReceiver) {
                $_.ArmRoleReceiver | Where-Object {
                    $_.RoleId -eq $monitoringContributorRoleId
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

    $monitoringReaderRoleTokens = @(
        $ActionGroup | ForEach-Object {
            if ($_.ArmRoleReceiver) {
                $_.ArmRoleReceiver | Where-Object {
                    $_.RoleId -eq $monitoringReaderRoleId
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
    return ,(@($emailTokens) + ($ownerTokens | ForEach-Object { "Owner::" + $_ }) + ($monitoringContributorRoleTokens | ForEach-Object { "MonitoringContributor::" + $_ }) + ($monitoringReaderRoleTokens | ForEach-Object { "MonitoringReader::" + $_ }))
}

function Validate-ActionGroups {
    <#
    .SYNOPSIS
        Validates action groups associated with service health alerts.
    .DESCRIPTION
        Evaluates each action group's notification contacts and returns aggregate
        compliance results. When subscription owners and monitoring roles are configured as notification
        targets, the effective contact count depends on the actual number of owners
        assigned to the subscription:
        - 1 owner or monitoring role assigned -> counts as 1 contact
        - 2 or more owners or monitoring roles assigned -> counts as 2 contacts
        Returns a PSCustomObject containing unique contacts, effective contact count,
        comments, and any errors encountered during validation.
    #>
    param (
        [Object[]] $alerts,
        [Parameter(Mandatory=$true)][string] $SubscriptionName,
        [Parameter(Mandatory=$true)][string] $SubscriptionId,
        [Parameter(Mandatory=$true)][hashtable] $MsgTable,
        [Object[]] $allEnabledActionGroups
    )

    # Evaluate each action group's contacts and surface aggregate results back to the caller.
    # When subscription owners are used as notification targets, the effective contact count
    # depends on the actual number of owners/monitoring roles assigned to the subscription:
    #   - 1 owner or monitoring role assigned -> counts as 1 contact
    #   - 2 or more owners or monitoring roles assigned -> counts as 2 contacts

    # Retrieve action group IDs from alerts
    $actionGroupIds = $alerts | Select-Object -ExpandProperty ActionGroup | Select-Object -ExpandProperty Id
    if ($actionGroupIds -isnot [System.Collections.IEnumerable] -or $actionGroupIds -is [string]) {
        $actionGroupIds = @($actionGroupIds)
    }

    # Track aggregate outcomes.
    $uniqueContacts = New-Object 'System.Collections.Generic.HashSet[string]'
    $comments = [System.Collections.ArrayList]::new()
    $errors = [System.Collections.ArrayList]::new()

    # Get all enabled action groups for the subscription
    try{
        # Get action group IDs
        $actionGroupIdsArray = [System.Collections.ArrayList]@($actionGroupIds | Where-Object { $_ -in $allEnabledActionGroups.Id })
            Write-Verbose "Retrieved $($actionGroupIdsArray.Count) enabled action group IDs for subscription '$SubscriptionName'"
        if ($actionGroupIdsArray.Count -eq 0) {
            $comments.Add($MsgTable.noServiceHealthActionGroups -f $SubscriptionName) | Out-Null
            $errors.Add("No action groups were returned for this Service Health alert evaluation for the subscription: $SubscriptionName") | Out-Null
            return [PSCustomObject]@{
                UniqueContacts = @()
                EffectiveContactCount = 0
                Comments = $comments
                Errors = $errors
            }
        }
        # Retrieve contacts from each action group
        foreach ($id in $actionGroupIdsArray){
            try{
                $actionGroup = $allEnabledActionGroups | Where-Object { $_.Id -eq $id }
                $contactTokens = Get-ActionGroupContactTokens -ActionGroup $actionGroup
                
                foreach ($token in $contactTokens) { $uniqueContacts.Add($token) | Out-Null }
            }
            catch{
                $comments.Add($MsgTable.noServiceHealthActionGroups -f $SubscriptionName) | Out-Null
                $errors.Add("Error retrieving service health alerts for the following subscription: $_") | Out-Null
            }
        }
        
    }
    catch{
        $comments.Add($MsgTable.noServiceHealthActionGroups -f $SubscriptionName) | Out-Null
        $errors.Add("Error retrieving service health alerts for the following subscription: $_") | Out-Null
        return [PSCustomObject]@{
            UniqueContacts = @()
            EffectiveContactCount = 0
            Comments = $comments
            Errors = $errors
        }
    }
    

    # Separate owner tokens from other contact tokens (e.g., email addresses, Monitoring Contributor/Reader ARM role receivers
    $ownerTokens = @($uniqueContacts | Where-Object { $_ -like 'Owner::*' })
    $monitoringContributorRoleTokens = @($uniqueContacts | Where-Object { $_ -like 'MonitoringContributor::*' })
    $monitoringReaderRoleTokens = @($uniqueContacts | Where-Object { $_ -like 'MonitoringReader::*' })
    $nonOwnerTokens = @($uniqueContacts |
        Where-Object { $_ -notlike 'Owner::*'} |
        Where-Object { $_ -notlike 'MonitoringContributor::*'} |
        Where-Object { $_ -notlike 'MonitoringReader::*' }
    )
    Write-Verbose "Retrieved $($ownerTokens.Count) owner tokens for subscription '$SubscriptionName'"
    Write-Verbose "Retrieved $($monitoringContributorRoleTokens.Count) monitoring contributor role tokens for subscription '$SubscriptionName'"
    Write-Verbose "Retrieved $($monitoringReaderRoleTokens.Count) monitoring reader role tokens for subscription '$SubscriptionName'"
    Write-Verbose "Retrieved $($nonOwnerTokens.Count) non-owner tokens for subscription '$SubscriptionName'"

    # Calculate effective contact count
    # Non-owner contacts (emails, Monitoring Contributor/Reader role receivers, etc.) count as 1 each
    $effectiveContactCount = $nonOwnerTokens.Count

    # Azure built-in Owner/Monitoring role role ID (constant across all Azure tenants)
    $ownerRoleId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
    $monitoringContributorRoleId = '749f88d5-cbae-40b8-bcfc-e573ddc772fa'
    $monitoringReaderRoleId = '43d0d8ad-25c7-4714-9337-8ba259a9fe05'

    # If subscription owners are being used as notification targets, check actual owner count
    if ($ownerTokens.Count -gt 0) {
        $subscriptionOwnerCount = Get-SubscriptionRequiredRoleCount -requiredRoleId $ownerRoleId
        Write-Verbose "Retrieved $subscriptionOwnerCount owner assignments for the current Subscription: $SubscriptionName"
        
        if ($subscriptionOwnerCount -eq 0) {
            # No owners found - this is unusual, log a warning
            $errors.Add("No subscription owners found for subscription '$SubscriptionName' despite Owner role being configured as a notification target.") | Out-Null
        }
        elseif ($subscriptionOwnerCount -eq 1) {
            # Only 1 owner assigned -> counts as 1 contact
            $effectiveContactCount += 1
        }
        else {
            # 2 or more owners assigned -> counts as 2 contacts
            $effectiveContactCount += 2
        }
    }

    # If subscription monitoring contributor roles are being used as notification targets, check actual monitoring role count  
    if ($monitoringContributorRoleTokens.Count -gt 0) {
        
        $monitoringContributorCount = Get-SubscriptionRequiredRoleCount -requiredRoleId $monitoringContributorRoleId
        Write-Verbose "Retrieved $monitoringContributorCount assignments for the current Subscription: $SubscriptionName"
                
        if ($monitoringContributorCount -eq 0) {
            # No monitoring roles found
            $errors.Add("No subscription monitoring contributor roles found for subscription '$SubscriptionName' despite non-owner contacts being configured as notification targets.") | Out-Null
        }
        elseif ($monitoringContributorCount -eq 1) {
            # Only 1 monitoring role assigned -> counts as 1 contact
            $effectiveContactCount += 1
        }
        else {
            # 2 or more monitoring roles assigned -> counts as 2 contacts
            $effectiveContactCount += 2
        }
    }

    # If subscription monitoring reader roles are being used as notification targets, check actual monitoring readerrole count  
    if ($monitoringReaderRoleTokens.Count -gt 0) {
        
        $monitoringReaderCount = Get-SubscriptionRequiredRoleCount -requiredRoleId $monitoringReaderRoleId
        Write-Verbose "Retrieved $monitoringReaderCount assignments for the current Subscription: $SubscriptionName"
        if ($monitoringReaderCount -eq 0) {
            # No monitoring roles found
            $errors.Add("No subscription monitoring reader roles found for subscription '$SubscriptionName'.") | Out-Null
        }
        elseif ($monitoringReaderCount -eq 1) {
            # Only 1 monitoring role assigned -> counts as 1 contact
            $effectiveContactCount += 1
        }
        else {
            # 2 or more monitoring roles assigned -> counts as 2 contacts
            $effectiveContactCount += 2
        }
    }


    return [PSCustomObject]@{
        UniqueContacts = @($uniqueContacts)
        EffectiveContactCount = $effectiveContactCount
        Comments = $comments
        Errors = $errors
    }
}


function Get-ServiceHealthAlerts {
    <#
    .SYNOPSIS
        Retrieves service health alerts for the specified subscriptions.
    .DESCRIPTION
        This function queries Azure Monitor to get all enabled action groups and evaluates the service health alerts for the subscriptions.
    #>
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
        [switch] $EnableMultiCloudProfiles # feature flag
    )

    [PSCustomObject] $PsObject = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    
    # Get All the Subscriptions
    try {
        $allSubs = Get-AzSubscription -ErrorAction Stop
        $subs = @($allSubs | Where-Object {$_.State -eq "Enabled"})
        $skippedSubs = @($allSubs | Where-Object {$_.State -ne "Enabled"})
        Write-Verbose "Total enabled subscriptions: $($subs.Count)"
    }
    catch {
        $Errorlist.Add("Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_" )
        throw "Error: Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_"
    }

    foreach ($skippedSub in $skippedSubs){
        $notEvaluatedResult = [PSCustomObject]@{
            SubscriptionName = $skippedSub.Name
            ComplianceStatus = $false
            Comments         = ''
            ItemName         = $ItemName
            ControlName      = $ControlName
            itsgcode         = $itsgcode
            ReportTime       = $ReportTime
        }
        $notEvaluatedResult = Set-SubscriptionNotEvaluatedStatus -Result $notEvaluatedResult -SubscriptionName $skippedSub.Name -msgTable $msgTable
        [void]$PsObject.Add($notEvaluatedResult) | Out-Null
    }


    # Get all enabled action groups in the tenant scope azure monitor
    $allEnabledActionGroups = @()
    try{
        $subs | ForEach-Object {
            Select-AzSubscription -SubscriptionId $_.Id | Out-Null
            Get-AzResourceGroup | ForEach-Object {
                $rgActionGroups = Get-AzActionGroup -ResourceGroupName $_.ResourceGroupName -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
                if($null -ne $rgActionGroups){
                    $allEnabledActionGroups += $rgActionGroups | Where-Object { $_.Enabled -eq $true }
                }
            }
        }
    }
    catch{
        $ErrorList.Add("Failed to execute the 'Get-AzActionGroup' command--verify your permissions and the installion of the Az.Monitor module; returned error message: $_" )
        throw "Error: Failed to execute the 'Get-AzActionGroup' command--verify your permissions and the installion of the Az.Monitor module; returned error message: $_"
    }
    
    # Evaluate service health alerts and their associated action groups
    foreach($subscription in $subs){
        # Initialize
        $isCompliant = $false
        $Comments = ""
        $checkActionGroupNext = $false
        $eventTypeConditionPass = $false

        # find subscription information
        $subId = $subscription.Id
        Set-AzContext -SubscriptionId $subId
        Write-Verbose "Evaluating service health alerts for subscription '$($subscription.Name)'"
        
        try{
            # List activity log alerts (service health alerts) under current subscription set by the context
            $alerts = Get-AzActivityLogAlert
            $enabledAlerts = $alerts | Where-Object { $_.Enabled -eq $true }
            
            # Filter for Service Health Alerts with specific conditions
            $filteredAlerts = $enabledAlerts | Where-Object {
                # Check if any condition in ConditionAllOf matches the criteria
                $_.ConditionAllOf | Where-Object { 
                    $_.Field -eq "category" -and $_.Equal -eq "ServiceHealth" 
                }
            }
            Write-Verbose "Total enabled service health alerts: $($filteredAlerts.Count) for the subscription '$($subscription.Name)'"
            
            # Condition: Non-compliant if no health alert found for any sub
            if($null -eq $filteredAlerts){
                $isCompliant = $false
                $Comments = $msgTable.noEnabledHealthAlert
            }
            else{
                # Case: consider multiple alerts exists for the subscription;
                # When all event types are selected from the conditions/properties.incidentType

                # Create object with each alert and boolean indicating if all event types are selected

                $alertEventTypeSelectionds = @(
                    foreach($alert in $filteredAlerts){
                        $isAllEventTypesSelected = 
                            if ($alert.ConditionAllOf.Count -gt 1) {
                                $false
                            } 
                            else{
                                $alert.ConditionAllOf -notmatch '\S' -or ($_.ConditionAllOf | ForEach-Object {
                                    if ($null -eq $_.AnyOf -or $_.AnyOf.Count -eq 0) {$true} else {$false}
                                }) -notcontains $false
                            }
                        

                        [PSCustomObject]@{
                            Alert                   = $alert
                            IsAllEventTypesSelected = $isAllEventTypesSelected
                        }
                    }
                )

                # Filter alerts where all event types are selected
                $allAnyOfNullOrEmpty = $false
                $alertsWithAllEventTypesSelected = $alertEventTypeSelectionds | Where-Object { $_.IsAllEventTypesSelected -eq $true }
                if($alertsWithAllEventTypesSelected.Count -gt 0){
                    $allAnyOfNullOrEmpty = $true
                }

                # Filter alerts without 'select all' for all event types
                $alertsWithoutAllEventTypesSelected = $alertEventTypeSelectionds | Where-Object { $_.IsAllEventTypesSelected -eq $false }

                # Filter alerts where 3 required event types are selected
                # Filter again to make sure correct alert conditions are used; "Service Issue" -> Incident, "Health Advisories" -> Informational, "Security Advisory -> Security"
                $filteredAlertsConditions = $alertsWithoutAllEventTypesSelected  | Where-Object {
                    # Check if ConditionAllOf contains objects with AnyOf containing the required 3 conditions
                    ($_.ConditionAllOf | Where-Object {

                        $_.AnyOf | Where-Object { 
                            $_.Field -eq "properties.incidentType" -and $_.Equal -match "Security|Informational|ActionRequired|Incident"
                        }
                    }).Count -eq 0
                }
                $totalAlertsWithRequiredEventTypes = $alertsWithAllEventTypesSelected.Count + $filteredAlertsConditions.Count
                Write-Verbose "Retrieved the filtered alerts with required event types for subscription '$($subscription.Name)': $($totalAlertsWithRequiredEventTypes.Count)"
                if($null -eq $alertsWithAllEventTypesSelected -and ($null -eq $filteredAlertsConditions)){
                    # CASE:alert condition event types does not meet required condition
                    # checkActionGroupNext remains false
                    $isCompliant = $false
                    $Comments = $msgTable.EventTypeMissingForAlert -f $subscription.Name
                }
                elseif($alertsWithAllEventTypesSelected.Count -gt 0 -and ($null -eq $filteredAlertsConditions)){
                    # CASE: Alert condition event types have met the required criteria; check action group condition
                    Write-Verbose "Checking action group configuration next for subscription '$($subscription.Name)'..." 
                    # $checkActionGroupNext = $true
                    $eventTypeConditionPass = $true
                      
                }
                elseif($null -eq $alertsWithAllEventTypesSelected  -and $filteredAlertsConditions.Count -gt 0){
                    # CASE: Alert condition event types are selected; evaluate for 3 required event types
                    Write-Verbose "Selected alert event types. Evaluating alert event types for the subscription '$($subscription.Name)'..." 
                    # event types selected; check of required condition
                    $requiredFilteredAlerts = $filteredAlertsConditions | Select-Object -ExpandProperty Alert |where-object {
                        (
                            $_.ConditionAllOf | Where-Object {
                            # ($null -ne $_.AnyOf) -and 
                                ($_.AnyOf.Count -gt 0) -and
                                    ($_.AnyOf | Where-Object { 
                                        $_.Field -eq "properties.incidentType"
                                    })
                            }
                        ).Count -gt 0
                    }
                    
                    $incidentTypes = $requiredFilteredAlerts | ForEach-Object {
                        $_.ConditionAllOf | ForEach-Object {
                            $_.AnyOf | Where-Object {
                                $_.Field -eq "properties.incidentType"
                            }
                        }
                    }

                    # Evaluating alert event types

                    # Condition: non-compliant if alert conditions < 3
                    if ($incidentTypes.Count -lt 3) {
                        $isCompliant = $false
                        $Comments = $msgTable.EventTypeMissingForAlert -f $subscription.Name
                    }
                    # Condition: Meets the 3 requires alert conditions ("Service Issues" -> Incident, "Health Advisories" -> Informational, "Security Advisory -> Security")
                    elseif (($incidentTypes.Count -ge- 3) -and @("Security", "Informational", "Incident" | ForEach-Object { $_ -in $incidentTypes }) -notcontains "False") {
                        Write-Verbose "Meets the 3 requires alert conditions for subscription '$($subscription.Name)'. Checking action group condition next"
                        # $checkActionGroupNext = $true
                        $eventTypeConditionPass = $true
                    }
                    else{
                        # Condition: non-compliant if 3 correct alert conditions are not met
                        Write-Verbose "The condition for the required 3 event types are not met"
                        $isCompliant = $false
                        $Comments = $msgTable.EventTypeMissingForAlert -f $subscription.Name
                    }
                }
                elseif($alertsWithAllEventTypesSelected.Count -gt 0  -and $filteredAlertsConditions.Count -gt 0){
                    # multiple service alert exists for the same subscription with carious alert event type selection
                    # Evaluate each filtered alert for compliance

                    # First, evaluate each filtered alert for the required 3 event types
                    #any of the filtered alerts must meet the 3 required event types to proceed with action group evaluation
                    $eventTypeConditionPass = @()
                    foreach ($alert in $filteredAlertsConditions) {
                        $pass = $false
                        # $incidentTypes = $alert.Properties | Where-Object { $_.Name -eq "IncidentType" } | Select-Object -ExpandProperty Value
                        $requiredFilteredAlerts = $filteredAlertsConditions | Select-Object -ExpandProperty Alert |where-object {
                            (
                                $_.ConditionAllOf | Where-Object {
                                # ($null -ne $_.AnyOf) -and 
                                    ($_.AnyOf.Count -gt 0) -and
                                        ($_.AnyOf | Where-Object { 
                                            $_.Field -eq "properties.incidentType"
                                        })
                                }
                            ).Count -gt 0
                        }
                        
                        $incidentTypes = $requiredFilteredAlerts | ForEach-Object {
                            $_.ConditionAllOf | ForEach-Object {
                                $_.AnyOf | Where-Object {
                                    $_.Field -eq "properties.incidentType"
                                }
                            }
                        }
                        if (($incidentTypes.Count -ge 3) -and @("Security", "Informational", "Incident" | ForEach-Object { $_ -in $incidentTypes }) -notcontains "False") {
                            Write-Verbose "Filtered alert '$($alert.Name)' meets the 3 required event types for subscription '$($subscription.Name)'."
                            $checkActionGroupNext = $true
                            $pass = $true
                        }
                        else {
                            Write-Verbose "Filtered alert '$($alert.Name)' does not meet the 3 required event types for subscription '$($subscription.Name)'."
                            # Do not proceed to evaluate action groups for this alert as it does not meet the required event types.
                            # Proceed to the next alert without evaluating action groups for this one.
                            $pass = $false
                        }
                        $eventTypeConditionPass += $pass
                    }

                    # add to eventTypeConditionPass for the alerts in $alertsWithAllEventTypesSelected
                    if ($alertsWithAllEventTypesSelected) {
                        $pass = $true
                        # Evaluate each alert with all event types selected
                        $eventTypeConditionPass += $pass
                    }
                }
                
                # Determine if any alerts passed the event type condition
                $checkActionGroupNext = $eventTypeConditionPass -contains $true

                
                # Proceed to evaluate action groups as previous per previous evaluation condition
                if($checkActionGroupNext){
                    Write-Verbose "Evaluating action groups for subscription '$($subscription.Name)'"
                    # Store compliance state of each action group
                    $evaluation = Validate-ActionGroups -alerts $filteredAlerts -SubscriptionName $subscription.Name -SubscriptionId $subId -MsgTable $msgTable -allEnabledActionGroups $allEnabledActionGroups

                    if ($evaluation.Comments.Count -gt 0) {
                        # Merge any helper-supplied context (e.g., missing action group) with existing comments.
                        $commentItems = @()
                        if (-not [string]::IsNullOrWhiteSpace($Comments)) {
                            $commentItems += $Comments
                        }
                        $commentItems += $evaluation.Comments
                        $Comments = ($commentItems | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
                    }
                    foreach ($err in $evaluation.Errors) {
                        # Preserve detailed errors so downstream diagnostics remain intact.
                        $ErrorList.Add($err) | Out-Null
                    }

                    # Use EffectiveContactCount which accounts for subscription owner count logic:
                    # - If owners or monitoring roles are used and only 1 owner/monitoring role is assigned -> counts as 1 contact
                    # - If owners/monitoring roles are used and 2+ owners/monitoring roles are assigned -> counts as 2 contacts
                    $totalContacts = $evaluation.EffectiveContactCount
                    Write-Verbose "Total effective contacts for subscription '$($subscription.Name)': $totalContacts"
                    if ($totalContacts -ge 2) {
                        $isCompliant = $true
                        if ([string]::IsNullOrWhiteSpace($Comments)) {
                            $Comments = $msgTable.compliantServiceHealthAlerts
                        }
                    }
                    else {
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
            $Comments = $msgTable.noServiceHealthAlerts -f $subscription.Name
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
            $result = Add-ProfileInformation -Result $C -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subId -ErrorList $ErrorList
            Write-Host "$result"
            $PsObject.Add($result) | Out-Null
        } else {
            $PsObject.Add($C) | Out-Null
        }

    }
    
    $moduleOutput = [PSCustomObject]@{
        ComplianceResults = $PsObject
        Errors = $ErrorList
    }

    return $moduleOutput
}