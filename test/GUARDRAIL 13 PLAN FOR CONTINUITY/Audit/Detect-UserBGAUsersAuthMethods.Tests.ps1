BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Invoke-GraphQueryEX { }
    function global:Add-ProfileInformation { param($Result) return $Result }

    Import-Module (Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 13 PLAN FOR CONTINUITY\Audit\Detect-UserBGAUsersAuthMethods.psm1') -Force
}

AfterAll {
    Remove-Item Function:\Invoke-GraphQueryEX -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Get-UserAuthenticationMethod' {
    BeforeAll {
        $script:msgTable = @{ mfaEnabledFor = 'MFA enabled for {0}' }
        $script:params = @{
            ControlName          = 'GUARDRAIL 13'
            msgTable             = $script:msgTable
            ItemName             = 'Break Glass MFA'
            itsgcode             = 'CP-2'
            FirstBreakGlassEmail = 'bg1@contoso.com'
            SecondBreakGlassEmail = 'bg2@contoso.com'
            ReportTime           = '2026-09-25'
        }
    }

    It 'Returns compliant when neither break glass account has MFA methods' {
        Mock Invoke-GraphQueryEX -ModuleName Detect-UserBGAUsersAuthMethods {
            [pscustomobject]@{ Content = [pscustomobject]@{ value = @() } }
        }

        $result = Get-UserAuthenticationMethod @script:params

        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.Errors.Count | Should -Be 0
    }

    It 'Returns non-compliant when an MFA method is present' {
        Mock Invoke-GraphQueryEX -ModuleName Detect-UserBGAUsersAuthMethods {
            if ($urlPath -like '*bg1*') {
                [pscustomobject]@{ Content = [pscustomobject]@{ value = @([pscustomobject]@{ '@odata.type' = '#microsoft.graph.phoneAuthenticationMethod' }) } }
            }
            else {
                [pscustomobject]@{ Content = [pscustomobject]@{ value = @() } }
            }
        }

        $result = Get-UserAuthenticationMethod @script:params

        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'MFA enabled for bg1@contoso.com'
    }
}
