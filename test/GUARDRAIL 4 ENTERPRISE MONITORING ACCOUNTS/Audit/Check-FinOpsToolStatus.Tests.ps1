BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) return $Result }

    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 4 ENTERPRISE MONITORING ACCOUNTS\Audit\Check-FinOpsToolStatus.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-FinOpsToolStatus' {
    BeforeAll {
        $script:msgTable = @{
            SPNNotExist              = 'The service principal does not exist.'
            SPNIncorrectPermissions  = 'The service principal permissions are incorrect.'
            FinOpsToolCompliant      = 'FinOps tooling is compliant.'
            FinOpsToolNonCompliant   = 'FinOps tooling is non-compliant. {0}'
        }
        $script:commonParams = @{
            ControlName = 'GUARDRAIL 4'
            ItemName    = 'FinOps Tool Status'
            itsgcode    = 'AC-4'
            msgTable    = $script:msgTable
            ReportTime  = '2026-09-25'
        }
    }

    Context 'When the service principal is missing' {
        BeforeAll {
            Mock Check-ServicePrincipalExists -ModuleName Check-FinOpsToolStatus { $false }
            Mock Check-ServicePrincipalPermissions -ModuleName Check-FinOpsToolStatus { $true }
        }

        It 'Returns non-compliant and skips the permissions check' {
            $result = Check-FinOpsToolStatus @script:commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -Be ($script:msgTable.FinOpsToolNonCompliant -f $script:msgTable.SPNNotExist)
            Should -Invoke Check-ServicePrincipalPermissions -ModuleName Check-FinOpsToolStatus -Times 0
        }
    }

    Context 'When the service principal exists and has the required permissions' {
        BeforeAll {
            Mock Check-ServicePrincipalExists -ModuleName Check-FinOpsToolStatus { $true }
            Mock Check-ServicePrincipalPermissions -ModuleName Check-FinOpsToolStatus { $true }
        }

        It 'Returns compliant' {
            $result = Check-FinOpsToolStatus @script:commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -Be $script:msgTable.FinOpsToolCompliant
        }
    }

    Context 'When the service principal exists but permissions are missing' {
        BeforeAll {
            Mock Check-ServicePrincipalExists -ModuleName Check-FinOpsToolStatus { $true }
            Mock Check-ServicePrincipalPermissions -ModuleName Check-FinOpsToolStatus { $false }
        }

        It 'Returns non-compliant with the permissions message' {
            $result = Check-FinOpsToolStatus @script:commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -Be ($script:msgTable.FinOpsToolNonCompliant -f $script:msgTable.SPNIncorrectPermissions)
        }
    }

    Context 'When multi-cloud profiles are enabled' {
        BeforeAll {
            Mock Check-ServicePrincipalExists -ModuleName Check-FinOpsToolStatus { $true }
            Mock Check-ServicePrincipalPermissions -ModuleName Check-FinOpsToolStatus { $true }
            Mock Add-ProfileInformation -ModuleName Check-FinOpsToolStatus { param($Result) return $Result }
        }

        It 'Calls Add-ProfileInformation' {
            $null = Check-FinOpsToolStatus @script:commonParams -EnableMultiCloudProfiles -CloudUsageProfiles '3' -ModuleProfiles '1,2,3'

            Should -Invoke Add-ProfileInformation -ModuleName Check-FinOpsToolStatus -Times 1
        }
    }
}
