BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Get-AzContext { }
    function global:Get-AzRoleAssignment { }
    function global:Get-AzADServicePrincipal { }
    function global:Invoke-GraphQueryEX { }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) return $Result }

    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 4 ENTERPRISE MONITORING ACCOUNTS\Audit\Check-ServicePrincipal.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Item Function:\Get-AzContext -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-AzRoleAssignment -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-AzADServicePrincipal -ErrorAction SilentlyContinue
    Remove-Item Function:\Invoke-GraphQueryEX -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Verify-Roles' {
    BeforeAll {
        $script:msgTable = @{
            ServicePrincipalNameHasNoReaderRole              = 'Reader role missing. '
            ServicePrincipalNameHasReaderRole                = 'Reader role assigned. '
            ServicePrincipalNameHasNoMarketPlaceAdminRole    = 'Marketplace admin role missing.'
            ServicePrincipalNameHasMarketPlaceAdminRole      = 'Marketplace admin role assigned.'
        }
    }

    Context 'When both required roles are assigned' {
        BeforeAll {
            Mock Get-AzContext -ModuleName Check-ServicePrincipal {
                [pscustomobject]@{
                    Tenant = [pscustomobject]@{ Id = 'tenant-001' }
                }
            }
            Mock Get-AzRoleAssignment -ModuleName Check-ServicePrincipal {
                param($Scope)
                if ($Scope -eq '/providers/Microsoft.Marketplace') {
                    @([pscustomobject]@{
                        ObjectId           = 'spn-001'
                        RoleDefinitionName = 'Marketplace Admin'
                        Scope              = '/providers/Microsoft.Marketplace'
                    })
                } else {
                    @([pscustomobject]@{
                        ObjectId           = 'spn-001'
                        RoleDefinitionName = 'Cost Management Reader'
                        Scope              = '/providers/Microsoft.Management/managementGroups/tenant-001'
                    })
                }
            }
        }

        It 'Marks the service principal compliant' {
            $servicePrincipal = [pscustomobject]@{
                ServicePrincipalNameID = 'spn-001'
                ComplianceStatus       = $false
                ComplianceComments     = ''
            }

            Verify-Roles -ServicePrincipal $servicePrincipal -msgTable $script:msgTable

            $servicePrincipal.ComplianceStatus | Should -BeTrue
            $servicePrincipal.ComplianceComments | Should -BeLike '*Reader role assigned*'
            $servicePrincipal.ComplianceComments | Should -BeLike '*Marketplace admin role assigned*'
        }
    }

    Context 'When one of the required roles is missing' {
        BeforeAll {
            Mock Get-AzContext -ModuleName Check-ServicePrincipal {
                [pscustomobject]@{
                    Tenant = [pscustomobject]@{ Id = 'tenant-001' }
                }
            }
            Mock Get-AzRoleAssignment -ModuleName Check-ServicePrincipal {
                param($Scope)
                if ($Scope -eq '/providers/Microsoft.Marketplace') {
                    @()
                } else {
                    @([pscustomobject]@{
                        ObjectId           = 'spn-001'
                        RoleDefinitionName = 'Cost Management Reader'
                        Scope              = '/providers/Microsoft.Management/managementGroups/tenant-001'
                    })
                }
            }
        }

        It 'Marks the service principal non-compliant' {
            $servicePrincipal = [pscustomobject]@{
                ServicePrincipalNameID = 'spn-001'
                ComplianceStatus       = $false
                ComplianceComments     = ''
            }

            Verify-Roles -ServicePrincipal $servicePrincipal -msgTable $script:msgTable

            $servicePrincipal.ComplianceStatus | Should -BeFalse
            $servicePrincipal.ComplianceComments | Should -BeLike '*Marketplace admin role missing*'
        }
    }
}

Describe 'Check-DepartmentServicePrincipalName' {
    BeforeAll {
        $script:msgTable = @{
            NoSPN                                  = 'Service principal was not found.'
            SPNExist                               = 'Service principal exists.'
            ServicePrincipalNameHasNoReaderRole    = 'Reader role missing. '
            ServicePrincipalNameHasReaderRole      = 'Reader role assigned. '
            ServicePrincipalNameHasNoMarketPlaceAdminRole = 'Marketplace admin role missing.'
            ServicePrincipalNameHasMarketPlaceAdminRole   = 'Marketplace admin role assigned.'
        }
        $script:commonParams = @{
            SPNID       = '11111111-1111-1111-1111-111111111111'
            ControlName = 'GUARDRAIL 4'
            ItemName    = 'Department Service Principal'
            itsgcode    = 'AC-4'
            msgTable    = $script:msgTable
            ReportTime  = '2026-09-25'
        }
    }

    Context 'When the service principal cannot be found' {
        BeforeAll {
            Mock Get-AzADServicePrincipal -ModuleName Check-ServicePrincipal { $null }
        }

        It 'Returns non-compliant with the missing SPN message' {
            $result = Check-DepartmentServicePrincipalName @script:commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -Be $script:msgTable.NoSPN
        }
    }

    Context 'When the service principal exists and Graph returns success' {
        BeforeAll {
            Mock Get-AzADServicePrincipal -ModuleName Check-ServicePrincipal {
                [pscustomobject]@{
                    Id    = 'spn-001'
                    AppId = 'app-001'
                }
            }
            Mock Invoke-GraphQueryEX -ModuleName Check-ServicePrincipal {
                [pscustomobject]@{
                    StatusCode = 200
                }
            }
            Mock Verify-Roles -ModuleName Check-ServicePrincipal {
                param($ServicePrincipal, $msgTable)
                $ServicePrincipal.ComplianceStatus = $true
                $ServicePrincipal.ComplianceComments = 'Roles verified.'
            }
        }

        It 'Returns the verified role status' {
            $result = Check-DepartmentServicePrincipalName @script:commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -Be 'Roles verified.'
        }
    }

    Context 'When multi-cloud profiles are enabled' {
        BeforeAll {
            Mock Get-AzADServicePrincipal -ModuleName Check-ServicePrincipal {
                [pscustomobject]@{
                    Id    = 'spn-001'
                    AppId = 'app-001'
                }
            }
            Mock Invoke-GraphQueryEX -ModuleName Check-ServicePrincipal {
                [pscustomobject]@{
                    StatusCode = 200
                }
            }
            Mock Verify-Roles -ModuleName Check-ServicePrincipal {
                param($ServicePrincipal, $msgTable)
                $ServicePrincipal.ComplianceStatus = $true
                $ServicePrincipal.ComplianceComments = 'Roles verified.'
            }
            Mock Add-ProfileInformation -ModuleName Check-ServicePrincipal { param($Result) return $Result }
        }

        It 'Calls Add-ProfileInformation' {
            $null = Check-DepartmentServicePrincipalName @script:commonParams -EnableMultiCloudProfiles -CloudUsageProfiles '3' -ModuleProfiles '1,2,3'

            Should -Invoke Add-ProfileInformation -ModuleName Check-ServicePrincipal -Times 1
        }
    }
}
