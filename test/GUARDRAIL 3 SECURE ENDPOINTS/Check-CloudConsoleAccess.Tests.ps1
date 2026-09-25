BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Get-allowedLocationCAPCompliance { }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) return $Result }

    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 3 SECURE ENDPOINTS\Audit\Check-CloudConsoleAccess.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Item Function:\Get-allowedLocationCAPCompliance -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Get-CloudConsoleAccess' {
    BeforeAll {
        $script:commonParams = @{
            ControlName = 'GUARDRAIL 3'
            ItemName    = 'Cloud Console Access'
            itsgcode    = 'AC-3'
            msgTable    = @{}
            ReportTime  = '2026-09-25'
        }
    }

    Context 'When the underlying location-based CAP check is compliant' {
        BeforeAll {
            Mock Get-allowedLocationCAPCompliance -ModuleName Check-CloudConsoleAccess {
                [pscustomobject]@{
                    ComplianceStatus = $true
                    Comments         = 'Named locations are configured.'
                    Errors           = [System.Collections.ArrayList]::new()
                }
            }
        }

        It 'Returns the helper compliance result' {
            $result = Get-CloudConsoleAccess @script:commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -Be 'Named locations are configured.'
            $result.Errors.Count | Should -Be 0
        }
    }

    Context 'When the underlying location-based CAP check is non-compliant' {
        BeforeAll {
            Mock Get-allowedLocationCAPCompliance -ModuleName Check-CloudConsoleAccess {
                $errors = [System.Collections.ArrayList]::new()
                $null = $errors.Add('Named locations are missing.')
                [pscustomobject]@{
                    ComplianceStatus = $false
                    Comments         = 'Named locations are missing.'
                    Errors           = $errors
                }
            }
        }

        It 'Returns the propagated comments and errors' {
            $result = Get-CloudConsoleAccess @script:commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -Be 'Named locations are missing.'
            $result.Errors.Count | Should -Be 1
        }
    }

    Context 'When multi-cloud profiles are enabled' {
        BeforeAll {
            Mock Get-allowedLocationCAPCompliance -ModuleName Check-CloudConsoleAccess {
                [pscustomobject]@{
                    ComplianceStatus = $true
                    Comments         = 'Named locations are configured.'
                    Errors           = [System.Collections.ArrayList]::new()
                }
            }
            Mock Add-ProfileInformation -ModuleName Check-CloudConsoleAccess { param($Result) return $Result }
        }

        It 'Calls Add-ProfileInformation' {
            $null = Get-CloudConsoleAccess @script:commonParams -EnableMultiCloudProfiles -CloudUsageProfiles '3' -ModuleProfiles '1,2,3'

            Should -Invoke Add-ProfileInformation -ModuleName Check-CloudConsoleAccess -Times 1
        }
    }
}
