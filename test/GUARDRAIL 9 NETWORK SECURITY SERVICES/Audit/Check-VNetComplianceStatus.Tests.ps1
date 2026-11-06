BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Set-SubscriptionNotEvaluatedStatus { param($Result) return $Result }
    function global:Add-ProfileInformation { param($Result) return $Result }

    Import-Module (Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 9 NETWORK SECURITY SERVICES\Audit\Check-VNetComplianceStatus.psm1') -Force
}

AfterAll {
    Remove-Item Function:\Set-SubscriptionNotEvaluatedStatus -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Get-SubscriptionPublicIpStatus' {
    It 'Counts protected public IPs' {
        Mock Invoke-ArgPagedQuery -ModuleName Check-VNetComplianceStatus {
            @(
                [pscustomobject]@{ publicIpName = 'pip1'; protectionMode = 'Enabled' },
                [pscustomobject]@{ publicIpName = 'pip2'; protectionMode = 'Disabled' }
            )
        }
        $errors = [System.Collections.ArrayList]::new()
        $msgTable = @{ ddosPublicIpCheckFailed = 'Failed {0} {1}' }

        $result = Get-SubscriptionPublicIpStatus -SubscriptionId 'sub-1' -SubscriptionName 'Subscription One' -msgTable $msgTable -ErrorList $errors

        $result.PublicIpCount | Should -Be 2
        $result.ProtectedPublicIps | Should -Be 1
    }
}

Describe 'Get-SubscriptionComplianceObject' {
    It 'Returns compliant when a protected public IP exists' {
        $msgTable = @{
            subscriptionScope                  = 'Subscription Scope'
            vnetDDosConfig                     = 'VNet DDoS'
            ddosSubscriptionNoResources        = '{0} has no resources.'
            ddosSubscriptionProtectionFound    = '{0} has protection {1}/{2}/{3}/{4}'
            ddosPublicIpCheckFailedNoProtection = '{0} failed {1}/{2}'
            ddosSubscriptionProtectionMissing  = '{0} missing {1}/{2}/{3}/{4}'
        }
        $errors = [System.Collections.ArrayList]::new()

        $result = Get-SubscriptionComplianceObject -sub ([pscustomobject]@{ Id = 'sub-1'; Name = 'Subscription One' }) -includedVNETs @() -publicIpStatus ([pscustomobject]@{ QueryFailed = $false; PublicIpCount = 1; ProtectedPublicIps = 1 }) -msgTable $msgTable -ControlName 'GUARDRAIL 9' -itsgcode 'SC-7' -ReportTime '2026-09-25' -EnableMultiCloudProfiles:$false -ErrorList $errors -CloudUsageProfiles '3' -ModuleProfiles ''

        $result.ComplianceStatus | Should -BeTrue
    }
}

Describe 'Get-VNetComplianceInformation' {
    It 'Returns a compliant subscription row when no resources are in scope' {
        $msgTable = @{
            subscriptionScope                  = 'Subscription Scope'
            vnetDDosConfig                     = 'VNet DDoS'
            ddosSubscriptionNoResources        = '{0} has no resources.'
            ddosSubscriptionProtectionFound    = '{0} has protection {1}/{2}/{3}/{4}'
            ddosPublicIpCheckFailedNoProtection = '{0} failed {1}/{2}'
            ddosSubscriptionProtectionMissing  = '{0} missing {1}/{2}/{3}/{4}'
        }
        Mock Get-AzSubscription -ModuleName Check-VNetComplianceStatus {
            @([pscustomobject]@{ Id = 'sub-1'; SubscriptionId = 'sub-1'; Name = 'Subscription One'; State = 'Enabled' })
        }
        Mock Select-AzSubscription -ModuleName Check-VNetComplianceStatus { }
        Mock Get-AzVirtualNetwork -ModuleName Check-VNetComplianceStatus { @() }
        Mock Get-SubscriptionPublicIpStatus -ModuleName Check-VNetComplianceStatus {
            [pscustomobject]@{ QueryFailed = $false; PublicIpCount = 0; ProtectedPublicIps = 0 }
        }

        $result = Get-VNetComplianceInformation -ControlName 'GUARDRAIL 9' -itsgcode 'SC-7' -msgTable $msgTable -ReportTime '2026-09-25'

        $result.ComplianceResults[0].ComplianceStatus | Should -BeTrue
        $result.ComplianceResults[0].Comments | Should -Be 'Subscription One has no resources.'
    }
}
