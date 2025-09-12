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

    # 4) Build augmented records (user + registration summary) - OPTIMIZED FOR LARGE TENANTS
    # Pre-define constants for better performance
    $VALID_SYSTEM_METHODS = @("Fido2", "HardwareOTP")
    $VALID_MFA_METHODS = @("microsoftAuthenticatorPush", "mobilePhone", "softwareOneTimePasscode", "passKeyDeviceBound")
    
    # Create HashSets for O(1) lookups - created once before the loop for better performance
    $validSystemMethodsSet = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($method in $VALID_SYSTEM_METHODS) {
        $validSystemMethodsSet.Add($method) | Out-Null
    }
    
    $validMfaMethodsSet = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($method in $VALID_MFA_METHODS) {
        $validMfaMethodsSet.Add($method) | Out-Null
    }
    
    # Use ArrayList for better performance than array concatenation
    $augmentedUsers = [System.Collections.ArrayList]::new()
    
    # Pre-allocate counters to avoid repeated counting operations
    $mfaCompliantCount = 0
    $nonCompliantCount = 0
    
    $totalUsers = $allUsers.Count
    $processedCount = 0
    
    Write-Verbose "Processing $totalUsers users with optimized algorithm..."
    
    foreach ($u in $allUsers) {
        $processedCount++
        
        # Progress reporting for large tenants
        if ($totalUsers -gt 1000 -and ($processedCount % 1000 -eq 0 -or $processedCount -eq $totalUsers)) {
            $percentComplete = [math]::Round(($processedCount / $totalUsers) * 100, 1)
            Write-Warning "Progress: $processedCount/$totalUsers users processed ($percentComplete%)"
        }
        
        # DEBUG: Start processing user
        Write-Warning "DEBUG: Processing user $($u.userPrincipalName) (ID: $($u.id))"
        
        $r = $null
        if ($null -ne $u.id -and $regById.ContainsKey($u.id)) { 
            $r = $regById[$u.id]
            Write-Warning "DEBUG: Found registration data for user $($u.userPrincipalName)"
        } else {
            Write-Warning "DEBUG: No registration data found for user $($u.userPrincipalName)"
        }

        $methods = @()
        if ($null -ne $r -and $null -ne $r.methodsRegistered) { 
            $methods = @($r.methodsRegistered)
            Write-Warning "DEBUG: User $($u.userPrincipalName) has methods: $($methods -join ', ')"
        } else {
            Write-Warning "DEBUG: User $($u.userPrincipalName) has no registered methods"
        }

        # Determine MFA compliance based on system preferred auth or registered methods
        # REQUIREMENT: At least 2 matching authentication methods for traditional MFA (not system preferred)
        $isMfaCompliant = $false
        $complianceReason = $msgTable.mfaComplianceNoMfa
        $matchingMethodsCount = 0
        $matchedMethods = @()
        
        if ($null -ne $r) {
            # Check system preferred authentication method first (most efficient check)
            # System preferred methods only need 1 method for compliance
            $isSystemPreferredEnabled = $r.isSystemPreferredAuthenticationMethodEnabled
            $systemPreferredMethods = $r.systemPreferredAuthenticationMethods
            
            Write-Warning "DEBUG: User $($u.userPrincipalName) - System preferred enabled: $isSystemPreferredEnabled"
            Write-Warning "DEBUG: User $($u.userPrincipalName) - System preferred methods: $($systemPreferredMethods -join ', ')"
            
            if ($isSystemPreferredEnabled -eq $true -and $null -ne $systemPreferredMethods -and $systemPreferredMethods.Count -gt 0) {
                Write-Warning "DEBUG: User $($u.userPrincipalName) - Checking system preferred methods against valid list: $($VALID_SYSTEM_METHODS -join ', ')"
                
                # OPTIMIZATION: Check each system preferred method against pre-created HashSet for O(1) lookups
                foreach ($method in $systemPreferredMethods) {
                    if ($validSystemMethodsSet.Contains($method)) {
                        $isMfaCompliant = $true
                        $complianceReason = $msgTable.mfaComplianceSystemPreferred -f $method
                        $matchedMethods = @($method)
                        Write-Warning "DEBUG: User $($u.userPrincipalName) - COMPLIANT via system preferred method: $method"
                        break
                    }
                }
                
                if (-not $isMfaCompliant) {
                    Write-Warning "DEBUG: User $($u.userPrincipalName) - No valid system preferred methods found"
                }
            } else {
                Write-Warning "DEBUG: User $($u.userPrincipalName) - System preferred not enabled or no methods"
            }
            
            # If not compliant via system preferred, check traditional MFA registration
            # Traditional MFA methods require at least 2 methods for compliance
            if (-not $isMfaCompliant -and $r.isMfaRegistered -eq $true -and $methods.Count -gt 0) {
                Write-Warning "DEBUG: User $($u.userPrincipalName) - Checking traditional MFA methods (requires 2+)"
                Write-Warning "DEBUG: User $($u.userPrincipalName) - MFA registered: $($r.isMfaRegistered), Methods count: $($methods.Count)"
                Write-Warning "DEBUG: User $($u.userPrincipalName) - Valid MFA methods: $($VALID_MFA_METHODS -join ', ')"
                
                # OPTIMIZATION: Check each user method against pre-created HashSet for O(1) lookups
                foreach ($method in $methods) {
                    if ($validMfaMethodsSet.Contains($method)) {
                        $matchingMethodsCount++
                        $matchedMethods += $method
                        Write-Warning "DEBUG: User $($u.userPrincipalName) - Found valid method: $method (total: $matchingMethodsCount)"
                    }
                }
                
                Write-Warning "DEBUG: User $($u.userPrincipalName) - Total matching methods: $matchingMethodsCount"
                Write-Warning "DEBUG: User $($u.userPrincipalName) - Matched methods: $($matchedMethods -join ', ')"
                
                # Check if we have at least 2 traditional MFA methods
                if ($matchingMethodsCount -ge 2) {
                    $isMfaCompliant = $true
                    $complianceReason = $msgTable.mfaComplianceMfaRegistered -f ($matchedMethods -join ', ')
                    Write-Warning "DEBUG: User $($u.userPrincipalName) - COMPLIANT via traditional MFA methods: $($matchedMethods -join ', ')"
                } elseif ($matchingMethodsCount -eq 1) {
                    $complianceReason = $msgTable.mfaComplianceOnlyOneMethod -f ($matchedMethods -join ', ')
                    Write-Warning "DEBUG: User $($u.userPrincipalName) - NON-COMPLIANT: Only 1 method found: $($matchedMethods -join ', ')"
                } else {
                    $complianceReason = $msgTable.mfaComplianceNoValidMethods
                    Write-Warning "DEBUG: User $($u.userPrincipalName) - NON-COMPLIANT: No valid methods found"
                }
            } else {
                if (-not $isMfaCompliant) {
                    Write-Warning "DEBUG: User $($u.userPrincipalName) - Skipping traditional MFA check - MFA registered: $($r.isMfaRegistered), Methods count: $($methods.Count)"
                }
            }
        } else {
            Write-Warning "DEBUG: User $($u.userPrincipalName) - No registration data available - will be marked as non-compliant"
        }
        
        # DEBUG: Final compliance status
        Write-Warning "DEBUG: User $($u.userPrincipalName) - FINAL STATUS: Compliant=$isMfaCompliant, Reason='$complianceReason'"
        Write-Warning "DEBUG: User $($u.userPrincipalName) - Methods count: $matchingMethodsCount, Matched: $($matchedMethods -join ', ')"
        
        # OPTIMIZATION: Count during processing instead of separate loops
        if ($isMfaCompliant) {
            $mfaCompliantCount++
            Write-Warning "DEBUG: User $($u.userPrincipalName) - Added to COMPLIANT count (total: $mfaCompliantCount)"
        } else {
            $nonCompliantCount++
            Write-Warning "DEBUG: User $($u.userPrincipalName) - Added to NON-COMPLIANT count (total: $nonCompliantCount)"
        }

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
            
            # MFA Compliance status
            isMfaCompliant        = $isMfaCompliant
            MfaComplianceReason   = $complianceReason
            matchingMethodsCount  = $matchingMethodsCount
            matchedMethods        = $matchedMethods

            # Context
            ReportTime        = $ReportTime
            ItemName          = $ItemName
            itsgcode          = $itsgcode
        }
        
        $augmentedUsers.Add($userObject) | Out-Null
    }

    # DEBUG: Processing summary
    Write-Warning "DEBUG: ===== PROCESSING COMPLETE ====="
    Write-Warning "DEBUG: Total users processed: $totalUsers"
    Write-Warning "DEBUG: Compliant users: $mfaCompliantCount"
    Write-Warning "DEBUG: Non-compliant users: $nonCompliantCount"
    Write-Warning "DEBUG: ================================"

    # 5) Analyze MFA compliance status based on collected data - OPTIMIZED
    Write-Verbose "Analyzing MFA compliance results for $($augmentedUsers.Count) users..."
    
    # OPTIMIZATION: Use pre-calculated counts instead of Where-Object operations
    $totalUsers = $augmentedUsers.Count
    $mfaCompliantUsers = $mfaCompliantCount
    $mfaRegisteredUsers = $mfaRegisteredCount
    $nonCompliantUsers = $nonCompliantCount

    # Determine compliance status and appropriate message
    if ($ErrorList.Count -gt 0) {
        # If there were errors during data collection, mark as not evaluated
        $IsCompliant = $false
        $Comments = $msgTable.evaluationError -f ($ErrorList -join "; ")
    } 
    elseif ($totalUsers -eq 0) {
        $IsCompliant = $true
        $Comments =  $msgTable.noUsersFound 
    }
    elseif ($nonCompliantUsers -eq 0) {
        $IsCompliant = $true
        $Comments = $msgTable.allUsersHaveMFA -f $mfaCompliantUsers, $totalUsers 
    }
    else {
        $IsCompliant = $false
        $Comments = $msgTable.usersWithoutMFA -f $nonCompliantUsers, $totalUsers 
    }
    Write-Verbose "MFA Compliance Summary: Total=$totalUsers , Compliant=$mfaCompliantUsers, Registered=$mfaRegisteredUsers, NonCompliant=$nonCompliantUsers, Status=$IsCompliant"
    
    # Performance reporting for large tenants
    $stopwatch.Stop()
    $finalMemory = [System.GC]::GetTotalMemory($false)
    $memoryUsed = ($finalMemory - $initialMemory) / 1MB
    
    Write-Warning "Performance Summary: Processing completed in $($stopwatch.ElapsedMilliseconds) ms, Memory used: $([math]::Round($memoryUsed, 2)) MB"
    
    # Memory warning for very large tenants
    if ($memoryUsed -gt 200) {
        Write-Warning "High memory usage detected: $([math]::Round($memoryUsed, 2)) MB for $totalUsers users"
    }

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
