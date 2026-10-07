BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Invoke-GraphQueryEX { }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) return $Result }

    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 3 SECURE ENDPOINTS\Audit\Check-AdminAccess.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Item Function:\Invoke-GraphQueryEX -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Get-AdminAccess' {
    BeforeAll {
        $script:msgTable = @{
            hasRequiredPolicies       = 'Required admin policies exist.'
            noLocationFilterPolicies  = 'Location filter policies are missing.'
            noDeviceFilterPolicies    = 'Device filter policies are missing.'
            noCompliantPoliciesAdmin  = 'No compliant admin policies exist.'
        }
        $script:commonParams = @{
            ControlName = 'GUARDRAIL 3'
            ItemName    = 'Admin Access'
            itsgcode    = 'AC-3'
            msgTable    = $script:msgTable
            ReportTime  = '2026-09-25'
        }
        $script:adminRoleIds = @(
            '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3',
            '62e90394-69f5-4237-9190-012177145e10',
            '194ae4cb-b126-40b2-bd5b-6091b380977d',
            'fe930be7-5e62-47db-91af-98c3a49a38b1'
        )
    }

    Context 'When both device and location policies exist for admin roles' {
        BeforeAll {
            $policies = @(
                [pscustomobject]@{
                    state = 'enabled'
                    conditions = [pscustomobject]@{
                        devices = [pscustomobject]@{
                            deviceFilter = [pscustomobject]@{ mode = 'include' }
                        }
                        applications = [pscustomobject]@{
                            includeApplications = @('All')
                        }
                        locations = [pscustomobject]@{
                            includeLocations = $null
                        }
                        users = [pscustomobject]@{
                            includeRoles = @($script:adminRoleIds[0])
                        }
                    }
                },
                [pscustomobject]@{
                    state = 'enabled'
                    conditions = [pscustomobject]@{
                        devices = [pscustomobject]@{
                            deviceFilter = $null
                        }
                        applications = [pscustomobject]@{
                            includeApplications = @()
                        }
                        locations = [pscustomobject]@{
                            includeLocations = @('AllTrusted')
                        }
                        users = [pscustomobject]@{
                            includeRoles = @($script:adminRoleIds[1])
                        }
                    }
                }
            )

            Mock Invoke-GraphQueryEX -ModuleName Check-AdminAccess {
                [pscustomobject]@{
                    Content = [pscustomobject]@{
                        value = $policies
                    }
                }
            }
        }

        It 'Returns compliant results' {
            $result = Get-AdminAccess @script:commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -Be $script:msgTable.hasRequiredPolicies
            $result.Errors.Count | Should -Be 0
        }
    }

    Context 'When only device filter policies exist' {
        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-AdminAccess {
                [pscustomobject]@{
                    Content = [pscustomobject]@{
                        value = @(
                            [pscustomobject]@{
                                state = 'enabled'
                                conditions = [pscustomobject]@{
                                    devices = [pscustomobject]@{
                                        deviceFilter = [pscustomobject]@{ mode = 'include' }
                                    }
                                    applications = [pscustomobject]@{
                                        includeApplications = @('All')
                                    }
                                    locations = [pscustomobject]@{
                                        includeLocations = $null
                                    }
                                    users = [pscustomobject]@{
                                        includeRoles = @($script:adminRoleIds[2])
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }

        It 'Returns non-compliant with the missing location filter message' {
            $result = Get-AdminAccess @script:commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -Be $script:msgTable.noLocationFilterPolicies
        }
    }

    Context 'When the Graph query fails' {
        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-AdminAccess { throw 'Graph failure' }
        }

        It 'Returns an error and the default non-compliant comment' {
            $result = Get-AdminAccess @script:commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -Be $script:msgTable.noCompliantPoliciesAdmin
            $result.Errors.Count | Should -Be 1
            ([string]$result.Errors) | Should -BeLike '*Failed to call Microsoft Graph REST API*'
        }
    }

    Context 'When multi-cloud profiles are enabled' {
        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-AdminAccess {
                [pscustomobject]@{
                    Content = [pscustomobject]@{
                        value = @()
                    }
                }
            }
            Mock Add-ProfileInformation -ModuleName Check-AdminAccess { param($Result) return $Result }
        }

        It 'Calls Add-ProfileInformation' {
            $null = Get-AdminAccess @script:commonParams -EnableMultiCloudProfiles -CloudUsageProfiles '3' -ModuleProfiles '1,2,3'

            Should -Invoke Add-ProfileInformation -ModuleName Check-AdminAccess -Times 1
        }
    }
}
