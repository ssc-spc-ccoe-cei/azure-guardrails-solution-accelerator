BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'
    $script:dependencyNames = @('Invoke-GraphQueryEX', 'Add-ProfileInformation')
    $script:previousFunctions = @{}
    foreach ($name in $script:dependencyNames) {
        $script:previousFunctions[$name] = if (Test-Path "Function:\$name") { (Get-Item "Function:\$name").ScriptBlock } else { $null }
    }
    function global:Invoke-GraphQueryEX { [CmdletBinding()] param($urlPath) throw 'Unmocked Graph dependency' }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) throw 'Unmocked profile dependency' }
    $script:previousModules = @(Get-Module Get-AzureADLicenseType)
    $modulePath = Join-Path $PSScriptRoot '../../../src/GUARDRAIL 1 PROTECT USER ACCOUNTS AND IDENTITIES/Audit/Get-AzureADLicenseType.psm1'
    $script:testModule = Import-Module $modulePath -PassThru
    $script:params = @{
        ControlName = 'GUARDRAIL 1'; ItemName = 'Entra license'; itsgcode = 'IA-2'; ReportTime = '2026-10-14'
        msgTable = @{ MSEntIDLicenseTypeFound = 'P2 found'; MSEntIDLicenseTypeNotFound = 'P2 missing' }
    }
}

AfterAll {
    if ($script:previousModules.Count -eq 0) { Remove-Module $script:testModule -ErrorAction SilentlyContinue }
    foreach ($name in $script:dependencyNames) {
        if ($null -ne $script:previousFunctions[$name]) {
            Set-Item "Function:\global:$name" -Value $script:previousFunctions[$name]
        } else { Remove-Item "Function:\$name" -ErrorAction SilentlyContinue }
    }
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Get-ADLicenseType' {
    BeforeEach {
        Mock Invoke-GraphQueryEX -ModuleName Get-AzureADLicenseType {
            @{ Content = @{ value = @(@{ servicePlans = @(@{ ServicePlanName = 'AAD_PREMIUM_P2' }) }) }; StatusCode = 200 }
        }
    }

    It 'Finds P2 and preserves all compliance metadata without profile evaluation by default' {
        $output = @(Get-ADLicenseType @script:params)
        $output.Count | Should -Be 1
        $result = $output[0]
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.ADLicenseType | Should -Be 'AAD_PREMIUM_P2'
        $result.ComplianceResults.Comments | Should -Be 'P2 found'
        foreach ($name in 'ControlName', 'ItemName', 'itsgcode', 'ReportTime') {
            $result.ComplianceResults.$name | Should -Be $script:params[$name]
        }
        $result.Errors.Count | Should -Be 0
        $result.PSObject.Properties.Name | Should -Contain 'AdditionalResults'
        $result.AdditionalResults | Should -BeNullOrEmpty
        Should -Invoke Invoke-GraphQueryEX -ModuleName Get-AzureADLicenseType -Times 1 -Exactly -ParameterFilter { $urlPath -eq '/subscribedSkus' }
    }

    It 'Searches every SKU and service plan, case-insensitively' {
        Mock Invoke-GraphQueryEX -ModuleName Get-AzureADLicenseType {
            @{ Content = @{ value = @(
                @{ servicePlans = @(@{ ServicePlanName = 'OTHER' }) },
                @{ servicePlans = @(@{ ServicePlanName = 'AAD_PREMIUM' }, @{ ServicePlanName = 'aad_premium_p2' }) }
            ) } }
        }
        (Get-ADLicenseType @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Returns noncompliant for <Label>' -ForEach @(
        @{ Label = 'no SKUs'; Response = @{ Content = @{ value = @() } } },
        @{ Label = 'null response'; Response = $null },
        @{ Label = 'missing content'; Response = @{} },
        @{ Label = 'null service plans'; Response = @{ Content = @{ value = @(@{ servicePlans = $null }) } } },
        @{ Label = 'P1 only'; Response = @{ Content = @{ value = @(@{ servicePlans = @(@{ ServicePlanName = 'AAD_PREMIUM' }) }) } } },
        @{ Label = 'a lookalike plan'; Response = @{ Content = @{ value = @(@{ servicePlans = @(@{ ServicePlanName = 'AAD_PREMIUM_P2_EXTRA' }) }) } } }
    ) {
        Mock Invoke-GraphQueryEX -ModuleName Get-AzureADLicenseType { $Response }
        $result = Get-ADLicenseType @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.ADLicenseType | Should -Be 'N/A'
        $result.ComplianceResults.Comments | Should -Be 'P2 missing'
        $result.Errors.Count | Should -Be 0
    }

    It 'Records a caught Graph failure and exposes the current extraneous ArrayList index output' {
        Mock Invoke-GraphQueryEX -ModuleName Get-AzureADLicenseType { throw 'Graph unavailable' }
        $output = @(Get-ADLicenseType @script:params -ErrorVariable failure -ErrorAction SilentlyContinue)
        $output.Count | Should -Be 2
        $output[0] | Should -Be 0
        $output[1].ComplianceResults.ComplianceStatus | Should -BeFalse
        $output[1].ComplianceResults.Comments | Should -Be 'P2 missing'
        $output[1].Errors.Count | Should -Be 1
        $output[1].Errors[0] | Should -BeLike '*Microsoft Graph*/subscribedSkus*Graph unavailable*'
        ($failure | Out-String) | Should -BeLike '*Graph unavailable*'
    }

    It 'Desired behavior: emits only the result object on Graph failure (ArrayList.Add currently leaks an index)' -Skip {
        Mock Invoke-GraphQueryEX -ModuleName Get-AzureADLicenseType { throw 'Graph unavailable' }
        @(Get-ADLicenseType @script:params -ErrorAction SilentlyContinue).Count | Should -Be 1
    }

    It 'Passes tenant-level profile arguments and returns in-place profile changes' {
        Mock Add-ProfileInformation -ModuleName Get-AzureADLicenseType {
            param($Result)
            $Result | Add-Member NoteProperty Profile 2
            $Result.ComplianceStatus = 'Not Applicable'
            $Result.Comments = 'Profile excluded'
            $Result
        }
        $result = Get-ADLicenseType @script:params -EnableMultiCloudProfiles -CloudUsageProfiles '1,2' -ModuleProfiles '2'
        $result.ComplianceResults.Profile | Should -Be 2
        $result.ComplianceResults.ComplianceStatus | Should -Be 'Not Applicable'
        $result.ComplianceResults.Comments | Should -Be 'Profile excluded'
        Should -Invoke Add-ProfileInformation -ModuleName Get-AzureADLicenseType -Times 1 -Exactly -ParameterFilter {
            $CloudUsageProfiles -eq '1,2' -and $ModuleProfiles -eq '2' -and
            [string]::IsNullOrEmpty($SubscriptionId) -and $ErrorList.Count -eq 0 -and $Result.ItemName -eq 'Entra license'
        }
    }

    It 'Passes accumulated Graph errors to profile evaluation' {
        Mock Invoke-GraphQueryEX -ModuleName Get-AzureADLicenseType { throw 'Graph unavailable' }
        Mock Add-ProfileInformation -ModuleName Get-AzureADLicenseType { param($Result) $Result }
        $output = @(Get-ADLicenseType @script:params -EnableMultiCloudProfiles -ErrorAction SilentlyContinue)
        $output.Count | Should -Be 2
        $output[1].Errors.Count | Should -Be 1
        Should -Invoke Add-ProfileInformation -ModuleName Get-AzureADLicenseType -Times 1 -Exactly -ParameterFilter {
            $CloudUsageProfiles -eq '3' -and $ErrorList.Count -eq 1 -and $ErrorList[0] -like '*Graph unavailable*'
        }
    }
}
