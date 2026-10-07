BeforeAll {
    # Ensure Write-Error in source modules stays non-terminating (CI and VS Code set $ErrorActionPreference = 'Stop')
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    # Define stubs for external functions
    function global:Get-AzADUser { }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) return $Result }

    # Import the module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 2 MANAGE ACCESS\Audit\Check-DeprecatedAccounts.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Item Function:\Get-AzADUser -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-DeprecatedUsers' {

    BeforeAll {
        $script:msgTable = @{
            noncompliantUsers   = 'Deprecated users: '
            compliantComment    = 'No deprecated users found.'
            noncompliantComment = '{0} deprecated user(s) found. {1}'
            mitigationCommands  = 'Review and remove deprecated accounts.'
        }
        $script:commonParams = @{
            ControlName = 'GUARDRAIL 2'
            ItemName    = 'Deprecated Accounts'
            itsgcode    = 'AC-2'
            msgTable    = $script:msgTable
            ReportTime  = (Get-Date -Format 'yyyy-MM-dd')
        }
    }

    Context 'When no deprecated users are returned' {

        BeforeAll {
            Mock Get-AzADUser -ModuleName Check-DeprecatedAccounts { @() }
        }

        It 'Returns compliant' {
            $result = Check-DeprecatedUsers @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -Be $script:msgTable.compliantComment
        }
    }

    Context 'When disabled cloud-only users exist' {

        BeforeAll {
            Mock Get-AzADUser -ModuleName Check-DeprecatedAccounts {
                @(
                    [PSCustomObject]@{
                        UserPrincipalName      = 'deprecated1@tenant.onmicrosoft.com'
                        OnPremisesSyncEnabled  = $null
                    },
                    [PSCustomObject]@{
                        UserPrincipalName      = 'deprecated2@tenant.onmicrosoft.com'
                        OnPremisesSyncEnabled  = $null
                    }
                )
            }
        }

        It 'Returns non-compliant and lists the deprecated UPNs in comments' {
            $result = Check-DeprecatedUsers @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -BeLike '*deprecated1@tenant.onmicrosoft.com*'
            $result.ComplianceResults.Comments | Should -BeLike '*deprecated2@tenant.onmicrosoft.com*'
        }
    }

    Context 'When EnableMultiCloudProfiles is set' {

        BeforeAll {
            Mock Get-AzADUser -ModuleName Check-DeprecatedAccounts { @() }
            Mock Add-ProfileInformation -ModuleName Check-DeprecatedAccounts { param($Result) return $Result }
        }

        It 'Calls Add-ProfileInformation' {
            $params = $script:commonParams.Clone()
            $result = Check-DeprecatedUsers @params -EnableMultiCloudProfiles -CloudUsageProfiles '3' -ModuleProfiles '1,2,3'
            Should -Invoke Add-ProfileInformation -ModuleName Check-DeprecatedAccounts -Times 1
        }
    }
}
