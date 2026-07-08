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
    # Scan several group memberships at the same time to reduce large-tenant runtime.
    # Keep these values conservative so large "all users" groups do not create a large memory spike.
    $groupScanThrottleLimit = 4
    $groupBatchSize = 8
    $maxRetries = 3
    $retryDelaySeconds = 5

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
        $accessToken = (Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com/').Token
    }
    catch {
        [void]$ErrorList.Add("Failed to get access token for Microsoft Graph API: $_")
        return "Error: Failed to get access token for Microsoft Graph API: $_"
    }

    $headers = @{
        Authorization    = "Bearer $accessToken"
        ConsistencyLevel = "eventual"
    }

    # Graph 429 responses can include Retry-After, which tells us how long to wait.
    # This helps parallel scans back off cleanly instead of retrying too quickly.
    function Get-GraphRetryDelay {
        param(
            [Parameter(Mandatory=$true)]
            $ErrorRecord,
            [int] $DefaultDelaySeconds = 5
        )

        $retryAfter = $null
        if ($ErrorRecord.Exception.Response -and $ErrorRecord.Exception.Response.Headers) {
            $retryAfterValues = $null
            try {
                if ($ErrorRecord.Exception.Response.Headers.TryGetValues('Retry-After', [ref]$retryAfterValues)) {
                    $retryAfter = $retryAfterValues | Select-Object -First 1
                }
            } catch {
                $retryAfter = $null
            }
        }

        $retryAfterSeconds = 0
        if ($null -ne $retryAfter -and [int]::TryParse([string]$retryAfter, [ref]$retryAfterSeconds) -and $retryAfterSeconds -gt 0) {
            return $retryAfterSeconds
        }

        return $DefaultDelaySeconds
    }

    # Small local retry wrapper for this module's direct Graph calls.
    function Invoke-GraphGetWithRetry {
        param (
            [Parameter(Mandatory=$true)]
            [string] $Uri,
            [Parameter(Mandatory=$true)]
            [hashtable] $Headers,
            [int] $MaxRetries = $maxRetries,
            [int] $RetryDelaySeconds = $retryDelaySeconds
        )

        for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
            try {
                return Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -ErrorAction Stop
            } catch {
                $statusCode = $null
                if ($_.Exception.Response -and $null -ne $_.Exception.Response.StatusCode) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }

                $isRetryable = $null -eq $statusCode -or $statusCode -in @(429, 500, 502, 503, 504)
                if (-not $isRetryable -or $attempt -eq $MaxRetries) {
                    throw
                }

                $delaySeconds = Get-GraphRetryDelay -ErrorRecord $_ -DefaultDelaySeconds $RetryDelaySeconds
                Write-Warning "Retryable Graph error calling '$Uri' (attempt $attempt/$MaxRetries): $($_.Exception.Message). Retrying in $delaySeconds seconds..."
                Start-Sleep -Seconds $delaySeconds
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
        [void]$ErrorList.Add("Failed to get member count: $_")
    }
    $memberCount = [int]$memResp

    $guestUrlPath = '/users/$count?$filter=userType eq ''Guest'''
    $guestUri = "https://graph.microsoft.com/v1.0$guestUrlPath"
    try {
        $guestResp = Invoke-GraphGetWithRetry -Uri $guestUri -Headers $headers
    } catch {
        [void]$ErrorList.Add("Failed to get guest count: $_")
    }
    $guestCount = [int]$guestResp

    $groupUrlPath = '/groups/$count'
    $groupsUri = "https://graph.microsoft.com/v1.0$groupUrlPath"
    try {
        $groupResp = Invoke-GraphGetWithRetry -Uri $groupsUri -Headers $headers
    } catch {
        [void]$ErrorList.Add("Failed to get group count: $_")
    }
    $groupCount = [int]$groupResp
    
    
    # Find total user count in the environment
    $allUserCount = $memberCount + $guestCount

    Write-Host "Members: $memberCount, Guests: $guestCount, Groups: $groupCount"

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
                [void]$ErrorList.Add("Failed to get groups: $_")
                break
            }

            $groups = @($grpResp.value)
            for ($batchStart = 0; $batchStart -lt $groups.Count -and $uniqueUPNs.Count -lt $allUserCount; $batchStart += $groupBatchSize) {
                $batchEnd = [Math]::Min($batchStart + $groupBatchSize - 1, $groups.Count - 1)
                $groupBatch = for ($i = $batchStart; $i -le $batchEnd; $i++) {
                    [PSCustomObject]@{
                        Index = $i
                        Id    = $groups[$i].id
                    }
                }

                # Fetch group members in parallel, then merge the results below in group order.
                # Only the main runspace updates $uniqueUPNs so the shared count stays predictable.
                $batchResults = $groupBatch | ForEach-Object -Parallel {
                    $groupId = $_.Id
                    $groupIndex = $_.Index
                    $workerHeaders = $using:headers
                    $workerMaxRetries = $using:maxRetries
                    $workerRetryDelaySeconds = $using:retryDelaySeconds
                    $memberPages = [System.Collections.Generic.List[object]]::new()
                    $success = $true
                    $errorMessage = $null
                    $membersUrl = "https://graph.microsoft.com/v1.0/groups/$groupId/members/microsoft.graph.user?`$select=userPrincipalName&`$top=999"

                    do {
                        $memResp = $null
                        for ($attempt = 1; $attempt -le $workerMaxRetries; $attempt++) {
                            try {
                                $memResp = Invoke-RestMethod -Method Get -Uri $membersUrl -Headers $workerHeaders -ErrorAction Stop
                                break
                            } catch {
                                $statusCode = $null
                                if ($_.Exception.Response -and $null -ne $_.Exception.Response.StatusCode) {
                                    $statusCode = [int]$_.Exception.Response.StatusCode
                                }

                                $isRetryable = $null -eq $statusCode -or $statusCode -in @(429, 500, 502, 503, 504)
                                if (-not $isRetryable -or $attempt -eq $workerMaxRetries) {
                                    $success = $false
                                    $errorMessage = $_.Exception.Message
                                    break
                                }

                                $delaySeconds = $workerRetryDelaySeconds
                                if ($_.Exception.Response -and $_.Exception.Response.Headers) {
                                    $retryAfterValues = $null
                                    try {
                                        if ($_.Exception.Response.Headers.TryGetValues('Retry-After', [ref]$retryAfterValues)) {
                                            $retryAfter = $retryAfterValues | Select-Object -First 1
                                            $retryAfterSeconds = 0
                                            if ([int]::TryParse([string]$retryAfter, [ref]$retryAfterSeconds) -and $retryAfterSeconds -gt 0) {
                                                $delaySeconds = $retryAfterSeconds
                                            }
                                        }
                                    } catch {
                                        $delaySeconds = $workerRetryDelaySeconds
                                    }
                                }

                                Start-Sleep -Seconds $delaySeconds
                            }
                        }

                        if (-not $success -or $null -eq $memResp) {
                            break
                        }

                        $pageUPNs = [System.Collections.Generic.List[string]]::new()
                        foreach ($u in $memResp.value) {
                            if ($u.userPrincipalName) {
                                [void]$pageUPNs.Add([string]$u.userPrincipalName)
                            }
                        }

                        if ($pageUPNs.Count -gt 0) {
                            [void]$memberPages.Add([PSCustomObject]@{
                                UserPrincipalNames = [string[]]$pageUPNs.ToArray()
                            })
                        }

                        $membersUrl = $memResp.'@odata.nextLink'
                    } while ($membersUrl)

                    [PSCustomObject]@{
                        GroupIndex = $groupIndex
                        GroupId    = $groupId
                        Success    = $success
                        Error      = $errorMessage
                        Pages      = $memberPages.ToArray()
                    }
                } -ThrottleLimit $groupScanThrottleLimit

                foreach ($result in ($batchResults | Sort-Object GroupIndex)) {
                    if ($uniqueUPNs.Count -ge $allUserCount) {
                        break
                    }

                    $thresholdReached = $false
                    foreach ($page in @($result.Pages)) {
                        foreach ($upn in @($page.UserPrincipalNames)) {
                            if ($upn) {
                                [void]$uniqueUPNs.Add($upn)
                            }
                        }

                        # Match the original hotfix behavior: evaluate the stop point after each Graph page.
                        if ($uniqueUPNs.Count -ge $allUserCount) {
                            $thresholdReached = $true
                            break
                        }
                    }

                    if (-not $thresholdReached -and -not $result.Success) {
                        [void]$ErrorList.Add("Failed to get members for group ID '$($result.GroupId)': $($result.Error)")
                    }
                }

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
                    [void]$ErrorList.Add("Failed to call Microsoft Graph REST API at URL '$CABaseAPIUrl'; returned error message: $_")
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