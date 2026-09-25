BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Add-ProfileInformation { param($Result) return $Result }
    function global:Set-SubscriptionNotEvaluatedStatus { param($Result) return $Result }

    Import-Module (Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 11 LOGGING AND MONITORING\Audit\Check-ServiceHealthAlerts.psm1') -Force
}

AfterAll {
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    Remove-Item Function:\Set-SubscriptionNotEvaluatedStatus -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Get-ActionGroupContactTokens' {
    It 'Returns email and owner contact tokens' {
        $group = [pscustomobject]@{
            EmailReceiver = @([pscustomobject]@{ EmailAddress = 'ops@contoso.com' })
            ArmRoleReceiver = @([pscustomobject]@{ RoleName = 'Owner'; Name = 'sub-owner' })
        }

        $result = Get-ActionGroupContactTokens -ActionGroup $group

        $result | Should -Contain 'ops@contoso.com'
        $result | Should -Contain 'Owner::sub-owner'
    }
}

Describe 'Validate-ActionGroups' {
    It 'Counts owner targets using the effective owner count' {
        Mock Get-SubscriptionOwnerCount -ModuleName Check-ServiceHealthAlerts { 2 }
        $msgTable = @{ noServiceHealthActionGroups = 'No action groups for {0}' }
        $alert = [pscustomobject]@{ ActionGroup = @([pscustomobject]@{ Id = '/ag/1' }) }
        $group = [pscustomobject]@{ Id = '/ag/1'; ArmRoleReceiver = @([pscustomobject]@{ RoleName = 'Owner'; Name = 'owner' }) }

        $result = Validate-ActionGroups -alerts @($alert) -SubscriptionName 'Subscription One' -SubscriptionId 'sub-1' -MsgTable $msgTable -allEnabledActionGroups @($group)

        $result.EffectiveContactCount | Should -Be 2
    }
}

Describe 'Get-ServiceHealthAlerts' {
    BeforeAll {
        $script:msgTable = @{
            noEnabledHealthAlert       = 'No enabled service health alert.'
            EventTypeMissingForAlert   = 'Event types missing for {0}'
            compliantServiceHealthAlerts = 'Service health alerts are compliant.'
            nonCompliantActionGroups   = 'Action groups are not compliant.'
            noServiceHealthAlerts      = 'Failed to retrieve service health alerts for {0}'
            noServiceHealthActionGroups = 'No action groups for {0}'
        }
        $script:params = @{
            ControlName = 'GUARDRAIL 11'
            ItemName    = 'Service Health Alerts'
            itsgcode    = 'AU-5'
            msgTable    = $script:msgTable
            ReportTime  = '2026-09-25'
        }
    }

    It 'Returns compliant when alerts and action groups meet requirements' {
        $alertCondition = @(
            [pscustomobject]@{ Field = 'category'; Equal = 'ServiceHealth'; AnyOf = @() },
            [pscustomobject]@{ Field = 'incidentType'; Equal = $null; AnyOf = @([pscustomobject]@{ Field = 'properties.incidentType'; Equal = 'Security' }) }
        )
        $alerts = @(
            [pscustomobject]@{ Enabled = $true; ActionGroup = @([pscustomobject]@{ Id = '/ag/1' }); ConditionAllOf = $alertCondition },
            [pscustomobject]@{ Enabled = $true; ActionGroup = @([pscustomobject]@{ Id = '/ag/1' }); ConditionAllOf = @([pscustomobject]@{ Field = 'category'; Equal = 'ServiceHealth'; AnyOf = @() }, [pscustomobject]@{ Field = 'incidentType'; Equal = $null; AnyOf = @([pscustomobject]@{ Field = 'properties.incidentType'; Equal = 'Informational' }) }) },
            [pscustomobject]@{ Enabled = $true; ActionGroup = @([pscustomobject]@{ Id = '/ag/1' }); ConditionAllOf = @([pscustomobject]@{ Field = 'category'; Equal = 'ServiceHealth'; AnyOf = @() }, [pscustomobject]@{ Field = 'incidentType'; Equal = $null; AnyOf = @([pscustomobject]@{ Field = 'properties.incidentType'; Equal = 'Incident' }) }) }
        )

        Mock Get-AzSubscription -ModuleName Check-ServiceHealthAlerts { @([pscustomobject]@{ Id = 'sub-1'; Name = 'Subscription One'; State = 'Enabled' }) }
        Mock Select-AzSubscription -ModuleName Check-ServiceHealthAlerts { }
        Mock Set-AzContext -ModuleName Check-ServiceHealthAlerts { }
        Mock Get-AzResourceGroup -ModuleName Check-ServiceHealthAlerts { @([pscustomobject]@{ ResourceGroupName = 'rg1' }) }
        Mock Get-AzActionGroup -ModuleName Check-ServiceHealthAlerts { @([pscustomobject]@{ Id = '/ag/1'; Enabled = $true }) }
        Mock Get-AzActivityLogAlert -ModuleName Check-ServiceHealthAlerts { $alerts }
        Mock Validate-ActionGroups -ModuleName Check-ServiceHealthAlerts { [pscustomobject]@{ UniqueContacts = @('a','b'); EffectiveContactCount = 2; Comments = @(); Errors = @() } }

        $result = Get-ServiceHealthAlerts @script:params

        $result.ComplianceResults[0].ComplianceStatus | Should -BeTrue
        $result.ComplianceResults[0].Comments | Should -Be 'Service health alerts are compliant.'
    }

    It 'Returns non-compliant when no service health alerts exist' {
        Mock Get-AzSubscription -ModuleName Check-ServiceHealthAlerts { @([pscustomobject]@{ Id = 'sub-1'; Name = 'Subscription One'; State = 'Enabled' }) }
        Mock Select-AzSubscription -ModuleName Check-ServiceHealthAlerts { }
        Mock Set-AzContext -ModuleName Check-ServiceHealthAlerts { }
        Mock Get-AzResourceGroup -ModuleName Check-ServiceHealthAlerts { @([pscustomobject]@{ ResourceGroupName = 'rg1' }) }
        Mock Get-AzActionGroup -ModuleName Check-ServiceHealthAlerts { @() }
        Mock Get-AzActivityLogAlert -ModuleName Check-ServiceHealthAlerts { @() }

        $result = Get-ServiceHealthAlerts @script:params

        $result.ComplianceResults[0].ComplianceStatus | Should -BeFalse
        $result.ComplianceResults[0].Comments | Should -Be 'No enabled service health alert.'
    }
}
