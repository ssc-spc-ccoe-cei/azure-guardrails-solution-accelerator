BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Invoke-GraphQueryEX { }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) return $Result }

    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 2 MANAGE ACCESS\Audit\Check-UserRiskBasedCAP.psm1'
    Import-Module $modulePath -Force

    $script:msgTable = @{
        isCompliant    = 'Compliant.'
        isNotCompliant = 'Non-compliant.'
        compliantC1    = 'A valid user risk based conditional access policy exists.'
        nonCompliantC1 = 'No valid user risk based conditional access policy exists.'
    }
}

AfterAll {
    Remove-Item Function:\Invoke-GraphQueryEX -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

function script:New-ValidUserRiskPolicy {
    param(
        [string[]]$ExcludeGroups = @()
    )

    return [PSCustomObject]@{
        id = 'policy-1'
        state = 'enabled'
        conditions = [PSCustomObject]@{
            users = [PSCustomObject]@{
                includeUsers                 = @('All')
                excludeUsers                 = @('bg1-id', 'bg2-id')
                includeGroups                = @()
                excludeGroups                = $ExcludeGroups
                includeRoles                 = @()
                excludeRoles                 = @()
                includeGuestsOrExternalUsers = $null
                excludeGuestsOrExternalUsers = $null
            }
            applications = [PSCustomObject]@{
                includeApplications = @('All')
                excludeApplications = @()
            }
            clientAppTypes     = @('all')
            userRiskLevels     = @('high')
            signInRiskLevels   = @()
            platforms          = $null
            locations          = $null
            devices            = $null
            clientApplications = $null
        }
        grantControls = [PSCustomObject]@{
            builtInControls = @('mfa', 'passwordChange')
        }
        sessionControls = [PSCustomObject]@{
            signInFrequency = [PSCustomObject]@{
                frequencyInterval = @('everyTime')
                authenticationType = @('primaryAndSecondaryAuthentication')
                isEnabled = $true
            }
        }
    }
}

Describe 'Test-IsNullOrEmptyArray' {
    It 'Returns true for null' {
        Test-IsNullOrEmptyArray -Value $null | Should -BeTrue
    }

    It 'Returns true for an empty array' {
        Test-IsNullOrEmptyArray -Value @() | Should -BeTrue
    }

    It 'Returns true for an empty string' {
        Test-IsNullOrEmptyArray -Value '' | Should -BeTrue
    }

    It 'Returns false for a non-empty array' {
        Test-IsNullOrEmptyArray -Value @('value') | Should -BeFalse
    }

    It 'Returns false for a non-empty string' {
        Test-IsNullOrEmptyArray -Value 'value' | Should -BeFalse
    }
}

Describe 'Test-CommonFilters' {
    BeforeAll {
        $script:firstBgId = 'bg1-id'
        $script:secondBgId = 'bg2-id'
    }

    It 'Returns the policy when all required filters match' {
        $policy = New-ValidUserRiskPolicy
        $result = @(Test-CommonFilters -policy $policy -FirstBreakGlassID $firstBgId -SecondBreakGlassID $secondBgId)

        $result.Count | Should -Be 1
        $result[0].id | Should -Be 'policy-1'
    }

    It 'Filters out a policy missing MFA' {
        $policy = New-ValidUserRiskPolicy
        $policy.grantControls.builtInControls = @('passwordChange')

        @(Test-CommonFilters -policy $policy -FirstBreakGlassID $firstBgId -SecondBreakGlassID $secondBgId) | Should -BeNullOrEmpty
    }

    It 'Filters out a disabled policy' {
        $policy = New-ValidUserRiskPolicy
        $policy.state = 'disabled'

        @(Test-CommonFilters -policy $policy -FirstBreakGlassID $firstBgId -SecondBreakGlassID $secondBgId) | Should -BeNullOrEmpty
    }

    It 'Filters out a policy that does not include all users' {
        $policy = New-ValidUserRiskPolicy
        $policy.conditions.users.includeUsers = @('user-1')

        @(Test-CommonFilters -policy $policy -FirstBreakGlassID $firstBgId -SecondBreakGlassID $secondBgId) | Should -BeNullOrEmpty
    }

    It 'Filters out a policy with sign-in frequency disabled' {
        $policy = New-ValidUserRiskPolicy
        $policy.sessionControls.signInFrequency.isEnabled = $false

        @(Test-CommonFilters -policy $policy -FirstBreakGlassID $firstBgId -SecondBreakGlassID $secondBgId) | Should -BeNullOrEmpty
    }

    It 'Filters out a policy that includes groups' {
        $policy = New-ValidUserRiskPolicy
        $policy.conditions.users.includeGroups = @('group-1')

        @(Test-CommonFilters -policy $policy -FirstBreakGlassID $firstBgId -SecondBreakGlassID $secondBgId) | Should -BeNullOrEmpty
    }
}

Describe 'Get-UserRiskBasedCAP' {
    BeforeAll {
        $script:commonParams = @{
            ControlName         = 'GUARDRAIL 2'
            ItemName            = 'Manage Access - User Risk CAP'
            itsgcode            = 'AC-2'
            msgTable            = $script:msgTable
            ReportTime          = '2026-09-03'
            FirstBreakGlassUPN  = 'bg1@tenant.onmicrosoft.com'
            SecondBreakGlassUPN = 'bg2@tenant.onmicrosoft.com'
        }
    }

    Context 'When a valid policy exists and excludes the shared break-glass group' {
        BeforeAll {
            $script:validPolicy = New-ValidUserRiskPolicy -ExcludeGroups @('shared-group')

            Mock Invoke-GraphQueryEX -ModuleName Check-UserRiskBasedCAP {
                param($urlPath)

                switch ($urlPath) {
                    '/identity/conditionalAccess/policies' {
                        return [PSCustomObject]@{
                            Content = [PSCustomObject]@{
                                value = @($script:validPolicy)
                            }
                        }
                    }
                    '/users/bg1%40tenant.onmicrosoft.com' {
                        return [PSCustomObject]@{
                            Content = [PSCustomObject]@{ id = 'bg1-id' }
                        }
                    }
                    '/users/bg2%40tenant.onmicrosoft.com' {
                        return [PSCustomObject]@{
                            Content = [PSCustomObject]@{ id = 'bg2-id' }
                        }
                    }
                    '/users/bg1-id/memberOf' {
                        return [PSCustomObject]@{
                            Content = [PSCustomObject]@{
                                value = @(
                                    [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.group'; id = 'shared-group' },
                                    [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.group'; id = 'bg1-only-group' }
                                )
                            }
                        }
                    }
                    '/users/bg2-id/memberOf' {
                        return [PSCustomObject]@{
                            Content = [PSCustomObject]@{
                                value = @(
                                    [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.group'; id = 'shared-group' },
                                    [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.group'; id = 'bg2-only-group' }
                                )
                            }
                        }
                    }
                    default {
                        throw "Unexpected urlPath: $urlPath"
                    }
                }
            }
        }

        It 'Returns compliant' {
            $result = Get-UserRiskBasedCAP @commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -Be ($script:msgTable.isCompliant + ' ' + $script:msgTable.compliantC1)
        }
    }

    Context 'When no valid policy exists' {
        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-UserRiskBasedCAP {
                param($urlPath)

                switch ($urlPath) {
                    '/identity/conditionalAccess/policies' {
                        return [PSCustomObject]@{
                            Content = [PSCustomObject]@{
                                value = @()
                            }
                        }
                    }
                    '/users/bg1%40tenant.onmicrosoft.com' {
                        return [PSCustomObject]@{
                            Content = [PSCustomObject]@{ id = 'bg1-id' }
                        }
                    }
                    '/users/bg2%40tenant.onmicrosoft.com' {
                        return [PSCustomObject]@{
                            Content = [PSCustomObject]@{ id = 'bg2-id' }
                        }
                    }
                    '/users/bg1-id/memberOf' {
                        return [PSCustomObject]@{
                            Content = [PSCustomObject]@{
                                value = @([PSCustomObject]@{ '@odata.type' = '#microsoft.graph.group'; id = 'shared-group' })
                            }
                        }
                    }
                    '/users/bg2-id/memberOf' {
                        return [PSCustomObject]@{
                            Content = [PSCustomObject]@{
                                value = @([PSCustomObject]@{ '@odata.type' = '#microsoft.graph.group'; id = 'shared-group' })
                            }
                        }
                    }
                    default {
                        throw "Unexpected urlPath: $urlPath"
                    }
                }
            }
        }

        It 'Returns non-compliant' {
            $result = Get-UserRiskBasedCAP @commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -Be ($script:msgTable.isNotCompliant + ' ' + $script:msgTable.nonCompliantC1)
        }
    }
}
