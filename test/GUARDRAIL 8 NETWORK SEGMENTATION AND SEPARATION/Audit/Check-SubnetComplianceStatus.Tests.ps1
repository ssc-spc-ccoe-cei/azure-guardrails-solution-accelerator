BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    . (Join-Path $PSScriptRoot '..\..\UnitTestHelpers.ps1')
    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 8 NETWORK SEGMENTATION AND SEPARATION\Audit\Check-SubnetComplianceStatus.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Reset-UnitTestHelpers
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Get-SubnetComplianceInformation' {
    It 'reports NSG coverage for an included subnet and a missing NSG as non-compliant' {
        Mock Get-AzSubscription -ModuleName Check-SubnetComplianceStatus {
            @([PSCustomObject]@{ Id = 'sub-1'; Name = 'Subscription 1'; State = 'Enabled' })
        }
        Mock Select-AzSubscription -ModuleName Check-SubnetComplianceStatus {}
        Mock Get-AzVirtualNetwork -ModuleName Check-SubnetComplianceStatus {
            @([PSCustomObject]@{ Name = 'vnet-1'; Tag = @{} })
        }
        Mock Get-AzVirtualNetworkSubnetConfig -ModuleName Check-SubnetComplianceStatus {
            @(
                [PSCustomObject]@{ Name = 'with-nsg'; NetworkSecurityGroup = [PSCustomObject]@{ Id = '/nsg/nsg-1' }; RouteTable = $null }
                [PSCustomObject]@{ Name = 'without-nsg'; NetworkSecurityGroup = $null; RouteTable = $null }
            )
        }

        $result = Get-SubnetComplianceInformation -ControlName 'GUARDRAIL 8' `
            -itsgcodesegmentation 'SC-7' -itsgcodeseparation 'SC-7' -ExcludedSubnetsList '' `
            -ReservedSubnetList '' -msgTable @{ subnetCompliant = 'Compliant'; noNSG = 'No NSG'; networkSegmentation = 'Segmentation'; networkSeparation = 'Separation' } `
            -ReportTime '2026-10-30' -CBSSubscriptionName 'CBS'

        $segmentationResults = @($result.ComplianceResults | Where-Object ItemName -eq 'Segmentation')
        $segmentationResults.Count | Should -Be 2
        ($segmentationResults | Where-Object SubnetName -like '*with-nsg').ComplianceStatus | Should -BeTrue
        ($segmentationResults | Where-Object SubnetName -like '*without-nsg').ComplianceStatus | Should -BeFalse
    }

    It 'excludes subnets listed in the caller configuration' {
        Mock Get-AzSubscription -ModuleName Check-SubnetComplianceStatus {
            @([PSCustomObject]@{ Id = 'sub-1'; Name = 'Subscription 1'; State = 'Enabled' })
        }
        Mock Select-AzSubscription -ModuleName Check-SubnetComplianceStatus {}
        Mock Get-AzVirtualNetwork -ModuleName Check-SubnetComplianceStatus {
            @([PSCustomObject]@{ Name = 'vnet-1'; Tag = @{} })
        }
        Mock Get-AzVirtualNetworkSubnetConfig -ModuleName Check-SubnetComplianceStatus {
            @([PSCustomObject]@{ Name = 'reserved'; NetworkSecurityGroup = $null; RouteTable = $null })
        }

        $result = Get-SubnetComplianceInformation -ControlName 'GUARDRAIL 8' `
            -itsgcodesegmentation 'SC-7' -itsgcodeseparation 'SC-7' -ExcludedSubnetsList '' `
            -ReservedSubnetList 'reserved' -msgTable @{ subnetExcludedByReservedName = 'Excluded {0}'; networkSeparation = 'Separation' } `
            -ReportTime '2026-10-30' -CBSSubscriptionName 'CBS'

        $result.ComplianceResults.Count | Should -Be 1
        $result.ComplianceResults[0].ComplianceStatus | Should -BeTrue
        $result.ComplianceResults[0].Comments | Should -BeLike '*reserved*'
    }
}
