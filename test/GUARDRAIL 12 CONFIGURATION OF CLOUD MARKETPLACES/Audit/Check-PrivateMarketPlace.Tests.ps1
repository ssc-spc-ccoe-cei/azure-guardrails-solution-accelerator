BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    . (Join-Path $PSScriptRoot '..\..\UnitTestHelpers.ps1')
    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 12 CONFIGURATION OF CLOUD MARKETPLACES\Audit\Check-PrivateMarketPlace.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Reset-UnitTestHelpers
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-PrivateMarketPlaceCreation' {
    It 'returns compliant when the private store is enabled' {
        Mock Get-AzMarketplacePrivateStore -ModuleName Check-PrivateMarketPlace {
            [PSCustomObject]@{ Availability = 'enabled'; PrivateStoreId = 'store-1' }
        }

        $result = Check-PrivateMarketPlaceCreation -ControlName 'GUARDRAIL 12' -itsgcode 'SA-9' `
            -msgTable @{ mktPlaceCreatedEnabled = 'Enabled'; mktPlaceCreation = 'Private marketplace' } `
            -ReportTime '2026-10-30'

        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'Enabled - store-1'
    }

    It 'returns non-compliant when a private store exists but is disabled' {
        Mock Get-AzMarketplacePrivateStore -ModuleName Check-PrivateMarketPlace {
            [PSCustomObject]@{ Availability = 'disabled'; PrivateStoreId = 'store-1' }
        }

        $result = Check-PrivateMarketPlaceCreation -ControlName 'GUARDRAIL 12' -itsgcode 'SA-9' `
            -msgTable @{ mktPlaceCreatedNotEnabled = 'Store is disabled'; enableMktPlace = 'Enable store'; mktPlaceCreation = 'Private marketplace' } `
            -ReportTime '2026-10-30'

        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'Store is disabled'
        $result.ComplianceResults.MitigationCommands | Should -Be 'Enable store'
    }
}
