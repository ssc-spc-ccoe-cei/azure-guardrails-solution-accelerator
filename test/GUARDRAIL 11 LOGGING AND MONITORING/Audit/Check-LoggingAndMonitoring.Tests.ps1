BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    . (Join-Path $PSScriptRoot '..\..\UnitTestHelpers.ps1')
    $script:guardrailPath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 11 LOGGING AND MONITORING\Audit'
    @('Check-DefenderForCloudAlerts.psm1', 'Check-ServiceHealthAlerts.psm1') |
        ForEach-Object { Import-Module (Join-Path $script:guardrailPath $_) -Force }
}

AfterAll {
    Reset-UnitTestHelpers
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Get-ActionGroupContactTokens' {
    It 'returns distinct, trimmed email contacts' {
        $actionGroup = [PSCustomObject]@{
            EmailReceiver = @(
                [PSCustomObject]@{ EmailAddress = ' ops@example.test ' }
                [PSCustomObject]@{ EmailAddress = 'ops@example.test' }
                [PSCustomObject]@{ EmailAddress = 'alerts@example.test' }
            )
            ArmRoleReceiver = @()
        }

        $contacts = Get-ActionGroupContactTokens -ActionGroup @($actionGroup)

        $contacts.Count | Should -Be 2
        $contacts | Should -Contain 'ops@example.test'
        $contacts | Should -Contain 'alerts@example.test'
    }
}

Describe 'Validate-ActionGroups' {
    It 'counts contacts from enabled action groups' {
        $alert = [PSCustomObject]@{
            ActionGroup = [PSCustomObject]@{ Id = 'action-group-1' }
        }
        $actionGroup = [PSCustomObject]@{
            Id = 'action-group-1'
            EmailReceiver = @([PSCustomObject]@{ EmailAddress = 'ops@example.test' })
            ArmRoleReceiver = @()
        }

        $result = Validate-ActionGroups -alerts @($alert) -SubscriptionName 'Subscription 1' `
            -SubscriptionId 'sub-1' -MsgTable @{ noServiceHealthActionGroups = 'No action groups for {0}' } `
            -allEnabledActionGroups @($actionGroup)

        $result.EffectiveContactCount | Should -Be 1
        $result.UniqueContacts | Should -Contain 'ops@example.test'
        $result.Errors.Count | Should -Be 0
    }
}

Describe 'Get-ServiceHealthAlerts' {
    It 'returns no compliance rows when there are no enabled subscriptions' {
        Mock Get-AzSubscription -ModuleName Check-ServiceHealthAlerts { @() }

        $result = Get-ServiceHealthAlerts -ControlName 'GUARDRAIL 11' -ItemName 'Service health alerts' `
            -itsgcode 'SI-4' -msgTable @{} -ReportTime '2026-10-30'

        $result.ComplianceResults.Count | Should -Be 0
        $result.Errors.Count | Should -Be 0
    }
}

Describe 'Get-DefenderForCloudAlerts' {
    It 'fails closed when no access token can be obtained' {
        Mock Get-AzSubscription -ModuleName Check-DefenderForCloudAlerts {
            @([PSCustomObject]@{ Id = 'sub-1'; SubscriptionId = 'sub-1'; Name = 'Subscription 1'; State = 'Enabled' })
        }
        Mock Get-ResourceCountsFromARG -ModuleName Check-DefenderForCloudAlerts { @{} }
        Mock Set-AzContext -ModuleName Check-DefenderForCloudAlerts {}
        Mock Get-AzContext -ModuleName Check-DefenderForCloudAlerts {
            [PSCustomObject]@{ Subscription = [PSCustomObject]@{ TenantId = 'tenant-1' } }
        }
        Mock Get-AzAccessToken -ModuleName Check-DefenderForCloudAlerts { throw 'Token unavailable' }

        $result = Get-DefenderForCloudAlerts -ControlName 'GUARDRAIL 11' -ItemName 'Defender' `
            -itsgcode 'SI-4' -msgTable @{ NotAllSubsHaveDefenderPlans = 'No Defender plan' } `
            -ReportTime '2026-10-30'

        $result.ComplianceResults.Count | Should -Be 1
        $result.ComplianceResults[0].ComplianceStatus | Should -BeFalse
        $result.ComplianceResults[0].Comments | Should -BeLike '*missing auth token*'
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
