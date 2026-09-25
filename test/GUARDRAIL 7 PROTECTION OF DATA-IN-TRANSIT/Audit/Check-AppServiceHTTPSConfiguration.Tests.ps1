BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Check-PBMMPolicies { }
    function global:Set-SubscriptionNotEvaluatedStatus { param($Result) return $Result }

    Import-Module (Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 7 PROTECTION OF DATA-IN-TRANSIT\Audit\Check-AppServiceHTTPSConfiguration.psm1') -Force
}

AfterAll {
    Remove-Item Function:\Check-PBMMPolicies -ErrorAction SilentlyContinue
    Remove-Item Function:\Set-SubscriptionNotEvaluatedStatus -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Verify-AppServiceHTTPSConfiguration' {
    BeforeAll {
        $script:params = @{
            ControlName = 'GUARDRAIL 7'
            ItemName    = 'App Service HTTPS'
            PolicyID    = 'policy-1'
            itsgcode    = 'SC-8'
            msgTable    = @{}
            ReportTime  = '2026-09-25'
        }
    }

    It 'Uses the expected PBMM policy name' {
        Mock Get-AzSubscription -ModuleName Check-AppServiceHTTPSConfiguration {
            @([pscustomobject]@{ Id = 'sub-1'; Name = 'Enabled Sub'; State = 'Enabled' })
        }
        Mock Check-PBMMPolicies -ModuleName Check-AppServiceHTTPSConfiguration {
            @([pscustomobject]@{ SubscriptionName = 'Enabled Sub'; ComplianceStatus = $true })
        }

        $result = Verify-AppServiceHTTPSConfiguration @script:params

        $result.ComplianceResults[0].ComplianceStatus | Should -BeTrue
        $result.Errors.Count | Should -Be 0
    }

    It 'Throws when Get-AzSubscription fails' {
        Mock Get-AzSubscription -ModuleName Check-AppServiceHTTPSConfiguration { throw 'boom' }
        { Verify-AppServiceHTTPSConfiguration @script:params } | Should -Throw
    }
}
