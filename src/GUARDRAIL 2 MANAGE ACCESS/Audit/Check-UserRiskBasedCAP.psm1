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
    # 7. signInRiskLevels = @()
    # 8. platforms = null
    # 9. locations = null
    # 10. devices = null
    # 11. clientApplications = null
    # 12. signInFrequency.frequencyInterval = 'everyTime'
    # 13. signInFrequency.isEnabled = true
    # 14. signInFrequency.authenticationType = 'primaryAndSecondaryAuthentication'
    # 15. includeGroups = null
    # 16. excludeApplications = null
    # 17. includeRoles = null
    # 18. excludeRoles = null
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
            [string]::IsNullOrEmpty($_.conditions.signInRiskLevels) -and
            [string]::IsNullOrEmpty($_.conditions.platforms) -and
            [string]::IsNullOrEmpty($_.conditions.locations) -and
            [string]::IsNullOrEmpty($_.conditions.devices)  -and
            [string]::IsNullOrEmpty($_.conditions.clientApplications) -and
            [string]::IsNullOrEmpty($_.conditions.users.includedGroups) -and
            [string]::IsNullOrEmpty($_.conditions.applications.excludeApplications) -and
            [string]::IsNullOrEmpty($_.conditions.users.includeRoles) -and
            [string]::IsNullOrEmpty($_.conditions.users.excludeRoles) -and
            [string]::IsNullOrEmpty($_.conditions.users.includeGuestsOrExternalUsers) -and
            [string]::IsNullOrEmpty($_.conditions.users.excludeGuestsOrExternalUsers)
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

    # validate BG account user group
    $BGAccountUserGroup = $groupMemberList | Where-Object {$_.userPrincipalName -eq $FirstBreakGlassUPN -or $_.userPrincipalName -eq $SecondBreakGlassUPN}
    if($BGAccountUserGroup.Count -eq 2){
        $breakGlassUserGroup = $BGAccountUserGroup
    }
    else{
        $breakGlassUserGroup = $null
    }
    $uniqueGroupIdBG = $breakGlassUserGroup.groupId | select-object -unique
    
    # check for a conditional access policy which meets the requirements
    if ($null -ne $breakGlassUserGroup){
        $validPolicies = (Test-CommonFilters -policy $caps -FirstBreakGlassID $FirstBreakGlassID -SecondBreakGlassID $SecondBreakGlassID) 
        if ($validPolicies){
            $validPolicies = $validPolicies | Where-Object {
                $_.conditions.users.excludeGroups.Count -eq 1 -and
                $_.conditions.users.excludeGroups -contains $uniqueGroupIdBG
            }
        } 
    }
    else{
        $validPolicies = (Test-CommonFilters -policy $caps -FirstBreakGlassID $FirstBreakGlassID -SecondBreakGlassID $SecondBreakGlassID) 
        if ($validPolicies){
            $validPolicies = $validPolicies | Where-Object {
                [string]::IsNullOrEmpty($_.conditions.users.excludeGroups)
            }
        }
    }


    Write-Host "validPolicies.count: $($validPolicies.count)"
    if ($validPolicies -and $validPolicies.count -ne 0){
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