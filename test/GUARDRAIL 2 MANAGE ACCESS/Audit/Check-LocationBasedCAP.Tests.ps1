BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'
    $script:savedFunctions = @{}
    foreach ($name in @('Select-AzSubscription', 'Get-AzContext', 'New-AzStorageContext', 'Get-AzStorageBlob', 'Get-AzStorageBlobContent')) {
        $script:savedFunctions[$name] = (Get-Item "Function:global:$name" -ErrorAction SilentlyContinue).ScriptBlock
        Set-Item "Function:global:$name" {
            [CmdletBinding()]
            param($Subscription, $StorageAccountName, [switch]$UseConnectedAccount, $Container, $Context, $Blob, [switch]$Force)
            throw 'Unmocked Azure/storage dependency'
        }
    }
    Import-Module (Join-Path $PSScriptRoot '../../../src/Guardrails-Common/GR-Common.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '../../../src/GUARDRAIL 2 MANAGE ACCESS/Audit/Check-LocationBasedCAP.psm1') -Force
}

AfterAll {
    Remove-Module Check-LocationBasedCAP, GR-Common -Force -ErrorAction SilentlyContinue
    foreach ($name in $script:savedFunctions.Keys) {
        if ($null -ne $script:savedFunctions[$name]) {
            Set-Item "Function:global:$name" $script:savedFunctions[$name]
        } else {
            Remove-Item "Function:global:$name" -ErrorAction SilentlyContinue
        }
    }
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Get-LocationBasedCAP and its actual shared policy evaluator' {
    BeforeAll {
        $script:params = @{
            ControlName = 'GUARDRAIL 2'; ItemName = 'Allowed locations'; itsgcode = 'AC-3'; ReportTime = '2026-10-14'
            StorageAccountName = 'offline-storage'; ContainerName = 'evidence'; ResourceGroupName = 'rg-test'
            SubscriptionID = 'sub-test'; DocumentName = @('approved-ips')
            msgTable = @{
                isCompliant = 'Pass'; compliantC2 = 'Location protected'; isNotCompliant = 'Fail'; nonCompliantC2 = 'Location unprotected'
                noNamedLocationFound = 'No named location'; noEnabledPoliciesFound = 'No enabled policy'
                noCompliantPoliciesfound = 'No compliant policy'; allPoliciesAreCompliant = 'Compliant policies: {0}'
                noCanadaNamedLocationFound = 'No Canada location'; noCAallLocationsNonCompliant = 'No rest-of-world location'
                noValidIPLocationsNonCompliant = 'No valid IP location'
                approvedIPrangesNotFound = 'Missing IP ranges {0}'; approvedIPrangeFileFound = 'Found IP file {0}'
                approvedIPrangeFileNotFound = 'Missing IP file {0} in {1}/{2}'
                procedureFileNotFoundWithCorrectExtension = 'Wrong extension {0} in {1}/{2}'
            }
        }
        function New-LocationPolicy {
            param($Includes = @('All'), $Excludes = @('canada'), $Controls = @('block'), $State = 'enabled')
            [pscustomobject]@{
                id = 'policy1'; displayName = 'Canada block'; state = $State
                conditions = [pscustomobject]@{
                    locations = [pscustomobject]@{ includeLocations = $Includes; excludeLocations = $Excludes }
                }
                grantControls = [pscustomobject]@{ builtInControls = $Controls }
            }
        }
    }
    BeforeEach {
        $script:locations = @([pscustomobject]@{
            id = 'canada'; displayName = 'Canada'; '@odata.type' = '#microsoft.graph.countryNamedLocation'; countriesAndRegions = @('CA')
        })
        $script:policies = @(New-LocationPolicy)
        Mock Invoke-GraphQueryEX -ModuleName GR-Common {
            switch ($urlPath) {
                '/identity/conditionalAccess/namedLocations' { return @{ Content = @{ value = $script:locations } } }
                '/identity/conditionalAccess/policies' { return @{ Content = @{ value = $script:policies } } }
                default { throw "Unexpected Graph path: $urlPath" }
            }
        }
        Mock Add-ProfileInformation -ModuleName Check-LocationBasedCAP { throw 'Unexpected profile call' }
        Mock Select-AzSubscription -ModuleName GR-Common { throw 'Unexpected subscription call' }
        Mock Get-AzContext -ModuleName GR-Common { throw 'Unexpected context call' }
        Mock New-AzStorageContext -ModuleName GR-Common { throw 'Unexpected storage context call' }
        Mock Get-AzStorageBlob -ModuleName GR-Common { throw 'Unexpected blob call' }
        Mock Get-AzStorageBlobContent -ModuleName GR-Common { throw 'Unexpected download call' }
        Mock Get-Content -ModuleName GR-Common { throw 'Unexpected local file read' }
    }

    It 'Uses the real shared policy helper and returns one envelope with all caller metadata' {
        $output = @(Get-LocationBasedCAP @script:params)
        $output.Count | Should -Be 1
        $output[0].ComplianceResults.ComplianceStatus | Should -BeTrue
        $output[0].ComplianceResults.Comments | Should -Be 'Pass Location protected Compliant policies: Canada block'
        foreach ($key in @('ControlName', 'ItemName', 'ReportTime', 'itsgcode')) {
            $output[0].ComplianceResults.$key | Should -Be $script:params[$key]
        }
        $output[0].Errors.Count | Should -Be 0
        $output[0].AdditionalResults | Should -BeNullOrEmpty
        Should -Invoke Invoke-GraphQueryEX -ModuleName GR-Common -Exactly -Times 2
        Should -Invoke Select-AzSubscription -ModuleName GR-Common -Times 0
        Should -Invoke Get-AzStorageBlob -ModuleName GR-Common -Times 0
        Should -Invoke Add-ProfileInformation -ModuleName Check-LocationBasedCAP -Times 0
    }

    It 'Accepts block-all-except-Canada pattern using <Include> alias' -ForEach @(
        @{ Include = 'all' }, @{ Include = 'any' }, @{ Include = 'alltrusted' }
        @{ Include = 'alltrustedlocations' }, @{ Include = 'alllocations' }, @{ Include = 'ALL' }
    ) {
        $script:policies = @(New-LocationPolicy -Includes @($Include) -Excludes @('CANADA'))
        (Get-LocationBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Accepts a block policy with empty includes and explicit Canada exclusion' {
        $script:policies = @(New-LocationPolicy -Includes @())
        (Get-LocationBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
    }

    It 'Accepts the 249-entry rest-of-world block pattern but not the 248 boundary' -ForEach @(
        @{ Count = 249; Expected = $true }, @{ Count = 248; Expected = $false }
    ) {
        $script:locations = @([pscustomobject]@{
            id = 'world'; displayName = 'Rest of world'; '@odata.type' = '#microsoft.graph.countryNamedLocation'
            countriesAndRegions = @(1..$Count | ForEach-Object { "country-$_" })
        })
        $script:policies = @(New-LocationPolicy -Includes @('WORLD') -Excludes @())
        (Get-LocationBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -Be $Expected
    }

    It 'Rejects <Label> policy' -ForEach @(
        @{ Label = 'grant-only Canada inclusion'; Includes = @('canada'); Excludes = @(); Controls = @('mfa'); State = 'enabled' }
        @{ Label = 'grant rather than block'; Includes = @('All'); Excludes = @('canada'); Controls = @('mfa'); State = 'enabled' }
        @{ Label = 'missing block control'; Includes = @('All'); Excludes = @('canada'); Controls = @(); State = 'enabled' }
        @{ Label = 'wrong exclusion'; Includes = @('All'); Excludes = @('unknown'); Controls = @('block'); State = 'enabled' }
        @{ Label = 'disabled'; Includes = @('All'); Excludes = @('canada'); Controls = @('block'); State = 'disabled' }
        @{ Label = 'report only'; Includes = @('All'); Excludes = @('canada'); Controls = @('block'); State = 'enabledForReportingButNotEnforced' }
    ) {
        $script:policies = @(New-LocationPolicy -Includes $Includes -Excludes $Excludes -Controls $Controls -State $State)
        (Get-LocationBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
    }

    It 'Rejects Canada mixed with another country as an allowed exclusion' {
        $script:locations[0].countriesAndRegions = @('CA', 'US')
        (Get-LocationBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
    }

    It 'Lists all matching policies while ignoring a disabled policy' {
        $second = New-LocationPolicy
        $second.displayName = 'Second block'
        $script:policies += $second
        $script:policies += New-LocationPolicy -State 'disabled'
        $result = Get-LocationBasedCAP @script:params
        $result.ComplianceResults.Comments | Should -Be 'Pass Location protected Compliant policies: Canada block, Second block'
    }

    It 'Fails closed for <Label> named-location responses' -ForEach @(
        @{ Label = 'missing content'; Content = $null }
        @{ Label = 'missing value'; Content = @{} }
        @{ Label = 'empty'; Content = @{ value = @() } }
        @{ Label = 'unsupported location type'; Content = @{ value = @(@{ id = 'unknown'; '@odata.type' = '#other' }) } }
    ) {
        Mock Invoke-GraphQueryEX -ModuleName GR-Common { @{ Content = $Content } } -ParameterFilter { $urlPath -eq '/identity/conditionalAccess/namedLocations' }
        $result = Get-LocationBasedCAP @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'Fail Location unprotected No named location'
        $result.Errors | Should -Contain 'No named locations found. Cannot evaluate Conditional Access Policies for compliance.'
    }

    It 'Fails closed for empty or missing policies' -ForEach @(
        @{ Content = $null }, @{ Content = @{} }, @{ Content = @{ value = @() } }
    ) {
        Mock Invoke-GraphQueryEX -ModuleName GR-Common { @{ Content = $Content } } -ParameterFilter { $urlPath -eq '/identity/conditionalAccess/policies' }
        $result = Get-LocationBasedCAP @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'Fail Location unprotected No enabled policy'
        $result.Errors.Count | Should -Be 1
    }

    It 'Keeps caught Graph errors in a single envelope for <Path>' -ForEach @(
        @{ Path = '/identity/conditionalAccess/namedLocations' }, @{ Path = '/identity/conditionalAccess/policies' }
    ) {
        Mock Invoke-GraphQueryEX -ModuleName GR-Common { throw 'Graph offline' } -ParameterFilter { $urlPath -eq $Path }
        $output = @(Get-LocationBasedCAP @script:params)
        $output.Count | Should -Be 1
        $output[0].ComplianceResults.ComplianceStatus | Should -BeFalse
        $output[0].Errors.Count | Should -Be 2
        $output[0].Errors[0] | Should -Match ([regex]::Escape($Path))
        $output[0].Errors[0] | Should -Match 'Graph offline'
    }

    Context 'IP evidence with all Azure and file operations mocked' {
        BeforeEach {
            $script:locations = @([pscustomobject]@{
                id = 'trusted-ip'; displayName = 'Trusted IP'; '@odata.type' = '#microsoft.graph.ipNamedLocation'
                ipRanges = @([pscustomobject]@{ cidrAddress = '192.0.2.0/24' }, [pscustomobject]@{ cidrAddress = '2001:db8::/32' })
            })
            $script:policies = @(New-LocationPolicy -Excludes @('trusted-ip'))
            $script:cidrs = @(' 192.0.2.0/24 ', '', '2001:db8::/32')
            Mock Select-AzSubscription -ModuleName GR-Common {}
            Mock Get-AzContext -ModuleName GR-Common { @{ Subscription = @{ Name = 'Offline subscription' } } }
            Mock New-AzStorageContext -ModuleName GR-Common { 'offline-context' }
            Mock Get-AzStorageBlob -ModuleName GR-Common { [pscustomobject]@{ Name = 'approved-ips.txt' } }
            Mock Get-AzStorageBlobContent -ModuleName GR-Common { @{ Name = 'mock-evidence.txt' } }
            Mock Get-Content -ModuleName GR-Common { $script:cidrs }
        }

        It 'Trims CIDRs, ignores blank lines and uses connected-account storage with correct parameters' {
            $result = Get-LocationBasedCAP @script:params
            $result.ComplianceResults.ComplianceStatus | Should -BeTrue
            $result.Errors.Count | Should -Be 0
            Should -Invoke Select-AzSubscription -ModuleName GR-Common -Exactly -Times 1 -ParameterFilter { $Subscription -eq 'sub-test' }
            Should -Invoke New-AzStorageContext -ModuleName GR-Common -Exactly -Times 1 -ParameterFilter {
                $StorageAccountName -eq 'offline-storage' -and $UseConnectedAccount
            }
            Should -Invoke Get-AzStorageBlob -ModuleName GR-Common -Exactly -Times 1 -ParameterFilter {
                $Blob -eq 'approved-ips.txt' -and $Container -eq 'evidence' -and $Context -eq 'offline-context'
            }
            Should -Invoke Get-AzStorageBlobContent -ModuleName GR-Common -Exactly -Times 1 -ParameterFilter {
                $Blob -eq 'approved-ips.txt' -and $Force -and $ErrorAction -eq 'Stop'
            }
            Should -Invoke Get-Content -ModuleName GR-Common -Exactly -Times 1 -ParameterFilter { $Path -eq 'mock-evidence.txt' }
        }

        It 'Rejects IP location missing one or all required CIDRs' -ForEach @(
            @{ Ranges = @([pscustomobject]@{ cidrAddress = '192.0.2.0/24' }) }
            @{ Ranges = @([pscustomobject]@{ cidrAddress = '198.51.100.0/24' }) }
            @{ Ranges = @() }
        ) {
            $script:locations[0].ipRanges = $Ranges
            (Get-LocationBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
        }

        It 'Rejects missing evidence and never downloads it' {
            Mock Get-AzStorageBlob -ModuleName GR-Common { $null }
            (Get-LocationBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
            Should -Invoke Get-AzStorageBlobContent -ModuleName GR-Common -Times 0
        }

        It 'Rejects wrong document extension without reading the file' {
            Mock Get-AzStorageBlob -ModuleName GR-Common { @{ Name = 'approved-ips.csv' } }
            (Get-LocationBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
            Should -Invoke Get-Content -ModuleName GR-Common -Times 0
        }

        It 'Rejects empty or whitespace-only evidence' -ForEach @(
            @{ Lines = @() }, @{ Lines = @('', ' ', "`t") }
        ) {
            $script:cidrs = $Lines
            (Get-LocationBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
        }

        It 'Rejects grant-only IP inclusion even with complete evidence' {
            $script:policies = @(New-LocationPolicy -Includes @('trusted-ip') -Excludes @() -Controls @('mfa'))
            (Get-LocationBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
        }

        It 'Accepts empty includes and an explicit valid IP exclusion' {
            $script:policies = @(New-LocationPolicy -Includes @() -Excludes @('trusted-ip'))
            (Get-LocationBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
        }

        It 'Propagates subscription selection failure (current helper contract)' {
            Mock Select-AzSubscription -ModuleName GR-Common { throw 'Selection failed' }
            { Get-LocationBasedCAP @script:params } | Should -Throw '*Select-Azsubscription*Selection failed*'
        }

        It 'Propagates uncaught blob listing and download failures' -ForEach @(
            @{ Command = 'Get-AzStorageBlob' }, @{ Command = 'Get-AzStorageBlobContent' }
        ) {
            Mock $Command -ModuleName GR-Common { throw 'Storage offline' }
            { Get-LocationBasedCAP @script:params } | Should -Throw '*Storage offline*'
        }

        It 'Characterizes a narrow disjoint IP block incorrectly passing as all nontrusted addresses' {
            $script:locations[0].ipRanges = @([pscustomobject]@{ cidrAddress = '198.51.100.0/24' })
            $script:policies = @(New-LocationPolicy -Includes @('trusted-ip') -Excludes @())
            (Get-LocationBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeTrue
        }

        It 'Should reject a narrow disjoint CIDR block as insufficient protection' -Skip {
            # Pattern A equates missing all required CIDRs with covering every nontrusted IP.
            $script:locations[0].ipRanges = @([pscustomobject]@{ cidrAddress = '198.51.100.0/24' })
            $script:policies = @(New-LocationPolicy -Includes @('trusted-ip') -Excludes @())
            (Get-LocationBasedCAP @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
        }
    }

    Context 'Wrapper forwarding and optional profiles' {
        BeforeEach {
            Mock Get-allowedLocationCAPCompliance -ModuleName Check-LocationBasedCAP {
                [void]$ErrorList.Add('Evaluator warning')
                [pscustomobject]@{ ComplianceStatus = $true; Comments = 'Evaluator evidence'; Errors = $ErrorList }
            }
        }
        It 'Forwards all storage inputs, false initial state and the mutable error collection' {
            $result = Get-LocationBasedCAP @script:params
            $result.Errors | Should -Contain 'Evaluator warning'
            $result.ComplianceResults.Comments | Should -Be 'Pass Location protected Evaluator evidence'
            Should -Invoke Get-allowedLocationCAPCompliance -ModuleName Check-LocationBasedCAP -Exactly -Times 1 -ParameterFilter {
                -not $IsCompliant -and $ErrorList -is [System.Collections.ArrayList] -and
                $ItemName -eq 'Allowed locations' -and $DocumentName[0] -eq 'approved-ips' -and
                $SubscriptionID -eq 'sub-test' -and $StorageAccountName -eq 'offline-storage' -and
                $ResourceGroupName -eq 'rg-test' -and $ContainerName -eq 'evidence' -and $msgTable.isCompliant -eq 'Pass'
            }
        }
        It 'Enriches the original result and preserves errors through profile evaluation' {
            Mock Add-ProfileInformation -ModuleName Check-LocationBasedCAP {
                $Result | Add-Member Profile 2
                [void]$ErrorList.Add('Profile warning')
                $Result
            }
            $result = Get-LocationBasedCAP @script:params -EnableMultiCloudProfiles -CloudUsageProfiles '1,2' -ModuleProfiles '2'
            $result.ComplianceResults.Profile | Should -Be 2
            $result.Errors.Count | Should -Be 2
            Should -Invoke Add-ProfileInformation -ModuleName Check-LocationBasedCAP -Exactly -Times 1 -ParameterFilter {
                $SubscriptionId -eq 'sub-test' -and $CloudUsageProfiles -eq '1,2' -and $ModuleProfiles -eq '2'
            }
        }
        It 'Propagates evaluator exceptions rather than hiding them' {
            Mock Get-allowedLocationCAPCompliance -ModuleName Check-LocationBasedCAP { throw 'Evaluator failed' }
            { Get-LocationBasedCAP @script:params } | Should -Throw '*Evaluator failed*'
        }
        It 'Uses the default cloud profile when the feature is enabled without an explicit profile' {
            Mock Add-ProfileInformation -ModuleName Check-LocationBasedCAP { $Result }
            $null = Get-LocationBasedCAP @script:params -EnableMultiCloudProfiles
            Should -Invoke Add-ProfileInformation -ModuleName Check-LocationBasedCAP -Exactly -Times 1 -ParameterFilter {
                $CloudUsageProfiles -eq '3' -and $SubscriptionId -eq 'sub-test'
            }
        }
        It 'Propagates optional profile exceptions' {
            Mock Add-ProfileInformation -ModuleName Check-LocationBasedCAP { throw 'Profile failed' }
            { Get-LocationBasedCAP @script:params -EnableMultiCloudProfiles } | Should -Throw '*Profile failed*'
        }
    }
}
