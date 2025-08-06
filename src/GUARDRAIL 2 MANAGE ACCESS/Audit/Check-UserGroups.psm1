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
    $urlPath = "/users"
    try {
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
        # portal
        $data = $response.Content
        # # localExecution
        # $data = $response

        if ($null -ne $data -and $null -ne $data.value) {
            $users = $data.value | Select-Object userPrincipalName , displayName, givenName, surname, id, mail
        }
    }
    catch {
        $errorMsg = "Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"                
        $ErrorList.Add($errorMsg)
        Write-Error "Error: $errorMsg"
    }
    Write-Host "users count is $($users.Count)"
    
    # Find total user count in the environment
    $allUserCount = $users.Count
    Write-Host "userCount is $allUserCount"

    # List of all user groups in the environment
    $urlPath = "/groups"
    try {
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
        # portal
        $data = $response.Content
        # # localExecution
        # $data = $response

        if ($null -ne $data -and $null -ne $data.value) {
            $groups = $data.value #| Select-Object userPrincipalName , displayName, givenName, surname, id, mail
        }
    }
    catch {
        $errorMsg = "Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"                
        $ErrorList.Add($errorMsg)
        Write-Error "Error: $errorMsg"
    }
    # Find total user groups count are in the environment
    $userGroupCount = $groups.Count
    Write-Host "number of user groups in the tenant are $userGroupCount"

    # Find members in each group
    $groupMemberList = @()
    foreach ($group in $groups){
        $groupId = $group.id
        $urlPath = "/groups/$groupId/members"
        try {
            $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
            # portal
            $data = $response.Content
            # # localExecution
            # $data = $response

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
    # Find unique users from all user groups by unique userPrincipalName
    $uniqueUsers = $groupMemberList | Sort-Object userPrincipalName -Unique
    Write-Host "number of unique users calculated from user groups are $($uniqueUsers.Count)"
    # filter unique users which have UPN only (e.g exclude mailbox email etc.)
    $uniqueUsers = $uniqueUsers | Where-Object { $_.userPrincipalName -ne $null -and $_.userPrincipalName -ne '' }
    
    # Condition: if only 1 user in the tenant
    if($allUserCount -le 1) {
        $commentsArray = $msgTable.isCompliant + " " + $msgTable.userCountOne    
        $IsCompliant = $true
    }
    else{
        # Condition: if more than 1 user in the tenant
        if($userGroupCount -lt 2){
            # Condition: There is less than 2 user group in the tenant
            $IsCompliant = $false
            $commentsArray = $msgTable.isNotCompliant + " " +  $commentsArray  + " " + $msgTable.userGroupsMany
            
            # Identify users without group assignments for remediation
            $usersWithoutGroups = @()
            $users | Where-Object { 
                $_.userPrincipalName -ne $null -and $_.userPrincipalName -ne '' -and
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
            if( $uniqueUsers.Count -eq $allUserCount){
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
                    $_.userPrincipalName -ne $null -and $_.userPrincipalName -ne '' -and
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

    $Comments = $commentsArray -join ";"
    
    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        ItemName         = $ItemName
        Comments         = $Comments
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }

    # Add profile information if MCUP feature is enabled
    if ($EnableMultiCloudProfiles) {
        $result = Add-ProfileInformation -Result $PsObject -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId
        Write-Host "$result"
    }
    
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput   
}