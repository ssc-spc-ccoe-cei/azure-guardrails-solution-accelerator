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
    # Refreshing this token during long scans prevents avoidable 401 failures in large tenants.
    function Get-GraphAuthorizationHeader {
        $accessToken = (Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com/').Token
        return "Bearer $accessToken"
    }

    # Graph 429 responses can tell us exactly how long to wait before retrying.
    # Honoring Retry-After reduces false fail-closed results caused by retrying too quickly.
    function Get-GraphRetryDelay {
        param(
            [Parameter(Mandatory=$true)]
            $ErrorRecord,
            [int] $DefaultDelaySeconds = 5
        )

        $retryAfter = $null
        if ($ErrorRecord.Exception.Response -and $ErrorRecord.Exception.Response.Headers) {
            $retryAfterValues = $null
            if ($ErrorRecord.Exception.Response.Headers.TryGetValues('Retry-After', [ref]$retryAfterValues)) {
                $retryAfter = $retryAfterValues | Select-Object -First 1
            }
        }

        $retryAfterSeconds = 0
        if ($null -ne $retryAfter -and [int]::TryParse([string]$retryAfter, [ref]$retryAfterSeconds) -and $retryAfterSeconds -gt 0) {
            return $retryAfterSeconds
        }

        return $DefaultDelaySeconds
    }

    # Use one retry helper for normal Graph reads so transient failures do not fail the control immediately.
    # This supports the compliance goal by retrying throttling/server errors, while real 4xx failures still fail closed.
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

                $delaySeconds = Get-GraphRetryDelay -ErrorRecord $_ -DefaultDelaySeconds $RetryDelaySeconds
                Write-Warning "Retryable Graph error calling '$Uri' (attempt $attempt/$MaxRetries): $($_.Exception.Message). Retrying in $delaySeconds seconds..."
                Start-Sleep -Seconds $delaySeconds
            }
        }
    }

    # Build remediation output for a small sample of uncovered users.
    # The scan keeps only user IDs to save memory in large tenants.
    # If users are missing from groups, fetch details for up to 20 examples
    # so the report is useful without loading every uncovered user's profile.
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
                # Fetch details only when building the sample report, not during the full compliance scan.
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

    # Build the compliance baseline as user IDs only.
    # Later, each group member ID is removed from this set; any IDs left over are users not found in a group.
    # This is the core compliance improvement: prove coverage for actual users instead of comparing totals.
    $userBaselineStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $uncoveredUserIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $userBaselineComplete = $true
    $memberCount = 0
    $guestCount = 0
    $usersUrl = "https://graph.microsoft.com/v1.0/users?`$select=id,userType&`$top=999"

    try {
        do {
            $usersResp = Invoke-GraphGetWithRetry -Uri $usersUrl -Headers $headers -MaxRetries $maxRetries -RetryDelaySeconds $retryDelaySeconds
            foreach ($user in @($usersResp.value)) {
                if ($user.id -and $user.userType -in @("Member", "Guest")) {
                    # Store only the ID here. Display names and UPNs are loaded later only for the small remediation sample.
                    $uncoveredUserIds.Add($user.id) | Out-Null
                    if ($user.userType -eq "Member") {
                        $memberCount++
                    }
                    else {
                        $guestCount++
                    }
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

    # Member/Guest counts come from the same user baseline used for compliance.
    # This keeps report stats aligned with the users we actually evaluated.
    $groupCount = 0

    $allUserCount = $uncoveredUserIds.Count

    # Fetch group IDs first so membership reads can be processed in controlled parallel batches.
    # This improves runtime for large tenants without changing the compliance question being answered.
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
    # Use the enumerated group list for checks and reporting instead of a separate /groups/$count call.
    # This avoids count-vs-enumeration mismatch and prevents a failed count call from producing the wrong verdict.
    $groupCount = $groupIds.Count
    Write-Host "Members: $memberCount, Guests: $guestCount, Groups: $groupCount"
    Write-Host "Current user baseline: $($uncoveredUserIds.Count)"
    & $writePhaseTiming "group-list" $groupsStopwatch

    # If the group list is incomplete, the membership scan cannot prove coverage for missing groups.
    # Keep that state so the final result can fail closed instead of passing on partial data.
    $groupScanComplete = $groupListComplete
    $groupMembershipStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $tokenRefreshStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    if ($groupIds.Count -gt 0 -and $uncoveredUserIds.Count -gt 0) {
        # Batch size is larger than throttle to reduce runspace setup cost.
        # Throttle still limits active Graph reads to 8 at a time; batch size 24 does not mean 24 calls at once.
        # This balances performance with memory and Graph throttling risk.
        for ($batchStart = 0; $batchStart -lt $groupIds.Count -and $uncoveredUserIds.Count -gt 0; $batchStart += $groupBatchSize) {
            if ($tokenRefreshStopwatch.Elapsed.TotalMinutes -ge $tokenRefreshIntervalMinutes) {
                try {
                    # Refresh between batches only. Running workers keep their current header,
                    # and the next batch receives the fresh token.
                    # This keeps long scans moving without adding shared-token logic inside parallel workers.
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

            # Workers only read Graph and return user IDs.
            # The main runspace updates the uncovered set so parallel workers do not edit shared state.
            # This keeps the faster parallel scan from creating race conditions in the compliance result.
            $batchResults = $groupBatch | ForEach-Object -Parallel {
                $groupId = $_
                $memberIds = New-Object System.Collections.Generic.List[string]
                $membersUrl = "https://graph.microsoft.com/v1.0/groups/$groupId/members/microsoft.graph.user?`$select=id&`$top=999"

                try {
                    do {
                        # Retry each group-members page on throttling or transient Graph failures.
                        # A completed group read gives trusted coverage data; an incomplete read fails closed later.
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

                                $delaySeconds = $using:retryDelaySeconds
                                $retryAfter = $null
                                if ($_.Exception.Response -and $_.Exception.Response.Headers) {
                                    $retryAfterValues = $null
                                    if ($_.Exception.Response.Headers.TryGetValues('Retry-After', [ref]$retryAfterValues)) {
                                        $retryAfter = $retryAfterValues | Select-Object -First 1
                                    }
                                }

                                $retryAfterSeconds = 0
                                if ($null -ne $retryAfter -and [int]::TryParse([string]$retryAfter, [ref]$retryAfterSeconds) -and $retryAfterSeconds -gt 0) {
                                    $delaySeconds = $retryAfterSeconds
                                }

                                Start-Sleep -Seconds $delaySeconds
                            }
                        }

                        # Return direct user member IDs. Nested group membership is not expanded by this endpoint.
                        # The compliance result is therefore based on direct group membership, matching the endpoint used.
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
                    # Return the failure to the main runspace.
                    # Partial member IDs from this group are discarded because the group read was incomplete.
                    # This avoids marking users as covered from data we know may be incomplete.
                    [PSCustomObject]@{
                        GroupId = $groupId
                        Success = $false
                        UserIds = @()
                        Error   = $_.Exception.Message
                    }
                }
            } -ThrottleLimit $groupScanThrottleLimit

            # Merge worker results in one place.
            # Removing IDs here avoids race conditions and keeps the compliance result based on a complete, trusted set.
            # Once the set is empty, every current Member/Guest user has been proven to be in at least one group.
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
        # Without a complete user list, the control cannot prove who should have group coverage.
        $IsCompliant = $false
        $commentsArray += $msgTable.isNotCompliant + " " + $msgTable.userCountGroupNoMatch
    }
    elseif ($allUserCount -le 1) {
        $commentsArray += $msgTable.isCompliant + " " + $msgTable.userCountOne
        $IsCompliant = $true
    }
    elseif ($groupListComplete -and $groupCount -lt 2) {
        $IsCompliant = $false
        $commentsArray += $msgTable.isNotCompliant + " " + $msgTable.userGroupsMany
        # Include a small remediation sample when there are too few groups.
        # This helps operators fix the issue without loading every affected user into memory.
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
                # User coverage alone is not enough for this control.
                # It also requires an enabled Conditional Access policy that includes or excludes groups.
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
        # This is intentionally conservative for compliance: unknown coverage is not treated as compliant.
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