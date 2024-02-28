Describe "Get-ADLicenseType Function Tests" {
    Context "When AAD_PREMIUM_P2 license is found" {
        BeforeAll {
            $ControlName = "GUARDRAIL 1 PROTECT ROOT GLOBAL ADMINS ACCOUNT"
            $ItemName = "Microsoft Entra ID License Type"
            $itsgcode = "AC2(7)"
            $msgTable = @{
                MSEntIDLicenseTypeNotFound = "Required Microsoft Entra ID license type not found"
                MSEntIDLicenseTypeFound = "Found correct license type"
            }
            $ReportTime = Get-Date
    
            # Mocking Invoke-GraphQuery function
            Mock Invoke-GraphQuery {
                return @{
                    Content = @{
                        "value" = @(
                            @{
                                "servicePlans" = @(
                                    @{
                                        "ServicePlanName" = "AAD_PREMIUM_P2"
                                    }
                                )
                            }
                        )
                    }
                }
            }    
        }
        It "Should return compliant status" {
            $result = Get-ADLicenseType -ControlName $ControlName -itsgcode $itsgcode -msgTable $msgTable -ItemName $ItemName -ReportTime $ReportTime
            $result.ComplianceResults.ComplianceStatus | Should -Be $true
        }

        It "Should return correct license type" {
            $result = Get-ADLicenseType -ControlName $ControlName -itsgcode $itsgcode -msgTable $msgTable -ItemName $ItemName -ReportTime $ReportTime
            $result.ComplianceResults.ADLicenseType | Should -Be "AAD_PREMIUM_P2"
        }

        It "Should return correct comments" {
            $result = Get-ADLicenseType -ControlName $ControlName -itsgcode $itsgcode -msgTable $msgTable -ItemName $ItemName -ReportTime $ReportTime
            $result.ComplianceResults.Comments | Should -Be $msgTable.MSEntIDLicenseTypeFound
        }
    }
}