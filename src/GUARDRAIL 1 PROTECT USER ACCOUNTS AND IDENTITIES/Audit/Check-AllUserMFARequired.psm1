function Check-AllUserMFARequired {
    [CmdletBinding()]
    param (      
        [Parameter(Mandatory=$true)]
        [string] $ControlName,
        [Parameter(Mandatory=$true)]
        [string] $ItemName,
        [Parameter(Mandatory=$true)]
        [string] $itsgcode,
        [Parameter(Mandatory=$false)]
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string] $ReportTime, 
        [Parameter(Mandatory=$true)] 
        [string] $FirstBreakGlassUPN,
        [Parameter(Mandatory=$true)] 
        [string] $SecondBreakGlassUPN,
        [string] $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] $EnableMultiCloudProfiles # default to false
    )

    Write-Verbose "Entered Check-AllUserMFARequired for ItemName='$ItemName' itsgcode='$itsgcode'"

    # Initialize error list for orchestrator compatibility
    $ErrorList = @()

    # 1) Fetch users (paged automatically by Invoke-GraphQueryEX)
    $usersPath = "/users?`$select=displayName,id,userPrincipalName,mail,createdDateTime,userType,accountEnabled,signInActivity"
    Write-Verbose "Fetching users from Microsoft Graph: $usersPath"
    try {
        $response = Invoke-GraphQueryEX -urlPath $usersPath -ErrorAction Stop
        if ($response -is [System.Array]) {
            $response = $response | Where-Object { $_.Content -ne $null -or $_.StatusCode -ne $null } | Select-Object -Last 1
        }
        $allUsers = @($response.Content.value)
        Write-Verbose "Retrieved $($allUsers.Count) users"
    }
    catch {
        Write-Warning "Failed to call Microsoft Graph REST API at URL '$usersPath'; error: $_"
        $ErrorList += "Graph call failed for users list: $_"
        $allUsers = @()
    }

    # 2) Fetch tenant-wide registration details in one pass (no per-user calls)
    #    Endpoint: GET /reports/authenticationMethods/userRegistrationDetails (paged)
    $regPath = "/reports/authenticationMethods/userRegistrationDetails"
    Write-Verbose "Fetching authentication registration details: $regPath"
    $registrationDetails = @()
    try {
        $regResp = Invoke-GraphQueryEX -urlPath $regPath -ErrorAction Stop
        if ($regResp -is [System.Array]) {
            $regResp = $regResp | Where-Object { $_.Content -ne $null -or $_.StatusCode -ne $null } | Select-Object -Last 1
        }
        $registrationDetails = @($regResp.Content.value)
        Write-Verbose "Retrieved $($registrationDetails.Count) registration detail records"
    }
    catch {
        Write-Warning "Failed to call Microsoft Graph REST API at URL '$regPath'; error: $_"
        $ErrorList += "Graph call failed for registration details: $_"
        $registrationDetails = @()
    }

    # 3) Index registration details by user id for fast join
    $regById = @{}
    foreach ($r in $registrationDetails) {
        if ($null -ne $r.id -and -not $regById.ContainsKey($r.id)) { $regById[$r.id] = $r }
    }

    # 4) Build augmented records (user + registration summary)
    $augmentedUsers = @()
    foreach ($u in $allUsers) {
        $r = $null
        if ($null -ne $u.id -and $regById.ContainsKey($u.id)) { $r = $regById[$u.id] }

        $methods = @()
        if ($null -ne $r -and $null -ne $r.methodsRegistered) { $methods = @($r.methodsRegistered) }

        $augmentedUsers += [PSCustomObject]@{
            # User properties
            id                = $u.id
            userPrincipalName = $u.userPrincipalName
            displayName       = $u.displayName
            mail              = $u.mail
            createdDateTime   = $u.createdDateTime
            userType          = $u.userType
            accountEnabled    = $u.accountEnabled
            signInActivity    = $u.signInActivity
            
            # Registration summary (no PII like phone numbers)
            isMfaRegistered       = $r.isMfaRegistered
            isMfaCapable          = $r.isMfaCapable
            isSsprEnabled         = $r.isSsprEnabled
            isSsprRegistered      = $r.isSsprRegistered
            isSsprCapable         = $r.isSsprCapable
            isPasswordlessCapable = $r.isPasswordlessCapable
            defaultMethod         = $r.defaultMethod
            methodsRegistered     = $methods

            # Context
            ReportTime        = $ReportTime
            ItemName          = $ItemName
            itsgcode          = $itsgcode
        }
    }

    # 5) Analyze MFA compliance status based on collected data
    $totalUsers = $augmentedUsers.Count
    $mfaCapableUsers = ($augmentedUsers | Where-Object { $_.isMfaCapable -eq $true }).Count
    $mfaRegisteredUsers = ($augmentedUsers | Where-Object { $_.isMfaRegistered -eq $true }).Count
    $nonCompliantUsers = $mfaCapableUsers - $mfaRegisteredUsers

    # Determine compliance status and appropriate message
    if ($ErrorList.Count -gt 0) {
        # If there were errors during data collection, mark as not evaluated
        $IsCompliant = "Not Evaluated"
        $Comments = if ($msgTable) { 
            $msgTable.evaluationError -f ($ErrorList -join "; ")
        } else { 
            "Evaluation failed due to errors: $($ErrorList -join '; ')" 
        }
    }
    elseif ($totalUsers -eq 0) {
        $IsCompliant = $true
        $Comments = if ($msgTable) { $msgTable.noUsersFound } else { "No users found in tenant" }
    }
    elseif ($mfaCapableUsers -eq 0) {
        $IsCompliant = "Not Applicable"
        $Comments = if ($msgTable) { $msgTable.noMfaCapableUsers } else { "No MFA capable users found" }
    }
    elseif ($nonCompliantUsers -eq 0) {
        $IsCompliant = $true
        $Comments = if ($msgTable) { 
            $msgTable.allUsersHaveMFA -f $mfaRegisteredUsers, $mfaCapableUsers 
        } else { 
            "All MFA capable users have MFA enabled ($mfaRegisteredUsers/$mfaCapableUsers)" 
        }
    }
    else {
        $IsCompliant = $false
        $Comments = if ($msgTable) { 
            $msgTable.usersWithoutMFA -f $nonCompliantUsers, $mfaCapableUsers 
        } else { 
            "$nonCompliantUsers out of $mfaCapableUsers MFA capable users do not have MFA enabled" 
        }
    }

    Write-Verbose "MFA Compliance Summary: Total=$totalUsers, Capable=$mfaCapableUsers, Registered=$mfaRegisteredUsers, NonCompliant=$nonCompliantUsers, Status=$IsCompliant"

    # 6) Prepare compliance object with proper status and messaging
    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        ItemName         = $ItemName
        Comments         = $Comments
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }

    # 7) Add profile-based evaluation (consistent with other modules)
    if ($EnableMultiCloudProfiles) {
        $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        if (!$evalResult.ShouldEvaluate) {
            if ($evalResult.Profile -gt 0) {
                $PsObject.ComplianceStatus = "Not Applicable"
                $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                $PsObject.Comments = if ($msgTable) {
                    $msgTable.profileNotApplicable -f $evalResult.Profile, $CloudUsageProfiles
                } else {
                    "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
                }
            } else {
                $ErrorList += "Error occurred while evaluating profile configuration"
            }
        } else {
            $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
        }
    }

    # 8) Return in the expected envelope; main.ps1 will send AdditionalResults to Log Analytics
    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = $PsObject  # Single object, not array (consistent with other modules)
        Errors            = $ErrorList
        AdditionalResults = [PSCustomObject]@{
            records = @($augmentedUsers)
            logType = "GuardrailsUserRaw"
        }
    }
    return $moduleOutput
}

