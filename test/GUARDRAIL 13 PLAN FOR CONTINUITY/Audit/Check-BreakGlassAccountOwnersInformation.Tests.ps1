BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Invoke-GraphQueryEX { }
    function global:Hide-Email { param($email) return $email }
    function global:Add-ProfileInformation { param($Result) return $Result }

    Import-Module (Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 13 PLAN FOR CONTINUITY\Audit\Check-BreakGlassAccountOwnersInformation.psm1') -Force
}

AfterAll {
    Remove-Item Function:\Invoke-GraphQueryEX -ErrorAction SilentlyContinue
    Remove-Item Function:\Hide-Email -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Get-BreakGlassOwnerinformation' {
    BeforeAll {
        $script:msgTable = @{
            bgAccountHasManager = '{0} has a manager.'
            bgAccountNoManager  = '{0} has no manager.'
            bgBothHaveManager   = 'Both break glass accounts have managers.'
        }
        $script:params = @{
            FirstBreakGlassUPNOwner  = 'bg1@contoso.com'
            SecondBreakGlassUPNOwner = 'bg2@contoso.com'
            ControlName              = 'GUARDRAIL 13'
            ItemName                 = 'Break Glass Owners'
            itsgcode                 = 'CP-2'
            msgTable                 = $script:msgTable
            ReportTime               = '2026-09-25'
        }
    }

    It 'Returns compliant when both accounts have managers' {
        Mock Invoke-GraphQueryEX -ModuleName Check-BreakGlassAccountOwnersInformation {
            [pscustomobject]@{ StatusCode = 200 }
        }

        $result = Get-BreakGlassOwnerinformation @script:params

        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'Both break glass accounts have managers.'
    }

    It 'Returns non-compliant when one account has no manager' {
        Mock Invoke-GraphQueryEX -ModuleName Check-BreakGlassAccountOwnersInformation -ParameterFilter { $urlPath -like '*bg1*' } {
            [pscustomobject]@{ StatusCode = 404 }
        }
        Mock Invoke-GraphQueryEX -ModuleName Check-BreakGlassAccountOwnersInformation -ParameterFilter { $urlPath -like '*bg2*' } {
            [pscustomobject]@{ StatusCode = 200 }
        }

        $result = Get-BreakGlassOwnerinformation @script:params

        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'bg1@contoso.com has no manager.'
    }
}
