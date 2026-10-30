BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    . (Join-Path $PSScriptRoot '..\..\UnitTestHelpers.ps1')
    $script:guardrailPath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 13 PLAN FOR CONTINUITY\Audit'
    @(
        'Check-BreakGlassAccountIdentityProtectionLicense.psm1',
        'Check-BreakGlassAccountOwnersInformation.psm1',
        'Detect-UserBGAUsersAuthMethods.psm1',
        'Monitor-BreakGlassAccount.psm1',
        'Validate-BreakGlassAccount.psm1'
    ) | ForEach-Object { Import-Module (Join-Path $script:guardrailPath $_) -Force }
}

AfterAll {
    Reset-UnitTestHelpers
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Get-BreakGlassAccounts' {
    It 'requires two distinct break-glass accounts' {
        Mock Invoke-GraphQueryEX -ModuleName Validate-BreakGlassAccount { throw 'Graph should not be called' }

        $result = Get-BreakGlassAccounts -FirstBreakGlassUPN 'same@example.test' `
            -SecondBreakGlassUPN 'same@example.test' -msgTable @{ bgAccountsCompliance2 = 'Accounts must differ' } `
            -ControlName 'GUARDRAIL 13' -ItemName 'Break glass accounts' -itsgcode 'CP-2' `
            -ReportTime '2026-10-30'

        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'Accounts must differ'
        Should -Invoke Invoke-GraphQueryEX -ModuleName Validate-BreakGlassAccount -Times 0
    }

    It 'returns compliant when both configured users are directory members' {
        Mock Invoke-GraphQueryEX -ModuleName Validate-BreakGlassAccount {
            [PSCustomObject]@{ Content = [PSCustomObject]@{ value = [PSCustomObject]@{ userType = 'Member' } } }
        }

        $result = Get-BreakGlassAccounts -FirstBreakGlassUPN 'first@example.test' `
            -SecondBreakGlassUPN 'second@example.test' `
            -msgTable @{ bgAccountsCompliance = 'Accounts: {0}, {1}' } -ControlName 'GUARDRAIL 13' `
            -ItemName 'Break glass accounts' -itsgcode 'CP-2' -ReportTime '2026-10-30'

        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        Should -Invoke Invoke-GraphQueryEX -ModuleName Validate-BreakGlassAccount -Times 2
    }
}

Describe 'Get-BreakGlassAccountLicense' {
    It 'requires the P2 service plan on both break-glass accounts' {
        Mock Invoke-GraphQueryEX -ModuleName Check-BreakGlassAccountIdentityProtectionLicense {
            param($urlPath)

            if ($urlPath -like '*/licenseDetails') {
                [PSCustomObject]@{
                    Content = [PSCustomObject]@{
                        value = @([PSCustomObject]@{
                            servicePlans = @([PSCustomObject]@{ ServicePlanName = 'AAD_PREMIUM_P2' })
                        })
                    }
                }
            } else {
                [PSCustomObject]@{ Content = [PSCustomObject]@{ value = [PSCustomObject]@{ id = 'user-1' } } }
            }
        }

        $result = Get-BreakGlassAccountLicense -FirstBreakGlassUPN 'first@example.test' `
            -SecondBreakGlassUPN 'second@example.test' -ControlName 'GUARDRAIL 13' -ItemName 'P2 license' `
            -itsgcode 'CP-2' -msgTable @{ firstBgAccount = 'First'; secondBgAccount = 'Second'; bgValidLicenseAssigned = 'licensed' } `
            -ReportTime '2026-10-30'

        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'First licensed & Second licensed'
    }
}

Describe 'Get-BreakGlassOwnerinformation' {
    It 'returns compliant when both accounts have a manager' {
        Mock Invoke-GraphQueryEX -ModuleName Check-BreakGlassAccountOwnersInformation {
            [PSCustomObject]@{ StatusCode = 200 }
        }

        $result = Get-BreakGlassOwnerinformation -FirstBreakGlassUPNOwner 'first@example.test' `
            -SecondBreakGlassUPNOwner 'second@example.test' -ControlName 'GUARDRAIL 13' `
            -ItemName 'Break glass owners' -itsgcode 'CP-2' -msgTable @{ bgBothHaveManager = 'Both have managers' } `
            -ReportTime '2026-10-30'

        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'Both have managers'
    }
}

Describe 'Get-UserAuthenticationMethod' {
    It 'is compliant when neither account has phone or authenticator MFA configured' {
        Mock Invoke-GraphQueryEX -ModuleName Detect-UserBGAUsersAuthMethods {
            [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @() } }
        }

        $result = Get-UserAuthenticationMethod -ControlName 'GUARDRAIL 13' -msgTable @{ mfaEnabledFor = 'MFA enabled for {0}' } `
            -ItemName 'Authentication methods' -itsgcode 'CP-2' -FirstBreakGlassEmail 'first@example.test' `
            -SecondBreakGlassEmail 'second@example.test' -ReportTime '2026-10-30'

        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -BeNullOrEmpty
        Should -Invoke Invoke-GraphQueryEX -ModuleName Detect-UserBGAUsersAuthMethods -Times 2
    }
}

Describe 'Test-BreakGlassAccounts' {
    It 'rejects duplicate configured accounts' {
        Mock Invoke-GraphQueryEX -ModuleName Monitor-BreakGlassAccount { throw 'Graph should not be called' }

        $result = Test-BreakGlassAccounts -ControlName 'GUARDRAIL 13' -ItemName 'Account monitoring' `
            -FirstBreakGlassUPN 'same@example.test' -SecondBreakGlassUPN 'same@example.test' `
            -LAWResourceId '/subscriptions/sub/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/law' `
            -msgTable @{ isNotCompliant = 'Non-compliant'; bgAccountNotExist = 'Accounts must be unique' } `
            -itsgcode 'CP-2' -ReportTime '2026-10-30'

        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        Should -Invoke Invoke-GraphQueryEX -ModuleName Monitor-BreakGlassAccount -Times 0
    }
}
