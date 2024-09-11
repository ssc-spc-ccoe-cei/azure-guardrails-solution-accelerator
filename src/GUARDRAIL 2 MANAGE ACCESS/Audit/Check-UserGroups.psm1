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
        [Parameter(Mandatory=$true)]
        [string] $FirstBreakGlassUPN,
        [Parameter(Mandatory=$true)] 
        [string] $SecondBreakGlassUPN,
        [string] 
        $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] 
        $EnableMultiCloudProfiles # New feature flag, default to false
    )

    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    [bool] $IsCompliant = $false
    [string] $Comments = $null

    # Find how many users there are in the environment
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
    Write-Host "DEBUG: users count is $($users.Count)"

    # ## *************************##
    # ## ****** Member user ******##
    # ## *************************##
    # $memberUsers = $users | Where-Object { $_.userPrincipalName -notlike "*#EXT#*" }

    # # Get member users UPNs
    # $memberUserList = $memberUsers | Select-Object userPrincipalName, mail
    # # Exclude the breakglass account UPNs from the list
    # if ($memberUserList.userPrincipalName -contains $FirstBreakGlassUPN){
    #     $memberUserList = $memberUserList | Where-Object { $_.userPrincipalName -ne $FirstBreakGlassUPN }
    # }
    # if ($memberUserList.userPrincipalName -contains $SecondBreakGlassUPN){
    #     $memberUserList = $memberUserList | Where-Object { $_.userPrincipalName -ne $SecondBreakGlassUPN }

    # }
    # Write-Host "DEBUG: memberUserList with BG accounts count is $($memberUsers.Count)"

    # Write-Host "DEBUG: memberUserList without BG accounts count is $($memberUserList.Count)"

    
    # ## ***************************##
    # ## ****** External user ******##
    # ## ***************************##
    # $extUsers = $users | Where-Object { $_.userPrincipalName -like "*#EXT#*" }
    # Write-Output "DEBUG: extUsers count is $($extUsers.Count)"
    # Write-Output "DEBUG: extUsers UPNs are $($extUsers.userPrincipalName)"


    
    $allUserCount = $users.Count
    Write-Output "DEBUG: userCount is $allUserCount"
    # Find how many user groups there are in the environment
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

    $userGroupCount = $groups.Count
    Write-Output "DEBUG: number of user groups in the tenant are $userGroupCount"
    Write-Output "DEBUG: the user groups in the tenant are $($groups.displayName)"
    Write-Output "DEBUG: ***************************************************************"


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
    # find unique users from all user groups
    # Get unique users based on userPrincipalName
    $uniqueUsers = $groupMemberList | Sort-Object userPrincipalName -Unique
    
    # Condition: There is only 1 user in the tenant
    if($allUserCount -le 1) {
        $commentsArray = "Compliant. There is only one user in the tenant."
        $IsCompliant = $true
    }
    else{
        # Condition: There is more than 1 user in the tenant
        $commentsArray += " " + "There are more than one user in the tenant"
        if($userGroupCount -lt 2){
            # Condition: There is less than 2 user group in the tenant
            $IsCompliant = $false
            $commentsArray += " " + "There should be at least 2 user group in the tenant"
        } else {
                # Contdition: User group >= 2
                # Condition: no. of all users == no. of unique users in all groups
                if( $uniqueUsers.Count -eq $allUserCount){
                    # Condition: CAP
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
                            # 1. includedGroups = not null
                            # 2. excludeGroups = null
                            $validPolicies = $caps | Where-Object {
                                $_.state -eq 'enabled' -and
                                $null -ne $_.conditions.users.includeGroups -and
                                [string]::IsNullOrEmpty($_.conditions.users.excludeGroups) 
                            }

                            $groupsInValidPolicy = $validPolicies.conditions.users.includeGroups
                            Write-Host "The groups in the policies are $($validPolicies.displayName -join ", ")"

                            if ($validPolicies.count -ne 0) {
                                if ($groupsInValidPolicy.Count -eq $groups.Count ){
                                    # Condition: total group countin the tenant and in the CAP policy should match
                                    $IsCompliant = $true
                                    $Comments = $msgTable.isCompliant  
                                } else{
                                    # group count doesn't match 
                                    $IsCompliant = $false
                                    $Comments += " " + "All groups must be assigned to CAP"
                                }
                            }
                            else {
                                # Failed. Reason: No policies meet the requirements
                                $IsCompliant = $false
                                $Comments = $msgTable.noCAPforAllGroups
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
        $result = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        if ($result -eq 0) {
            Write-Output "No matching profile found"
            $PsObject.ComplianceStatus = "Not Applicable"
        } else {
            Write-Output "Valid profile returned: $result"
            $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $result
        }
    }
    
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput   
}