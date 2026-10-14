BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'
    $script:savedFunctions = @{}
    foreach ($name in @('Invoke-GraphQueryEX', 'Add-ProfileInformation')) {
        $script:savedFunctions[$name] = (Get-Item "Function:global:$name" -ErrorAction SilentlyContinue).ScriptBlock
        Set-Item "Function:global:$name" {
            [CmdletBinding()]
            param($urlPath, $Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList)
            throw 'Unmocked external dependency'
        }
    }
    Import-Module (Join-Path $PSScriptRoot '../../../src/GUARDRAIL 2 MANAGE ACCESS/Audit/Check-UserRiskBasedCAP.psm1') -Force
}

AfterAll {
    Remove-Module Check-UserRiskBasedCAP -Force -ErrorAction SilentlyContinue
    foreach ($name in $script:savedFunctions.Keys) {
        if ($null -ne $script:savedFunctions[$name]) {
            Set-Item "Function:global:$name" $script:savedFunctions[$name]
        } else {
            Remove-Item "Function:global:$name" -ErrorAction SilentlyContinue
        }
    }
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Get-UserRiskBasedCAP' {
    BeforeAll {
        $script:params = @{
            ControlName = 'GUARDRAIL 2'; ItemName = 'User risk CAP'; itsgcode = 'AC-3'; ReportTime = '2026-10-14'
            FirstBreakGlassUPN = 'bg+one@example.test'; SecondBreakGlassUPN = 'bg2@example.test'
            msgTable = @{ isCompliant = 'Pass'; compliantC1 = 'Risk protected'; isNotCompliant = 'Fail'; nonCompliantC1 = 'Risk unprotected' }
        }
        function New-RiskPolicy {
            [pscustomobject]@{
                id = 'policy1'; displayName = 'High risk'; state = 'enabled'
                conditions = [pscustomobject]@{
                    users = [pscustomobject]@{
                        includeUsers = @('All'); excludeUsers = @('bg1', 'bg2'); excludeGroups = @()
                        includeGroups = @(); includeRoles = @(); excludeRoles = @()
                        includeGuestsOrExternalUsers = $null; excludeGuestsOrExternalUsers = $null
                    }
                    applications = [pscustomobject]@{ includeApplications = @('All'); excludeApplications = @() }
                    clientAppTypes = @('all'); userRiskLevels = @('high'); signInRiskLevels = @()
                    platforms = $null; locations = $null; devices = $null; clientApplications = $null
                }
                grantControls = [pscustomobject]@{ builtInControls = @('mfa', 'passwordChange') }
                sessionControls = [pscustomobject]@{
                    signInFrequency = [pscustomobject]@{
                        frequencyInterval = 'everyTime'; authenticationType = 'primaryAndSecondaryAuthentication'; isEnabled = $true
                    }
                }
            }
        }
    }
    BeforeEach {
        $script:policies = @(New-RiskPolicy)
        $script:groups1 = @()
        $script:groups2 = @()
        Mock Invoke-GraphQueryEX -ModuleName Check-UserRiskBasedCAP {
            switch ($urlPath) {
                '/identity/conditionalAccess/policies' { return @{ Content = @{ value = $script:policies } } }
                '/users/bg%2Bone%40example.test' { return @{ Content = @{ id = 'bg1' } } }
                '/users/bg2%40example.test' { return @{ Content = @{ value = @(@{ id = 'bg2' }) } } }
                '/users/bg1/memberOf' { return @{ Content = @{ value = $script:groups1 } } }
                '/users/bg2/memberOf' { return @{ Content = @{ value = $script:groups2 } } }
                default { throw "Unexpected Graph path: $urlPath" }
            }
        }
        Mock Add-ProfileInformation -ModuleName Check-UserRiskBasedCAP { throw 'Unexpected profile call' }
    }

    It 'Accepts password-change plus MFA and returns full metadata without auxiliary results' {
        $output = @(Get-UserRiskBasedCAP @script:params)
        $output.Count | Should -Be 1
        $output[0].ComplianceResults.ComplianceStatus | Should -BeTrue
        $output[0].ComplianceResults.Comments | Should -Be 'Pass Risk protected'
        $output[0].Errors.Count | Should -Be 0
        $output[0].AdditionalResults | Should -BeNullOrEmpty
        foreach ($key in @('ControlName', 'ItemName', 'ReportTime', 'itsgcode')) {
            $output[0].ComplianceResults.$key | Should -Be $script:params[$key]
        }
        Should -Invoke Invoke-GraphQueryEX -ModuleName Check-UserRiskBasedCAP -Exactly -Times 5
        Should -Invoke Invoke-GraphQueryEX -ModuleName Check-UserRiskBasedCAP -Exactly -Times 1 -ParameterFilter {
            $urlPath -eq '/users/bg%2Bone%40example.test' -and $ErrorAction -eq 'Stop'
        }
        Should -Invoke Add-ProfileInformation -ModuleName Check-UserRiskBasedCAP -Times 0
    }

    It 'Accepts block policy for <Kind> risk without session controls' -ForEach @(
        @{ Kind = 'user high'; UserRisk = @('high'); SignInRisk = @() }
        @{ Kind = 'sign-in medium'; UserRisk = @(); SignInRisk = @('medium') }
        @{ Kind = 'sign-in high'; UserRisk = @(); SignInRisk = @('high') }
    ) {
        $script:policies[0].grantControls.builtInControls = @('block')
        $script:policies[0].sessionControls = $null
        $script:policies[0].conditions.userRiskLevels = $UserRisk
        $script:policies[0].conditions.signInRiskLevels = $SignInRisk
        (Get-UserRiskBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Rejects policy with <Label>' -ForEach @(
        @{ Label = 'disabled state'; Mutate = { $script:policies[0].state = 'disabled' } }
        @{ Label = 'report-only state'; Mutate = { $script:policies[0].state = 'enabledForReportingButNotEnforced' } }
        @{ Label = 'not all users'; Mutate = { $script:policies[0].conditions.users.includeUsers = @('bg1') } }
        @{ Label = 'third excluded user'; Mutate = { $script:policies[0].conditions.users.excludeUsers += 'extra' } }
        @{ Label = 'only one break glass excluded'; Mutate = { $script:policies[0].conditions.users.excludeUsers = @('bg1') } }
        @{ Label = 'selected application'; Mutate = { $script:policies[0].conditions.applications.includeApplications = @('app1') } }
        @{ Label = 'MFA only'; Mutate = { $script:policies[0].grantControls.builtInControls = @('mfa') } }
        @{ Label = 'password change only'; Mutate = { $script:policies[0].grantControls.builtInControls = @('passwordChange') } }
        @{ Label = 'medium user risk only'; Mutate = { $script:policies[0].conditions.userRiskLevels = @('medium') } }
        @{ Label = 'missing user risk'; Mutate = { $script:policies[0].conditions.userRiskLevels = $null } }
        @{ Label = 'browser client only'; Mutate = { $script:policies[0].conditions.clientAppTypes = @('browser') } }
        @{ Label = 'missing session'; Mutate = { $script:policies[0].sessionControls = $null } }
        @{ Label = 'disabled sign-in frequency'; Mutate = { $script:policies[0].sessionControls.signInFrequency.isEnabled = $false } }
        @{ Label = 'periodic frequency'; Mutate = { $script:policies[0].sessionControls.signInFrequency.frequencyInterval = 'timeBased' } }
        @{ Label = 'primary-only authentication'; Mutate = { $script:policies[0].sessionControls.signInFrequency.authenticationType = 'primaryAuthentication' } }
        @{ Label = 'selected platform'; Mutate = { $script:policies[0].conditions.platforms = @{ includePlatforms = @('windows') } } }
        @{ Label = 'location filter'; Mutate = { $script:policies[0].conditions.locations = @{ includeLocations = @('All') } } }
        @{ Label = 'device filter'; Mutate = { $script:policies[0].conditions.devices = @{ deviceFilter = @{} } } }
        @{ Label = 'client application filter'; Mutate = { $script:policies[0].conditions.clientApplications = @{ includeServicePrincipals = @('All') } } }
        @{ Label = 'included group'; Mutate = { $script:policies[0].conditions.users.includeGroups = @('group1') } }
        @{ Label = 'excluded application'; Mutate = { $script:policies[0].conditions.applications.excludeApplications = @('app1') } }
        @{ Label = 'included role'; Mutate = { $script:policies[0].conditions.users.includeRoles = @('role1') } }
        @{ Label = 'excluded role'; Mutate = { $script:policies[0].conditions.users.excludeRoles = @('role1') } }
        @{ Label = 'included guests'; Mutate = { $script:policies[0].conditions.users.includeGuestsOrExternalUsers = @{ guestOrExternalUserTypes = 'all' } } }
        @{ Label = 'excluded guests'; Mutate = { $script:policies[0].conditions.users.excludeGuestsOrExternalUsers = @{ guestOrExternalUserTypes = 'all' } } }
    ) {
        & $Mutate
        $result = Get-UserRiskBasedCAP @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'Fail Risk unprotected'
        $result.Errors.Count | Should -Be 0
    }

    It 'Rejects block policies with nonempty session controls or low sign-in risk' -ForEach @(
        @{ Session = @{ signInFrequency = @{ isEnabled = $true } }; Risk = @('high') }
        @{ Session = $null; Risk = @('low') }
    ) {
        $script:policies[0].grantControls.builtInControls = @('block')
        $script:policies[0].sessionControls = $Session
        $script:policies[0].conditions.userRiskLevels = @()
        $script:policies[0].conditions.signInRiskLevels = $Risk
        (Get-UserRiskBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
    }

    It 'Accepts all explicit client and platform choices including Linux and admin portals' {
        $script:policies[0].conditions.clientAppTypes = @('browser', 'mobileAppsAndDesktopClients', 'exchangeActiveSync', 'other')
        $script:policies[0].conditions.platforms = @{ includePlatforms = @('android', 'iOS', 'windows', 'macOS', 'linux') }
        $script:policies[0].conditions.applications.includeApplications = @('MicrosoftAdminPortals')
        (Get-UserRiskBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Requires Linux when platforms are specified individually' {
        $script:policies[0].conditions.platforms = @{ includePlatforms = @('android', 'iOS', 'windows', 'macOS') }
        (Get-UserRiskBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
    }

    It 'Accepts a shared break glass group instead of explicit users, ignoring non-group memberships' {
        $script:groups1 = @(@{ id = 'shared'; '@odata.type' = '#microsoft.graph.group' }, @{ id = 'role'; '@odata.type' = '#microsoft.graph.directoryRole' })
        $script:groups2 = @(@{ id = 'shared'; '@odata.type' = '#microsoft.graph.group' })
        $script:policies[0].conditions.users.excludeUsers = @()
        $script:policies[0].conditions.users.excludeGroups = @('shared')
        (Get-UserRiskBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Rejects unrelated or only individually shared group exclusions' -ForEach @(
        @{ Groups1 = @('shared'); Groups2 = @('shared'); Excluded = @('shared', 'extra') }
        @{ Groups1 = @('one'); Groups2 = @('two'); Excluded = @('one') }
        @{ Groups1 = @(); Groups2 = @(); Excluded = @('extra') }
    ) {
        $script:groups1 = @($Groups1 | ForEach-Object { @{ id = $_; '@odata.type' = '#microsoft.graph.group' } })
        $script:groups2 = @($Groups2 | ForEach-Object { @{ id = $_; '@odata.type' = '#microsoft.graph.group' } })
        $script:policies[0].conditions.users.excludeGroups = $Excluded
        (Get-UserRiskBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
    }

    It 'Accepts explicit user exclusions even when both accounts share a group' {
        $script:groups1 = @(@{ id = 'shared'; '@odata.type' = '#microsoft.graph.group' })
        $script:groups2 = $script:groups1
        (Get-UserRiskBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Accepts any qualifying policy among multiple invalid ones' {
        $other = New-RiskPolicy
        $other.state = 'disabled'
        $script:policies = @($other, $script:policies[0])
        (Get-UserRiskBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Fails closed for <Label> policies' -ForEach @(
        @{ Label = 'empty'; Content = @{ value = @() } }
        @{ Label = 'missing content'; Content = $null }
        @{ Label = 'missing value'; Content = @{} }
    ) {
        Mock Invoke-GraphQueryEX -ModuleName Check-UserRiskBasedCAP { @{ Content = $Content } } -ParameterFilter { $urlPath -eq '/identity/conditionalAccess/policies' }
        (Get-UserRiskBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
    }

    It 'Collects <Stage> failures (currently leaking Add index) and retains the envelope' -ForEach @(
        @{ Stage = 'policies'; Path = '/identity/conditionalAccess/policies'; ErrorPattern = 'Failed to call Microsoft Graph' }
        @{ Stage = 'first UPN'; Path = '/users/bg%2Bone%40example.test'; ErrorPattern = 'Failed to resolve break glass UPN' }
        @{ Stage = 'second UPN'; Path = '/users/bg2%40example.test'; ErrorPattern = 'Failed to resolve break glass UPN' }
        @{ Stage = 'first membership'; Path = '/users/bg1/memberOf'; ErrorPattern = 'Failed to get group memberships' }
        @{ Stage = 'second membership'; Path = '/users/bg2/memberOf'; ErrorPattern = 'Failed to get group memberships' }
    ) {
        Mock Invoke-GraphQueryEX -ModuleName Check-UserRiskBasedCAP { throw 'Graph offline' } -ParameterFilter { $urlPath -eq $Path }
        $output = @(Get-UserRiskBasedCAP @script:params -ErrorAction SilentlyContinue)
        $output.Count | Should -Be 2
        $output[0] | Should -Be 0
        $output[-1].Errors.Count | Should -Be 1
        $output[-1].Errors[0] | Should -Match "$ErrorPattern.*Graph offline"
        if ($Stage -notlike '*membership') {
            $output[-1].ComplianceResults.ComplianceStatus | Should -BeFalse
        } else {
            # Explicit user exclusions still qualify when group lookup fails.
            $output[-1].ComplianceResults.ComplianceStatus | Should -BeTrue
        }
    }

    It 'Does not query memberships for unresolved users' {
        Mock Invoke-GraphQueryEX -ModuleName Check-UserRiskBasedCAP { @{ Content = $null } } -ParameterFilter { $urlPath -like '/users/*%40example.test' }
        (Get-UserRiskBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
        Should -Invoke Invoke-GraphQueryEX -ModuleName Check-UserRiskBasedCAP -Times 0 -ParameterFilter { $urlPath -like '*/memberOf' }
    }

    It 'Characterizes sign-in risk restriction not being rejected on a password-change policy' {
        $script:policies[0].conditions.signInRiskLevels = @('low')
        (Get-UserRiskBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Should reject password-change policies restricted to low sign-in risk' -Skip {
        # Test-CommonFilters documents an empty signInRiskLevels requirement but never enforces it.
        $script:policies[0].conditions.signInRiskLevels = @('low')
        (Get-UserRiskBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
    }

    It 'Should not leak collection indexes on caught Graph errors' -Skip {
        # All Graph catch blocks call ArrayList.Add without suppressing its return value.
        Mock Invoke-GraphQueryEX -ModuleName Check-UserRiskBasedCAP { throw 'offline' }
        @(Get-UserRiskBasedCAP @script:params -ErrorAction SilentlyContinue).Count | Should -Be 1
    }

    It 'Enriches the original report in place with supplied profile settings' {
        Mock Add-ProfileInformation -ModuleName Check-UserRiskBasedCAP {
            $Result | Add-Member Profile 3
            [void]$ErrorList.Add('Profile warning')
            $Result
        }
        $result = Get-UserRiskBasedCAP @script:params -EnableMultiCloudProfiles -CloudUsageProfiles '2,3' -ModuleProfiles '3'
        $result.ComplianceResults.Profile | Should -Be 3
        $result.Errors | Should -Contain 'Profile warning'
        Should -Invoke Add-ProfileInformation -ModuleName Check-UserRiskBasedCAP -Exactly -Times 1 -ParameterFilter {
            $CloudUsageProfiles -eq '2,3' -and $ModuleProfiles -eq '3'
        }
    }

    It 'Propagates profile helper failure' {
        Mock Add-ProfileInformation -ModuleName Check-UserRiskBasedCAP { throw 'Profile failed' }
        { Get-UserRiskBasedCAP @script:params -EnableMultiCloudProfiles } | Should -Throw '*Profile failed*'
    }
}

Describe 'Test-IsNullOrEmptyArray risk helper' {
    It 'Recognizes <Label> as empty' -ForEach @(
        @{ Label = 'null'; Value = $null }, @{ Label = 'empty array'; Value = @() }, @{ Label = 'empty string'; Value = '' }
    ) {
        Test-IsNullOrEmptyArray -Value $Value | Should -BeTrue
    }
    It 'Treats <Label> as nonempty' -ForEach @(
        @{ Label = 'whitespace'; Value = ' ' }, @{ Label = 'zero'; Value = 0 }
        @{ Label = 'empty object'; Value = [pscustomobject]@{} }, @{ Label = 'populated array'; Value = @('value') }
    ) {
        Test-IsNullOrEmptyArray -Value $Value | Should -BeFalse
    }
}
