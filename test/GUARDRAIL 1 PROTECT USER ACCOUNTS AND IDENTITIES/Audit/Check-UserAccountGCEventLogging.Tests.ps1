BeforeAll {
    # Define stubs for external functions
    function global:get-AADDiagnosticSettings { }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) return $Result }

    # Import the module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 1 PROTECT USER ACCOUNTS AND IDENTITIES\Audit\Check-UserAccountGCEventLogging.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Item Function:\get-AADDiagnosticSettings -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
}

# ──────────────────────────────────────────────
# Unit tests for Get-ResourceIdInfo (helper)
# ──────────────────────────────────────────────
Describe 'Get-ResourceIdInfo' {

    It 'Parses a valid LAW resource ID correctly' {
        $id = '/subscriptions/sub-123/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-name'
        $info = Get-ResourceIdInfo -Id $id
        $info.SubscriptionId | Should -Be 'sub-123'
        $info.ResourceGroupName | Should -Be 'rg-test'
        $info.Name | Should -Be 'law-name'
    }

    It 'Extracts workspace name as last segment' {
        $id = '/subscriptions/a/resourceGroups/b/providers/Microsoft.OperationalInsights/workspaces/my-ws'
        $info = Get-ResourceIdInfo -Id $id
        $info.Name | Should -Be 'my-ws'
    }
}

# ──────────────────────────────────────────────
# Unit tests for Test-SentinelTables (helper)
# ──────────────────────────────────────────────
Describe 'Test-SentinelTables' {

    Context 'When Sentinel tables exist' {

        BeforeAll {
            Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-UserAccountGCEventLogging { }
        }

        It 'Returns HasAny=true when tables compile' {
            $ws = [PSCustomObject]@{ CustomerId = 'ws-id' }
            $result = Test-SentinelTables -Workspace $ws
            $result.HasAny | Should -BeTrue
            $result.Found.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When no Sentinel tables exist' {

        BeforeAll {
            Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-UserAccountGCEventLogging { throw 'Table does not exist' }
        }

        It 'Returns HasAny=false' {
            $ws = [PSCustomObject]@{ CustomerId = 'ws-id' }
            $result = Test-SentinelTables -Workspace $ws
            $result.HasAny | Should -BeFalse
            $result.Found.Count | Should -Be 0
        }
    }

    Context 'When some tables exist and some do not' {

        BeforeAll {
            $script:callCount = 0
            Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-UserAccountGCEventLogging {
                $script:callCount++
                if ($script:callCount -eq 1) { return }  # first table exists
                throw 'Table does not exist'
            }
        }

        It 'Returns HasAny=true with partial found list' {
            $script:callCount = 0
            $ws = [PSCustomObject]@{ CustomerId = 'ws-id' }
            $result = Test-SentinelTables -Workspace $ws
            $result.HasAny | Should -BeTrue
            $result.Found.Count | Should -Be 1
        }
    }
}

# ──────────────────────────────────────────────
# Unit tests for Check-UserAccountGCEventLogging
# ──────────────────────────────────────────────
Describe 'Check-UserAccountGCEventLogging' {

    BeforeAll {
        $script:msgTable = @{
            retentionNotMet              = 'LAW {0} retention not met.'
            logsNotCollected             = 'Logs not collected.'
            nonCompliantLaw              = 'LAW {0} not found.'
            gcEventLoggingCompliantComment = 'GC Event logging is compliant.'
            lockLevelApproved            = 'LAW {0} has approved lock {1}.'
            lockLevelNotApproved         = 'LAW {0} lock level {1} not approved.'
            tagFound                     = 'LAW {0} has sentinel tag.'
            sentinelTablesFound          = 'LAW {0} has sentinel tables.'
            noLockNoTagNoTables          = 'LAW {0} no lock no tag no tables.'
        }
        $script:lawResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/TestRG/providers/Microsoft.OperationalInsights/workspaces/TestLAW'
        $script:commonParams = @{
            LAWResourceId         = $script:lawResourceId
            RequiredRetentionDays = 365
            ControlName           = 'GUARDRAIL 1'
            ItemName              = 'GC Event Logging'
            itsgcode              = 'AC-2'
            msgTable              = $script:msgTable
            ReportTime            = (Get-Date -Format 'yyyy-MM-dd')
        }
    }

    Context 'When LAW meets retention, has all logs, and has a ReadOnly lock' {

        BeforeAll {
            Mock Select-AzSubscription -ModuleName Check-UserAccountGCEventLogging { }
            Mock Get-AzOperationalInsightsWorkspace -ModuleName Check-UserAccountGCEventLogging {
                [PSCustomObject]@{
                    RetentionInDays = 730
                    CustomerId      = 'cust-id'
                    Tags            = @{}
                }
            }
            Mock get-AADDiagnosticSettings -ModuleName Check-UserAccountGCEventLogging {
                @([PSCustomObject]@{
                    properties = [PSCustomObject]@{
                        workspaceId = $script:lawResourceId
                        logs = @(
                            [PSCustomObject]@{ category = 'AuditLogs'; enabled = $true },
                            [PSCustomObject]@{ category = 'SignInLogs'; enabled = $true },
                            [PSCustomObject]@{ category = 'ManagedIdentitySignInLogs'; enabled = $true },
                            [PSCustomObject]@{ category = 'RiskyUsers'; enabled = $true },
                            [PSCustomObject]@{ category = 'MicrosoftGraphActivityLogs'; enabled = $true }
                        )
                    }
                })
            }
            Mock Get-AzResourceLock -ModuleName Check-UserAccountGCEventLogging {
                [PSCustomObject]@{
                    Properties = [PSCustomObject]@{ level = 'ReadOnly' }
                }
            }
        }

        It 'Returns compliant' {
            $result = Check-UserAccountGCEventLogging @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -Be $script:msgTable.gcEventLoggingCompliantComment
        }
    }

    Context 'When retention is insufficient' {

        BeforeAll {
            Mock Select-AzSubscription -ModuleName Check-UserAccountGCEventLogging { }
            Mock Get-AzOperationalInsightsWorkspace -ModuleName Check-UserAccountGCEventLogging {
                [PSCustomObject]@{
                    RetentionInDays = 30
                    CustomerId      = 'cust-id'
                    Tags            = @{}
                }
            }
            Mock get-AADDiagnosticSettings -ModuleName Check-UserAccountGCEventLogging {
                @([PSCustomObject]@{
                    properties = [PSCustomObject]@{
                        workspaceId = $script:lawResourceId
                        logs = @(
                            [PSCustomObject]@{ category = 'AuditLogs'; enabled = $true },
                            [PSCustomObject]@{ category = 'SignInLogs'; enabled = $true },
                            [PSCustomObject]@{ category = 'ManagedIdentitySignInLogs'; enabled = $true },
                            [PSCustomObject]@{ category = 'RiskyUsers'; enabled = $true },
                            [PSCustomObject]@{ category = 'MicrosoftGraphActivityLogs'; enabled = $true }
                        )
                    }
                })
            }
            Mock Get-AzResourceLock -ModuleName Check-UserAccountGCEventLogging {
                [PSCustomObject]@{
                    Properties = [PSCustomObject]@{ level = 'ReadOnly' }
                }
            }
        }

        It 'Returns non-compliant' {
            $result = Check-UserAccountGCEventLogging @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        }
    }

    Context 'When required logs are missing' {

        BeforeAll {
            Mock Select-AzSubscription -ModuleName Check-UserAccountGCEventLogging { }
            Mock Get-AzOperationalInsightsWorkspace -ModuleName Check-UserAccountGCEventLogging {
                [PSCustomObject]@{
                    RetentionInDays = 730
                    CustomerId      = 'cust-id'
                    Tags            = @{}
                }
            }
            Mock get-AADDiagnosticSettings -ModuleName Check-UserAccountGCEventLogging {
                @([PSCustomObject]@{
                    properties = [PSCustomObject]@{
                        workspaceId = $script:lawResourceId
                        logs = @(
                            [PSCustomObject]@{ category = 'AuditLogs'; enabled = $true }
                        )
                    }
                })
            }
            Mock Get-AzResourceLock -ModuleName Check-UserAccountGCEventLogging {
                [PSCustomObject]@{
                    Properties = [PSCustomObject]@{ level = 'ReadOnly' }
                }
            }
        }

        It 'Returns non-compliant and mentions missing logs' {
            $result = Check-UserAccountGCEventLogging @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        }
    }

    Context 'When no lock exists but sentinel tag is present' {

        BeforeAll {
            Mock Select-AzSubscription -ModuleName Check-UserAccountGCEventLogging { }
            Mock Get-AzOperationalInsightsWorkspace -ModuleName Check-UserAccountGCEventLogging {
                [PSCustomObject]@{
                    RetentionInDays = 730
                    CustomerId      = 'cust-id'
                    Tags            = @{ sentinel = 'true' }
                }
            }
            Mock get-AADDiagnosticSettings -ModuleName Check-UserAccountGCEventLogging {
                @([PSCustomObject]@{
                    properties = [PSCustomObject]@{
                        workspaceId = $script:lawResourceId
                        logs = @(
                            [PSCustomObject]@{ category = 'AuditLogs'; enabled = $true },
                            [PSCustomObject]@{ category = 'SignInLogs'; enabled = $true },
                            [PSCustomObject]@{ category = 'ManagedIdentitySignInLogs'; enabled = $true },
                            [PSCustomObject]@{ category = 'RiskyUsers'; enabled = $true },
                            [PSCustomObject]@{ category = 'MicrosoftGraphActivityLogs'; enabled = $true }
                        )
                    }
                })
            }
            Mock Get-AzResourceLock -ModuleName Check-UserAccountGCEventLogging { $null }
        }

        It 'Returns compliant (tag found serves as alternative)' {
            $result = Check-UserAccountGCEventLogging @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        }
    }

    Context 'When no lock, no tag, and no sentinel tables' {

        BeforeAll {
            Mock Select-AzSubscription -ModuleName Check-UserAccountGCEventLogging { }
            Mock Get-AzOperationalInsightsWorkspace -ModuleName Check-UserAccountGCEventLogging {
                [PSCustomObject]@{
                    RetentionInDays = 730
                    CustomerId      = 'cust-id'
                    Tags            = @{}
                }
            }
            Mock get-AADDiagnosticSettings -ModuleName Check-UserAccountGCEventLogging {
                @([PSCustomObject]@{
                    properties = [PSCustomObject]@{
                        workspaceId = $script:lawResourceId
                        logs = @(
                            [PSCustomObject]@{ category = 'AuditLogs'; enabled = $true },
                            [PSCustomObject]@{ category = 'SignInLogs'; enabled = $true },
                            [PSCustomObject]@{ category = 'ManagedIdentitySignInLogs'; enabled = $true },
                            [PSCustomObject]@{ category = 'RiskyUsers'; enabled = $true },
                            [PSCustomObject]@{ category = 'MicrosoftGraphActivityLogs'; enabled = $true }
                        )
                    }
                })
            }
            Mock Get-AzResourceLock -ModuleName Check-UserAccountGCEventLogging { $null }
            Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-UserAccountGCEventLogging { throw 'Table does not exist' }
        }

        It 'Returns non-compliant' {
            $result = Check-UserAccountGCEventLogging @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        }
    }

    Context 'When Select-AzSubscription fails' {

        BeforeAll {
            Mock Select-AzSubscription -ModuleName Check-UserAccountGCEventLogging { throw 'Subscription not found' }
        }

        It 'Throws an error' {
            { Check-UserAccountGCEventLogging @commonParams } | Should -Throw
        }
    }

    Context 'When LAW does not exist (ResourceNotFound)' {

        BeforeAll {
            Mock Select-AzSubscription -ModuleName Check-UserAccountGCEventLogging { }
            Mock Get-AzOperationalInsightsWorkspace -ModuleName Check-UserAccountGCEventLogging { throw 'ResourceNotFound: workspace not found' }
        }

        It 'Returns non-compliant' {
            $result = Check-UserAccountGCEventLogging @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        }
    }
}
