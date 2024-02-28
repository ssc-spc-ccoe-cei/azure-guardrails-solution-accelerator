Import-Module ".\src\GUARDRAIL 1 PROTECT ROOT  GLOBAL ADMINS ACCOUNT\Audit\Check-BreakGlassAccountIdentityProtectionLicense.psm1"

Describe "Get-BreakGlassAccountLicense Function" {
    BeforeAll {
        $FirstBreakGlassUPN = "bga1@163cspmdev.onmicrosoft.com"
        $SecondBreakGlassUPN = "bga2@163CSPMDEV.onmicrosoft.com"
        $ControlName = "Guardrails1"
        $ItemName = "Break Glass Microsoft Entra ID P2"
        $itsgcode = "AC2(7)"

        $msgTable = @{
            firstBgAccount          = "First BG Account"
            secondBgAccount         = "Second BG Account"
            bgValidLicenseAssigned  = "has a valid license assigned"
            bgNoValidLicenseAssigned = "does not have a valid license assigned"
        }
    }

    It "Should return compliant results when both accounts have a valid license" {
        $result = Get-BreakGlassAccountLicense -FirstBreakGlassUPN $FirstBreakGlassUPN -SecondBreakGlassUPN $SecondBreakGlassUPN -ControlName $ControlName -ItemName $ItemName -itsgcode $itsgcode -msgTable $msgTable -ReportTime "2024-01-01"
        $result.ComplianceResults.ComplianceStatus | Should -Be $true
    }

    It "Should return non-compliant results when the first account does not have a valid license" {
        $result = Get-BreakGlassAccountLicense -FirstBreakGlassUPN $FirstBreakGlassUPN -SecondBreakGlassUPN $SecondBreakGlassUPN -ControlName $ControlName -ItemName $ItemName -itsgcode $itsgcode -msgTable $msgTable -ReportTime "2024-01-01"
        $result.ComplianceResults.ComplianceStatus | Should -Be $false
    }

    It "Should return non-compliant results when the second account does not have a valid license" {
        $result = Get-BreakGlassAccountLicense -FirstBreakGlassUPN $FirstBreakGlassUPN -SecondBreakGlassUPN $SecondBreakGlassUPN -ControlName $ControlName -ItemName $ItemName -itsgcode $itsgcode -msgTable $msgTable -ReportTime "2024-01-01"
        $result.ComplianceResults.ComplianceStatus | Should -Be $false
    }
}