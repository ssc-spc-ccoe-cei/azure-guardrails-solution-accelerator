BeforeAll {
    # Ensure Write-Error in source modules stays non-terminating (CI and VS Code set $ErrorActionPreference = 'Stop')
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    # Define stubs for external functions
    function global:Invoke-GraphQueryEX { param($urlPath) }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) return $Result }
    function global:add-documentFileExtensions { param($DocumentName, $ItemName) }

    # Override compiled Az cmdlets with function stubs (functions take precedence over cmdlets)
    # This prevents parameter type-validation errors when mocking strongly-typed parameters
    function global:Set-AzContext { param($Subscription) }
    function global:Get-AzStorageAccount { param($ResourceGroupName, $Name, [string]$ErrorAction) }
    function global:Get-AzStorageBlob { param($Container, $Context, $Blob) }

    # Import the module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 1 PROTECT USER ACCOUNTS AND IDENTITIES\Audit\Check-DedicatedAdminAccounts.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Item Function:\Invoke-GraphQueryEX -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    Remove-Item Function:\add-documentFileExtensions -ErrorAction SilentlyContinue
    Remove-Item Function:\Set-AzContext -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-AzStorageAccount -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-AzStorageBlob -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-DedicatedAdminAccounts' {

    BeforeAll {
        $script:msgTable = @{
            isCompliant                              = 'Compliant.'
            isNotCompliant                           = 'Non-compliant.'
            procedureFileNotFound                    = "Could not find '{0}' in container '{1}' in storage '{2}'."
            procedureFileNotFoundWithCorrectExtension = "File '{0}' found but wrong extension in container '{1}' storage '{2}'."
            invalidUserFile                          = 'Update {0} file.'
            invalidFileHeader                        = 'Update {0} file headers.'
            dedicatedAdminAccNotExist                = 'Privileged users without dedicated HP role.'
            regAccHasHProle                          = 'Non-privileged users with HP role.'
            dedicatedAccExist                        = 'Dedicated admin accounts exist.'
            bgAccExistInUPNlist                      = 'BG accounts exist in UPN list.'
            hpAccNotGA                               = 'HP admin not using active GA.'
            dupHPAccount                             = 'Duplicate HP account UPNs.'
            dupRegAccount                            = 'Duplicate regular account UPNs.'
            missingHPaccUPN                          = 'Missing HP_admin_account_UPN data.'
            missingRegAccUPN                         = 'Missing regular_account_UPN data.'
        }
        $script:commonParams = @{
            StorageAccountName  = 'teststorage'
            ContainerName       = 'testcontainer'
            ResourceGroupName   = 'TestRG'
            SubscriptionID      = '00000000-0000-0000-0000-000000000000'
            ControlName         = 'GUARDRAIL 1'
            ItemName            = 'Dedicated Admin Accounts'
            itsgcode            = 'AC-2'
            msgTable            = $script:msgTable
            ReportTime          = (Get-Date -Format 'yyyy-MM-dd')
            FirstBreakGlassUPN  = 'bg1@tenant.onmicrosoft.com'
            SecondBreakGlassUPN = 'bg2@tenant.onmicrosoft.com'
            DocumentName        = @('adminAccounts')
        }
    }

    Context 'When blob is not found in storage' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-DedicatedAdminAccounts {
                param($urlPath)
                if ($urlPath -eq '/directoryRoles') {
                    [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ id = 'ga-role-id'; displayName = 'Global Administrator' },
                        [PSCustomObject]@{ id = 'pra-role-id'; displayName = 'Privileged Role Administrator' }
                    )}}
                } elseif ($urlPath -like '/directoryRoles/*/members') {
                    [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ id='u1'; displayName='Admin1'; mail='admin1@t.com'; userPrincipalName='admin1@t.com' }
                    )}}
                } elseif ($urlPath -eq '/users') {
                    [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ id='u1'; displayName='Admin1'; mail='admin1@t.com'; userPrincipalName='admin1@t.com'; givenName='A'; surname='B' },
                        [PSCustomObject]@{ id='u2'; displayName='User2'; mail='user2@t.com'; userPrincipalName='user2@t.com'; givenName='C'; surname='D' }
                    )}}
                }
            }
            Mock add-documentFileExtensions -ModuleName Check-DedicatedAdminAccounts { return @("adminAccounts.csv") }
            Mock Set-AzContext -ModuleName Check-DedicatedAdminAccounts { }
            Mock Get-AzStorageAccount -ModuleName Check-DedicatedAdminAccounts { [PSCustomObject]@{ Context = [PSCustomObject]@{ } } }
            Mock Get-AzStorageBlob -ModuleName Check-DedicatedAdminAccounts { $null }
        }

        It 'Returns non-compliant with file not found message' {
            $result = Check-DedicatedAdminAccounts @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -BeLike "*Could not find*"
        }
    }

    Context 'When blob exists but has invalid content (NA)' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-DedicatedAdminAccounts {
                param($urlPath)
                if ($urlPath -eq '/directoryRoles') {
                    [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ id = 'ga-role-id'; displayName = 'Global Administrator' },
                        [PSCustomObject]@{ id = 'pra-role-id'; displayName = 'Privileged Role Administrator' }
                    )}}
                } elseif ($urlPath -like '/directoryRoles/*/members') {
                    [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ id='u1'; displayName='Admin1'; mail='admin1@t.com'; userPrincipalName='admin1@t.com' }
                    )}}
                } elseif ($urlPath -eq '/users') {
                    [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ id='u1'; displayName='Admin1'; mail='admin1@t.com'; userPrincipalName='admin1@t.com'; givenName='A'; surname='B' }
                    )}}
                }
            }
            Mock add-documentFileExtensions -ModuleName Check-DedicatedAdminAccounts { return @("adminAccounts.csv") }
            Mock Set-AzContext -ModuleName Check-DedicatedAdminAccounts { }
            Mock Get-AzStorageAccount -ModuleName Check-DedicatedAdminAccounts { [PSCustomObject]@{ Context = [PSCustomObject]@{ } } }
            Mock Get-AzStorageBlob -ModuleName Check-DedicatedAdminAccounts {
                param($Container, $Context, $Blob)
                if ($Blob) {
                    $mockBlob = [PSCustomObject]@{ ICloudBlob = [PSCustomObject]@{ } }
                    $mockBlob.ICloudBlob | Add-Member -MemberType ScriptMethod -Name 'DownloadText' -Value { 'N/A' }
                    return $mockBlob
                } else {
                    @([PSCustomObject]@{ Name = 'adminAccounts.csv' })
                }
            }
        }

        It 'Returns non-compliant with invalid user file message' {
            $result = Check-DedicatedAdminAccounts @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -BeLike '*Update*file*'
        }
    }

    Context 'When blob has BG accounts in UPN list' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-DedicatedAdminAccounts {
                param($urlPath)
                if ($urlPath -eq '/directoryRoles') {
                    [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ id = 'ga-role-id'; displayName = 'Global Administrator' },
                        [PSCustomObject]@{ id = 'pra-role-id'; displayName = 'Privileged Role Administrator' }
                    )}}
                } elseif ($urlPath -like '/directoryRoles/*/members') {
                    [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ id='u1'; displayName='Admin1'; mail='admin1@t.com'; userPrincipalName='admin1@t.com' }
                    )}}
                } elseif ($urlPath -eq '/users') {
                    [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ id='u1'; displayName='Admin1'; mail='admin1@t.com'; userPrincipalName='admin1@t.com'; givenName='A'; surname='B' }
                    )}}
                }
            }
            Mock add-documentFileExtensions -ModuleName Check-DedicatedAdminAccounts { return @("adminAccounts.csv") }
            Mock Set-AzContext -ModuleName Check-DedicatedAdminAccounts { }
            Mock Get-AzStorageAccount -ModuleName Check-DedicatedAdminAccounts { [PSCustomObject]@{ Context = [PSCustomObject]@{ } } }
            Mock Get-AzStorageBlob -ModuleName Check-DedicatedAdminAccounts {
                param($Container, $Context, $Blob)
                if ($Blob) {
                    $mockBlob = [PSCustomObject]@{ ICloudBlob = [PSCustomObject]@{ } }
                    $mockBlob.ICloudBlob | Add-Member -MemberType ScriptMethod -Name 'DownloadText' -Value { "HP_admin_account_UPN,regular_account_UPN`nbg1@tenant.onmicrosoft.com,user1@t.com" }
                    return $mockBlob
                } else {
                    @([PSCustomObject]@{ Name = 'adminAccounts.csv' })
                }
            }
        }

        It 'Returns non-compliant with BG account warning' {
            $result = Check-DedicatedAdminAccounts @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -BeLike '*BG accounts*'
        }
    }

    Context 'When blob has correct content and dedicated admin accounts exist' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-DedicatedAdminAccounts {
                param($urlPath)
                if ($urlPath -eq '/directoryRoles') {
                    [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ id = 'ga-role-id'; displayName = 'Global Administrator' },
                        [PSCustomObject]@{ id = 'pra-role-id'; displayName = 'Privileged Role Administrator' }
                    )}}
                } elseif ($urlPath -like '/directoryRoles/*/members') {
                    [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ id='u1'; displayName='Admin1'; mail='admin1@t.com'; userPrincipalName='admin1@t.com' }
                    )}}
                } elseif ($urlPath -eq '/users') {
                    [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ id='u1'; displayName='Admin1'; mail='admin1@t.com'; userPrincipalName='admin1@t.com'; givenName='A'; surname='B' },
                        [PSCustomObject]@{ id='u2'; displayName='User2'; mail='user2@t.com'; userPrincipalName='user2@t.com'; givenName='C'; surname='D' }
                    )}}
                }
            }
            Mock add-documentFileExtensions -ModuleName Check-DedicatedAdminAccounts { return @("adminAccounts.csv") }
            Mock Set-AzContext -ModuleName Check-DedicatedAdminAccounts { }
            Mock Get-AzStorageAccount -ModuleName Check-DedicatedAdminAccounts { [PSCustomObject]@{ Context = [PSCustomObject]@{ } } }
            Mock Get-AzStorageBlob -ModuleName Check-DedicatedAdminAccounts {
                param($Container, $Context, $Blob)
                if ($Blob) {
                    $mockBlob = [PSCustomObject]@{ ICloudBlob = [PSCustomObject]@{ } }
                    $mockBlob.ICloudBlob | Add-Member -MemberType ScriptMethod -Name 'DownloadText' -Value { "HP_admin_account_UPN,regular_account_UPN`nadmin1@t.com,user2@t.com" }
                    return $mockBlob
                } else {
                    @([PSCustomObject]@{ Name = 'adminAccounts.csv' })
                }
            }
        }

        It 'Returns compliant with dedicated accounts message' {
            $result = Check-DedicatedAdminAccounts @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -BeLike '*Dedicated admin accounts*'
        }
    }

    Context 'When Set-AzContext fails' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-DedicatedAdminAccounts {
                param($urlPath)
                [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @() }}
            }
            Mock add-documentFileExtensions -ModuleName Check-DedicatedAdminAccounts { return @("adminAccounts.csv") }
            Mock Set-AzContext -ModuleName Check-DedicatedAdminAccounts { throw 'Subscription error' }
        }

        It 'Throws an error' {
            { Check-DedicatedAdminAccounts @commonParams } | Should -Throw
        }
    }

    Context 'Output structure when blob not found' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-DedicatedAdminAccounts {
                param($urlPath)
                [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @() }}
            }
            Mock add-documentFileExtensions -ModuleName Check-DedicatedAdminAccounts { return @("adminAccounts.csv") }
            Mock Set-AzContext -ModuleName Check-DedicatedAdminAccounts { }
            Mock Get-AzStorageAccount -ModuleName Check-DedicatedAdminAccounts { [PSCustomObject]@{ Context = [PSCustomObject]@{ } } }
            Mock Get-AzStorageBlob -ModuleName Check-DedicatedAdminAccounts { $null }
        }

        It 'Returns an object with ComplianceResults and Errors' {
            $result = Check-DedicatedAdminAccounts @commonParams
            $result.PSObject.Properties.Name | Should -Contain 'ComplianceResults'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
        }

        It 'ComplianceResults has ControlName matching input' {
            $result = Check-DedicatedAdminAccounts @commonParams
            $result.ComplianceResults.ControlName | Should -Be 'GUARDRAIL 1'
        }
    }

    Context 'When blob has missing HP_admin_account_UPN column data' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-DedicatedAdminAccounts {
                param($urlPath)
                if ($urlPath -eq '/directoryRoles') {
                    [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ id = 'ga-role-id'; displayName = 'Global Administrator' },
                        [PSCustomObject]@{ id = 'pra-role-id'; displayName = 'Privileged Role Administrator' }
                    )}}
                } elseif ($urlPath -like '/directoryRoles/*/members') {
                    [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ id='u1'; displayName='Admin1'; mail='admin1@t.com'; userPrincipalName='admin1@t.com' }
                    )}}
                } elseif ($urlPath -eq '/users') {
                    [PSCustomObject]@{ Content = [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ id='u1'; displayName='Admin1'; mail='admin1@t.com'; userPrincipalName='admin1@t.com'; givenName='A'; surname='B' }
                    )}}
                }
            }
            Mock add-documentFileExtensions -ModuleName Check-DedicatedAdminAccounts { return @("adminAccounts.csv") }
            Mock Set-AzContext -ModuleName Check-DedicatedAdminAccounts { }
            Mock Get-AzStorageAccount -ModuleName Check-DedicatedAdminAccounts { [PSCustomObject]@{ Context = [PSCustomObject]@{ } } }
            Mock Get-AzStorageBlob -ModuleName Check-DedicatedAdminAccounts {
                param($Container, $Context, $Blob)
                if ($Blob) {
                    $mockBlob = [PSCustomObject]@{ ICloudBlob = [PSCustomObject]@{ } }
                    $mockBlob.ICloudBlob | Add-Member -MemberType ScriptMethod -Name 'DownloadText' -Value { "HP_admin_account_UPN,regular_account_UPN`n,user1@t.com" }
                    return $mockBlob
                } else {
                    @([PSCustomObject]@{ Name = 'adminAccounts.csv' })
                }
            }
        }

        It 'Returns non-compliant with missing HP UPN message' {
            $result = Check-DedicatedAdminAccounts @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -BeLike '*Missing HP_admin_account_UPN*'
        }
    }
}
