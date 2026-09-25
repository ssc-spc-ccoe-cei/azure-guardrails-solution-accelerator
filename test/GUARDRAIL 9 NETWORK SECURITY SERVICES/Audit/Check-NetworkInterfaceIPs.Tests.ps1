BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Check-BuiltInPoliciesPerSubscription { }

    Import-Module (Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 9 NETWORK SECURITY SERVICES\Audit\Check-NetworkInterfaceIPs.psm1') -Force
}

AfterAll {
    Remove-Item Function:\Check-BuiltInPoliciesPerSubscription -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-NetworkInterfaceIPs' {
    It 'Calls the built-in policy helper with the expected policy id' {
        Mock Check-BuiltInPoliciesPerSubscription -ModuleName Check-NetworkInterfaceIPs {
            @([pscustomobject]@{ ComplianceStatus = $true })
        }

        $result = Check-NetworkInterfaceIPs -ControlName 'GUARDRAIL 9' -ItemName 'NIC Public IPs' -itsgcode 'SC-7' -msgTable @{} -ReportTime '2026-09-25'

        $result.ComplianceResults[0].ComplianceStatus | Should -BeTrue
        Should -Invoke Check-BuiltInPoliciesPerSubscription -ModuleName Check-NetworkInterfaceIPs -Times 1 -ParameterFilter {
            $requiredPolicyIds[0] -eq '/providers/Microsoft.Authorization/policyDefinitions/83a86a26-fd1f-447c-b59d-e51f44264114'
        }
    }
}
