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
    $script:module = Import-Module (Join-Path $PSScriptRoot '../../../src/GUARDRAIL 2 MANAGE ACCESS/Audit/Check-ExternalAccounts.psm1') -Force -PassThru
    & $script:module { $script:debug = $false; $script:subscriptionId = $null }
    $script:params = @{
        ControlName = 'GUARDRAIL 2'; ItemName = 'External accounts'; itsgcode = 'AC-2'; ReportTime = '2026-10-14'
        msgTable = @{
            noGuestAccounts = 'No guests.'; guestAccountsNoPermission = 'Guests without subscription permission.'
            guestAssigned = 'Assigned.'; guestNotAssigned = 'Unassigned.'
            existingGuestAccountsComment = 'Existing guest accounts.'; existingGuestAccounts = 'Review guests.'
        }
    }
    $script:guest = [pscustomobject]@{
        Id = 'guest-1'; DisplayName = 'Guest One'; Mail = 'guest@example.test'; UserPrincipalName = 'guest@example.test'
        UserType = 'Guest'; CreatedDateTime = '2025-01-01'; AccountEnabled = $true
    }
}

AfterAll {
    Remove-Module $script:module -ErrorAction SilentlyContinue
    foreach ($name in $script:createdStubs) { Remove-Item "Function:\$name" -ErrorAction SilentlyContinue }
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-ExternalUsers' {
    BeforeEach {
        Mock Get-AzADUser -ModuleName Check-ExternalAccounts { $null }
        Mock Get-AzSubscription -ModuleName Check-ExternalAccounts { @() }
        Mock Get-AzRoleAssignment -ModuleName Check-ExternalAccounts { $null }
        Mock Add-ProfileInformation -ModuleName Check-ExternalAccounts { throw 'Unexpected profile call' }
        Mock Send-OMSAPIIngestionFile -ModuleName Check-ExternalAccounts { throw 'Unexpected ingestion' }
        Mock Write-Host -ModuleName Check-ExternalAccounts {}
    }

    It 'Returns compliant metadata for absent guests without querying subscriptions' {
        $output = @(Check-ExternalUsers @script:params)
        $result = $output[-1]
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'No guests.'
        $result.ComplianceResults.MitigationCommands | Should -Be 'N/A'
        $result.Errors.Count | Should -Be 0
        foreach ($key in @('ControlName', 'ItemName', 'itsgcode', 'ReportTime')) {
            $result.ComplianceResults.$key | Should -Be $script:params[$key]
        }
        $result.PSObject.Properties.Name | Should -Not -Contain 'AdditionalResults'
        Should -Invoke Get-AzADUser -ModuleName Check-ExternalAccounts -Times 1 -Exactly -ParameterFilter { $Filter -eq "usertype eq 'guest'" }
        Should -Invoke Get-AzSubscription -ModuleName Check-ExternalAccounts -Times 0 -Exactly
        Should -Invoke Add-ProfileInformation -ModuleName Check-ExternalAccounts -Times 0 -Exactly
        Should -Invoke Send-OMSAPIIngestionFile -ModuleName Check-ExternalAccounts -Times 0 -Exactly
    }

    # Desired: return only the module-output object; send diagnostics and ArrayList indices outside the success stream.
    It 'Characterizes the extra success-stream string and ArrayList index for absent guests' {
        $output = @(Check-ExternalUsers @script:params)
        $output.Count | Should -Be 3
        $output[0] | Should -Be 'No Guest Users found in the tenant'
        $output[1] | Should -Be 0
    }

    It 'Handles an empty user collection as no guests' {
        Mock Get-AzADUser -ModuleName Check-ExternalAccounts { @() }
        (@(Check-ExternalUsers @script:params)[-1]).ComplianceResults.Comments | Should -Be 'No guests.'
    }

    It 'Returns the no-permission message when guests exist but no enabled subscription exists' {
        Mock Get-AzADUser -ModuleName Check-ExternalAccounts { $script:guest }
        Mock Get-AzSubscription -ModuleName Check-ExternalAccounts { [pscustomobject]@{ Id = 'disabled'; State = 'Disabled' } }
        $result = @(Check-ExternalUsers @script:params)[-1]
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'Guests without subscription permission.'
        $result.ComplianceResults.MitigationCommands | Should -Be 'N/A'
        Should -Invoke Get-AzRoleAssignment -ModuleName Check-ExternalAccounts -Times 0 -Exactly
    }

    It 'Returns the no-permission message when assignments are null' {
        Mock Get-AzADUser -ModuleName Check-ExternalAccounts { $script:guest }
        Mock Get-AzSubscription -ModuleName Check-ExternalAccounts { [pscustomobject]@{ Id = 'sub-1'; Name = 'One'; State = 'Enabled' } }
        $result = @(Check-ExternalUsers @script:params)[-1]
        $result.ComplianceResults.Comments | Should -Be 'Guests without subscription permission.'
        Should -Invoke Get-AzRoleAssignment -ModuleName Check-ExternalAccounts -Times 1 -Exactly -ParameterFilter { $Scope -eq '/subscriptions/sub-1' }
    }

    # Desired: a failed directory lookup must not be reported as a successful no-guest audit.
    It 'Characterizes nonterminating directory errors as a compliant no-guest result' {
        Mock Get-AzADUser -ModuleName Check-ExternalAccounts { Write-Error 'Directory unavailable' -ErrorAction Continue }
        $result = @(Check-ExternalUsers @script:params 2>$null)[-1]
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'No guests.'
        $result.Errors.Count | Should -Be 0
    }

    It 'Handles empty role assignments like null assignments' {
        Mock Get-AzADUser -ModuleName Check-ExternalAccounts { $script:guest }
        Mock Get-AzSubscription -ModuleName Check-ExternalAccounts { [pscustomobject]@{ Id = 'sub-1'; Name = 'One'; State = 'Enabled' } }
        Mock Get-AzRoleAssignment -ModuleName Check-ExternalAccounts { @() }
        (@(Check-ExternalUsers @script:params)[-1]).ComplianceResults.Comments | Should -Be 'Guests without subscription permission.'
    }

    It 'Is informational and remains compliant with a <role> assigned to a guest' -ForEach @(
        @{ role = 'Owner' }, @{ role = 'Reader' }
    ) {
        Mock Get-AzADUser -ModuleName Check-ExternalAccounts { $script:guest }
        Mock Get-AzSubscription -ModuleName Check-ExternalAccounts {
            @([pscustomobject]@{ Id = 'sub-1'; Name = 'One'; State = 'Enabled' }, [pscustomobject]@{ Id = 'disabled'; State = 'Disabled' })
        }
        Mock Get-AzRoleAssignment -ModuleName Check-ExternalAccounts { [pscustomobject]@{ ObjectId = 'guest-1'; RoleDefinitionName = $role } }
        $result = @(Check-ExternalUsers @script:params)[-1]
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'Existing guest accounts.'
        $result.ComplianceResults.MitigationCommands | Should -Be 'Review guests.'
        $result.Errors.Count | Should -Be 0
        Should -Invoke Get-AzRoleAssignment -ModuleName Check-ExternalAccounts -Times 1 -Exactly
    }

    It 'Records unassigned guests when only unrelated role assignments exist' {
        Mock Get-AzADUser -ModuleName Check-ExternalAccounts { $script:guest }
        Mock Get-AzSubscription -ModuleName Check-ExternalAccounts { [pscustomobject]@{ Id = 'sub-1'; Name = 'One'; State = 'Enabled' } }
        Mock Get-AzRoleAssignment -ModuleName Check-ExternalAccounts { [pscustomobject]@{ ObjectId = 'member-1' } }
        $result = @(Check-ExternalUsers @script:params)[-1]
        $result.ComplianceResults.Comments | Should -Be 'Existing guest accounts.'
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Queries each enabled subscription exactly once' {
        Mock Get-AzADUser -ModuleName Check-ExternalAccounts { $script:guest }
        Mock Get-AzSubscription -ModuleName Check-ExternalAccounts {
            @([pscustomobject]@{ Id = 'sub-1'; State = 'Enabled' }, [pscustomobject]@{ Id = 'sub-2'; State = 'Enabled' })
        }
        Check-ExternalUsers @script:params | Out-Null
        Should -Invoke Get-AzRoleAssignment -ModuleName Check-ExternalAccounts -Times 1 -Exactly -ParameterFilter { $Scope -eq '/subscriptions/sub-1' }
        Should -Invoke Get-AzRoleAssignment -ModuleName Check-ExternalAccounts -Times 1 -Exactly -ParameterFilter { $Scope -eq '/subscriptions/sub-2' }
    }

    It 'Propagates a failure in <dependency> (there is no catch in this audit)' -ForEach @(
        @{ dependency = 'Get-AzADUser' }, @{ dependency = 'Get-AzSubscription' }, @{ dependency = 'Get-AzRoleAssignment' }
    ) {
        Mock Get-AzADUser -ModuleName Check-ExternalAccounts { $script:guest }
        Mock Get-AzSubscription -ModuleName Check-ExternalAccounts { [pscustomobject]@{ Id = 'sub-1'; State = 'Enabled' } }
        Mock $dependency -ModuleName Check-ExternalAccounts { throw 'Dependency unavailable' }
        { Check-ExternalUsers @script:params } | Should -Throw '*Dependency unavailable*'
    }

    It 'Preserves profile mutation and appended errors and forwards explicit profile configuration' {
        Mock Add-ProfileInformation -ModuleName Check-ExternalAccounts {
            param($Result, $ErrorList)
            $Result | Add-Member Profile 2
            $Result.ComplianceStatus = 'Not Applicable'
            [void]$ErrorList.Add('Profile diagnostic')
            $Result
        }
        $result = @(Check-ExternalUsers @script:params -EnableMultiCloudProfiles -CloudUsageProfiles '1,2' -ModuleProfiles '2')[-1]
        $result.ComplianceResults.Profile | Should -Be 2
        $result.ComplianceResults.ComplianceStatus | Should -Be 'Not Applicable'
        @($result.Errors) | Should -Contain 'Profile diagnostic'
        Should -Invoke Add-ProfileInformation -ModuleName Check-ExternalAccounts -Times 1 -Exactly -ParameterFilter {
            $CloudUsageProfiles -eq '1,2' -and $ModuleProfiles -eq '2' -and $null -eq $SubscriptionId
        }
    }

    It 'Passes the default cloud profile to the helper' {
        Mock Add-ProfileInformation -ModuleName Check-ExternalAccounts { param($Result) $Result }
        Check-ExternalUsers @script:params -EnableMultiCloudProfiles | Out-Null
        Should -Invoke Add-ProfileInformation -ModuleName Check-ExternalAccounts -Times 1 -Exactly -ParameterFilter { $CloudUsageProfiles -eq '3' }
    }

    It 'Propagates profile helper failures' {
        Mock Add-ProfileInformation -ModuleName Check-ExternalAccounts { throw 'Profile unavailable' }
        { Check-ExternalUsers @script:params -EnableMultiCloudProfiles } | Should -Throw '*Profile unavailable*'
    }
}
