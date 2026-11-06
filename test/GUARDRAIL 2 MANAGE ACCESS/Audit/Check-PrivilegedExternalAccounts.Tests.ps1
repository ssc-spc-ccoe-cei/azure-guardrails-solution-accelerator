BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) return $Result }

    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 2 MANAGE ACCESS\Audit\Check-PrivilegedExternalAccounts.psm1'
    Import-Module $modulePath -Force

    $script:msgTable = @{
        noGuestAccounts                     = 'No guest accounts found.'
        guestAccountsNoPermission           = 'Guest accounts exist but have no Azure permissions.'
        guestAccountsNoPrivilegedPermission = 'Guest accounts exist but have no privileged Azure permissions.'
        existingGuestAccountsComment        = 'Guest accounts with Azure permissions exist.'
        existingGuestAccounts               = 'Review guest account assignments.'
        existingPrivilegedGuestAccountsComment = 'Privileged guest accounts exist.'
        existingPrivilegedGuestAccounts     = 'Review privileged guest account assignments.'
        guestAssigned                       = 'Guest account has an assignment.'
        guestNotAssigned                    = 'Guest account has no assignment.'
        guestHasPrivilegedRole              = 'Guest account has a privileged role.'
    }

    function script:New-GuestUser {
        param(
            [string]$Id,
            [string]$DisplayName = 'Guest User',
            [string]$UserPrincipalName = 'guest@contoso.com',
            [string]$Mail = 'guest@contoso.com',
            [string]$UserType = 'Guest',
            [string]$CreatedDateTime = '2024-01-01T00:00:00Z',
            [bool]$AccountEnabled = $true
        )

        [pscustomobject]@{
            Id                = $Id
            DisplayName       = $DisplayName
            UserPrincipalName = $UserPrincipalName
            Mail              = $Mail
            userType          = $UserType
            createdDateTime   = $CreatedDateTime
            accountEnabled    = $AccountEnabled
        }
    }

    function script:New-Subscription {
        param(
            [string]$Id,
            [string]$Name
        )

        [pscustomobject]@{
            Id    = $Id
            Name  = $Name
            State = 'Enabled'
        }
    }

    function script:New-RoleAssignment {
        param(
            [string]$ObjectId,
            [string]$SignInName,
            [string]$DisplayName,
            [string]$RoleDefinitionName,
            [string]$Scope = '/subscriptions/sub-001',
            [string]$ObjectType = 'User'
        )

        [pscustomobject]@{
            ObjectId           = $ObjectId
            ObjectType         = $ObjectType
            SignInName         = $SignInName
            DisplayName        = $DisplayName
            RoleAssignmentName = 'assignment-001'
            RoleAssignmentId   = 'ra-001'
            Scope              = $Scope
            RoleDefinitionName = $RoleDefinitionName
            RoleDefinitionId   = 'role-001'
            CanDelegate        = $false
            Description        = 'Test role assignment'
        }
    }
}

AfterAll {
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-PrivilegedExternalUsers' {
    BeforeAll {
        $script:commonParams = @{
            ControlName = 'GUARDRAIL 2'
            ItemName    = 'Privileged External Accounts'
            itsgcode    = 'AC-2'
            msgTable    = $script:msgTable
            ReportTime  = '2026-09-03'
        }
    }

    Context 'When no guest users exist' {
        BeforeAll {
            Mock Get-AzADUser -ModuleName Check-PrivilegedExternalAccounts { $null }
            Mock Get-AzSubscription -ModuleName Check-PrivilegedExternalAccounts { @() }
            Mock Get-AzRoleAssignment -ModuleName Check-PrivilegedExternalAccounts { @() }
        }

        It 'Returns compliant with the no guest accounts comment' {
            $result = Check-PrivilegedExternalUsers @commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -Be $script:msgTable.noGuestAccounts
            $result.ComplianceResults.MitigationCommands | Should -Be 'N/A'
        }
    }

    Context 'When guest users exist without any role assignments' {
        BeforeAll {
            $guestUsers = @(
                New-GuestUser -Id 'guest-001' -DisplayName 'Guest One' -UserPrincipalName 'guest1@contoso.com' -Mail 'guest1@contoso.com'
            )
            $subscriptions = @(
                New-Subscription -Id 'sub-001' -Name 'Subscription One'
            )
            Mock Get-AzADUser -ModuleName Check-PrivilegedExternalAccounts { $guestUsers }
            Mock Get-AzSubscription -ModuleName Check-PrivilegedExternalAccounts { $subscriptions }
            Mock Get-AzRoleAssignment -ModuleName Check-PrivilegedExternalAccounts { $null }
        }

        It 'Returns the no privileged permission comment' {
            $result = Check-PrivilegedExternalUsers @commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -Be $script:msgTable.guestAccountsNoPrivilegedPermission
            $result.ComplianceResults.MitigationCommands | Should -Be 'N/A'
        }
    }

    Context 'When a guest user has a privileged role assignment' {
        BeforeAll {
            $guestUsers = @(
                New-GuestUser -Id 'guest-001' -DisplayName 'Guest One' -UserPrincipalName 'guest1@contoso.com' -Mail 'guest1@contoso.com'
            )
            $subscriptions = @(
                New-Subscription -Id 'sub-001' -Name 'Subscription One'
            )
            $matchingAssignments = @(
                New-RoleAssignment -ObjectId 'guest-001' -SignInName 'guest1@contoso.com' -DisplayName 'Guest One' -RoleDefinitionName 'Owner' -Scope '/subscriptions/sub-001'
            )

            Mock Get-AzADUser -ModuleName Check-PrivilegedExternalAccounts { $guestUsers }
            Mock Get-AzSubscription -ModuleName Check-PrivilegedExternalAccounts { $subscriptions }
            Mock Get-AzRoleAssignment -ModuleName Check-PrivilegedExternalAccounts { $matchingAssignments }
        }

        It 'Flags the record as privileged and appends the privileged role comment' {
            $result = Check-PrivilegedExternalUsers @commonParams
            $record = @($result.AdditionalResults.records)[0]

            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -Be $script:msgTable.existingPrivilegedGuestAccountsComment
            $record.PrivilegedRole | Should -Be 'True'
            $record.Comments | Should -BeLike "*$($script:msgTable.guestHasPrivilegedRole)*"
        }
    }

    Context 'When a guest user has only a non-privileged role assignment' {
        BeforeAll {
            $guestUsers = @(
                New-GuestUser -Id 'guest-001' -DisplayName 'Guest One' -UserPrincipalName 'guest1@contoso.com' -Mail 'guest1@contoso.com'
            )
            $subscriptions = @(
                New-Subscription -Id 'sub-001' -Name 'Subscription One'
            )
            $matchingAssignments = @(
                New-RoleAssignment -ObjectId 'guest-001' -SignInName 'guest1@contoso.com' -DisplayName 'Guest One' -RoleDefinitionName 'Reader' -Scope '/subscriptions/sub-001'
            )

            Mock Get-AzADUser -ModuleName Check-PrivilegedExternalAccounts { $guestUsers }
            Mock Get-AzSubscription -ModuleName Check-PrivilegedExternalAccounts { $subscriptions }
            Mock Get-AzRoleAssignment -ModuleName Check-PrivilegedExternalAccounts { $matchingAssignments }
        }

        It 'Flags the record as non-privileged' {
            $result = Check-PrivilegedExternalUsers @commonParams
            $record = @($result.AdditionalResults.records)[0]

            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $record.PrivilegedRole | Should -Be 'False'
            $record.Comments | Should -Be $script:msgTable.guestAssigned
        }
    }
}
