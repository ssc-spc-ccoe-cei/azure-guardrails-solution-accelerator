BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Invoke-GraphQueryEX { }
    function global:Add-ProfileInformation { param($Result) return $Result }

    Import-Module (Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 13 PLAN FOR CONTINUITY\Audit\Check-BreakGlassAccountIdentityProtectionLicense.psm1') -Force
}

AfterAll {
    Remove-Item Function:\Invoke-GraphQueryEX -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Get-BreakGlassAccountLicense' {
    BeforeAll {
        $script:msgTable = @{
            firstBgAccount          = 'first account'
            secondBgAccount         = 'second account'
            bgValidLicenseAssigned  = 'has a valid P2 license.'
            bgNoValidLicenseAssigned = 'No valid P2 license for'
        }
        $script:params = @{
            FirstBreakGlassUPN = 'bg1@contoso.com'
            SecondBreakGlassUPN = 'bg2@contoso.com'
            ControlName      = 'GUARDRAIL 13'
            ItemName         = 'Identity Protection License'
            itsgcode         = 'CP-2'
            msgTable         = $script:msgTable
            ReportTime       = '2026-09-25'
        }
    }

    It 'Returns compliant when both break glass accounts have AAD Premium P2' {
        Mock Invoke-GraphQueryEX -ModuleName Check-BreakGlassAccountIdentityProtectionLicense -ParameterFilter { $urlPath -eq '/users/bg1@contoso.com' } {
            [pscustomobject]@{ Content = [pscustomobject]@{ value = [pscustomobject]@{ id = '1' } } }
        }
        Mock Invoke-GraphQueryEX -ModuleName Check-BreakGlassAccountIdentityProtectionLicense -ParameterFilter { $urlPath -eq '/users/bg2@contoso.com' } {
            [pscustomobject]@{ Content = [pscustomobject]@{ value = [pscustomobject]@{ id = '2' } } }
        }
        Mock Invoke-GraphQueryEX -ModuleName Check-BreakGlassAccountIdentityProtectionLicense -ParameterFilter { $urlPath -like '*/licenseDetails' } {
            [pscustomobject]@{ Content = [pscustomobject]@{ value = @([pscustomobject]@{ servicePlans = @([pscustomobject]@{ ServicePlanName = 'AAD_PREMIUM_P2' }) }) } }
        }

        $result = Get-BreakGlassAccountLicense @script:params

        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -BeLike '*first account has a valid P2 license.*'
    }

    It 'Returns non-compliant when one account lacks the license' {
        Mock Invoke-GraphQueryEX -ModuleName Check-BreakGlassAccountIdentityProtectionLicense -ParameterFilter { $urlPath -eq '/users/bg1@contoso.com' } {
            [pscustomobject]@{ Content = [pscustomobject]@{ value = [pscustomobject]@{ id = '1' } } }
        }
        Mock Invoke-GraphQueryEX -ModuleName Check-BreakGlassAccountIdentityProtectionLicense -ParameterFilter { $urlPath -eq '/users/bg2@contoso.com' } {
            [pscustomobject]@{ Content = [pscustomobject]@{ value = [pscustomobject]@{ id = '2' } } }
        }
        Mock Invoke-GraphQueryEX -ModuleName Check-BreakGlassAccountIdentityProtectionLicense -ParameterFilter { $urlPath -eq '/users/bg1@contoso.com/licenseDetails' } {
            [pscustomobject]@{ Content = [pscustomobject]@{ value = @() } }
        }
        Mock Invoke-GraphQueryEX -ModuleName Check-BreakGlassAccountIdentityProtectionLicense -ParameterFilter { $urlPath -eq '/users/bg2@contoso.com/licenseDetails' } {
            [pscustomobject]@{ Content = [pscustomobject]@{ value = @([pscustomobject]@{ servicePlans = @([pscustomobject]@{ ServicePlanName = 'AAD_PREMIUM_P2' }) }) } }
        }

        $result = Get-BreakGlassAccountLicense @script:params

        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -BeLike '*first account*'
    }
}
