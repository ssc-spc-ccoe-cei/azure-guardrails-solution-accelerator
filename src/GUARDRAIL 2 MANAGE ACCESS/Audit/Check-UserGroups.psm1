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
    # Keep scan settings local so this module can be tuned without changing other controls.
    $commentsArray = @()
    $moduleStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    # Run up to 8 group membership reads at once; this is conservative for Graph throttling.
    $groupScanThrottleLimit = 8
    # Process 24 groups per batch to reduce parallel setup overhead while checking early-stop often.
    $groupBatchSize = 24
    # Retry transient Graph failures a few times before failing closed.
    $maxRetries = 3
    # Wait 5 seconds between retries so Graph throttling has time to clear.
    $retryDelaySeconds = 5
    # Managed identity gets new tokens for us, but each Graph bearer token can still expire.
    # Refresh before the usual token lifetime so very long group scans do not fail on 401.
    $tokenRefreshIntervalMinutes = 45

    # Emit phase timings to job output so large-tenant runs show where time is spent.
    $writePhaseTiming = {
        param(
            [string] $PhaseName,
            [System.Diagnostics.Stopwatch] $PhaseStopwatch
        )
        $phaseDurationSeconds = [Math]::Round($PhaseStopwatch.Elapsed.TotalSeconds, 2)
        $phaseDurationMinutes = [Math]::Round($PhaseStopwatch.Elapsed.TotalMinutes, 2)
        Write-Host "Check-UserGroups timing | Phase=$PhaseName | Seconds=$phaseDurationSeconds | Minutes=$phaseDurationMinutes"
    }

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

    # Azure Automation uses managed identity, but the Graph header still contains a short-lived bearer token.
    function Get-GraphAuthorizationHeader {
        $accessToken = (Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com/').Token
        return "Bearer $accessToken"
    }

    # Use one retry helper for normal Graph reads so transient failures do not fail the control immediately.
    function Invoke-GraphGetWithRetry {
        param(
            [Parameter(Mandatory=$true)]
            [string] $Uri,
            [Parameter(Mandatory=$true)]
            [hashtable] $Headers,
            [int] $MaxRetries = 3,
            [int] $RetryDelaySeconds = 5
        )

        for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
            try {
                return Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -ErrorAction Stop
            }
            catch {
                $statusCode = $null
                if ($_.Exception.Response -and $null -ne $_.Exception.Response.StatusCode) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }

                $isRetryable = $null -eq $statusCode -or $statusCode -in @(429, 500, 502, 503, 504)
                if (-not $isRetryable -or $attempt -eq $MaxRetries) {
                    throw
                }

                Write-Warning "Retryable Graph error calling '$Uri' (attempt $attempt/$MaxRetries): $($_.Exception.Message). Retrying in $RetryDelaySeconds seconds..."
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
    }

    # Count calls are used for reporting; the compliance proof comes from user IDs below.
    function Get-GraphCount {
        param(
            [Parameter(Mandatory=$true)]
            [string] $UrlPath,
            [Parameter(Mandatory=$true)]
            [hashtable] $Headers
        )

        $countUri = "https://graph.microsoft.com/v1.0$UrlPath"
        $countResponse = Invoke-GraphGetWithRetry -Uri $countUri -Headers $Headers -MaxRetries $maxRetries -RetryDelaySeconds $retryDelaySeconds
        return [int]$countResponse
    }

    # Build remediation output for up to 20 uncovered users.
    # Fetch only a small sample so large tenants do not spend extra memory/time loading every missing user's details.
    function Get-UserWithoutGroupResult {
        param(
            [Parameter(Mandatory=$true)]
            [System.Collections.Generic.HashSet[string]] $UncoveredUserIds,
            [Parameter(Mandatory=$true)]
            [hashtable] $Headers,
            [Parameter(Mandatory=$true)]
            [hashtable] $MessageTable,
            [Parameter(Mandatory=$true)]
            [string] $CurrentReportTime,
            [Parameter(Mandatory=$true)]
            [string] $ItsgCode
        )

        if ($UncoveredUserIds.Count -eq 0) {
            return $null
        }

        $usersWithoutGroups = New-Object System.Collections.Generic.List[object]
        foreach ($userId in $UncoveredUserIds) {
            if ($usersWithoutGroups.Count -ge 20) {
                break
            }

            $user = $null
            try {
                # Fetch details lazily so we do not keep every tenant user's display data in memory.
                $userUri = "https://graph.microsoft.com/v1.0/users/$userId?`$select=id,displayName,givenName,userPrincipalName"
                $user = Invoke-GraphGetWithRetry -Uri $userUri -Headers $Headers -MaxRetries $maxRetries -RetryDelaySeconds $retryDelaySeconds
            }
            catch {
                # Remediation details are helpful, but the ID alone is enough to identify the uncovered user.
                $user = [PSCustomObject]@{
                    id                = $userId
                    displayName       = "N/A"
                    givenName         = "N/A"
                    userPrincipalName = "N/A"
                }
            }

            $usersWithoutGroups.Add([PSCustomObject]@{
                UserId            = $user.id
                DisplayName       = $user.displayName
                GivenName         = $user.givenName
                UserPrincipalName = $user.userPrincipalName
                Comments          = $MessageTable.userNotInGroup
                ReportTime        = $CurrentReportTime
                itsgcode          = $ItsgCode
            }) | Out-Null
        }

        if ($usersWithoutGroups.Count -eq 0) {
            return $null
        }

        return [PSCustomObject]@{
            records = [object[]]$usersWithoutGroups.ToArray()
            logType = "GR2UsersWithoutGroups"
        }
    }

    try {
        $headers = @{
            Authorization    = (Get-GraphAuthorizationHeader)
            ConsistencyLevel = "eventual"
        }
    }
    catch {
        $ErrorList.Add("Failed to get access token for Microsoft Graph API: $_") | Out-Null
        return "Error: Failed to get access token for Microsoft Graph API: $_"
    }

    # Build the compliance baseline as user IDs only; this keeps memory low for 200k+ tenants.
    $userBaselineStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $uncoveredUserIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $userBaselineComplete = $true
    $usersUrl = "https://graph.microsoft.com/v1.0/users?`$select=id,userType&`$top=999"

    try {
        do {
            $usersResp = Invoke-GraphGetWithRetry -Uri $usersUrl -Headers $headers -MaxRetries $maxRetries -RetryDelaySeconds $retryDelaySeconds
            foreach ($user in @($usersResp.value)) {
                if ($user.id -and $user.userType -in @("Member", "Guest")) {
                    # User IDs are the compliance baseline; display names are fetched only for remediation samples.
                    $uncoveredUserIds.Add($user.id) | Out-Null
                }
            }
            $usersUrl = $usersResp.'@odata.nextLink'
        } while ($usersUrl)
    }
    catch {
        $userBaselineComplete = $false
        $ErrorList.Add("Failed to get current users from Microsoft Graph: $_") | Out-Null
    }
    & $writePhaseTiming "user-baseline" $userBaselineStopwatch

    # Keep the member/guest/group counts for the report text, not for the pass/fail decision.
    $memberCount = 0
    $guestCount = 0
    $groupCount = 0
    try {
        $memberCount = Get-GraphCount -UrlPath "/users/`$count?`$filter=userType eq 'Member'" -Headers $headers
    }
    catch {
        $ErrorList.Add("Failed to get member count: $_") | Out-Null
    }
    try {
        $guestCount = Get-GraphCount -UrlPath "/users/`$count?`$filter=userType eq 'Guest'" -Headers $headers
    }
    catch {
        $ErrorList.Add("Failed to get guest count: $_") | Out-Null
    }
    try {
        $groupCount = Get-GraphCount -UrlPath "/groups/`$count" -Headers $headers
    }
    catch {
        $ErrorList.Add("Failed to get group count: $_") | Out-Null
    }

    $allUserCount = $uncoveredUserIds.Count
    if ($allUserCount -eq 0 -and ($memberCount + $guestCount) -gt 0) {
        # Keep the report text useful if user enumeration failed; compliance still fails closed below.
        $allUserCount = $memberCount + $guestCount
    }

    Write-Output "Members: $memberCount, Guests: $guestCount, Groups: $groupCount"
    Write-Host "Current user baseline: $($uncoveredUserIds.Count)"

    # Fetch group IDs first so membership reads can be processed in controlled parallel batches.
    $groupsStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $groupIds = New-Object System.Collections.Generic.List[string]
    $groupListComplete = $true
    $groupsUrl = "https://graph.microsoft.com/v1.0/groups?`$select=id&`$top=999"
    try {
        do {
            $grpResp = Invoke-GraphGetWithRetry -Uri $groupsUrl -Headers $headers -MaxRetries $maxRetries -RetryDelaySeconds $retryDelaySeconds
            foreach ($group in @($grpResp.value)) {
                if ($group.id) {
                    $groupIds.Add($group.id) | Out-Null
                }
            }
            $groupsUrl = $grpResp.'@odata.nextLink'
        } while ($groupsUrl)
    }
    catch {
        $groupListComplete = $false
        $ErrorList.Add("Failed to get groups: $_") | Out-Null
    }
    & $writePhaseTiming "group-list" $groupsStopwatch

    # If the group list is incomplete, the membership scan cannot prove coverage for missing groups.
    $groupScanComplete = $groupListComplete
    $groupMembershipStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $tokenRefreshStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    if ($groupIds.Count -gt 0 -and $uncoveredUserIds.Count -gt 0) {
        # Batch size is larger than throttle to reduce runspace setup cost while keeping concurrency at 8.
        # PowerShell 7.2 supports -Parallel here; batch size 24 does not mean 24 Graph calls at once.
        for ($batchStart = 0; $batchStart -lt $groupIds.Count -and $uncoveredUserIds.Count -gt 0; $batchStart += $groupBatchSize) {
            if ($tokenRefreshStopwatch.Elapsed.TotalMinutes -ge $tokenRefreshIntervalMinutes) {
                try {
                    # Refresh between batches only; workers in the next batch receive the fresh header.
                    $headers.Authorization = Get-GraphAuthorizationHeader
                    $tokenRefreshStopwatch.Restart()
                }
                catch {
                    $groupScanComplete = $false
                    $ErrorList.Add("Failed to refresh Microsoft Graph access token during group scan: $_") | Out-Null
                    break
                }
            }

            $batchEnd = [Math]::Min($batchStart + $groupBatchSize - 1, $groupIds.Count - 1)
            $groupBatch = @($groupIds[$batchStart..$batchEnd])

            # Workers only read Graph and return user IDs. The main runspace updates the shared uncovered set.
            $batchResults = $groupBatch | ForEach-Object -Parallel {
                $groupId = $_
                $memberIds = New-Object System.Collections.Generic.List[string]
                $membersUrl = "https://graph.microsoft.com/v1.0/groups/$groupId/members/microsoft.graph.user?`$select=id&`$top=999"

                try {
                    do {
                        # Retry each group-members page on throttling or transient Graph failures.
                        $success = $false
                        for ($attempt = 1; $attempt -le $using:maxRetries -and -not $success; $attempt++) {
                            try {
                                $response = Invoke-RestMethod -Method Get -Uri $membersUrl -Headers $using:headers -ErrorAction Stop
                                $success = $true
                            }
                            catch {
                                $statusCode = $null
                                if ($_.Exception.Response -and $null -ne $_.Exception.Response.StatusCode) {
                                    $statusCode = [int]$_.Exception.Response.StatusCode
                                }

                                $isRetryable = $null -eq $statusCode -or $statusCode -in @(429, 500, 502, 503, 504)
                                if (-not $isRetryable -or $attempt -eq $using:maxRetries) {
                                    throw
                                }

                                Start-Sleep -Seconds $using:retryDelaySeconds
                            }
                        }

                        # Workers return direct user member IDs; the main runspace decides which IDs still matter.
                        foreach ($member in @($response.value)) {
                            if ($member.id) {
                                $memberIds.Add($member.id) | Out-Null
                            }
                        }
                        $membersUrl = $response.'@odata.nextLink'
                    } while ($membersUrl)

                    [PSCustomObject]@{
                        GroupId = $groupId
                        Success = $true
                        UserIds = [string[]]$memberIds.ToArray()
                        Error   = $null
                    }
                }
                catch {
                    # Return the failure to the main runspace so it can fail closed with the group ID in the error.
                    [PSCustomObject]@{
                        GroupId = $groupId
                        Success = $false
                        UserIds = @()
                        Error   = $_.Exception.Message
                    }
                }
            } -ThrottleLimit $groupScanThrottleLimit

            # Parallel workers only return user IDs; they do not modify the shared uncovered set.
            # The main runspace removes IDs one at a time to avoid race conditions and keep compliance results reliable.
            foreach ($result in @($batchResults)) {
                if (-not $result.Success) {
                    $groupScanComplete = $false
                    $ErrorList.Add("Failed to get members for group ID '$($result.GroupId)': $($result.Error)") | Out-Null
                    continue
                }

                foreach ($memberId in @($result.UserIds)) {
                    if ($uncoveredUserIds.Contains($memberId)) {
                        $uncoveredUserIds.Remove($memberId) | Out-Null
                    }
                }
            }
        }
    }
    & $writePhaseTiming "group-membership" $groupMembershipStopwatch

    # Report how many current users were proven to have at least one direct group membership.
    $totalGroupUsers = $allUserCount - $uncoveredUserIds.Count
    if ($totalGroupUsers -lt 0) {
        $totalGroupUsers = 0
    }

    if (-not $userBaselineComplete) {
        # Fail closed when the current user baseline cannot be trusted.
        $IsCompliant = $false
        $commentsArray += $msgTable.isNotCompliant + " " + $msgTable.userCountGroupNoMatch
    }
    elseif ($allUserCount -le 1) {
        $commentsArray += $msgTable.isCompliant + " " + $msgTable.userCountOne
        $IsCompliant = $true
    }
    elseif ($groupCount -lt 2) {
        $IsCompliant = $false
        $commentsArray += $msgTable.isNotCompliant + " " + $msgTable.userGroupsMany
        # Include a small remediation sample when there are too few groups.
        $userResults = Get-UserWithoutGroupResult -UncoveredUserIds $uncoveredUserIds -Headers $headers -MessageTable $msgTable -CurrentReportTime $ReportTime -ItsgCode $itsgcode
        if ($null -ne $userResults) {
            $AdditionalResults = $userResults
        }
    }
    elseif ($uncoveredUserIds.Count -eq 0) {
        # Every current Member/Guest user has at least one direct group membership; now check CAP usage.
        # This stays compliant even if a later group read failed, because coverage was already proven.
        $CABaseAPIUrl = '/identity/conditionalAccess/policies'
        try {
            $response = Invoke-GraphQueryEX -urlPath $CABaseAPIUrl -ErrorAction Stop
            $data = $response.Content
            if ($null -ne $data -and $null -ne $data.value) {
                $caps = $data.value
                $validPolicies = $caps | Where-Object {
                    $_.state -eq 'enabled' -and
                    ($_.conditions.users.includeGroups.Count -ge 1 -or
                    $_.conditions.users.excludeGroups.Count -ge 1 )
                }

                if ($validPolicies.count -ne 0) {
                    $IsCompliant = $true
                    $commentsArray += $msgTable.isCompliant + " " + $msgTable.reqPolicyUserGroupExists
                }
                else {
                    $IsCompliant = $false
                    $commentsArray += $msgTable.isNotCompliant + " " + $msgTable.noCAPforAnyGroups
                }
            }
        }
        catch {
            $Errorlist.Add("Failed to call Microsoft Graph REST API at URL '$CABaseAPIUrl'; returned error message: $_") | Out-Null
            Write-Warning "Error: Failed to call Microsoft Graph REST API at URL '$CABaseAPIUrl'; returned error message: $_"
        }
    }
    elseif (-not $groupScanComplete) {
        # Fail closed when incomplete group reads leave user coverage unproven.
        $IsCompliant = $false
        $commentsArray += $msgTable.isNotCompliant + " " + $msgTable.userCountGroupNoMatch
        # Show sample users still uncovered after the incomplete scan.
        $userResults = Get-UserWithoutGroupResult -UncoveredUserIds $uncoveredUserIds -Headers $headers -MessageTable $msgTable -CurrentReportTime $ReportTime -ItsgCode $itsgcode
        if ($null -ne $userResults) {
            $AdditionalResults = $userResults
        }
    }
    else {
        $IsCompliant = $false
        $commentsArray += $msgTable.isNotCompliant + " " + $msgTable.userCountGroupNoMatch
        # The scan completed and these sample users still had no direct group membership.
        $userResults = Get-UserWithoutGroupResult -UncoveredUserIds $uncoveredUserIds -Headers $headers -MessageTable $msgTable -CurrentReportTime $ReportTime -ItsgCode $itsgcode
        if ($null -ne $userResults) {
            $AdditionalResults = $userResults
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

    $moduleStopwatch.Stop()
    # Emit total module timing after compliance and remediation work are complete.
    & $writePhaseTiming "total" $moduleStopwatch

    $moduleOutput= [PSCustomObject]@{
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput
}