BeforeAll {
    # Ensure Write-Error in source modules stays non-terminating (CI and VS Code set $ErrorActionPreference = 'Stop')
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    # Define stubs for external functions
    function global:Invoke-GraphQueryEX { param($urlPath) }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) return $Result }
    function global:Get-AllUserAuthInformation { param($allUserList) }

    # Import the module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 1 PROTECT USER ACCOUNTS AND IDENTITIES\Audit\Check-GAUserCountMFARequired.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Item Function:\Invoke-GraphQueryEX -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-AllUserAuthInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

# ──────────────────────────────────────────────
# Unit tests for get-MFACount (helper function)
# ──────────────────────────────────────────────
Describe 'get-MFACount' {

    Context 'When all member users have valid MFA' {

        BeforeAll {
            Mock Get-AllUserAuthInformation -ModuleName Check-GAUserCountMFARequired {
                [PSCustomObject]@{
                    userUPNsBadMFA      = @()
                    userUPNsValidMFA    = @([PSCustomObject]@{ UPN = 'admin@tenant.com' })
                    userValidMFACounter = 1
                    ErrorList           = $null
                }
            }
        }

        It 'Returns correct valid MFA counter for member users' {
            $gaUsers = @(
                [PSCustomObject]@{
                    userPrincipalName = 'admin@tenant.com'
                    mail              = 'admin@tenant.com'
                }
            )
            $result = get-MFACount -globalAdminUserAccounts $gaUsers
            $result.userValidMFACounter | Should -Be 1
            $result.userUPNsBadMFA | Should -BeNullOrEmpty
        }
    }

    Context 'When external users exist with bad MFA' {

        BeforeAll {
            Mock Get-AllUserAuthInformation -ModuleName Check-GAUserCountMFARequired {
                param($allUserList)
                $upns = $allUserList | Select-Object -ExpandProperty userPrincipalName
                if ($upns -like '*#EXT#*') {
                    [PSCustomObject]@{
                        userUPNsBadMFA      = @([PSCustomObject]@{ UPN = 'ext_user@external.com#EXT#@tenant.onmicrosoft.com' })
                        userUPNsValidMFA    = @()
                        userValidMFACounter = 0
                        ErrorList           = $null
                    }
                } else {
                    [PSCustomObject]@{
                        userUPNsBadMFA      = @()
                        userUPNsValidMFA    = @([PSCustomObject]@{ UPN = 'admin@tenant.com' })
                        userValidMFACounter = 1
                        ErrorList           = $null
                    }
                }
            }
        }

        It 'Combines bad MFA lists from member and external users' {
            $gaUsers = @(
                [PSCustomObject]@{
                    userPrincipalName = 'admin@tenant.com'
                    mail              = 'admin@tenant.com'
                },
                [PSCustomObject]@{
                    userPrincipalName = 'ext_user@external.com#EXT#@tenant.onmicrosoft.com'
                    mail              = 'ext_user@external.com'
                }
            )
            $result = get-MFACount -globalAdminUserAccounts $gaUsers
            $result.userUPNsBadMFA | Should -Not -BeNullOrEmpty
        }
    }
}

# ──────────────────────────────────────────────
# Unit tests for Check-GAUserCountMFARequired
# ──────────────────────────────────────────────
Describe 'Check-GAUserCountMFARequired' {

    BeforeAll {
        $script:msgTable = @{
            isCompliant              = 'Compliant.'
            isNotCompliant           = 'Non-compliant.'
            globalAdminAccntsSurplus = 'Too many GA accounts.'
            globalAdminAccntsMinimum = 'Not enough active GA accounts.'
            allGAUserHaveMFA        = 'All GA users have MFA.'
            gaUserMisconfiguredMFA  = 'GA users with bad MFA: {0}'
        }
        $script:commonParams = @{
            ControlName         = 'GUARDRAIL 1'
            ItemName            = 'GA User Count MFA'
            itsgcode            = 'AC-2'
            msgTable            = $script:msgTable
            ReportTime          = (Get-Date -Format 'yyyy-MM-dd')
            FirstBreakGlassUPN  = 'bg1@tenant.onmicrosoft.com'
            SecondBreakGlassUPN = 'bg2@tenant.onmicrosoft.com'
        }
    }

    Context 'When only break glass accounts exist (0 non-BG GA users)' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-GAUserCountMFARequired {
                param($urlPath)
                if ($urlPath -eq '/directoryRoles') {
                    [PSCustomObject]@{
                        Content = [PSCustomObject]@{
                            value = @(
                                [PSCustomObject]@{
                                    id          = 'role-1'
                                    displayName = 'Global Administrator'
                                }
                            )
                        }
                    }
                } else {
                    # members of GA role = only BG accounts
                    [PSCustomObject]@{
                        Content = [PSCustomObject]@{
                            value = @(
                                [PSCustomObject]@{
                                    id                = 'u1'
                                    displayName       = 'BG1'
                                    mail              = 'bg1@tenant.onmicrosoft.com'
                                    userPrincipalName = 'bg1@tenant.onmicrosoft.com'
                                },
                                [PSCustomObject]@{
                                    id                = 'u2'
                                    displayName       = 'BG2'
                                    mail              = 'bg2@tenant.onmicrosoft.com'
                                    userPrincipalName = 'bg2@tenant.onmicrosoft.com'
                                }
                            )
                        }
                    }
                }
            }
        }

        It 'Returns compliant when only BG accounts have GA role' {
            $result = Check-GAUserCountMFARequired @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -BeLike '*Not enough active GA*'
        }
    }

    Context 'When more than 5 non-BG GA users exist' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-GAUserCountMFARequired {
                param($urlPath)
                if ($urlPath -eq '/directoryRoles') {
                    [PSCustomObject]@{
                        Content = [PSCustomObject]@{
                            value = @(
                                [PSCustomObject]@{
                                    id          = 'role-1'
                                    displayName = 'Global Administrator'
                                }
                            )
                        }
                    }
                } else {
                    # 6 non-BG GA users + 2 BG
                    $users = @()
                    $users += [PSCustomObject]@{ id='bg-1'; displayName='BG1'; mail='bg1@tenant.onmicrosoft.com'; userPrincipalName='bg1@tenant.onmicrosoft.com' }
                    $users += [PSCustomObject]@{ id='bg-2'; displayName='BG2'; mail='bg2@tenant.onmicrosoft.com'; userPrincipalName='bg2@tenant.onmicrosoft.com' }
                    for ($i = 1; $i -le 6; $i++) {
                        $users += [PSCustomObject]@{
                            id                = "user-$i"
                            displayName       = "User$i"
                            mail              = "user$i@tenant.com"
                            userPrincipalName = "user$i@tenant.com"
                        }
                    }
                    [PSCustomObject]@{
                        Content = [PSCustomObject]@{
                            value = $users
                        }
                    }
                }
            }
        }

        It 'Returns non-compliant when too many GA accounts' {
            $result = Check-GAUserCountMFARequired @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -BeLike '*Too many GA*'
        }
    }

    Context 'When 2 non-BG GA users exist with valid MFA' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-GAUserCountMFARequired {
                param($urlPath)
                if ($urlPath -eq '/directoryRoles') {
                    [PSCustomObject]@{
                        Content = [PSCustomObject]@{
                            value = @(
                                [PSCustomObject]@{
                                    id          = 'role-1'
                                    displayName = 'Global Administrator'
                                }
                            )
                        }
                    }
                } else {
                    [PSCustomObject]@{
                        Content = [PSCustomObject]@{
                            value = @(
                                [PSCustomObject]@{ id='bg-1'; displayName='BG1'; mail='bg1@tenant.onmicrosoft.com'; userPrincipalName='bg1@tenant.onmicrosoft.com' },
                                [PSCustomObject]@{ id='bg-2'; displayName='BG2'; mail='bg2@tenant.onmicrosoft.com'; userPrincipalName='bg2@tenant.onmicrosoft.com' },
                                [PSCustomObject]@{ id='u1'; displayName='Admin1'; mail='admin1@tenant.com'; userPrincipalName='admin1@tenant.com' },
                                [PSCustomObject]@{ id='u2'; displayName='Admin2'; mail='admin2@tenant.com'; userPrincipalName='admin2@tenant.com' }
                            )
                        }
                    }
                }
            }
            Mock Get-AllUserAuthInformation -ModuleName Check-GAUserCountMFARequired {
                [PSCustomObject]@{
                    userUPNsBadMFA      = @()
                    userUPNsValidMFA    = @([PSCustomObject]@{ UPN = 'admin1@tenant.com' }, [PSCustomObject]@{ UPN = 'admin2@tenant.com' })
                    userValidMFACounter = 2
                    ErrorList           = $null
                }
            }
        }

        It 'Returns compliant when all GA users have MFA' {
            $result = Check-GAUserCountMFARequired @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -BeLike '*All GA users have MFA*'
        }
    }

    Context 'When 1 non-BG GA user exists without valid MFA' {

        BeforeAll {
            Mock Invoke-GraphQueryEX -ModuleName Check-GAUserCountMFARequired {
                param($urlPath)
                if ($urlPath -eq '/directoryRoles') {
                    [PSCustomObject]@{
                        Content = [PSCustomObject]@{
                            value = @(
                                [PSCustomObject]@{
                                    id          = 'role-1'
                                    displayName = 'Global Administrator'
                                }
                            )
                        }
                    }
                } else {
                    [PSCustomObject]@{
                        Content = [PSCustomObject]@{
                            value = @(
                                [PSCustomObject]@{ id='bg-1'; displayName='BG1'; mail='bg1@tenant.onmicrosoft.com'; userPrincipalName='bg1@tenant.onmicrosoft.com' },
                                [PSCustomObject]@{ id='bg-2'; displayName='BG2'; mail='bg2@tenant.onmicrosoft.com'; userPrincipalName='bg2@tenant.onmicrosoft.com' },
                                [PSCustomObject]@{ id='u1'; displayName='Admin1'; mail='admin1@tenant.com'; userPrincipalName='admin1@tenant.com' }
                            )
                        }
                    }
                }
            }
            Mock Get-AllUserAuthInformation -ModuleName Check-GAUserCountMFARequired {
                [PSCustomObject]@{
                    userUPNsBadMFA      = @([PSCustomObject]@{ UPN = 'admin1@tenant.com' })
                    userUPNsValidMFA    = @()
                    userValidMFACounter = 0
                    ErrorList           = $null
                }
            }
        }

        It 'Returns non-compliant when GA user has bad MFA' {
            $result = Check-GAUserCountMFARequired @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -BeLike '*bad MFA*'
        }
    }
}
