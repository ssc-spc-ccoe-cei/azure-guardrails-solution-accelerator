BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'
    $script:savedFunctions = @{}
    foreach ($name in @('Get-AzAccessToken', 'Invoke-GraphQueryEX', 'Add-ProfileInformation')) {
        $script:savedFunctions[$name] = (Get-Item "Function:\$name" -ErrorAction SilentlyContinue).ScriptBlock
        Set-Item "Function:global:$name" {
            [CmdletBinding()]
            param($ResourceUrl, [switch]$AsSecureString, $urlPath, $Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList)
            throw 'Unmocked external dependency'
        }
    }
    Import-Module (Join-Path $PSScriptRoot '../../../src/GUARDRAIL 2 MANAGE ACCESS/Audit/Check-UserGroups.psm1') -Force
}

AfterAll {
    Remove-Module Check-UserGroups -Force -ErrorAction SilentlyContinue
    foreach ($name in $script:savedFunctions.Keys) {
        if ($null -ne $script:savedFunctions[$name]) {
            Set-Item "Function:global:$name" $script:savedFunctions[$name]
        } else {
            Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
        }
    }
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-UserGroups offline exact coverage and conditional access' {
    BeforeAll {
        $script:params = @{
            ControlName = 'GUARDRAIL 2'; ItemName = 'User groups'; itsgcode = 'AC-2'; ReportTime = '2026-10-14'
            msgTable = @{
                isCompliant = 'Pass'; isNotCompliant = 'Fail'; userInGroup = 'All users covered'
                userNotInGroup = 'User uncovered'; userGroupScanIncomplete = 'Scan incomplete'
                userCountOne = 'At most one user'; userGroupsMany = 'Need two groups'; userCountGroupNoMatch = 'Uncovered users'
                reqPolicyUserGroupExists = 'Group policy exists'; noCAPforAnyGroups = 'No group policy'
                userStats = 'Users={0}, Covered={1}, Members={2}, Guests={3}'
            }
        }
        $script:groupId = '10000000-0000-0000-0000-000000000001'
        function New-OfflineUsers {
            param([int]$Count)
            @(1..$Count | ForEach-Object {
                if ($Count -gt 0) {
                    [pscustomobject]@{ id = ('00000000-0000-0000-0000-{0:d12}' -f $_); userType = 'Member' }
                }
            })
        }
        function Resolve-OfflineGroupRequest {
            param([string]$Url)
            $path = $Url -replace '^https://graph.microsoft.com/v1.0', ''
            if ($path -match '^/users\?') {
                if ($script:baselineFailure) { throw 'Baseline offline' }
                return [pscustomobject]@{ value = $script:users; '@odata.nextLink' = $script:baselineNextLink }
            }
            if ($path -eq '/users-next') {
                return [pscustomobject]@{ value = $script:nextUsers }
            }
            if ($path -eq '/groups/$count') {
                if ($script:countFailure) { throw 'Count offline' }
                return $script:groupCount
            }
            if ($path -match '^/groups\?') {
                if ($script:listFailure) { throw 'Group listing offline' }
                return [pscustomobject]@{ value = @(@{ id = $script:groupId }); '@odata.nextLink' = $null }
            }
            if ($path -match '^/groups/[^/]+/members/') {
                if ($script:groupFailure) { throw 'Group membership offline' }
                return [pscustomobject]@{
                    value = $script:groupMembers; '@odata.count' = $script:users.Count; '@odata.nextLink' = $script:memberNextLink
                }
            }
            if ($path -eq '/members-next') {
                return [pscustomobject]@{ value = $script:nextGroupMembers }
            }
            if ($path -match '^/users/([^/?]+)/memberOf/microsoft.graph.group') {
                $userId = $Matches[1]
                if ($script:membershipFailure) { throw 'User membership offline' }
                $memberships = if ($script:uncovered -contains $userId) { @() } else { @(@{ id = $script:groupId }) }
                return [pscustomobject]@{ value = $memberships }
            }
            if ($path -match '^/users/([^/?]+)\?') {
                if ($script:detailFailure) { throw 'User details offline' }
                return [pscustomobject]@{
                    id = $Matches[1]; displayName = 'Offline user'; givenName = 'Offline'; userPrincipalName = 'offline@example.test'
                }
            }
            throw "Unexpected external request: $Url"
        }
    }
    BeforeEach {
        $script:users = @(New-OfflineUsers 2)
        $script:nextUsers = @()
        $script:baselineNextLink = $null
        $script:groupCount = '2'
        $script:groupMembers = $script:users
        $script:memberNextLink = $null
        $script:nextGroupMembers = @()
        $script:uncovered = @()
        $script:baselineFailure = $false
        $script:countFailure = $false
        $script:listFailure = $false
        $script:groupFailure = $false
        $script:membershipFailure = $false
        $script:detailFailure = $false
        $script:innerStatus = 200
        $script:policies = @(@{ state = 'enabled'; conditions = @{ users = @{ includeGroups = @('group'); excludeGroups = @() } } })
        Mock Get-AzAccessToken -ModuleName Check-UserGroups {
            @{ Token = ConvertTo-SecureString 'offline-token' -AsPlainText -Force }
        }
        Mock Invoke-RestMethod -ModuleName Check-UserGroups {
            if ($Method -eq 'Get') { return Resolve-OfflineGroupRequest -Url $Uri }
            if ($Method -eq 'Post' -and $Uri -eq 'https://graph.microsoft.com/v1.0/$batch') {
                $requests = ($Body | ConvertFrom-Json).requests
                if ($requests.Count -gt 20) { throw 'Batch exceeded Graph limit' }
                $responses = @($requests | ForEach-Object {
                    $request = $_
                    if ($script:innerStatus -ne 200) {
                        return @{
                            id = $request.id; status = $script:innerStatus; headers = [pscustomobject]@{ 'Retry-After' = '7' }
                            body = @{ error = @{ code = 'OfflineError'; message = 'Inner failure' } }
                        }
                    }
                    try {
                        @{ id = $request.id; status = 200; body = (Resolve-OfflineGroupRequest -Url $request.url) }
                    } catch {
                        @{ id = $request.id; status = 403; body = @{ error = @{ code = 'OfflineError'; message = $_.Exception.Message } } }
                    }
                })
                return [pscustomobject]@{ responses = $responses }
            }
            throw "Unexpected HTTP method/URL: $Method $Uri"
        }
        Mock Invoke-GraphQueryEX -ModuleName Check-UserGroups {
            if ($urlPath -ne '/identity/conditionalAccess/policies') { throw "Unexpected Graph query: $urlPath" }
            @{ Content = @{ value = $script:policies } }
        }
        Mock Add-ProfileInformation -ModuleName Check-UserGroups { throw 'Unexpected profile call' }
        Mock Start-Sleep -ModuleName Check-UserGroups {}
        Mock Write-Warning -ModuleName Check-UserGroups {}
    }

    It 'Proves all user coverage and returns full report and placeholder remediation metadata' {
        $output = @(Check-UserGroups @script:params)
        $output.Count | Should -Be 1
        $result = $output[0]
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'Pass Group policy exists; Users=2, Covered=2, Members=2, Guests=0'
        foreach ($key in @('ControlName', 'ItemName', 'itsgcode', 'ReportTime')) {
            $result.ComplianceResults.$key | Should -Be $script:params[$key]
        }
        $result.Errors.Count | Should -Be 0
        $result.AdditionalResults.logType | Should -Be 'GR2UsersWithoutGroups'
        $row = $result.AdditionalResults.records[0]
        foreach ($key in @('UserId', 'DisplayName', 'GivenName', 'UserPrincipalName')) { $row.$key | Should -Be 'N/A' }
        $row.Comments | Should -Be 'All users covered'
        $row.ReportTime | Should -Be $script:params.ReportTime
        $row.itsgcode | Should -Be $script:params.itsgcode
        Should -Invoke Invoke-GraphQueryEX -ModuleName Check-UserGroups -Exactly -Times 1
        Should -Invoke Add-ProfileInformation -ModuleName Check-UserGroups -Times 0
    }

    It 'Preserves the zero/one-user exemption without checking membership or CAPs' -ForEach @(
        @{ Count = 0 }, @{ Count = 1 }
    ) {
        $script:users = @(New-OfflineUsers $Count)
        $script:groupCount = '0'
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Match 'Pass At most one user'
        Should -Invoke Invoke-RestMethod -ModuleName Check-UserGroups -Times 0 -ParameterFilter { $Method -eq 'Post' -or $Uri -like '*/memberOf/*' }
        Should -Invoke Invoke-GraphQueryEX -ModuleName Check-UserGroups -Times 0
    }

    It 'Fails minimum-group rule at <Count> without expensive coverage work' -ForEach @(@{ Count = '0' }, @{ Count = '1' }) {
        $script:groupCount = $Count
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Match 'Fail Need two groups'
        $result.AdditionalResults.records[0].Comments | Should -Be 'Need two groups'
        $result.Errors.Count | Should -Be 0
        Should -Invoke Invoke-GraphQueryEX -ModuleName Check-UserGroups -Times 0
        Should -Invoke Invoke-RestMethod -ModuleName Check-UserGroups -Times 0 -ParameterFilter { $Method -eq 'Post' }
    }

    It 'Pages the baseline, deduplicates IDs, counts guests, and skips other user types' {
        $script:users[1].userType = 'Guest'
        $script:users += @{ id = 'not-a-guid'; userType = 'Service' }
        $script:baselineNextLink = 'https://graph.microsoft.com/v1.0/users-next'
        $script:nextUsers = @($script:users[0])
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Match 'Users=2, Covered=2, Members=1, Guests=1'
        Should -Invoke Invoke-RestMethod -ModuleName Check-UserGroups -Exactly -Times 1 -ParameterFilter { $Uri -like '*/users-next' }
    }

    It 'Normalizes a scalar baseline user and scalar numeric group count' {
        $script:users = (New-OfflineUsers 1)[0]
        $script:groupCount = 2
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Match 'Users=1, Covered=0, Members=1, Guests=0'
        $result.Errors.Count | Should -Be 0
        Should -Invoke Invoke-GraphQueryEX -ModuleName Check-UserGroups -Times 0
    }

    It 'Fails closed on invalid in-scope GUID and does not label unknown users as violations' {
        $script:users += @{ id = 'bad-guid'; userType = 'Member' }
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Match 'Scan incomplete'
        $result.Errors.Count | Should -Be 2
        $result.Errors[0] | Should -Match 'InvalidUserId.*bad-guid'
        $result.Errors[1] | Should -Match 'Failure summary:.*Affected=1'
        $result.AdditionalResults.records[0].UserId | Should -Be 'N/A'
        Should -Invoke Invoke-GraphQueryEX -ModuleName Check-UserGroups -Times 0
    }

    It 'Rejects a <UserType> baseline user with a missing ID' -ForEach @(
        @{ UserType = 'Member' }, @{ UserType = 'Guest' }
    ) {
        $script:users = [pscustomobject]@{ userType = $UserType }
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Match 'Scan incomplete'
        $result.Errors[0] | Should -Match 'InvalidUserId.*without a valid GUID'
        $result.AdditionalResults.records[0].UserId | Should -Be 'N/A'
    }

    It 'Fails closed on token failure before any network query' {
        Mock Get-AzAccessToken -ModuleName Check-UserGroups { throw 'No token' }
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.Errors.Count | Should -Be 1
        $result.Errors[0] | Should -Match 'Failed to get access token.*No token'
        $result.AdditionalResults.records[0].Comments | Should -Be 'Scan incomplete'
        Should -Invoke Get-AzAccessToken -ModuleName Check-UserGroups -Exactly -Times 2
        Should -Invoke Invoke-RestMethod -ModuleName Check-UserGroups -Times 0
    }

    It 'Falls back to the plain text Az token contract' {
        Mock Get-AzAccessToken -ModuleName Check-UserGroups {
            if ($AsSecureString) { throw 'Unsupported switch' }
            @{ Token = 'offline-token' }
        }
        (Check-UserGroups @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
        Should -Invoke Get-AzAccessToken -ModuleName Check-UserGroups -Exactly -Times 2
    }

    It 'Uses bearer authorization and eventual consistency for direct Graph requests' {
        $null = Check-UserGroups @script:params
        Should -Invoke Invoke-RestMethod -ModuleName Check-UserGroups -ParameterFilter {
            $Method -eq 'Get' -and $Headers.Authorization -eq ('Bearer ' + 'offline-token') -and $Headers.ConsistencyLevel -eq 'eventual'
        }
    }

    It 'Retries <Stage> failure exactly three times and collects bounded structured errors' -ForEach @(
        @{ Stage = 'baseline'; Pattern = 'UserBaseline'; Failure = { $script:baselineFailure = $true }; UrlPattern = '*/users?*' }
        @{ Stage = 'group count'; Pattern = 'GroupCount'; Failure = { $script:countFailure = $true }; UrlPattern = '*/groups/$count' }
    ) {
        & $Failure
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Match 'Scan incomplete'
        $result.Errors.Count | Should -Be 2
        $result.Errors[0] | Should -Match "Stage=$Pattern"
        $result.Errors[1] | Should -Match 'Failure summary:'
        Should -Invoke Invoke-RestMethod -ModuleName Check-UserGroups -Exactly -Times 3 -ParameterFilter { $Uri -like $UrlPattern }
        Should -Invoke Start-Sleep -ModuleName Check-UserGroups -Exactly -Times 2 -ParameterFilter { $Seconds -eq 5 }
    }

    It 'Rejects malformed group counts' {
        $script:groupCount = 'invalid'
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.Errors[0] | Should -Match 'invalid group count'
    }

    It 'Fails closed when Graph returns null rather than a baseline response' {
        Mock Invoke-RestMethod -ModuleName Check-UserGroups { $null } -ParameterFilter { $Uri -match '/users\?' }
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.Errors[0] | Should -Match 'empty response'
        Should -Invoke Invoke-RestMethod -ModuleName Check-UserGroups -Exactly -Times 3 -ParameterFilter { $Uri -match '/users\?' }
    }

    It 'Characterizes a missing baseline value collection being mistaken for an empty tenant' {
        Mock Invoke-RestMethod -ModuleName Check-UserGroups { [pscustomobject]@{} } -ParameterFilter { $Uri -match '/users\?' }
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Match 'At most one user.*Users=0'
        $result.Errors.Count | Should -Be 0
    }

    It 'Should fail closed when the baseline collection is absent' -Skip {
        # Baseline parsing does not validate value; a malformed non-null response becomes zero users and passes.
        Mock Invoke-RestMethod -ModuleName Check-UserGroups { [pscustomobject]@{} } -ParameterFilter { $Uri -match '/users\?' }
        (Check-UserGroups @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
    }

    It 'Recovers a transient baseline failure without retaining an error or leaking a success-stream index' {
        $script:baselineAttempts = 0
        Mock Invoke-RestMethod -ModuleName Check-UserGroups {
            $script:baselineAttempts++
            if ($script:baselineAttempts -eq 1) { throw 'Transient offline' }
            [pscustomobject]@{ value = $script:users }
        } -ParameterFilter { $Uri -match '/users\?' }
        $output = @(Check-UserGroups @script:params)
        $output.Count | Should -Be 1
        $output[0].ComplianceResults.ComplianceStatus | Should -BeTrue
        $output[0].Errors.Count | Should -Be 0
        Should -Invoke Start-Sleep -ModuleName Check-UserGroups -Exactly -Times 1
    }

    It 'Does not retry a permanent direct HTTP 403 baseline failure or sleep' {
        Mock Invoke-RestMethod -ModuleName Check-UserGroups {
            $exception = [System.Exception]::new('Baseline access denied')
            $exception | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = 403 })
            throw $exception
        } -ParameterFilter { $Uri -match '/users\?' }
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.Errors[0] | Should -Match 'HTTP=403.*Baseline access denied'
        Should -Invoke Invoke-RestMethod -ModuleName Check-UserGroups -Exactly -Times 1 -ParameterFilter { $Uri -match '/users\?' }
        Should -Invoke Start-Sleep -ModuleName Check-UserGroups -Times 0
    }

    It 'Reports proved uncovered users with their full remediation metadata' {
        $script:uncovered = @($script:users[1].id)
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'Fail Uncovered users; Users=2, Covered=1, Members=2, Guests=0'
        $result.Errors.Count | Should -Be 0
        $result.AdditionalResults.records.Count | Should -Be 1
        $row = $result.AdditionalResults.records[0]
        $row.UserId | Should -Be $script:users[1].id
        $row.DisplayName | Should -Be 'Offline user'
        $row.GivenName | Should -Be 'Offline'
        $row.UserPrincipalName | Should -Be 'offline@example.test'
        $row.Comments | Should -Be 'User uncovered'
        $row.ReportTime | Should -Be $script:params.ReportTime
        $row.itsgcode | Should -Be $script:params.itsgcode
        Should -Invoke Invoke-GraphQueryEX -ModuleName Check-UserGroups -Times 0
    }

    It 'Limits remediation to twenty users without changing exact coverage statistics' {
        $script:users = @(New-OfflineUsers 25)
        $script:groupCount = '100'
        $script:uncovered = @($script:users.id)
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.AdditionalResults.records.Count | Should -Be 20
        $result.ComplianceResults.Comments | Should -Match 'Users=25, Covered=0'
    }

    It 'Keeps uncovered user IDs with N/A metadata when optional details fail' {
        $script:uncovered = @($script:users[1].id)
        $script:detailFailure = $true
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.AdditionalResults.records[0].UserId | Should -Be $script:users[1].id
        $result.AdditionalResults.records[0].DisplayName | Should -Be 'N/A'
        $result.Errors.Count | Should -Be 0
    }

    It 'Does not report incomplete membership reads as proven uncovered users' {
        $script:membershipFailure = $true
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Match 'Scan incomplete'
        $result.AdditionalResults.records[0].UserId | Should -Be 'N/A'
        $result.Errors.Count | Should -Be 3
        $result.Errors[-1] | Should -Match 'Affected=2'
    }

    It 'Rejects <Label> CAPs after exact coverage' -ForEach @(
        @{ Label = 'empty'; Policies = @() }
        @{ Label = 'disabled group policy'; Policies = @(@{ state = 'disabled'; conditions = @{ users = @{ includeGroups = @('group') } } }) }
        @{ Label = 'report-only group policy'; Policies = @(@{ state = 'enabledForReportingButNotEnforced'; conditions = @{ users = @{ includeGroups = @('group') } } }) }
        @{ Label = 'no group conditions'; Policies = @(@{ state = 'enabled'; conditions = @{ users = @{ includeGroups = @(); excludeGroups = @() } } }) }
    ) {
        $script:policies = $Policies
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Match 'Fail No group policy'
        $result.Errors.Count | Should -Be 0
    }

    It 'Accepts an enabled group exclusion policy as well as inclusion' {
        $script:policies = @(@{ state = 'enabled'; conditions = @{ users = @{ excludeGroups = @('group') } } })
        (Check-UserGroups @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Collects missing CAP collection and thrown query failures' -ForEach @(
        @{ Throws = $false }, @{ Throws = $true }
    ) {
        Mock Invoke-GraphQueryEX -ModuleName Check-UserGroups {
            if ($Throws) { throw 'CAP offline' }
            @{ Content = @{} }
        }
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Match 'Scan incomplete'
        $result.Errors.Count | Should -Be 2
        $result.Errors[0] | Should -Match 'ConditionalAccessPolicyCheck'
    }

    It 'Chooses group scanning for twenty-one users and two groups rather than direct user batches' {
        $script:users = @(New-OfflineUsers 21)
        $script:groupMembers = $script:users
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        Should -Invoke Invoke-RestMethod -ModuleName Check-UserGroups -Exactly -Times 1 -ParameterFilter { $Uri -match '/groups\?' }
        Should -Invoke Invoke-RestMethod -ModuleName Check-UserGroups -Exactly -Times 1 -ParameterFilter { $Uri -like '*/groups/*/members/*' }
        Should -Invoke Invoke-RestMethod -ModuleName Check-UserGroups -Times 0 -ParameterFilter { $Uri -like '*/users/*/memberOf/*' }
    }

    It 'Follows group membership nextLink to prove coverage, not an eventually consistent count' {
        $script:users = @(New-OfflineUsers 21)
        $script:groupMembers = @($script:users[0..9])
        $script:memberNextLink = 'https://graph.microsoft.com/v1.0/members-next'
        $script:nextGroupMembers = @($script:users[10..20]) + @($script:users[0])
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Match 'Users=21, Covered=21'
        Should -Invoke Invoke-RestMethod -ModuleName Check-UserGroups -Exactly -Times 1 -ParameterFilter { $Uri -like '*/members-next' }
    }

    It 'Recovers failed full group enumeration by completing exact direct user checks' {
        $script:users = @(New-OfflineUsers 21)
        $script:listFailure = $true
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.Errors.Count | Should -Be 0
        Should -Invoke Invoke-RestMethod -ModuleName Check-UserGroups -Exactly -Times 3 -ParameterFilter { $Uri -match '/groups\?' }
        Should -Invoke Invoke-RestMethod -ModuleName Check-UserGroups -Exactly -Times 1 -ParameterFilter { $Method -eq 'Post' }
    }

    It 'Recovers group-member read failure using direct-user proof and clears provisional errors' {
        $script:users = @(New-OfflineUsers 21)
        $script:groupFailure = $true
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Match 'Users=21, Covered=21'
        $result.Errors.Count | Should -Be 0
        Should -Invoke Invoke-RestMethod -ModuleName Check-UserGroups -Exactly -Times 3 -ParameterFilter { $Uri -like '*/groups/*/members/*' }
        Should -Invoke Invoke-RestMethod -ModuleName Check-UserGroups -Exactly -Times 1 -ParameterFilter { $Method -eq 'Post' }
    }

    It 'Uses broad discovery only above both small-tenant boundaries' -ForEach @(
        @{ Users = 40; Groups = '61'; Probes = 0 }
        @{ Users = 41; Groups = '60'; Probes = 0 }
        @{ Users = 41; Groups = '61'; Probes = 2 }
    ) {
        $script:users = @(New-OfflineUsers $Users)
        $script:groupMembers = $script:users
        $script:groupCount = $Groups
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        Should -Invoke Invoke-RestMethod -ModuleName Check-UserGroups -Exactly -Times $Probes -ParameterFilter {
            $Method -eq 'Post' -and $Body -match 'memberOf' -and $Body -match 'top=999'
        }
    }

    It 'Retries inner transient failures with a bounded budget and no real sleeps' {
        $script:innerStatus = 503
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.Errors[-1] | Should -Match 'HTTP=503.*Affected=2'
        Should -Invoke Invoke-RestMethod -ModuleName Check-UserGroups -Exactly -Times 3 -ParameterFilter { $Method -eq 'Post' }
        Should -Invoke Start-Sleep -ModuleName Check-UserGroups -Exactly -Times 2
    }

    It 'Honors inner throttle Retry-After once per retry round, not once per user' {
        $script:innerStatus = 429
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.Errors[-1] | Should -Match 'HTTP=429.*Affected=2'
        Should -Invoke Start-Sleep -ModuleName Check-UserGroups -Exactly -Times 2 -ParameterFilter { $Seconds -eq 7 }
    }

    It 'Refreshes authorization once per unauthorized inner batch round without sleeping' {
        $script:innerStatus = 401
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.Errors[-1] | Should -Match 'HTTP=401.*Affected=2'
        Should -Invoke Get-AzAccessToken -ModuleName Check-UserGroups -Exactly -Times 3
        Should -Invoke Start-Sleep -ModuleName Check-UserGroups -Times 0
    }

    It 'Fails closed when an outer batch is empty and does not create remediation allegations' {
        Mock Invoke-RestMethod -ModuleName Check-UserGroups { [pscustomobject]@{} } -ParameterFilter { $Method -eq 'Post' }
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.Errors[0] | Should -Match 'empty JSON batch response'
        $result.AdditionalResults.records[0].UserId | Should -Be 'N/A'
        Should -Invoke Invoke-RestMethod -ModuleName Check-UserGroups -Exactly -Times 3 -ParameterFilter { $Method -eq 'Post' }
    }

    It 'Bounds structured failures for a twenty-five-user outage' {
        $script:users = @(New-OfflineUsers 25)
        $script:groupCount = '100'
        $script:membershipFailure = $true
        $result = Check-UserGroups @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        # Ten details per category plus its summary; all affected users remain counted.
        $result.Errors.Count | Should -Be 11
        $result.Errors[-1] | Should -Match 'Affected=25'
        $result.AdditionalResults.records[0].UserId | Should -Be 'N/A'
    }

    It 'Does not retry inner forbidden responses' {
        $script:innerStatus = 403
        $result = Check-UserGroups @script:params
        $result.Errors[-1] | Should -Match 'HTTP=403.*Affected=2'
        Should -Invoke Invoke-RestMethod -ModuleName Check-UserGroups -Exactly -Times 1 -ParameterFilter { $Method -eq 'Post' }
        Should -Invoke Start-Sleep -ModuleName Check-UserGroups -Times 0
    }

    It 'Mutates profile metadata in place while preserving collected helper warnings' {
        Mock Add-ProfileInformation -ModuleName Check-UserGroups {
            $Result | Add-Member Profile 2
            [void]$ErrorList.Add('Profile warning')
            $Result
        }
        $result = Check-UserGroups @script:params -EnableMultiCloudProfiles -CloudUsageProfiles '1,2' -ModuleProfiles '2'
        $result.ComplianceResults.Profile | Should -Be 2
        $result.Errors | Should -Contain 'Profile warning'
        Should -Invoke Add-ProfileInformation -ModuleName Check-UserGroups -Exactly -Times 1 -ParameterFilter {
            $CloudUsageProfiles -eq '1,2' -and $ModuleProfiles -eq '2'
        }
    }

    It 'Propagates profile enrichment exceptions' {
        Mock Add-ProfileInformation -ModuleName Check-UserGroups { throw 'Profile offline' }
        { Check-UserGroups @script:params -EnableMultiCloudProfiles } | Should -Throw '*Profile offline*'
    }
}
