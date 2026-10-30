BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Set-SubscriptionNotEvaluatedStatus { param($Result, $SubscriptionName, $msgTable) $Result.Comments = "Skipped $SubscriptionName"; return $Result }
    function global:get-tagValue { param($tagKey, $object) return $null }
    function global:Get-EvaluationProfile { }

    Import-Module (Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 8 NETWORK SEGMENTATION AND SEPARATION\Audit\Check-SubnetComplianceStatus.psm1') -Force
}

AfterAll {
    Remove-Item Function:\Set-SubscriptionNotEvaluatedStatus -ErrorAction SilentlyContinue
    Remove-Item Function:\get-tagValue -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-EvaluationProfile -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Update-SubnetObjectWithProfile' {
    It 'Adds the evaluation profile when the subscription should be evaluated' {
        $subnet = [pscustomobject]@{ ComplianceStatus = $true; Comments = 'ok' }
        $errors = [System.Collections.ArrayList]::new()

        Update-SubnetObjectWithProfile -SubnetObject $subnet -EvalResult ([pscustomobject]@{ ShouldEvaluate = $true; Profile = 3 }) -ErrorList $errors

        $subnet.Profile | Should -Be 3
        $errors.Count | Should -Be 0
    }
}

Describe 'Get-SubnetComplianceInformation' {
    BeforeAll {
        $script:msgTable = @{
            noSubnets                   = 'No subnets'
            networkSegmentation         = 'Network Segmentation'
            networkSeparation           = 'Network Separation'
            subnetCompliant             = 'Subnet compliant'
            noNSG                       = 'Subnet missing NSG'
            routeNVA                    = 'Route does not send 0.0.0.0/0 to an NVA'
            subnetExcludedByReservedName = '{0} excluded by reserved list {1}'
            subnetExcludedByTag         = '{0} excluded from {1} by tag {2}'
            subnetExcludedByVNET        = '{0}\{1} excluded by VNET tag {2}'
        }
        $script:params = @{
            ControlName          = 'GUARDRAIL 8'
            itsgcodesegmentation = 'SC-7'
            itsgcodeseparation   = 'SC-7'
            ExcludedSubnetsList  = ''
            ReservedSubnetList   = 'GatewaySubnet'
            msgTable             = $script:msgTable
            ReportTime           = '2026-09-25'
            CBSSubscriptionName  = 'n/a'
        }
    }

    It 'Returns subscription-level compliant rows when no VNets are present' {
        Mock Get-AzSubscription -ModuleName Check-SubnetComplianceStatus {
            @([pscustomobject]@{ Id = 'sub-1'; Name = 'Subscription One'; State = 'Enabled' })
        }
        Mock Select-AzSubscription -ModuleName Check-SubnetComplianceStatus { }
        Mock Get-AzVirtualNetwork -ModuleName Check-SubnetComplianceStatus { @() }

        $result = Get-SubnetComplianceInformation @script:params

        $result.ComplianceResults | Should -HaveCount 2
        ($result.ComplianceResults | Select-Object -ExpandProperty ComplianceStatus | Select-Object -Unique) | Should -BeTrue
    }

    It 'Marks a subnet non-compliant when it has no NSG' {
        Mock Get-AzSubscription -ModuleName Check-SubnetComplianceStatus {
            @([pscustomobject]@{ Id = 'sub-1'; Name = 'Subscription One'; State = 'Enabled' })
        }
        Mock Select-AzSubscription -ModuleName Check-SubnetComplianceStatus { }
        Mock Get-AzVirtualNetwork -ModuleName Check-SubnetComplianceStatus {
            @([pscustomobject]@{ Name = 'vnet1'; Tag = @{} })
        }
        Mock Get-AzVirtualNetworkSubnetConfig -ModuleName Check-SubnetComplianceStatus {
            @([pscustomobject]@{ Name = 'subnet1'; NetworkSecurityGroup = $null; RouteTable = $null })
        }

        $result = Get-SubnetComplianceInformation @script:params

        ($result.ComplianceResults | Where-Object ItemName -eq 'Network Segmentation')[0].ComplianceStatus | Should -BeFalse
        ($result.ComplianceResults | Where-Object ItemName -eq 'Network Separation')[0].ComplianceStatus | Should -BeFalse
    }
}
