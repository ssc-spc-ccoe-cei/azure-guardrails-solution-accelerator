BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    . (Join-Path $PSScriptRoot '..\..\UnitTestHelpers.ps1')
    $script:guardrailPath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 7 PROTECTION OF DATA-IN-TRANSIT\Audit'
    @(
        'Check-AppServiceHTTPSConfiguration.psm1',
        'Check-ApplicationGatewayCertificateValidity.psm1',
        'Check-FunctionAppHTTPSConfiguration.psm1',
        'Check-SecureConnectionInTransit.psm1',
        'Check-StorageAccountTLSversion.psm1',
        'Check-TLSConfiguration.psm1'
    ) | ForEach-Object { Import-Module (Join-Path $script:guardrailPath $_) -Force }
}

AfterAll {
    Reset-UnitTestHelpers
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Guardrail 7 subscription policy checks' {
    It 'checks HTTPS policy using enabled subscriptions' {
        Mock Get-AzSubscription -ModuleName Check-AppServiceHTTPSConfiguration {
            @(
                [PSCustomObject]@{ Id = 'enabled'; State = 'Enabled' }
                [PSCustomObject]@{ Id = 'disabled'; State = 'Disabled' }
            )
        }
        Mock Check-PBMMPolicies -ModuleName Check-AppServiceHTTPSConfiguration {
            [PSCustomObject]@{ ComplianceStatus = $true }
        }

        $result = Verify-AppServiceHTTPSConfiguration -ControlName 'GUARDRAIL 7' -ItemName 'HTTPS' `
            -PolicyID 'policy' -itsgcode 'SC-8' -msgTable @{} -ReportTime '2026-10-30'

        $result.ComplianceResults.Count | Should -Be 1
        Should -Invoke Check-PBMMPolicies -ModuleName Check-AppServiceHTTPSConfiguration -Times 1 -ParameterFilter {
            $objList.Count -eq 1 -and $requiredPolicyExemptionIds -contains 'webapplicationshouldonlybeaccessibleoverhttps'
        }
    }

    It 'checks function app policies through the shared subscription evaluator' {
        Mock Get-AzSubscription -ModuleName Check-FunctionAppHTTPSConfiguration {
            @([PSCustomObject]@{ Id = 'enabled'; State = 'Enabled' })
        }
        Mock Check-PBMMPolicies -ModuleName Check-FunctionAppHTTPSConfiguration {
            [PSCustomObject]@{ ComplianceStatus = $true }
        }

        $result = Verify-FunctionAppHTTPSConfiguration -ControlName 'GUARDRAIL 7' -ItemName 'Function HTTPS' `
            -PolicyID 'policy' -itsgcode 'SC-8' -msgTable @{} -ReportTime '2026-10-30'

        $result.ComplianceResults.Count | Should -Be 1
        Should -Invoke Check-PBMMPolicies -ModuleName Check-FunctionAppHTTPSConfiguration -Times 1
    }

    It 'reports TLS policy results for the selected item name' {
        Mock Check-BuiltInPoliciesWithResourceGraph -ModuleName Check-TLSConfiguration {
            return ,@([PSCustomObject]@{ ComplianceStatus = $true })
        }

        $result = Verify-TLSConfiguration -ControlName 'GUARDRAIL 7' -ItemName 'App Service TLS' `
            -itsgcode 'SC-8' -msgTable @{ appServiceTLSConfig = 'App Service TLS' } -ReportTime '2026-10-30'

        $result.ComplianceResults.Count | Should -Be 1
        Should -Invoke Check-BuiltInPoliciesWithResourceGraph -ModuleName Check-TLSConfiguration -Times 1 -ParameterFilter {
            $requiredPolicyIds.Count -eq 4
        }
    }

    It 'normalizes Resource Graph storage TLS results and paginates' {
        $script:searchCount = 0
        Mock Search-AzGraph -ModuleName Check-StorageAccountTLSversion {
            $script:searchCount++
            if ($script:searchCount -eq 1) {
                return @([PSCustomObject]@{
                    subscriptionId = 'sub-1'
                    resourceGroup = 'rg'
                    name = 'storage1'
                    minimumTlsVersion = 'TLS1_2'
                    SkipToken = 'next'
                })
            }

            @([PSCustomObject]@{
                subscriptionId = 'sub-1'
                resourceGroup = 'rg'
                name = 'storage2'
                minimumTlsVersion = 'TLS1_0'
            })
        }

        $result = Check-TLSversion -objList @([PSCustomObject]@{ Id = 'sub-1'; Name = 'Subscription 1' })

        $result.Count | Should -Be 2
        $result[0].SubscriptionName | Should -Be 'Subscription 1'
        $result[0].TLSversionNumeric | Should -Be '1.2'
        $script:searchCount | Should -Be 2
    }

    It 'returns a compliant TLS result when a subscription has no storage accounts' {
        Mock Get-AzSubscription -ModuleName Check-StorageAccountTLSversion {
            @([PSCustomObject]@{ Id = 'sub-1'; Name = 'Subscription 1'; State = 'Enabled' })
        }
        Mock Check-TLSversion -ModuleName Check-StorageAccountTLSversion { @() }

        $result = Verify-TLSForStorageAccount -ControlName 'GUARDRAIL 7' -ItemName 'Storage TLS' `
            -msgTable @{ isCompliant = 'Compliant'; storageAccValidTLS = 'TLS is valid' } -ReportTime '2026-10-30'

        $result.ComplianceResults.Count | Should -Be 1
        $result.ComplianceResults[0].ComplianceStatus | Should -BeTrue
    }

    It 'reports a missing approved certificate document without evaluating gateways' {
        Mock Select-AzSubscription -ModuleName Check-ApplicationGatewayCertificateValidity {}
        Mock Get-AzContext -ModuleName Check-ApplicationGatewayCertificateValidity {
            [PSCustomObject]@{ Subscription = [PSCustomObject]@{ Name = 'Subscription 1' } }
        }
        Mock Get-AzStorageAccount -ModuleName Check-ApplicationGatewayCertificateValidity {
            [PSCustomObject]@{ Context = 'storage-context' }
        }
        Mock Get-AzStorageBlob -ModuleName Check-ApplicationGatewayCertificateValidity { @() }

        $result = Check-ApplicationGatewayCertificateValidity -ControlName 'GUARDRAIL 7' `
            -ItemName 'Approved CA' -itsgcode 'SC-8' -msgTable @{ approvedCAFileNotFound = 'Missing {0}' } `
            -ReportTime '2026-10-30' -StorageAccountName 'storage' -ContainerName 'approved' `
            -ResourceGroupName 'rg' -SubscriptionID 'sub-1' -DocumentName @('ca-list')

        $result.ComplianceResults.Count | Should -Be 1
        $result.ComplianceResults[0].ComplianceStatus | Should -BeFalse
        $result.ComplianceResults[0].Comments | Should -BeLike '*Missing*'
    }
}

Describe 'Verify-SecureConnectionInTransit' {
    It 'passes required policy identifiers to the shared evaluator' {
        Mock Get-AzSubscription -ModuleName Check-SecureConnectionInTransit {
            @([PSCustomObject]@{ Id = 'sub-1'; State = 'Enabled' })
        }
        Mock Check-PBMMPolicies -ModuleName Check-SecureConnectionInTransit {
            [PSCustomObject]@{ ComplianceStatus = $true }
        }

        $result = Verify-SecureConnectionInTransit -ControlName 'GUARDRAIL 7' -ItemName 'Secure transit' `
            -PolicyID 'policy' -itsgcode 'SC-8' -msgTable @{} -ReportTime '2026-10-30'

        $result.ComplianceResults.Count | Should -Be 1
        Should -Invoke Check-PBMMPolicies -ModuleName Check-SecureConnectionInTransit -Times 1 -ParameterFilter {
            $requiredPolicyExemptionIds -contains 'SecureTransferToStorageAccountsShouldBeEnabled' -and
            $requiredPolicyExemptionIds -contains 'OnlySecureConnectionsToYourRedisCacheShouldBeEnabled'
        }
    }
}
