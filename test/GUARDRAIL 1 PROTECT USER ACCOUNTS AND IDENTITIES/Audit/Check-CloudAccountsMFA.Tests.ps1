BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'
    $script:savedFunctions = @{}
    foreach ($name in @('Invoke-GraphQueryEX', 'Add-ProfileInformation', 'Check-CloudAccountsMFA')) {
        $script:savedFunctions[$name] = if (Test-Path "Function:\$name") { (Get-Item "Function:\$name").ScriptBlock } else { $null }
    }
    function global:Invoke-GraphQueryEX { [CmdletBinding()] param($urlPath) throw 'Unmocked Graph call' }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) throw 'Unmocked profile call' }
    $script:testedModule = Import-Module (Join-Path $PSScriptRoot '../../../src/GUARDRAIL 1 PROTECT USER ACCOUNTS AND IDENTITIES/Audit/Check-CloudAccountsMFA.psm1') -Force -PassThru
}
AfterAll {
    Remove-Module $script:testedModule -Force -ErrorAction SilentlyContinue
    foreach ($name in $script:savedFunctions.Keys) {
        Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
        if ($null -ne $script:savedFunctions[$name]) { Set-Item "Function:\global:$name" $script:savedFunctions[$name] }
    }
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-CloudAccountsMFA' {
    BeforeAll {
        $script:params = @{
            ControlName = 'GUARDRAIL 1'; ItemName = 'Cloud accounts MFA'; itsgcode = 'IA-2'; ReportTime = '2026-10-01'
            msgTable = @{ mfaRequiredForAllUsers = 'All users require MFA.'; noMFAPolicyForAllUsers = 'No qualifying MFA policy.' }
        }
        function New-MfaPolicy {
            [pscustomobject]@{
                id = 'policy-001'; displayName = 'Require MFA'; state = 'enabled'
                grantControls = [pscustomobject]@{ operator = 'AND'; builtInControls = @('mfa') }
                conditions = [pscustomobject]@{
                    users = [pscustomobject]@{ includeUsers = @('All'); excludeUsers = @() }
                    applications = [pscustomobject]@{ includeApplications = @('All'); excludeApplications = @() }
                    clientAppTypes = @('all'); userRiskLevels = @(); signInRiskLevels = @()
                    platforms = $null; locations = $null; devices = $null; clientApplications = $null
                }
            }
        }
    }
    BeforeEach {
        $script:policies = @(New-MfaPolicy)
        Mock Invoke-GraphQueryEX -ModuleName Check-CloudAccountsMFA { [pscustomobject]@{ StatusCode = 200; Content = [pscustomobject]@{ value = $script:policies } } }
        Mock Add-ProfileInformation -ModuleName Check-CloudAccountsMFA { throw 'Unexpected profile call' }
    }

    It 'Returns a compliant row with metadata and queries the paginated helper exactly once' {
        $result = Check-CloudAccountsMFA @script:params
        @($result).Count | Should -Be 1
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be $script:params.msgTable.mfaRequiredForAllUsers
        foreach ($name in @('ControlName', 'ItemName', 'itsgcode', 'ReportTime')) { $result.ComplianceResults.$name | Should -Be $script:params[$name] }
        $result.Errors.Count | Should -Be 0
        $result.AdditionalResults | Should -BeNullOrEmpty
        Should -Invoke Invoke-GraphQueryEX -ModuleName Check-CloudAccountsMFA -Exactly -Times 1 -ParameterFilter { $urlPath -eq '/identity/conditionalAccess/policies' }
        Should -Invoke Add-ProfileInformation -ModuleName Check-CloudAccountsMFA -Times 0
    }

    It 'Rejects policies with <Restriction>' -ForEach @(
        @{ Restriction = 'disabled' }, @{ Restriction = 'report-only' }, @{ Restriction = 'specific users' },
        @{ Restriction = 'specific application' }, @{ Restriction = 'no grant controls' }, @{ Restriction = 'password only' },
        @{ Restriction = 'partial clients' }, @{ Restriction = 'user risk' }, @{ Restriction = 'sign-in risk' },
        @{ Restriction = 'partial platforms' }, @{ Restriction = 'missing linux' }, @{ Restriction = 'location' },
        @{ Restriction = 'device' }, @{ Restriction = 'client application' }
    ) {
        $policy = $script:policies[0]
        switch ($Restriction) {
            'disabled' { $policy.state = 'disabled' }
            'report-only' { $policy.state = 'enabledForReportingButNotEnforced' }
            'specific users' { $policy.conditions.users.includeUsers = @('user-001') }
            'specific application' { $policy.conditions.applications.includeApplications = @('app-001') }
            'no grant controls' { $policy.grantControls = $null }
            'password only' { $policy.grantControls.builtInControls = @('compliantDevice') }
            'partial clients' { $policy.conditions.clientAppTypes = @('browser', 'mobileAppsAndDesktopClients', 'exchangeActiveSync') }
            'user risk' { $policy.conditions.userRiskLevels = @('high') }
            'sign-in risk' { $policy.conditions.signInRiskLevels = @('medium') }
            'partial platforms' { $policy.conditions.platforms = [pscustomobject]@{ includePlatforms = @('windows') } }
            'missing linux' { $policy.conditions.platforms = [pscustomobject]@{ includePlatforms = @('android', 'iOS', 'windows', 'macOS') } }
            'location' { $policy.conditions.locations = [pscustomobject]@{ includeLocations = @('AllTrusted') } }
            'device' { $policy.conditions.devices = [pscustomobject]@{ deviceFilter = [pscustomobject]@{ mode = 'include'; rule = 'device.isCompliant -eq True' } } }
            'client application' { $policy.conditions.clientApplications = [pscustomobject]@{ includeServicePrincipals = @('sp-001') } }
        }
        $result = Check-CloudAccountsMFA @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be $script:params.msgTable.noMFAPolicyForAllUsers
        $result.Errors.Count | Should -Be 0
    }

    It 'Accepts the complete explicit client/platform lists and admin portal application' {
        $script:policies[0].conditions.clientAppTypes = @('browser', 'mobileAppsAndDesktopClients', 'exchangeActiveSync', 'other')
        $script:policies[0].conditions.platforms = [pscustomobject]@{ includePlatforms = @('android', 'iOS', 'windows', 'macOS', 'linux') }
        $script:policies[0].conditions.applications.includeApplications = @('MicrosoftAdminPortals')
        (Check-CloudAccountsMFA @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Accepts the all-platforms sentinel' {
        $script:policies[0].conditions.platforms = [pscustomobject]@{ includePlatforms = @('all') }
        (Check-CloudAccountsMFA @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Evaluates authentication strength <Shape> as <Expected>' -ForEach @(
        @{ Shape = 'string'; Expected = $true }, @{ Shape = 'id'; Expected = $true }, @{ Shape = 'displayName'; Expected = $true },
        @{ Shape = 'null'; Expected = $false }, @{ Shape = 'empty string'; Expected = $false }, @{ Shape = 'whitespace'; Expected = $false },
        @{ Shape = 'empty object'; Expected = $false }, @{ Shape = 'blank properties'; Expected = $false }
    ) {
        $strength = switch ($Shape) {
            'string' { 'strength-001' }
            'id' { [pscustomobject]@{ id = 'strength-001' } }
            'displayName' { [pscustomobject]@{ displayName = 'Phishing-resistant MFA' } }
            'null' { $null }
            'empty string' { '' }
            'whitespace' { '   ' }
            'empty object' { [pscustomobject]@{} }
            'blank properties' { [pscustomobject]@{ id = ' '; displayName = '' } }
        }
        $script:policies[0].grantControls = [pscustomobject]@{ builtInControls = @(); authenticationStrength = $strength }
        (Check-CloudAccountsMFA @script:params).ComplianceResults.ComplianceStatus | Should -Be $Expected
    }

    It 'Accepts built-in MFA even when authentication strength is null' {
        $script:policies[0].grantControls | Add-Member authenticationStrength $null
        (Check-CloudAccountsMFA @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Requires a single policy to meet every requirement rather than combining partial policies' {
        $first = New-MfaPolicy
        $first.conditions.users.includeUsers = @('user-001')
        $second = New-MfaPolicy
        $second.grantControls.builtInControls = @('compliantDevice')
        $script:policies = @($first, $second)
        (Check-CloudAccountsMFA @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
        $script:policies += New-MfaPolicy
        (Check-CloudAccountsMFA @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Returns noncompliant for empty or absent content: <Shape>' -ForEach @(@{ Shape = 'empty' }, @{ Shape = 'null content' }, @{ Shape = 'null response' }) {
        $script:shape = $Shape
        Mock Invoke-GraphQueryEX -ModuleName Check-CloudAccountsMFA {
            switch ($script:shape) {
                'empty' { [pscustomobject]@{ Content = [pscustomobject]@{ value = @() } } }
                'null content' { [pscustomobject]@{ Content = $null; StatusCode = 503; Error = 'Unavailable' } }
                'null response' { $null }
            }
        }
        $result = Check-CloudAccountsMFA @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be $script:params.msgTable.noMFAPolicyForAllUsers
        $result.Errors.Count | Should -Be 0
    }

    It 'Records Graph exceptions (current behavior also leaks ArrayList.Add index onto the success stream)' {
        Mock Invoke-GraphQueryEX -ModuleName Check-CloudAccountsMFA { throw 'Graph unavailable' }
        $output = @(Check-CloudAccountsMFA @script:params -WarningAction SilentlyContinue)
        $output.Count | Should -Be 2
        $output[0] | Should -Be 0
        $result = $output[-1]
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.Errors.Count | Should -Be 1
        $result.Errors[0] | Should -Match '/identity/conditionalAccess/policies.*Graph unavailable'
    }

    It 'Currently accepts excluded users and OR grants even though MFA is not required for all users' {
        $script:policies[0].conditions.users.excludeUsers = @('unprotected-user')
        $script:policies[0].grantControls.operator = 'OR'
        $script:policies[0].grantControls.builtInControls = @('mfa', 'compliantDevice')
        (Check-CloudAccountsMFA @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Passes profile arguments and returns in-place profile mutations and diagnostics' {
        Mock Add-ProfileInformation -ModuleName Check-CloudAccountsMFA {
            param($Result, $ErrorList)
            $Result | Add-Member Profile 2
            $Result.ComplianceStatus = 'Not Applicable'
            [void]$ErrorList.Add('Profile diagnostic')
            $Result
        }
        $result = Check-CloudAccountsMFA @script:params -EnableMultiCloudProfiles -CloudUsageProfiles '2,3' -ModuleProfiles '1,2'
        $result.ComplianceResults.Profile | Should -Be 2
        $result.ComplianceResults.ComplianceStatus | Should -Be 'Not Applicable'
        $result.Errors | Should -Contain 'Profile diagnostic'
        Should -Invoke Add-ProfileInformation -ModuleName Check-CloudAccountsMFA -Exactly -Times 1 -ParameterFilter {
            $CloudUsageProfiles -eq '2,3' -and $ModuleProfiles -eq '1,2' -and [string]::IsNullOrEmpty($SubscriptionId) -and $ErrorList -is [System.Collections.ArrayList]
        }
    }

    It 'Currently ignores a replacement profile row instead of returning it' {
        Mock Add-ProfileInformation -ModuleName Check-CloudAccountsMFA { [pscustomobject]@{ ComplianceStatus = 'Not Applicable'; Profile = 2 } }
        $result = Check-CloudAccountsMFA @script:params -EnableMultiCloudProfiles
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.PSObject.Properties.Name | Should -Not -Contain 'Profile'
    }

    It 'Propagates profile exceptions' {
        Mock Add-ProfileInformation -ModuleName Check-CloudAccountsMFA { throw 'Profile failure' }
        { Check-CloudAccountsMFA @script:params -EnableMultiCloudProfiles } | Should -Throw '*Profile failure*'
    }
}
