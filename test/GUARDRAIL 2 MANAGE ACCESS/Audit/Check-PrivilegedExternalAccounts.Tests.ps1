BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'
    $script:createdStubs = @()
    $script:loadedCommands = @(Get-Command -ListImported).Name
    foreach ($name in @('Get-AzADUser', 'Get-AzSubscription', 'Get-AzRoleAssignment', 'Add-ProfileInformation', 'Send-OMSAPIIngestionFile')) {
        if ($name -notin $script:loadedCommands) {
            Set-Item "Function:global:$name" {
                [CmdletBinding()]
                param($Filter, $Scope, $Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList)
                throw 'Unmocked dependency'
            }
            $script:createdStubs += $name
        }
    }
    $script:module = Import-Module (Join-Path $PSScriptRoot '../../../src/GUARDRAIL 2 MANAGE ACCESS/Audit/Check-PrivilegedExternalAccounts.psm1') -Force -PassThru
    & $script:module { $script:debug = $false; $script:subscriptionId = $null }
    $script:params = @{
        ControlName = 'GUARDRAIL 2'; ItemName = 'Privileged external accounts'; itsgcode = 'AC-2'; ReportTime = '2026-10-14'
        msgTable = @{
            noGuestAccounts = 'No guests.'; guestAccountsNoPrivilegedPermission = 'No privileged permissions.'
            guestAssigned = 'Assigned.'; guestNotAssigned = 'Unassigned.'; guestHasPrivilegedRole = 'Privileged role.'
            existingPrivilegedGuestAccountsComment = 'Existing guests.'; existingPrivilegedGuestAccounts = 'Review guests.'
        }
    }
    $script:guest = [pscustomobject]@{
        Id = 'guest-1'; DisplayName = 'Guest One'; Mail = 'guest@example.test'; UserPrincipalName = 'guest@example.test'
        UserType = 'Guest'; CreatedDateTime = '2025-01-01'; AccountEnabled = $true
    }
    function New-GuestAssignment {
        param($Role = 'Owner', $ObjectType = 'User', $DisplayName = 'Guest One', $SignInName = 'guest@example.test')
        [pscustomobject]@{
            ObjectId = 'guest-1'; ObjectType = $ObjectType; DisplayName = $DisplayName; SignInName = $SignInName
            RoleDefinitionName = $Role; Scope = '/subscriptions/sub-1'; RoleAssignmentId = 'assignment-1'
        }
    }
}

AfterAll {
    Remove-Module $script:module -ErrorAction SilentlyContinue
    foreach ($name in $script:createdStubs) { Remove-Item "Function:\$name" -ErrorAction SilentlyContinue }
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-PrivilegedExternalUsers' {
    BeforeEach {
        Mock Get-AzADUser -ModuleName Check-PrivilegedExternalAccounts { $script:guest }
        Mock Get-AzSubscription -ModuleName Check-PrivilegedExternalAccounts {
            [pscustomobject]@{ Id = 'sub-1'; Name = 'One'; State = 'Enabled' }
        }
        Mock Get-AzRoleAssignment -ModuleName Check-PrivilegedExternalAccounts { New-GuestAssignment }
        Mock Add-ProfileInformation -ModuleName Check-PrivilegedExternalAccounts { throw 'Unexpected profile call' }
        Mock Send-OMSAPIIngestionFile -ModuleName Check-PrivilegedExternalAccounts { throw 'Unexpected ingestion' }
        Mock Write-Host -ModuleName Check-PrivilegedExternalAccounts {}
    }

    It 'Returns compliant metadata and a placeholder record when there are no guests' {
        Mock Get-AzADUser -ModuleName Check-PrivilegedExternalAccounts { $null }
        $result = @(Check-PrivilegedExternalUsers @script:params)[-1]
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'No guests.'
        $result.ComplianceResults.MitigationCommands | Should -Be 'N/A'
        $result.Errors.Count | Should -Be 0
        $result.AdditionalResults.logType | Should -Be 'GR2ExternalUsers'
        @($result.AdditionalResults.records).Count | Should -Be 1
        foreach ($key in @('DisplayName', 'Subscription', 'Mail', 'Type', 'CreatedDate', 'Enabled', 'Role', 'PrivilegedRole')) {
            $result.AdditionalResults.records.$key | Should -Be 'N/A'
        }
        foreach ($key in @('ControlName', 'ItemName', 'itsgcode', 'ReportTime')) {
            $result.ComplianceResults.$key | Should -Be $script:params[$key]
        }
        foreach ($key in @('ItemName', 'itsgcode', 'ReportTime')) {
            $result.AdditionalResults.records.$key | Should -Be $script:params[$key]
        }
        Should -Invoke Get-AzADUser -ModuleName Check-PrivilegedExternalAccounts -Times 1 -Exactly -ParameterFilter { $Filter -eq "usertype eq 'guest'" }
        Should -Invoke Get-AzSubscription -ModuleName Check-PrivilegedExternalAccounts -Times 0 -Exactly
        Should -Invoke Add-ProfileInformation -ModuleName Check-PrivilegedExternalAccounts -Times 0 -Exactly
        Should -Invoke Send-OMSAPIIngestionFile -ModuleName Check-PrivilegedExternalAccounts -Times 0 -Exactly
    }

    It 'Handles an empty user result as absent users' {
        Mock Get-AzADUser -ModuleName Check-PrivilegedExternalAccounts { @() }
        (@(Check-PrivilegedExternalUsers @script:params)[-1]).ComplianceResults.Comments | Should -Be 'No guests.'
    }

    It 'Reports no privileged permission when subscriptions or assignments are <missing>' -ForEach @(
        @{ missing = 'absent subscriptions' }, @{ missing = 'disabled subscriptions' },
        @{ missing = 'null assignments' }, @{ missing = 'empty assignments' }
    ) {
        if ($missing -eq 'absent subscriptions') {
            Mock Get-AzSubscription -ModuleName Check-PrivilegedExternalAccounts { @() }
        } elseif ($missing -eq 'disabled subscriptions') {
            Mock Get-AzSubscription -ModuleName Check-PrivilegedExternalAccounts { [pscustomobject]@{ Id = 'disabled'; State = 'Disabled' } }
        } elseif ($missing -eq 'null assignments') {
            Mock Get-AzRoleAssignment -ModuleName Check-PrivilegedExternalAccounts { $null }
        } else {
            Mock Get-AzRoleAssignment -ModuleName Check-PrivilegedExternalAccounts { @() }
        }
        $result = @(Check-PrivilegedExternalUsers @script:params)[-1]
        $result.ComplianceResults.Comments | Should -Be 'No privileged permissions.'
        $result.ComplianceResults.MitigationCommands | Should -Be 'N/A'
        $result.AdditionalResults.records.Role | Should -Be 'N/A'
        if ($missing -in @('absent subscriptions', 'disabled subscriptions')) {
            Should -Invoke Get-AzRoleAssignment -ModuleName Check-PrivilegedExternalAccounts -Times 0 -Exactly
        }
    }

    It 'Detects privileged role <role> but remains informational and compliant' -ForEach @(
        @{ role = 'Owner' }
        @{ role = 'Contributor' }
        @{ role = 'Access Review Operator Service Role' }
        @{ role = 'Custom - Landing Zone Application Owner' }
        @{ role = 'Custom - Landing Zone Subscription Owner' }
        @{ role = 'Role Based Access Control Administrator' }
        @{ role = 'User Access Administrator' }
    ) {
        Mock Get-AzRoleAssignment -ModuleName Check-PrivilegedExternalAccounts { New-GuestAssignment -Role $role }
        $result = @(Check-PrivilegedExternalUsers @script:params)[-1]
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'Existing guests.'
        $result.ComplianceResults.MitigationCommands | Should -Be 'Review guests.'
        $record = $result.AdditionalResults.records
        $record.DisplayName | Should -Be 'Guest One'
        $record.Mail | Should -Be 'guest@example.test'
        $record.Subscription | Should -Be 'One'
        $record.Role | Should -Be 'True'
        $record.PrivilegedRole | Should -Be 'True'
        $record.Comments | Should -Be 'Assigned. Privileged role.'
        $result.Errors.Count | Should -Be 0
        Should -Invoke Get-AzRoleAssignment -ModuleName Check-PrivilegedExternalAccounts -Times 1 -Exactly -ParameterFilter { $Scope -eq '/subscriptions/sub-1' }
    }

    It 'Does not classify <role> as a privileged role' -ForEach @(
        @{ role = 'Reader' }, @{ role = 'Owner Custom' }, @{ role = '' }
    ) {
        Mock Get-AzRoleAssignment -ModuleName Check-PrivilegedExternalAccounts { New-GuestAssignment -Role $role }
        $record = (@(Check-PrivilegedExternalUsers @script:params)[-1]).AdditionalResults.records
        $record.Role | Should -Be 'True'
        $record.PrivilegedRole | Should -Be 'False'
        $record.Comments | Should -Be 'Assigned.'
    }

    It 'Detects a privileged role among multiple assignments for the same guest' {
        Mock Get-AzRoleAssignment -ModuleName Check-PrivilegedExternalAccounts {
            @(New-GuestAssignment -Role 'Reader'; New-GuestAssignment -Role 'Contributor')
        }
        (@(Check-PrivilegedExternalUsers @script:params)[-1]).AdditionalResults.records.PrivilegedRole | Should -Be 'True'
    }

    It 'Accepts <type> assignments for the name/UPN join' -ForEach @(
        @{ type = 'User'; expected = 'True' }, @{ type = 'Group'; expected = 'True' }, @{ type = 'ServicePrincipal'; expected = 'False' }
    ) {
        Mock Get-AzRoleAssignment -ModuleName Check-PrivilegedExternalAccounts { New-GuestAssignment -ObjectType $type }
        (@(Check-PrivilegedExternalUsers @script:params)[-1]).AdditionalResults.records.PrivilegedRole | Should -Be $expected
    }

    It 'Requires both the display name and sign-in name to match (<mismatch>)' -ForEach @(
        @{ mismatch = 'name' }, @{ mismatch = 'UPN' }
    ) {
        Mock Get-AzRoleAssignment -ModuleName Check-PrivilegedExternalAccounts {
            if ($mismatch -eq 'name') { New-GuestAssignment -DisplayName 'Other' }
            else { New-GuestAssignment -SignInName 'other@example.test' }
        }
        $record = (@(Check-PrivilegedExternalUsers @script:params)[-1]).AdditionalResults.records
        $record.Role | Should -Be 'True'
        $record.PrivilegedRole | Should -Be 'False'
    }

    It 'Includes unmatched guests as unassigned with a blank subscription' {
        Mock Get-AzRoleAssignment -ModuleName Check-PrivilegedExternalAccounts { [pscustomobject]@{ ObjectId = 'member-1'; ObjectType = 'User' } }
        $record = (@(Check-PrivilegedExternalUsers @script:params)[-1]).AdditionalResults.records
        $record.DisplayName | Should -Be 'Guest One'
        $record.Role | Should -Be 'False'
        $record.PrivilegedRole | Should -Be 'False'
        $record.Subscription | Should -Be ''
        $record.Comments | Should -Be 'Unassigned.'
    }

    It 'Aggregates matching subscriptions and excludes disabled subscriptions' {
        Mock Get-AzSubscription -ModuleName Check-PrivilegedExternalAccounts {
            @(
                [pscustomobject]@{ Id = 'sub-1'; Name = 'One'; State = 'Enabled' }
                [pscustomobject]@{ Id = 'sub-2'; Name = 'Two'; State = 'Enabled' }
                [pscustomobject]@{ Id = 'disabled'; Name = 'Disabled'; State = 'Disabled' }
            )
        }
        $result = @(Check-PrivilegedExternalUsers @script:params)[-1]
        @($result.AdditionalResults.records).Count | Should -Be 1
        $result.AdditionalResults.records.Subscription | Should -Be 'One, Two'
        Should -Invoke Get-AzRoleAssignment -ModuleName Check-PrivilegedExternalAccounts -Times 2 -Exactly
        Should -Invoke Get-AzRoleAssignment -ModuleName Check-PrivilegedExternalAccounts -Times 0 -Exactly -ParameterFilter { $Scope -eq '/subscriptions/disabled' }
    }

    # Desired: preserve UserType, CreatedDateTime and AccountEnabled through the selected-property join.
    It 'Characterizes metadata lost by the selected-property join' {
        $record = (@(Check-PrivilegedExternalUsers @script:params)[-1]).AdditionalResults.records
        $record.Type | Should -BeNullOrEmpty
        $record.CreatedDate | Should -BeNullOrEmpty
        $record.Enabled | Should -BeNullOrEmpty
    }

    # Desired: aggregate privileged flags with logical OR rather than keeping only the first subscription's flag.
    It 'Characterizes loss of later privileged flags when grouping otherwise identical rows' {
        Mock Get-AzSubscription -ModuleName Check-PrivilegedExternalAccounts {
            @([pscustomobject]@{ Id = 'sub-1'; Name = 'One'; State = 'Enabled' }, [pscustomobject]@{ Id = 'sub-2'; Name = 'Two'; State = 'Enabled' })
        }
        Mock Get-AzRoleAssignment -ModuleName Check-PrivilegedExternalAccounts {
            param($Scope)
            if ($Scope -eq '/subscriptions/sub-1') { New-GuestAssignment -Role 'Reader' }
            else { New-GuestAssignment -Role 'Owner' }
        }
        $record = (@(Check-PrivilegedExternalUsers @script:params)[-1]).AdditionalResults.records
        $record.Subscription | Should -Be 'One, Two'
        $record.PrivilegedRole | Should -Be 'False'
    }

    # Desired: deduplicate by stable user identity, not display name, and retain both users.
    It 'Characterizes two distinct guest identities sharing a display name being collapsed' {
        Mock Get-AzADUser -ModuleName Check-PrivilegedExternalAccounts {
            @(
                $script:guest
                [pscustomobject]@{ Id = 'guest-2'; DisplayName = 'Guest One'; UserPrincipalName = 'other@example.test'; Mail = 'other@example.test' }
            )
        }
        Mock Get-AzRoleAssignment -ModuleName Check-PrivilegedExternalAccounts {
            @(
                New-GuestAssignment
                [pscustomobject]@{ ObjectId = 'guest-2'; ObjectType = 'User'; DisplayName = 'Guest One'; SignInName = 'other@example.test'; RoleDefinitionName = 'Reader' }
            )
        }
        @((@(Check-PrivilegedExternalUsers @script:params)[-1]).AdditionalResults.records).Count | Should -Be 1
    }

    # Desired: fail closed and preserve directory-error diagnostics instead of returning a compliant placeholder.
    It 'Characterizes nonterminating directory errors as compliant without captured errors' {
        Mock Get-AzADUser -ModuleName Check-PrivilegedExternalAccounts { Write-Error 'Directory unavailable' -ErrorAction Continue }
        $result = @(Check-PrivilegedExternalUsers @script:params 2>$null)[-1]
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'No guests.'
        $result.Errors.Count | Should -Be 0
    }

    It 'Propagates a failure in <dependency> rather than returning an Errors envelope' -ForEach @(
        @{ dependency = 'Get-AzADUser' }, @{ dependency = 'Get-AzSubscription' }, @{ dependency = 'Get-AzRoleAssignment' }
    ) {
        Mock $dependency -ModuleName Check-PrivilegedExternalAccounts { throw 'Dependency unavailable' }
        { Check-PrivilegedExternalUsers @script:params } | Should -Throw '*Dependency unavailable*'
    }

    It 'Forwards optional profiles and preserves mutations and errors' {
        Mock Add-ProfileInformation -ModuleName Check-PrivilegedExternalAccounts {
            param($Result, $ErrorList)
            $Result | Add-Member Profile 2
            $Result.ComplianceStatus = 'Not Applicable'
            [void]$ErrorList.Add('Profile diagnostic')
            $Result
        }
        $result = @(Check-PrivilegedExternalUsers @script:params -EnableMultiCloudProfiles -CloudUsageProfiles '1,2' -ModuleProfiles '2')[-1]
        $result.ComplianceResults.Profile | Should -Be 2
        $result.ComplianceResults.ComplianceStatus | Should -Be 'Not Applicable'
        @($result.Errors) | Should -Contain 'Profile diagnostic'
        $result.AdditionalResults.records.PrivilegedRole | Should -Be 'True'
        Should -Invoke Add-ProfileInformation -ModuleName Check-PrivilegedExternalAccounts -Times 1 -Exactly -ParameterFilter {
            $CloudUsageProfiles -eq '1,2' -and $ModuleProfiles -eq '2' -and $null -eq $SubscriptionId
        }
    }

    It 'Passes default profile 3 when no override is specified' {
        Mock Add-ProfileInformation -ModuleName Check-PrivilegedExternalAccounts { param($Result) $Result }
        Check-PrivilegedExternalUsers @script:params -EnableMultiCloudProfiles | Out-Null
        Should -Invoke Add-ProfileInformation -ModuleName Check-PrivilegedExternalAccounts -Times 1 -Exactly -ParameterFilter { $CloudUsageProfiles -eq '3' }
    }

    It 'Propagates profile helper failures' {
        Mock Add-ProfileInformation -ModuleName Check-PrivilegedExternalAccounts { throw 'Profile unavailable' }
        { Check-PrivilegedExternalUsers @script:params -EnableMultiCloudProfiles } | Should -Throw '*Profile unavailable*'
    }
}
