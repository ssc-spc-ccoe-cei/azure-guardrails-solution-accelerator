BeforeAll {
    # Ensure Write-Error in source modules stays non-terminating (CI and VS Code set $ErrorActionPreference = 'Stop')
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    # Define stubs for external functions
    function global:Invoke-GraphQueryEX { param($urlPath) }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) return $Result }

    # Import the module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 2 MANAGE ACCESS\Audit\Check-OnlineAttackCountermeasures.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Item Function:\Invoke-GraphQueryEX -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-OnlineAttackCountermeasures' {

    BeforeAll {
        $script:msgTable = @{
            onlineAttackNonCompliantC1C2 = 'Lockout threshold is too high and the banned password list is insufficient.'
            onlineAttackNonCompliantC1   = 'Lockout threshold exceeds 10.'
            onlineAttackNonCompliantC2   = 'Banned password list does not meet requirements.'
            onlineAttackIsCompliant      = 'Online attack countermeasures are compliant.'
        }
        $script:commonParams = @{
            ControlName = 'GUARDRAIL 2'
            ItemName    = 'Online Attack Countermeasures'
            itsgcode    = 'AC-7'
            msgTable    = $script:msgTable
            ReportTime  = (Get-Date -Format 'yyyy-MM-dd')
        }
    }

    Context 'When password rule settings are fully compliant' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-OnlineAttackCountermeasures {
                [PSCustomObject]@{
                    Content = [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                displayName = 'Password Rule Settings'
                                values      = @(
                                    [PSCustomObject]@{ name = 'LockoutThreshold'; value = '10' },
                                    [PSCustomObject]@{ name = 'BannedPasswordList'; value = "password`tPassword!`tSummer2018`tWinter2024!" }
                                )
                            }
                        )
                    }
                }
            }
        }

        It 'Returns compliant' {
            $result = Check-OnlineAttackCountermeasures @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -Be $script:msgTable.onlineAttackIsCompliant
        }
    }

    Context 'When the lockout threshold is greater than 10' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-OnlineAttackCountermeasures {
                [PSCustomObject]@{
                    Content = [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                displayName = 'Password Rule Settings'
                                values      = @(
                                    [PSCustomObject]@{ name = 'LockoutThreshold'; value = '11' },
                                    [PSCustomObject]@{ name = 'BannedPasswordList'; value = "password`tPassword!`tSummer2018`tWinter2024!" }
                                )
                            }
                        )
                    }
                }
            }
        }

        It 'Returns non-compliant for the threshold condition' {
            $result = Check-OnlineAttackCountermeasures @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments.Trim() | Should -Be $script:msgTable.onlineAttackNonCompliantC1
        }
    }

    Context 'When the banned password list is missing' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-OnlineAttackCountermeasures {
                [PSCustomObject]@{
                    Content = [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                displayName = 'Password Rule Settings'
                                values      = @(
                                    [PSCustomObject]@{ name = 'LockoutThreshold'; value = '10' },
                                    [PSCustomObject]@{ name = 'BannedPasswordList'; value = $null }
                                )
                            }
                        )
                    }
                }
            }
        }

        It 'Returns non-compliant for the banned password condition' {
            $result = Check-OnlineAttackCountermeasures @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments.Trim() | Should -Be $script:msgTable.onlineAttackNonCompliantC2
        }
    }

    Context 'When Invoke-GraphQueryEX throws an exception' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-OnlineAttackCountermeasures { throw 'Graph unavailable' }
        }

        It 'Returns non-compliant and adds the error to the error list' {
            $result = Check-OnlineAttackCountermeasures @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.Errors.Count | Should -BeGreaterThan 0
            $result.Errors | Should -BeLike '*Failed to retrieve or process group settings*Graph unavailable*'
        }
    }

    Context 'When EnableMultiCloudProfiles is set' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-OnlineAttackCountermeasures {
                [PSCustomObject]@{
                    Content = [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                displayName = 'Password Rule Settings'
                                values      = @(
                                    [PSCustomObject]@{ name = 'LockoutThreshold'; value = '10' },
                                    [PSCustomObject]@{ name = 'BannedPasswordList'; value = "password`tPassword!`tSummer2018`tWinter2024!" }
                                )
                            }
                        )
                    }
                }
            }
            Mock Add-ProfileInformation -ModuleName Check-OnlineAttackCountermeasures { param($Result) return $Result }
        }

        It 'Calls Add-ProfileInformation' {
            $params = $script:commonParams.Clone()
            $result = Check-OnlineAttackCountermeasures @params -EnableMultiCloudProfiles -CloudUsageProfiles '3' -ModuleProfiles '1,2,3'
            Should -Invoke Add-ProfileInformation -ModuleName Check-OnlineAttackCountermeasures -Times 1
        }
    }
}
