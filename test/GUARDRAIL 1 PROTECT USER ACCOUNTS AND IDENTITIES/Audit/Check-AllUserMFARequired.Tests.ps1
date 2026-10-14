BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'
    $script:savedFunctions = @{}
    foreach ($name in @('Invoke-AzOperationalInsightsQuery', 'Add-ProfileInformation', 'Check-AllUserMFARequired')) {
        $script:savedFunctions[$name] = if (Test-Path "Function:\$name") { (Get-Item "Function:\$name").ScriptBlock } else { $null }
    }
    $script:savedVariables = @{}
    foreach ($name in @('GuardrailsUserRawDataCollectionComplete', 'GuardrailsUserRawDataExpectedRecordCount')) {
        $variable = Get-Variable $name -Scope Global -ErrorAction SilentlyContinue
        $script:savedVariables[$name] = @{ Exists = $null -ne $variable; Value = $variable.Value }
    }
    function global:Invoke-AzOperationalInsightsQuery { [CmdletBinding()] param($WorkspaceId, $Query) throw 'Unmocked Log Analytics call' }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) throw 'Unmocked profile call' }
    $script:testedModule = Import-Module (Join-Path $PSScriptRoot '../../../src/GUARDRAIL 1 PROTECT USER ACCOUNTS AND IDENTITIES/Audit/Check-AllUserMFARequired.psm1') -Force -PassThru
}

AfterAll {
    Remove-Module $script:testedModule -Force -ErrorAction SilentlyContinue
    foreach ($name in $script:savedFunctions.Keys) {
        Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
        if ($null -ne $script:savedFunctions[$name]) { Set-Item "Function:\global:$name" $script:savedFunctions[$name] }
    }
    foreach ($name in $script:savedVariables.Keys) {
        Remove-Variable $name -Scope Global -ErrorAction SilentlyContinue
        if ($script:savedVariables[$name].Exists) { Set-Variable $name -Scope Global -Value $script:savedVariables[$name].Value }
    }
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-AllUserMFARequired' {
    BeforeAll {
        $script:params = @{
            ControlName = 'GUARDRAIL 1'; ItemName = 'All users MFA'; itsgcode = 'IA-2'
            ReportTime = '2026-10-01T00:00:00Z'; WorkSpaceID = 'workspace-001'; mfaGracePeriod = '14'
            msgTable = @{ allUserMfaNotAssessedIncompleteData = 'Current user data is incomplete.' }
        }
        function New-EvaluationRow {
            param($Status = $true, $Count = 3)
            [pscustomobject]@{
                ComplianceStatus = $Status; ControlName = 'GUARDRAIL 1'; ItemName = 'All users MFA'
                itsgcode = 'IA-2'; ReportTime = '2026-10-01T00:00:00Z'
                Comments = 'KQL evaluated current users.'; RawUserRecordCount = $Count
            }
        }
    }
    BeforeEach {
        Remove-Variable GuardrailsUserRawDataCollectionComplete, GuardrailsUserRawDataExpectedRecordCount -Scope Global -ErrorAction SilentlyContinue
        $script:attempt = 0
        Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired { throw 'Unexpected query' }
        Mock Add-ProfileInformation -ModuleName Check-AllUserMFARequired { throw 'Unexpected profile call' }
        Mock Start-Sleep -ModuleName Check-AllUserMFARequired {}
    }

    It 'Preserves the KQL <Status> result, metadata and comments without leaking the raw count' -ForEach @(
        @{ Status = $true }, @{ Status = $false }, @{ Status = 'Not Applicable' }
    ) {
        $script:row = New-EvaluationRow -Status $Status
        Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired { [pscustomobject]@{ Results = @($script:row) } }
        $result = Check-AllUserMFARequired @script:params
        [object]::ReferenceEquals($result.ComplianceResults, $script:row) | Should -BeTrue
        $result.ComplianceResults.ComplianceStatus | Should -Be $Status
        $result.ComplianceResults.Comments | Should -Be 'KQL evaluated current users.'
        foreach ($name in @('ControlName', 'ItemName', 'itsgcode', 'ReportTime')) {
            $result.ComplianceResults.$name | Should -Be $script:params[$name]
        }
        $result.ComplianceResults.PSObject.Properties.Name | Should -Not -Contain 'RawUserRecordCount'
        $result.Errors.Count | Should -Be 0
        Should -Invoke Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired -Exactly -Times 1 -ParameterFilter {
            $WorkspaceId -eq 'workspace-001' -and $Query -match "ReportTime_s == '2026-10-01T00:00:00Z'" -and
            $Query -match "gr_mfa_evaluation\('2026-10-01T00:00:00Z', '14'\)" -and $Query -match 'extend RawUserRecordCount'
        }
        Should -Invoke Start-Sleep -ModuleName Check-AllUserMFARequired -Times 0
        Should -Invoke Add-ProfileInformation -ModuleName Check-AllUserMFARequired -Times 0
    }

    It 'Returns not assessed immediately when upstream collection is incomplete (currently bypassing profile enrichment)' {
        $global:GuardrailsUserRawDataCollectionComplete = $false
        $result = Check-AllUserMFARequired @script:params -EnableMultiCloudProfiles -ErrorAction SilentlyContinue
        $result.ComplianceResults.ComplianceStatus | Should -Be 'Not Applicable'
        $result.ComplianceResults.Comments | Should -Be $script:params.msgTable.allUserMfaNotAssessedIncompleteData
        foreach ($name in @('ControlName', 'ItemName', 'itsgcode', 'ReportTime')) {
            $result.ComplianceResults.$name | Should -Be $script:params[$name]
        }
        $result.Errors.Count | Should -Be 1
        $result.Errors[0] | Should -Match 'collection did not complete'
        Should -Invoke Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired -Times 0
        Should -Invoke Add-ProfileInformation -ModuleName Check-AllUserMFARequired -Times 0
    }

    It 'Retries <Kind> ten times and returns a metadata-bearing not assessed row' -ForEach @(
        @{ Kind = 'empty' }, @{ Kind = 'zero count' }, @{ Kind = 'missing count' }, @{ Kind = 'negative count' }, @{ Kind = 'partial ingestion' }
    ) {
        $script:kind = $Kind
        $global:GuardrailsUserRawDataCollectionComplete = $true
        $global:GuardrailsUserRawDataExpectedRecordCount = 4
        Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired {
            switch ($script:kind) {
                'empty' { [pscustomobject]@{ Results = @() } }
                'missing count' { [pscustomobject]@{ Results = @([pscustomobject]@{ ComplianceStatus = $true }) } }
                'negative count' { [pscustomobject]@{ Results = @(New-EvaluationRow -Count -1) } }
                'partial ingestion' { [pscustomobject]@{ Results = @(New-EvaluationRow -Count 3) } }
                default { [pscustomobject]@{ Results = @(New-EvaluationRow -Count 0) } }
            }
        }
        $result = Check-AllUserMFARequired @script:params -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        $result.ComplianceResults.ComplianceStatus | Should -Be 'Not Applicable'
        $result.ComplianceResults.Comments | Should -Be $script:params.msgTable.allUserMfaNotAssessedIncompleteData
        $result.Errors.Count | Should -Be 1
        $result.Errors[0] | Should -Be 'Failed to call gr_mfa_evaluation KQL function after 10 attempts'
        Should -Invoke Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired -Exactly -Times 10
        Should -Invoke Start-Sleep -ModuleName Check-AllUserMFARequired -Exactly -Times 9 -ParameterFilter { $Seconds -eq 30 }
    }

    It 'Waits for expected ingestion and accepts counts at or above the threshold: <Count>' -ForEach @(@{ Count = 4 }, @{ Count = 5 }) {
        $global:GuardrailsUserRawDataExpectedRecordCount = 4
        $script:count = $Count
        Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired {
            $script:attempt++
            [pscustomobject]@{ Results = @(New-EvaluationRow -Count $(if ($script:attempt -eq 1) { 3 } else { $script:count })) }
        }
        $result = Check-AllUserMFARequired @script:params -WarningAction SilentlyContinue
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.Errors.Count | Should -Be 0
        Should -Invoke Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired -Exactly -Times 2
        Should -Invoke Start-Sleep -ModuleName Check-AllUserMFARequired -Exactly -Times 1
    }

    It 'Recovers from a transient query exception without retaining an error' {
        Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired {
            $script:attempt++
            if ($script:attempt -eq 1) { throw 'Transient timeout' }
            [pscustomobject]@{ Results = @(New-EvaluationRow) }
        }
        $result = Check-AllUserMFARequired @script:params -WarningAction SilentlyContinue
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.Errors.Count | Should -Be 0
        Should -Invoke Start-Sleep -ModuleName Check-AllUserMFARequired -Exactly -Times 1
    }

    It 'Recovers from an empty response and accepts a complete result on the tenth attempt' {
        Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired {
            $script:attempt++
            [pscustomobject]@{ Results = @(if ($script:attempt -eq 10) { New-EvaluationRow }) }
        }
        $result = Check-AllUserMFARequired @script:params -WarningAction SilentlyContinue
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.Errors.Count | Should -Be 0
        Should -Invoke Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired -Exactly -Times 10
        Should -Invoke Start-Sleep -ModuleName Check-AllUserMFARequired -Exactly -Times 9
    }

    It 'Retries malformed raw counts instead of treating an invalid value as evidence of compliance' {
        Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired {
            [pscustomobject]@{ Results = @(New-EvaluationRow -Count 'not-a-count') }
        }
        $result = Check-AllUserMFARequired @script:params -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        $result.ComplianceResults.ComplianceStatus | Should -Be 'Not Applicable'
        $result.Errors.Count | Should -Be 1
        $result.Errors[0] | Should -Match 'All 10 attempts failed'
        Should -Invoke Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired -Exactly -Times 10
        Should -Invoke Start-Sleep -ModuleName Check-AllUserMFARequired -Exactly -Times 9
    }

    It 'Records the final persistent query exception without sleeping after the tenth attempt' {
        Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired { throw 'Log Analytics unavailable' }
        $result = Check-AllUserMFARequired @script:params -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        $result.ComplianceResults.ComplianceStatus | Should -Be 'Not Applicable'
        $result.Errors.Count | Should -Be 1
        $result.Errors[0] | Should -Match 'All 10 attempts failed.*Log Analytics unavailable'
        Should -Invoke Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired -Exactly -Times 10
        Should -Invoke Start-Sleep -ModuleName Check-AllUserMFARequired -Exactly -Times 9
    }

    It 'Uses only the first KQL result and does not leak the count into its schema' {
        Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired {
            [pscustomobject]@{ Results = @((New-EvaluationRow -Status $false), (New-EvaluationRow -Status $true)) }
        }
        $result = Check-AllUserMFARequired @script:params
        @($result.ComplianceResults).Count | Should -Be 1
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
    }

    It 'Enriches both evaluated and not assessed rows: <MissingData>' -ForEach @(@{ MissingData = $false }, @{ MissingData = $true }) {
        $script:missingData = $MissingData
        Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired {
            [pscustomobject]@{ Results = $(if ($script:missingData) { @() } else { @(New-EvaluationRow) }) }
        }
        Mock Add-ProfileInformation -ModuleName Check-AllUserMFARequired {
            param($Result, $ErrorList)
            $Result | Add-Member Profile 2
            [void]$ErrorList.Add('Profile diagnostic')
            $Result
        }
        $result = Check-AllUserMFARequired @script:params -EnableMultiCloudProfiles -CloudUsageProfiles '2,3' -ModuleProfiles '1,2' -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        $result.ComplianceResults.Profile | Should -Be 2
        $result.Errors | Should -Contain 'Profile diagnostic'
        Should -Invoke Add-ProfileInformation -ModuleName Check-AllUserMFARequired -Exactly -Times 1 -ParameterFilter {
            $CloudUsageProfiles -eq '2,3' -and $ModuleProfiles -eq '1,2' -and [string]::IsNullOrEmpty($SubscriptionId) -and $ErrorList -is [System.Collections.ArrayList]
        }
    }

    It 'Adopts a replacement row returned by profile enrichment' {
        Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired { [pscustomobject]@{ Results = @(New-EvaluationRow) } }
        Mock Add-ProfileInformation -ModuleName Check-AllUserMFARequired { [pscustomobject]@{ ComplianceStatus = 'Not Applicable'; Profile = 1; Comments = 'Not evaluated.' } }
        $result = Check-AllUserMFARequired @script:params -EnableMultiCloudProfiles
        $result.ComplianceResults.ComplianceStatus | Should -Be 'Not Applicable'
        $result.ComplianceResults.Comments | Should -Be 'Not evaluated.'
    }

    It 'Preserves the evaluated row and reports enrichment failure' {
        Mock Invoke-AzOperationalInsightsQuery -ModuleName Check-AllUserMFARequired { [pscustomobject]@{ Results = @(New-EvaluationRow -Status $false) } }
        Mock Add-ProfileInformation -ModuleName Check-AllUserMFARequired { throw 'Profile unavailable' }
        $result = Check-AllUserMFARequired @script:params -EnableMultiCloudProfiles -WarningAction SilentlyContinue
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.Errors.Count | Should -Be 1
        $result.Errors[0] | Should -Match 'Failed to add Profile information.*Profile unavailable'
    }
}
