BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Search-AzGraph { }
    function global:Get-AzSubscription { }
    function global:Check-PolicyStatus { }

    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 5 DATA LOCATION\Audit\Check-AllowedLocationPolicy.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Item Function:\Search-AzGraph -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-AzSubscription -ErrorAction SilentlyContinue
    Remove-Item Function:\Check-PolicyStatus -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Get-PolicyComplianceDataOptimized' {
    Context 'When Azure Resource Graph returns compliance data' {
        BeforeAll {
            Mock Search-AzGraph -ModuleName Check-AllowedLocationPolicy {
                @(
                    [pscustomobject]@{
                        subscriptionId              = 'sub-001'
                        InitiativeTotalCount        = 4
                        InitiativeCompliantCount    = 3
                        InitiativeNonCompliantCount = 1
                        PolicyTotalCount            = 2
                        PolicyCompliantCount        = 2
                        PolicyNonCompliantCount     = 0
                        SkipToken                   = $null
                    }
                )
            }
        }

        It 'Builds a cache keyed by subscription id' {
            $cache = Get-PolicyComplianceDataOptimized -PolicyID 'policy-001' -InitiativeID 'initiative-001'

            $cache.ContainsKey('sub-001') | Should -BeTrue
            $cache['sub-001'].InitiativeNonCompliantCount | Should -Be 1
            $cache['sub-001'].PolicyCompliantCount | Should -Be 2
        }
    }

    Context 'When Azure Resource Graph throws' {
        BeforeAll {
            Mock Search-AzGraph -ModuleName Check-AllowedLocationPolicy { throw 'ARG unavailable' }
        }

        It 'Returns an empty cache' {
            $cache = Get-PolicyComplianceDataOptimized -PolicyID 'policy-001' -InitiativeID 'initiative-001'

            $cache.Count | Should -Be 0
        }
    }
}

Describe 'Verify-AllowedLocationPolicy' {
    BeforeAll {
        $script:msgTable = @{
            policyNotAssigned        = '{0} is missing the policy assignment.'
            notAllowedLocation       = 'A disallowed location was assigned.'
            isCompliant              = 'Compliant.'
            isNotCompliant           = 'Non-compliant.'
            allCompliantResources    = 'All resources are compliant.'
            allNonCompliantResources = 'All resources are non-compliant.'
            hasNonComplianceResource = '{0} of {1} resources are non-compliant.'
            noResource               = 'No resources were evaluated.'
        }
        $script:commonParams = @{
            ControlName            = 'GUARDRAIL 5'
            ItemName               = 'Allowed Location Policy'
            PolicyID               = 'policy-001'
            InitiativeID           = 'initiative-001'
            LogType                = 'AzureDiagnostics'
            itsgcode               = 'AC-5'
            AllowedLocationsString = 'canadacentral,canadaeast'
            msgTable               = $script:msgTable
            ReportTime             = '2026-09-25'
        }
    }

    Context 'When subscriptions are returned and policy status succeeds' {
        BeforeAll {
            Mock Get-AzSubscription -ModuleName Check-AllowedLocationPolicy {
                @(
                    [pscustomobject]@{ Id = 'sub-001'; Name = 'Subscription One'; State = 'Enabled' },
                    [pscustomobject]@{ Id = 'sub-002'; Name = 'Subscription Two'; State = 'Disabled' }
                )
            }
            Mock Get-PolicyComplianceDataOptimized -ModuleName Check-AllowedLocationPolicy {
                @{
                    'sub-001' = @{
                        InitiativeTotalCount        = 1
                        InitiativeCompliantCount    = 1
                        InitiativeNonCompliantCount = 0
                        PolicyTotalCount            = 1
                        PolicyCompliantCount        = 1
                        PolicyNonCompliantCount     = 0
                    }
                }
            }
            Mock Check-PolicyStatus -ModuleName Check-AllowedLocationPolicy {
                @(
                    [pscustomobject]@{
                        Type             = 'subscription'
                        Id               = 'sub-001'
                        SubscriptionName = 'Subscription One'
                        ComplianceStatus = $true
                        Comments         = 'Compliant. All resources are compliant.'
                        ItemName         = 'Allowed Location Policy'
                        itsgcode         = 'AC-5'
                        ControlName      = 'GUARDRAIL 5'
                        ReportTime       = '2026-09-25'
                    },
                    [pscustomobject]@{
                        Type             = 'subscription'
                        Id               = 'sub-002'
                        SubscriptionName = 'Subscription Two'
                        ComplianceStatus = $false
                        Comments         = 'Not evaluated.'
                        ItemName         = 'Allowed Location Policy'
                        itsgcode         = 'AC-5'
                        ControlName      = 'GUARDRAIL 5'
                        ReportTime       = '2026-09-25'
                    }
                )
            }
        }

        It 'Returns the compliance results emitted by Check-PolicyStatus' {
            $result = Verify-AllowedLocationPolicy @script:commonParams

            $result.ComplianceResults.Count | Should -Be 2
            $result.ComplianceResults[0].ComplianceStatus | Should -BeTrue
            $result.Errors.Count | Should -Be 0
        }
    }

    Context 'When retrieving subscriptions fails' {
        BeforeAll {
            Mock Get-AzSubscription -ModuleName Check-AllowedLocationPolicy { throw 'Subscription lookup failed' }
        }

        It 'Throws a descriptive error' {
            { Verify-AllowedLocationPolicy @script:commonParams } | Should -Throw '*Get-AzSubscription*'
        }
    }
}
