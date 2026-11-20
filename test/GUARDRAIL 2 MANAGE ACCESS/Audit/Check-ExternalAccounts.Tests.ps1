BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) return $Result }

    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 2 MANAGE ACCESS\Audit\Check-ExternalAccounts.psm1'
    Import-Module $modulePath -Force

    $script:msgTable = @{
        noGuestAccounts                = 'No guest accounts found.'
        guestAccountsNoPermission      = 'Guest accounts exist but have no Azure permissions.'
        guestAccountsNoPrivilegedPermission = 'Guest accounts exist but have no privileged Azure permissions.'
        existingGuestAccountsComment   = 'Guest accounts with Azure permissions exist.'
        existingGuestAccounts          = 'Review guest account assignments.'
        existingPrivilegedGuestAccountsComment = 'Privileged guest accounts exist.'
        existingPrivilegedGuestAccounts = 'Review privileged guest account assignments.'
        guestAssigned                  = 'Guest account has an assignment.'
        guestNotAssigned               = 'Guest account has no assignment.'
        guestHasPrivilegedRole         = 'Guest account has a privileged role.'
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
            [string]$RoleDefinitionName = 'Reader',
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

Describe 'Check-ExternalUsers' {
    BeforeAll {
        $script:commonParams = @{
            ControlName = 'GUARDRAIL 2'
            ItemName    = 'External Accounts'
            itsgcode    = 'AC-2'
            msgTable    = $script:msgTable
            ReportTime  = '2026-09-03'
        }
    }

    Context 'When no guest users exist' {
        BeforeAll {
            Mock Get-AzADUser -ModuleName Check-ExternalAccounts { $null }
            Mock Get-AzSubscription -ModuleName Check-ExternalAccounts { @() }
            Mock Get-AzRoleAssignment -ModuleName Check-ExternalAccounts { @() }
        }

        It 'Returns compliant with the no guest accounts comment' {
            $result = Check-ExternalUsers @commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -Be $script:msgTable.noGuestAccounts
            $result.ComplianceResults.MitigationCommands | Should -Be 'N/A'
        }
    }

    Context 'When guest users exist without role assignments in enabled subscriptions' {
        BeforeAll {
            $guestUsers = @(
                New-GuestUser -Id 'guest-001' -DisplayName 'Guest One' -UserPrincipalName 'guest1@contoso.com' -Mail 'guest1@contoso.com'
            )
            $subscriptions = @(
                (New-Subscription -Id 'sub-001' -Name 'Subscription One'),
                (New-Subscription -Id 'sub-002' -Name 'Subscription Two')
            )

            Mock Get-AzADUser -ModuleName Check-ExternalAccounts { $guestUsers }
            Mock Get-AzSubscription -ModuleName Check-ExternalAccounts { $subscriptions }
            Mock Get-AzRoleAssignment -ModuleName Check-ExternalAccounts { $null }
        }

        It 'Returns compliant with the no permission comment' {
            $result = Check-ExternalUsers @commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -Be $script:msgTable.guestAccountsNoPermission
            $result.ComplianceResults.MitigationCommands | Should -Be 'N/A'
        }
    }

    Context 'When guest users exist and at least one has a role assignment' {
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

            Mock Get-AzADUser -ModuleName Check-ExternalAccounts { $guestUsers }
            Mock Get-AzSubscription -ModuleName Check-ExternalAccounts { $subscriptions }
            Mock Get-AzRoleAssignment -ModuleName Check-ExternalAccounts { $matchingAssignments }
        }

        It 'Remains compliant and returns the existing guest accounts guidance' {
            $result = Check-ExternalUsers @commonParams

            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -Be $script:msgTable.existingGuestAccountsComment
            $result.ComplianceResults.MitigationCommands | Should -Be $script:msgTable.existingGuestAccounts
        }
    }
}
