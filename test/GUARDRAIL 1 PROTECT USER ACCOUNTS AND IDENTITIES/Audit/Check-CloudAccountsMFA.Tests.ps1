BeforeAll {
    # Define stubs for external functions
    function global:Invoke-GraphQueryEX { param($urlPath) }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) return $Result }

    # Import the module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 1 PROTECT USER ACCOUNTS AND IDENTITIES\Audit\Check-CloudAccountsMFA.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Item Function:\Invoke-GraphQueryEX -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
}

Describe 'Check-CloudAccountsMFA' {

    BeforeAll {
        $script:msgTable = @{
            isCompliant             = 'Compliant.'
            isNotCompliant          = 'Non-compliant.'
            mfaRequiredForAllUsers  = 'MFA required for all users by Conditional Access Policy.'
            noMFAPolicyForAllUsers  = 'No MFA policy found for all users.'
        }
        $script:commonParams = @{
            ControlName = 'GUARDRAIL 1'
            ItemName    = 'Cloud Accounts MFA'
            itsgcode    = 'AC-2'
            msgTable    = $script:msgTable
            ReportTime  = (Get-Date -Format 'yyyy-MM-dd')
        }
    }

    Context 'When a valid CA policy requiring MFA for all users exists' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-CloudAccountsMFA {
                [PSCustomObject]@{
                    Content = [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                state = 'enabled'
                                conditions = [PSCustomObject]@{
                                    users = [PSCustomObject]@{ includeUsers = @('All') }
                                    applications = [PSCustomObject]@{ includeApplications = @('All') }
                                    clientAppTypes = @('all')
                                    userRiskLevels = @()
                                    signInRiskLevels = @()
                                    platforms = $null
                                    locations = $null
                                    devices = $null
                                    clientApplications = $null
                                }
                                grantControls = [PSCustomObject]@{ builtInControls = @('mfa') }
                            }
                        )
                    }
                }
            }
        }

        It 'Returns compliant' {
            $result = Check-CloudAccountsMFA @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -Be $script:msgTable.mfaRequiredForAllUsers
        }

        It 'Returns the correct ControlName' {
            $result = Check-CloudAccountsMFA @commonParams
            $result.ComplianceResults.ControlName | Should -Be 'GUARDRAIL 1'
        }
    }

    Context 'When CA policy targets MicrosoftAdminPortals instead of All' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-CloudAccountsMFA {
                [PSCustomObject]@{
                    Content = [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                state = 'enabled'
                                conditions = [PSCustomObject]@{
                                    users = [PSCustomObject]@{ includeUsers = @('All') }
                                    applications = [PSCustomObject]@{ includeApplications = @('MicrosoftAdminPortals') }
                                    clientAppTypes = @('all')
                                    userRiskLevels = @()
                                    signInRiskLevels = @()
                                    platforms = $null
                                    locations = $null
                                    devices = $null
                                    clientApplications = $null
                                }
                                grantControls = [PSCustomObject]@{ builtInControls = @('mfa') }
                            }
                        )
                    }
                }
            }
        }

        It 'Returns compliant (MicrosoftAdminPortals is accepted)' {
            $result = Check-CloudAccountsMFA @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        }
    }

    Context 'When CA policy is disabled' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-CloudAccountsMFA {
                [PSCustomObject]@{
                    Content = [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                state = 'disabled'
                                conditions = [PSCustomObject]@{
                                    users = [PSCustomObject]@{ includeUsers = @('All') }
                                    applications = [PSCustomObject]@{ includeApplications = @('All') }
                                    clientAppTypes = @('all')
                                    userRiskLevels = @()
                                    signInRiskLevels = @()
                                    platforms = $null
                                    locations = $null
                                    devices = $null
                                    clientApplications = $null
                                }
                                grantControls = [PSCustomObject]@{ builtInControls = @('mfa') }
                            }
                        )
                    }
                }
            }
        }

        It 'Returns non-compliant' {
            $result = Check-CloudAccountsMFA @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -Be $script:msgTable.noMFAPolicyForAllUsers
        }
    }

    Context 'When no CA policies exist' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-CloudAccountsMFA {
                [PSCustomObject]@{
                    Content = [PSCustomObject]@{
                        value = @()
                    }
                }
            }
        }

        It 'Returns non-compliant' {
            $result = Check-CloudAccountsMFA @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        }
    }

    Context 'When CA policy does not include MFA in grant controls' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-CloudAccountsMFA {
                [PSCustomObject]@{
                    Content = [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                state = 'enabled'
                                conditions = [PSCustomObject]@{
                                    users = [PSCustomObject]@{ includeUsers = @('All') }
                                    applications = [PSCustomObject]@{ includeApplications = @('All') }
                                    clientAppTypes = @('all')
                                    userRiskLevels = @()
                                    signInRiskLevels = @()
                                    platforms = $null
                                    locations = $null
                                    devices = $null
                                    clientApplications = $null
                                }
                                grantControls = [PSCustomObject]@{ builtInControls = @('block') }
                            }
                        )
                    }
                }
            }
        }

        It 'Returns non-compliant' {
            $result = Check-CloudAccountsMFA @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        }
    }

    Context 'When CA policy has individual clientAppTypes instead of all' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-CloudAccountsMFA {
                [PSCustomObject]@{
                    Content = [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                state = 'enabled'
                                conditions = [PSCustomObject]@{
                                    users = [PSCustomObject]@{ includeUsers = @('All') }
                                    applications = [PSCustomObject]@{ includeApplications = @('All') }
                                    clientAppTypes = @('browser', 'mobileAppsAndDesktopClients', 'exchangeActiveSync', 'other')
                                    userRiskLevels = @()
                                    signInRiskLevels = @()
                                    platforms = $null
                                    locations = $null
                                    devices = $null
                                    clientApplications = $null
                                }
                                grantControls = [PSCustomObject]@{ builtInControls = @('mfa') }
                            }
                        )
                    }
                }
            }
        }

        It 'Returns compliant when all individual client app types present' {
            $result = Check-CloudAccountsMFA @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        }
    }

    Context 'When CA policy has non-empty userRiskLevels (scoped policy)' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-CloudAccountsMFA {
                [PSCustomObject]@{
                    Content = [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                state = 'enabled'
                                conditions = [PSCustomObject]@{
                                    users = [PSCustomObject]@{ includeUsers = @('All') }
                                    applications = [PSCustomObject]@{ includeApplications = @('All') }
                                    clientAppTypes = @('all')
                                    userRiskLevels = @('high')
                                    signInRiskLevels = @()
                                    platforms = $null
                                    locations = $null
                                    devices = $null
                                    clientApplications = $null
                                }
                                grantControls = [PSCustomObject]@{ builtInControls = @('mfa') }
                            }
                        )
                    }
                }
            }
        }

        It 'Returns non-compliant because policy is scoped by risk level' {
            $result = Check-CloudAccountsMFA @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        }
    }

    Context 'When Graph API call fails' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-CloudAccountsMFA { throw 'Forbidden' }
        }

        It 'Returns non-compliant with errors' {
            $result = Check-CloudAccountsMFA @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.Errors.Count | Should -BeGreaterThan 0
        }
    }
}
