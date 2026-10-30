BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Set-SubscriptionNotEvaluatedStatus { param($Result, $SubscriptionName, $msgTable) $Result.Comments = $msgTable.subscriptionNotEvaluated -f $SubscriptionName; return $Result }
    function global:Get-EvaluationProfile { }

    Import-Module (Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 7 PROTECTION OF DATA-IN-TRANSIT\Audit\Check-StorageAccountTLSversion.psm1') -Force
}

AfterAll {
    Remove-Item Function:\Set-SubscriptionNotEvaluatedStatus -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-EvaluationProfile -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-TLSversion' {
    It 'Maps storage account graph results to subscription names' {
        Mock Search-AzGraph -ModuleName Check-StorageAccountTLSversion {
            @([pscustomobject]@{ subscriptionId = 'sub-1'; resourceGroup = 'rg1'; name = 'stg1'; minimumTlsVersion = 'TLS1_2' })
        }

        $result = Check-TLSversion -objList @([pscustomobject]@{ Id = 'sub-1'; Name = 'Subscription One' })

        $result | Should -HaveCount 1
        $result[0].SubscriptionName | Should -Be 'Subscription One'
        $result[0].TLSversionNumeric | Should -Be '1.2'
    }
}

Describe 'Verify-TLSForStorageAccount' {
    BeforeAll {
        $script:msgTable = @{
            isCompliant              = 'Compliant.'
            isNotCompliant           = 'Non-compliant.'
            storageAccValidTLS       = 'All storage accounts use TLS 1.2.'
            storageAccNotValidTLS    = 'Storage accounts use unsupported TLS.'
            storageAccNotValidList   = 'Affected: {0}'
            subscriptionNotEvaluated = 'Subscription {0} not evaluated.'
        }
        $script:params = @{
            ControlName = 'GUARDRAIL 7'
            ItemName    = 'Storage TLS'
            itsgcode    = 'SC-8'
            msgTable    = $script:msgTable
            ReportTime  = '2026-09-25'
        }
    }

    It 'Returns compliant when all storage accounts use TLS 1.2' {
        Mock Get-AzSubscription -ModuleName Check-StorageAccountTLSversion {
            @([pscustomobject]@{ Id = 'sub-1'; Name = 'Subscription One'; DisplayName = 'Subscription One'; State = 'Enabled' })
        }
        Mock Check-TLSversion -ModuleName Check-StorageAccountTLSversion {
            @([pscustomobject]@{ SubscriptionName = 'Subscription One'; StorageAccountName = 'stg1'; MinimumTlsVersion = 'TLS1_2'; TLSversionNumeric = '1.2' })
        }

        $result = Verify-TLSForStorageAccount @script:params

        $result.ComplianceResults | Should -HaveCount 1
        $result.ComplianceResults[0].ComplianceStatus | Should -BeTrue
        $result.ComplianceResults[0].Comments | Should -Be 'Compliant. All storage accounts use TLS 1.2.'
    }

    It 'Returns non-compliant when a storage account uses TLS 1.0' {
        Mock Get-AzSubscription -ModuleName Check-StorageAccountTLSversion {
            @([pscustomobject]@{ Id = 'sub-1'; Name = 'Subscription One'; DisplayName = 'Subscription One'; State = 'Enabled' })
        }
        Mock Check-TLSversion -ModuleName Check-StorageAccountTLSversion {
            @([pscustomobject]@{ SubscriptionName = 'Subscription One'; StorageAccountName = 'stg1'; MinimumTlsVersion = 'TLS1_0'; TLSversionNumeric = '1.0' })
        }

        $result = Verify-TLSForStorageAccount @script:params

        $result.ComplianceResults[0].ComplianceStatus | Should -BeFalse
        $result.ComplianceResults[0].Comments | Should -BeLike '*stg1*'
    }
}
