BeforeAll {
    # Define stubs for external functions
    function global:Invoke-GraphQueryEX { param($urlPath) }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) return $Result }

    # Import the module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 1 PROTECT USER ACCOUNTS AND IDENTITIES\Audit\Get-AzureADLicenseType.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Item Function:\Invoke-GraphQueryEX -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
}

Describe 'Get-ADLicenseType' {

    BeforeAll {
        $script:msgTable = @{
            MSEntIDLicenseTypeFound    = 'Found correct license type'
            MSEntIDLicenseTypeNotFound = 'Required Microsoft Entra ID license type not found'
        }
        $script:commonParams = @{
            ControlName = 'GUARDRAIL 1'
            ItemName    = 'License Type'
            itsgcode    = 'AC-2'
            msgTable    = $script:msgTable
            ReportTime  = (Get-Date -Format 'yyyy-MM-dd')
        }
    }

    Context 'When AAD_PREMIUM_P2 license exists' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Get-AzureADLicenseType {
                [PSCustomObject]@{
                    Content = [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                servicePlans = @(
                                    [PSCustomObject]@{ ServicePlanName = 'EXCHANGE_S_ENTERPRISE' },
                                    [PSCustomObject]@{ ServicePlanName = 'AAD_PREMIUM_P2' },
                                    [PSCustomObject]@{ ServicePlanName = 'INTUNE_A' }
                                )
                            }
                        )
                    }
                }
            }
        }

        It 'Returns compliant' {
            $result = Get-ADLicenseType @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        }

        It 'Sets ADLicenseType to AAD_PREMIUM_P2' {
            $result = Get-ADLicenseType @commonParams
            $result.ComplianceResults.ADLicenseType | Should -Be 'AAD_PREMIUM_P2'
        }

        It 'Returns correct comments' {
            $result = Get-ADLicenseType @commonParams
            $result.ComplianceResults.Comments | Should -Be $script:msgTable.MSEntIDLicenseTypeFound
        }
    }

    Context 'When AAD_PREMIUM_P2 license does not exist' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Get-AzureADLicenseType {
                [PSCustomObject]@{
                    Content = [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                servicePlans = @(
                                    [PSCustomObject]@{ ServicePlanName = 'EXCHANGE_S_ENTERPRISE' },
                                    [PSCustomObject]@{ ServicePlanName = 'AAD_PREMIUM_P1' }
                                )
                            }
                        )
                    }
                }
            }
        }

        It 'Returns non-compliant' {
            $result = Get-ADLicenseType @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        }

        It 'Sets ADLicenseType to N/A' {
            $result = Get-ADLicenseType @commonParams
            $result.ComplianceResults.ADLicenseType | Should -Be 'N/A'
        }

        It 'Returns correct comments' {
            $result = Get-ADLicenseType @commonParams
            $result.ComplianceResults.Comments | Should -Be $script:msgTable.MSEntIDLicenseTypeNotFound
        }
    }

    Context 'When no licenses exist at all' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Get-AzureADLicenseType {
                [PSCustomObject]@{
                    Content = [PSCustomObject]@{
                        value = @()
                    }
                }
            }
        }

        It 'Returns non-compliant' {
            $result = Get-ADLicenseType @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        }
    }

    Context 'When Graph API call fails' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Get-AzureADLicenseType { throw 'API Error' }
        }

        It 'Returns non-compliant with error' {
            $result = Get-ADLicenseType @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When multiple SKUs contain the license' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Get-AzureADLicenseType {
                [PSCustomObject]@{
                    Content = [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                servicePlans = @(
                                    [PSCustomObject]@{ ServicePlanName = 'EXCHANGE_S_ENTERPRISE' }
                                )
                            },
                            [PSCustomObject]@{
                                servicePlans = @(
                                    [PSCustomObject]@{ ServicePlanName = 'AAD_PREMIUM_P2' }
                                )
                            }
                        )
                    }
                }
            }
        }

        It 'Returns compliant when license found in any SKU' {
            $result = Get-ADLicenseType @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        }
    }

    Context 'When EnableMultiCloudProfiles is set' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Get-AzureADLicenseType {
                [PSCustomObject]@{
                    Content = [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                servicePlans = @(
                                    [PSCustomObject]@{ ServicePlanName = 'AAD_PREMIUM_P2' }
                                )
                            }
                        )
                    }
                }
            }
            Mock Add-ProfileInformation -ModuleName Get-AzureADLicenseType { param($Result) return $Result }
        }

        It 'Calls Add-ProfileInformation' {
            $params = $script:commonParams.Clone()
            $result = Get-ADLicenseType @params -EnableMultiCloudProfiles -CloudUsageProfiles '3' -ModuleProfiles '1,2,3'
            Should -Invoke Add-ProfileInformation -ModuleName Get-AzureADLicenseType -Times 1
        }
    }

    Context 'Output structure' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Get-AzureADLicenseType {
                [PSCustomObject]@{
                    Content = [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                servicePlans = @(
                                    [PSCustomObject]@{ ServicePlanName = 'AAD_PREMIUM_P2' }
                                )
                            }
                        )
                    }
                }
            }
        }

        It 'Returns moduleOutput with ComplianceResults and Errors properties' {
            $result = Get-ADLicenseType @commonParams
            $result.PSObject.Properties.Name | Should -Contain 'ComplianceResults'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
        }

        It 'ComplianceResults has expected fields' {
            $result = Get-ADLicenseType @commonParams
            $cr = $result.ComplianceResults
            $cr.PSObject.Properties.Name | Should -Contain 'ComplianceStatus'
            $cr.PSObject.Properties.Name | Should -Contain 'ControlName'
            $cr.PSObject.Properties.Name | Should -Contain 'ADLicenseType'
            $cr.PSObject.Properties.Name | Should -Contain 'ItemName'
            $cr.PSObject.Properties.Name | Should -Contain 'ReportTime'
            $cr.PSObject.Properties.Name | Should -Contain 'itsgcode'
            $cr.PSObject.Properties.Name | Should -Contain 'Comments'
        }
    }
}
