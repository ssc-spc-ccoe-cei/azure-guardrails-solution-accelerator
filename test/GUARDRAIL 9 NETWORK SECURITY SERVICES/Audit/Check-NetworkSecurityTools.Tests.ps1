BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Set-SubscriptionNotEvaluatedStatus { param($Result) return $Result }
    function global:Add-ProfileInformation { param($Result) return $Result }

    Import-Module (Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 9 NETWORK SECURITY SERVICES\Audit\Check-NetworkSecurityTools.psm1') -Force
}

AfterAll {
    Remove-Item Function:\Set-SubscriptionNotEvaluatedStatus -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Get-SubscriptionNetworkSecurityStatus' {
    It 'Returns firewall compliance when Azure Firewall exists' {
        Mock Select-AzSubscription -ModuleName Check-NetworkSecurityTools { }
        Mock Get-AzFirewall -ModuleName Check-NetworkSecurityTools { @([pscustomobject]@{ Name = 'fw1' }) }
        Mock Get-AzApplicationGateway -ModuleName Check-NetworkSecurityTools { @() }

        $errors = [System.Collections.ArrayList]::new()
        $result = Get-SubscriptionNetworkSecurityStatus -Subscription ([pscustomobject]@{ Name = 'Subscription One' }) -ErrorList $errors

        $result.HasFirewall | Should -BeTrue
        $result.FirewallType | Should -Be 'Azure Firewall'
    }
}

Describe 'Check-NetworkSecurityTools' {
    BeforeAll {
        $script:msgTable = @{
            firewallFound                = '{0} is configured.'
            wAFEnabled                   = 'App Gateway WAF enabled.'
            noFirewallOrGatewayCompliant = 'Compliant because another subscription provides the control.'
            wAFNotEnabled                = 'App Gateway exists without WAF.'
            noFirewallOrGateway          = 'No firewall or gateway found.'
        }
        $script:params = @{
            ControlName = 'GUARDRAIL 9'
            ItemName    = 'Network Security Tools'
            itsgcode    = 'SC-7'
            msgTable    = $script:msgTable
            ReportTime  = '2026-09-25'
        }
    }

    It 'Marks other subscriptions compliant when one subscription has a compliant setup' {
        Mock Get-AzSubscription -ModuleName Check-NetworkSecurityTools {
            @(
                [pscustomobject]@{ Id = 'sub-1'; Name = 'Subscription One'; State = 'Enabled' },
                [pscustomobject]@{ Id = 'sub-2'; Name = 'Subscription Two'; State = 'Enabled' }
            )
        }
        Mock Get-SubscriptionNetworkSecurityStatus -ModuleName Check-NetworkSecurityTools -ParameterFilter { $Subscription.Id -eq 'sub-1' } {
            @{ HasFirewall = $true; HasAppGateway = $false; HasWAFEnabled = $false; FirewallType = 'Azure Firewall' }
        }
        Mock Get-SubscriptionNetworkSecurityStatus -ModuleName Check-NetworkSecurityTools -ParameterFilter { $Subscription.Id -eq 'sub-2' } {
            @{ HasFirewall = $false; HasAppGateway = $false; HasWAFEnabled = $false; FirewallType = $null }
        }

        $result = Check-NetworkSecurityTools @script:params

        ($result.ComplianceResults | Where-Object SubscriptionName -eq 'Subscription One')[0].ComplianceStatus | Should -BeTrue
        ($result.ComplianceResults | Where-Object SubscriptionName -eq 'Subscription Two')[0].Comments | Should -Be 'Compliant because another subscription provides the control.'
    }
}
