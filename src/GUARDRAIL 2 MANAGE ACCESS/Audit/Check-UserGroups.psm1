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
        [string] $CheckUserGroupsScanMode,
        [object[]] $CheckUserGroupsGroupIds,
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
    $commentsArray = @()
    $implementationId = 'IdBaselineDynamicV1'
    # Keep detailed validation diagnostics for the first representative scale runs. After those
    # results answer the open tuning questions, change this to Operational to reduce routine output.
    $diagnosticLevel = 'Validation'
    $userPageSize = 999
    $membershipPageSize = 999
    $probeSampleSize = 40
    $probeCandidateLimit = 20
    $probeFrequencyPercent = 10
    $smallUserThreshold = 40
    $smallGroupThreshold = 60
    $reprobeMinimumUsers = 1000
    $reprobeMinimumRounds = 6
    $minimumResidualSampleSize = 10
    $groupPathRecheckInterval = 250

    # Graph accepts at most 20 inner requests. Known full continuation pages use a lower cap
    # because several 999-record responses in one batch create a much larger memory spike.
    $graphBatchRequestSize = 20
    $fullContinuationBatchSize = 5
    $concurrentGraphBatchCalls = 1
    $defaultMaxRetries = 3
    $defaultRetryDelaySeconds = 5
    # Keep diagnostics useful but bounded so logging does not become part of the scale problem.
    $remediationSampleLimit = 20
    $slowGroupDiagnosticThresholdSeconds = 30
    $slowBatchDiagnosticThresholdSeconds = 30
    # Separate limits preserve high-value group diagnostics even when retries are frequent.
    $detailedDiagnosticBudgets = @{
        Retry            = [PSCustomObject]@{ Limit = 5;  LinesWritten = 0; SuppressionLogged = $false }
        MultiPage        = [PSCustomObject]@{ Limit = 10; LinesWritten = 0; SuppressionLogged = $false }
        NoteworthyGroup  = [PSCustomObject]@{ Limit = 10; LinesWritten = 0; SuppressionLogged = $false }
        NoteworthyBatch  = [PSCustomObject]@{ Limit = 10; LinesWritten = 0; SuppressionLogged = $false }
        Failure          = [PSCustomObject]@{ Limit = 20; LinesWritten = 0; SuppressionLogged = $false }
    }
    $overallProgressMinuteInterval = 5
    # Refresh with a wide safety margin so a slow batch is unlikely to reach token expiry.
    $tokenRefreshIntervalMinutes = 30
    $moduleStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $diagnosticMetrics = [PSCustomObject]@{
        Lines      = 0
        Characters = 0
        WriteMs    = 0.0
    }
    $graphMetrics = [PSCustomObject]@{
        DirectAttempts                = 0
        BatchCalls                    = 0
        InnerAttempts                 = 0
        Retries                       = 0
        Throttles429                  = 0
        ResourceUnits                 = 0.0
        ResourceUnitResponses         = 0
        MaximumThrottlePercentage     = 0.0
        ThrottlePercentageResponses   = 0
        MaximumBatchRecords           = 0
    }
    $scanMetrics = [PSCustomObject]@{
        UserBaselinePages        = 0
        UserRecordsReturned      = 0
        SkippedUserRecords       = 0
        ProbeRuns                = 0
        ProbeUsers               = 0
        ProbeTruncatedResponses  = 0
        CandidateCounts          = 0
        CandidateGroupsScanned   = 0
        GroupListPages           = 0
        GroupsStarted            = 0
        GroupsCompleted          = 0
        MembershipPages          = 0
        FirstPages               = 0
        ContinuationPages        = 0
        MembershipRecords        = 0
        DirectUsersChecked       = 0
        Reprobes                 = 0
        SelectedPath             = 'NotSelected'
        SinglePageGroups         = 0
        TwoToFivePageGroups      = 0
        SixToTwentyPageGroups    = 0
        OverTwentyPageGroups     = 0
    }
    # Failures are collected by category first so a tenant-wide outage cannot create thousands
    # of Log Analytics exception rows. Optional read failures are promoted only if coverage remains unknown.
    $terminalFailureStore = [PSCustomObject]@{
        Total      = 0
        Categories = @{}
        Details    = [System.Collections.Generic.List[string]]::new()
    }
    $pendingFailureStore = [PSCustomObject]@{
        Total      = 0
        Categories = @{}
        Details    = [System.Collections.Generic.List[string]]::new()
    }
    $planningFailureStore = [PSCustomObject]@{
        Total      = 0
        Categories = @{}
        Details    = [System.Collections.Generic.List[string]]::new()
    }

    # Clients sometimes test by uploading only this module, without the matching localization package.
    # Prefer localized text when available, but keep standalone tests readable when a newer key is missing.
    $userGroupScanIncompleteMessage = [string]$msgTable['userGroupScanIncomplete']
    if ([string]::IsNullOrWhiteSpace($userGroupScanIncompleteMessage)) {
        $userGroupScanIncompleteMessage = 'User group compliance could not be fully evaluated because Microsoft Graph data retrieval did not complete.'
    }
    $userStatsMessageTemplate = [string]$msgTable['userStats']
    if ([string]::IsNullOrWhiteSpace($userStatsMessageTemplate) -or
        $userStatsMessageTemplate -match 'Group Users \(Total - Unique\)|Utilisateurs de groupe \(Total - Unique\)') {
        # A one-off module upload can still have the older localization package. Use an accurate
        # built-in label rather than describing this exact covered-user value as the old UPN total.
        $userStatsMessageTemplate = 'User stats - Total Users: {0}; Covered Member/Guest Users (Unique): {1}; Members in Tenants: {2}; Guests in Tenants: {3}'
    }

    # Capture both working-set and private memory because Azure's sandbox limit does not map cleanly
    # to one process metric. Processor time helps show whether Graph waits or local CPU dominate.
    function Get-GroupScanResourceSnapshot {
        $process = [System.Diagnostics.Process]::GetCurrentProcess()
        try {
            return [PSCustomObject]@{
                CurrentMb       = [Math]::Round(($process.WorkingSet64 / 1MB), 1)
                PeakMb          = [Math]::Round(($process.PeakWorkingSet64 / 1MB), 1)
                PrivateMb       = [Math]::Round(($process.PrivateMemorySize64 / 1MB), 1)
                ProcessorSeconds = [Math]::Round($process.TotalProcessorTime.TotalSeconds, 3)
            }
        }
        finally {
            $process.Dispose()
        }
    }

    # Send diagnostics to a stream that Azure Automation preserves in exported job logs.
    # Warning records stay separate from the module's structured return value and do not change compliance results.
    function Write-CheckUserGroupDiagnostic {
        param(
            [Parameter(Mandatory=$true)]
            [string] $Message
        )

        $diagnosticStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $formattedMessage = "[Diagnostic] $Message"
        Write-Warning $formattedMessage
        $diagnosticMetrics.Lines++
        $diagnosticMetrics.Characters += $formattedMessage.Length
        $diagnosticMetrics.WriteMs += $diagnosticStopwatch.Elapsed.TotalMilliseconds
    }

    # Mark the start and end of major stages so the last job-output line identifies where a stopped run was working.
    function Write-CheckUserGroupStage {
        param(
            [Parameter(Mandatory=$true)]
            [string] $Stage,
            [Parameter(Mandatory=$true)]
            [string] $State,
            [Parameter(Mandatory=$true)]
            [System.Diagnostics.Stopwatch] $Stopwatch,
            [string] $Details
        )

        $memory = Get-GroupScanResourceSnapshot
        $message = "Check-UserGroups stage: Stage=$Stage; State=$State; StageElapsed=$($Stopwatch.Elapsed); TotalElapsed=$($moduleStopwatch.Elapsed); Memory=$($memory.CurrentMb) MB; PeakMemory=$($memory.PeakMb) MB; PrivateMemory=$($memory.PrivateMb) MB; ProcessorSeconds=$($memory.ProcessorSeconds)"
        if ($Details) {
            $message += "; $Details"
        }
        Write-CheckUserGroupDiagnostic -Message $message
    }

    # Cap detailed event lines so heavy Graph throttling cannot flood the Azure Automation output stream.
    # Periodic progress and final aggregate summaries continue after this limit is reached.
    function Test-GroupDiagnosticDetailAllowed {
        param(
            [Parameter(Mandatory=$true)]
            [ValidateSet('Retry', 'MultiPage', 'NoteworthyGroup', 'NoteworthyBatch', 'Failure')]
            [string] $Category
        )

        $categoryState = $detailedDiagnosticBudgets[$Category]
        if ($categoryState.LinesWritten -lt $categoryState.Limit) {
            $categoryState.LinesWritten++
            return $true
        }

        if (-not $categoryState.SuppressionLogged) {
            Write-CheckUserGroupDiagnostic -Message "Check-UserGroups $Category diagnostics capped at $($categoryState.Limit) lines; periodic and final summaries will continue."
            $categoryState.SuppressionLogged = $true
        }
        return $false
    }

    Write-CheckUserGroupStage -Stage 'Module' -State 'Started' -Stopwatch $moduleStopwatch -Details "Implementation=$implementationId; DiagnosticLevel=$diagnosticLevel; UserPageSize=$userPageSize; MembershipPageSize=$membershipPageSize; GraphBatchLimit=$graphBatchRequestSize; FullContinuationLimit=$fullContinuationBatchSize; ConcurrentBatchCalls=$concurrentGraphBatchCalls"

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

    # Managed identity issues the token, but the bearer token in the header can expire during a long scan.
    function Get-GraphAuthorizationHeader {
        try {
            # Az.Accounts versions differ on whether Token is plain text or SecureString.
            # Requesting a SecureString first and converting it here keeps the header valid in either runtime.
            $tokenResponse = Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com/' -AsSecureString -ErrorAction Stop
            $accessToken = [System.Net.NetworkCredential]::new('', $tokenResponse.Token).Password
        }
        catch {
            $tokenResponse = Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com/' -ErrorAction Stop
            if ($tokenResponse.Token -is [System.Security.SecureString]) {
                $accessToken = [System.Net.NetworkCredential]::new('', $tokenResponse.Token).Password
            }
            else {
                $accessToken = [string]$tokenResponse.Token
            }
        }

        return "Bearer $accessToken"
    }

    $authenticationStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-CheckUserGroupStage -Stage 'GraphAuthentication' -State 'Started' -Stopwatch $authenticationStopwatch
    try {
        $headers = @{
            Authorization    = (Get-GraphAuthorizationHeader)
            ConsistencyLevel = "eventual"
        }
        $tokenRefreshStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Write-CheckUserGroupStage -Stage 'GraphAuthentication' -State 'Completed' -Stopwatch $authenticationStopwatch
    }
    catch {
        Write-CheckUserGroupStage -Stage 'GraphAuthentication' -State 'Failed' -Stopwatch $authenticationStopwatch -Details "Error=$($_.Exception.Message)"
        [void]$ErrorList.Add("Failed to get access token for Microsoft Graph API: $_")
        $AdditionalResults.records[0].Comments = $userGroupScanIncompleteMessage
        $authenticationFailureResult = [PSCustomObject]@{
            ComplianceStatus = $false
            ControlName      = $ControlName
            ItemName         = $ItemName
            Comments         = "$($msgTable.isNotCompliant) $userGroupScanIncompleteMessage"
            ReportTime       = $ReportTime
            itsgcode         = $itsgcode
        }
        Write-CheckUserGroupStage -Stage 'Module' -State 'CompletedWithErrors' -Stopwatch $moduleStopwatch -Details 'IsCompliant=False; Failure=GraphAuthentication'
        return [PSCustomObject]@{
            ComplianceResults = $authenticationFailureResult
            Errors            = $ErrorList
            AdditionalResults = $AdditionalResults
        }
    }

    # Refresh the token between batch calls so long scans do not fail when the original token expires.
    function Invoke-GraphAuthorizationRefresh {
        param(
            [Parameter(Mandatory=$true)]
            [string] $Trigger
        )

        $tokenRefreshStageStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Write-CheckUserGroupStage -Stage 'GraphTokenRefresh' -State 'Started' -Stopwatch $tokenRefreshStageStopwatch -Details "Trigger=$Trigger"
        try {
            $newAuthorizationHeader = Get-GraphAuthorizationHeader
            $headers.Authorization = $newAuthorizationHeader
            $tokenRefreshStopwatch.Restart()
            Write-CheckUserGroupStage -Stage 'GraphTokenRefresh' -State 'Completed' -Stopwatch $tokenRefreshStageStopwatch -Details "Trigger=$Trigger"
            return $true
        }
        catch {
            Write-CheckUserGroupStage -Stage 'GraphTokenRefresh' -State 'Failed' -Stopwatch $tokenRefreshStageStopwatch -Details "Trigger=$Trigger; Error=$($_.Exception.Message)"
            return $false
        }
    }

    # Graph may return request-cost and throttle-percentage headers. They are tuning evidence only;
    # missing or malformed optional headers never change compliance or retry behavior.
    function Add-GraphHeaderMetric {
        param($ResponseHeaders)

        if ($null -eq $ResponseHeaders) {
            return
        }

        $getHeaderValue = {
            param($Headers, [string] $Name)

            if ($Headers -is [System.Collections.IDictionary]) {
                foreach ($key in $Headers.Keys) {
                    if ([string]$key -ieq $Name) {
                        return @($Headers[$key]) | Select-Object -First 1
                    }
                }
            }

            $property = $Headers.PSObject.Properties |
                Where-Object { $_.Name -ieq $Name } |
                Select-Object -First 1
            if ($property) {
                return @($property.Value) | Select-Object -First 1
            }

            return $null
        }

        $resourceUnitText = & $getHeaderValue $ResponseHeaders 'x-ms-resource-unit'
        $resourceUnits = 0.0
        if ($null -ne $resourceUnitText -and
            [double]::TryParse([string]$resourceUnitText, [ref]$resourceUnits)) {
            $graphMetrics.ResourceUnits += $resourceUnits
            $graphMetrics.ResourceUnitResponses++
        }

        $throttleText = & $getHeaderValue $ResponseHeaders 'x-ms-throttle-limit-percentage'
        $throttlePercentage = 0.0
        if ($null -ne $throttleText -and
            [double]::TryParse(([string]$throttleText).TrimEnd('%'), [ref]$throttlePercentage)) {
            $graphMetrics.MaximumThrottlePercentage = [Math]::Max($graphMetrics.MaximumThrottlePercentage, $throttlePercentage)
            $graphMetrics.ThrottlePercentageResponses++
        }
    }

    # Graph 429 responses can include Retry-After, which tells us how long to wait.
    # This helps large scans back off cleanly instead of retrying too quickly.
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
            [ValidateRange(1, 10)]
            [int] $MaxRetries = $defaultMaxRetries,
            [ValidateRange(0, 300)]
            [int] $RetryDelaySeconds = $defaultRetryDelaySeconds
        )

        for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
            try {
                $responseHeaders = $null
                $graphMetrics.DirectAttempts++
                $response = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -ResponseHeadersVariable responseHeaders -ErrorAction Stop
                Add-GraphHeaderMetric -ResponseHeaders $responseHeaders
                return $response
            } catch {
                $statusCode = $null
                if ($_.Exception.Response -and $null -ne $_.Exception.Response.StatusCode) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }

                if ($statusCode -eq 429) {
                    $graphMetrics.Throttles429++
                }

                $isRetryable = $null -eq $statusCode -or $statusCode -in @(401, 429, 500, 502, 503, 504)
                if (-not $isRetryable -or $attempt -eq $MaxRetries) {
                    throw
                }

                $delaySeconds = Get-GraphRetryDelay -ErrorRecord $_ -DefaultDelaySeconds $RetryDelaySeconds
                if ($statusCode -eq 401) {
                    if (-not (Invoke-GraphAuthorizationRefresh -Trigger 'DirectRequest401')) {
                        throw
                    }
                    $delaySeconds = 0
                }

                $graphMetrics.Retries++
                if (Test-GroupDiagnosticDetailAllowed -Category 'Retry') {
                    Write-CheckUserGroupDiagnostic -Message "Check-UserGroups Graph retry: Scope=Direct; Attempt=$attempt/$MaxRetries; StatusCode=$statusCode; DelaySeconds=$delaySeconds; Endpoint=$(([Uri]$Uri).AbsolutePath)"
                }
                if ($delaySeconds -gt 0) {
                    Start-Sleep -Seconds $delaySeconds
                }
            }
        }

        # Parameter validation does not validate a default value, so never allow an empty loop to return null silently.
        throw "Graph request to '$Uri' ended without making a retry attempt. MaxRetries must be at least 1."
    }

    # Graph returns absolute nextLink URLs, while an inner JSON batch request needs a URL relative
    # to the v1.0 endpoint. Keeping only the path and query also avoids copying host details into batches.
    function ConvertTo-GraphBatchRelativeUrl {
        param(
            [Parameter(Mandatory=$true)]
            [string] $Url
        )

        if ([Uri]::IsWellFormedUriString($Url, [UriKind]::Absolute)) {
            $relativeUrl = ([Uri]$Url).PathAndQuery
        }
        else {
            $relativeUrl = $Url
        }

        if ($relativeUrl.StartsWith('/v1.0/', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $relativeUrl.Substring('/v1.0'.Length)
        }

        return $relativeUrl
    }

    # Retry-After is carried inside each JSON batch response rather than on the outer HTTP response.
    function Get-GraphBatchResponseRetryDelay {
        param(
            [Parameter(Mandatory=$true)]
            [AllowNull()]
            $BatchResponse,
            [int] $DefaultDelaySeconds = 5
        )

        $retryAfter = $null
        if ($null -ne $BatchResponse -and $BatchResponse.headers) {
            $retryAfterProperty = $BatchResponse.headers.PSObject.Properties |
                Where-Object { $_.Name -ieq 'Retry-After' } |
                Select-Object -First 1
            if ($retryAfterProperty) {
                $retryAfter = @($retryAfterProperty.Value) | Select-Object -First 1
            }
        }

        $retryAfterSeconds = 0
        if ($null -ne $retryAfter -and
            [int]::TryParse([string]$retryAfter, [ref]$retryAfterSeconds) -and
            $retryAfterSeconds -gt 0) {
            return $retryAfterSeconds
        }

        return $DefaultDelaySeconds
    }

    # Submit one bounded JSON batch. Only the outer HTTP call is retried here; failed inner
    # membership requests are retried individually by the queue that owns their group/page state.
    function Invoke-GraphJsonBatchWithRetry {
        param(
            [Parameter(Mandatory=$true)]
            [object[]] $Requests,
            [Parameter(Mandatory=$true)]
            [hashtable] $Headers,
            [ValidateRange(1, 10)]
            [int] $MaxRetries = $defaultMaxRetries,
            [ValidateRange(0, 300)]
            [int] $RetryDelaySeconds = $defaultRetryDelaySeconds
        )

        $batchUri = 'https://graph.microsoft.com/v1.0/$batch'
        $batchPayload = @{ requests = $Requests } | ConvertTo-Json -Depth 8 -Compress
        $outerThrottleCount = 0

        for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
            try {
                $batchHeaders = @{ Authorization = $Headers.Authorization }
                $responseHeaders = $null
                $graphMetrics.BatchCalls++
                $response = Invoke-RestMethod -Method Post -Uri $batchUri -Headers $batchHeaders -ContentType 'application/json' -Body $batchPayload -ResponseHeadersVariable responseHeaders -ErrorAction Stop
                Add-GraphHeaderMetric -ResponseHeaders $responseHeaders
                if ($null -eq $response -or $null -eq $response.responses) {
                    throw 'Microsoft Graph returned an empty JSON batch response.'
                }

                return [PSCustomObject]@{
                    Response             = $response
                    Attempts             = $attempt
                    RetryCount           = $attempt - 1
                    ThrottleResponseCount = $outerThrottleCount
                }
            }
            catch {
                $statusCode = $null
                if ($_.Exception.Response -and $null -ne $_.Exception.Response.StatusCode) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }
                if ($statusCode -eq 429) {
                    $outerThrottleCount++
                    $graphMetrics.Throttles429++
                }

                $isRetryable = $null -eq $statusCode -or $statusCode -in @(401, 429, 500, 502, 503, 504)
                if (-not $isRetryable -or $attempt -eq $MaxRetries) {
                    throw
                }

                $delaySeconds = Get-GraphRetryDelay -ErrorRecord $_ -DefaultDelaySeconds $RetryDelaySeconds
                if ($statusCode -eq 401) {
                    if (-not (Invoke-GraphAuthorizationRefresh -Trigger 'OuterBatch401')) {
                        throw
                    }
                    $delaySeconds = 0
                }

                if (Test-GroupDiagnosticDetailAllowed -Category 'Retry') {
                    Write-CheckUserGroupDiagnostic -Message "Check-UserGroups Graph batch retry: Scope=Outer; Attempt=$attempt/$MaxRetries; StatusCode=$statusCode; InnerRequests=$($Requests.Count); DelaySeconds=$delaySeconds"
                }
                $graphMetrics.Retries++
                if ($delaySeconds -gt 0) {
                    Start-Sleep -Seconds $delaySeconds
                }
            }
        }

        throw 'Microsoft Graph JSON batch ended without making a retry attempt.'
    }

    # Extract enough Graph error context to group repeated failures without retaining every response body.
    function Get-GraphFailureContext {
        param($ErrorRecord)

        $statusCode = 'NoStatus'
        if ($ErrorRecord.Exception.Response -and $null -ne $ErrorRecord.Exception.Response.StatusCode) {
            $statusCode = [string][int]$ErrorRecord.Exception.Response.StatusCode
        }

        $graphCode = 'NoCode'
        if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
            try {
                $errorBody = $ErrorRecord.ErrorDetails.Message | ConvertFrom-Json -ErrorAction Stop
                if ($errorBody.error.code) {
                    $graphCode = [string]$errorBody.error.code
                }
            }
            catch {
                $graphCode = 'NoCode'
            }
        }

        return [PSCustomObject]@{
            StatusCode = $statusCode
            GraphCode  = $graphCode
            Message    = [string]$ErrorRecord.Exception.Message
        }
    }

    # Count every failure for compliance, but keep only bounded examples for Log Analytics.
    # Pending failures come from optional paths and are promoted only if exact coverage remains unproved.
    function Add-CheckUserGroupFailure {
        param(
            [Parameter(Mandatory=$true)]
            [ValidateSet('Terminal', 'Pending', 'Planning')]
            [string] $Kind,
            [Parameter(Mandatory=$true)]
            [string] $Stage,
            [Parameter(Mandatory=$true)]
            [string] $Endpoint,
            [Parameter(Mandatory=$true)]
            [string] $StatusCode,
            [Parameter(Mandatory=$true)]
            [string] $GraphCode,
            [string] $EntityId,
            [Parameter(Mandatory=$true)]
            [string] $Message
        )

        $store = switch ($Kind) {
            'Terminal' { $terminalFailureStore }
            'Pending'  { $pendingFailureStore }
            default    { $planningFailureStore }
        }
        $categoryKey = "$Stage|$Endpoint|$StatusCode|$GraphCode"
        if (-not $store.Categories.ContainsKey($categoryKey)) {
            $store.Categories[$categoryKey] = [PSCustomObject]@{
                Stage      = $Stage
                Endpoint   = $Endpoint
                StatusCode = $StatusCode
                GraphCode  = $GraphCode
                Count      = 0
                DetailCount = 0
                EntityIds  = [System.Collections.Generic.List[string]]::new()
            }
        }

        $category = $store.Categories[$categoryKey]
        $store.Total++
        $category.Count++
        if ($EntityId -and $category.EntityIds.Count -lt 10 -and -not $category.EntityIds.Contains($EntityId)) {
            [void]$category.EntityIds.Add($EntityId)
        }

        if ($store.Details.Count -lt 20 -and $category.DetailCount -lt 10) {
            $detail = "Stage=$Stage; Endpoint=$Endpoint; HTTP=$StatusCode; GraphCode=$GraphCode"
            if ($EntityId) {
                $detail += "; EntityId=$EntityId"
            }
            $detail += "; Error=$Message"
            [void]$store.Details.Add($detail)
            $category.DetailCount++
        }

        if (Test-GroupDiagnosticDetailAllowed -Category 'Failure') {
            Write-CheckUserGroupDiagnostic -Message "Check-UserGroups Graph failure: Kind=$Kind; Stage=$Stage; Endpoint=$Endpoint; HTTP=$StatusCode; GraphCode=$GraphCode; EntityId=$EntityId; Error=$Message"
        }
    }

    function Add-ErrorRecordFailure {
        param(
            [Parameter(Mandatory=$true)]
            [ValidateSet('Terminal', 'Pending', 'Planning')]
            [string] $Kind,
            [Parameter(Mandatory=$true)]
            [string] $Stage,
            [Parameter(Mandatory=$true)]
            [string] $Endpoint,
            [string] $EntityId,
            [Parameter(Mandatory=$true)]
            $ErrorRecord
        )

        $context = Get-GraphFailureContext -ErrorRecord $ErrorRecord
        Add-CheckUserGroupFailure -Kind $Kind -Stage $Stage -Endpoint $Endpoint -StatusCode $context.StatusCode -GraphCode $context.GraphCode -EntityId $EntityId -Message $context.Message
    }

    # Optional-path failures matter only when no later exact path proves coverage.
    function Merge-PendingFailure {
        foreach ($detail in $pendingFailureStore.Details) {
            if ($terminalFailureStore.Details.Count -lt 20) {
                [void]$terminalFailureStore.Details.Add($detail)
            }
        }

        foreach ($categoryKey in $pendingFailureStore.Categories.Keys) {
            $pendingCategory = $pendingFailureStore.Categories[$categoryKey]
            if (-not $terminalFailureStore.Categories.ContainsKey($categoryKey)) {
                $terminalFailureStore.Categories[$categoryKey] = [PSCustomObject]@{
                    Stage       = $pendingCategory.Stage
                    Endpoint    = $pendingCategory.Endpoint
                    StatusCode  = $pendingCategory.StatusCode
                    GraphCode   = $pendingCategory.GraphCode
                    Count       = 0
                    DetailCount = 0
                    EntityIds   = [System.Collections.Generic.List[string]]::new()
                }
            }

            $terminalCategory = $terminalFailureStore.Categories[$categoryKey]
            $terminalCategory.Count += $pendingCategory.Count
            foreach ($entityId in $pendingCategory.EntityIds) {
                if ($terminalCategory.EntityIds.Count -lt 10 -and -not $terminalCategory.EntityIds.Contains($entityId)) {
                    [void]$terminalCategory.EntityIds.Add($entityId)
                }
            }
        }

        $terminalFailureStore.Total += $pendingFailureStore.Total
    }

    # Materialize bounded detail and summary rows only once, after the final result is known.
    function Write-StructuredFailure {
        foreach ($detail in $terminalFailureStore.Details) {
            [void]$ErrorList.Add($detail)
        }

        $categories = @($terminalFailureStore.Categories.Values | Sort-Object -Property Count -Descending)
        $categoryLimit = [Math]::Min(20, $categories.Count)
        for ($index = 0; $index -lt $categoryLimit; $index++) {
            $category = $categories[$index]
            $sampleIds = if ($category.EntityIds.Count -gt 0) { $category.EntityIds -join ',' } else { 'N/A' }
            [void]$ErrorList.Add("Failure summary: Stage=$($category.Stage); Endpoint=$($category.Endpoint); HTTP=$($category.StatusCode); GraphCode=$($category.GraphCode); Affected=$($category.Count); SampleEntityIds=$sampleIds")
        }

        if ($categories.Count -gt $categoryLimit) {
            $overflowCount = [int](($categories[$categoryLimit..($categories.Count - 1)] | Measure-Object -Property Count -Sum).Sum)
            [void]$ErrorList.Add("Failure summary: AdditionalCategories=$($categories.Count - $categoryLimit); Affected=$overflowCount")
        }
    }

    # Execute independent Graph requests in batches of at most 20. Failed inner requests retry on their
    # own so successful work is preserved rather than repeating the whole outer batch.
    function Invoke-GraphBatchRequestSet {
        param(
            [Parameter(Mandatory=$true)]
            [AllowEmptyCollection()]
            [object[]] $Items,
            [Parameter(Mandatory=$true)]
            [string] $Stage,
            [Parameter(Mandatory=$true)]
            [string] $Endpoint,
            [ValidateSet('Terminal', 'Pending', 'Planning')]
            [string] $FailureKind = 'Terminal'
        )

        $successfulResults = [System.Collections.Generic.List[object]]::new()
        $failedResults = [System.Collections.Generic.List[object]]::new()
        $pendingItems = [System.Collections.Generic.List[object]]::new()
        foreach ($item in @($Items)) {
            # Keep caller-specific page state (for example PageNumber and KnownFullContinuation)
            # while adding retry state used only by this helper.
            $pendingItem = $item.PSObject.Copy()
            $pendingItem | Add-Member -MemberType NoteProperty -Name Attempt -Value 1 -Force
            [void]$pendingItems.Add($pendingItem)
        }

        while ($pendingItems.Count -gt 0) {
            if ($tokenRefreshStopwatch.Elapsed.TotalMinutes -ge $tokenRefreshIntervalMinutes) {
                if (-not (Invoke-GraphAuthorizationRefresh -Trigger "$Stage-BeforeBatch")) {
                    foreach ($pendingItem in $pendingItems) {
                        Add-CheckUserGroupFailure -Kind $FailureKind -Stage $Stage -Endpoint $Endpoint -StatusCode 'NoStatus' -GraphCode 'TokenRefreshFailed' -EntityId $pendingItem.EntityId -Message 'Microsoft Graph access token refresh failed.'
                        [void]$failedResults.Add([PSCustomObject]@{ Item = $pendingItem; Status = $null; GraphCode = 'TokenRefreshFailed' })
                    }
                    break
                }
            }

            $nextPendingItems = [System.Collections.Generic.List[object]]::new()
            $maximumRetryDelaySeconds = 0
            $inner401RefreshSucceeded = $null
            for ($offset = 0; $offset -lt $pendingItems.Count; $offset += $graphBatchRequestSize) {
                $lastIndex = [Math]::Min($offset + $graphBatchRequestSize - 1, $pendingItems.Count - 1)
                $chunk = @($pendingItems[$offset..$lastIndex])
                $batchRequests = [System.Collections.Generic.List[object]]::new()
                $itemByRequestId = @{}
                $requestId = 1
                foreach ($pendingItem in $chunk) {
                    $requestKey = [string]$requestId
                    $itemByRequestId[$requestKey] = $pendingItem
                    [void]$batchRequests.Add(@{
                        id      = $requestKey
                        method  = 'GET'
                        url     = (ConvertTo-GraphBatchRelativeUrl -Url $pendingItem.Url)
                        headers = @{ ConsistencyLevel = 'eventual' }
                    })
                    $requestId++
                    $graphMetrics.InnerAttempts++
                }

                try {
                    $batchResult = Invoke-GraphJsonBatchWithRetry -Requests $batchRequests.ToArray() -Headers $headers
                }
                catch {
                    foreach ($pendingItem in $chunk) {
                        Add-ErrorRecordFailure -Kind $FailureKind -Stage $Stage -Endpoint $Endpoint -EntityId $pendingItem.EntityId -ErrorRecord $_
                        [void]$failedResults.Add([PSCustomObject]@{ Item = $pendingItem; Status = $null; GraphCode = 'OuterBatchFailed' })
                    }
                    continue
                }

                $responsesById = @{}
                foreach ($innerResponse in @($batchResult.Response.responses)) {
                    $responsesById[[string]$innerResponse.id] = $innerResponse
                }

                foreach ($requestKey in $itemByRequestId.Keys) {
                    $pendingItem = $itemByRequestId[$requestKey]
                    $innerResponse = $responsesById[$requestKey]
                    $statusCode = if ($null -ne $innerResponse -and $null -ne $innerResponse.status) { [int]$innerResponse.status } else { $null }
                    Add-GraphHeaderMetric -ResponseHeaders $innerResponse.headers

                    if ($statusCode -ge 200 -and $statusCode -lt 300 -and $null -ne $innerResponse.body) {
                        [void]$successfulResults.Add([PSCustomObject]@{
                            Item   = $pendingItem
                            Status = $statusCode
                            Body   = $innerResponse.body
                        })
                        continue
                    }

                    $graphCode = if ($innerResponse.body.error.code) { [string]$innerResponse.body.error.code } else { 'NoCode' }
                    $errorMessage = if ($innerResponse.body.error.message) { [string]$innerResponse.body.error.message } else { 'Microsoft Graph returned no response body.' }
                    if ($statusCode -eq 429) {
                        $graphMetrics.Throttles429++
                    }

                    $isRetryable = $null -eq $statusCode -or $statusCode -in @(401, 429, 500, 502, 503, 504)
                    if ($isRetryable -and $pendingItem.Attempt -lt $defaultMaxRetries) {
                        $delaySeconds = Get-GraphBatchResponseRetryDelay -BatchResponse $innerResponse -DefaultDelaySeconds $defaultRetryDelaySeconds
                        if ($statusCode -eq 401) {
                            # One expired batch can return many 401 responses. Refresh once, then let
                            # every affected inner request retry with the same new token.
                            if ($null -eq $inner401RefreshSucceeded) {
                                $inner401RefreshSucceeded = Invoke-GraphAuthorizationRefresh -Trigger "$Stage-Inner401"
                            }
                            if (-not $inner401RefreshSucceeded) {
                                $isRetryable = $false
                            }
                            $delaySeconds = 0
                        }

                        if ($isRetryable) {
                            $pendingItem.Attempt++
                            $graphMetrics.Retries++
                            if (Test-GroupDiagnosticDetailAllowed -Category 'Retry') {
                                Write-CheckUserGroupDiagnostic -Message "Check-UserGroups Graph retry: Scope=Inner; Stage=$Stage; EntityId=$($pendingItem.EntityId); Attempt=$($pendingItem.Attempt)/$defaultMaxRetries; HTTP=$statusCode; DelaySeconds=$delaySeconds"
                            }
                            $maximumRetryDelaySeconds = [Math]::Max($maximumRetryDelaySeconds, $delaySeconds)
                            [void]$nextPendingItems.Add($pendingItem)
                            continue
                        }
                    }

                    Add-CheckUserGroupFailure -Kind $FailureKind -Stage $Stage -Endpoint $Endpoint -StatusCode $(if ($null -eq $statusCode) { 'NoStatus' } else { [string]$statusCode }) -GraphCode $graphCode -EntityId $pendingItem.EntityId -Message $errorMessage
                    [void]$failedResults.Add([PSCustomObject]@{ Item = $pendingItem; Status = $statusCode; GraphCode = $graphCode })
                }
            }

            # Inner requests share one retry window. Waiting once for the longest Retry-After avoids
            # multiplying a 60-second throttle delay by every failed request in the same batch.
            if ($nextPendingItems.Count -gt 0 -and $maximumRetryDelaySeconds -gt 0) {
                Start-Sleep -Seconds $maximumRetryDelaySeconds
            }

            $pendingItems = $nextPendingItems
        }

        return [PSCustomObject]@{
            Successful = $successfulResults.ToArray()
            Failed     = $failedResults.ToArray()
        }
    }

    # Reservoir sampling keeps a fixed-size, uniformly mixed sample while walking a HashSet once.
    # One random generator is reused for the full walk so rapid clock-based reseeding cannot bias the sample.
    function Get-UniformUserSample {
        param(
            [Parameter(Mandatory=$true)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.HashSet[Guid]] $UserIds,
            [ValidateRange(1, 1000)]
            [int] $Limit = $probeSampleSize
        )

        $sample = [System.Collections.Generic.List[Guid]]::new($Limit)
        $random = [System.Random]::new()
        $seen = 0
        foreach ($userId in $UserIds) {
            $seen++
            if ($sample.Count -lt $Limit) {
                [void]$sample.Add($userId)
                continue
            }

            $replacementIndex = $random.Next(0, $seen)
            if ($replacementIndex -lt $Limit) {
                $sample[$replacementIndex] = $userId
            }
        }

        return [Guid[]]$sample.ToArray()
    }

    # Probe a uniform user sample for direct group IDs. This is an ordering hint only: the probe
    # reads one page per user and exact group/user paths still decide compliance if it misses a group.
    function Find-BroadGroupCandidate {
        param(
            [Parameter(Mandatory=$true)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.HashSet[Guid]] $UncoveredUserIds,
            [Parameter(Mandatory=$true)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.HashSet[Guid]] $CompletedGroupIds,
            [Parameter(Mandatory=$true)]
            [int] $ProbeNumber,
            [Parameter(Mandatory=$true)]
            [string] $Reason
        )

        $probeStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $sampleIds = Get-UniformUserSample -UserIds $UncoveredUserIds -Limit $probeSampleSize
        $scanMetrics.ProbeRuns++
        $scanMetrics.ProbeUsers += $sampleIds.Count
        Write-CheckUserGroupStage -Stage 'BroadGroupProbe' -State 'Started' -Stopwatch $probeStopwatch -Details "Probe=$ProbeNumber; Reason=$Reason; SampleSize=$($sampleIds.Count); Uncovered=$($UncoveredUserIds.Count)"
        if ($diagnosticLevel -eq 'Validation' -and $sampleIds.Count -gt 0) {
            Write-CheckUserGroupDiagnostic -Message "Check-UserGroups probe sample: Probe=$ProbeNumber; UserIds=$($sampleIds -join ',')"
        }

        # Keep at most 40 user-to-group arrays plus one integer per observed group. Creating a
        # separate HashSet for every possible group would add avoidable object overhead in memory.
        $groupFrequency = [System.Collections.Generic.Dictionary[Guid, int]]::new()
        $sampleGroupsByUser = [System.Collections.Generic.Dictionary[Guid, Guid[]]]::new()
        for ($offset = 0; $offset -lt $sampleIds.Count; $offset += $graphBatchRequestSize) {
            $lastIndex = [Math]::Min($offset + $graphBatchRequestSize - 1, $sampleIds.Count - 1)
            $items = [System.Collections.Generic.List[object]]::new()
            foreach ($userId in @($sampleIds[$offset..$lastIndex])) {
                [void]$items.Add([PSCustomObject]@{
                    Key      = [string]$userId
                    EntityId = [string]$userId
                    Url      = "/users/$userId/memberOf/microsoft.graph.group?`$select=id&`$top=$membershipPageSize&`$count=true"
                })
            }

            $probeResult = Invoke-GraphBatchRequestSet -Items $items.ToArray() -Stage 'BroadGroupProbe' -Endpoint 'UserMemberOfProbe' -FailureKind 'Planning'
            foreach ($success in @($probeResult.Successful)) {
                $sampleUserId = [Guid]$success.Item.EntityId
                $groupsForUser = [System.Collections.Generic.List[Guid]]::new()
                if ($success.Body.'@odata.nextLink') {
                    $scanMetrics.ProbeTruncatedResponses++
                }

                foreach ($group in @($success.Body.value)) {
                    $groupId = [Guid]::Empty
                    if (-not [Guid]::TryParse([string]$group.id, [ref]$groupId) -or $CompletedGroupIds.Contains($groupId)) {
                        continue
                    }

                    [void]$groupsForUser.Add($groupId)
                    if ($groupFrequency.ContainsKey($groupId)) {
                        $groupFrequency[$groupId]++
                    }
                    else {
                        $groupFrequency[$groupId] = 1
                    }
                }
                $sampleGroupsByUser[$sampleUserId] = $groupsForUser.ToArray()
            }
        }

        $minimumHits = [Math]::Max(2, [int][Math]::Ceiling($sampleIds.Count * ($probeFrequencyPercent / 100.0)))
        $rankedGroupIds = @($groupFrequency.GetEnumerator() |
            Where-Object { $_.Value -ge $minimumHits } |
            Sort-Object -Property @{ Expression = { $_.Value }; Descending = $true }, @{ Expression = { [string]$_.Key }; Descending = $false } |
            Select-Object -First $probeCandidateLimit |
            ForEach-Object { [Guid]$_.Key })
        $candidateById = @{}
        foreach ($groupId in $rankedGroupIds) {
            $candidateById[[string]$groupId] = [PSCustomObject]@{
                GroupId       = $groupId
                SampleUserIds = [System.Collections.Generic.HashSet[Guid]]::new()
            }
        }
        foreach ($sampleUserId in $sampleGroupsByUser.Keys) {
            foreach ($groupId in $sampleGroupsByUser[$sampleUserId]) {
                $candidate = $candidateById[[string]$groupId]
                if ($candidate) {
                    [void]$candidate.SampleUserIds.Add($sampleUserId)
                }
            }
        }
        $candidates = @($rankedGroupIds | ForEach-Object { $candidateById[[string]$_] })

        Write-CheckUserGroupStage -Stage 'BroadGroupProbe' -State 'Completed' -Stopwatch $probeStopwatch -Details "Probe=$ProbeNumber; Candidates=$($candidates.Count); MinimumHits=$minimumHits; TruncatedResponses=$($scanMetrics.ProbeTruncatedResponses); PlanningFailures=$($planningFailureStore.Total)"
        return [PSCustomObject]@{
            SampleIds  = [Guid[]]$sampleIds
            Candidates = $candidates
        }
    }

    # Candidate counts estimate scan cost only. The exact ID set, never these eventually consistent
    # counts, determines whether every current Member/Guest user was covered.
    function Add-BroadGroupCandidateCount {
        param(
            [Parameter(Mandatory=$true)]
            [AllowEmptyCollection()]
            [object[]] $Candidates
        )

        if ($Candidates.Count -eq 0) {
            return @()
        }

        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($candidate in $Candidates) {
            [void]$items.Add([PSCustomObject]@{
                Key      = [string]$candidate.GroupId
                EntityId = [string]$candidate.GroupId
                Url      = "/groups/$($candidate.GroupId)/members/microsoft.graph.user?`$select=id&`$top=1&`$count=true"
            })
        }

        $countResult = Invoke-GraphBatchRequestSet -Items $items.ToArray() -Stage 'CandidatePlanning' -Endpoint 'GroupUserCount' -FailureKind 'Planning'
        $countByGroup = @{}
        foreach ($success in @($countResult.Successful)) {
            $countValue = 0L
            if ($null -ne $success.Body.'@odata.count' -and [long]::TryParse([string]$success.Body.'@odata.count', [ref]$countValue)) {
                $countByGroup[[string]$success.Item.EntityId] = $countValue
                $scanMetrics.CandidateCounts++
            }
        }

        $countedCandidates = [System.Collections.Generic.List[object]]::new()
        foreach ($candidate in $Candidates) {
            $candidateKey = [string]$candidate.GroupId
            if (-not $countByGroup.ContainsKey($candidateKey)) {
                continue
            }
            [void]$countedCandidates.Add([PSCustomObject]@{
                GroupId       = $candidate.GroupId
                SampleUserIds = $candidate.SampleUserIds
                DirectUserCount = [long]$countByGroup[$candidateKey]
                EstimatedPages  = [Math]::Max(1, [int][Math]::Ceiling($countByGroup[$candidateKey] / [double]$membershipPageSize))
            })
        }

        return $countedCandidates.ToArray()
    }

    # Scan direct user members for one or more groups. nextLink pages return to the queue so one
    # very large group cannot permanently block other groups that may cover the remaining users.
    function Invoke-GroupMembershipScan {
        param(
            [Parameter(Mandatory=$true)]
            [AllowEmptyCollection()]
            [Guid[]] $GroupIds,
            [Parameter(Mandatory=$true)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.HashSet[Guid]] $UncoveredUserIds,
            [Parameter(Mandatory=$true)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.HashSet[Guid]] $CompletedGroupIds,
            [Parameter(Mandatory=$true)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.HashSet[Guid]] $AttemptedGroupIds,
            [Parameter(Mandatory=$true)]
            [string] $Source,
            [ValidateSet('Terminal', 'Pending')]
            [string] $FailureKind = 'Pending',
            [bool] $AllowDirectSwitch = $false,
            [int] $TotalGroupCount = 0
        )

        $stageStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $progressStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $queue = [System.Collections.Generic.Queue[object]]::new()
        $groupStates = @{}
        foreach ($groupId in $GroupIds) {
            if ($CompletedGroupIds.Contains($groupId) -or $groupStates.ContainsKey([string]$groupId)) {
                continue
            }

            $groupKey = [string]$groupId
            $groupStates[$groupKey] = [PSCustomObject]@{
                GroupId       = $groupId
                PageCount     = 0
                RecordCount   = 0
                NewlyCovered  = 0
                StartedAt     = $null
            }
            $queue.Enqueue([PSCustomObject]@{
                Key                   = "$groupKey|1"
                EntityId              = $groupKey
                Url                   = "/groups/$groupKey/members/microsoft.graph.user?`$select=id&`$top=$membershipPageSize&`$count=true"
                GroupId               = $groupId
                PageNumber            = 1
                KnownFullContinuation = $false
            })
        }

        Write-CheckUserGroupStage -Stage 'GroupMembership' -State 'Started' -Stopwatch $stageStopwatch -Details "Source=$Source; GroupsQueued=$($queue.Count); Uncovered=$($UncoveredUserIds.Count)"
        $failedGroups = [System.Collections.Generic.HashSet[Guid]]::new()
        $switchToDirect = $false
        $lastPathCheckGroups = $scanMetrics.GroupsCompleted

        while ($queue.Count -gt 0 -and $UncoveredUserIds.Count -gt 0 -and -not $switchToDirect) {
            $batchItems = [System.Collections.Generic.List[object]]::new()
            $knownFullContinuations = 0
            while ($queue.Count -gt 0 -and $batchItems.Count -lt $graphBatchRequestSize) {
                $item = $queue.Dequeue()
                if ($item.KnownFullContinuation -and $knownFullContinuations -ge $fullContinuationBatchSize) {
                    # Rotate this large continuation to the back and submit the bounded batch now.
                    # This avoids walking a very large queue just to defer every remaining item.
                    $queue.Enqueue($item)
                    break
                }

                [void]$batchItems.Add($item)
                if ($item.KnownFullContinuation) {
                    $knownFullContinuations++
                }
            }
            if ($batchItems.Count -eq 0) {
                continue
            }

            foreach ($batchItem in $batchItems) {
                if ($batchItem.PageNumber -eq 1 -and $AttemptedGroupIds.Add([Guid]$batchItem.GroupId)) {
                    $scanMetrics.GroupsStarted++
                }
                $groupState = $groupStates[[string]$batchItem.GroupId]
                if ($null -eq $groupState.StartedAt) {
                    $groupState.StartedAt = [DateTime]::UtcNow
                }
            }

            $batchStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $batchResult = Invoke-GraphBatchRequestSet -Items $batchItems.ToArray() -Stage 'GroupMembership' -Endpoint 'GroupMembers' -FailureKind $FailureKind
            $batchRecordCount = 0
            foreach ($failure in @($batchResult.Failed)) {
                [void]$failedGroups.Add([Guid]$failure.Item.EntityId)
            }

            foreach ($success in @($batchResult.Successful)) {
                $item = $success.Item
                $groupId = [Guid]$item.EntityId
                $groupState = $groupStates[[string]$groupId]
                $users = @($success.Body.value)
                $batchRecordCount += $users.Count
                $beforeCount = $UncoveredUserIds.Count
                foreach ($user in $users) {
                    $userId = [Guid]::Empty
                    if ([Guid]::TryParse([string]$user.id, [ref]$userId)) {
                        [void]$UncoveredUserIds.Remove($userId)
                    }
                }

                $groupState.PageCount++
                $groupState.RecordCount += $users.Count
                $groupState.NewlyCovered += ($beforeCount - $UncoveredUserIds.Count)
                $scanMetrics.MembershipPages++
                $scanMetrics.MembershipRecords += $users.Count
                if ($item.PageNumber -eq 1) { $scanMetrics.FirstPages++ } else { $scanMetrics.ContinuationPages++ }

                $nextLink = [string]$success.Body.'@odata.nextLink'
                if ($nextLink -and $UncoveredUserIds.Count -gt 0) {
                    $queue.Enqueue([PSCustomObject]@{
                        Key                   = "$groupId|$($item.PageNumber + 1)"
                        EntityId              = [string]$groupId
                        Url                   = $nextLink
                        GroupId               = $groupId
                        PageNumber            = $item.PageNumber + 1
                        KnownFullContinuation = $users.Count -ge $membershipPageSize
                    })
                    if ($item.PageNumber -eq 1 -and (Test-GroupDiagnosticDetailAllowed -Category 'MultiPage')) {
                        Write-CheckUserGroupDiagnostic -Message "Check-UserGroups multi-page group: Source=$Source; GroupId=$groupId; FirstPageRecords=$($users.Count); NewlyCovered=$($beforeCount - $UncoveredUserIds.Count)"
                    }
                }
                else {
                    [void]$CompletedGroupIds.Add($groupId)
                    $scanMetrics.GroupsCompleted++
                    if ($groupState.PageCount -eq 1) { $scanMetrics.SinglePageGroups++ }
                    elseif ($groupState.PageCount -le 5) { $scanMetrics.TwoToFivePageGroups++ }
                    elseif ($groupState.PageCount -le 20) { $scanMetrics.SixToTwentyPageGroups++ }
                    else { $scanMetrics.OverTwentyPageGroups++ }

                    $groupDuration = ([DateTime]::UtcNow - $groupState.StartedAt).TotalSeconds
                    if (($groupState.PageCount -gt 1 -or $groupDuration -ge $slowGroupDiagnosticThresholdSeconds) -and
                        (Test-GroupDiagnosticDetailAllowed -Category 'NoteworthyGroup')) {
                        Write-CheckUserGroupDiagnostic -Message "Check-UserGroups noteworthy group: Source=$Source; GroupId=$groupId; Pages=$($groupState.PageCount); Records=$($groupState.RecordCount); NewlyCovered=$($groupState.NewlyCovered); DurationSec=$([Math]::Round($groupDuration, 1)); Uncovered=$($UncoveredUserIds.Count)"
                    }
                }
            }

            $graphMetrics.MaximumBatchRecords = [Math]::Max($graphMetrics.MaximumBatchRecords, $batchRecordCount)
            if ($batchStopwatch.Elapsed.TotalSeconds -ge $slowBatchDiagnosticThresholdSeconds -and
                (Test-GroupDiagnosticDetailAllowed -Category 'NoteworthyBatch')) {
                $batchMemory = Get-GroupScanResourceSnapshot
                Write-CheckUserGroupDiagnostic -Message "Check-UserGroups noteworthy batch: Source=$Source; Requests=$($batchItems.Count); Records=$batchRecordCount; DurationSec=$([Math]::Round($batchStopwatch.Elapsed.TotalSeconds, 1)); Queue=$($queue.Count); Uncovered=$($UncoveredUserIds.Count); PrivateMemory=$($batchMemory.PrivateMb) MB"
            }

            if (($scanMetrics.GroupsCompleted - $lastPathCheckGroups -ge $groupPathRecheckInterval) -or
                $progressStopwatch.Elapsed.TotalMinutes -ge $overallProgressMinuteInterval) {
                $progressMemory = Get-GroupScanResourceSnapshot
                Write-CheckUserGroupDiagnostic -Message "Check-UserGroups group progress: Source=$Source; GroupsStarted=$($scanMetrics.GroupsStarted); GroupsCompleted=$($scanMetrics.GroupsCompleted); Pages=$($scanMetrics.MembershipPages); Records=$($scanMetrics.MembershipRecords); Queue=$($queue.Count); Uncovered=$($UncoveredUserIds.Count); Retries=$($graphMetrics.Retries); Throttles429=$($graphMetrics.Throttles429); Elapsed=$($stageStopwatch.Elapsed); PrivateMemory=$($progressMemory.PrivateMb) MB; PeakMemory=$($progressMemory.PeakMb) MB"
                $lastPathCheckGroups = $scanMetrics.GroupsCompleted
                $progressStopwatch.Restart()

                if ($AllowDirectSwitch -and $TotalGroupCount -gt 0) {
                    $directRounds = [int][Math]::Ceiling($UncoveredUserIds.Count / [double]$graphBatchRequestSize)
                    $remainingGroups = [Math]::Max(0, $TotalGroupCount - $AttemptedGroupIds.Count)
                    # Add known continuation/queued requests to unstarted first pages. This keeps the
                    # comparison from making the group path look cheaper after many large groups start.
                    $knownRemainingGroupRequests = $remainingGroups + $queue.Count
                    $groupRounds = [int][Math]::Ceiling($knownRemainingGroupRequests / [double]$graphBatchRequestSize)
                    if ($directRounds -le $groupRounds) {
                        $switchToDirect = $true
                    }
                }
            }
        }

        $state = if ($failedGroups.Count -gt 0) { 'CompletedWithErrors' } elseif ($switchToDirect) { 'SwitchedToDirect' } elseif ($UncoveredUserIds.Count -eq 0) { 'CoverageProven' } else { 'Completed' }
        Write-CheckUserGroupStage -Stage 'GroupMembership' -State $state -Stopwatch $stageStopwatch -Details "Source=$Source; FailedGroups=$($failedGroups.Count); Uncovered=$($UncoveredUserIds.Count); SwitchToDirect=$switchToDirect"
        return [PSCustomObject]@{
            FailedGroupIds = [Guid[]]@($failedGroups)
            SwitchToDirect = $switchToDirect
        }
    }

    # Check the remaining users directly. The endpoint is cast to groups, so directory roles and
    # administrative units cannot incorrectly count as group coverage.
    function Invoke-DirectUserCompletion {
        param(
            [Parameter(Mandatory=$true)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.HashSet[Guid]] $UncoveredUserIds
        )

        $stageStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $userIds = [Guid[]]@($UncoveredUserIds)
        Write-CheckUserGroupStage -Stage 'DirectUserCompletion' -State 'Started' -Stopwatch $stageStopwatch -Details "Users=$($userIds.Count)"
        for ($offset = 0; $offset -lt $userIds.Count; $offset += $graphBatchRequestSize) {
            $lastIndex = [Math]::Min($offset + $graphBatchRequestSize - 1, $userIds.Count - 1)
            $items = [System.Collections.Generic.List[object]]::new()
            foreach ($userId in @($userIds[$offset..$lastIndex])) {
                [void]$items.Add([PSCustomObject]@{
                    Key      = [string]$userId
                    EntityId = [string]$userId
                    Url      = "/users/$userId/memberOf/microsoft.graph.group?`$select=id&`$top=1&`$count=true"
                })
            }

            $directResult = Invoke-GraphBatchRequestSet -Items $items.ToArray() -Stage 'DirectUserCompletion' -Endpoint 'UserMemberOf' -FailureKind 'Terminal'
            foreach ($success in @($directResult.Successful)) {
                $scanMetrics.DirectUsersChecked++
                if (@($success.Body.value).Count -gt 0) {
                    [void]$UncoveredUserIds.Remove([Guid]$success.Item.EntityId)
                }
            }

            if ((($offset / $graphBatchRequestSize) + 1) % 25 -eq 0 -or $lastIndex -eq $userIds.Count - 1) {
                $memory = Get-GroupScanResourceSnapshot
                Write-CheckUserGroupDiagnostic -Message "Check-UserGroups direct-user progress: Completed=$($lastIndex + 1)/$($userIds.Count); Uncovered=$($UncoveredUserIds.Count); Retries=$($graphMetrics.Retries); Throttles429=$($graphMetrics.Throttles429); Elapsed=$($stageStopwatch.Elapsed); PrivateMemory=$($memory.PrivateMb) MB"
            }
        }

        $state = if ($terminalFailureStore.Total -gt 0) { 'CompletedWithErrors' } else { 'Completed' }
        Write-CheckUserGroupStage -Stage 'DirectUserCompletion' -State $state -Stopwatch $stageStopwatch -Details "UsersChecked=$($scanMetrics.DirectUsersChecked); Uncovered=$($UncoveredUserIds.Count)"
    }

    # Enumerate tenant groups only after the group path is selected. Two directory pages are kept
    # at a time, which bounds queued group state while still giving JSON batches enough independent work.
    function Invoke-FullTenantGroupCompletion {
        param(
            [Parameter(Mandatory=$true)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.HashSet[Guid]] $UncoveredUserIds,
            [Parameter(Mandatory=$true)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.HashSet[Guid]] $CompletedGroupIds,
            [Parameter(Mandatory=$true)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.HashSet[Guid]] $AttemptedGroupIds,
            [Parameter(Mandatory=$true)]
            [int] $TotalGroupCount
        )

        $stageStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Write-CheckUserGroupStage -Stage 'FullGroupCompletion' -State 'Started' -Stopwatch $stageStopwatch -Details "Groups=$TotalGroupCount; Uncovered=$($UncoveredUserIds.Count)"
        $groupsUrl = "https://graph.microsoft.com/v1.0/groups?`$select=id&`$top=$membershipPageSize"
        $listComplete = $true
        $switchToDirect = $false

        while ($groupsUrl -and $UncoveredUserIds.Count -gt 0 -and -not $switchToDirect) {
            $windowGroupIds = [System.Collections.Generic.List[Guid]]::new()
            for ($pageInWindow = 0; $pageInWindow -lt 2 -and $groupsUrl; $pageInWindow++) {
                $pageStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    $groupResponse = Invoke-GraphGetWithRetry -Uri $groupsUrl -Headers $headers
                }
                catch {
                    $listComplete = $false
                    Add-ErrorRecordFailure -Kind 'Pending' -Stage 'FullGroupCompletion' -Endpoint 'GroupList' -ErrorRecord $_
                    $groupsUrl = $null
                    break
                }

                $scanMetrics.GroupListPages++
                foreach ($group in @($groupResponse.value)) {
                    $groupId = [Guid]::Empty
                    if ([Guid]::TryParse([string]$group.id, [ref]$groupId) -and -not $CompletedGroupIds.Contains($groupId)) {
                        [void]$windowGroupIds.Add($groupId)
                    }
                }
                $groupsUrl = [string]$groupResponse.'@odata.nextLink'

                if ($diagnosticLevel -eq 'Validation') {
                    Write-CheckUserGroupDiagnostic -Message "Check-UserGroups group-list page: Page=$($scanMetrics.GroupListPages); GroupsQueued=$($windowGroupIds.Count); HasNextPage=$([bool]$groupsUrl); Duration=$($pageStopwatch.Elapsed)"
                }
            }

            if ($windowGroupIds.Count -gt 0) {
                $scanResult = Invoke-GroupMembershipScan -GroupIds $windowGroupIds.ToArray() -UncoveredUserIds $UncoveredUserIds -CompletedGroupIds $CompletedGroupIds -AttemptedGroupIds $AttemptedGroupIds -Source 'TenantGroups' -FailureKind 'Pending' -AllowDirectSwitch $true -TotalGroupCount $TotalGroupCount
                $switchToDirect = $scanResult.SwitchToDirect
            }
        }

        $state = if (-not $listComplete) { 'CompletedWithErrors' } elseif ($switchToDirect) { 'SwitchedToDirect' } elseif ($UncoveredUserIds.Count -eq 0) { 'CoverageProven' } else { 'Completed' }
        Write-CheckUserGroupStage -Stage 'FullGroupCompletion' -State $state -Stopwatch $stageStopwatch -Details "GroupListPages=$($scanMetrics.GroupListPages); Uncovered=$($UncoveredUserIds.Count); SwitchToDirect=$switchToDirect; ListComplete=$listComplete"
        return [PSCustomObject]@{
            ListComplete   = $listComplete
            SwitchToDirect = $switchToDirect
        }
    }

    # Fetch full profiles only for up to 20 proved-uncovered users. These examples help operators
    # remediate the finding; they do not participate in the compliance decision.
    function Get-UserWithoutGroupAdditionalResult {
        param(
            [Parameter(Mandatory=$true)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.HashSet[Guid]] $UncoveredUserIds
        )

        $sampleIds = [Guid[]]@($UncoveredUserIds | Select-Object -First $remediationSampleLimit)
        if ($sampleIds.Count -eq 0) {
            return $null
        }

        $stageStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Write-CheckUserGroupStage -Stage 'RemediationSample' -State 'Started' -Stopwatch $stageStopwatch -Details "Maximum=$remediationSampleLimit; Selected=$($sampleIds.Count)"
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($userId in $sampleIds) {
            [void]$items.Add([PSCustomObject]@{
                Key      = [string]$userId
                EntityId = [string]$userId
                Url      = "/users/$userId?`$select=id,displayName,givenName,userPrincipalName"
            })
        }

        $detailsResult = Invoke-GraphBatchRequestSet -Items $items.ToArray() -Stage 'RemediationSample' -Endpoint 'UserDetails' -FailureKind 'Planning'
        $detailsById = @{}
        foreach ($success in @($detailsResult.Successful)) {
            $detailsById[[string]$success.Item.EntityId] = $success.Body
        }

        $records = [System.Collections.Generic.List[object]]::new()
        foreach ($userId in $sampleIds) {
            $user = $detailsById[[string]$userId]
            [void]$records.Add([PSCustomObject]@{
                UserId            = [string]$userId
                DisplayName       = if ($user) { $user.displayName } else { 'N/A' }
                GivenName         = if ($user) { $user.givenName } else { 'N/A' }
                UserPrincipalName = if ($user) { $user.userPrincipalName } else { 'N/A' }
                Comments          = $msgTable.userNotInGroup
                ReportTime        = $ReportTime
                itsgcode          = $itsgcode
            })
        }

        Write-CheckUserGroupStage -Stage 'RemediationSample' -State 'Completed' -Stopwatch $stageStopwatch -Details "Selected=$($sampleIds.Count); DetailsLoaded=$($detailsById.Count); DetailFailures=$($detailsResult.Failed.Count)"
        return [PSCustomObject]@{
            records = $records.ToArray()
            logType = 'GR2UsersWithoutGroups'
        }
    }

    # Compare the remaining user work with the lower bound for remaining group work.
    # These estimates choose an execution path only; exact user IDs still decide compliance.
    function Get-CompletionPlan {
        param(
            [Parameter(Mandatory=$true)]
            [long] $UncoveredCount,
            [Parameter(Mandatory=$true)]
            [int] $TotalGroupCount,
            [Parameter(Mandatory=$true)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.HashSet[Guid]] $CompletedGroupIds,
            [AllowEmptyCollection()]
            [object[]] $KnownCandidates = @()
        )

        $directRounds = [int][Math]::Ceiling($UncoveredCount / [double]$graphBatchRequestSize)
        $remainingGroups = [Math]::Max(0, $TotalGroupCount - $CompletedGroupIds.Count)
        $groupRounds = [int][Math]::Ceiling($remainingGroups / [double]$graphBatchRequestSize)
        $largestKnownChain = 0
        foreach ($candidate in @($KnownCandidates)) {
            if (-not $CompletedGroupIds.Contains([Guid]$candidate.GroupId)) {
                $largestKnownChain = [Math]::Max($largestKnownChain, [int]$candidate.EstimatedPages)
            }
        }
        $groupRounds = [Math]::Max($groupRounds, $largestKnownChain)
        $selectedPath = if ($directRounds -le $groupRounds) { 'DirectUsers' } else { 'TenantGroups' }

        return [PSCustomObject]@{
            DirectRounds      = $directRounds
            GroupRounds       = $groupRounds
            RemainingGroups   = $remainingGroups
            LargestKnownChain = $largestKnownChain
            SelectedPath      = $selectedPath
            CheapestRounds    = [Math]::Min($directRounds, $groupRounds)
        }
    }

    # Normalize optional client settings. Priority mode changes scan order only; configured-only
    # mode intentionally limits which groups are allowed to prove coverage.
    $configurationStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-CheckUserGroupStage -Stage 'Configuration' -State 'Started' -Stopwatch $configurationStopwatch
    $requestedMode = if ([string]::IsNullOrWhiteSpace($CheckUserGroupsScanMode)) { '' } else { $CheckUserGroupsScanMode.Trim() }
    $rawConfiguredGroupIds = @($CheckUserGroupsGroupIds | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) })
    $scanMode = 'Automatic'
    $configurationRequiresFailure = $false
    if ($requestedMode -in @('Automatic', 'PriorityThenAutomatic', 'ConfiguredGroupsOnly')) {
        $scanMode = $requestedMode
    }
    elseif ($requestedMode) {
        Write-CheckUserGroupDiagnostic -Message "Check-UserGroups configuration warning: UnknownMode=$requestedMode; Action=UseAutomatic"
    }

    # Automatic discovery does not consume client-provided IDs. Warn instead of silently ignoring
    # them so operators know which explicit mode to select for priority or restricted scanning.
    if ($scanMode -eq 'Automatic' -and $rawConfiguredGroupIds.Count -gt 0) {
        Write-CheckUserGroupDiagnostic -Message "Check-UserGroups configuration warning: GroupIdsProvided=$($rawConfiguredGroupIds.Count); Mode=Automatic; Action=IgnoreGroupIds; ValidModes=PriorityThenAutomatic,ConfiguredGroupsOnly"
    }

    $configuredGroupIds = [System.Collections.Generic.List[Guid]]::new()
    $configuredGroupIdSet = [System.Collections.Generic.HashSet[Guid]]::new()
    $malformedConfiguredGroupIds = 0
    $duplicateConfiguredGroupIds = 0
    if ($scanMode -ne 'Automatic') {
        foreach ($rawGroupId in $rawConfiguredGroupIds) {
            $groupId = [Guid]::Empty
            if (-not [Guid]::TryParse(([string]$rawGroupId).Trim(), [ref]$groupId)) {
                $malformedConfiguredGroupIds++
                Write-CheckUserGroupDiagnostic -Message "Check-UserGroups configuration warning: InvalidGroupId=$rawGroupId; Action=Skip"
                continue
            }
            if (-not $configuredGroupIdSet.Add($groupId)) {
                $duplicateConfiguredGroupIds++
                continue
            }
            [void]$configuredGroupIds.Add($groupId)
        }
    }

    if ($scanMode -eq 'PriorityThenAutomatic' -and $configuredGroupIds.Count -eq 0) {
        Write-CheckUserGroupDiagnostic -Message 'Check-UserGroups configuration warning: PriorityThenAutomatic has no usable group IDs; Action=UseAutomatic'
        $scanMode = 'Automatic'
    }
    elseif ($scanMode -eq 'ConfiguredGroupsOnly' -and $configuredGroupIds.Count -eq 0) {
        $configurationRequiresFailure = $true
        Add-CheckUserGroupFailure -Kind 'Terminal' -Stage 'Configuration' -Endpoint 'ConfiguredGroups' -StatusCode 'NoStatus' -GraphCode 'InvalidConfiguration' -Message 'ConfiguredGroupsOnly requires at least one valid group object ID.'
    }

    $acceptedConfiguredIds = if ($configuredGroupIds.Count -le 50) {
        $configuredGroupIds -join ','
    }
    else {
        "$(@($configuredGroupIds | Select-Object -First 10) -join ','),...($($configuredGroupIds.Count - 10) more)"
    }
    Write-CheckUserGroupStage -Stage 'Configuration' -State $(if ($configurationRequiresFailure) { 'Failed' } else { 'Completed' }) -Stopwatch $configurationStopwatch -Details "Mode=$scanMode; Provided=$($rawConfiguredGroupIds.Count); Valid=$($configuredGroupIds.Count); Malformed=$malformedConfiguredGroupIds; Duplicates=$duplicateConfiguredGroupIds; AcceptedIds=$acceptedConfiguredIds"

    # Build one exact, ID-only baseline. Storing GUIDs instead of full profiles keeps memory bounded,
    # while Member/Guest totals come from the same records that the compliance decision evaluates.
    $baselineStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-CheckUserGroupStage -Stage 'UserBaseline' -State 'Started' -Stopwatch $baselineStopwatch -Details "PageSize=$userPageSize"
    $uncoveredUserIds = [System.Collections.Generic.HashSet[Guid]]::new()
    $baselineComplete = $true
    $memberCount = 0
    $guestCount = 0
    $usersUrl = 'https://graph.microsoft.com/v1.0/users?$select=id,userType&$top={0}' -f $userPageSize
    do {
        $userResponse = $null
        try {
            $userResponse = Invoke-GraphGetWithRetry -Uri $usersUrl -Headers $headers
        }
        catch {
            $baselineComplete = $false
            Add-ErrorRecordFailure -Kind 'Terminal' -Stage 'UserBaseline' -Endpoint 'Users' -ErrorRecord $_
            break
        }

        $scanMetrics.UserBaselinePages++
        $users = @($userResponse.value)
        $scanMetrics.UserRecordsReturned += $users.Count
        foreach ($user in $users) {
            if ($user.userType -notin @('Member', 'Guest')) {
                $scanMetrics.SkippedUserRecords++
                continue
            }

            $userId = [Guid]::Empty
            if (-not [Guid]::TryParse([string]$user.id, [ref]$userId)) {
                $baselineComplete = $false
                Add-CheckUserGroupFailure -Kind 'Terminal' -Stage 'UserBaseline' -Endpoint 'Users' -StatusCode 'NoStatus' -GraphCode 'InvalidUserId' -EntityId ([string]$user.id) -Message 'Microsoft Graph returned a Member/Guest user without a valid GUID.'
                continue
            }

            if ($uncoveredUserIds.Add($userId)) {
                if ($user.userType -eq 'Member') { $memberCount++ } else { $guestCount++ }
            }
        }

        $usersUrl = [string]$userResponse.'@odata.nextLink'
        if ($scanMetrics.UserBaselinePages % 25 -eq 0 -or -not $usersUrl) {
            $baselineMemory = Get-GroupScanResourceSnapshot
            Write-CheckUserGroupDiagnostic -Message "Check-UserGroups baseline progress: Pages=$($scanMetrics.UserBaselinePages); Records=$($scanMetrics.UserRecordsReturned); InScope=$($uncoveredUserIds.Count); Members=$memberCount; Guests=$guestCount; Skipped=$($scanMetrics.SkippedUserRecords); HasNextPage=$([bool]$usersUrl); Elapsed=$($baselineStopwatch.Elapsed); PrivateMemory=$($baselineMemory.PrivateMb) MB"
        }
    } while ($usersUrl)

    $allUserCount = $uncoveredUserIds.Count
    Write-CheckUserGroupStage -Stage 'UserBaseline' -State $(if ($baselineComplete) { 'Completed' } else { 'CompletedWithErrors' }) -Stopwatch $baselineStopwatch -Details "Pages=$($scanMetrics.UserBaselinePages); Users=$allUserCount; Members=$memberCount; Guests=$guestCount; Skipped=$($scanMetrics.SkippedUserRecords)"

    # The exact group total remains required by the inherited minimum-two-groups rule. It is also a
    # planning hint, but it is never used as proof that a particular user has group coverage.
    $groupCountStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-CheckUserGroupStage -Stage 'GroupCount' -State 'Started' -Stopwatch $groupCountStopwatch
    $groupCount = 0
    $groupCountComplete = $true
    try {
        $groupCountResponse = Invoke-GraphGetWithRetry -Uri 'https://graph.microsoft.com/v1.0/groups/$count' -Headers $headers
        if ($null -eq $groupCountResponse -or -not [int]::TryParse([string]$groupCountResponse, [ref]$groupCount)) {
            throw 'Microsoft Graph returned an invalid group count.'
        }
    }
    catch {
        $groupCountComplete = $false
        Add-ErrorRecordFailure -Kind 'Terminal' -Stage 'GroupCount' -Endpoint 'GroupsCount' -ErrorRecord $_
    }
    Write-CheckUserGroupStage -Stage 'GroupCount' -State $(if ($groupCountComplete) { 'Completed' } else { 'Failed' }) -Stopwatch $groupCountStopwatch -Details "Groups=$groupCount"

    Write-CheckUserGroupDiagnostic -Message "Check-UserGroups directory summary: Members=$memberCount; Guests=$guestCount; InScopeUsers=$allUserCount; Groups=$groupCount; BaselineComplete=$baselineComplete; GroupCountComplete=$groupCountComplete"
    Write-CheckUserGroupDiagnostic -Message "Check-UserGroups scan settings: Implementation=$implementationId; Mode=$scanMode; GraphBatchLimit=$graphBatchRequestSize; FullContinuationLimit=$fullContinuationBatchSize; ConcurrentBatchCalls=$concurrentGraphBatchCalls; ProbeSample=$probeSampleSize; CandidateLimit=$probeCandidateLimit; MaxRetries=$defaultMaxRetries"

    $completedGroupIds = [System.Collections.Generic.HashSet[Guid]]::new()
    $attemptedGroupIds = [System.Collections.Generic.HashSet[Guid]]::new()
    $completionReadComplete = $baselineComplete -and $groupCountComplete -and -not $configurationRequiresFailure
    # Fewer than two groups already fails the inherited minimum-group rule, so a tenant-wide
    # membership scan cannot change the result and would only add avoidable Graph work.
    $coverageWorkRequired = $completionReadComplete -and $allUserCount -gt 1 -and $groupCount -ge 2
    $configuredOnly = $scanMode -eq 'ConfiguredGroupsOnly'
    $candidatePool = @()
    $probeState = $null
    $reprobeUsed = $false

    if ($coverageWorkRequired -and $configuredGroupIds.Count -gt 0) {
        $configuredSource = if ($configuredOnly) { 'ConfiguredOnly' } else { 'ConfiguredPriority' }
        $configuredScan = Invoke-GroupMembershipScan -GroupIds $configuredGroupIds.ToArray() -UncoveredUserIds $uncoveredUserIds -CompletedGroupIds $completedGroupIds -AttemptedGroupIds $attemptedGroupIds -Source $configuredSource -FailureKind 'Pending'
        if ($uncoveredUserIds.Count -eq 0) {
            $scanMetrics.SelectedPath = $configuredSource
        }
        Write-CheckUserGroupDiagnostic -Message "Check-UserGroups configured-group result: Mode=$scanMode; Requested=$($configuredGroupIds.Count); Completed=$($completedGroupIds.Count); Failed=$($configuredScan.FailedGroupIds.Count); Uncovered=$($uncoveredUserIds.Count); NextAction=$(if ($configuredOnly) { 'DecideConfiguredOnly' } elseif ($uncoveredUserIds.Count -eq 0) { 'CoverageProven' } else { 'AutomaticDiscovery' })"
    }

    if ($coverageWorkRequired -and -not $configuredOnly -and $uncoveredUserIds.Count -gt 0) {
        # Probe only when both sides are large enough that choosing better work can save meaningful time.
        if ($uncoveredUserIds.Count -gt $smallUserThreshold -and $groupCount -gt $smallGroupThreshold) {
            $probeNumber = 1
            while ($true) {
                $probeReason = if ($probeNumber -eq 1) { 'InitialAutomaticDiscovery' } else { 'ResidualSampleTooSmall' }
                $probeState = Find-BroadGroupCandidate -UncoveredUserIds $uncoveredUserIds -CompletedGroupIds $completedGroupIds -ProbeNumber $probeNumber -Reason $probeReason
                $candidatePool = @(Add-BroadGroupCandidateCount -Candidates $probeState.Candidates)

                while ($candidatePool.Count -gt 0 -and $uncoveredUserIds.Count -gt 0) {
                    $remainingSampleIds = @($probeState.SampleIds | Where-Object { $uncoveredUserIds.Contains($_) })
                    if ($remainingSampleIds.Count -eq 0) {
                        break
                    }

                    $currentPlan = Get-CompletionPlan -UncoveredCount $uncoveredUserIds.Count -TotalGroupCount $groupCount -CompletedGroupIds $completedGroupIds -KnownCandidates $candidatePool
                    $evaluatedCandidates = [System.Collections.Generic.List[object]]::new()
                    foreach ($candidate in $candidatePool) {
                        if ($completedGroupIds.Contains([Guid]$candidate.GroupId)) {
                            continue
                        }

                        $remainingHits = @($candidate.SampleUserIds | Where-Object { $uncoveredUserIds.Contains($_) }).Count
                        if ($remainingHits -eq 0) {
                            continue
                        }

                        $estimatedCoverage = [long][Math]::Ceiling($uncoveredUserIds.Count * ($remainingHits / [double]$remainingSampleIds.Count))
                        $estimatedCoverage = [Math]::Min($uncoveredUserIds.Count, [Math]::Min([long]$candidate.DirectUserCount, $estimatedCoverage))
                        $projectedUncovered = [Math]::Max(0, $uncoveredUserIds.Count - $estimatedCoverage)
                        $remainingCandidates = @($candidatePool | Where-Object { $_.GroupId -ne $candidate.GroupId })
                        $projectedPlan = Get-CompletionPlan -UncoveredCount $projectedUncovered -TotalGroupCount $groupCount -CompletedGroupIds $completedGroupIds -KnownCandidates $remainingCandidates
                        $expectedSavings = [Math]::Max(0, $currentPlan.CheapestRounds - $projectedPlan.CheapestRounds)
                        $requiredSavings = 2 * [int]$candidate.EstimatedPages
                        $qualifies = $expectedSavings -ge $requiredSavings
                        [void]$evaluatedCandidates.Add([PSCustomObject]@{
                            Candidate         = $candidate
                            RemainingHits     = $remainingHits
                            SampleRemaining   = $remainingSampleIds.Count
                            EstimatedCoverage = $estimatedCoverage
                            ExpectedSavings   = $expectedSavings
                            RequiredSavings   = $requiredSavings
                            Qualifies         = $qualifies
                        })

                        if ($diagnosticLevel -eq 'Validation') {
                            Write-CheckUserGroupDiagnostic -Message "Check-UserGroups candidate plan: Probe=$probeNumber; GroupId=$($candidate.GroupId); SampleHits=$remainingHits/$($remainingSampleIds.Count); DirectUserCount=$($candidate.DirectUserCount); Pages=$($candidate.EstimatedPages); EstimatedCoverage=$estimatedCoverage; CurrentPlan=$($currentPlan.SelectedPath)/$($currentPlan.CheapestRounds); ExpectedSavings=$expectedSavings; RequiredSavings=$requiredSavings; Action=$(if ($qualifies) { 'Eligible' } else { 'Skip' })"
                        }
                    }

                    $selectedCandidate = $evaluatedCandidates |
                        Where-Object { $_.Qualifies } |
                        Sort-Object -Property @{ Expression = { $_.ExpectedSavings }; Descending = $true }, @{ Expression = { $_.RemainingHits }; Descending = $true }, @{ Expression = { $_.Candidate.DirectUserCount }; Descending = $true } |
                        Select-Object -First 1
                    if (-not $selectedCandidate) {
                        break
                    }

                    Write-CheckUserGroupDiagnostic -Message "Check-UserGroups candidate selected: Probe=$probeNumber; GroupId=$($selectedCandidate.Candidate.GroupId); EstimatedPages=$($selectedCandidate.Candidate.EstimatedPages); EstimatedCoverage=$($selectedCandidate.EstimatedCoverage); ExpectedSavings=$($selectedCandidate.ExpectedSavings); RequiredSavings=$($selectedCandidate.RequiredSavings); UncoveredBefore=$($uncoveredUserIds.Count)"
                    $candidateScan = Invoke-GroupMembershipScan -GroupIds ([Guid[]]@($selectedCandidate.Candidate.GroupId)) -UncoveredUserIds $uncoveredUserIds -CompletedGroupIds $completedGroupIds -AttemptedGroupIds $attemptedGroupIds -Source 'BroadCandidate' -FailureKind 'Pending'
                    $scanMetrics.CandidateGroupsScanned++
                    if ($uncoveredUserIds.Count -eq 0) {
                        $scanMetrics.SelectedPath = 'BroadCandidate'
                    }
                    $candidatePool = @($candidatePool | Where-Object { $_.GroupId -ne $selectedCandidate.Candidate.GroupId })
                    if ($candidateScan.FailedGroupIds.Count -gt 0) {
                        Write-CheckUserGroupDiagnostic -Message "Check-UserGroups candidate failed: GroupId=$($selectedCandidate.Candidate.GroupId); Action=ContinueWithExactFallback"
                    }
                }

                if ($uncoveredUserIds.Count -eq 0) {
                    break
                }

                $remainingSampleCount = if ($probeState) {
                    @($probeState.SampleIds | Where-Object { $uncoveredUserIds.Contains($_) }).Count
                }
                else { 0 }
                $fallbackPlan = Get-CompletionPlan -UncoveredCount $uncoveredUserIds.Count -TotalGroupCount $groupCount -CompletedGroupIds $completedGroupIds -KnownCandidates $candidatePool
                $shouldReprobe = -not $reprobeUsed -and
                    $remainingSampleCount -lt $minimumResidualSampleSize -and
                    $uncoveredUserIds.Count -gt $reprobeMinimumUsers -and
                    $fallbackPlan.CheapestRounds -ge $reprobeMinimumRounds
                if (-not $shouldReprobe) {
                    break
                }

                $reprobeUsed = $true
                $scanMetrics.Reprobes++
                $probeNumber++
                Write-CheckUserGroupDiagnostic -Message "Check-UserGroups re-probe decision: Action=Run; RemainingSample=$remainingSampleCount; Uncovered=$($uncoveredUserIds.Count); CheapestFallbackRounds=$($fallbackPlan.CheapestRounds)"
                $probeState = $null
                $candidatePool = @()
            }
        }

        if ($uncoveredUserIds.Count -gt 0) {
            $completionPlan = Get-CompletionPlan -UncoveredCount $uncoveredUserIds.Count -TotalGroupCount $groupCount -CompletedGroupIds $completedGroupIds -KnownCandidates $candidatePool
            $scanMetrics.SelectedPath = $completionPlan.SelectedPath
            Write-CheckUserGroupDiagnostic -Message "Check-UserGroups path selected: Path=$($completionPlan.SelectedPath); DirectUserRounds=$($completionPlan.DirectRounds); GroupRoundsLowerBound=$($completionPlan.GroupRounds); RemainingGroups=$($completionPlan.RemainingGroups); LargestKnownChain=$($completionPlan.LargestKnownChain); Uncovered=$($uncoveredUserIds.Count); TieRule=DirectUsers"

            if ($completionPlan.SelectedPath -eq 'DirectUsers') {
                # Direct checks independently complete the proof, so earlier optional group failures no longer matter.
                $pendingFailureStore.Total = 0
                $pendingFailureStore.Categories.Clear()
                $pendingFailureStore.Details.Clear()
                Invoke-DirectUserCompletion -UncoveredUserIds $uncoveredUserIds
                if ($terminalFailureStore.Total -gt 0) {
                    $completionReadComplete = $false
                }
            }
            else {
                # Try any unscanned high-value candidates before paying to enumerate all tenant groups.
                $priorityFallbackIds = [Guid[]]@($candidatePool |
                    Where-Object { -not $completedGroupIds.Contains([Guid]$_.GroupId) } |
                    Sort-Object -Property DirectUserCount -Descending |
                    ForEach-Object { [Guid]$_.GroupId })
                if ($priorityFallbackIds.Count -gt 0) {
                    [void](Invoke-GroupMembershipScan -GroupIds $priorityFallbackIds -UncoveredUserIds $uncoveredUserIds -CompletedGroupIds $completedGroupIds -AttemptedGroupIds $attemptedGroupIds -Source 'CandidateFallback' -FailureKind 'Pending')
                }

                if ($uncoveredUserIds.Count -gt 0) {
                    $revisedPlan = Get-CompletionPlan -UncoveredCount $uncoveredUserIds.Count -TotalGroupCount $groupCount -CompletedGroupIds $completedGroupIds
                    if ($revisedPlan.SelectedPath -eq 'DirectUsers') {
                        $scanMetrics.SelectedPath = 'DirectUsersAfterCandidates'
                        $pendingFailureStore.Total = 0
                        $pendingFailureStore.Categories.Clear()
                        $pendingFailureStore.Details.Clear()
                        Invoke-DirectUserCompletion -UncoveredUserIds $uncoveredUserIds
                        if ($terminalFailureStore.Total -gt 0) {
                            $completionReadComplete = $false
                        }
                    }
                    else {
                        # Full enumeration retries configured/candidate groups that failed earlier, so clear
                        # their provisional failures before this required complete path starts.
                        $pendingFailureStore.Total = 0
                        $pendingFailureStore.Categories.Clear()
                        $pendingFailureStore.Details.Clear()
                        $fullGroupResult = Invoke-FullTenantGroupCompletion -UncoveredUserIds $uncoveredUserIds -CompletedGroupIds $completedGroupIds -AttemptedGroupIds $attemptedGroupIds -TotalGroupCount $groupCount
                        if ($fullGroupResult.SwitchToDirect -and $uncoveredUserIds.Count -gt 0) {
                            $scanMetrics.SelectedPath = 'DirectUsersAfterGroupProgress'
                            $pendingFailureStore.Total = 0
                            $pendingFailureStore.Categories.Clear()
                            $pendingFailureStore.Details.Clear()
                            Invoke-DirectUserCompletion -UncoveredUserIds $uncoveredUserIds
                            if ($terminalFailureStore.Total -gt 0) {
                                $completionReadComplete = $false
                            }
                        }
                        elseif (-not $fullGroupResult.ListComplete -or $pendingFailureStore.Total -gt 0) {
                            # A failed group read does not have to end as inconclusive. Direct checks
                            # for only the remaining users can still prove coverage independently.
                            Write-CheckUserGroupDiagnostic -Message "Check-UserGroups recovery path: Trigger=IncompleteGroupPath; Action=DirectUsers; Uncovered=$($uncoveredUserIds.Count); PendingFailures=$($pendingFailureStore.Total)"
                            $scanMetrics.SelectedPath = 'DirectUsersAfterGroupFailure'
                            $pendingFailureStore.Total = 0
                            $pendingFailureStore.Categories.Clear()
                            $pendingFailureStore.Details.Clear()
                            Invoke-DirectUserCompletion -UncoveredUserIds $uncoveredUserIds
                            if ($terminalFailureStore.Total -gt 0) {
                                $completionReadComplete = $false
                            }
                        }
                    }
                }
            }
        }
    }
    elseif ($coverageWorkRequired -and $configuredOnly) {
        $scanMetrics.SelectedPath = 'ConfiguredGroupsOnly'
        if ($uncoveredUserIds.Count -gt 0 -and $pendingFailureStore.Total -gt 0) {
            $completionReadComplete = $false
            Merge-PendingFailure
        }
    }

    # Once exact coverage is proved, optional-path failures cannot invalidate it. If required reads
    # are incomplete and IDs remain, fail closed and do not publish potentially innocent user names.
    $coverageProven = $baselineComplete -and $uncoveredUserIds.Count -eq 0
    if ($coverageProven) {
        $pendingFailureStore.Total = 0
        $pendingFailureStore.Categories.Clear()
        $pendingFailureStore.Details.Clear()
    }
    $totalCoveredUsers = [Math]::Max(0, $allUserCount - $uncoveredUserIds.Count)
    $coverageIncomplete = -not $baselineComplete -or -not $groupCountComplete -or $configurationRequiresFailure -or (-not $coverageProven -and -not $completionReadComplete)

    $complianceStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-CheckUserGroupStage -Stage 'CoverageEvaluation' -State 'Started' -Stopwatch $complianceStopwatch -Details "Baseline=$allUserCount; Covered=$totalCoveredUsers; Uncovered=$($uncoveredUserIds.Count); RequiredReadsComplete=$(-not $coverageIncomplete)"
    if ($coverageIncomplete) {
        $IsCompliant = $false
        $commentsArray += "$($msgTable.isNotCompliant) $userGroupScanIncompleteMessage"
        $AdditionalResults.records[0].Comments = $userGroupScanIncompleteMessage
        Write-CheckUserGroupStage -Stage 'CoverageEvaluation' -State 'Incomplete' -Stopwatch $complianceStopwatch -Details "Uncovered=$($uncoveredUserIds.Count); TerminalFailures=$($terminalFailureStore.Total)"
    }
    elseif ($allUserCount -le 1) {
        # Preserve the existing edge rule: a tenant with at most one in-scope user passes this item.
        $IsCompliant = $true
        $commentsArray += "$($msgTable.isCompliant) $($msgTable.userCountOne)"
        Write-CheckUserGroupStage -Stage 'CoverageEvaluation' -State 'PassedSingleUserRule' -Stopwatch $complianceStopwatch
    }
    elseif ($groupCount -lt 2) {
        # Preserve the existing minimum-two-groups rule independently of user coverage.
        $IsCompliant = $false
        $commentsArray += "$($msgTable.isNotCompliant) $($msgTable.userGroupsMany)"
        $AdditionalResults.records[0].Comments = $msgTable.userGroupsMany
        Write-CheckUserGroupStage -Stage 'CoverageEvaluation' -State 'FailedMinimumGroups' -Stopwatch $complianceStopwatch -Details "Groups=$groupCount; Uncovered=$($uncoveredUserIds.Count)"
    }
    elseif (-not $coverageProven) {
        $IsCompliant = $false
        $commentsArray += "$($msgTable.isNotCompliant) $($msgTable.userCountGroupNoMatch)"
        $AdditionalResults = Get-UserWithoutGroupAdditionalResult -UncoveredUserIds $uncoveredUserIds
        Write-CheckUserGroupStage -Stage 'CoverageEvaluation' -State 'FailedUncoveredUsers' -Stopwatch $complianceStopwatch -Details "Uncovered=$($uncoveredUserIds.Count); RemediationLimit=$remediationSampleLimit"
    }
    else {
        # Coverage and the minimum-group rule passed. Preserve the existing CAP requirement:
        # at least one enabled Conditional Access policy must include or exclude a group.
        Write-CheckUserGroupStage -Stage 'CoverageEvaluation' -State 'Passed' -Stopwatch $complianceStopwatch
        $conditionalAccessStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Write-CheckUserGroupStage -Stage 'ConditionalAccessPolicyCheck' -State 'Started' -Stopwatch $conditionalAccessStopwatch
        $capPolicyCount = 0
        $validPolicyCount = 0
        try {
            $capResponse = Invoke-GraphQueryEX -urlPath '/identity/conditionalAccess/policies' -ErrorAction Stop
            $capData = $capResponse.Content
            if ($null -eq $capData -or $null -eq $capData.value) {
                throw 'Microsoft Graph returned no Conditional Access policy collection.'
            }

            $policies = @($capData.value)
            $capPolicyCount = $policies.Count
            $validPolicies = @($policies | Where-Object {
                $_.state -eq 'enabled' -and
                ($_.conditions.users.includeGroups.Count -ge 1 -or $_.conditions.users.excludeGroups.Count -ge 1)
            })
            $validPolicyCount = $validPolicies.Count
            if ($validPolicyCount -gt 0) {
                $IsCompliant = $true
                $commentsArray += "$($msgTable.isCompliant) $($msgTable.reqPolicyUserGroupExists)"
                Write-CheckUserGroupStage -Stage 'ConditionalAccessPolicyCheck' -State 'Passed' -Stopwatch $conditionalAccessStopwatch -Details "Policies=$capPolicyCount; Qualifying=$validPolicyCount"
            }
            else {
                $IsCompliant = $false
                $commentsArray += "$($msgTable.isNotCompliant) $($msgTable.noCAPforAnyGroups)"
                Write-CheckUserGroupStage -Stage 'ConditionalAccessPolicyCheck' -State 'FailedNoQualifyingPolicy' -Stopwatch $conditionalAccessStopwatch -Details "Policies=$capPolicyCount; Qualifying=0"
            }
        }
        catch {
            $IsCompliant = $false
            Add-ErrorRecordFailure -Kind 'Terminal' -Stage 'ConditionalAccessPolicyCheck' -Endpoint 'ConditionalAccessPolicies' -ErrorRecord $_
            $commentsArray += "$($msgTable.isNotCompliant) $userGroupScanIncompleteMessage"
            Write-CheckUserGroupStage -Stage 'ConditionalAccessPolicyCheck' -State 'Incomplete' -Stopwatch $conditionalAccessStopwatch -Details "Policies=$capPolicyCount; Error=$($_.Exception.Message)"
        }
    }

    $commentsArray += ($userStatsMessageTemplate -f $allUserCount, $totalCoveredUsers, $memberCount, $guestCount)
    $Comments = $commentsArray -join '; '
    Write-StructuredFailure

    $finalMemory = Get-GroupScanResourceSnapshot
    $diagnosticPercent = if ($moduleStopwatch.Elapsed.TotalMilliseconds -gt 0) {
        [Math]::Round(($diagnosticMetrics.WriteMs / $moduleStopwatch.Elapsed.TotalMilliseconds) * 100, 3)
    }
    else { 0 }
    Write-CheckUserGroupDiagnostic -Message "Check-UserGroups final summary: Implementation=$implementationId; Mode=$scanMode; Path=$($scanMetrics.SelectedPath); Users=$allUserCount; Covered=$totalCoveredUsers; Uncovered=$($uncoveredUserIds.Count); Groups=$groupCount; UserPages=$($scanMetrics.UserBaselinePages); GroupListPages=$($scanMetrics.GroupListPages); GroupsStarted=$($scanMetrics.GroupsStarted); GroupsCompleted=$($scanMetrics.GroupsCompleted); MembershipPages=$($scanMetrics.MembershipPages); FirstPages=$($scanMetrics.FirstPages); ContinuationPages=$($scanMetrics.ContinuationPages); PageBuckets=1:$($scanMetrics.SinglePageGroups),2-5:$($scanMetrics.TwoToFivePageGroups),6-20:$($scanMetrics.SixToTwentyPageGroups),21Plus:$($scanMetrics.OverTwentyPageGroups); MembershipRecords=$($scanMetrics.MembershipRecords); DirectUsersChecked=$($scanMetrics.DirectUsersChecked); ProbeRuns=$($scanMetrics.ProbeRuns); Reprobes=$($scanMetrics.Reprobes); BatchCalls=$($graphMetrics.BatchCalls); InnerAttempts=$($graphMetrics.InnerAttempts); DirectAttempts=$($graphMetrics.DirectAttempts); Retries=$($graphMetrics.Retries); Throttles429=$($graphMetrics.Throttles429); MaximumBatchRecords=$($graphMetrics.MaximumBatchRecords); ResourceUnits=$([Math]::Round($graphMetrics.ResourceUnits, 1)); MaximumThrottlePercentage=$($graphMetrics.MaximumThrottlePercentage); PlanningFailures=$($planningFailureStore.Total); TerminalFailures=$($terminalFailureStore.Total); StructuredErrors=$($ErrorList.Count); IsCompliant=$IsCompliant; Elapsed=$($moduleStopwatch.Elapsed); PrivateMemory=$($finalMemory.PrivateMb) MB; PeakMemory=$($finalMemory.PeakMb) MB; ProcessorSeconds=$($finalMemory.ProcessorSeconds); DiagnosticLines=$($diagnosticMetrics.Lines + 1); DiagnosticCharacters=$($diagnosticMetrics.Characters); DiagnosticWriteMs=$([Math]::Round($diagnosticMetrics.WriteMs, 1)); DiagnosticRuntimePercent=$diagnosticPercent"

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
        $profileStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $profileErrorStart = $ErrorList.Count
        Write-CheckUserGroupStage -Stage 'ProfileEnrichment' -State 'Started' -Stopwatch $profileStopwatch
        $result = Add-ProfileInformation -Result $PsObject -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId -ErrorList $ErrorList
        Write-Host "$result"
        $profileState = if ($ErrorList.Count -gt $profileErrorStart) { 'CompletedWithErrors' } else { 'Completed' }
        Write-CheckUserGroupStage -Stage 'ProfileEnrichment' -State $profileState -Stopwatch $profileStopwatch
    }
    
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    $moduleState = if ($ErrorList.Count -gt 0) { 'CompletedWithErrors' } else { 'Completed' }
    Write-CheckUserGroupStage -Stage 'Module' -State $moduleState -Stopwatch $moduleStopwatch -Details "IsCompliant=$IsCompliant; TotalErrors=$($ErrorList.Count)"
    return $moduleOutput   
}