Import-Module '.\src\GUARDRAIL 1 PROTECT ROOT  GLOBAL ADMINS ACCOUNT\Audit\Check-BreakGlassAccountOwnersInformation.psm1'

Describe "Get-BreakGlassOwnerinformation Function" {
    BeforeAll{
        $FirstBreakGlassUPNOwner = "test123@gmail.com"
        $SecondBreakGlassUPNOwner = "test321@gmail.com"
        $ControlName = "Guardrails1"
        $ItemName = "Break Glass Account Owners Contact information"
        $itsgcode = "AC2"


        $msgTable = @{
            bgAccountHasManager = "{0} has a manager listed in the directory."
            bgAccountNoManager  = "{0} doesn't have a manager listed in the directory."
            bgBothHaveManager   = "Both Break Glass Accounts have a manager listed in the directory."
        }
    }

    It "Should return compliant results when both accounts have a manager listed" {
        $result = Get-BreakGlassOwnerinformation -FirstBreakGlassUPNOwner $FirstBreakGlassUPNOwner -SecondBreakGlassUPNOwner $SecondBreakGlassUPNOwner -ControlName $ControlName -ItemName $ItemName -itsgcode $itsgcode -msgTable $msgTable -ReportTime "2024-01-01"
        $result.ComplianceResults.ComplianceStatus | Should -Be $true
    }

    It "Should return non-compliant results when the first account doesn't have a manager listed" {
        $result = Get-BreakGlassOwnerinformation -FirstBreakGlassUPNOwner "noncompliant1@contoso.com" -SecondBreakGlassUPNOwner $SecondBreakGlassUPNOwner -ControlName $ControlName -ItemName $ItemName -itsgcode $itsgcode -msgTable $msgTable -ReportTime "2024-01-01"
        $result.ComplianceResults.ComplianceStatus | Should -Be $false
    }

    It "Should return non-compliant results when the second account doesn't have a manager listed" {
        $result = Get-BreakGlassOwnerinformation -FirstBreakGlassUPNOwner $FirstBreakGlassUPNOwner -SecondBreakGlassUPNOwner $SecondBreakGlassUPNOwner -ControlName $ControlName -ItemName $ItemName -itsgcode $itsgcode -msgTable $msgTable -ReportTime "2024-01-01"
        $result.ComplianceResults.ComplianceStatus | Should -Be $false
    }
}
