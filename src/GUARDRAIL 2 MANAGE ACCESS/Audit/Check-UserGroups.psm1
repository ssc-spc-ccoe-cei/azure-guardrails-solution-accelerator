function Check-UserGroups {
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
        [string] 
        $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] 
        $EnableMultiCloudProfiles # New feature flag, default to false
    )

    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    [bool] $IsCompliant = $false
    [string] $Comments = $null
    [PSCustomObject] $AdditionalResults = $null

    # list all users in the tenant
    
    try {
        $accessToken = (Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com/').Token
    }
    catch {
        $ErrorList.Add("Failed to get access token for Microsoft Graph API: $_")
        return "Error: Failed to get access token for Microsoft Graph API: $_"
    }

    $headers = @{
        Authorization    = "Bearer $accessToken"
        ConsistencyLevel = "eventual"
    }
    
    # Get all users in the tenant (Members and Guests)
    $usersUrl = "https://graph.microsoft.com/v1.0/users?`$select=id,displayName,givenName,userPrincipalName&`$top=999"
    $users = @()
    do {
        try {
            $usersResp = Invoke-RestMethod -Method Get -Uri $usersUrl -Headers $headers
        } catch {
            $ErrorList.Add("Failed to get users: $_")
        }
        if ($usersResp.value) {
            $users += $usersResp.value
        }
        $usersUrl = $usersResp.'@odata.nextLink'
    } while ($usersUrl)

    $memberUrlPath = '/users/$count?$filter=userType eq ''Member'''
    $memberUri = "https://graph.microsoft.com/v1.0$memberUrlPath"
    try {
        $memResp = Invoke-RestMethod -Uri $memberUri -Method Get -Headers $headers
    } catch {
        $ErrorList.Add("Failed to get member count: $_")
    }
    $memberCount = [int]$memResp

    $guestUrlPath = '/users/$count?$filter=userType eq ''Guest'''
    $guestUri = "https://graph.microsoft.com/v1.0$guestUrlPath"
    try {
        $guestResp = Invoke-RestMethod -Uri $guestUri -Method Get -Headers $headers
    } catch {
        $ErrorList.Add("Failed to get guest count: $_")
    }
    $guestCount = [int]$guestResp

    $groupUrlPath = '/groups/$count'
    $groupsUri = "https://graph.microsoft.com/v1.0$groupUrlPath"
    try {
        $groupResp = Invoke-RestMethod -Uri $groupsUri -Method Get -Headers $headers
    } catch {
        $ErrorList.Add("Failed to get group count: $_")
    }
    $groupCount = [int]$groupResp
    
    
    # Find total user count in the environment
    $allUserCount = $memberCount + $guestCount

    Write-Output "Members: $memberCount, Guests: $guestCount, Groups: $groupCount"

    $uniqueUPNs = [System.Collections.Generic.HashSet[string]]::new()


    $groupsUrl = "https://graph.microsoft.com/v1.0/groups?`$select=id&`$top=999"
    do {
        try {
            # Get all groups in the tenant
            $grpResp = Invoke-RestMethod -Method Get -Uri $groupsUrl -Headers $headers
        } catch {
            $ErrorList.Add("Failed to get groups: $_")
        }
    foreach ($g in $grpResp.value) {

        # page members of each group (filter to users only)
        $membersUrl = "https://graph.microsoft.com/v1.0/groups/$($g.id)/members/microsoft.graph.user?`$select=userPrincipalName&`$top=999"

        do {
            try {
                # Get members of the group
                $memResp = Invoke-RestMethod -Method Get -Uri $membersUrl -Headers $headers
            } catch {
                $ErrorList.Add("Failed to get members for group ID '$($g.id)': $_")
            }
            foreach ($u in $memResp.value) {
                if ($u.userPrincipalName) {
                    $uniqueUPNs.Add($u.userPrincipalName) | Out-Null
                }
            }
            $membersUrl = $memResp.'@odata.nextLink'
            # stop paging members early if we’ve seen every user
        } while ($membersUrl -and $uniqueUPNs.Count -lt $allUserCount)

        # break out of the group loop if done
        if ($uniqueUPNs.Count -eq $allUserCount) { break }
    }

    $groupsUrl = $grpResp.'@odata.nextLink'
    } while ($groupsUrl)

    $totalGroupUsers = $uniqueUPNs.Count
    $uniqueUsers = $users | Where-Object { $uniqueUPNs.Contains($_.userPrincipalName) }

    # Condition: if only 1 user in the tenant
    if($allUserCount -le 1) {
        $commentsArray = $msgTable.isCompliant + " " + $msgTable.userCountOne    
        $IsCompliant = $true
    }
    else{
        # Condition: if more than 1 user in the tenant
        if($groupCount -lt 2){
            # Condition: There is less than 2 user group in the tenant
            $IsCompliant = $false
            $commentsArray = $msgTable.isNotCompliant + " " +  $commentsArray  + " " + $msgTable.userGroupsMany
            
            # Identify users without group assignments for remediation
            $usersWithoutGroups = @()
            $users | Where-Object { 
                $null -ne $_.userPrincipalName -and $_.userPrincipalName -ne '' -and
                -not ($uniqueUsers.userPrincipalName -contains $_.userPrincipalName)
            } | ForEach-Object {
                    $userObject = [PSCustomObject]@{
                        UserId = $_.id
                        DisplayName = $_.displayName
                        GivenName = $_.givenName
                        UserPrincipalName = $_.userPrincipalName
                        Comments = $msgTable.userNotInGroup
                        ReportTime = $ReportTime
                        itsgcode = $itsgcode
                    }
                    $usersWithoutGroups += $userObject
            }
                
            if ($usersWithoutGroups -and $usersWithoutGroups.Count -gt 0) {
                $limitedUsers = $usersWithoutGroups | Select-Object -First 20
                $AdditionalResults = [PSCustomObject]@{
                    records = $limitedUsers
                    logType = "GR2UsersWithoutGroups"
                }
            }
        } 
        else {
            # User groups >= 2
            # Condition: all users count == unique users in all groups count
            if( $totalGroupUsers -eq $allUserCount){
                # get conditional access policies
                $CABaseAPIUrl = '/identity/conditionalAccess/policies'
                try {
                    $response = Invoke-GraphQuery -urlPath $CABaseAPIUrl -ErrorAction Stop
                    # portal
                    $data = $response.Content
                    # # localExecution
                    # $data = $response
                    if ($null -ne $data -and $null -ne $data.value) {
                        $caps = $data.value
                        # Check for a conditional access policy which meets the requirements:
                        # 1. state = 'enabled'
                        # 2. includedGroups = not null
                        $validPolicies = $caps | Where-Object {
                            $_.state -eq 'enabled' -and
                            ($_.conditions.users.includeGroups.Count -ge 1 -or
                            $_.conditions.users.excludeGroups.Count -ge 1 )
                        }
                        # Condition: at least one CAP refers to at least one user group
                        if ($validPolicies.count -ne 0) {
                            $IsCompliant = $true
                            $commentsArray = $msgTable.isCompliant + " " +  $commentsArray + " " + $msgTable.reqPolicyUserGroupExists
                        }
                        else {
                            # Fail. No policy meets the requirements
                            $IsCompliant = $false
                            $commentsArray = $msgTable.isNotCompliant + " " +  $commentsArray  + " " +$msgTable.noCAPforAnyGroups
                        }
                    }
                }
                catch {
                    $Errorlist.Add("Failed to call Microsoft Graph REST API at URL '$CABaseAPIUrl'; returned error message: $_")
                    Write-Warning "Error: Failed to call Microsoft Graph REST API at URL '$CABaseAPIUrl'; returned error message: $_"
                }

            } else {
                $IsCompliant = $false
                $commentsArray += " " + $msgTable.userCountGroupNoMatch
                
                # Identify users without group assignments for remediation
                $usersWithoutGroups = @()
                $users | Where-Object { 
                    $null -ne $_.userPrincipalName -and $_.userPrincipalName -ne '' -and
                    -not ($uniqueUsers.userPrincipalName -contains $_.userPrincipalName)
                } | ForEach-Object {
                    $userObject = [PSCustomObject]@{
                        UserId = $_.id
                        DisplayName = $_.displayName
                        GivenName = $_.givenName
                        UserPrincipalName = $_.userPrincipalName
                        Comments = $msgTable.userNotInGroup
                        ReportTime = $ReportTime
                        itsgcode = $itsgcode
                    }
                    $usersWithoutGroups += $userObject
                }
                
                if ($usersWithoutGroups -and $usersWithoutGroups.Count -gt 0) {
                    $limitedUsers = $usersWithoutGroups | Select-Object -First 20
                    $AdditionalResults = [PSCustomObject]@{
                        records = $limitedUsers
                        logType = "GR2UsersWithoutGroups"
                    }
                }
            }
        }
        
    }

    $commentsArray += $msgTable.userStats -f $allUserCount, $totalGroupUsers, $memberCount, $guestCount
    $Comments = $commentsArray -join ";"
    
    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        ItemName         = $ItemName
        Comments         = $Comments
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
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
    
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput   
}