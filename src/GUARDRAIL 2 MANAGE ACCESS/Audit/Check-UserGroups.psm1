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

    # Seed AdditionalResults so the LA table always exists
    $AdditionalResults = [PSCustomObject]@{
        logType = "GR2UsersWithoutGroups"
        records = @([PSCustomObject]@{
            UserId            = "N/A"
            DisplayName       = "N/A"
            GivenName         = "N/A"
            UserPrincipalName = "N/A"
            Comments          = $msgTable.userInGroup
            ReportTime        = $ReportTime
            itsgcode          = $itsgcode
        })
    }

    # list all users in the tenant
    
    try {
        # The PowerShell 7.6 migration also upgrades the Runtime Environment's Az modules.
        # Use their secure token path so this check no longer depends on the older plain-text token response.
        # This is an Az compatibility change; it does not change which users or groups are checked.
        # ErrorAction Stop makes a token failure reach the catch block and return a clear module error.
        $accessToken = (Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com/' -AsSecureString -ErrorAction Stop).Token
    }
    catch {
        $ErrorList.Add("Failed to get access token for Microsoft Graph API: $_")
        return "Error: Failed to get access token for Microsoft Graph API: $_"
    }

    $headers = @{
        ConsistencyLevel = "eventual"
    }

    # Small local retry wrapper for this module's direct Graph calls.
    function Invoke-GraphGetWithRetry {
        param (
            [Parameter(Mandatory=$true)]
            [string] $Uri,
            [Parameter(Mandatory=$true)]
            [hashtable] $Headers,
            [int] $MaxRetries = 3,
            [int] $RetryDelaySeconds = 5
        )

        for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
            try {
                # Pass the secure token directly to PowerShell instead of rebuilding the old plain-text authorization header.
                return Invoke-RestMethod -Method Get -Uri $Uri -Authentication Bearer -Token $accessToken -Headers $Headers -ErrorAction Stop
            } catch {
                if ($attempt -eq $MaxRetries) {
                    throw
                }

                Write-Warning "Transient error calling Microsoft Graph URI '$Uri': $($_.Exception.Message). Retrying in $RetryDelaySeconds seconds... (Attempt $attempt of $MaxRetries)"
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
    }

    # Fetch only enough users to show remediation examples instead of loading every user.
    function Get-FirstUserWithoutGroup {
        param (
            [Parameter(Mandatory=$true)]
            [hashtable] $Headers,
            [Parameter(Mandatory=$true)]
            [System.Collections.Generic.HashSet[string]] $GroupedUPNs,
            [Parameter(Mandatory=$true)]
            [string] $ReportTime,
            [Parameter(Mandatory=$true)]
            [string] $itsgcode,
            [Parameter(Mandatory=$true)]
            [string] $Comments,
            [Parameter(Mandatory=$true)]
            [System.Collections.IList] $ErrorList,
            [int] $Limit = 20
        )

        $usersWithoutGroups = [System.Collections.Generic.List[object]]::new()
        $usersUrl = "https://graph.microsoft.com/v1.0/users?`$select=id,displayName,givenName,userPrincipalName&`$top=999"

        do {
            $usersResp = $null
            try {
                $usersResp = Invoke-GraphGetWithRetry -Uri $usersUrl -Headers $Headers
            } catch {
                [void]$ErrorList.Add("Failed to get users: $_")
                break
            }

            foreach ($user in $usersResp.value) {
                if ($usersWithoutGroups.Count -ge $Limit) {
                    break
                }

                if ($null -ne $user.userPrincipalName -and $user.userPrincipalName -ne '' -and -not $GroupedUPNs.Contains($user.userPrincipalName)) {
                    $usersWithoutGroups.Add([PSCustomObject]@{
                        UserId = $user.id
                        DisplayName = $user.displayName
                        GivenName = $user.givenName
                        UserPrincipalName = $user.userPrincipalName
                        Comments = $Comments
                        ReportTime = $ReportTime
                        itsgcode = $itsgcode
                    }) | Out-Null
                }
            }

            $usersUrl = if ($usersWithoutGroups.Count -lt $Limit) { $usersResp.'@odata.nextLink' } else { $null }
        } while ($usersUrl)

        return $usersWithoutGroups.ToArray()
    }

    # Build the optional remediation table only on non-compliant paths.
    function Get-UserWithoutGroupAdditionalResult {
        param (
            [Parameter(Mandatory=$true)]
            [hashtable] $Headers,
            [Parameter(Mandatory=$true)]
            [System.Collections.Generic.HashSet[string]] $GroupedUPNs,
            [Parameter(Mandatory=$true)]
            [string] $ReportTime,
            [Parameter(Mandatory=$true)]
            [string] $itsgcode,
            [Parameter(Mandatory=$true)]
            [hashtable] $msgTable,
            [Parameter(Mandatory=$true)]
            [System.Collections.IList] $ErrorList
        )

        $limitedUsers = Get-FirstUserWithoutGroup -Headers $Headers -GroupedUPNs $GroupedUPNs -ReportTime $ReportTime -itsgcode $itsgcode -Comments $msgTable.userNotInGroup -ErrorList $ErrorList
        if ($limitedUsers -and $limitedUsers.Count -gt 0) {
            return [PSCustomObject]@{
                records = $limitedUsers
                logType = "GR2UsersWithoutGroups"
            }
        }

        return $null
    }

    $memberUrlPath = '/users/$count?$filter=userType eq ''Member'''
    $memberUri = "https://graph.microsoft.com/v1.0$memberUrlPath"
    try {
        $memResp = Invoke-GraphGetWithRetry -Uri $memberUri -Headers $headers
    } catch {
        $ErrorList.Add("Failed to get member count: $_")
    }
    $memberCount = [int]$memResp

    $guestUrlPath = '/users/$count?$filter=userType eq ''Guest'''
    $guestUri = "https://graph.microsoft.com/v1.0$guestUrlPath"
    try {
        $guestResp = Invoke-GraphGetWithRetry -Uri $guestUri -Headers $headers
    } catch {
        $ErrorList.Add("Failed to get guest count: $_")
    }
    $guestCount = [int]$guestResp

    $groupUrlPath = '/groups/$count'
    $groupsUri = "https://graph.microsoft.com/v1.0$groupUrlPath"
    try {
        $groupResp = Invoke-GraphGetWithRetry -Uri $groupsUri -Headers $headers
    } catch {
        $ErrorList.Add("Failed to get group count: $_")
    }
    $groupCount = [int]$groupResp
    
    
    # Find total user count in the environment
    $allUserCount = $memberCount + $guestCount

    Write-Output "Members: $memberCount, Guests: $guestCount, Groups: $groupCount"

    # UPN casing can vary between Graph responses; compare users case-insensitively.
    $uniqueUPNs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # No need to scan group memberships when there are no users or no groups to compare.
    if ($allUserCount -gt 0 -and $groupCount -gt 0) {
        $groupsUrl = "https://graph.microsoft.com/v1.0/groups?`$select=id&`$top=999"
        do {
            $grpResp = $null
            try {
                # Get all groups in the tenant
                $grpResp = Invoke-GraphGetWithRetry -Uri $groupsUrl -Headers $headers
            } catch {
                $ErrorList.Add("Failed to get groups: $_")
                break
            }

            foreach ($g in $grpResp.value) {

                # page members of each group (filter to users only)
                $membersUrl = "https://graph.microsoft.com/v1.0/groups/$($g.id)/members/microsoft.graph.user?`$select=userPrincipalName&`$top=999"

                do {
                    $memResp = $null
                    try {
                        # Get members of the group
                        $memResp = Invoke-GraphGetWithRetry -Uri $membersUrl -Headers $headers
                    } catch {
                        $ErrorList.Add("Failed to get members for group ID '$($g.id)': $_")
                        break
                    }
                    foreach ($u in $memResp.value) {
                        if ($u.userPrincipalName) {
                            $uniqueUPNs.Add($u.userPrincipalName) | Out-Null
                        }
                    }
                    $membersUrl = $memResp.'@odata.nextLink'
                    # Stop paging members once Graph has returned enough unique grouped users.
                } while ($membersUrl -and $uniqueUPNs.Count -lt $allUserCount)

                # Count equality still decides compliance later; >= only avoids wasted scanning.
                if ($uniqueUPNs.Count -ge $allUserCount) {
                    break
                }
            }

            $groupsUrl = $grpResp.'@odata.nextLink'
        } while ($groupsUrl -and $uniqueUPNs.Count -lt $allUserCount)
    }

    $totalGroupUsers = $uniqueUPNs.Count

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
            
            $usersWithoutGroupsResults = Get-UserWithoutGroupAdditionalResult -Headers $headers -GroupedUPNs $uniqueUPNs -ReportTime $ReportTime -itsgcode $itsgcode -msgTable $msgTable -ErrorList $ErrorList
            if ($usersWithoutGroupsResults) {
                $AdditionalResults = $usersWithoutGroupsResults
            }
        } 
        else {
            # User groups >= 2
            # Condition: all users count == unique users in all groups count
            if( $totalGroupUsers -eq $allUserCount){
                # get conditional access policies (using paginated query to handle >100 policies)
                $CABaseAPIUrl = '/identity/conditionalAccess/policies'
                try {
                    $response = Invoke-GraphQueryEX -urlPath $CABaseAPIUrl -ErrorAction Stop
                    # portal
                    $data = $response.Content
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
                
                $usersWithoutGroupsResults = Get-UserWithoutGroupAdditionalResult -Headers $headers -GroupedUPNs $uniqueUPNs -ReportTime $ReportTime -itsgcode $itsgcode -msgTable $msgTable -ErrorList $ErrorList
                if ($usersWithoutGroupsResults) {
                    $AdditionalResults = $usersWithoutGroupsResults
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