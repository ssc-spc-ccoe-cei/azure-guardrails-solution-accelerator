BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Invoke-GraphQueryEX { }
    function global:Add-ProfileInformation { param($Result) return $Result }

    Import-Module (Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 13 PLAN FOR CONTINUITY\Audit\Validate-BreakGlassAccount.psm1') -Force
}

AfterAll {
    Remove-Item Function:\Invoke-GraphQueryEX -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Get-BreakGlassAccounts' {
    BeforeAll {
        $script:msgTable = @{
            bgAccountsCompliance  = 'First: {0}; Second: {1}'
            bgAccountsCompliance2 = 'Break glass accounts must be unique.'
        }
        $script:baseParams = @{
            msgTable    = $script:msgTable
            itsgcode    = 'CP-2'
            ControlName = 'GUARDRAIL 13'
            ItemName    = 'Break Glass Accounts'
            ReportTime  = '2026-09-25'
        }
    }

    It 'Returns non-compliant when both configured accounts are the same' {
        $result = Get-BreakGlassAccounts @script:baseParams -FirstBreakGlassUPN 'bg@contoso.com' -SecondBreakGlassUPN 'bg@contoso.com'

        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'Break glass accounts must be unique.'
    }

    It 'Returns compliant when both member accounts exist' {
        Mock Invoke-GraphQueryEX -ModuleName Validate-BreakGlassAccount {
            [pscustomobject]@{ Content = [pscustomobject]@{ value = [pscustomobject]@{ userType = 'Member' } } }
        }

        $result = Get-BreakGlassAccounts @script:baseParams -FirstBreakGlassUPN 'bg1@contoso.com' -SecondBreakGlassUPN 'bg2@contoso.com'

        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'First: True; Second: True'
    }
}
