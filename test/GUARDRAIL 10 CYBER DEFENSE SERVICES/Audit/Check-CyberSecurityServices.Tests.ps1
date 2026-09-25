BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Add-ProfileInformation { param($Result) return $Result }

    Import-Module (Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 10 CYBER DEFENSE SERVICES\Audit\Check-CyberSecurityServices.psm1') -Force
}

AfterAll {
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-CBSSensors' {
    BeforeAll {
        $script:msgTable = @{
            cbsSubDoesntExist     = 'CBS subscription does not exist.'
            cbssMitigation        = 'Create CBS resources in {0}.'
            cbssCompliant         = 'CBS sensors found for'
            cbssV3DetectedSuffix  = 'V3 sensors detected.'
            cbssV2DeprecatedWarning = 'V2 sensors detected.'
            cbcSensorsdontExist   = 'CBS sensors not found in'
        }
        $script:params = @{
            SubscriptionName = 'Subscription One'
            TenantID         = '12345678-1111-2222-3333-444444444444'
            ControlName      = 'GUARDRAIL 10'
            ItemName         = 'CBS Sensors'
            itsgcode         = 'SI-4'
            msgTable         = $script:msgTable
            ReportTime       = '2026-09-25'
        }
    }

    It 'Returns non-compliant when the subscription is missing' {
        Mock Get-AzSubscription -ModuleName Check-CyberSecurityServices { @() }

        $result = Check-CBSSensors @script:params

        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'CBS subscription does not exist.'
    }

    It 'Returns compliant when all v3 resources exist' {
        Mock Get-AzSubscription -ModuleName Check-CyberSecurityServices {
            @([pscustomobject]@{ Id = 'sub-1'; Name = 'Subscription One'; State = 'Enabled' })
        }
        Mock Set-AzContext -ModuleName Check-CyberSecurityServices { }
        Mock Get-AzResource -ModuleName Check-CyberSecurityServices { 'found' }

        $result = Check-CBSSensors @script:params

        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -BeLike '*V3 sensors detected.*'
    }

    It 'Falls back to v2 sensors when a v3 resource is missing' {
        Mock Get-AzSubscription -ModuleName Check-CyberSecurityServices {
            @([pscustomobject]@{ Id = 'sub-1'; Name = 'Subscription One'; State = 'Enabled' })
        }
        Mock Set-AzContext -ModuleName Check-CyberSecurityServices { }
        Mock Get-AzResource -ModuleName Check-CyberSecurityServices -ParameterFilter { $Name -like 'cbsstate*' } { '' }
        Mock Get-AzResource -ModuleName Check-CyberSecurityServices -ParameterFilter { $Name -notlike 'cbsstate*' } { 'found' }

        $result = Check-CBSSensors @script:params

        $result.ComplianceResults.Comments | Should -BeLike '*V2 sensors detected.*'
    }
}
