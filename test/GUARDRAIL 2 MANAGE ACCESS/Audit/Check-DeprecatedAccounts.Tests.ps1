BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'
    $script:createdStubs = @()
    $script:loadedCommands = @(Get-Command -ListImported).Name
    foreach ($name in @('Get-AzADUser', 'Add-ProfileInformation')) {
        if ($name -notin $script:loadedCommands) {
            Set-Item "Function:global:$name" {
                [CmdletBinding()]
                param($Filter, $Select, $Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList)
                throw 'Unmocked dependency'
            }
            $script:createdStubs += $name
        }
    }
    $script:module = Import-Module (Join-Path $PSScriptRoot '../../../src/GUARDRAIL 2 MANAGE ACCESS/Audit/Check-DeprecatedAccounts.psm1') -Force -PassThru
    & $script:module { $script:subscriptionId = $null }
    $script:params = @{
        ControlName = 'GUARDRAIL 2'; ItemName = 'Deprecated accounts'; itsgcode = 'AC-2'
        ReportTime = '2026-10-14T12:00:00Z'
        msgTable = @{
            noncompliantUsers = 'Users: '; compliantComment = 'No deprecated users.'
            noncompliantComment = '{0} deprecated accounts. {1}'; mitigationCommands = 'Remove deprecated users.'
        }
    }
}

AfterAll {
    Remove-Module $script:module -ErrorAction SilentlyContinue
    foreach ($name in $script:createdStubs) { Remove-Item "Function:\$name" -ErrorAction SilentlyContinue }
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-DeprecatedUsers' {
    BeforeEach {
        Mock Get-AzADUser -ModuleName Check-DeprecatedAccounts { $null }
        Mock Add-ProfileInformation -ModuleName Check-DeprecatedAccounts { throw 'Profiles must be explicitly enabled' }
        Mock Write-Host -ModuleName Check-DeprecatedAccounts {}
    }

    It 'Returns a compliant result and all supplied metadata when there are no users' {
        $result = Check-DeprecatedUsers @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'No deprecated users.'
        $result.ComplianceResults.MitigationCommands | Should -Be 'N/A'
        $result.Errors.Count | Should -Be 0
        foreach ($key in @('ControlName', 'ItemName', 'itsgcode', 'ReportTime')) {
            $result.ComplianceResults.$key | Should -Be $script:params[$key]
        }
        Should -Invoke Get-AzADUser -ModuleName Check-DeprecatedAccounts -Times 1 -Exactly -ParameterFilter {
            $Filter -eq 'accountEnabled eq false' -and ($Select -join ',') -eq 'OnPremisesSyncEnabled,UserPrincipalName'
        }
        Should -Invoke Add-ProfileInformation -ModuleName Check-DeprecatedAccounts -Times 0 -Exactly
    }

    It 'Treats an empty result as compliant' {
        Mock Get-AzADUser -ModuleName Check-DeprecatedAccounts { @() }
        (Check-DeprecatedUsers @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Reports one cloud-only disabled user without a scalar count error' {
        Mock Get-AzADUser -ModuleName Check-DeprecatedAccounts {
            [pscustomobject]@{ UserPrincipalName = 'disabled@example.test'; OnPremisesSyncEnabled = $null }
        }
        $result = Check-DeprecatedUsers @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be '1 deprecated accounts. Users: disabled@example.test'
        $result.ComplianceResults.MitigationCommands | Should -Be 'Remove deprecated users.'
        $result.Errors.Count | Should -Be 0
    }

    It 'Counts only null sync flags, excluding both true and false sync flags' {
        Mock Get-AzADUser -ModuleName Check-DeprecatedAccounts {
            @(
                [pscustomobject]@{ UserPrincipalName = 'first@example.test'; OnPremisesSyncEnabled = $null }
                [pscustomobject]@{ UserPrincipalName = 'synced@example.test'; OnPremisesSyncEnabled = $true }
                [pscustomobject]@{ UserPrincipalName = 'formerly@example.test'; OnPremisesSyncEnabled = $false }
                [pscustomobject]@{ UserPrincipalName = 'second@example.test' }
            )
        }
        $result = Check-DeprecatedUsers @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be '2 deprecated accounts. Users: first@example.test  second@example.test'
    }

    It 'Passes when all disabled users have non-null synchronization flags' {
        Mock Get-AzADUser -ModuleName Check-DeprecatedAccounts {
            @([pscustomobject]@{ OnPremisesSyncEnabled = $true }, [pscustomobject]@{ OnPremisesSyncEnabled = $false })
        }
        (Check-DeprecatedUsers @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Propagates an Az failure rather than returning a misleading success' {
        Mock Get-AzADUser -ModuleName Check-DeprecatedAccounts { throw 'Directory unavailable' }
        { Check-DeprecatedUsers @script:params } | Should -Throw '*Directory unavailable*'
    }

    # Desired: fail closed and record directory errors rather than treating a failed lookup as an empty directory.
    It 'Characterizes a nonterminating directory error as compliant with no captured errors' {
        Mock Get-AzADUser -ModuleName Check-DeprecatedAccounts { Write-Error 'Directory unavailable' -ErrorAction Continue }
        $result = Check-DeprecatedUsers @script:params 2>$null
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.Errors.Count | Should -Be 0
    }

    It 'Preserves in-place profile changes and profile errors' {
        Mock Add-ProfileInformation -ModuleName Check-DeprecatedAccounts {
            param($Result, $ErrorList)
            $Result | Add-Member Profile 2
            $Result.ComplianceStatus = 'Not Applicable'
            [void]$ErrorList.Add('Profile diagnostic')
            $Result
        }
        $result = Check-DeprecatedUsers @script:params -EnableMultiCloudProfiles -CloudUsageProfiles '1,2' -ModuleProfiles '2'
        $result.ComplianceResults.Profile | Should -Be 2
        $result.ComplianceResults.ComplianceStatus | Should -Be 'Not Applicable'
        @($result.Errors) | Should -Contain 'Profile diagnostic'
        Should -Invoke Add-ProfileInformation -ModuleName Check-DeprecatedAccounts -Times 1 -Exactly -ParameterFilter {
            $CloudUsageProfiles -eq '1,2' -and $ModuleProfiles -eq '2' -and $null -eq $SubscriptionId -and
            $Result.ItemName -eq 'Deprecated accounts' -and $ErrorList -is [System.Collections.ArrayList]
        }
    }

    It 'Uses the default cloud profile when profiles are enabled without an override' {
        Mock Add-ProfileInformation -ModuleName Check-DeprecatedAccounts { param($Result) $Result }
        Check-DeprecatedUsers @script:params -EnableMultiCloudProfiles | Out-Null
        Should -Invoke Add-ProfileInformation -ModuleName Check-DeprecatedAccounts -Times 1 -Exactly -ParameterFilter { $CloudUsageProfiles -eq '3' }
    }

    It 'Does not catch a profile helper failure' {
        Mock Add-ProfileInformation -ModuleName Check-DeprecatedAccounts { throw 'Profile unavailable' }
        { Check-DeprecatedUsers @script:params -EnableMultiCloudProfiles } | Should -Throw '*Profile unavailable*'
    }
}
