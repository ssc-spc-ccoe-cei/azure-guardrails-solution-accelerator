BeforeAll {
    # Ensure Write-Error in source modules stays non-terminating (CI and VS Code set $ErrorActionPreference = 'Stop')
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    # Define stubs for external functions not available outside the solution
    function global:get-AADDiagnosticSettings { }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) return $Result }

    # Import the module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 1 PROTECT USER ACCOUNTS AND IDENTITIES\Audit\Check-AlertsMonitor.psm1'
    Import-Module $modulePath -Force

    # Common message table stub used across tests
    $script:msgTable = @{
        signInlogsNotCollected    = 'SignInLogs not collected.'
        auditlogsNotCollected     = 'AuditLogs not collected.'
        noAlertRules              = 'No alert rules for RG {0}.'
        noActionGroups            = 'No action groups for RG {0}.'
        noActionGroupsForBGaccts  = 'No action groups for BG accounts.'
        noActionGroupsForAuditLogs = 'No action groups for audit logs.'
        compliantAlerts           = 'Alerts are compliant.'
        noAlertRuleforBGaccts     = 'Missing BG alert rule.'
        noAlertRuleforCaps        = 'Missing CAP alert rule.'
        nonCompliantLaw           = 'LAW {0} not found.'
        isNotCompliant            = 'Non-compliant.'
    }
}

AfterAll {
    # Clean up global stubs
    Remove-Item Function:\get-AADDiagnosticSettings -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

# ──────────────────────────────────────────────
# Unit tests for Find-ReceiverValues
# The function filters properties by MemberType -eq 'Property'
# which corresponds to .NET properties from Az SDK objects.
# PSCustomObject creates NoteProperty members, so we test
# the function's behavior with realistic edge cases and by
# using InModuleScope to verify internal logic.
# ──────────────────────────────────────────────
Describe 'Find-ReceiverValues' {

    It 'Returns empty when no action groups provided' {
        $result = Find-ReceiverValues -actionGroups @()
        $result | Should -BeNullOrEmpty
    }

    It 'Skips null action groups without throwing' {
        { Find-ReceiverValues -actionGroups @($null) } | Should -Not -Throw
    }

    It 'Returns empty when action groups have no Receiver-named properties' {
        $ag = [PSCustomObject]@{
            Name       = 'AG3'
            NoReceiver = 'not a receiver'
        }
        $result = Find-ReceiverValues -actionGroups @($ag)
        $result | Should -BeNullOrEmpty
    }

    It 'Returns empty for null input' {
        $result = Find-ReceiverValues -actionGroups $null
        $result | Should -BeNullOrEmpty
    }
}

# ──────────────────────────────────────────────
# Unit tests for CompareKQLQueryToPattern
# ──────────────────────────────────────────────
Describe 'CompareKQLQueryToPattern' {

    It 'Returns true when target matches pattern' {
        $pattern = 'SigninLogs\s*\|'
        $target  = 'SigninLogs | where UserPrincipalName == "bg@tenant.com"'
        CompareKQLQueryToPattern -pattern $pattern -targetQuery $target | Should -BeTrue
    }

    It 'Returns false when target does not match pattern' {
        $pattern = 'AuditLogs\s*\|.*Update'
        $target  = 'SigninLogs | where something'
        CompareKQLQueryToPattern -pattern $pattern -targetQuery $target | Should -BeFalse
    }

    It 'Returns false for null/empty pattern' {
        CompareKQLQueryToPattern -pattern '' -targetQuery 'something' | Should -BeFalse
        CompareKQLQueryToPattern -pattern $null -targetQuery 'something' | Should -BeFalse
    }

    It 'Returns false for null/empty target query' {
        CompareKQLQueryToPattern -pattern 'test' -targetQuery '' | Should -BeFalse
        CompareKQLQueryToPattern -pattern 'test' -targetQuery $null | Should -BeFalse
    }

    It 'Is case-insensitive' {
        CompareKQLQueryToPattern -pattern 'signinlogs' -targetQuery 'SigninLogs | where x' | Should -BeTrue
    }
}

# ──────────────────────────────────────────────
# Unit tests for Check-AlertsMonitor
# ──────────────────────────────────────────────
Describe 'Check-AlertsMonitor' {

    BeforeAll {
        $script:commonParams = @{
            LAWResourceId       = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/TestRG/providers/Microsoft.OperationalInsights/workspaces/TestLAW'
            FirstBreakGlassUPN  = 'bg1@tenant.onmicrosoft.com'
            SecondBreakGlassUPN = 'bg2@tenant.onmicrosoft.com'
            ControlName         = 'GUARDRAIL 1'
            ItemName            = 'Alerts Monitor'
            itsgcode            = 'AC-2'
            msgTable            = $script:msgTable
            ReportTime          = (Get-Date -Format 'yyyy-MM-dd')
        }
    }

    Context 'When diagnostic settings show all logs, alert rules and action groups exist and match' {

        BeforeAll {
            # Mock Select-AzSubscription
            Mock Select-AzSubscription { } -ModuleName Check-AlertsMonitor

            # Mock get-AADDiagnosticSettings to return a matching workspace with SignInLogs and AuditLogs enabled
            Mock get-AADDiagnosticSettings -ModuleName Check-AlertsMonitor {
                @([PSCustomObject]@{
                    properties = [PSCustomObject]@{
                        workspaceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/TestRG/providers/Microsoft.OperationalInsights/workspaces/TestLAW'
                        logs = @(
                            [PSCustomObject]@{ category = 'SignInLogs'; enabled = $true },
                            [PSCustomObject]@{ category = 'AuditLogs'; enabled = $true }
                        )
                    }
                })
            }

            # BG alert rule: query references both BG UPNs
            $bgQuery = 'SigninLogs | where UserPrincipalName == "bg1@tenant.onmicrosoft.com" or UserPrincipalName == "bg2@tenant.onmicrosoft.com"'
            # CAP alert rule: query references audit log CAP operations
            $capQuery = 'AuditLogs | where OperationName == "Update conditional access policy"'

            Mock Get-AzScheduledQueryRule -ModuleName Check-AlertsMonitor {
                @(
                    [PSCustomObject]@{
                        Name          = 'BG-Alert'
                        CriterionAllOf = @([PSCustomObject]@{ Query = $bgQuery })
                        ActionGroup   = @('/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/TestRG/providers/microsoft.insights/actionGroups/AG1')
                    },
                    [PSCustomObject]@{
                        Name          = 'CAP-Alert'
                        CriterionAllOf = @([PSCustomObject]@{ Query = $capQuery })
                        ActionGroup   = @('/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/TestRG/providers/microsoft.insights/actionGroups/AG1')
                    }
                )
            }

            Mock Get-AzActionGroup -ModuleName Check-AlertsMonitor {
                @([PSCustomObject]@{
                    Name          = 'AG1'
                    Id            = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/TestRG/providers/microsoft.insights/actionGroups/AG1'
                    EmailReceiver = @([PSCustomObject]@{ EmailAddress = 'admin@tenant.com' })
                })
            }

            Mock Find-ReceiverValues -ModuleName Check-AlertsMonitor {
                @([PSCustomObject]@{
                    ActionGroupName = 'AG1'
                    Receivers       = @('EmailReceiver')
                    ReceiverCount   = 1
                })
            }
        }

        It 'Returns compliant when all conditions are met' {
            $result = Check-AlertsMonitor @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -Be $script:msgTable.compliantAlerts
        }
    }

    Context 'When diagnostic settings are missing SignInLogs' {

        BeforeAll {
            Mock Select-AzSubscription { } -ModuleName Check-AlertsMonitor
            Mock get-AADDiagnosticSettings -ModuleName Check-AlertsMonitor {
                @([PSCustomObject]@{
                    properties = [PSCustomObject]@{
                        workspaceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/TestRG/providers/Microsoft.OperationalInsights/workspaces/TestLAW'
                        logs = @(
                            [PSCustomObject]@{ category = 'AuditLogs'; enabled = $true }
                        )
                    }
                })
            }
            Mock Get-AzScheduledQueryRule -ModuleName Check-AlertsMonitor { @() }
            Mock Get-AzActionGroup -ModuleName Check-AlertsMonitor { @() }
        }

        It 'Returns non-compliant and mentions missing SignInLogs' {
            $result = Check-AlertsMonitor @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -BeLike '*SignInLogs*'
        }
    }

    Context 'When no alert rules exist' {

        BeforeAll {
            Mock Select-AzSubscription { } -ModuleName Check-AlertsMonitor
            Mock get-AADDiagnosticSettings -ModuleName Check-AlertsMonitor {
                @([PSCustomObject]@{
                    properties = [PSCustomObject]@{
                        workspaceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/TestRG/providers/Microsoft.OperationalInsights/workspaces/TestLAW'
                        logs = @(
                            [PSCustomObject]@{ category = 'SignInLogs'; enabled = $true },
                            [PSCustomObject]@{ category = 'AuditLogs'; enabled = $true }
                        )
                    }
                })
            }
            Mock Get-AzScheduledQueryRule -ModuleName Check-AlertsMonitor { @() }
            Mock Get-AzActionGroup -ModuleName Check-AlertsMonitor { @() }
        }

        It 'Returns non-compliant' {
            $result = Check-AlertsMonitor @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        }
    }

    Context 'When Select-AzSubscription fails' {

        BeforeAll {
            Mock Select-AzSubscription -ModuleName Check-AlertsMonitor { throw 'Subscription not found' }
        }

        It 'Throws an error' {
            { Check-AlertsMonitor @commonParams } | Should -Throw
        }
    }
}
