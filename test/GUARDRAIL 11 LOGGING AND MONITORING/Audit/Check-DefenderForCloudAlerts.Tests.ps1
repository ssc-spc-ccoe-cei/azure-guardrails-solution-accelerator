BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Set-SubscriptionNotEvaluatedStatus { param($Result) return $Result }
    function global:Add-ProfileInformation { param($Result) return $Result }

    Import-Module (Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 11 LOGGING AND MONITORING\Audit\Check-DefenderForCloudAlerts.psm1') -Force
}

AfterAll {
    Remove-Item Function:\Set-SubscriptionNotEvaluatedStatus -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Get-CwpCoverageForSubscription' {
    It 'Reports missing Standard plans when mapped resources exist' {
        $msgTable = @{ NoMappedResourcesOrMappingIncomplete = 'No resources'; CwpPlansNotStandard = 'Missing plans: {0}'; CoverageOk = 'Coverage ok' }
        $counts = @{ 'sub-1' = @{ 'microsoft.compute/virtualmachines' = 1 } }
        $map = @{ 'microsoft.compute/virtualmachines' = 'VirtualMachines' }
        $pricing = @{ 'VirtualMachines' = 'Free' }

        $result = Get-CwpCoverageForSubscription -SubscriptionId 'sub-1' -CountsBySub $counts -TypeToPlanMap $map -PricingByPlan $pricing -msgTable $msgTable

        $result.coverageOk | Should -BeFalse
        $result.comment | Should -Be 'Missing plans: VirtualMachines'
    }
}

Describe 'Get-DFCAcheckComplianceStatus' {
    It 'Returns compliant when contacts and notification sources are configured' {
        $msgTable = @{
            EmailsOrOwnerNotConfigured      = 'Need more contacts for {0}'
            AlertNotificationNotConfigured  = 'Alert notifications missing.'
            AttackPathNotificationNotConfigured = 'Attack path notifications missing.'
            DefenderCompliant               = 'Defender contacts are compliant.'
        }
        $apiResponse = [pscustomobject]@{
            properties = [pscustomobject]@{
                notificationsSources = @(
                    [pscustomobject]@{ sourceType = 'Alert'; minimalSeverity = 'Low' },
                    [pscustomobject]@{ sourceType = 'AttackPath'; minimalRiskLevel = 'Medium' }
                )
                emails = 'one@contoso.com;two@contoso.com'
                notificationsByRole = [pscustomobject]@{ roles = @('Owner'); state = 'Off' }
            }
        }

        $result = Get-DFCAcheckComplianceStatus -apiResponse $apiResponse -msgTable $msgTable -subscriptionId 'sub-1' -SubscriptionName 'Subscription One'

        $result.isCompliant | Should -BeTrue
        $result.Comments | Should -Be 'Defender contacts are compliant.'
    }
}

Describe 'Get-DefenderForCloudAlerts' {
    It 'Returns non-compliant when Microsoft.Security is not registered' {
        $msgTable = @{
            NotAllSubsHaveDefenderPlans   = 'Defender plans are not enabled.'
            FoundationalCspmOnlyInfo      = 'Free tier only.'
            errorRetrievingNotifications  = 'Unable to retrieve notifications.'
            DefenderEnabledNonCompliant   = 'Defender enabled but non-compliant.'
            DefenderCompliant             = 'Defender compliant.'
            CwpInformational              = 'CWP: {0}'
        }
        Mock Get-AzSubscription -ModuleName Check-DefenderForCloudAlerts {
            @([pscustomobject]@{ Id = 'sub-1'; SubscriptionId = 'sub-1'; Name = 'Subscription One'; State = 'Enabled' })
        }
        Mock Get-ResourceCountsFromARG -ModuleName Check-DefenderForCloudAlerts { @{} }
        Mock Set-AzContext -ModuleName Check-DefenderForCloudAlerts { }
        Mock Get-AzContext -ModuleName Check-DefenderForCloudAlerts { [pscustomobject]@{ Subscription = [pscustomobject]@{ TenantId = 'tenant-1' } } }
        Mock Get-AzAccessToken -ModuleName Check-DefenderForCloudAlerts {
            $secureToken = New-Object System.Security.SecureString
            'token'.ToCharArray() | ForEach-Object { $secureToken.AppendChar($_) }
            [pscustomobject]@{ Token = $secureToken }
        }
        Mock Invoke-RestMethod -ModuleName Check-DefenderForCloudAlerts -ParameterFilter { $Uri -like '*/providers/Microsoft.Security?*' } { [pscustomobject]@{ registrationState = 'Unregistered' } }

        $result = Get-DefenderForCloudAlerts -ControlName 'GUARDRAIL 11' -ItemName 'Defender Alerts' -itsgcode 'SI-4' -msgTable $msgTable -ReportTime '2026-09-25'

        $result.ComplianceResults[0].ComplianceStatus | Should -BeFalse
        $result.ComplianceResults[0].Comments | Should -Be 'Defender plans are not enabled.'
    }
}
