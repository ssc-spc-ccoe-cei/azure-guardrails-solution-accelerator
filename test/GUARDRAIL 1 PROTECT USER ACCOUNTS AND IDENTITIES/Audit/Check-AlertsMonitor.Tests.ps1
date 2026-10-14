BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'
    $script:dependencyNames = @('Select-AzSubscription', 'get-AADDiagnosticSettings', 'Get-AzScheduledQueryRule', 'Get-AzActionGroup', 'Add-ProfileInformation')
    $script:previousFunctions = @{}
    foreach ($name in $script:dependencyNames) {
        $script:previousFunctions[$name] = if (Test-Path "Function:\$name") { (Get-Item "Function:\$name").ScriptBlock } else { $null }
    }
    function global:Select-AzSubscription { [CmdletBinding()] param($Subscription) throw 'Unmocked subscription dependency' }
    function global:get-AADDiagnosticSettings { throw 'Unmocked diagnostics dependency' }
    function global:Get-AzScheduledQueryRule { [CmdletBinding()] param($ResourceGroupName) throw 'Unmocked alert dependency' }
    function global:Get-AzActionGroup { [CmdletBinding()] param($ResourceGroupName) throw 'Unmocked action group dependency' }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) throw 'Unmocked profile dependency' }
    $script:previousModules = @(Get-Module Check-AlertsMonitor)
    $modulePath = Join-Path $PSScriptRoot '../../../src/GUARDRAIL 1 PROTECT USER ACCOUNTS AND IDENTITIES/Audit/Check-AlertsMonitor.psm1'
    $script:testModule = Import-Module $modulePath -PassThru
    # CLR properties exercise the Property filter; PSCustomObject NoteProperties do not.
    $typeName = 'GR1AlertsFixture_' + [guid]::NewGuid().ToString('N')
    $script:actionGroupType = Add-Type -PassThru -TypeDefinition @"
public class $typeName {
    public string Name { get; set; }
    public string Id { get; set; }
    public object[] EmailReceiver { get; set; }
    public object[] SmsReceiver { get; set; }
    public object[] WebhookReceiver { get; set; }
    public object[] Other { get; set; }
}
"@
    $script:lawId = '/subscriptions/sub-001/resourceGroups/rg-001/providers/Microsoft.OperationalInsights/workspaces/law-001'
    $script:bgQuery = 'SigninLogs | where UserPrincipalName == "bg.one@example.test" or UserPrincipalName =~ "bg.two@example.test"'
    $script:capQuery = 'AuditLogs | where OperationName in ("Update conditional access policy", "Add conditional access policy", "Delete conditional access policy")'
    $script:params = @{
        LAWResourceId = $script:lawId; FirstBreakGlassUPN = 'bg.one@example.test'; SecondBreakGlassUPN = 'bg.two@example.test'
        ControlName = 'GUARDRAIL 1'; ItemName = 'Alerts monitoring'; itsgcode = 'AU-6'; ReportTime = '2026-10-14'
        msgTable = @{
            signInlogsNotCollected = 'Signins missing. '; auditlogsNotCollected = 'Audit missing. '
            nonCompliantLaw = 'Missing workspace {0}. '; noAlertRules = 'No alerts in {0}. '
            noActionGroups = 'No action groups in {0}. '; noActionGroupsForBGaccts = 'BG receivers missing. '
            noAlertRuleforBGaccts = 'BG alert missing. '; noAlertRuleforCaps = 'CAP alert missing. '
            noActionGroupsForAuditLogs = 'CAP receivers missing. '; compliantAlerts = 'Alerts compliant.'
            isNotCompliant = 'Noncompliant.'
        }
    }
}

AfterAll {
    if ($script:previousModules.Count -eq 0) { Remove-Module $script:testModule -ErrorAction SilentlyContinue }
    foreach ($name in $script:dependencyNames) {
        if ($null -ne $script:previousFunctions[$name]) {
            Set-Item "Function:\global:$name" -Value $script:previousFunctions[$name]
        } else { Remove-Item "Function:\$name" -ErrorAction SilentlyContinue }
    }
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Find-ReceiverValues' {
    It 'Includes only nonempty CLR receiver properties and counts receiver types, not individual recipients' {
        $group = [Activator]::CreateInstance($script:actionGroupType)
        $group.Name = 'configured'
        $group.EmailReceiver = @('one@example.test', 'two@example.test')
        $group.SmsReceiver = @('555-0100')
        $group.WebhookReceiver = @()
        $group.Other = @('not a receiver')
        $empty = [Activator]::CreateInstance($script:actionGroupType)
        $empty.Name = 'empty'
        $group.PSObject.Properties['EmailReceiver'].MemberType | Should -Be 'Property'
        $result = @(Find-ReceiverValues -actionGroups @($null, $group, $empty))
        $result.Count | Should -Be 1
        $result[0].ActionGroupName | Should -Be 'configured'
        $result[0].ReceiverCount | Should -Be 2
        $result[0].Receivers.Name | Should -Contain 'EmailReceiver'
        $result[0].Receivers.Name | Should -Contain 'SmsReceiver'
        $result[0].Receivers.Name | Should -Not -Contain 'Other'
        $result[0].Receivers.Name | Should -Not -Contain 'WebhookReceiver'
    }

    It 'Does not confuse NoteProperty fixtures with Azure CLR properties' {
        $group = [pscustomobject]@{ Name = 'note'; EmailReceiver = @('one@example.test') }
        $group.PSObject.Properties['EmailReceiver'].MemberType | Should -Be 'NoteProperty'
        @(Find-ReceiverValues -actionGroups @($group)).Count | Should -Be 0
    }

    It 'Reports an error and emits no receivers for <Label> input' -ForEach @(
        @{ Label = 'null'; Groups = $null }, @{ Label = 'empty'; Groups = @() }
    ) {
        $output = @(Find-ReceiverValues -actionGroups $Groups 2>&1)
        $output.Count | Should -Be 1
        $output[0] | Should -BeOfType ([System.Management.Automation.ErrorRecord])
        $output[0].ToString() | Should -BeLike '*No action groups provided*'
    }

    It 'Catches receiver inspection failures and identifies the action group' {
        $group = [Activator]::CreateInstance($script:actionGroupType)
        $group.Name = 'broken-group'
        $group.EmailReceiver = @('alerts@example.test')
        Mock Where-Object -ModuleName Check-AlertsMonitor { throw 'receiver inspection failed' } -ParameterFilter {
            $FilterScript.ToString() -like '*MemberType*'
        }
        $output = @(Find-ReceiverValues -actionGroups @($group) 2>&1)
        $output.Count | Should -Be 1
        $output[0] | Should -BeOfType ([System.Management.Automation.ErrorRecord])
        $output[0].ToString() | Should -BeLike '*Error processing action group broken-group*receiver inspection failed*'
    }
}

Describe 'CompareKQLQueryToPattern' {
    It 'Matches case-insensitively using the supplied regex' {
        CompareKQLQueryToPattern -pattern 'signinlogs\s*\|' -targetQuery 'SIGNINLOGS | take 1' | Should -BeTrue
        CompareKQLQueryToPattern -pattern '^AuditLogs' -targetQuery 'SigninLogs | take 1' | Should -BeFalse
    }

    It 'Rejects blank <Label>' -ForEach @(
        @{ Label = 'pattern'; Pattern = ''; Query = 'SigninLogs' },
        @{ Label = 'query'; Pattern = 'SigninLogs'; Query = ' ' }
    ) {
        CompareKQLQueryToPattern -pattern $Pattern -targetQuery $Query -WarningAction SilentlyContinue | Should -BeFalse
    }

    It 'Catches invalid regex syntax and returns false with an error' {
        $output = @(CompareKQLQueryToPattern -pattern '[' -targetQuery 'SigninLogs' 2>&1)
        $output.Count | Should -Be 2
        $output[0].ToString() | Should -BeLike '*Error in pattern matching*'
        $output[1] | Should -BeFalse
    }
}

Describe 'Check-AlertsMonitor' {
    BeforeEach {
        $script:group = [Activator]::CreateInstance($script:actionGroupType)
        $script:group.Name = 'notifications'
        $script:group.Id = '/ACTIONGROUPS/NOTIFICATIONS'
        $script:group.EmailReceiver = @('alerts@example.test')
        $script:rules = @(
            [pscustomobject]@{ Enabled = $true; Scope = @($script:lawId); CriterionAllOf = @(@{ Query = $script:bgQuery }); ActionGroup = @('/actiongroups/notifications') },
            [pscustomobject]@{ Enabled = $true; Scope = @($script:lawId); CriterionAllOf = @(@{ Query = $script:capQuery }); ActionGroup = @('/ActionGroups/Notifications') }
        )
        Mock Select-AzSubscription -ModuleName Check-AlertsMonitor {}
        Mock get-AADDiagnosticSettings -ModuleName Check-AlertsMonitor {
            @{ properties = @{ workspaceId = $script:lawId; logs = @(
                @{ category = 'SignInLogs'; enabled = $true }, @{ category = 'AuditLogs'; enabled = $true }
            ) } }
        }
        Mock Get-AzScheduledQueryRule -ModuleName Check-AlertsMonitor { $script:rules }
        Mock Get-AzActionGroup -ModuleName Check-AlertsMonitor { $script:group }
    }

    It 'Uses real receiver filtering and both alert queries for compliance, retaining metadata' {
        $output = @(Check-AlertsMonitor @script:params)
        $output.Count | Should -Be 1
        $result = $output[0]
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'Alerts compliant.'
        $result.Errors.Count | Should -Be 0
        foreach ($name in 'ControlName', 'ItemName', 'itsgcode', 'ReportTime') {
            $result.ComplianceResults.$name | Should -Be $script:params[$name]
        }
        Should -Invoke Select-AzSubscription -ModuleName Check-AlertsMonitor -Times 1 -Exactly -ParameterFilter { $Subscription -eq 'sub-001' }
        Should -Invoke Get-AzScheduledQueryRule -ModuleName Check-AlertsMonitor -Times 1 -Exactly -ParameterFilter { $ResourceGroupName -eq 'rg-001' }
        Should -Invoke Get-AzActionGroup -ModuleName Check-AlertsMonitor -Times 1 -Exactly -ParameterFilter { $ResourceGroupName -eq 'rg-001' }
    }

    It 'Accepts supported two-account query form <Label>' -ForEach @(
        @{ Label = 'reverse OR'; Query = 'SigninLogs | where UserPrincipalName contains "bg.two@example.test" or UserPrincipalName == "bg.one@example.test"' },
        @{ Label = 'in list'; Query = 'SigninLogs | where UserPrincipalName in ("bg.one@example.test", "bg.two@example.test")' },
        @{ Label = 'reverse has_any'; Query = 'SIGNINLOGS | where UserPrincipalName has_any ("bg.two@example.test", "bg.one@example.test")' }
    ) {
        $script:rules[0].CriterionAllOf[0].Query = $Query
        (Check-AlertsMonitor @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Rejects insufficient or lookalike breakglass query <Label>' -ForEach @(
        @{ Label = 'one account'; Query = 'SigninLogs | where UserPrincipalName == "bg.one@example.test"' },
        @{ Label = 'same account twice'; Query = 'SigninLogs | where UserPrincipalName == "bg.one@example.test" or UserPrincipalName == "bg.one@example.test"' },
        @{ Label = 'incomplete list'; Query = 'SigninLogs | where UserPrincipalName in ("bg.one@example.test")' },
        @{ Label = 'regex metacharacters replaced'; Query = 'SigninLogs | where UserPrincipalName == "bgXone@exampleXtest" or UserPrincipalName == "bgXtwo@exampleXtest"' }
    ) {
        $script:rules[0].CriterionAllOf[0].Query = $Query
        $result = Check-AlertsMonitor @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -BeLike '*BG alert missing*'
        $result.Errors.Count | Should -Be 0
    }

    It 'Accepts supported CAP query <Label>' -ForEach @(
        @{ Label = 'single operation'; Query = 'AuditLogs | where OperationName == "Update conditional access policy"' },
        @{ Label = 'activity name'; Query = 'AuditLogs | where ActivityDisplayName contains "Add conditional access policy"' },
        @{ Label = 'reordered has_any'; Query = 'AuditLogs | where OperationName has_any ("Delete conditional access policy", "Update conditional access policy", "Add conditional access policy")' }
    ) {
        $script:rules[1].CriterionAllOf[0].Query = $Query
        (Check-AlertsMonitor @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Rejects incomplete CAP lists and alert criteria without queries' {
        $script:rules[1].CriterionAllOf[0].Query = 'AuditLogs | where OperationName in ("Update conditional access policy", "Add conditional access policy")'
        $result = Check-AlertsMonitor @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -BeLike '*CAP alert missing*'
        $script:rules[0].CriterionAllOf = @()
        $script:rules[1].CriterionAllOf = $null
        $result = Check-AlertsMonitor @script:params
        $result.ComplianceResults.Comments | Should -BeLike '*BG alert missing*CAP alert missing*'
    }

    It 'Rejects alerts with <Label> action group references' -ForEach @(
        @{ Label = 'null'; References = $null }, @{ Label = 'blank'; References = @('', ' ') },
        @{ Label = 'unconfigured'; References = @('/actiongroups/other') }
    ) {
        $script:rules[0].ActionGroup = $References
        $script:rules[1].ActionGroup = $References
        $result = Check-AlertsMonitor @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -BeLike '*BG receivers missing*CAP receivers missing*'
    }

    It 'Rejects action groups with no configured receivers but currently misclassifies the null ID conversion as retrieval failure' {
        $script:group.EmailReceiver = @()
        $result = Check-AlertsMonitor @script:params -ErrorAction SilentlyContinue
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.Errors.Count | Should -Be 1
        $result.Errors[0] | Should -BeLike '*Get-AzActionGroup*null-valued expression*'
        $result.ComplianceResults.Comments | Should -BeLike '*No action groups in rg-001*BG receivers missing*CAP receivers missing*'
    }

    It 'Desired behavior: receiver-free action groups report missing receivers, not retrieval failure (null ID is dereferenced)' -Skip {
        $script:group.EmailReceiver = @()
        $result = Check-AlertsMonitor @script:params -ErrorAction SilentlyContinue
        $result.Errors[0] | Should -BeLike '*No action groups with configured receivers*'
    }

    It 'Ignores receiver-free groups when a referenced configured group also exists' {
        $empty = [Activator]::CreateInstance($script:actionGroupType)
        $empty.Name = 'empty'
        $empty.Id = '/actiongroups/empty'
        Mock Get-AzActionGroup -ModuleName Check-AlertsMonitor { @($script:group, $empty) }
        $result = Check-AlertsMonitor @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.Errors.Count | Should -Be 0
    }

    It 'Currently accepts disabled alert rules because Enabled is not examined' {
        $script:rules[0].Enabled = $false
        $script:rules[1].Enabled = $false
        (Check-AlertsMonitor @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Desired behavior: disabled rules cannot provide monitoring (Enabled is currently ignored)' -Skip {
        $script:rules[0].Enabled = $false
        $script:rules[1].Enabled = $false
        (Check-AlertsMonitor @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
    }

    It 'Currently accepts matching alerts scoped to a different workspace' {
        $script:rules[0].Scope = @('/another/workspace')
        $script:rules[1].Scope = @('/another/workspace')
        (Check-AlertsMonitor @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Desired behavior: alert rules must monitor the supplied workspace (Scope is currently ignored)' -Skip {
        $script:rules[0].Scope = @('/another/workspace')
        $script:rules[1].Scope = @('/another/workspace')
        (Check-AlertsMonitor @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
    }

    It 'Records empty alert and action group collections without throwing' {
        Mock Get-AzScheduledQueryRule -ModuleName Check-AlertsMonitor { @() }
        Mock Get-AzActionGroup -ModuleName Check-AlertsMonitor { @() }
        $result = Check-AlertsMonitor @script:params -ErrorAction SilentlyContinue
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -BeLike '*Noncompliant*No alerts in rg-001*No action groups in rg-001*'
        $result.Errors.Count | Should -Be 2
    }

    It 'Catches Azure alert and action group retrieval failures' {
        Mock Get-AzScheduledQueryRule -ModuleName Check-AlertsMonitor { throw 'alerts denied' }
        Mock Get-AzActionGroup -ModuleName Check-AlertsMonitor { throw 'groups denied' }
        $result = Check-AlertsMonitor @script:params -ErrorAction SilentlyContinue
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.Errors.Count | Should -Be 2
        $result.Errors[0] | Should -BeLike '*Get-AzScheduledQueryRule*alerts denied*'
        $result.Errors[1] | Should -BeLike '*Get-AzActionGroup*groups denied*'
    }

    It 'Records processing failures separately for BG and CAP rules' {
        Mock CompareKQLQueryToPattern -ModuleName Check-AlertsMonitor { throw 'pattern processing failed' }
        $result = Check-AlertsMonitor @script:params -ErrorAction SilentlyContinue
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.Errors.Count | Should -Be 2
        $result.Errors[0] | Should -BeLike '*break glass*pattern processing failed*'
        $result.Errors[1] | Should -BeLike '*conditional access*pattern processing failed*'
    }

    It 'Currently reports compliant despite absent diagnostic collection when alerts match' {
        Mock get-AADDiagnosticSettings -ModuleName Check-AlertsMonitor { @() }
        $result = Check-AlertsMonitor @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'Alerts compliant.'
        $result.Errors.Count | Should -Be 0
    }

    It 'Desired behavior: missing required diagnostics must be noncompliant (flags currently ignored)' -Skip {
        Mock get-AADDiagnosticSettings -ModuleName Check-AlertsMonitor { @() }
        (Check-AlertsMonitor @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
    }

    It 'Preserves missing diagnostic category comments when alert compliance also fails' {
        Mock get-AADDiagnosticSettings -ModuleName Check-AlertsMonitor {
            @{ properties = @{ workspaceId = $script:lawId; logs = @(
                @{ category = 'AuditLogs'; enabled = $false }, @{ category = 'SignInLogs'; enabled = $false }
            ) } }
        }
        $script:rules[0].CriterionAllOf = @()
        $result = Check-AlertsMonitor @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -BeLike '*Signins missing*Missing logs: SignInLogs*Audit missing*Missing logs: AuditLogs*'
    }

    It 'Catches diagnostics <Failure> but currently leaves matching alert compliance true' -ForEach @(
        @{ Failure = 'ResourceNotFound'; Expected = '*Workspace not found*' },
        @{ Failure = 'diagnostics denied'; Expected = '*Error accessing*diagnostics denied*' }
    ) {
        Mock get-AADDiagnosticSettings -ModuleName Check-AlertsMonitor { throw $Failure }
        $result = Check-AlertsMonitor @script:params
        $result.Errors.Count | Should -Be 1
        $result.Errors[0] | Should -BeLike $Expected
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'Alerts compliant.'
    }

    It 'Throws subscription selection failures before retrieving diagnostics or alerts' {
        Mock Select-AzSubscription -ModuleName Check-AlertsMonitor { throw 'subscription denied' }
        { Check-AlertsMonitor @script:params } | Should -Throw '*Select-AzSubscription*sub-001*subscription denied*'
        Should -Invoke get-AADDiagnosticSettings -ModuleName Check-AlertsMonitor -Times 0 -Exactly
        Should -Invoke Get-AzScheduledQueryRule -ModuleName Check-AlertsMonitor -Times 0 -Exactly
    }

    It 'Passes resource-specific profiles and returns their in-place changes' {
        Mock Add-ProfileInformation -ModuleName Check-AlertsMonitor {
            param($Result)
            $Result | Add-Member NoteProperty Profile 2
            $Result.ComplianceStatus = 'Not Applicable'
            $Result
        }
        $result = Check-AlertsMonitor @script:params -EnableMultiCloudProfiles -CloudUsageProfiles '1,2' -ModuleProfiles '2'
        $result.ComplianceResults.Profile | Should -Be 2
        $result.ComplianceResults.ComplianceStatus | Should -Be 'Not Applicable'
        Should -Invoke Add-ProfileInformation -ModuleName Check-AlertsMonitor -Times 1 -Exactly -ParameterFilter {
            $SubscriptionId -eq 'sub-001' -and $CloudUsageProfiles -eq '1,2' -and $ModuleProfiles -eq '2' -and $ErrorList.Count -eq 0
        }
    }

    It 'Passes accumulated alert errors to profile evaluation' {
        Mock Get-AzScheduledQueryRule -ModuleName Check-AlertsMonitor { @() }
        Mock Add-ProfileInformation -ModuleName Check-AlertsMonitor { param($Result) $Result }
        $result = Check-AlertsMonitor @script:params -EnableMultiCloudProfiles -ErrorAction SilentlyContinue
        $result.Errors.Count | Should -Be 1
        Should -Invoke Add-ProfileInformation -ModuleName Check-AlertsMonitor -Times 1 -Exactly -ParameterFilter {
            $CloudUsageProfiles -eq '3' -and $ErrorList.Count -eq 1 -and $ErrorList[0] -like '*No alert rules found*'
        }
    }
}
