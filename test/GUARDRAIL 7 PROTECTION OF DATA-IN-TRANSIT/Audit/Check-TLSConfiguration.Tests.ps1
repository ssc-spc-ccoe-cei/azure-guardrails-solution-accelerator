BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Check-BuiltInPoliciesWithResourceGraph { }

    Import-Module (Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 7 PROTECTION OF DATA-IN-TRANSIT\Audit\Check-TLSConfiguration.psm1') -Force
}

AfterAll {
    Remove-Item Function:\Check-BuiltInPoliciesWithResourceGraph -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Verify-TLSConfiguration' {
    BeforeAll {
        $script:msgTable = @{
            appServiceTLSConfig  = 'App Service TLS'
            functionAppTLSConfig = 'Function App TLS'
            sqlDbTLSConfig       = 'SQL DB TLS'
            appGatewayWAFConfig  = 'App Gateway WAF'
        }
        $script:baseParams = @{
            ControlName = 'GUARDRAIL 7'
            itsgcode    = 'SC-8'
            msgTable    = $script:msgTable
            ReportTime  = '2026-09-25'
        }
    }

    It 'Maps app service items to four policy ids' {
        Mock Check-BuiltInPoliciesWithResourceGraph -ModuleName Check-TLSConfiguration {
            ,@([pscustomobject]@{ ComplianceStatus = $true })
        }

        $result = Verify-TLSConfiguration @script:baseParams -ItemName $script:msgTable.appServiceTLSConfig

        $result.ComplianceResults[0].ComplianceStatus | Should -BeTrue
        $result.Errors.Count | Should -Be 0
    }

    It 'Maps function app items to two policy ids' {
        Mock Check-BuiltInPoliciesWithResourceGraph -ModuleName Check-TLSConfiguration {
            ,@([pscustomobject]@{ ComplianceStatus = $true })
        }

        $result = Verify-TLSConfiguration @script:baseParams -ItemName $script:msgTable.functionAppTLSConfig

        $result.ComplianceResults[0].ComplianceStatus | Should -BeTrue
    }
}
