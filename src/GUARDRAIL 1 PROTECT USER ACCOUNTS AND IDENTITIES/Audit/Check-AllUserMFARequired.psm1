function Check-AllUserMFARequired {
    [CmdletBinding()]
    param (      
        [Parameter(Mandatory=$true)]
        [string] $ControlName,
        [Parameter(Mandatory=$true)]
        [string] $ItemName,
        [Parameter(Mandatory=$true)]
        [string] $itsgcode,
        [Parameter(Mandatory=$true)]
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
    
    # Performance monitoring for large tenants
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $initialMemory = [System.GC]::GetTotalMemory($false)

    # 1) Fetch users (paged automatically by Invoke-GraphQueryEX)
    $usersPath = "/users?`$select=displayName,id,userPrincipalName,mail,createdDateTime,userType,accountEnabled,signInActivity"
    Write-Verbose "Fetching users from Microsoft Graph: $usersPath"
    try {
        $response = Invoke-GraphQueryEX -urlPath $usersPath -ErrorAction Stop
        if ($response -is [System.Array]) {
            $response = $response | Where-Object { $_.Content -ne $null -or $_.StatusCode -ne $null } | Select-Object -Last 1
        }
        $allUsers = @($response.Content.value)
     # Exclude Break Glass accounts from evaluation and output (case-insensitive)
        $bgUpns = @($FirstBreakGlassUPN, $SecondBreakGlassUPN) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        if ($bgUpns.Count -gt 0) {
            $allUsers = @($allUsers | Where-Object {
                $upn = $_.userPrincipalName
                -not $upn -or ($bgUpns -notcontains $upn)
            })
        }
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

    # 4) Build augmented records (user + registration summary) - SIMPLIFIED FOR PERFORMANCE
    # Use ArrayList for better performance than array concatenation
    $augmentedUsers = [System.Collections.ArrayList]::new()
    
    $totalUsers = $allUsers.Count
    $processedCount = 0
    
    Write-Verbose "Processing $totalUsers users with simplified data collection..."
    
    foreach ($u in $allUsers) {
        $processedCount++
        
        # Progress reporting for large tenants
        if ($totalUsers -gt 1000 -and ($processedCount % 1000 -eq 0 -or $processedCount -eq $totalUsers)) {
            $percentComplete = [math]::Round(($processedCount / $totalUsers) * 100, 1)
            Write-Verbose "Progress: $processedCount/$totalUsers users processed ($percentComplete%)"
        }
        
        $r = $null
        if ($null -ne $u.id -and $regById.ContainsKey($u.id)) { 
            $r = $regById[$u.id]
        }

        $methods = @()
        if ($null -ne $r -and $null -ne $r.methodsRegistered) { 
            $methods = @($r.methodsRegistered)
        }

        # Create user object with raw data - MFA compliance logic will be handled in KQL
        $userObject = [PSCustomObject]@{
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
            
            # System preferred authentication data
            isSystemPreferredAuthenticationMethodEnabled = $r.isSystemPreferredAuthenticationMethodEnabled
            systemPreferredAuthenticationMethods = $r.systemPreferredAuthenticationMethods
            userPreferredMethodForSecondaryAuthentication = $r.userPreferredMethodForSecondaryAuthentication

            # Context
            ReportTime        = $ReportTime
            ItemName          = $ItemName
            itsgcode          = $itsgcode
        }
        
        $augmentedUsers.Add($userObject) | Out-Null
    }

    Write-Verbose "Data collection completed for $($augmentedUsers.Count) users"

    # 5) Simple compliance check - detailed analysis will be done in KQL
    $totalUsers = $augmentedUsers.Count
    
    # Determine basic compliance status
    if ($ErrorList.Count -gt 0) {
        $IsCompliant = $false
        $Comments = $msgTable.evaluationError -f ($ErrorList -join "; ")
    } 
    elseif ($totalUsers -eq 0) {
        $IsCompliant = $true
        $Comments = $msgTable.noUsersFound 
    }
    else {
        # Basic check - will be refined in KQL
        $IsCompliant = $true
        $Comments = $msgTable.dataCollectedForAnalysis -f $totalUsers
    }
    
    Write-Verbose "Basic compliance check completed. Detailed analysis will be performed in KQL queries."
    
    # Performance reporting
    $stopwatch.Stop()
    $finalMemory = [System.GC]::GetTotalMemory($false)
    $memoryUsed = ($finalMemory - $initialMemory) / 1MB
    
    Write-Verbose "Performance Summary: Data collection completed in $($stopwatch.ElapsedMilliseconds) ms, Memory used: $([math]::Round($memoryUsed, 2)) MB"

    # 6) Prepare compliance object with proper status and messaging
    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        ItemName         = $ItemName
        Comments         = $Comments
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }

    # Add profile information if MCUP feature is enabled
    if ($EnableMultiCloudProfiles) {
        $result = Add-ProfileInformation -Result $PsObject -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId -ErrorList $ErrorList
        Write-Host "$result"
        $PsObject = $result
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
