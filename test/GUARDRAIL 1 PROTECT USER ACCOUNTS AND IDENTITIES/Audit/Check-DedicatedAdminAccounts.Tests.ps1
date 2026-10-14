BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'
    $script:dependencyNames = @('Invoke-GraphQueryEX', 'add-documentFileExtensions', 'Set-AzContext', 'New-ConnectedStorageContext', 'Get-AzStorageBlob', 'Add-ProfileInformation')
    $script:previousFunctions = @{}
    foreach ($name in $script:dependencyNames) {
        $script:previousFunctions[$name] = if (Test-Path "Function:\$name") { (Get-Item "Function:\$name").ScriptBlock } else { $null }
    }
    function global:Invoke-GraphQueryEX { [CmdletBinding()] param($urlPath) throw 'Unmocked Graph dependency' }
    function global:add-documentFileExtensions { param($DocumentName, $ItemName) throw 'Unmocked document dependency' }
    function global:Set-AzContext { [CmdletBinding()] param($Subscription) throw 'Unmocked context dependency' }
    function global:New-ConnectedStorageContext { param($storageaccountName) throw 'Unmocked storage dependency' }
    function global:Get-AzStorageBlob { [CmdletBinding()] param($Container, $Context, [string[]]$Blob) throw 'Unmocked blob dependency' }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) throw 'Unmocked profile dependency' }
    $script:previousModules = @(Get-Module Check-DedicatedAdminAccounts)
    $modulePath = Join-Path $PSScriptRoot '../../../src/GUARDRAIL 1 PROTECT USER ACCOUNTS AND IDENTITIES/Audit/Check-DedicatedAdminAccounts.psm1'
    $script:testModule = Import-Module $modulePath -PassThru
    $script:params = @{
        StorageAccountName = 'evidence'; ContainerName = 'attestations'; ResourceGroupName = 'rg-001'; SubscriptionID = 'sub-001'
        ControlName = 'GUARDRAIL 1'; ItemName = 'Dedicated user accounts for administration'; itsgcode = 'AC-6'; ReportTime = '2026-10-14'
        FirstBreakGlassUPN = 'bg.one@example.test'; SecondBreakGlassUPN = 'bg.two@example.test'; DocumentName = @('accounts')
        msgTable = @{
            procedureFileNotFoundWithCorrectExtension = 'Wrong extension: {0} in {1} on {2}.'
            procedureFileNotFound = 'Missing file: {0} in {1} on {2}.'
            invalidUserFile = 'Invalid content: {0}.'; invalidFileHeader = 'Invalid header: {0}.'
            isNotCompliant = 'Noncompliant.'; isCompliant = 'Compliant.'
            bgAccExistInUPNlist = 'Breakglass listed.'; missingHPaccUPN = 'HP missing.'; missingRegAccUPN = 'Regular missing.'
            dupHPAccount = 'Duplicate HP.'; dupRegAccount = 'Duplicate regular.'
            dedicatedAdminAccNotExist = 'Admin is regular.'; regAccHasHProle = 'Regular is privileged.'
            dedicatedAccExist = 'Dedicated accounts exist.'; hpAccNotGA = 'HP not privileged.'
        }
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

Describe 'Check-DedicatedAdminAccounts' {
    BeforeEach {
        $script:csv = "HP_admin_account_UPN,regular_account_UPN`nadmin@example.test,user@example.test"
        $script:downloadFailure = $false
        $script:members = @(
            @{ userPrincipalName = 'admin@example.test' }, @{ userPrincipalName = 'admin2@example.test' },
            @{ userPrincipalName = '' }, @{ userPrincipalName = $null }, @{ id = 'service-principal' }
        )
        Mock Invoke-GraphQueryEX -ModuleName Check-DedicatedAdminAccounts {
            param($urlPath)
            switch ($urlPath) {
                '/directoryRoles' { @{ Content = @{ value = @(
                    @{ id = 'ga'; displayName = 'Global Administrator' },
                    @{ id = 'pra'; displayName = 'Privileged Role Administrator' },
                    @{ id = 'reader'; displayName = 'Global Reader' }
                ) } } }
                '/directoryRoles/ga/members' { @{ Content = @{ value = $script:members } } }
                '/directoryRoles/pra/members' { @{ Content = @{ value = @(@{ userPrincipalName = 'pra@example.test' }) } } }
                default { throw "Unexpected Graph path $urlPath" }
            }
        }
        Mock add-documentFileExtensions -ModuleName Check-DedicatedAdminAccounts { @('accounts.csv') }
        Mock Set-AzContext -ModuleName Check-DedicatedAdminAccounts {}
        Mock New-ConnectedStorageContext -ModuleName Check-DedicatedAdminAccounts { 'connected-context' }
        Mock Get-AzStorageBlob -ModuleName Check-DedicatedAdminAccounts {
            param($Blob)
            if (-not $Blob) { [pscustomobject]@{ Name = 'accounts.csv' } }
            else {
                $content = [pscustomobject]@{ Text = $script:csv; Fail = $script:downloadFailure }
                $content | Add-Member ScriptMethod DownloadText {
                    if ($this.Fail) { throw 'download denied' }
                    $this.Text
                }
                [pscustomobject]@{ ICloudBlob = $content }
            }
        }
    }

    It 'Validates documented dedicated administrators without scanning the tenant user list' {
        $output = @(Check-DedicatedAdminAccounts @script:params)
        $output.Count | Should -Be 1
        $result = $output[0]
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'Compliant. Dedicated accounts exist.'
        $result.Errors.Count | Should -Be 0
        foreach ($name in 'ControlName', 'ItemName', 'itsgcode', 'ReportTime') {
            $result.ComplianceResults.$name | Should -Be $script:params[$name]
        }
        $result.AdditionalResults | Should -BeNullOrEmpty
        Should -Invoke Invoke-GraphQueryEX -ModuleName Check-DedicatedAdminAccounts -Times 3 -Exactly
        Should -Invoke Invoke-GraphQueryEX -ModuleName Check-DedicatedAdminAccounts -Times 0 -Exactly -ParameterFilter { $urlPath -like '/users*' -or $urlPath -eq '/directoryRoles/reader/members' }
        Should -Invoke add-documentFileExtensions -ModuleName Check-DedicatedAdminAccounts -Times 1 -Exactly -ParameterFilter {
            $DocumentName[0] -eq 'accounts' -and $ItemName -eq 'Dedicated user accounts for administration'
        }
        Should -Invoke Set-AzContext -ModuleName Check-DedicatedAdminAccounts -Times 1 -Exactly -ParameterFilter { $Subscription -eq 'sub-001' }
        Should -Invoke New-ConnectedStorageContext -ModuleName Check-DedicatedAdminAccounts -Times 1 -Exactly -ParameterFilter { $storageaccountName -eq 'evidence' }
        Should -Invoke Get-AzStorageBlob -ModuleName Check-DedicatedAdminAccounts -Times 1 -Exactly -ParameterFilter {
            $Container -eq 'attestations' -and $Context -eq 'connected-context' -and $Blob -and $Blob[0] -eq 'accounts.csv'
        }
    }

    It 'Uses both highly privileged roles and trims UPNs for case-insensitive lookups' {
        $script:csv = "HP_admin_account_UPN,regular_account_UPN`n ADMIN@EXAMPLE.TEST , user@example.test `nPRA@example.test,user2@example.test"
        $result = Check-DedicatedAdminAccounts @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Not -BeLike '*HP not privileged*'
    }

    It 'Rejects <Label> documented account data' -ForEach @(
        @{ Label = 'breakglass admin'; Rows = 'bg.one@example.test,user@example.test'; Expected = 'Breakglass listed.' },
        @{ Label = 'breakglass regular'; Rows = 'admin@example.test,bg.two@example.test'; Expected = 'Breakglass listed.' },
        @{ Label = 'missing admin'; Rows = ',user@example.test'; Expected = 'HP missing.' },
        @{ Label = 'missing regular'; Rows = 'admin@example.test,'; Expected = 'Regular missing.' },
        @{ Label = 'admin also regular'; Rows = 'ADMIN@example.test,admin@example.test'; Expected = 'Admin is regular.' },
        @{ Label = 'privileged regular'; Rows = 'admin@example.test,pra@example.test'; Expected = 'Regular is privileged.' }
    ) {
        $script:csv = "HP_admin_account_UPN,regular_account_UPN`n$Rows"
        $result = Check-DedicatedAdminAccounts @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be "Noncompliant. $Expected"
        $result.Errors.Count | Should -Be 0
    }

    It 'Rejects invalid CSV headers' {
        $script:csv = "Admin,Regular`nadmin@example.test,user@example.test"
        $result = Check-DedicatedAdminAccounts @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'Noncompliant. Invalid header: accounts.csv.'
    }

    It 'Rejects <Label> CSV content' -ForEach @(
        @{ Label = 'empty'; Csv = '' },
        @{ Label = 'header only'; Csv = 'HP_admin_account_UPN,regular_account_UPN' },
        @{ Label = 'NA only'; Csv = 'NA' },
        @{ Label = 'N/A only'; Csv = 'N/A' }
    ) {
        $script:csv = $Csv
        $result = Check-DedicatedAdminAccounts @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'Invalid content: accounts.csv.'
    }

    It 'Reports a missing evidence file for <Label>' -ForEach @(
        @{ Label = 'null listing'; Listing = $null }, @{ Label = 'empty listing'; Listing = @() },
        @{ Label = 'unrelated names'; Listing = @(@{ Name = 'other.csv' }) }
    ) {
        Mock Get-AzStorageBlob -ModuleName Check-DedicatedAdminAccounts { $Listing }
        $result = Check-DedicatedAdminAccounts @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'Missing file: accounts in attestations on evidence.'
        Should -Invoke Get-AzStorageBlob -ModuleName Check-DedicatedAdminAccounts -Times 0 -Exactly -ParameterFilter { $Blob }
    }

    It 'Reports a matching base name with the wrong extension' {
        Mock Get-AzStorageBlob -ModuleName Check-DedicatedAdminAccounts { @{ Name = 'accounts.pdf' } }
        $result = Check-DedicatedAdminAccounts @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be 'Wrong extension: accounts in attestations on evidence.'
    }

    It 'Remains noncompliant when a listed matching blob disappears before download' {
        Mock Get-AzStorageBlob -ModuleName Check-DedicatedAdminAccounts { $null } -ParameterFilter { $Blob }
        $result = Check-DedicatedAdminAccounts @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be ''
        $result.Errors.Count | Should -Be 0
    }

    It 'Rejects two distinct duplicated <Label> groups at the current threshold' -ForEach @(
        @{ Label = 'admin'; Rows = "admin@example.test,user1@example.test`nadmin@example.test,user2@example.test`nadmin2@example.test,user3@example.test`nadmin2@example.test,user4@example.test"; Expected = 'Duplicate HP.' },
        @{ Label = 'regular'; Rows = "admin@example.test,user1@example.test`nadmin2@example.test,user1@example.test`npra@example.test,user2@example.test`nadmin3@example.test,user2@example.test"; Expected = 'Duplicate regular.' }
    ) {
        $script:csv = "HP_admin_account_UPN,regular_account_UPN`n$Rows"
        $result = Check-DedicatedAdminAccounts @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be "Noncompliant. $Expected"
    }

    It 'Rejects a single duplicated <Label> group because scalar GroupInfo.Count counts its rows' -ForEach @(
        @{ Label = 'admin'; Rows = "admin@example.test,user1@example.test`nadmin@example.test,user2@example.test"; Expected = 'Duplicate HP.' },
        @{ Label = 'regular'; Rows = "admin@example.test,user@example.test`nadmin2@example.test,user@example.test"; Expected = 'Duplicate regular.' }
    ) {
        $script:csv = "HP_admin_account_UPN,regular_account_UPN`n$Rows"
        $result = Check-DedicatedAdminAccounts @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -Be "Noncompliant. $Expected"
    }

    It 'Currently marks an administrator without a privileged role compliant and appends a warning' {
        $script:csv = "HP_admin_account_UPN,regular_account_UPN`nunprivileged@example.test,user@example.test"
        $result = Check-DedicatedAdminAccounts @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -Be 'Compliant. Dedicated accounts exist. HP not privileged.'
    }

    It 'Desired behavior: documented HP accounts require a privileged role (hpUPNnotGA never clears compliance)' -Skip {
        $script:csv = "HP_admin_account_UPN,regular_account_UPN`nunprivileged@example.test,user@example.test"
        (Check-DedicatedAdminAccounts @script:params).ComplianceResults.ComplianceStatus | Should -BeFalse
    }

    It 'Handles an empty directory role list without querying members, but currently still reports compliant' {
        Mock Invoke-GraphQueryEX -ModuleName Check-DedicatedAdminAccounts { @{ Content = @{ value = @() } } }
        $result = Check-DedicatedAdminAccounts @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.Comments | Should -BeLike '*HP not privileged*'
        Should -Invoke Invoke-GraphQueryEX -ModuleName Check-DedicatedAdminAccounts -Times 1 -Exactly
    }

    It 'Handles null role membership content without inventing privileged UPNs' {
        Mock Invoke-GraphQueryEX -ModuleName Check-DedicatedAdminAccounts { @{ Content = $null } } -ParameterFilter { $urlPath -like '/directoryRoles/*/members' }
        $result = Check-DedicatedAdminAccounts @script:params
        $result.ComplianceResults.Comments | Should -Be 'Compliant. Dedicated accounts exist. HP not privileged.'
        $result.Errors.Count | Should -Be 0
    }

    It 'Records a caught role query failure, including the current leaked ArrayList index' {
        Mock Invoke-GraphQueryEX -ModuleName Check-DedicatedAdminAccounts { throw 'roles denied' }
        $output = @(Check-DedicatedAdminAccounts @script:params 2>$null)
        $output.Count | Should -Be 2
        $output[0] | Should -Be 0
        $output[1].Errors.Count | Should -Be 1
        $output[1].Errors[0] | Should -BeLike '*/directoryRoles*roles denied*'
        $output[1].ComplianceResults.ComplianceStatus | Should -BeTrue
        $output[1].ComplianceResults.Comments | Should -BeLike '*HP not privileged*'
    }

    It 'Does not reuse GA members when the following PRA membership query fails' {
        Mock Invoke-GraphQueryEX -ModuleName Check-DedicatedAdminAccounts { throw 'PRA denied' } -ParameterFilter { $urlPath -eq '/directoryRoles/pra/members' }
        $script:csv = "HP_admin_account_UPN,regular_account_UPN`npra@example.test,user@example.test"
        $output = @(Check-DedicatedAdminAccounts @script:params 2>$null)
        $output.Count | Should -Be 2
        $output[0] | Should -Be 0
        $output[1].Errors[0] | Should -BeLike '*/directoryRoles/pra/members*PRA denied*'
        $output[1].ComplianceResults.Comments | Should -BeLike '*HP not privileged*'
    }

    It 'Records a caught download failure, invalid content and the leaked ArrayList index' {
        $script:downloadFailure = $true
        $output = @(Check-DedicatedAdminAccounts @script:params 2>$null)
        $output.Count | Should -Be 2
        $output[0] | Should -Be 0
        $output[1].ComplianceResults.ComplianceStatus | Should -BeFalse
        $output[1].ComplianceResults.Comments | Should -Be 'Invalid content: accounts.csv.'
        $output[1].Errors.Count | Should -Be 1
        $output[1].Errors[0] | Should -BeLike '*Error downloading content*download denied*'
    }

    It 'Desired behavior: caught failures emit only one result (ArrayList.Add currently leaks its index)' -Skip {
        $script:downloadFailure = $true
        @(Check-DedicatedAdminAccounts @script:params 2>$null).Count | Should -Be 1
    }

    It 'Throws a descriptive context selection error before creating storage context' {
        Mock Set-AzContext -ModuleName Check-DedicatedAdminAccounts { throw 'context denied' }
        { Check-DedicatedAdminAccounts @script:params } | Should -Throw '*Select-Azsubscription*context denied*'
        Should -Invoke New-ConnectedStorageContext -ModuleName Check-DedicatedAdminAccounts -Times 0 -Exactly
    }

    It 'Throws a descriptive storage connection error before listing blobs' {
        Mock New-ConnectedStorageContext -ModuleName Check-DedicatedAdminAccounts { throw 'storage denied' }
        { Check-DedicatedAdminAccounts @script:params } | Should -Throw '*evidence*rg-001*sub-001*storage denied*'
        Should -Invoke Get-AzStorageBlob -ModuleName Check-DedicatedAdminAccounts -Times 0 -Exactly
    }

    It 'Propagates uncaught blob listing failures' {
        Mock Get-AzStorageBlob -ModuleName Check-DedicatedAdminAccounts { throw 'listing denied' }
        { Check-DedicatedAdminAccounts @script:params } | Should -Throw '*listing denied*'
    }

    It 'Propagates uncaught matching blob retrieval failures' {
        Mock Get-AzStorageBlob -ModuleName Check-DedicatedAdminAccounts { throw 'blob retrieval denied' } -ParameterFilter { $Blob }
        { Check-DedicatedAdminAccounts @script:params } | Should -Throw '*blob retrieval denied*'
    }

    It 'Passes storage subscription profiles and returns in-place profile changes' {
        Mock Add-ProfileInformation -ModuleName Check-DedicatedAdminAccounts {
            param($Result)
            $Result | Add-Member NoteProperty Profile 2
            $Result.ComplianceStatus = 'Not Applicable'
            $Result
        }
        $result = Check-DedicatedAdminAccounts @script:params -EnableMultiCloudProfiles -CloudUsageProfiles '1,2' -ModuleProfiles '2'
        $result.ComplianceResults.Profile | Should -Be 2
        $result.ComplianceResults.ComplianceStatus | Should -Be 'Not Applicable'
        Should -Invoke Add-ProfileInformation -ModuleName Check-DedicatedAdminAccounts -Times 1 -Exactly -ParameterFilter {
            $SubscriptionId -eq 'sub-001' -and $CloudUsageProfiles -eq '1,2' -and $ModuleProfiles -eq '2' -and $ErrorList.Count -eq 0
        }
    }

    It 'Passes accumulated download errors to profile evaluation' {
        $script:downloadFailure = $true
        Mock Add-ProfileInformation -ModuleName Check-DedicatedAdminAccounts { param($Result) $Result }
        $output = @(Check-DedicatedAdminAccounts @script:params -EnableMultiCloudProfiles 2>$null)
        $output.Count | Should -Be 2
        $output[1].Errors.Count | Should -Be 1
        Should -Invoke Add-ProfileInformation -ModuleName Check-DedicatedAdminAccounts -Times 1 -Exactly -ParameterFilter {
            $CloudUsageProfiles -eq '3' -and $ErrorList.Count -eq 1 -and $ErrorList[0] -like '*download denied*'
        }
    }
}
