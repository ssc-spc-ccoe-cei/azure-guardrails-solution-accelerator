BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'
    $script:savedFunctions = @{}
    foreach ($name in @('Invoke-GraphQueryEX', 'Get-AllUserAuthInformation', 'Add-ProfileInformation', 'get-MFACount', 'Check-GAUserCountMFARequired')) {
        $script:savedFunctions[$name] = if (Test-Path "Function:\$name") { (Get-Item "Function:\$name").ScriptBlock } else { $null }
    }
    function global:Invoke-GraphQueryEX { [CmdletBinding()] param($urlPath) throw 'Unmocked Graph call' }
    function global:Get-AllUserAuthInformation { [CmdletBinding()] param($allUserList) throw 'Unmocked authentication call' }
    function global:Add-ProfileInformation { param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList) throw 'Unmocked profile call' }
    $script:testedModule = Import-Module (Join-Path $PSScriptRoot '../../../src/GUARDRAIL 1 PROTECT USER ACCOUNTS AND IDENTITIES/Audit/Check-GAUserCountMFARequired.psm1') -Force -PassThru
}
AfterAll {
    Remove-Module $script:testedModule -Force -ErrorAction SilentlyContinue
    foreach ($name in $script:savedFunctions.Keys) {
        Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
        if ($null -ne $script:savedFunctions[$name]) { Set-Item "Function:\global:$name" $script:savedFunctions[$name] }
    }
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Check-GAUserCountMFARequired' {
    BeforeAll {
        $script:params = @{
            ControlName = 'GUARDRAIL 1'; ItemName = 'Global administrators MFA'; itsgcode = 'IA-2'; ReportTime = '2026-10-01'
            FirstBreakGlassUPN = 'breakglass1@tenant.example'; SecondBreakGlassUPN = 'breakglass2@tenant.example'
            msgTable = @{
                isCompliant = 'Compliant.'; isNotCompliant = 'Noncompliant.'
                globalAdminAccntsMinimum = 'Minimum administrator assumption.'
                globalAdminAccntsSurplus = 'Too many administrators.'
                allGAUserHaveMFA = 'All administrators have MFA.'
                gaUserMisconfiguredMFA = 'MFA missing: {0}'
            }
        }
        function New-GaUser {
            param($UPN = 'admin1@tenant.example')
            [pscustomobject]@{ '@odata.type' = '#microsoft.graph.user'; id = $UPN; displayName = $UPN; userPrincipalName = $UPN; mail = $UPN }
        }
    }
    BeforeEach {
        $script:members = @(New-GaUser)
        $script:groupMembers = @()
        Mock Invoke-GraphQueryEX -ModuleName Check-GAUserCountMFARequired {
            param($urlPath)
            switch ($urlPath) {
                '/directoryRoles' { [pscustomobject]@{ Content = [pscustomobject]@{ value = @(
                    [pscustomobject]@{ id = 'reader-role'; displayName = 'Global Reader' },
                    [pscustomobject]@{ id = 'ga-role'; displayName = 'Global Administrator' }
                ) } } }
                '/directoryRoles/ga-role/members' { [pscustomobject]@{ Content = [pscustomobject]@{ value = $script:members } } }
                '/groups/group-001/members' { [pscustomobject]@{ Content = [pscustomobject]@{ value = $script:groupMembers } } }
                default { throw "Unexpected Graph URL: $urlPath" }
            }
        }
        Mock Get-AllUserAuthInformation -ModuleName Check-GAUserCountMFARequired {
            param($allUserList)
            [pscustomobject]@{
                userValidMFACounter = @($allUserList).Count; userUPNsBadMFA = @()
                userUPNsValidMFA = @($allUserList | ForEach-Object { [pscustomobject]@{ UPN = $_.userPrincipalName; MFAStatus = $true } })
                ErrorList = [System.Collections.ArrayList]::new()
            }
        }
        Mock Add-ProfileInformation -ModuleName Check-GAUserCountMFARequired { throw 'Unexpected profile call' }
    }

    It 'Evaluates the lower and upper count boundaries: <Count> administrators, compliant <Expected>' -ForEach @(
        @{ Count = 0; Expected = $true }, @{ Count = 1; Expected = $true },
        @{ Count = 2; Expected = $true }, @{ Count = 5; Expected = $true }, @{ Count = 6; Expected = $false }
    ) {
        $script:members = @(for ($i = 0; $i -lt $Count; $i++) { New-GaUser "admin$i@tenant.example" })
        $result = Check-GAUserCountMFARequired @script:params
        @($result).Count | Should -Be 1
        $result.ComplianceResults.ComplianceStatus | Should -Be $Expected
        foreach ($name in @('ControlName', 'ItemName', 'itsgcode', 'ReportTime')) { $result.ComplianceResults.$name | Should -Be $script:params[$name] }
        $result.Errors.Count | Should -Be 0
        $result.AdditionalResults | Should -BeNullOrEmpty
        if ($Count -le 1) { $result.ComplianceResults.Comments | Should -Be 'Compliant. Minimum administrator assumption.' }
        elseif ($Count -gt 5) { $result.ComplianceResults.Comments | Should -Be 'Noncompliant. Too many administrators.' }
        else { $result.ComplianceResults.Comments | Should -Be ' All administrators have MFA.' }
        Should -Invoke Get-AllUserAuthInformation -ModuleName Check-GAUserCountMFARequired -Exactly -Times $(if ($Count -eq 0 -or $Count -gt 5) { 0 } else { 1 })
        Should -Invoke Invoke-GraphQueryEX -ModuleName Check-GAUserCountMFARequired -Exactly -Times 1 -ParameterFilter { $urlPath -eq '/directoryRoles' }
        Should -Invoke Invoke-GraphQueryEX -ModuleName Check-GAUserCountMFARequired -Exactly -Times 1 -ParameterFilter { $urlPath -eq '/directoryRoles/ga-role/members' }
        Should -Invoke Add-ProfileInformation -ModuleName Check-GAUserCountMFARequired -Times 0
    }

    It 'Marks <Count> administrators noncompliant and formats the exact misconfigured UPN list' -ForEach @(@{ Count = 1 }, @{ Count = 2 }, @{ Count = 5 }) {
        $script:members = @(for ($i = 0; $i -lt $Count; $i++) { New-GaUser "admin$i@tenant.example" })
        Mock Get-AllUserAuthInformation -ModuleName Check-GAUserCountMFARequired {
            param($allUserList)
            [pscustomobject]@{
                userValidMFACounter = 0
                userUPNsBadMFA = @($allUserList | ForEach-Object { [pscustomobject]@{ UPN = $_.userPrincipalName; MFAStatus = $false } })
                userUPNsValidMFA = @(); ErrorList = @()
            }
        }
        $result = Check-GAUserCountMFARequired @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $expected = 'MFA missing: ' + (($script:members.userPrincipalName | Sort-Object) -join ', ')
        if ($Count -eq 1) { $expected = 'Noncompliant. Minimum administrator assumption. ' + $expected }
        else { $expected = ' ' + $expected }
        $result.ComplianceResults.Comments | Should -Be $expected
    }

    It 'Expands groups, filters nonusers, deduplicates UPNs and excludes both breakglass accounts regardless of assignment type or casing' {
        $script:members = @(
            (New-GaUser 'admin1@tenant.example'), (New-GaUser 'BREAKGLASS1@tenant.example'),
            [pscustomobject]@{ '@odata.type' = '#microsoft.graph.group'; id = 'group-001'; displayName = 'GA group' },
            [pscustomobject]@{ '@odata.type' = '#microsoft.graph.servicePrincipal'; id = 'sp-001' }
        )
        $script:groupMembers = @(
            (New-GaUser 'admin1@tenant.example'), (New-GaUser 'admin2@tenant.example'),
            (New-GaUser 'breakglass2@tenant.example'),
            [pscustomobject]@{ '@odata.type' = '#microsoft.graph.group'; id = 'nested-group' },
            [pscustomobject]@{ '@odata.type' = '#microsoft.graph.servicePrincipal'; id = 'sp-002' }
        )
        $result = Check-GAUserCountMFARequired @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        Should -Invoke Get-AllUserAuthInformation -ModuleName Check-GAUserCountMFARequired -Exactly -Times 1 -ParameterFilter {
            @($allUserList).Count -eq 2 -and
            $allUserList.userPrincipalName -contains 'admin1@tenant.example' -and
            $allUserList.userPrincipalName -contains 'admin2@tenant.example'
        }
        Should -Invoke Invoke-GraphQueryEX -ModuleName Check-GAUserCountMFARequired -Exactly -Times 1 -ParameterFilter { $urlPath -eq '/groups/group-001/members' }
        Should -Invoke Invoke-GraphQueryEX -ModuleName Check-GAUserCountMFARequired -Exactly -Times 3
    }

    It 'Treats only the two breakglass accounts as an empty administrator population' {
        $script:members = @((New-GaUser $script:params.FirstBreakGlassUPN), (New-GaUser $script:params.SecondBreakGlassUPN))
        $result = Check-GAUserCountMFARequired @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        Should -Invoke Get-AllUserAuthInformation -ModuleName Check-GAUserCountMFARequired -Times 0
    }

    It 'Combines member and external administrator MFA results' {
        $script:members = @((New-GaUser), (New-GaUser 'guest_partner.example#EXT#@tenant.example'))
        $result = Check-GAUserCountMFARequired @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        Should -Invoke Get-AllUserAuthInformation -ModuleName Check-GAUserCountMFARequired -Exactly -Times 2
    }

    It 'Propagates a thrown authentication helper exception' {
        Mock Get-AllUserAuthInformation -ModuleName Check-GAUserCountMFARequired { throw 'Auth unavailable' }
        { Check-GAUserCountMFARequired @script:params } | Should -Throw '*Auth unavailable*'
    }

    It 'Remains noncompliant when the MFA count mismatches but the helper supplies no bad UPNs' {
        $script:members = @((New-GaUser), (New-GaUser 'admin2@tenant.example'))
        Mock Get-AllUserAuthInformation -ModuleName Check-GAUserCountMFARequired { [pscustomobject]@{ userValidMFACounter = 0; userUPNsBadMFA = @(); ErrorList = @() } }
        $result = Check-GAUserCountMFARequired @script:params 2>$null
        $result.ComplianceResults.ComplianceStatus | Should -BeFalse
        $result.ComplianceResults.Comments | Should -BeNullOrEmpty
        $result.Errors.Count | Should -Be 0
    }

    It 'Currently assumes compliance after failed <Endpoint> lookup and leaks an error index' -ForEach @(
        @{ Endpoint = 'roles' }, @{ Endpoint = 'members' }, @{ Endpoint = 'group' }
    ) {
        switch ($Endpoint) {
            'roles' {
                Mock Invoke-GraphQueryEX -ModuleName Check-GAUserCountMFARequired { throw 'Role lookup failure' } -ParameterFilter { $urlPath -eq '/directoryRoles' }
                Mock Invoke-GraphQueryEX -ModuleName Check-GAUserCountMFARequired { [pscustomobject]@{ Content = [pscustomobject]@{ value = @() } } } -ParameterFilter { $urlPath -eq '/directoryRoles//members' }
            }
            'members' { Mock Invoke-GraphQueryEX -ModuleName Check-GAUserCountMFARequired { throw 'Member lookup failure' } -ParameterFilter { $urlPath -eq '/directoryRoles/ga-role/members' } }
            'group' {
                $script:members = @([pscustomobject]@{ '@odata.type' = '#microsoft.graph.group'; id = 'group-001'; displayName = 'GA group' })
                Mock Invoke-GraphQueryEX -ModuleName Check-GAUserCountMFARequired { throw 'Group lookup failure' } -ParameterFilter { $urlPath -eq '/groups/group-001/members' }
            }
        }
        $output = @(Check-GAUserCountMFARequired @script:params 2>$null)
        $output.Count | Should -Be 2
        $output[0] | Should -Be 0
        $result = $output[-1]
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.Errors.Count | Should -Be 1
        $result.Errors[0] | Should -Match 'Failed to call Microsoft Graph REST API.*lookup failure'
    }

    It 'Currently treats a returned Graph error envelope as compliant without recording the error' {
        Mock Invoke-GraphQueryEX -ModuleName Check-GAUserCountMFARequired { [pscustomobject]@{ Content = $null; StatusCode = 503; Error = 'Unavailable' } }
        $result = Check-GAUserCountMFARequired @script:params
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.Errors.Count | Should -Be 0
    }

    It 'Returns profile mutations and forwards exact arguments with the default cloud profile' {
        Mock Add-ProfileInformation -ModuleName Check-GAUserCountMFARequired {
            param($Result, $ErrorList)
            $Result | Add-Member Profile 2
            $Result.ComplianceStatus = 'Not Applicable'
            [void]$ErrorList.Add('Profile diagnostic')
            $Result
        }
        $result = Check-GAUserCountMFARequired @script:params -EnableMultiCloudProfiles -ModuleProfiles '1,2'
        $result.ComplianceResults.Profile | Should -Be 2
        $result.ComplianceResults.ComplianceStatus | Should -Be 'Not Applicable'
        $result.Errors | Should -Contain 'Profile diagnostic'
        Should -Invoke Add-ProfileInformation -ModuleName Check-GAUserCountMFARequired -Exactly -Times 1 -ParameterFilter {
            $CloudUsageProfiles -eq '3' -and $ModuleProfiles -eq '1,2' -and [string]::IsNullOrEmpty($SubscriptionId) -and $ErrorList -is [System.Collections.ArrayList]
        }
    }

    It 'Currently ignores replacement profile objects' {
        Mock Add-ProfileInformation -ModuleName Check-GAUserCountMFARequired { [pscustomobject]@{ ComplianceStatus = 'Not Applicable'; Profile = 2 } }
        $result = Check-GAUserCountMFARequired @script:params -EnableMultiCloudProfiles
        $result.ComplianceResults.ComplianceStatus | Should -BeTrue
        $result.ComplianceResults.PSObject.Properties.Name | Should -Not -Contain 'Profile'
    }

    It 'Propagates profile helper exceptions' {
        Mock Add-ProfileInformation -ModuleName Check-GAUserCountMFARequired { throw 'Profile failure' }
        { Check-GAUserCountMFARequired @script:params -EnableMultiCloudProfiles } | Should -Throw '*Profile failure*'
    }
}

Describe 'get-MFACount' {
    BeforeEach {
        Mock Get-AllUserAuthInformation -ModuleName Check-GAUserCountMFARequired { throw 'Unexpected auth call' }
    }

    It 'Does not invoke the authentication helper for an empty administrator list' {
        $result = get-MFACount -globalAdminUserAccounts @()
        $result.userValidMFACounter | Should -BeNullOrEmpty
        $result.userUPNsBadMFA | Should -BeNullOrEmpty
        $result.ErrorList.Count | Should -Be 0
        Should -Invoke Get-AllUserAuthInformation -ModuleName Check-GAUserCountMFARequired -Times 0
    }

    It 'Separates member and guest UPNs, preserves mail and combines their counts and bad-MFA lists: <Population>' -ForEach @(
        @{ Population = 'members only' }, @{ Population = 'guests only' }, @{ Population = 'mixed' }
    ) {
        $member = [pscustomobject]@{ userPrincipalName = 'member@tenant.example'; mail = 'member@tenant.example' }
        $guest = [pscustomobject]@{ userPrincipalName = 'guest_partner.example#EXT#@tenant.example'; mail = 'guest@partner.example' }
        $validMember = [pscustomobject]@{ userPrincipalName = 'valid-member@tenant.example'; mail = 'valid-member@tenant.example' }
        $validGuest = [pscustomobject]@{ userPrincipalName = 'valid-guest_partner.example#EXT#@tenant.example'; mail = 'valid-guest@partner.example' }
        $accounts = switch ($Population) {
            'members only' { @($member, $validMember) }
            'guests only' { @($guest, $validGuest) }
            'mixed' { @($member, $validMember, $guest, $validGuest) }
        }
        Mock Get-AllUserAuthInformation -ModuleName Check-GAUserCountMFARequired {
            param($allUserList)
            [pscustomobject]@{
                userValidMFACounter = 1
                userUPNsBadMFA = @([pscustomobject]@{ UPN = $allUserList[0].userPrincipalName; MFAStatus = $false })
                userUPNsValidMFA = @([pscustomobject]@{ UPN = $allUserList[1].userPrincipalName; MFAStatus = $true })
                ErrorList = @()
            }
        }
        $result = get-MFACount -globalAdminUserAccounts $accounts
        $result.userValidMFACounter | Should -Be (@($accounts).Count / 2)
        @($result.userUPNsBadMFA).Count | Should -Be (@($accounts).Count / 2)
        foreach ($account in ($accounts | Where-Object { $_.userPrincipalName -notlike 'valid-*' })) {
            $result.userUPNsBadMFA.UPN | Should -Contain $account.userPrincipalName
        }
        Should -Invoke Get-AllUserAuthInformation -ModuleName Check-GAUserCountMFARequired -Exactly -Times (@($accounts).Count / 2) -ParameterFilter {
            @($allUserList).Count -eq 2 -and $allUserList[0].mail -match '@' -and
            @($allUserList[0].PSObject.Properties.Name).Count -eq 2
        }
    }

    It 'Combines mixed populations when only <BadPopulation> returns bad MFA users' -ForEach @(@{ BadPopulation = 'members' }, @{ BadPopulation = 'guests' }, @{ BadPopulation = 'neither' }) {
        $script:badPopulation = $BadPopulation
        $accounts = @(
            [pscustomobject]@{ userPrincipalName = 'member@tenant.example'; mail = 'member@tenant.example' },
            [pscustomobject]@{ userPrincipalName = 'guest_partner.example#EXT#@tenant.example'; mail = 'guest@partner.example' }
        )
        Mock Get-AllUserAuthInformation -ModuleName Check-GAUserCountMFARequired {
            param($allUserList)
            $isGuest = $allUserList[0].userPrincipalName -like '*#EXT#*'
            $isBad = ($script:badPopulation -eq 'guests' -and $isGuest) -or ($script:badPopulation -eq 'members' -and -not $isGuest)
            $badUsers = @()
            if ($isBad) { $badUsers = @([pscustomobject]@{ UPN = $allUserList[0].userPrincipalName; MFAStatus = $false }) }
            [pscustomobject]@{
                userValidMFACounter = $(if ($isBad) { 0 } else { 1 })
                userUPNsBadMFA = $badUsers
                userUPNsValidMFA = @(); ErrorList = @()
            }
        }
        $result = get-MFACount -globalAdminUserAccounts $accounts
        $result.userValidMFACounter | Should -Be $(if ($BadPopulation -eq 'neither') { 2 } else { 1 })
        if ($BadPopulation -eq 'neither') { $result.userUPNsBadMFA | Should -BeNullOrEmpty }
        else { @($result.userUPNsBadMFA).Count | Should -Be 1 }
        if ($BadPopulation -eq 'guests') { $result.userUPNsBadMFA.UPN | Should -Be $accounts[1].userPrincipalName }
        if ($BadPopulation -eq 'members') { $result.userUPNsBadMFA.UPN | Should -Be $accounts[0].userPrincipalName }
    }

    It 'Retains authentication diagnostics (current behavior nests the list and leaks Add index)' {
        Mock Get-AllUserAuthInformation -ModuleName Check-GAUserCountMFARequired {
            [pscustomobject]@{ userValidMFACounter = 0; userUPNsBadMFA = @(); ErrorList = @('Auth diagnostic one', 'Auth diagnostic two') }
        }
        $output = @(get-MFACount -globalAdminUserAccounts @([pscustomobject]@{ userPrincipalName = 'member@tenant.example'; mail = 'member@tenant.example' }))
        $output.Count | Should -Be 2
        $output[0] | Should -Be 0
        $output[-1].ErrorList.Count | Should -Be 1
        $output[-1].ErrorList[0].Count | Should -Be 2
        $output[-1].ErrorList[0] | Should -Contain 'Auth diagnostic one'
    }
}
