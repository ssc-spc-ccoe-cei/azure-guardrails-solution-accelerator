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
    $script:module = Import-Module (Join-Path $PSScriptRoot '../../../src/GUARDRAIL 2 MANAGE ACCESS/Audit/Check-GuestRoleReviews.psm1') -Force -PassThru
    & $script:module { $script:subscriptionId = $null; $script:AdditionalResults = $null }
    $script:now = [datetime]'2026-10-14T12:00:00Z'
    $script:params = @{
        ControlName = 'GUARDRAIL 2'; ItemName = 'Guest reviews'; itsgcode = 'AC-2'; ReportTime = '2026-10-14'
        msgTable = @{
            isCompliant = 'Compliant.'; isNotCompliant = 'Non-compliant.'
            noAutomatedAccessReviewForGuests = 'No guest reviews configured.'
            noInProgressGuestAccessReview = 'No active guest reviews.'
            noScheduledGuestAccessReview = 'No guest scope.'
            compliantRecurrenceGuestReviews = 'Recurring guest reviews.'
            nonCompliantRecurrenceReviews = 'No valid recurrence.'
        }
    }
    function New-GuestReview {
        param($Scope = "/users?`$filter=userType eq 'Guest'", $End = '2026-10-15T12:00:00Z',
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

Describe 'Check-GuestRoleReviews' {
    BeforeEach {
        $script:reviews = @(New-GuestReview)
        Mock Invoke-GraphQueryEX -ModuleName Check-GuestRoleReviews { @{ Content = @{ value = $script:reviews } } }
        Mock Invoke-GraphQuery -ModuleName Check-GuestRoleReviews { @{ Content = @{ value = @() } } }
        Mock Get-AzADUser -ModuleName Check-GuestRoleReviews {
            [pscustomobject]@{ Id = 'reviewer-1'; UserPrincipalName = 'reviewer@example.test' }
        }
        Mock Get-Date -ModuleName Check-GuestRoleReviews { $script:now }
        Mock Write-Error -ModuleName Check-GuestRoleReviews {}
        Mock Write-Host -ModuleName Check-GuestRoleReviews {}
        Mock Add-ProfileInformation -ModuleName Check-GuestRoleReviews { throw 'Unexpected profile call' }
        Mock Invoke-AzRestMethod -ModuleName GR-Common { throw 'Unexpected real Graph transport' }
    }

    It 'Returns a compliant recurring guest review with exact metadata and no additional results' {
        $result = Check-GuestRoleReviews @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'Compliant. Recurring guest reviews.'
        $result.Errors.Count | Should -Be 0
        $result.AdditionalResults | Should -BeNullOrEmpty
        foreach ($key in @('ControlName', 'ItemName', 'itsgcode', 'ReportTime')) {
            $result.ComplianceResults.$key | Should -Be $script:params[$key]
        }
        Should -Invoke Invoke-GraphQuery -ModuleName Check-GuestRoleReviews -Times 0 -Exactly
        Should -Invoke Add-ProfileInformation -ModuleName Check-GuestRoleReviews -Times 0 -Exactly
        Should -Invoke Invoke-AzRestMethod -ModuleName GR-Common -Times 0 -Exactly
    }

    It 'Requests exactly the selected fields and six active statuses with eq rather than ne' {
        Check-GuestRoleReviews @script:params | Out-Null
        Should -Invoke Invoke-GraphQueryEX -ModuleName Check-GuestRoleReviews -Times 1 -Exactly -ParameterFilter {
            $urlPath -eq ("/identityGovernance/accessReviews/definitions?`$select=id,displayName,status,createdBy,createdDateTime,settings,scope,reviewers,descriptionForAdmins,descriptionForReviewers" +
                "&`$filter=status eq 'Initializing' or status eq 'Starting' or status eq 'InProgress' or status eq 'Completing' or status eq 'AutoReviewing' or status eq 'AutoReviewed'") -and
            $ErrorAction -eq 'Stop'
        }
    }

    It 'Distinguishes empty active reviews with <history> historical review data' -ForEach @(
        @{ history = 'empty'; expected = 'Non-compliant. No guest reviews configured.' }
        @{ history = 'null'; expected = 'Non-compliant. No guest reviews configured.' }
        @{ history = 'existing'; expected = 'Non-compliant. No active guest reviews.' }
    ) {
        $script:reviews = @()
        Mock Invoke-GraphQuery -ModuleName Check-GuestRoleReviews {
            if ($history -eq 'null') { @{ Content = $null } }
            elseif ($history -eq 'existing') { @{ Content = @{ value = @(@{ id = 'old' }) } } }
            else { @{ Content = @{ value = @() } } }
        }
        $result = Check-GuestRoleReviews @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be $expected
        $result.Errors.Count | Should -Be 0
        Should -Invoke Invoke-GraphQuery -ModuleName Check-GuestRoleReviews -Times 1 -Exactly -ParameterFilter {
            $urlPath -eq "/identityGovernance/accessReviews/definitions?`$select=id&`$top=1"
        }
        Should -Invoke Get-AzADUser -ModuleName Check-GuestRoleReviews -Times 0 -Exactly
    }

    # Desired: retain Graph failure diagnostics when an error envelope is returned without throwing.
    It 'Characterizes absent <shape> response data as noncompliant without recorded errors' -ForEach @(
        @{ shape = 'response' }, @{ shape = 'content' }, @{ shape = 'value' }, @{ shape = 'error envelope' }
    ) {
        Mock Invoke-GraphQueryEX -ModuleName Check-GuestRoleReviews {
            switch ($shape) {
                'response' { $null }
                'content' { @{ Content = $null } }
                'value' { @{ Content = @{} } }
                'error envelope' { @{ Content = $null; StatusCode = 403; Error = 'Forbidden' } }
            }
        }
        $result = Check-GuestRoleReviews @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be ''
        $result.Errors.Count | Should -Be 0
        Should -Invoke Invoke-GraphQuery -ModuleName Check-GuestRoleReviews -Times 0 -Exactly
    }

    It 'Rejects active reviews scoped to <scope>' -ForEach @(
        @{ scope = '/users' }, @{ scope = '/groups/group-1' }, @{ scope = '/applications/app-1' }, @{ scope = $null }
    ) {
        $script:reviews = @(New-GuestReview -Scope $scope)
        $result = Check-GuestRoleReviews @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'Non-compliant. No guest scope.'
    }

    It 'Reads principalScopes in preference to a conflicting direct query' {
        $script:reviews = @(New-GuestReview -Scope '/users' -PrincipalScopes @(@{ query = "/users?`$filter=userType eq 'GUEST'" }))
        (Check-GuestRoleReviews @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Evaluates recurrence <case> at a fixed clock' -ForEach @(
        @{ case = 'one second before now'; end = '2026-10-14T11:59:59Z'; range = 'endDate'; pattern = 'weekly'; expected = $false }
        @{ case = 'exactly now'; end = '2026-10-14T12:00:00Z'; range = 'endDate'; pattern = 'weekly'; expected = $false }
        @{ case = 'one second after now'; end = '2026-10-14T12:00:01Z'; range = 'endDate'; pattern = 'weekly'; expected = $true }
        @{ case = 'noEnd with expired date'; end = '2020-01-01'; range = 'noEnd'; pattern = 'monthly'; expected = $true }
        @{ case = 'oneTime despite future date'; end = '2030-01-01'; range = 'endDate'; pattern = 'oneTime'; expected = $false }
        @{ case = 'missing pattern'; end = '2030-01-01'; range = 'noEnd'; pattern = $null; expected = $false }
    ) {
        $script:reviews = @(New-GuestReview -End $end -Range $range -Pattern $pattern)
        $result = Check-GuestRoleReviews @script:params
        $result.ComplianceResults.ComplianceStatus | Should -Be $expected
        $result.ComplianceResults.Comments | Should -Be $(if ($expected) { 'Compliant. Recurring guest reviews.' } else { 'Non-compliant. No valid recurrence.' })
        $result.Errors.Count | Should -Be 0
    }

    It 'Passes if at least one guest review has a valid recurrence' {
        $script:reviews = @(New-GuestReview -Name 'Z-invalid' -Pattern 'oneTime'; New-GuestReview -Name 'A-valid' -Range 'noEnd')
        (Check-GuestRoleReviews @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Does not require a matching reviewer UPN to evaluate recurrence' {
        Mock Get-AzADUser -ModuleName Check-GuestRoleReviews { @() }
        (Check-GuestRoleReviews @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    # Desired: return the error envelope without also emitting the ArrayList.Add index on the success stream.
    It 'Captures <dependency> failure and characterizes the leaked error-list index' -ForEach @(
        @{ dependency = 'Invoke-GraphQueryEX' }, @{ dependency = 'Invoke-GraphQuery' },
        @{ dependency = 'Get-AzADUser' }, @{ dependency = 'Expand-ListColumns' }
    ) {
        if ($dependency -eq 'Invoke-GraphQuery') { $script:reviews = @() }
        Mock $dependency -ModuleName Check-GuestRoleReviews { throw 'Dependency unavailable' }
        $output = @(Check-GuestRoleReviews @script:params)
        $result = $output[-1]
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.Errors.Count | Should -Be 1
        $result.Errors[0] | Should -BeLike "*Failed to call Microsoft Graph REST API at URL '/identityGovernance/accessReviews/definitions?*Dependency unavailable*"
        Should -Invoke Write-Error -ModuleName Check-GuestRoleReviews -Times 1 -Exactly
        $output[0] | Should -Be 0
    }

    It 'Records a malformed end date as an error even for noEnd recurrence' {
        $script:reviews = @(New-GuestReview -End 'invalid-date' -Range 'noEnd')
        $result = @(Check-GuestRoleReviews @script:params)[-1]
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.Errors.Count | Should -Be 1
        $result.Errors[0] | Should -BeLike '*Parse*'
    }

    # Desired: evaluate each review's own isPassedToday property, so the future recurring review makes this compliant.
    It 'Characterizes the shared last-review date flag rejecting an otherwise future-dated review' {
        $script:reviews = @(New-GuestReview -Name 'Z-future' -End '2030-01-01'; New-GuestReview -Name 'A-expired' -End '2020-01-01')
        $result = Check-GuestRoleReviews @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'Non-compliant. No valid recurrence.'
    }

    # Desired: neither an expired recurring review nor a future one-time review should satisfy recurring-review compliance.
    It 'Characterizes a future one-time review making an expired recurring review pass' {
        $script:reviews = @(New-GuestReview -Name 'Z-expired' -End '2020-01-01'; New-GuestReview -Name 'A-future' -End '2030-01-01' -Pattern 'oneTime')
        (Check-GuestRoleReviews @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Forwards profiles and preserves in-place mutation and appended errors' {
        Mock Add-ProfileInformation -ModuleName Check-GuestRoleReviews {
            param($Result, $ErrorList)
            $Result | Add-Member Profile 2
            $Result.ComplianceStatus = 'Not Applicable'
            [void]$ErrorList.Add('Profile diagnostic')
            $Result
        }
        $result = Check-GuestRoleReviews @script:params -EnableMultiCloudProfiles -CloudUsageProfiles '1,2' -ModuleProfiles '2'
        $result.ComplianceResults.Profile | Should -Be 2
        $result.ComplianceResults.ComplianceStatus | Should -Be 'Not Applicable'
        @($result.Errors) | Should -Contain 'Profile diagnostic'
        Should -Invoke Add-ProfileInformation -ModuleName Check-GuestRoleReviews -Times 1 -Exactly -ParameterFilter {
            $CloudUsageProfiles -eq '1,2' -and $ModuleProfiles -eq '2' -and
            [string]::IsNullOrEmpty($SubscriptionId) -and $Result.ItemName -eq 'Guest reviews'
        }
    }

    It 'Passes default cloud profile 3' {
        Mock Add-ProfileInformation -ModuleName Check-GuestRoleReviews { param($Result) $Result }
        Check-GuestRoleReviews @script:params -EnableMultiCloudProfiles | Out-Null
        Should -Invoke Add-ProfileInformation -ModuleName Check-GuestRoleReviews -Times 1 -Exactly -ParameterFilter { $CloudUsageProfiles -eq '3' }
    }

    It 'Propagates a profile helper error outside the Graph try/catch' {
        Mock Add-ProfileInformation -ModuleName Check-GuestRoleReviews { throw 'Profile unavailable' }
        { Check-GuestRoleReviews @script:params -EnableMultiCloudProfiles } | Should -Throw '*Profile unavailable*'
    }
}

Describe 'Guest review list expansion helper' {
    It 'Repeats singleton columns, pads shorter columns and preserves metadata' {
        $inputReview = [pscustomobject]@{
            AccessReviewName = 'Guest review'; AccessReviewInstanceId = 'review-1'; AccessReviewCreatedBy = 'creator@example.test'
            AccessReviewStartDate = '2026-01-01'; AccessReviewEndDate = '2030-01-01'; AccessReviewStatus = 'InProgress'
            AccesReviewRecurrenceType = 'noEnd'; AccesReviewRecurrencePattern = 'weekly'
            AccessReviewScopeList = @('guest-1', 'guest-2', 'guest-3')
            AccessReviewReviewerList = @('reviewer-1')
            AccessReviewResourceScopeList = @('resource-1', 'resource-2')
        }
        $rows = @(Expand-ListColumns -accessReviewList @($inputReview))
        $rows.Count | Should -Be 3
        $rows.AccessReviewScope | Should -Be @('guest-1', 'guest-2', 'guest-3')
        $rows.AccessReviewReviewer | Should -Be @('reviewer-1', 'reviewer-1', 'reviewer-1')
        $rows[2].AccessReviewResourceScope | Should -BeNullOrEmpty
        $rows[1].AccessReviewResourceScope | Should -Be 'resource-2'
        $rows[2].AccessReviewCreatedBy | Should -Be 'creator@example.test'
        $rows[2].AccesReviewRecurrencePattern | Should -Be 'weekly'
    }

    It 'Produces no rows for a review whose expandable columns are all absent' {
        $rows = @(Expand-ListColumns -accessReviewList @([pscustomobject]@{ AccessReviewName = 'Empty review' }))
        $rows.Count | Should -Be 0
    }
}
