BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Add-ProfileInformation { param($Result) return $Result }
    function global:Get-AzMarketplacePrivateStore { }

    Import-Module (Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 12 CONFIGURATION OF CLOUD MARKETPLACES\Audit\Check-PrivateMarketPlace.psm1') -Force
}

AfterAll {
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-AzMarketplacePrivateStore -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-PrivateMarketPlaceCreation' {
    BeforeAll {
        $script:msgTable = @{
            mktPlaceNotCreated        = 'Private marketplace not created.'
            enableMktPlace            = 'Enable private marketplace.'
            mktPlaceCreatedEnabled    = 'Private marketplace enabled'
            mktPlaceCreatedNotEnabled = 'Private marketplace created but disabled.'
            mktPlaceCreation          = 'Private Marketplace'
        }
        $script:params = @{
            ControlName = 'GUARDRAIL 12'
            itsgcode    = 'CM-8'
            msgTable    = $script:msgTable
            ReportTime  = '2026-09-25'
        }
    }

    It 'Returns non-compliant when no private store exists' {
        Mock Get-AzMarketplacePrivateStore -ModuleName Check-PrivateMarketPlace { $null }

        $result = Check-PrivateMarketPlaceCreation @script:params

        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'Private marketplace not created.'
    }

    It 'Returns compliant when the private store is enabled' {
        Mock Get-AzMarketplacePrivateStore -ModuleName Check-PrivateMarketPlace { [pscustomobject]@{ Availability = 'enabled'; PrivateStoreId = 'store-1' } }

        $result = Check-PrivateMarketPlaceCreation @script:params

        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'Private marketplace enabled - store-1'
    }
}
