BeforeAll {
    # Ensure Write-Error in source modules stays non-terminating (CI and VS Code set $ErrorActionPreference = 'Stop')
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    # Define stubs for external functions not available outside the solution
    # (these live in src/Guardrails-Common/GR-Common.psm1, a sibling module)
    function global:Invoke-GraphQueryEX { }
    function global:Invoke-GraphQuery { }
    function global:Expand-ListColumns {
        # Simplified stand-in for the real GR-Common implementation: since our test
        # fixtures always use a single-element scope/reviewer list, just project the
        # singular "AccessReviewScope"/"AccessReviewReviewer" properties the caller expects.
        param($accessReviewList)
        $accessReviewList | ForEach-Object {
            $_ | Add-Member -MemberType NoteProperty -Name 'AccessReviewScope' -Value $_.AccessReviewScopeList -Force -PassThru |
                Add-Member -MemberType NoteProperty -Name 'AccessReviewReviewer' -Value $_.AccessReviewReviewerList -Force -PassThru
        }
    }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) return $Result }

    function global:New-AccessReviewDefinition {
        param(
            [string] $DisplayName = 'Guest Access Review',
            [string] $Status = 'InProgress',
            [string] $ScopeQuery = "/v1.0/users?`$filter=userType eq 'Guest'",
            [string] $RecurrenceType = 'noEnd',
            [string] $RecurrencePattern = 'weekly',
            [datetime] $EndDate = (Get-Date).AddDays(30)
        )
        [PSCustomObject]@{
            id                    = [guid]::NewGuid().ToString()
            displayName           = $DisplayName
            status                = $Status
            createdBy             = [PSCustomObject]@{ userPrincipalName = 'admin@tenant.onmicrosoft.com' }
            createdDateTime       = (Get-Date).AddDays(-10).ToString('o')
            descriptionForAdmins  = 'Admin description'
            descriptionForReviewers = 'Reviewer description'
            settings              = [PSCustomObject]@{
                recurrence = [PSCustomObject]@{
                    range   = [PSCustomObject]@{ type = $RecurrenceType; startDate = (Get-Date).AddDays(-30).ToString('o'); endDate = $EndDate.ToString('o') }
                    pattern = [PSCustomObject]@{ type = $RecurrencePattern }
                }
            }
            scope                 = [PSCustomObject]@{
                principalScopes = @([PSCustomObject]@{ query = $ScopeQuery })
                resourceScopes  = @()
            }
            reviewers             = @([PSCustomObject]@{ query = '/v1.0/users/00000000-0000-0000-0000-000000000001' })
        }
    }

    # Import the module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 2 MANAGE ACCESS\Audit\Check-GuestRoleReviews.psm1'
    Import-Module $modulePath -Force

    # Common message table stub used across tests
    $script:msgTable = @{
        isCompliant                       = 'Compliant:'
        isNotCompliant                    = 'Non-compliant:'
        noAutomatedAccessReviewForGuests   = 'No automated access review configured for guests.'
        noInProgressGuestAccessReview      = 'No in-progress guest access review found.'
        noScheduledGuestAccessReview       = 'No scheduled guest access review found.'
        compliantRecurrenceGuestReviews    = 'A recurring guest access review is configured.'
        nonCompliantRecurrenceReviews      = 'No recurring guest access review is configured.'
    }
}

AfterAll {
    # Clean up global stubs
    Remove-Item Function:\Invoke-GraphQueryEX -ErrorAction SilentlyContinue
    Remove-Item Function:\Invoke-GraphQuery -ErrorAction SilentlyContinue
    Remove-Item Function:\Expand-ListColumns -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    Remove-Item Function:\New-AccessReviewDefinition -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-GuestRoleReviews' {

    BeforeAll {
        $script:commonParams = @{
            ControlName = 'GUARDRAIL 2'
            ItemName    = 'Guest Role Reviews'
            itsgcode    = 'AC-2'
            msgTable    = $script:msgTable
            ReportTime  = (Get-Date -Format 'yyyy-MM-dd')
        }
    }

    Context 'When at least one active guest-scoped access review exists with a recurring (non one-time) schedule' {

        BeforeAll {
            $review = New-AccessReviewDefinition
            Mock Invoke-GraphQueryEX -ModuleName Check-GuestRoleReviews {
                [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @($review) } }
            }
            Mock Get-AzADUser -ModuleName Check-GuestRoleReviews { @() }
        }

        It 'Returns compliant' {
            $result = Check-GuestRoleReviews @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -BeLike "*$($script:msgTable.compliantRecurrenceGuestReviews)*"
        }
    }

    Context 'When active access reviews exist but none are scoped to guests' {

        BeforeAll {
            $review = New-AccessReviewDefinition -ScopeQuery "/v1.0/users?$filter=userType eq 'Member'"
            Mock Invoke-GraphQueryEX -ModuleName Check-GuestRoleReviews {
                [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @($review) } }
            }
            Mock Get-AzADUser -ModuleName Check-GuestRoleReviews { @() }
        }

        It 'Returns non-compliant and mentions no scheduled guest access review' {
            $result = Check-GuestRoleReviews @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -BeLike "*$($script:msgTable.noScheduledGuestAccessReview)*"
        }
    }

    Context 'When a guest-scoped review exists but its recurrence pattern is one-time (non-recurring)' {

        BeforeAll {
            $review = New-AccessReviewDefinition -RecurrencePattern 'oneTime' -EndDate (Get-Date).AddDays(-5)
            Mock Invoke-GraphQueryEX -ModuleName Check-GuestRoleReviews {
                [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @($review) } }
            }
            Mock Get-AzADUser -ModuleName Check-GuestRoleReviews { @() }
        }

        It 'Returns non-compliant' {
            $result = Check-GuestRoleReviews @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -BeLike "*$($script:msgTable.nonCompliantRecurrenceReviews)*"
        }
    }

    Context 'When no active access reviews exist and none have ever been created' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-GuestRoleReviews {
                [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @() } }
            }
            Mock Invoke-GraphQuery -ModuleName Check-GuestRoleReviews {
                [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @() } }
            }
        }

        It 'Returns non-compliant and mentions no automated access review' {
            $result = Check-GuestRoleReviews @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -BeLike "*$($script:msgTable.noAutomatedAccessReviewForGuests)*"
        }
    }

    Context 'When no active access reviews exist but some have been created previously' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-GuestRoleReviews {
                [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @() } }
            }
            Mock Invoke-GraphQuery -ModuleName Check-GuestRoleReviews {
                [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'abc' }) } }
            }
        }

        It 'Returns non-compliant and mentions no in-progress review' {
            $result = Check-GuestRoleReviews @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -BeLike "*$($script:msgTable.noInProgressGuestAccessReview)*"
        }
    }

    Context 'When Invoke-GraphQueryEX throws an error' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-GuestRoleReviews { throw 'Graph API unavailable' }
        }

        It 'Does not throw and records the error, returning non-compliant' {
            { $script:result = Check-GuestRoleReviews @commonParams } | Should -Not -Throw
            $script:result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $script:result.Errors.Count | Should -BeGreaterThan 0
        }
    }
}
