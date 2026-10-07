BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Get-AzAccessToken { }
    function global:Invoke-GraphQueryEX { }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) return $Result }

    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 2 MANAGE ACCESS\Audit\Check-UserGroups.psm1'
    Import-Module $modulePath -Force

    $script:msgTable = @{
        isCompliant             = 'Compliant.'
        isNotCompliant          = 'Non-compliant.'
        userCountOne            = 'One or fewer users exist in the tenant.'
        userGroupsMany          = 'At least two user groups are required.'
        userNotInGroup          = 'User is not assigned to any group.'
        userInGroup             = 'User is assigned to a group.'
        reqPolicyUserGroupExists = 'A conditional access policy references user groups.'
        noCAPforAnyGroups       = 'No enabled conditional access policy references any user groups.'
        userCountGroupNoMatch   = 'The total grouped users count does not match the total user count.'
        userStats               = 'Users:{0} GroupUsers:{1} Members:{2} Guests:{3}'
    }
}

AfterAll {
    Remove-Item Function:\Get-AzAccessToken -ErrorAction SilentlyContinue
    Remove-Item Function:\Invoke-GraphQueryEX -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-UserGroups' {
    BeforeAll {
        $script:commonParams = @{
            ControlName = 'GUARDRAIL 2'
            ItemName    = 'Manage Access - User Groups'
            itsgcode    = 'AC-2'
            msgTable    = $script:msgTable
            ReportTime  = '2026-09-03'
        }
    }

    Context 'When the tenant has one or fewer users' {
        BeforeAll {
            Mock Get-AzAccessToken -ModuleName Check-UserGroups {
                [PSCustomObject]@{ Token = 'fake-token' }
            }

            Mock Invoke-RestMethod -ModuleName Check-UserGroups {
                if ($Uri -eq "https://graph.microsoft.com/v1.0/users/`$count?`$filter=userType eq 'Member'") { return 1 }
                if ($Uri -eq "https://graph.microsoft.com/v1.0/users/`$count?`$filter=userType eq 'Guest'") { return 0 }
                if ($Uri -eq 'https://graph.microsoft.com/v1.0/groups/$count') { return 0 }
                if ($Uri -like 'https://graph.microsoft.com/v1.0/users`?*') {
                    return [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                id                = 'user-1'
                                displayName       = 'User One'
                                givenName         = 'User'
                                userPrincipalName = 'user1@tenant.onmicrosoft.com'
                            }
                        )
                        '@odata.nextLink' = $null
                    }
                }
                if ($Uri -like 'https://graph.microsoft.com/v1.0/groups`?*') {
                    return [PSCustomObject]@{
                        value = @()
                        '@odata.nextLink' = $null
                    }
                }

                throw "Unexpected Uri: $Uri"
            }

            Mock Invoke-GraphQueryEX -ModuleName Check-UserGroups {
                throw 'Conditional access lookup should not run for one or fewer users.'
            }
        }

        It 'Returns compliant with the one-user message' {
            $result = Check-UserGroups @commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -BeLike '*One or fewer users exist in the tenant.*'
            $result.ComplianceResults.Comments | Should -BeLike '*Users:1 GroupUsers:0 Members:1 Guests:0*'
        }
    }

    Context 'When fewer than two groups exist' {
        BeforeAll {
            Mock Get-AzAccessToken -ModuleName Check-UserGroups {
                [PSCustomObject]@{ Token = 'fake-token' }
            }

            Mock Invoke-RestMethod -ModuleName Check-UserGroups {
                if ($Uri -eq "https://graph.microsoft.com/v1.0/users/`$count?`$filter=userType eq 'Member'") { return 2 }
                if ($Uri -eq "https://graph.microsoft.com/v1.0/users/`$count?`$filter=userType eq 'Guest'") { return 0 }
                if ($Uri -eq 'https://graph.microsoft.com/v1.0/groups/$count') { return 1 }
                if ($Uri -like 'https://graph.microsoft.com/v1.0/users`?*') {
                    return [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                id                = 'user-1'
                                displayName       = 'User One'
                                givenName         = 'User'
                                userPrincipalName = 'user1@tenant.onmicrosoft.com'
                            },
                            [PSCustomObject]@{
                                id                = 'user-2'
                                displayName       = 'User Two'
                                givenName         = 'User'
                                userPrincipalName = 'user2@tenant.onmicrosoft.com'
                            }
                        )
                        '@odata.nextLink' = $null
                    }
                }
                if ($Uri -like 'https://graph.microsoft.com/v1.0/groups`?*') {
                    return [PSCustomObject]@{
                        value = @([PSCustomObject]@{ id = 'group-1' })
                        '@odata.nextLink' = $null
                    }
                }
                if ($Uri -like 'https://graph.microsoft.com/v1.0/groups/group-1/members/microsoft.graph.user?*') {
                    return [PSCustomObject]@{
                        value = @([PSCustomObject]@{ userPrincipalName = 'user1@tenant.onmicrosoft.com' })
                        '@odata.nextLink' = $null
                    }
                }

                throw "Unexpected Uri: $Uri"
            }

            Mock Invoke-GraphQueryEX -ModuleName Check-UserGroups {
                throw 'Conditional access lookup should not run when group count is below two.'
            }
        }

        It 'Returns non-compliant and includes users without groups in AdditionalResults' {
            $result = Check-UserGroups @commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -BeLike '*At least two user groups are required.*'
            $result.ComplianceResults.Comments | Should -BeLike '*Users:2 GroupUsers:1 Members:2 Guests:0*'
            $result.AdditionalResults.logType | Should -Be 'GR2UsersWithoutGroups'
            $result.AdditionalResults.records.Count | Should -Be 1
            $result.AdditionalResults.records[0].UserPrincipalName | Should -Be 'user2@tenant.onmicrosoft.com'
            $result.AdditionalResults.records[0].Comments | Should -Be $script:msgTable.userNotInGroup
        }
    }

    Context 'When all users are grouped and a matching conditional access policy exists' {
        BeforeAll {
            Mock Get-AzAccessToken -ModuleName Check-UserGroups {
                [PSCustomObject]@{ Token = 'fake-token' }
            }

            Mock Invoke-RestMethod -ModuleName Check-UserGroups {
                if ($Uri -eq "https://graph.microsoft.com/v1.0/users/`$count?`$filter=userType eq 'Member'") { return 2 }
                if ($Uri -eq "https://graph.microsoft.com/v1.0/users/`$count?`$filter=userType eq 'Guest'") { return 0 }
                if ($Uri -eq 'https://graph.microsoft.com/v1.0/groups/$count') { return 2 }
                if ($Uri -like 'https://graph.microsoft.com/v1.0/users`?*') {
                    return [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                id                = 'user-1'
                                displayName       = 'User One'
                                givenName         = 'User'
                                userPrincipalName = 'user1@tenant.onmicrosoft.com'
                            },
                            [PSCustomObject]@{
                                id                = 'user-2'
                                displayName       = 'User Two'
                                givenName         = 'User'
                                userPrincipalName = 'user2@tenant.onmicrosoft.com'
                            }
                        )
                        '@odata.nextLink' = $null
                    }
                }
                if ($Uri -like 'https://graph.microsoft.com/v1.0/groups`?*') {
                    return [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{ id = 'group-1' },
                            [PSCustomObject]@{ id = 'group-2' }
                        )
                        '@odata.nextLink' = $null
                    }
                }
                if ($Uri -like 'https://graph.microsoft.com/v1.0/groups/group-1/members/microsoft.graph.user?*') {
                    return [PSCustomObject]@{
                        value = @([PSCustomObject]@{ userPrincipalName = 'user1@tenant.onmicrosoft.com' })
                        '@odata.nextLink' = $null
                    }
                }
                if ($Uri -like 'https://graph.microsoft.com/v1.0/groups/group-2/members/microsoft.graph.user?*') {
                    return [PSCustomObject]@{
                        value = @([PSCustomObject]@{ userPrincipalName = 'user2@tenant.onmicrosoft.com' })
                        '@odata.nextLink' = $null
                    }
                }

                throw "Unexpected Uri: $Uri"
            }

            Mock Invoke-GraphQueryEX -ModuleName Check-UserGroups {
                [PSCustomObject]@{
                    Content = [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                state = 'enabled'
                                conditions = [PSCustomObject]@{
                                    users = [PSCustomObject]@{
                                        includeGroups = @('group-1')
                                        excludeGroups = @()
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }

        It 'Returns compliant and reports the matching policy' {
            $result = Check-UserGroups @commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -BeLike '*A conditional access policy references user groups.*'
            $result.ComplianceResults.Comments | Should -BeLike '*Users:2 GroupUsers:2 Members:2 Guests:0*'
        }
    }

    Context 'When all users are grouped but no matching conditional access policy exists' {
        BeforeAll {
            Mock Get-AzAccessToken -ModuleName Check-UserGroups {
                [PSCustomObject]@{ Token = 'fake-token' }
            }

            Mock Invoke-RestMethod -ModuleName Check-UserGroups {
                if ($Uri -eq "https://graph.microsoft.com/v1.0/users/`$count?`$filter=userType eq 'Member'") { return 2 }
                if ($Uri -eq "https://graph.microsoft.com/v1.0/users/`$count?`$filter=userType eq 'Guest'") { return 0 }
                if ($Uri -eq 'https://graph.microsoft.com/v1.0/groups/$count') { return 2 }
                if ($Uri -like 'https://graph.microsoft.com/v1.0/users`?*') {
                    return [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                id                = 'user-1'
                                displayName       = 'User One'
                                givenName         = 'User'
                                userPrincipalName = 'user1@tenant.onmicrosoft.com'
                            },
                            [PSCustomObject]@{
                                id                = 'user-2'
                                displayName       = 'User Two'
                                givenName         = 'User'
                                userPrincipalName = 'user2@tenant.onmicrosoft.com'
                            }
                        )
                        '@odata.nextLink' = $null
                    }
                }
                if ($Uri -like 'https://graph.microsoft.com/v1.0/groups`?*') {
                    return [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{ id = 'group-1' },
                            [PSCustomObject]@{ id = 'group-2' }
                        )
                        '@odata.nextLink' = $null
                    }
                }
                if ($Uri -like 'https://graph.microsoft.com/v1.0/groups/group-1/members/microsoft.graph.user?*') {
                    return [PSCustomObject]@{
                        value = @([PSCustomObject]@{ userPrincipalName = 'user1@tenant.onmicrosoft.com' })
                        '@odata.nextLink' = $null
                    }
                }
                if ($Uri -like 'https://graph.microsoft.com/v1.0/groups/group-2/members/microsoft.graph.user?*') {
                    return [PSCustomObject]@{
                        value = @([PSCustomObject]@{ userPrincipalName = 'user2@tenant.onmicrosoft.com' })
                        '@odata.nextLink' = $null
                    }
                }

                throw "Unexpected Uri: $Uri"
            }

            Mock Invoke-GraphQueryEX -ModuleName Check-UserGroups {
                [PSCustomObject]@{
                    Content = [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                state = 'enabled'
                                conditions = [PSCustomObject]@{
                                    users = [PSCustomObject]@{
                                        includeGroups = @()
                                        excludeGroups = @()
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }

        It 'Returns non-compliant and reports the missing policy coverage' {
            $result = Check-UserGroups @commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -BeLike '*No enabled conditional access policy references any user groups.*'
            $result.ComplianceResults.Comments | Should -BeLike '*Users:2 GroupUsers:2 Members:2 Guests:0*'
        }
    }
}
