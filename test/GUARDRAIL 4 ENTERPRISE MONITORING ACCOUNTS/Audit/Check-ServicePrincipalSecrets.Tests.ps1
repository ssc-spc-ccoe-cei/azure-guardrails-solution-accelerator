BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Get-AzADServicePrincipal { }
    function global:Get-AzADAppCredential { }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) return $Result }

    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 4 ENTERPRISE MONITORING ACCOUNTS\Audit\Check-ServicePrincipalSecrets.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Item Function:\Get-AzADServicePrincipal -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-AzADAppCredential -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Get-DepartmentServicePrincipalNameSecrets' {
    BeforeAll {
        $script:msgTable = @{
            NoSPN                       = 'Service principal was not found.'
            SPNNoValidCredentials       = 'No valid credentials exist. {0}'
            SPNSingleValidCredential    = 'One valid credential exists. {0}'
            SPNMultipleValidCredentials = 'Multiple valid credentials exist. {0}'
        }
        $script:commonParams = @{
            SPNID       = '11111111-1111-1111-1111-111111111111'
            ControlName = 'GUARDRAIL 4'
            ItemName    = 'Service Principal Secrets'
            itsgcode    = 'AC-4'
            msgTable    = $script:msgTable
            ReportTime  = '2026-09-25'
        }
    }

    Context 'When the service principal does not exist' {
        BeforeAll {
            Mock Get-AzADServicePrincipal -ModuleName Check-ServicePrincipalSecrets { $null }
        }

        It 'Returns non-compliant with the missing SPN message' {
            $result = Get-DepartmentServicePrincipalNameSecrets @script:commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -Be $script:msgTable.NoSPN
        }
    }

    Context 'When a single valid credential exists' {
        BeforeAll {
            Mock Get-AzADServicePrincipal -ModuleName Check-ServicePrincipalSecrets {
                [pscustomobject]@{
                    Id    = 'spn-001'
                    AppId = 'app-001'
                }
            }
            Mock Get-AzADAppCredential -ModuleName Check-ServicePrincipalSecrets {
                @(
                    [pscustomobject]@{
                        DisplayName = 'active-secret'
                        EndDateTime = (Get-Date).AddDays(10)
                    }
                )
            }
        }

        It 'Returns compliant with the active credential message' {
            $result = Get-DepartmentServicePrincipalNameSecrets @script:commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -BeLike 'One valid credential exists.*active-secret*'
        }
    }

    Context 'When multiple valid credentials exist' {
        BeforeAll {
            Mock Get-AzADServicePrincipal -ModuleName Check-ServicePrincipalSecrets {
                [pscustomobject]@{
                    Id    = 'spn-001'
                    AppId = 'app-001'
                }
            }
            Mock Get-AzADAppCredential -ModuleName Check-ServicePrincipalSecrets {
                @(
                    [pscustomobject]@{
                        DisplayName = 'secret-1'
                        EndDateTime = (Get-Date).AddDays(10)
                    },
                    [pscustomobject]@{
                        DisplayName = 'secret-2'
                        EndDateTime = (Get-Date).AddDays(20)
                    }
                )
            }
        }

        It 'Returns non-compliant and lists the valid credentials' {
            $result = Get-DepartmentServicePrincipalNameSecrets @script:commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -BeLike 'Multiple valid credentials exist.*secret-1*'
            $result.ComplianceResults.Comments | Should -BeLike '*secret-2*'
        }
    }

    Context 'When retrieving the service principal throws' {
        BeforeAll {
            Mock Get-AzADServicePrincipal -ModuleName Check-ServicePrincipalSecrets { throw 'Lookup failed' }
        }

        It 'Captures the error and returns the missing SPN message' {
            $result = Get-DepartmentServicePrincipalNameSecrets @script:commonParams

            $result.Errors.Count | Should -Be 1
            ([string]$result.Errors) | Should -BeLike '*Failed to retrieve Service Principal*'
            $result.ComplianceResults.Comments | Should -Be $script:msgTable.NoSPN
        }
    }

    Context 'When multi-cloud profiles are enabled' {
        BeforeAll {
            Mock Get-AzADServicePrincipal -ModuleName Check-ServicePrincipalSecrets {
                [pscustomobject]@{
                    Id    = 'spn-001'
                    AppId = 'app-001'
                }
            }
            Mock Get-AzADAppCredential -ModuleName Check-ServicePrincipalSecrets {
                @(
                    [pscustomobject]@{
                        DisplayName = 'active-secret'
                        EndDateTime = (Get-Date).AddDays(10)
                    }
                )
            }
            Mock Add-ProfileInformation -ModuleName Check-ServicePrincipalSecrets { param($Result) return $Result }
        }

        It 'Calls Add-ProfileInformation' {
            $null = Get-DepartmentServicePrincipalNameSecrets @script:commonParams -EnableMultiCloudProfiles -CloudUsageProfiles '3' -ModuleProfiles '1,2,3'

            Should -Invoke Add-ProfileInformation -ModuleName Check-ServicePrincipalSecrets -Times 1
        }
    }
}
