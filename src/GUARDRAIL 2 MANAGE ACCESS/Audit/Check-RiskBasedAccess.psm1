function Get-RiskBasedAccess {
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
    
    $CAPUrl = '/identity/conditionalAccess/policies'
    try {
        $response = Invoke-GraphQuery -urlPath $CAPUrl -ErrorAction Stop

        $caps = $response.Content.value
    }
    catch {
        $Errorlist.Add("Failed to call Microsoft Graph REST API at URL '$CAPUrl'; returned error message: $_")
        Write-Warning "Error: Failed to call Microsoft Graph REST API at URL '$CAPUrl'; returned error message: $_"
    }

    # list all users in the tenant
    $urlPath = "/users"
    try {
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
        $users = $response.Content.value | Select-Object userPrincipalName , displayName, givenName, surname, id, mail
        
    }
    catch {
        $errorMsg = "Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"                
        $ErrorList.Add($errorMsg)
        Write-Error "Error: $errorMsg"
    }
    # get ID for BG UPNs
    $FirstBreakGlassID = ($users| Where-Object {$_.userPrincipalName -eq $FirstBreakGlassUPN}| Select-Object id).id
    $SecondBreakGlassID = ($users| Where-Object {$_.userPrincipalName -eq $SecondBreakGlassUPN} | Select-Object id).id

    # List of all user groups in the environment
    $groupsUrlPath = "/groups"
    try {
        $response = Invoke-GraphQuery -urlPath $groupsUrlPath -ErrorAction Stop
        $userGroups = $response.Content.value
    }
    catch {
        $errorMsg = "Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"                
        $ErrorList.Add($errorMsg)
        Write-Error "Error: $errorMsg"
    }
    # Find any group (if any) for BG accounts
    $groupMemberList = @()
    foreach ($group in $userGroups){
        $groupId = $group.id
        $urlPath = "/groups/$groupId/members"
        try {
            $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
            $data = $response.Content
            if ($null -ne $data -and $null -ne $data.value) {
                $grMembers = $data.value | Select-Object userPrincipalName , displayName, givenName, surname, id, mail

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
            $errorMsg = "Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"                
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
    $commonFilters = {
        $_.state -eq 'enabled' -and
        $_.conditions.users.includeUsers -contains 'All' -and
        $_.conditions.users.excludeUsers.Count -le 2 -and
        $_.conditions.users.excludeUsers -contains $FirstBreakGlassID -and
        $_.conditions.users.excludeUsers -contains $SecondBreakGlassID -and
        ($_.conditions.applications.includeApplications -contains 'All' -or
        $_.conditions.applications.includeApplications -contains 'MicrosoftAdminPortals') -and
        $_.grantControls.builtInControls -contains 'mfa' -and
        $_.grantControls.builtInControls -contains 'passwordChange' -and
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
    }

    if ($null -ne $breakGlassUserGroup){
        $validPolicies = $caps | Where-Object {
            & $commonFilters -and
            $_.conditions.users.excludeGroups.Count -eq 1 -and
            $_.conditions.users.excludeGroups -contains $uniqueGroupIdBG
        } 
    }
    else{
        $validPolicies = $caps | Where-Object {
            & $commonFilters -and
            [string]::IsNullOrEmpty($_.conditions.users.excludeGroups)
    
        }
    }

    if ($validPolicies.count -ne 0) {
        $IsCompliantPasswordCAP = $true
    }
    else {
        # Failed. Reason: No policies meet the requirements
        $IsCompliantPasswordCAP = $false
    }

    # Check 2: Allowed Location – Conditional Access Policy
    $PsObjectLocation = Get-allowedLocationCAPCompliance -ErrorList $ErrorList -IsCompliant $IsCompliant
    $ErrorList = $PsObjectLocation.Errors

    # Combine status
    if ($IsCompliantPasswordCAP -eq $true -and $PsObjectLocation.ComplianceStatus -eq $true){
        $IsCompliant = $true
        $Comments = $msgTable.isCompliant + " " + $msgTable.compliantC1C2
    }
    elseif($PsObjectLocation.ComplianceStatus -eq $true -and $IsCompliantPasswordCAP -eq $false){
        $IsCompliant = $false
        $Comments = $msgTable.isNotCompliant + " " + $msgTable.nonCompliantC1
    }
    elseif ($IsCompliantPasswordCAP -eq $true -and $PsObjectLocation.ComplianceStatus -eq $false){
        $IsCompliant = $false
        $Comments = $msgTable.isNotCompliant + " " + $msgTable.nonCompliantC2
    }
    else{
        $IsCompliant = $false
        $Comments = $msgTable.isNotCompliant + " " + $msgTable.nonCompliantC1C2
    }
    
    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        Comments         = $Comments
        ItemName         = $ItemName
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }

    # Conditionally add the Profile field based on the feature flag
    if ($EnableMultiCloudProfiles) {
        $result = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        if ($result -gt 0) {
            Write-Output "Valid profile returned: $result"
            $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $result
        } elseif ($result -eq 0) {
            Write-Output "No matching profile found or error occurred"
            $PsObject.ComplianceStatus = "Not Applicable"
        } else {
            Write-Error "Unexpected result: $result"
        }
    }

    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput
}
