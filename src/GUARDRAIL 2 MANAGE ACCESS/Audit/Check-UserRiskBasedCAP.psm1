function Test-IsNullOrEmptyArray {
    <#
    .SYNOPSIS
        Helper function to check if a value is null or an empty array.
        Handles both null values and empty arrays returned by Microsoft Graph API.
    #>
    param(
        [AllowNull()]
        $Value
    )
    
    if ($null -eq $Value) {
        return $true
    }
    
    if ($Value -is [array] -and $Value.Count -eq 0) {
        return $true
    }
    
    if ($Value -is [string] -and [string]::IsNullOrEmpty($Value)) {
        return $true
    }
    
    return $false
}

function Test-CommonFilters {
    param(
        [PSCustomObject]$policy,
        [string] $FirstBreakGlassID,
        [string] $SecondBreakGlassID

    )

    
    # check for a conditional access policy which meets these requirements:
    # 1. state =  'enabled'
    # 2. includedUsers = 'All'
    # 3. applications.includedApplications = 'All'
    # 4. grantControls.builtInControls contains 'mfa' and 'passwordChange'
    # 5. clientAppTypes contains 'all'
    # 6. userRiskLevels = 'high'
    # 7. signInRiskLevels = @() or null
    # 8. platforms = null
    # 9. locations = null
    # 10. devices = null
    # 11. clientApplications = null
    # 12. signInFrequency.frequencyInterval = 'everyTime'
    # 13. signInFrequency.isEnabled = true
    # 14. signInFrequency.authenticationType = 'primaryAndSecondaryAuthentication'
    # 15. includeGroups = null or empty
    # 16. excludeApplications = null or empty
    # 17. includeRoles = null or empty
    # 18. excludeRoles = null or empty
    # 19. includeGuestsOrExternalUsers = null
    # 20. excludeGuestsOrExternalUsers = null
    # 21. excludeUsers/excludeGroups
    $validPolicies =  $policy | Where-Object {
        (
            $_.state -eq "enabled" -and
            $_.conditions.users.includeUsers -contains 'All' -and
            $_.conditions.users.excludeUsers.Count -le 2 -and
            $_.conditions.users.excludeUsers -contains $FirstBreakGlassID -and
            $_.conditions.users.excludeUsers -contains $SecondBreakGlassID -and
            ($_.conditions.applications.includeApplications -contains 'All' -or
            $_.conditions.applications.includeApplications -contains 'MicrosoftAdminPortals') -and
            (
                (
                    $_.grantControls.builtInControls -contains 'mfa' -and
                    $_.grantControls.builtInControls -contains 'passwordChange'
                ) -or
                $_.grantControls.builtInControls -contains 'block'
            ) -and
            $_.conditions.clientAppTypes -contains 'all' -and
            $_.conditions.userRiskLevels -contains 'high' -and
            $_.sessionControls.signInFrequency.frequencyInterval -contains 'everyTime' -and
            $_.sessionControls.signInFrequency.authenticationType -contains 'primaryAndSecondaryAuthentication' -and
            $_.sessionControls.signInFrequency.isEnabled -eq $true -and
            (Test-IsNullOrEmptyArray $_.conditions.signInRiskLevels) -and
            (Test-IsNullOrEmptyArray $_.conditions.platforms) -and
            (Test-IsNullOrEmptyArray $_.conditions.locations) -and
            (Test-IsNullOrEmptyArray $_.conditions.devices) -and
            (Test-IsNullOrEmptyArray $_.conditions.clientApplications) -and
            (Test-IsNullOrEmptyArray $_.conditions.users.includeGroups) -and
            (Test-IsNullOrEmptyArray $_.conditions.applications.excludeApplications) -and
            (Test-IsNullOrEmptyArray $_.conditions.users.includeRoles) -and
            (Test-IsNullOrEmptyArray $_.conditions.users.excludeRoles) -and
            (Test-IsNullOrEmptyArray $_.conditions.users.includeGuestsOrExternalUsers) -and
            (Test-IsNullOrEmptyArray $_.conditions.users.excludeGuestsOrExternalUsers)
        )
    }
    return $validPolicies
} 
    
function Get-UserRiskBasedCAP {
    param (      
        [Parameter(Mandatory=$true)]
        [string] $ControlName,
        [Parameter(Mandatory=$true)]
        [string] $ItemName,
        [Parameter(Mandatory=$true)]
        [string] $itsgcode,
        [Parameter(Mandatory=$true)]
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string] $ReportTime,
        [Parameter(Mandatory=$true)]
        [string] $FirstBreakGlassUPN,
        [Parameter(Mandatory=$true)] 
        [string] $SecondBreakGlassUPN,
        [string] $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] $EnableMultiCloudProfiles # New feature flag, default to false    
    )
    $IsCompliant = $false
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList

    # Check 1: Password Changes –Conditional Access Policy
    $IsCompliantPasswordCAP = $false

    # Get conditional access policies (using paginated query to handle >100 policies)
    $CAPUrl = '/identity/conditionalAccess/policies'
    try {
        $response = Invoke-GraphQueryEX -urlPath $CAPUrl -ErrorAction Stop
        $caps = if ($response.Content -and $response.Content.value) { $response.Content.value } else { @() }
    }
    catch {
        $Errorlist.Add("Failed to call Microsoft Graph REST API at URL '$CAPUrl'; returned error message: $_")
        Write-Warning "Error: Failed to call Microsoft Graph REST API at URL '$CAPUrl'; returned error message: $_"
    }
    Write-Host "Existing CAP count $($caps.count)"

    # list all users in the tenant (using paginated query to handle >100 users)
    $urlPath = "/users"
    try {
        $response = Invoke-GraphQueryEX -urlPath $urlPath -ErrorAction Stop
        $data = $response.Content
        $users = if ($data -and $data.value) { $data.value | Select-Object userPrincipalName, displayName, givenName, surname, id, mail } else { @() }
    }
    catch {
        $errorMsg = "Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"                
        $ErrorList.Add($errorMsg)
        Write-Error "Error: $errorMsg"
    }
    # get ID for BG UPNs
    $FirstBreakGlassID = ($users| Where-Object {$_.userPrincipalName -eq $FirstBreakGlassUPN}| Select-Object id).id
    $SecondBreakGlassID = ($users| Where-Object {$_.userPrincipalName -eq $SecondBreakGlassUPN} | Select-Object id).id
    
    # Diagnostic logging for break glass account resolution
    Write-Host "Break Glass UPN 1: $FirstBreakGlassUPN -> ID: $FirstBreakGlassID"
    Write-Host "Break Glass UPN 2: $SecondBreakGlassUPN -> ID: $SecondBreakGlassID"
    if ([string]::IsNullOrEmpty($FirstBreakGlassID)) {
        Write-Warning "Could not resolve FirstBreakGlassUPN '$FirstBreakGlassUPN' to a user ID"
    }
    if ([string]::IsNullOrEmpty($SecondBreakGlassID)) {
        Write-Warning "Could not resolve SecondBreakGlassUPN '$SecondBreakGlassUPN' to a user ID"
    }

    # List of all user groups in the environment (using paginated query to handle >100 groups)
    $groupsUrlPath = "/groups"
    try {
        $response = Invoke-GraphQueryEX -urlPath $groupsUrlPath -ErrorAction Stop
        $data = $response.Content
        $userGroups = if ($data -and $data.value) { $data.value } else { @() }
    }
    catch {
        $errorMsg = "Failed to call Microsoft Graph REST API at URL '$groupsUrlPath'; returned error message: $_"                
        $ErrorList.Add($errorMsg)
        Write-Error "Error: $errorMsg"
    }
    # Find any group (if any) for BG accounts
    $groupMemberList = @()
    foreach ($group in $userGroups){
        $groupId = $group.id
        $membersUrlPath = "/groups/$groupId/members"
        try {
            # Using paginated query to handle >100 members per group
            $response = Invoke-GraphQueryEX -urlPath $membersUrlPath -ErrorAction Stop
            $data = $response.Content
            if ($null -ne $data -and $null -ne $data.value) {
                $grMembers = $data.value | Select-Object userPrincipalName, displayName, givenName, surname, id, mail

                foreach ($grMember in $grMembers) {
                    $groupMembers = [PSCustomObject]@{
                        groupName           = $group.displayName
                        groupId             = $group.id
                        userId              = $grMember.id
                        displayName         = $grMember.displayName
                        givenName           = $grMember.givenName
                        surname             = $grMember.surname
                        mail                = $grMember.mail
                        userPrincipalName   = $grMember.userPrincipalName
                    }
                    $groupMemberList +=  $groupMembers
                }
            }
        }
        catch {
            $errorMsg = "Failed to call Microsoft Graph REST API at URL '$membersUrlPath'; returned error message: $_"                
            $ErrorList.Add($errorMsg)
            Write-Error "Error: $errorMsg" 
        }
    }

    # Check if both BG accounts share at least one common group
    # This is more robust than the previous Count -eq 2 check which could fail if:
    # - BG accounts are in multiple groups
    # - BG accounts are in different groups (false positive with count=2)
    $bg1Groups = @($groupMemberList | Where-Object {$_.userPrincipalName -eq $FirstBreakGlassUPN} | Select-Object -ExpandProperty groupId)
    $bg2Groups = @($groupMemberList | Where-Object {$_.userPrincipalName -eq $SecondBreakGlassUPN} | Select-Object -ExpandProperty groupId)
    
    # Find groups that contain BOTH BG accounts
    $commonBGGroups = @($bg1Groups | Where-Object { $bg2Groups -contains $_ } | Select-Object -Unique)
    
    # Diagnostic logging for BG group membership
    Write-Host "BG1 is in $($bg1Groups.Count) group(s): $($bg1Groups -join ', ')"
    Write-Host "BG2 is in $($bg2Groups.Count) group(s): $($bg2Groups -join ', ')"
    Write-Host "Common groups containing both BG accounts: $($commonBGGroups.Count)"
    
    if ($commonBGGroups.Count -gt 0) {
        Write-Host "Both BG accounts share group(s): $($commonBGGroups -join ', ')"
        $uniqueGroupIdBG = $commonBGGroups
    } else {
        Write-Host "BG accounts do NOT share any common group"
        $uniqueGroupIdBG = $null
    }
    
    # check for a conditional access policy which meets the requirements
    # Note: Test-CommonFilters already validates that BG accounts are excluded by user ID (excludeUsers)
    # If BG accounts share a common group, we accept EITHER:
    #   - Policy excludes one of the common BG groups (excludeGroups contains the group)
    #   - OR Policy excludes BG users individually (excludeUsers) with no extra groups excluded
    # This provides flexibility for customers who exclude BG accounts by user ID rather than group
    
    $validPolicies = @(Test-CommonFilters -policy $caps -FirstBreakGlassID $FirstBreakGlassID -SecondBreakGlassID $SecondBreakGlassID)
    Write-Host "Policies passing common filters: $($validPolicies.Count)"
    
    if ($validPolicies.Count -gt 0){
        if ($commonBGGroups.Count -gt 0){
            # Both BG accounts share at least one group - accept either group exclusion OR user exclusion with no extra groups
            $validPolicies = @( $validPolicies | Where-Object {
                # Option 1: Policy excludes at least one of the common BG groups
                $policyExcludesCommonGroup = $false
                foreach ($bgGroup in $commonBGGroups) {
                    if ($_.conditions.users.excludeGroups -contains $bgGroup) {
                        $policyExcludesCommonGroup = $true
                        break
                    }
                }
                # Also verify excludeGroups only contains BG groups (no extra groups)
                $onlyBGGroupsExcluded = $true
                if (-not (Test-IsNullOrEmptyArray $_.conditions.users.excludeGroups)) {
                    foreach ($excludedGroup in $_.conditions.users.excludeGroups) {
                        if ($commonBGGroups -notcontains $excludedGroup) {
                            $onlyBGGroupsExcluded = $false
                            break
                        }
                    }
                }
                
                ($policyExcludesCommonGroup -and $onlyBGGroupsExcluded) -or
                # Option 2: Policy excludes BG users individually (already validated in Test-CommonFilters)
                #           and has no excludeGroups (to avoid excluding additional users unintentionally)
                (Test-IsNullOrEmptyArray $_.conditions.users.excludeGroups)
            }
            Write-Host "Policies after BG exclusion check (group or user): $($validPolicies.Count)"
        }
        else{
            # BG accounts do not share any group - excludeGroups must be empty
            $validPolicies = @( $validPolicies | Where-Object {
                (Test-IsNullOrEmptyArray $_.conditions.users.excludeGroups)
            }
            Write-Host "Policies after excludeGroups empty check: $($validPolicies.Count)"
        }
    }


    Write-Host "validPolicies.count: $($validPolicies.count)"
    if ($validPolicies.Count -gt 0){
        $IsCompliantPasswordCAP = $true
    }
    else {
        # Failed. Reason: No policies meet the requirements
        $IsCompliantPasswordCAP = $false
    }

    if ($IsCompliantPasswordCAP -eq $true){
        $IsCompliant = $IsCompliantPasswordCAP
        $Comments = $msgTable.isCompliant + " " + $msgTable.compliantC1
    }
    else{
        $Comments = $msgTable.isNotCompliant + " " + $msgTable.nonCompliantC1
    }

    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        Comments         = $Comments
        ItemName         = $ItemName
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }

    # Add profile information if MCUP feature is enabled
    if ($EnableMultiCloudProfiles) {
        $result = Add-ProfileInformation -Result $PsObject -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId -ErrorList $ErrorList
        Write-Host "$result"
    }

    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput
}