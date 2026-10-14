BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'
    $script:createdStubs = @()
    $script:loadedCommands = @(Get-Command -ListImported).Name
    foreach ($name in @('Get-AzADUser', 'Invoke-AzRestMethod')) {
        if ($name -notin $script:loadedCommands) {
            Set-Item "Function:global:$name" {
                [CmdletBinding()]
                param($Filter, $Uri, $Method)
                throw 'Unmocked external dependency'
            }
            $script:createdStubs += $name
        }
    }
    $script:commonModule = $null
    if (-not (Get-Module GR-Common)) {
        $script:commonModule = Import-Module (Join-Path $PSScriptRoot '../../../src/Guardrails-Common/GR-Common.psm1') -Global -NoClobber -PassThru
    }
    $script:module = Import-Module (Join-Path $PSScriptRoot '../../../src/GUARDRAIL 2 MANAGE ACCESS/Audit/Check-UserRoleReviews.psm1') -Force -PassThru
    & $script:module { $script:subscriptionId = $null; $script:AdditionalResults = $null }
    $script:now = [datetime]'2026-10-14T12:00:00Z'
    $script:params = @{
        ControlName = 'GUARDRAIL 2'; ItemName = 'User reviews'; itsgcode = 'AC-2'; ReportTime = '2026-10-14'
        msgTable = @{
            isCompliant = 'Compliant.'; isNotCompliant = 'Non-compliant.'
            noAutomatedAccessReviewForUsers = 'No user reviews configured.'
            noInProgressAccessReview = 'No active user reviews.'
            noScheduledUserAccessReview = 'No user or group scope.'
            compliantRecurrenceReviews = 'Recurring user reviews.'
            nonCompliantRecurrenceReviews = 'No valid recurrence.'
        }
    }
    function New-UserReview {
        param($Scope = '/users', $End = '2026-10-15T12:00:00Z',
            $Range = 'endDate', $Pattern = 'weekly', $Name = 'Review', $PrincipalScopes = $null)
        [pscustomobject]@{
            id = "id-$Name"; displayName = $Name; status = 'InProgress'; createdDateTime = '2026-01-01'
            createdBy = @{ userPrincipalName = 'creator@example.test' }
            descriptionForAdmins = 'Admin description'; descriptionForReviewers = 'Reviewer description'
            settings = @{ recurrence = @{
                range = @{ type = $Range; startDate = '2026-01-01'; endDate = $End }
                pattern = $(if ($null -ne $Pattern) { @{ type = $Pattern } } else { $null })
            } }
            scope = @{ query = $Scope; principalScopes = $PrincipalScopes; resourceScopes = @('/groups/group-1') }
            reviewers = @(@{ query = '/v1.0/users/reviewer-1' })
        }
    }
}

AfterAll {
    Remove-Module $script:module -ErrorAction SilentlyContinue
    if ($script:commonModule) { Remove-Module $script:commonModule -ErrorAction SilentlyContinue }
    foreach ($name in $script:createdStubs) { Remove-Item "Function:\$name" -ErrorAction SilentlyContinue }
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-UserRoleReviews' {
    BeforeEach {
        $script:reviews = @(New-UserReview)
        Mock Invoke-GraphQueryEX -ModuleName Check-UserRoleReviews { @{ Content = @{ value = $script:reviews } } }
        Mock Invoke-GraphQuery -ModuleName Check-UserRoleReviews { @{ Content = @{ value = @() } } }
        Mock Get-AzADUser -ModuleName Check-UserRoleReviews {
            [pscustomobject]@{ Id = 'reviewer-1'; UserPrincipalName = 'reviewer@example.test' }
        }
        Mock Get-Date -ModuleName Check-UserRoleReviews { $script:now }
        Mock Write-Error -ModuleName Check-UserRoleReviews {}
        Mock Write-Host -ModuleName Check-UserRoleReviews {}
        Mock Add-ProfileInformation -ModuleName Check-UserRoleReviews { throw 'Unexpected profile call' }
        Mock Invoke-AzRestMethod -ModuleName GR-Common { throw 'Unexpected real Graph transport' }
    }

    It 'Returns a compliant recurring user review with exact metadata and no additional results' {
        $result = Check-UserRoleReviews @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'Compliant. Recurring user reviews.'
        $result.Errors.Count | Should -Be 0
        $result.AdditionalResults | Should -BeNullOrEmpty
        foreach ($key in @('ControlName', 'ItemName', 'itsgcode', 'ReportTime')) {
            $result.ComplianceResults.$key | Should -Be $script:params[$key]
        }
        Should -Invoke Invoke-GraphQuery -ModuleName Check-UserRoleReviews -Times 0 -Exactly
        Should -Invoke Add-ProfileInformation -ModuleName Check-UserRoleReviews -Times 0 -Exactly
        Should -Invoke Invoke-AzRestMethod -ModuleName GR-Common -Times 0 -Exactly
    }

    It 'Requests the six active statuses and selected fields with eq and ErrorAction Stop' {
        Check-UserRoleReviews @script:params | Out-Null
        Should -Invoke Invoke-GraphQueryEX -ModuleName Check-UserRoleReviews -Times 1 -Exactly -ParameterFilter {
            $urlPath -eq ("/identityGovernance/accessReviews/definitions?`$select=id,displayName,status,createdBy,createdDateTime,settings,scope,reviewers,descriptionForAdmins,descriptionForReviewers" +
                "&`$filter=status eq 'Initializing' or status eq 'Starting' or status eq 'InProgress' or status eq 'Completing' or status eq 'AutoReviewing' or status eq 'AutoReviewed'") -and
            $ErrorAction -eq 'Stop'
        }
    }

    It 'Distinguishes empty active reviews with <history> historical review data' -ForEach @(
        @{ history = 'empty'; expected = 'Non-compliant. No user reviews configured.' }
        @{ history = 'null'; expected = 'Non-compliant. No user reviews configured.' }
        @{ history = 'existing'; expected = 'Non-compliant. No active user reviews.' }
    ) {
        $script:reviews = @()
        Mock Invoke-GraphQuery -ModuleName Check-UserRoleReviews {
            if ($history -eq 'null') { @{ Content = $null } }
            elseif ($history -eq 'existing') { @{ Content = @{ value = @(@{ id = 'old' }) } } }
            else { @{ Content = @{ value = @() } } }
        }
        $result = Check-UserRoleReviews @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be $expected
        $result.Errors.Count | Should -Be 0
        Should -Invoke Invoke-GraphQuery -ModuleName Check-UserRoleReviews -Times 1 -Exactly -ParameterFilter {
            $urlPath -eq "/identityGovernance/accessReviews/definitions?`$select=id&`$top=1"
        }
        Should -Invoke Get-AzADUser -ModuleName Check-UserRoleReviews -Times 0 -Exactly
    }

    # Desired: retain Graph failure diagnostics when an error envelope is returned without throwing.
    It 'Characterizes absent <shape> response data as noncompliant without recorded errors' -ForEach @(
        @{ shape = 'response' }, @{ shape = 'content' }, @{ shape = 'value' }, @{ shape = 'error envelope' }
    ) {
        Mock Invoke-GraphQueryEX -ModuleName Check-UserRoleReviews {
            switch ($shape) {
                'response' { $null }
                'content' { @{ Content = $null } }
                'value' { @{ Content = @{} } }
                'error envelope' { @{ Content = $null; StatusCode = 403; Error = 'Forbidden' } }
            }
        }
        $result = Check-UserRoleReviews @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be ''
        $result.Errors.Count | Should -Be 0
        Should -Invoke Invoke-GraphQuery -ModuleName Check-UserRoleReviews -Times 0 -Exactly
    }

    It 'Accepts a recurring <scope> scope' -ForEach @(
        @{ scope = '/users' }, @{ scope = '/groups/group-1' }, @{ scope = '/USERS' }
    ) {
        $script:reviews = @(New-UserReview -Scope $scope)
        (Check-UserRoleReviews @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Rejects active reviews scoped to <scope>' -ForEach @(
        @{ scope = "/users?`$filter=userType eq 'Guest'" }, @{ scope = '/applications/app-1' }, @{ scope = $null }
    ) {
        $script:reviews = @(New-UserReview -Scope $scope)
        $result = Check-UserRoleReviews @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'Non-compliant. No user or group scope.'
    }

    It 'Reads principalScopes in preference to a conflicting direct query' {
        $script:reviews = @(New-UserReview -Scope "/users?`$filter=userType eq 'Guest'" -PrincipalScopes @(@{ query = '/groups/group-1' }))
        (Check-UserRoleReviews @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Evaluates recurrence <case> at a fixed clock' -ForEach @(
        @{ case = 'one second before now'; end = '2026-10-14T11:59:59Z'; range = 'endDate'; pattern = 'weekly'; expected = $false }
        @{ case = 'exactly now'; end = '2026-10-14T12:00:00Z'; range = 'endDate'; pattern = 'weekly'; expected = $false }
        @{ case = 'one second after now'; end = '2026-10-14T12:00:01Z'; range = 'endDate'; pattern = 'weekly'; expected = $true }
        @{ case = 'noEnd with expired date'; end = '2020-01-01'; range = 'noEnd'; pattern = 'monthly'; expected = $true }
        @{ case = 'oneTime despite future date'; end = '2030-01-01'; range = 'endDate'; pattern = 'oneTime'; expected = $false }
        @{ case = 'missing pattern'; end = '2030-01-01'; range = 'noEnd'; pattern = $null; expected = $false }
    ) {
        $script:reviews = @(New-UserReview -End $end -Range $range -Pattern $pattern)
        $result = Check-UserRoleReviews @script:params
        $result.ComplianceResults.ComplianceStatus | Should -Be $expected
        $result.ComplianceResults.Comments | Should -Be $(if ($expected) { 'Compliant. Recurring user reviews.' } else { 'Non-compliant. No valid recurrence.' })
        $result.Errors.Count | Should -Be 0
    }

    It 'Passes if at least one user or group review has valid recurrence' {
        $script:reviews = @(New-UserReview -Name 'Z-invalid' -Pattern 'oneTime'; New-UserReview -Name 'A-valid' -Scope '/groups/group-1' -Range 'noEnd')
        (Check-UserRoleReviews @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Does not require a matching reviewer UPN to evaluate recurrence' {
        Mock Get-AzADUser -ModuleName Check-UserRoleReviews { @() }
        (Check-UserRoleReviews @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    # Desired: return the error envelope without also emitting the ArrayList.Add index on the success stream.
    It 'Captures <dependency> failure and characterizes the leaked error-list index' -ForEach @(
        @{ dependency = 'Invoke-GraphQueryEX' }, @{ dependency = 'Invoke-GraphQuery' },
        @{ dependency = 'Get-AzADUser' }, @{ dependency = 'Expand-ListColumns' }
    ) {
        if ($dependency -eq 'Invoke-GraphQuery') { $script:reviews = @() }
        Mock $dependency -ModuleName Check-UserRoleReviews { throw 'Dependency unavailable' }
        $output = @(Check-UserRoleReviews @script:params)
        $result = $output[-1]
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.Errors.Count | Should -Be 1
        $result.Errors[0] | Should -BeLike "*Failed to call Microsoft Graph REST API at URL '/identityGovernance/accessReviews/definitions?*Dependency unavailable*"
        Should -Invoke Write-Error -ModuleName Check-UserRoleReviews -Times 1 -Exactly
        $output[0] | Should -Be 0
    }

    It 'Records a malformed end date as an error even for noEnd recurrence' {
        $script:reviews = @(New-UserReview -End 'invalid-date' -Range 'noEnd')
        $result = @(Check-UserRoleReviews @script:params)[-1]
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.Errors.Count | Should -Be 1
        $result.Errors[0] | Should -BeLike '*Parse*'
    }

    # Desired: evaluate each review's own isPassedToday property, so the future recurring review makes this compliant.
    It 'Characterizes the shared last-review date flag rejecting an otherwise future-dated review' {
        $script:reviews = @(New-UserReview -Name 'Z-future' -End '2030-01-01'; New-UserReview -Name 'A-expired' -End '2020-01-01')
        $result = Check-UserRoleReviews @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'Non-compliant. No valid recurrence.'
    }

    # Desired: guest review dates must not affect user/group review compliance; the expired user review should fail.
    It 'Characterizes a future one-time guest review making an expired user review pass' {
        $script:reviews = @(New-UserReview -Name 'Z-expired' -End '2020-01-01'; New-UserReview -Name 'A-guest' -End '2030-01-01' -Pattern 'oneTime' -Scope "/users?`$filter=userType eq 'Guest'")
        (Check-UserRoleReviews @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Forwards profiles and preserves in-place mutation and appended errors' {
        Mock Add-ProfileInformation -ModuleName Check-UserRoleReviews {
            param($Result, $ErrorList)
            $Result | Add-Member Profile 2
            $Result.ComplianceStatus = 'Not Applicable'
            [void]$ErrorList.Add('Profile diagnostic')
            $Result
        }
        $result = Check-UserRoleReviews @script:params -EnableMultiCloudProfiles -CloudUsageProfiles '1,2' -ModuleProfiles '2'
        $result.ComplianceResults.Profile | Should -Be 2
        $result.ComplianceResults.ComplianceStatus | Should -Be 'Not Applicable'
        @($result.Errors) | Should -Contain 'Profile diagnostic'
        Should -Invoke Add-ProfileInformation -ModuleName Check-UserRoleReviews -Times 1 -Exactly -ParameterFilter {
            $CloudUsageProfiles -eq '1,2' -and $ModuleProfiles -eq '2' -and
            [string]::IsNullOrEmpty($SubscriptionId) -and $Result.ItemName -eq 'User reviews'
        }
    }

    It 'Passes default cloud profile 3' {
        Mock Add-ProfileInformation -ModuleName Check-UserRoleReviews { param($Result) $Result }
        Check-UserRoleReviews @script:params -EnableMultiCloudProfiles | Out-Null
        Should -Invoke Add-ProfileInformation -ModuleName Check-UserRoleReviews -Times 1 -Exactly -ParameterFilter { $CloudUsageProfiles -eq '3' }
    }

    It 'Propagates a profile helper error outside the Graph try/catch' {
        Mock Add-ProfileInformation -ModuleName Check-UserRoleReviews { throw 'Profile unavailable' }
        { Check-UserRoleReviews @script:params -EnableMultiCloudProfiles } | Should -Throw '*Profile unavailable*'
    }
}

Describe 'User review list expansion helper' {
    It 'Expands multiple review objects independently while preserving order and null padding' {
        $reviews = @(
            [pscustomobject]@{
                AccessReviewName = 'First'; AccessReviewInstanceId = 'first-id'; AccesReviewRecurrenceType = 'noEnd'
                AccessReviewScopeList = @('/users', '/groups/group-1')
                AccessReviewReviewerList = @('reviewer-1', 'reviewer-2', 'reviewer-3')
                AccessReviewResourceScopeList = @('resource-1')
            }
            [pscustomobject]@{
                AccessReviewName = 'Second'; AccessReviewInstanceId = 'second-id'; AccesReviewRecurrenceType = 'endDate'
                AccessReviewScopeList = @('/users')
                AccessReviewReviewerList = @('reviewer-4')
                AccessReviewResourceScopeList = @()
            }
        )
        $rows = @(Expand-ListColumns -accessReviewList $reviews)
        $rows.Count | Should -Be 4
        $rows.AccessReviewName | Should -Be @('First', 'First', 'First', 'Second')
        $rows[2].AccessReviewScope | Should -BeNullOrEmpty
        $rows[2].AccessReviewReviewer | Should -Be 'reviewer-3'
        $rows[2].AccessReviewResourceScope | Should -Be 'resource-1'
        $rows[3].AccessReviewScope | Should -Be '/users'
        $rows[3].AccessReviewResourceScope | Should -BeNullOrEmpty
        $rows[3].AccessReviewInstanceId | Should -Be 'second-id'
        $rows[3].AccesReviewRecurrenceType | Should -Be 'endDate'
    }

    It 'Accepts scalar columns without splitting strings into characters' {
        $rows = @(Expand-ListColumns -accessReviewList @([pscustomobject]@{
            AccessReviewScopeList = '/users'; AccessReviewReviewerList = '/v1.0/users/reviewer-1'
            AccessReviewResourceScopeList = '/groups/resource-1'
        }))
        $rows.Count | Should -Be 1
        $rows[0].AccessReviewScope | Should -Be '/users'
        $rows[0].AccessReviewReviewer | Should -Be '/v1.0/users/reviewer-1'
        $rows[0].AccessReviewResourceScope | Should -Be '/groups/resource-1'
    }
}
