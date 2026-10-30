BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    . (Join-Path $PSScriptRoot '..\..\UnitTestHelpers.ps1')
    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 6 PROTECTION OF DATA-AT-REST\Audit\Check-ProtectionDataAtRest.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Reset-UnitTestHelpers
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Verify-ProtectionDataAtRest' {
    It 'evaluates only enabled subscriptions and returns policy results' {
        Mock Get-AzSubscription -ModuleName Check-ProtectionDataAtRest {
            @(
                [PSCustomObject]@{ Id = 'enabled'; State = 'Enabled' }
                [PSCustomObject]@{ Id = 'disabled'; State = 'Disabled' }
            )
        }
        Mock Check-PBMMPolicies -ModuleName Check-ProtectionDataAtRest {
            [PSCustomObject]@{ ComplianceStatus = $true }
        }

        $result = Verify-ProtectionDataAtRest -ControlName 'GUARDRAIL 6' -ItemName 'Data at rest' `
            -PolicyID 'policy' -itsgcode 'SC-28' -msgTable @{} -ReportTime '2026-10-30'

        $result.ComplianceResults.Count | Should -Be 1
        $result.ComplianceResults[0].ComplianceStatus | Should -BeTrue
        Should -Invoke Check-PBMMPolicies -ModuleName Check-ProtectionDataAtRest -Times 1 -ParameterFilter {
            $objList.Count -eq 1 -and $objList[0].Id -eq 'enabled' -and
            $requiredPolicyExemptionIds -contains 'TransparentDataEncryptionOnSqlDatabasesShouldBeEnabled'
        }
    }

    It 'passes profile parameters only when multi-cloud profiles are enabled' {
        Mock Get-AzSubscription -ModuleName Check-ProtectionDataAtRest {
            @([PSCustomObject]@{ Id = 'enabled'; State = 'Enabled' })
        }
        Mock Check-PBMMPolicies -ModuleName Check-ProtectionDataAtRest {
            [PSCustomObject]@{ ComplianceStatus = $true }
        }

        Verify-ProtectionDataAtRest -ControlName 'GUARDRAIL 6' -ItemName 'Data at rest' `
            -PolicyID 'policy' -itsgcode 'SC-28' -msgTable @{} -ReportTime '2026-10-30' `
            -EnableMultiCloudProfiles -CloudUsageProfiles '2' -ModuleProfiles 'module'

        Should -Invoke Check-PBMMPolicies -ModuleName Check-ProtectionDataAtRest -Times 1 -ParameterFilter {
            $EnableMultiCloudProfiles -and $CloudUsageProfiles -eq '2' -and $ModuleProfiles -eq 'module'
        }
    }
}
