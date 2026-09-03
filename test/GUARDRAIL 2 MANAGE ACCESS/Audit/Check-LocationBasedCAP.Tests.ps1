BeforeAll {
    # Ensure Write-Error in source modules stays non-terminating (CI and VS Code set $ErrorActionPreference = 'Stop')
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    # Define stubs for external functions
    function global:Get-allowedLocationCAPCompliance { }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) return $Result }

    # Import the module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 2 MANAGE ACCESS\Audit\Check-LocationBasedCAP.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Item Function:\Get-allowedLocationCAPCompliance -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Get-LocationBasedCAP' {

    BeforeAll {
        $script:msgTable = @{
            isCompliant    = 'Compliant.'
            compliantC2    = 'Allowed locations conditional access policy is configured.'
            isNotCompliant = 'Non-compliant.'
            nonCompliantC2 = 'Allowed locations conditional access policy is not configured.'
        }
        $script:commonParams = @{
            ControlName = 'GUARDRAIL 2'
            ItemName    = 'Location Based CAP'
            itsgcode    = 'AC-2'
            msgTable    = $script:msgTable
            ReportTime  = (Get-Date -Format 'yyyy-MM-dd')
        }
    }

    Context 'When allowed location CAP is compliant' {

        BeforeAll {
            Mock Get-allowedLocationCAPCompliance -ModuleName Check-LocationBasedCAP {
                [PSCustomObject]@{
                    ComplianceStatus = $true
                    Comments         = 'Canada-only named location is enforced.'
                    Errors           = [System.Collections.ArrayList]::new()
                    ControlName      = 'GUARDRAIL 2'
                    ItemName         = 'Location Based CAP'
                    ReportTime       = (Get-Date -Format 'yyyy-MM-dd')
                    itsgcode         = 'AC-2'
                }
            }
        }

        It 'Returns compliant with combined comments' {
            $result = Get-LocationBasedCAP @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.ComplianceResults.Comments | Should -Be "$($script:msgTable.isCompliant) $($script:msgTable.compliantC2) Canada-only named location is enforced."
        }
    }

    Context 'When allowed location CAP is non-compliant' {

        BeforeAll {
            Mock Get-allowedLocationCAPCompliance -ModuleName Check-LocationBasedCAP {
                [PSCustomObject]@{
                    ComplianceStatus = $false
                    Comments         = 'No valid named location was assigned to the policy.'
                    Errors           = [System.Collections.ArrayList]::new()
                    ControlName      = 'GUARDRAIL 2'
                    ItemName         = 'Location Based CAP'
                    ReportTime       = (Get-Date -Format 'yyyy-MM-dd')
                    itsgcode         = 'AC-2'
                }
            }
        }

        It 'Returns non-compliant with combined comments' {
            $result = Get-LocationBasedCAP @commonParams
            $result.ComplianceResults.ComplianceStatus | Should -BeFalse
            $result.ComplianceResults.Comments | Should -Be "$($script:msgTable.isNotCompliant) $($script:msgTable.nonCompliantC2) No valid named location was assigned to the policy."
        }
    }

    Context 'When EnableMultiCloudProfiles is set' {

        BeforeAll {
            Mock Get-allowedLocationCAPCompliance -ModuleName Check-LocationBasedCAP {
                [PSCustomObject]@{
                    ComplianceStatus = $true
                    Comments         = 'Policy is compliant.'
                    Errors           = [System.Collections.ArrayList]::new()
                }
            }
            Mock Add-ProfileInformation -ModuleName Check-LocationBasedCAP { param($Result) return $Result }
        }

        It 'Calls Add-ProfileInformation' {
            $params = $script:commonParams.Clone()
            $result = Get-LocationBasedCAP @params -EnableMultiCloudProfiles -CloudUsageProfiles '3' -ModuleProfiles '1,2,3'
            Should -Invoke Add-ProfileInformation -ModuleName Check-LocationBasedCAP -Times 1
        }
    }
}
