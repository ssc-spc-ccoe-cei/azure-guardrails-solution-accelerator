BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Check-PBMMPolicies { }
    function global:Set-SubscriptionNotEvaluatedStatus { param($Result) return $Result }

    Import-Module (Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 6 PROTECTION OF DATA-AT-REST\Audit\Check-ProtectionDataAtRest.psm1') -Force
}

AfterAll {
    Remove-Item Function:\Check-PBMMPolicies -ErrorAction SilentlyContinue
    Remove-Item Function:\Set-SubscriptionNotEvaluatedStatus -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Verify-ProtectionDataAtRest' {
    BeforeAll {
        $script:params = @{
            ControlName = 'GUARDRAIL 6'
            ItemName    = 'Protection Data At Rest'
            PolicyID    = 'policy-1'
            itsgcode    = 'SC-28'
            msgTable    = @{ }
            ReportTime  = '2026-09-25'
        }
    }

    It 'Returns Check-PBMMPolicies output for enabled subscriptions' {
        Mock Get-AzSubscription -ModuleName Check-ProtectionDataAtRest {
            @(
                [pscustomobject]@{ Id = 'sub-1'; Name = 'Enabled Sub'; State = 'Enabled' },
                [pscustomobject]@{ Id = 'sub-2'; Name = 'Disabled Sub'; State = 'Disabled' }
            )
        }
        Mock Check-PBMMPolicies -ModuleName Check-ProtectionDataAtRest {
            @([pscustomobject]@{ SubscriptionName = 'Enabled Sub'; ComplianceStatus = $true })
        }

        $result = Verify-ProtectionDataAtRest @script:params

        $result.ComplianceResults | Should -HaveCount 1
        $result.ComplianceResults[0].SubscriptionName | Should -Be 'Enabled Sub'
        $result.Errors.Count | Should -Be 0
    }

    It 'Throws when subscription discovery fails' {
        Mock Get-AzSubscription -ModuleName Check-ProtectionDataAtRest { throw 'boom' }

        { Verify-ProtectionDataAtRest @script:params } | Should -Throw
    }
}
