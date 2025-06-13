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

    # list all users in the tenant
    $urlPath = '/users?$select=userPrincipalName,displayName,givenName,surname,id,mail,userType'
    try {
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop

        if ($null -ne $response.Content -and $null -ne $response.Content.value) {
            $users = $response.Content.value
        }
    }
    catch {
        $errorMsg = "Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"                
        $ErrorList.Add($errorMsg)
        Write-Error "Error: $errorMsg"
    }
    Write-LogInfo "users count is $($users.Count)"
    
    # Find total user count in the environment
    $allUserCount = $users.Count
    Write-LogInfo "userCount is $allUserCount"
    $memberCount = ($users | Where-Object { $_.userType -eq 'Member' }).Count
    $guestCount = ($users | Where-Object { $_.userType -eq 'Guest' }).Count


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
    Write-LogInfo "number of user groups in the tenant are $userGroupCount"

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
    Write-LogInfo "number of unique users calculated from user groups are $($uniqueUsers.Count)"
    # filter unique users which have UPN only (e.g exclude mailbox email etc.)
    $uniqueUsers = $uniqueUsers | Where-Object { $null -ne $_.userPrincipalName -and $_.userPrincipalName -ne '' }
    $totalGroupUserCount = $uniqueUsers.Count
    
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
            }
        }
        
    }

    $statsComments = "\n User stats - Total Users: $allUserCount; Group Users (Total - Unique): $totalGroupUserCount; Members in Tenants: $memberCount; Guests in Tenants: $guestCount" 
    $commentsArray += $statsComments
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