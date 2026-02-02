function Get-SubscriptionOwnerCount {
    <#
    .SYNOPSIS
        Returns the number of owners assigned to the current subscription.
    .DESCRIPTION
        Queries Azure RBAC to count how many principals have the Owner role
        at the subscription scope. This is used to determine how many contacts
        the "Owner" notification target actually represents.
    #>
    [CmdletBinding()]
    param()

    # Azure built-in Owner role ID (constant across all Azure tenants)
    $ownerRoleId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'

    try {
        $ownerAssignments = Get-AzRoleAssignment -RoleDefinitionId $ownerRoleId -ErrorAction Stop 
        return @($ownerAssignments).Count
    }
    catch {
        Write-Output "Failed to retrieve subscription owner assignments: $_"
        return 0
    }
}

function Get-ActionGroupContactTokens {
    <#
    .SYNOPSIS
        Extracts contact tokens from an Azure Action Group.
    .DESCRIPTION
        Gathers all notification targets (email addresses and owner-role tokens)
        from the specified action group(s). Returns a unified set of "contact tokens"
        that can be used for counting unique contacts. Email addresses are returned
        as-is, while Owner role receivers are prefixed with "Owner::" to distinguish
        them from direct email contacts.
    #>
    param (
        [Parameter(Mandatory=$true)]
        [Object[]] $ActionGroup
    )

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
    <#
    .SYNOPSIS
        Validates action groups associated with service health alerts.
    .DESCRIPTION
        Evaluates each action group's notification contacts and returns aggregate
        compliance results. When subscription owners are configured as notification
        targets, the effective contact count depends on the actual number of owners
        assigned to the subscription:
        - 1 owner assigned -> counts as 1 contact
        - 2 or more owners assigned -> counts as 2 contacts
        Returns a PSCustomObject containing unique contacts, effective contact count,
        comments, and any errors encountered during validation.
    #>
    param (
        [Object[]] $alerts,
        [Parameter(Mandatory=$true)][string] $SubscriptionName,
        [Parameter(Mandatory=$true)][string] $SubscriptionId,
        [Parameter(Mandatory=$true)][hashtable] $MsgTable
    )

    # Evaluate each action group's contacts and surface aggregate results back to the caller.
    # When subscription owners are used as notification targets, the effective contact count
    # depends on the actual number of owners assigned to the subscription:
    #   - 1 owner assigned -> counts as 1 contact
    #   - 2 or more owners assigned -> counts as 2 contacts

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
        $allEnabledActionGroups = Get-AzActionGroup | Where-Object { $_.Enabled -eq $true }
        # Get action group IDs
        $actionGroupIdsArray = [System.Collections.ArrayList]@($actionGroupIds | Where-Object { $_ -in $allEnabledActionGroups.Id })
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
    

    # Separate owner tokens from other contact tokens (e.g., email addresses)
    $ownerTokens = @($uniqueContacts | Where-Object { $_ -like 'Owner::*' })
    $nonOwnerTokens = @($uniqueContacts | Where-Object { $_ -notlike 'Owner::*' })

    # Calculate effective contact count
    # Non-owner contacts (emails, etc.) count as 1 each
    $effectiveContactCount = $nonOwnerTokens.Count

    # If subscription owners are being used as notification targets, check actual owner count
    if ($ownerTokens.Count -gt 0) {
        $subscriptionOwnerCount = Get-SubscriptionOwnerCount
        
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

    return [PSCustomObject]@{
        UniqueContacts = @($uniqueContacts)
        EffectiveContactCount = $effectiveContactCount
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
        $checkActionGroupNext = $false

        # find subscription information
        $subId = $subscription.Id
        Set-AzContext -SubscriptionId $subId

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

            # Condition: Non-compliant if no health alert found for any sub
            if($null -eq $filteredAlerts){
                $isCompliant = $false
                $Comments = $msgTable.noEnabledHealthAlert
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
                    $evaluation = Validate-ActionGroups -alerts $filteredAlerts -SubscriptionName $subscription.Name -SubscriptionId $subId -MsgTable $msgTable

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
                    # - If owners are used and only 1 owner is assigned -> counts as 1 contact
                    # - If owners are used and 2+ owners are assigned -> counts as 2 contacts
                    $totalContacts = $evaluation.EffectiveContactCount
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