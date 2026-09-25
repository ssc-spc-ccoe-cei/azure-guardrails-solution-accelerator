BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Check-PBMMPolicies { }
    function global:Set-SubscriptionNotEvaluatedStatus { param($Result) return $Result }

    Import-Module (Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 7 PROTECTION OF DATA-IN-TRANSIT\Audit\Check-SecureConnectionInTransit.psm1') -Force
}

AfterAll {
    Remove-Item Function:\Check-PBMMPolicies -ErrorAction SilentlyContinue
    Remove-Item Function:\Set-SubscriptionNotEvaluatedStatus -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Verify-SecureConnectionInTransit' {
    BeforeAll {
        $script:params = @{
            ControlName = 'GUARDRAIL 7'
            ItemName    = 'Secure Connections'
            PolicyID    = 'policy-1'
            itsgcode    = 'SC-8'
            msgTable    = @{}
            ReportTime  = '2026-09-25'
        }
    }

    It 'Evaluates both required PBMM policies' {
        Mock Get-AzSubscription -ModuleName Check-SecureConnectionInTransit {
            @([pscustomobject]@{ Id = 'sub-1'; Name = 'Enabled Sub'; State = 'Enabled' })
        }
        Mock Check-PBMMPolicies -ModuleName Check-SecureConnectionInTransit {
            @([pscustomobject]@{ SubscriptionName = 'Enabled Sub'; ComplianceStatus = $true })
        }

        $result = Verify-SecureConnectionInTransit @script:params

        $result.ComplianceResults[0].ComplianceStatus | Should -BeTrue
        Should -Invoke Check-PBMMPolicies -ModuleName Check-SecureConnectionInTransit -Times 1 -ParameterFilter {
            $requiredPolicyExemptionIds.Count -eq 2
        }
    }

    It 'Throws when Get-AzSubscription fails' {
        Mock Get-AzSubscription -ModuleName Check-SecureConnectionInTransit { throw 'boom' }
        { Verify-SecureConnectionInTransit @script:params } | Should -Throw
    }
}
