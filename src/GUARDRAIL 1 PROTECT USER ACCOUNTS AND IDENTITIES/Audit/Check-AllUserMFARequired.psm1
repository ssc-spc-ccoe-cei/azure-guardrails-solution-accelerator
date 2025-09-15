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
        [switch] $EnableMultiCloudProfiles, # default to false
        [Parameter(Mandatory=$true)]
        [string] $WorkSpaceID,  # Log Analytics Workspace ID
        [Parameter(Mandatory=$true)]
        [string] $WorkspaceKey,  # Log Analytics Workspace Key
        [Parameter(Mandatory=$true)]
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
    
    # Compliance logic moved to KQL function for better performance with large datasets
    Write-Verbose "Raw data collection completed. Compliance analysis will be performed in KQL queries."
    
    # Send raw data to GuardrailsUserRaw_CL table
    try {
        Write-Verbose "Sending $($augmentedUsers.Count) user records to GuardrailsUserRaw_CL table"
        New-LogAnalyticsData -Data $augmentedUsers -WorkSpaceID $WorkSpaceID -WorkSpaceKey $WorkspaceKey -LogType "GuardrailsUserRaw" | Out-Null
        Write-Verbose "Successfully sent raw data to Log Analytics"
    } catch {
        Write-Error "Failed to send raw data to Log Analytics: $_"
        $ErrorList.Add("Failed to send raw data to GuardrailsUserRaw_CL: $_")
    }
    
    # Call KQL function to get compliance results with retry logic
    $complianceResult = $null
    $maxRetries = 3
    $retryDelay = 30 # seconds
    $success = $false
    
    try {
        $kqlQuery = "gr_mfa_evaluation('$ReportTime')"
        
        Write-Verbose "Calling KQL function with retry logic (max $maxRetries attempts, $retryDelay second delay)"
        
        for ($i = 1; $i -le $maxRetries; $i++) {
            Write-Verbose "Attempt $i of $maxRetries - waiting $retryDelay seconds for data ingestion..."
            Start-Sleep -Seconds $retryDelay
            
            try {
                $queryResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkSpaceID -Query $kqlQuery -ErrorAction Stop
                
                if ($queryResults.Results -and $queryResults.Results.Count -gt 0) {
                    $complianceResult = $queryResults.Results[0]
                    $success = $true
                    Write-Verbose "Successfully retrieved compliance result from KQL function on attempt $i"
                    break
                } else {
                    Write-Warning "Attempt $i - KQL function returned no results, retrying..."
                }
            } catch {
                Write-Warning "Attempt $i failed: $_"
                if ($i -eq $maxRetries) {
                    throw "All $maxRetries attempts failed. Last error: $_"
                }
            }
        }
        
        if (-not $success) {
            Write-Error "Failed to get compliance results after $maxRetries attempts"
            $ErrorList.Add("Failed to call gr_mfa_evaluation KQL function after $maxRetries attempts")
        }
    } catch {
        Write-Error "Failed to call KQL function: $_"
        $ErrorList.Add("Failed to call gr_mfa_evaluation KQL function: $_")
    }
    
    # Add Profile information to compliance result if KQL function was successful
    if ($complianceResult -and $EnableMultiCloudProfiles) {
        try {
            Write-Verbose "Adding Profile information to compliance result"
            $result = Add-ProfileInformation -Result $complianceResult -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId -ErrorList $ErrorList
            $complianceResult = $result
            Write-Verbose "Profile information added successfully"
        } catch {
            Write-Warning "Failed to add Profile information: $_"
            $ErrorList.Add("Failed to add Profile information: $_")
        }
    }
    
    # Performance reporting
    $stopwatch.Stop()
    $finalMemory = [System.GC]::GetTotalMemory($false)
    $memoryUsed = ($finalMemory - $initialMemory) / 1MB
    
    Write-Verbose "Performance Summary: Data collection completed in $($stopwatch.ElapsedMilliseconds) ms, Memory used: $([math]::Round($memoryUsed, 2)) MB"

    # 6) Return compliance results from KQL function
    # Raw data already sent to GuardrailsUserRaw_CL table
    # Compliance logic handled by KQL function for better performance
    
    # 7) Return in the expected envelope; main.ps1 will send ComplianceResults to Log Analytics
    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = $complianceResult
        Errors            = $ErrorList
    }
    return $moduleOutput
}
