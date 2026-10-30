BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'
    . (Join-Path $PSScriptRoot '..\..\UnitTestHelpers.ps1')
    $script:guardrailPath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 9 NETWORK SECURITY SERVICES\Audit'
    @(
        'Check-NetworkInterfaceIPs.psm1',
        'Check-NetworkSecurityTools.psm1',
        'Check-NetworkWatcherEnabled.psm1',
        'Check-VNetComplianceStatus.psm1'
    ) | ForEach-Object { Import-Module (Join-Path $script:guardrailPath $_) -Force }
}

AfterAll {
    Reset-UnitTestHelpers
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-NetworkInterfaceIPs' {
    It 'returns policy results for the required network interface policy' {
        Mock Check-BuiltInPoliciesPerSubscription -ModuleName Check-NetworkInterfaceIPs {
            @([PSCustomObject]@{ ComplianceStatus = $true })
        }

        $result = Check-NetworkInterfaceIPs -ControlName 'GUARDRAIL 9' -ItemName 'NIC IPs' `
            -itsgcode 'SC-7' -msgTable @{} -ReportTime '2026-10-30'

        $result.ComplianceResults.Count | Should -Be 1
        Should -Invoke Check-BuiltInPoliciesPerSubscription -ModuleName Check-NetworkInterfaceIPs -Times 1 -ParameterFilter {
            $requiredPolicyIds -contains '/providers/Microsoft.Authorization/policyDefinitions/83a86a26-fd1f-447c-b59d-e51f44264114'
        }
    }
}

Describe 'Check-NetworkSecurityTools' {
    It 'marks subscriptions compliant when a firewall is present' {
        Mock Get-AzSubscription -ModuleName Check-NetworkSecurityTools {
            @([PSCustomObject]@{ Id = 'sub-1'; Name = 'Subscription 1'; State = 'Enabled' })
        }
        Mock Get-SubscriptionNetworkSecurityStatus -ModuleName Check-NetworkSecurityTools {
            @{ HasFirewall = $true; HasAppGateway = $false; HasWAFEnabled = $false; FirewallType = 'Azure Firewall' }
        }

        $result = Check-NetworkSecurityTools -ControlName 'GUARDRAIL 9' -ItemName 'Network security' `
            -itsgcode 'SC-7' -msgTable @{ firewallFound = '{0} found' } -ReportTime '2026-10-30'

        $result.ComplianceResults.Count | Should -Be 1
        $result.ComplianceResults[0].ComplianceStatus | Should -BeTrue
        $result.ComplianceResults[0].Comments | Should -Be 'Azure Firewall found'
    }
}

Describe 'Get-NetworkWatcherStatus' {
    It 'returns a compliant result when the subscription has no included virtual networks' {
        Mock Get-AzSubscription -ModuleName Check-NetworkWatcherEnabled {
            @([PSCustomObject]@{ Id = 'sub-1'; Name = 'Subscription 1'; State = 'Enabled' })
        }
        Mock Select-AzSubscription -ModuleName Check-NetworkWatcherEnabled {}
        Mock Get-AzVirtualNetwork -ModuleName Check-NetworkWatcherEnabled { @() }

        $result = Get-NetworkWatcherStatus -ControlName 'GUARDRAIL 9' -itsgcode 'SC-7' `
            -ExcludedVNets '' -msgTable @{ networkWatcherConfigNoRegions = 'No regions'; networkWatcherConfig = 'Watcher' } `
            -ReportTime '2026-10-30' -CBSSubscriptionName 'CBS'

        $result.ComplianceResults.Count | Should -Be 1
        $result.ComplianceResults[0].ComplianceStatus | Should -BeTrue
        $result.ComplianceResults[0].Comments | Should -Be 'No regions'
    }
}

Describe 'Get-VNetComplianceInformation' {
    It 'treats a subscription with no VNets or public IPs as compliant' {
        Mock Get-AzSubscription -ModuleName Check-VNetComplianceStatus {
            @([PSCustomObject]@{ Id = 'sub-1'; Name = 'Subscription 1'; State = 'Enabled' })
        }
        Mock Select-AzSubscription -ModuleName Check-VNetComplianceStatus {}
        Mock Get-AzVirtualNetwork -ModuleName Check-VNetComplianceStatus { @() }
        Mock Invoke-ArgPagedQuery -ModuleName Check-VNetComplianceStatus { @() }

        $result = Get-VNetComplianceInformation -ControlName 'GUARDRAIL 9' -itsgcode 'SC-7' `
            -msgTable @{
                subscriptionScope = 'Subscription'
                vnetDDosConfig = 'DDoS'
                ddosSubscriptionNoResources = 'No resources in {0}'
            } -ReportTime '2026-10-30'

        $result.ComplianceResults.Count | Should -Be 1
        $result.ComplianceResults[0].ComplianceStatus | Should -BeTrue
        $result.ComplianceResults[0].Comments | Should -Be 'No resources in Subscription 1'
    }
}
