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
    Import-Module (Join-Path $PSScriptRoot '../../../src/GUARDRAIL 2 MANAGE ACCESS/Audit/Check-OnlineAttackCountermeasures.psm1') -Force
}

AfterAll {
    Remove-Module Check-OnlineAttackCountermeasures -Force -ErrorAction SilentlyContinue
    foreach ($name in $script:savedFunctions.Keys) {
        if ($null -ne $script:savedFunctions[$name]) {
            Set-Item "Function:global:$name" $script:savedFunctions[$name]
        } else {
            Remove-Item "Function:global:$name" -ErrorAction SilentlyContinue
        }
    }
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-OnlineAttackCountermeasures' {
    BeforeAll {
        $script:params = @{
            ControlName = 'GUARDRAIL 2'; ItemName = 'Online attack'; itsgcode = 'AC-7'; ReportTime = '2026-10-14'
            msgTable = @{
                onlineAttackIsCompliant = 'Protected'
                onlineAttackNonCompliantC1 = 'Lockout too high'
                onlineAttackNonCompliantC2 = 'Banned list insufficient'
                onlineAttackNonCompliantC1C2 = 'Both checks failed'
            }
        }
    }
    BeforeEach {
        $script:threshold = '10'
        $script:banned = "password`tPassword!`tSummer2018`tdepartment"
        $script:omitThreshold = $false
        Mock Invoke-GraphQueryEX -ModuleName Check-OnlineAttackCountermeasures {
            $values = @([pscustomobject]@{ name = 'BannedPasswordList'; value = $script:banned })
            if (-not $script:omitThreshold) {
                $values += [pscustomobject]@{ name = 'LockoutThreshold'; value = $script:threshold }
            }
            [pscustomobject]@{ Content = @{ value = @(
                [pscustomobject]@{ displayName = 'Unrelated'; values = @() }
                [pscustomobject]@{ displayName = 'Password Rule Settings'; values = $values }
            ) } }
        }
        Mock Add-ProfileInformation -ModuleName Check-OnlineAttackCountermeasures { throw 'Unexpected profile call' }
    }

    It 'Returns one compliant envelope with all report metadata and no profile work by default' {
        $output = @(Check-OnlineAttackCountermeasures @script:params)
        $output.Count | Should -Be 1
        $output[0].ComplianceResults.ComplianceStatus | Should -BeTrue
        $output[0].ComplianceResults.Comments | Should -Be 'Protected'
        foreach ($key in @('ControlName', 'ItemName', 'itsgcode', 'ReportTime')) {
            $output[0].ComplianceResults.$key | Should -Be $script:params[$key]
        }
        $output[0].Errors.Count | Should -Be 0
        Should -Invoke Invoke-GraphQueryEX -ModuleName Check-OnlineAttackCountermeasures -Exactly -Times 1 -ParameterFilter {
            $urlPath -eq '/groupSettings' -and $ErrorAction -eq 'Stop'
        }
        Should -Invoke Add-ProfileInformation -ModuleName Check-OnlineAttackCountermeasures -Times 0
    }

    It 'Accepts threshold <Threshold> at or below the upper boundary' -ForEach @(
        @{ Threshold = '1' }, @{ Threshold = '9' }, @{ Threshold = '10' }
    ) {
        $script:threshold = $Threshold
        (Check-OnlineAttackCountermeasures @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Rejects threshold <Threshold> above ten' -ForEach @(@{ Threshold = '11' }, @{ Threshold = '100' }) {
        $script:threshold = $Threshold
        $result = Check-OnlineAttackCountermeasures @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'Lockout too high '
        $result.Errors.Count | Should -Be 0
    }

    It 'Rejects <Label> banned password configuration' -ForEach @(
        @{ Label = 'null'; Banned = $null }
        @{ Label = 'empty'; Banned = '' }
        @{ Label = 'only three required entries'; Banned = "password`tPassword!`tSummer2018" }
        @{ Label = 'missing password'; Banned = "Password!`tSummer2018`tdepartment`tother" }
        @{ Label = 'missing Password!'; Banned = "password`tSummer2018`tdepartment`tother" }
        @{ Label = 'missing Summer2018'; Banned = "password`tPassword!`tdepartment`tother" }
        @{ Label = 'comma instead of tab delimiter'; Banned = 'password,Password!,Summer2018,department' }
    ) {
        $script:banned = $Banned
        $result = Check-OnlineAttackCountermeasures @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'Banned list insufficient '
    }

    It 'Reports both independent failures' {
        $script:threshold = '11'
        $script:banned = ''
        (Check-OnlineAttackCountermeasures @script:params).ComplianceResults.Comments | Should -Be 'Both checks failed'
    }

    It 'Fails closed for <Label> group settings responses and collects the caught error' -ForEach @(
        @{ Label = 'null'; Content = $null }
        @{ Label = 'missing value'; Content = @{} }
        @{ Label = 'empty collection'; Content = @{ value = @() } }
        @{ Label = 'unrelated setting'; Content = @{ value = @(@{ displayName = 'Other' }) } }
    ) {
        Mock Invoke-GraphQueryEX -ModuleName Check-OnlineAttackCountermeasures { @{ Content = $Content } }
        $output = @(Check-OnlineAttackCountermeasures @script:params)
        # ArrayList.Add is not suppressed in the catch: the current implementation emits its index.
        $output.Count | Should -Be 2
        $output[0] | Should -Be 0
        $output[-1].ComplianceResults.ComplianceStatus | Should -BeFalse
        $output[-1].ComplianceResults.Comments | Should -Be ''
        $output[-1].Errors.Count | Should -Be 1
        $output[-1].Errors[0] | Should -Match 'Password Rule Settings not found'
    }

    It 'Collects Graph failure without losing the returned envelope (currently also emits index zero)' {
        Mock Invoke-GraphQueryEX -ModuleName Check-OnlineAttackCountermeasures { throw 'Graph offline' }
        $output = @(Check-OnlineAttackCountermeasures @script:params)
        $output[0] | Should -Be 0
        $output[-1].Errors[0] | Should -Match 'Failed to retrieve or process group settings:.*Graph offline'
        $output[-1].ComplianceResults.ComplianceStatus | Should -BeFalse
    }

    It 'Catches a malformed integer instead of claiming compliance' {
        $script:threshold = 'not-an-integer'
        $result = @(Check-OnlineAttackCountermeasures @script:params)[-1]
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.Errors.Count | Should -Be 1
        $result.Errors[0] | Should -Match 'Failed to retrieve or process'
    }

    It 'Characterizes the missing lockout threshold defect: null is cast to zero and passes' {
        $script:omitThreshold = $true
        (Check-OnlineAttackCountermeasures @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Characterizes invalid nonpositive thresholds being accepted' -ForEach @(@{ Threshold = '0' }, @{ Threshold = '-1' }) {
        $script:threshold = $Threshold
        (Check-OnlineAttackCountermeasures @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Characterizes duplicate fourth banned entry being accepted as an additional component' {
        $script:banned = "password`tPassword!`tSummer2018`tpassword"
        (Check-OnlineAttackCountermeasures @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Should reject missing lockout settings' -Skip {
        # Production currently coerces a missing threshold to zero; enable after validation is fixed.
        $script:omitThreshold = $true
        (Check-OnlineAttackCountermeasures @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
    }

    It 'Should return a single envelope on caught failures' -Skip {
        # Production catch leaks ArrayList.Add's index to the success stream.
        Mock Invoke-GraphQueryEX -ModuleName Check-OnlineAttackCountermeasures { throw 'offline' }
        @(Check-OnlineAttackCountermeasures @script:params).Count | Should -Be 1
    }

    It 'Forwards optional profiles and preserves in-place enrichment and helper errors' {
        Mock Add-ProfileInformation -ModuleName Check-OnlineAttackCountermeasures {
            $Result | Add-Member Profile 2
            [void]$ErrorList.Add('Profile warning')
            $Result
        }
        $result = Check-OnlineAttackCountermeasures @script:params -EnableMultiCloudProfiles -CloudUsageProfiles '1,2' -ModuleProfiles '2'
        $result.ComplianceResults.Profile | Should -Be 2
        $result.Errors | Should -Contain 'Profile warning'
        Should -Invoke Add-ProfileInformation -ModuleName Check-OnlineAttackCountermeasures -Exactly -Times 1 -ParameterFilter {
            $CloudUsageProfiles -eq '1,2' -and $ModuleProfiles -eq '2' -and $Result.ItemName -eq 'Online attack'
        }
    }

    It 'Does not swallow profile helper exceptions' {
        Mock Add-ProfileInformation -ModuleName Check-OnlineAttackCountermeasures { throw 'Profile failed' }
        { Check-OnlineAttackCountermeasures @script:params -EnableMultiCloudProfiles } | Should -Throw '*Profile failed*'
    }
}
