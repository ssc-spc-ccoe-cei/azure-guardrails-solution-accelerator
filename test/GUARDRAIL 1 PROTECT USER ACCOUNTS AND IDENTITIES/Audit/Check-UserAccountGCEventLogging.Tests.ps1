BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'
    $script:dependencyNames = @('Select-AzSubscription', 'Get-AzOperationalInsightsWorkspace', 'get-AADDiagnosticSettings', 'Get-AzResourceLock', 'Invoke-AzOperationalInsightsQuery', 'Add-ProfileInformation')
    $script:previousFunctions = @{}
    foreach ($name in $script:dependencyNames) {
        $script:previousFunctions[$name] = if (Test-Path "Function:\$name") { (Get-Item "Function:\$name").ScriptBlock } else { $null }
    }
    function global:Select-AzSubscription { [CmdletBinding()] param($Subscription) throw 'Unmocked subscription dependency' }
    function global:Get-AzOperationalInsightsWorkspace { [CmdletBinding()] param($ResourceGroupName, $Name) throw 'Unmocked workspace dependency' }
    function global:get-AADDiagnosticSettings { throw 'Unmocked diagnostics dependency' }
    function global:Get-AzResourceLock { [CmdletBinding()] param($ResourceGroupName, $ResourceName, $ResourceType) throw 'Unmocked lock dependency' }
    function global:Invoke-AzOperationalInsightsQuery { [CmdletBinding()] param($WorkspaceId, $Query) throw 'Unmocked query dependency' }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) throw 'Unmocked profile dependency' }
    $script:previousModules = @(Get-Module Check-UserAccountGCEventLogging)
    $modulePath = Join-Path $PSScriptRoot '../../../src/GUARDRAIL 1 PROTECT USER ACCOUNTS AND IDENTITIES/Audit/Check-UserAccountGCEventLogging.psm1'
    $script:testModule = Import-Module $modulePath -PassThru
    $script:lawId = '/subscriptions/sub-001/resourceGroups/rg-001/providers/Microsoft.OperationalInsights/workspaces/law-001'
    $script:params = @{
        LAWResourceId = $script:lawId; RequiredRetentionDays = 90
        ControlName = 'GUARDRAIL 1'; ItemName = 'GC event logging'; itsgcode = 'AU-2'; ReportTime = '2026-10-14'
        msgTable = @{
            retentionNotMet = 'Retention missing for {0}. '; logsNotCollected = 'Logs missing.'
            lockLevelApproved = 'Approved lock on {0}: {1}. '; lockLevelNotApproved = 'Bad lock on {0}: {1}. '
            tagFound = 'Sentinel tag on {0}. '; sentinelTablesFound = 'Sentinel tables on {0}. '
            noLockNoTagNoTables = 'Unprotected {0}. '; nonCompliantLaw = 'Missing workspace {0}. '
            gcEventLoggingCompliantComment = 'Logging compliant.'
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

Describe 'GC logging helpers' {
    It 'Parses subscription, resource group and workspace names' {
        $info = Get-ResourceIdInfo -Id $script:lawId
        $info.SubscriptionId | Should -Be 'sub-001'
        $info.ResourceGroupName | Should -Be 'rg-001'
        $info.Name | Should -Be 'law-001'
    }

    It 'Checks all three Sentinel tables with zero-row queries and records only non-semantic failures' {
        Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-UserAccountGCEventLogging {
            param($Query)
            switch ($Query) {
                'SecurityIncident | take 0' { @{ Results = @() } }
                'HuntingBookmark | take 0' { throw 'table does not exist' }
                'SentinelHealth | take 0' { throw 'permission denied' }
            }
        }
        $result = Test-SentinelTables -Workspace @{ CustomerId = 'workspace-guid' }
        $result.HasAny | Should -BeTrue
        @($result.Found).Count | Should -Be 1
        $result.Found[0] | Should -Be 'SecurityIncident'
        $result.Checked.Count | Should -Be 3
        $result.Errors.Count | Should -Be 1
        $result.Errors[0] | Should -Be 'SentinelHealth: permission denied'
        Should -Invoke Invoke-AzOperationalInsightsQuery -ModuleName Check-UserAccountGCEventLogging -Times 3 -Exactly -ParameterFilter {
            $WorkspaceId -eq 'workspace-guid' -and $Query -match '^(SecurityIncident|HuntingBookmark|SentinelHealth) \| take 0$'
        }
    }

    It 'Returns no Sentinel tables and no notes when all tables are absent' {
        Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-UserAccountGCEventLogging { throw 'table does not exist' }
        $result = Test-SentinelTables -Workspace @{ CustomerId = 'workspace-guid' }
        $result.HasAny | Should -BeFalse
        $result.Found.Count | Should -Be 0
        $result.Errors.Count | Should -Be 0
    }

    It 'Treats a nonthrowing response with an Error property as an existing table (current behavior)' {
        Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-UserAccountGCEventLogging { @{ Error = 'does not exist'; Results = $null } }
        $result = Test-SentinelTables -Workspace @{ CustomerId = 'workspace-guid' }
        $result.HasAny | Should -BeTrue
        $result.Found.Count | Should -Be 3
    }

    It 'Desired behavior: rejects query Error responses even when the cmdlet does not throw' -Skip {
        Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-UserAccountGCEventLogging { @{ Error = 'does not exist'; Results = $null } }
        (Test-SentinelTables -Workspace @{ CustomerId = 'workspace-guid' }).HasAny | Should -BeFalse
    }
}

Describe 'Check-UserAccountGCEventLogging' {
    BeforeEach {
        $script:workspace = [pscustomobject]@{ RetentionInDays = 90; CustomerId = 'workspace-guid'; Tags = @{} }
        $script:logs = @('AuditLogs', 'SignInLogs', 'ManagedIdentitySignInLogs', 'RiskyUsers', 'MicrosoftGraphActivityLogs')
        $script:settingsId = $script:lawId
        $script:lockLevel = 'CanNotDelete'
        Mock Select-AzSubscription -ModuleName Check-UserAccountGCEventLogging {}
        Mock Get-AzOperationalInsightsWorkspace -ModuleName Check-UserAccountGCEventLogging { $script:workspace }
        Mock get-AADDiagnosticSettings -ModuleName Check-UserAccountGCEventLogging {
            @{ properties = @{ workspaceId = $script:settingsId; logs = @($script:logs | ForEach-Object { @{ category = $_; enabled = $true } }) } }
        }
        Mock Get-AzResourceLock -ModuleName Check-UserAccountGCEventLogging {
            if ($script:lockLevel) { @{ Properties = @{ level = $script:lockLevel } } }
        }
        Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-UserAccountGCEventLogging { throw 'table does not exist' }
    }

    It 'Is compliant at the exact retention threshold and retains all result metadata' {
        $output = @(Check-UserAccountGCEventLogging @script:params)
        $output.Count | Should -Be 1
        $result = $output[0]
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'Logging compliant.'
        $result.Errors.Count | Should -Be 0
        foreach ($name in 'ControlName', 'ItemName', 'itsgcode', 'ReportTime') {
            $result.ComplianceResults.$name | Should -Be $script:params[$name]
        }
        Should -Invoke Select-AzSubscription -ModuleName Check-UserAccountGCEventLogging -Times 1 -Exactly -ParameterFilter { $Subscription -eq 'sub-001' }
        Should -Invoke Get-AzOperationalInsightsWorkspace -ModuleName Check-UserAccountGCEventLogging -Times 1 -Exactly -ParameterFilter { $ResourceGroupName -eq 'rg-001' -and $Name -eq 'law-001' }
        Should -Invoke Get-AzResourceLock -ModuleName Check-UserAccountGCEventLogging -Times 1 -Exactly -ParameterFilter {
            $ResourceGroupName -eq 'rg-001' -and $ResourceName -eq 'law-001' -and $ResourceType -eq 'Microsoft.OperationalInsights/workspaces'
        }
        Should -Invoke Invoke-AzOperationalInsightsQuery -ModuleName Check-UserAccountGCEventLogging -Times 0 -Exactly
    }

    It 'Evaluates retention <Days> against 90 days' -ForEach @(
        @{ Days = 0; Compliant = $false }, @{ Days = 89; Compliant = $false },
        @{ Days = 90; Compliant = $true }, @{ Days = 91; Compliant = $true }
    ) {
        $script:workspace.RetentionInDays = $Days
        $result = Check-UserAccountGCEventLogging @script:params
        $result.ComplianceResults.ComplianceStatus | Should -Be $Compliant
        if (-not $Compliant) { $result.ComplianceResults.Comments | Should -BeLike '*Retention missing for law-001*' }
        $result.Errors.Count | Should -Be 0
    }

    It 'Rejects a missing required category <Category>' -ForEach @(
        @{ Category = 'AuditLogs' }, @{ Category = 'SignInLogs' }, @{ Category = 'ManagedIdentitySignInLogs' },
        @{ Category = 'RiskyUsers' }, @{ Category = 'MicrosoftGraphActivityLogs' }
    ) {
        $script:logs = @($script:logs | Where-Object { $_ -ne $Category })
        $result = Check-UserAccountGCEventLogging @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -BeLike "*Missing logs: $Category*"
    }

    It 'Rejects diagnostics targeted at a different workspace' {
        $script:settingsId = '/another/workspace'
        $result = Check-UserAccountGCEventLogging @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -BeLike '*AuditLogs, SignInLogs, ManagedIdentitySignInLogs, RiskyUsers, MicrosoftGraphActivityLogs*'
    }

    It 'Rejects empty diagnostics and disabled log categories' {
        Mock get-AADDiagnosticSettings -ModuleName Check-UserAccountGCEventLogging { @() }
        (Check-UserAccountGCEventLogging @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
        Mock get-AADDiagnosticSettings -ModuleName Check-UserAccountGCEventLogging {
            @{ properties = @{ workspaceId = $script:lawId; logs = @(@{ category = 'AuditLogs'; enabled = $false }) } }
        }
        $result = Check-UserAccountGCEventLogging @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -BeLike '*Missing logs: AuditLogs,*'
    }

    It 'Accepts either approved lock, including when multiple levels are present' -ForEach @(
        @{ Levels = @('ReadOnly') }, @{ Levels = @('CanNotDelete') }, @{ Levels = @('Other', 'ReadOnly') }
    ) {
        $script:lockLevel = $Levels
        (Check-UserAccountGCEventLogging @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
        Should -Invoke Invoke-AzOperationalInsightsQuery -ModuleName Check-UserAccountGCEventLogging -Times 0 -Exactly
    }

    It 'Accepts sentinel=true case-insensitively as the lock fallback' {
        $script:lockLevel = $null
        $script:workspace.Tags = @{ sentinel = 'TRUE' }
        (Check-UserAccountGCEventLogging @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
        Should -Invoke Invoke-AzOperationalInsightsQuery -ModuleName Check-UserAccountGCEventLogging -Times 0 -Exactly
    }

    It 'Falls back to actual Sentinel queries when no approved lock or true tag exists' {
        $script:lockLevel = 'Other'
        $script:workspace.Tags = @{ sentinel = 'false' }
        Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-UserAccountGCEventLogging {
            param($Query)
            if ($Query -eq 'SentinelHealth | take 0') { @{ Results = @() } } else { throw 'table does not exist' }
        }
        (Check-UserAccountGCEventLogging @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
        Should -Invoke Invoke-AzOperationalInsightsQuery -ModuleName Check-UserAccountGCEventLogging -Times 3 -Exactly
    }

    It 'Is noncompliant without a lock, tag or Sentinel tables' {
        $script:lockLevel = $null
        $result = Check-UserAccountGCEventLogging @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -BeLike '*Unprotected law-001*'
        $result.Errors.Count | Should -Be 0
    }

    It 'Preserves table-check notes in noncompliant comments' {
        $script:lockLevel = $null
        Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-UserAccountGCEventLogging { throw 'access denied' }
        $result = Check-UserAccountGCEventLogging @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -BeLike '*Table-check notes: SecurityIncident: access denied*HuntingBookmark: access denied*SentinelHealth: access denied*'
        $result.Errors.Count | Should -Be 0
    }

    It 'Catches workspace lookup <Failure> and reports the appropriate error' -ForEach @(
        @{ Failure = 'ResourceNotFound'; Expected = '*Workspace not found*'; Comment = '*Missing workspace law-001*' },
        @{ Failure = 'access denied'; Expected = '*Error accessing*access denied*'; Comment = '' }
    ) {
        Mock Get-AzOperationalInsightsWorkspace -ModuleName Check-UserAccountGCEventLogging { throw $Failure }
        $result = Check-UserAccountGCEventLogging @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.Errors.Count | Should -Be 1
        $result.Errors[0] | Should -BeLike $Expected
        $result.ComplianceResults.Comments | Should -BeLike $Comment
        Should -Invoke get-AADDiagnosticSettings -ModuleName Check-UserAccountGCEventLogging -Times 0 -Exactly
    }

    It 'Catches diagnostic failures rather than returning compliant' {
        Mock get-AADDiagnosticSettings -ModuleName Check-UserAccountGCEventLogging { throw 'diagnostics unavailable' }
        $result = Check-UserAccountGCEventLogging @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.Errors[0] | Should -BeLike '*diagnostics unavailable*'
    }

    It 'Catches a terminating lock lookup failure' {
        Mock Get-AzResourceLock -ModuleName Check-UserAccountGCEventLogging { throw 'lock lookup denied' }
        $result = Check-UserAccountGCEventLogging @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.Errors.Count | Should -Be 1
        $result.Errors[0] | Should -BeLike '*Error accessing*lock lookup denied*'
    }

    It 'Throws a descriptive subscription selection failure before querying the workspace' {
        Mock Select-AzSubscription -ModuleName Check-UserAccountGCEventLogging { throw 'subscription denied' }
        { Check-UserAccountGCEventLogging @script:params } | Should -Throw '*Select-AzSubscription*sub-001*subscription denied*'
        Should -Invoke Get-AzOperationalInsightsWorkspace -ModuleName Check-UserAccountGCEventLogging -Times 0 -Exactly
    }

    It 'Passes resource-specific profiles and returns their in-place changes' {
        Mock Add-ProfileInformation -ModuleName Check-UserAccountGCEventLogging {
            param($Result)
            $Result | Add-Member NoteProperty Profile 2
            $Result.ComplianceStatus = 'Not Applicable'
            $Result
        }
        $result = Check-UserAccountGCEventLogging @script:params -EnableMultiCloudProfiles -CloudUsageProfiles '1,2' -ModuleProfiles '2'
        $result.ComplianceResults.Profile | Should -Be 2
        $result.ComplianceResults.ComplianceStatus | Should -Be 'Not Applicable'
        Should -Invoke Add-ProfileInformation -ModuleName Check-UserAccountGCEventLogging -Times 1 -Exactly -ParameterFilter {
            $SubscriptionId -eq 'sub-001' -and $CloudUsageProfiles -eq '1,2' -and $ModuleProfiles -eq '2' -and $ErrorList.Count -eq 0
        }
    }

    It 'Passes accumulated workspace errors to profile evaluation' {
        Mock Get-AzOperationalInsightsWorkspace -ModuleName Check-UserAccountGCEventLogging { throw 'ResourceNotFound' }
        Mock Add-ProfileInformation -ModuleName Check-UserAccountGCEventLogging { param($Result) $Result }
        $result = Check-UserAccountGCEventLogging @script:params -EnableMultiCloudProfiles
        $result.Errors.Count | Should -Be 1
        Should -Invoke Add-ProfileInformation -ModuleName Check-UserAccountGCEventLogging -Times 1 -Exactly -ParameterFilter {
            $CloudUsageProfiles -eq '3' -and $ErrorList.Count -eq 1 -and $ErrorList[0] -like '*Workspace not found*'
        }
    }
}
