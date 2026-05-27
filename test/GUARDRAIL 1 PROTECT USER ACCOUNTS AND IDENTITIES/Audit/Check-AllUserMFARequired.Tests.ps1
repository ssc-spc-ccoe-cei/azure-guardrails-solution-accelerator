BeforeAll {
    # Ensure Write-Error in source modules stays non-terminating (CI and VS Code set $ErrorActionPreference = 'Stop')
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    # Define stubs for external functions
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) return $Result }

    # Import the module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 1 PROTECT USER ACCOUNTS AND IDENTITIES\Audit\Check-AllUserMFARequired.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-AllUserMFARequired' {

    BeforeAll {
        $script:msgTable = @{
            isCompliant    = 'Compliant.'
            isNotCompliant = 'Non-compliant.'
        }
        $script:commonParams = @{
            ControlName  = 'GUARDRAIL 1'
            ItemName     = 'All User MFA'
            itsgcode     = 'AC-2'
            msgTable     = $script:msgTable
            ReportTime   = (Get-Date -Format 'yyyy-MM-dd')
            WorkSpaceID  = '00000000-0000-0000-0000-000000000000'
        }
    }

    Context 'When KQL function returns compliance result on first attempt' {

        BeforeAll {
            Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired {
                [PSCustomObject]@{
                    Results = @(
                        [PSCustomObject]@{
                            ComplianceStatus = $true
                            ControlName      = 'GUARDRAIL 1'
                            Comments         = 'All users have MFA'
                            ItemName         = 'All User MFA'
                            ReportTime       = (Get-Date -Format 'yyyy-MM-dd')
                            itsgcode         = 'AC-2'
                        }
                    )
                }
            }
        }

        It 'Returns the compliance result from KQL' {
            $result = Check-AllUserMFARequired @commonParams
            $result.ComplianceResults | Should -Not -BeNullOrEmpty
            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        }

        It 'Has no errors' {
            $result = Check-AllUserMFARequired @commonParams
            $result.Errors.Count | Should -Be 0
        }
    }

    Context 'When KQL function returns no results (empty)' {

        BeforeAll {
            Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired {
                [PSCustomObject]@{
                    Results = @()
                }
            }
            Mock Start-Sleep -ModuleName Check-AllUserMFARequired { }
        }

        It 'Reports an error after retries' {
            $result = Check-AllUserMFARequired @commonParams
            $result.Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When KQL function throws on all attempts' {

        BeforeAll {
            Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired { throw 'Query failed' }
            Mock Start-Sleep -ModuleName Check-AllUserMFARequired { }
        }

        It 'Returns errors for failed KQL call' {
            $result = Check-AllUserMFARequired @commonParams
            $result.Errors.Count | Should -BeGreaterThan 0
            $result.Errors[0] | Should -BeLike '*gr_mfa_evaluation*'
        }
    }

    Context 'When EnableMultiCloudProfiles is set and KQL returns results' {

        BeforeAll {
            Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired {
                [PSCustomObject]@{
                    Results = @(
                        [PSCustomObject]@{
                            ComplianceStatus = $true
                            ControlName      = 'GUARDRAIL 1'
                            Comments         = 'MFA OK'
                            ItemName         = 'All User MFA'
                            ReportTime       = (Get-Date -Format 'yyyy-MM-dd')
                            itsgcode         = 'AC-2'
                        }
                    )
                }
            }
            Mock Add-ProfileInformation -ModuleName Check-AllUserMFARequired {
                param($Result) return $Result
            }
        }

        It 'Calls Add-ProfileInformation when profile flag is enabled' {
            $params = $script:commonParams.Clone()
            $result = Check-AllUserMFARequired @params -EnableMultiCloudProfiles -CloudUsageProfiles '3' -ModuleProfiles '1,2,3'
            Should -Invoke Add-ProfileInformation -ModuleName Check-AllUserMFARequired -Times 1
        }
    }
}
