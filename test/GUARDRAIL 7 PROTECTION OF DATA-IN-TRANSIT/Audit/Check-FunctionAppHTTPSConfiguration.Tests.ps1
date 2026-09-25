BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Check-PBMMPolicies { }
    function global:Set-SubscriptionNotEvaluatedStatus { param($Result) return $Result }

    Import-Module (Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 7 PROTECTION OF DATA-IN-TRANSIT\Audit\Check-FunctionAppHTTPSConfiguration.psm1') -Force
}

AfterAll {
    Remove-Item Function:\Check-PBMMPolicies -ErrorAction SilentlyContinue
    Remove-Item Function:\Set-SubscriptionNotEvaluatedStatus -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Verify-FunctionAppHTTPSConfiguration' {
    BeforeAll {
        $script:params = @{
            ControlName = 'GUARDRAIL 7'
            ItemName    = 'Function App HTTPS'
            PolicyID    = 'policy-1'
            itsgcode    = 'SC-8'
            msgTable    = @{}
            ReportTime  = '2026-09-25'
        }
    }

    It 'Uses the expected PBMM policy name' {
        Mock Get-AzSubscription -ModuleName Check-FunctionAppHTTPSConfiguration {
            @([pscustomobject]@{ Id = 'sub-1'; Name = 'Enabled Sub'; State = 'Enabled' })
        }
        Mock Check-PBMMPolicies -ModuleName Check-FunctionAppHTTPSConfiguration {
            @([pscustomobject]@{ SubscriptionName = 'Enabled Sub'; ComplianceStatus = $true })
        }

        $result = Verify-FunctionAppHTTPSConfiguration @script:params

        $result.ComplianceResults[0].ComplianceStatus | Should -BeTrue
        Should -Invoke Check-PBMMPolicies -ModuleName Check-FunctionAppHTTPSConfiguration -Times 1 -ParameterFilter {
            $requiredPolicyExemptionIds -contains 'functionappshouldonlybeaccessibleoverhttps'
        }
    }

    It 'Throws when Get-AzSubscription fails' {
        Mock Get-AzSubscription -ModuleName Check-FunctionAppHTTPSConfiguration { throw 'boom' }
        { Verify-FunctionAppHTTPSConfiguration @script:params } | Should -Throw
    }
}
