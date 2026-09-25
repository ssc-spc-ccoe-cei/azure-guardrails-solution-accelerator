BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:Invoke-GraphQueryEX { }
    function global:Add-ProfileInformation { param($Result) return $Result }

    Import-Module (Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 13 PLAN FOR CONTINUITY\Audit\Monitor-BreakGlassAccount.psm1') -Force
}

AfterAll {
    Remove-Item Function:\Invoke-GraphQueryEX -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Test-BreakGlassAccounts' {
    BeforeAll {
        $script:msgTable = @{
            isCompliant        = 'Compliant.'
            isNotCompliant     = 'Non-compliant.'
            bgAccountNotExist  = 'Break glass accounts are missing.'
            bgAccountLoginValid = 'Break glass accounts signed in within 365 days.'
            bgAccountLoginNotValid = 'Break glass accounts have stale sign-ins.'
        }
        $script:baseParams = @{
            ControlName         = 'GUARDRAIL 13'
            ItemName            = 'Break Glass Monitoring'
            LAWResourceId       = '/subscriptions/sub-1/resourceGroups/rg1/providers/Microsoft.OperationalInsights/workspaces/law1'
            msgTable            = $script:msgTable
            itsgcode            = 'CP-2'
            ReportTime          = '2026-09-25'
        }
    }

    It 'Returns non-compliant when no break glass accounts are configured' {
        $result = Test-BreakGlassAccounts @script:baseParams -FirstBreakGlassUPN '' -SecondBreakGlassUPN ''

        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be ''
        $result.Errors.Count | Should -Be 0
    }

    It 'Returns compliant when both accounts exist and signed in recently' {
        $recentDate = [datetimeoffset]::UtcNow.AddDays(-30).ToString('o')
        Mock Invoke-GraphQueryEX -ModuleName Monitor-BreakGlassAccount {
            param($urlPath)
            switch ($urlPath) {
                '/users/bg1@contoso.com?$select=userPrincipalName,id,userType' { [pscustomobject]@{ Content = [pscustomobject]@{ value = [pscustomobject]@{ id = 'id-1' } } } ; break }
                '/users/bg2@contoso.com?$select=userPrincipalName,id,userType' { [pscustomobject]@{ Content = [pscustomobject]@{ value = [pscustomobject]@{ id = 'id-2' } } } ; break }
                '/users/bg1@contoso.com?$select=id' { [pscustomobject]@{ Content = [pscustomobject]@{ value = [pscustomobject]@{ id = 'id-1' } } } ; break }
                '/users/bg2@contoso.com?$select=id' { [pscustomobject]@{ Content = [pscustomobject]@{ value = [pscustomobject]@{ id = 'id-2' } } } ; break }
                '/users/id-1?$select=userPrincipalName,signInActivity' { [pscustomobject]@{ Content = [pscustomobject]@{ value = [pscustomobject]@{ signInActivity = [pscustomobject]@{ lastSuccessfulSignInDateTime = $recentDate } } } } ; break }
                '/users/id-2?$select=userPrincipalName,signInActivity' { [pscustomobject]@{ Content = [pscustomobject]@{ value = [pscustomobject]@{ signInActivity = [pscustomobject]@{ lastSuccessfulSignInDateTime = $recentDate } } } } ; break }
            }
        }

        $result = Test-BreakGlassAccounts @script:baseParams -FirstBreakGlassUPN 'bg1@contoso.com' -SecondBreakGlassUPN 'bg2@contoso.com'

        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'Compliant. Break glass accounts signed in within 365 days.'
    }
}
