BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Set-SubscriptionNotEvaluatedStatus { param($Result) return $Result }
    function global:Get-EvaluationProfile { }

    Import-Module (Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 9 NETWORK SECURITY SERVICES\Audit\Check-NetworkWatcherEnabled.psm1') -Force
}

AfterAll {
    Remove-Item Function:\Set-SubscriptionNotEvaluatedStatus -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-EvaluationProfile -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Add-ProfileEvaluationResult' {
    It 'Adds the profile to an evaluated region object' {
        $region = [pscustomobject]@{ ComplianceStatus = $true; Comments = 'ok' }
        $errors = [System.Collections.ArrayList]::new()

        Add-ProfileEvaluationResult -RegionObject $region -evalResult ([pscustomobject]@{ ShouldEvaluate = $true; Profile = 3 }) -ErrorList $errors

        $region.Profile | Should -Be 3
        $errors.Count | Should -Be 0
    }
}

Describe 'Get-NetworkWatcherStatus' {
    BeforeAll {
        $script:msgTable = @{
            networkWatcherConfig          = 'Network Watcher'
            networkWatcherEnabled         = 'Enabled in {0}'
            networkWatcherNotEnabled      = 'Not enabled in {0}'
            networkWatcherConfigNoRegions = 'No in-scope VNets'
        }
        $script:params = @{
            ControlName         = 'GUARDRAIL 9'
            itsgcode            = 'SC-7'
            msgTable            = $script:msgTable
            ReportTime          = '2026-09-25'
            CBSSubscriptionName = 'n/a'
        }
    }

    It 'Returns compliant when a watcher exists for the included VNet region' {
        Mock Get-AzSubscription -ModuleName Check-NetworkWatcherEnabled {
            @([pscustomobject]@{ Id = 'sub-1'; Name = 'Subscription One'; State = 'Enabled' })
        }
        Mock Select-AzSubscription -ModuleName Check-NetworkWatcherEnabled { }
        Mock Get-AzVirtualNetwork -ModuleName Check-NetworkWatcherEnabled {
            @([pscustomobject]@{ Name = 'vnet1'; Location = 'canadacentral'; Tag = @{} })
        }
        Mock Get-AzNetworkWatcher -ModuleName Check-NetworkWatcherEnabled {
            [pscustomobject]@{ Name = 'NetworkWatcher_canadacentral' }
        }

        $result = Get-NetworkWatcherStatus @script:params

        $result.ComplianceResults[0].ComplianceStatus | Should -BeTrue
        $result.ComplianceResults[0].Comments | Should -Be 'Enabled in canadacentral'
    }

    It 'Returns a no-regions comment when all VNets are excluded' {
        Mock Get-AzSubscription -ModuleName Check-NetworkWatcherEnabled {
            @([pscustomobject]@{ Id = 'sub-1'; Name = 'Subscription One'; State = 'Enabled' })
        }
        Mock Select-AzSubscription -ModuleName Check-NetworkWatcherEnabled { }
        Mock Get-AzVirtualNetwork -ModuleName Check-NetworkWatcherEnabled {
            @([pscustomobject]@{ Name = 'vnet1'; Location = 'canadacentral'; Tag = @{ 'GR9-ExcludeVNetFromCompliance' = 'true' } })
        }

        $result = Get-NetworkWatcherStatus @script:params

        $result.ComplianceResults[0].Comments | Should -Be 'No in-scope VNets'
    }
}
