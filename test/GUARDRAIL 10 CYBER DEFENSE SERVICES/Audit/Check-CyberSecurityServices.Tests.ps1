BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    . (Join-Path $PSScriptRoot '..\..\UnitTestHelpers.ps1')
    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 10 CYBER DEFENSE SERVICES\Audit\Check-CyberSecurityServices.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Reset-UnitTestHelpers
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-CBSSensors' {
    It 'reports compliance when all v3 sensor resources are present' {
        Mock Get-AzSubscription -ModuleName Check-CyberSecurityServices {
            @([PSCustomObject]@{ Id = 'sub-1'; Name = 'CBS'; State = 'Enabled' })
        }
        Mock Set-AzContext -ModuleName Check-CyberSecurityServices {}
        Mock Get-AzResource -ModuleName Check-CyberSecurityServices {
            param($Name)
            [PSCustomObject]@{ Name = $Name }
        }

        $result = Check-CBSSensors -SubscriptionName 'CBS' -TenantID 'tenant-guid-more' `
            -ControlName 'GUARDRAIL 10' -ItemName 'CBS Sensors' -itsgcode 'SI-4' `
            -msgTable @{ cbssCompliant = 'Compliant'; cbssV3DetectedSuffix = 'V3'; cbsSubDoesntExist = 'No subscription' } `
            -ReportTime '2026-10-30'

        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -BeLike '*V3*'
        Should -Invoke Get-AzResource -ModuleName Check-CyberSecurityServices -Times 3
    }

    It 'reports a missing configured subscription as non-compliant' {
        Mock Get-AzSubscription -ModuleName Check-CyberSecurityServices { @() }

        $result = Check-CBSSensors -SubscriptionName 'CBS' -TenantID 'tenant-guid-more' `
            -ControlName 'GUARDRAIL 10' -ItemName 'CBS Sensors' -itsgcode 'SI-4' `
            -msgTable @{ cbsSubDoesntExist = 'No subscription'; cbssMitigation = 'Deploy in {0}' } `
            -ReportTime '2026-10-30'

        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'No subscription'
    }
}
