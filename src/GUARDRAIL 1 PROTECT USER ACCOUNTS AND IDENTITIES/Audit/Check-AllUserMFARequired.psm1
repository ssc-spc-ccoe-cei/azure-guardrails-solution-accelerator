function lastLoginInDays{
    param(
        $LastSignIn
    )

    $lastSignInDate = Get-Date $LastSignIn
    $todayDate = Get-Date
    $daysLastLogin = ($todayDate - $lastSignInDate).Days

    return $daysLastLogin
}

function Check-AllUserMFARequired {
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
    Write-Host "[DEBUG] Entered Check-AllUserMFARequired"
    Write-Host "[DEBUG] Parameters: ControlName=$ControlName, ItemName=$ItemName, itsgcode=$itsgcode, ReportTime=$ReportTime, FirstBreakGlassUPN=$FirstBreakGlassUPN, SecondBreakGlassUPN=$SecondBreakGlassUPN, CloudUsageProfiles=$CloudUsageProfiles, ModuleProfiles=$ModuleProfiles, EnableMultiCloudProfiles=$EnableMultiCloudProfiles"
    $usersSignIn = "/users?`$top=999&$select=displayName,id,userPrincipalName,mail,createdDateTime,userType,accountEnabled,signInActivity"
    Write-Host "[DEBUG] Fetching all users from Microsoft Graph: $usersSignIn"
    try {
        $response = Invoke-GraphQueryEX -urlPath $usersSignIn -ErrorAction Stop
        $allUsers = @($response.Content.value)
        Write-Host "[DEBUG] Retrieved $($allUsers.Count) users."
    }
    catch {
        Write-Warning "Failed to call Microsoft Graph REST API at URL '$usersSignIn'; error: $_"
        $allUsers = @()
    }

    # Send raw user data to Log Analytics
    if ($allUsers.Count -gt 0) {
        New-LogAnalyticsData -Data $allUsers -WorkSpaceID $ReportTime -WorkSpaceKey $FirstBreakGlassUPN -LogType "GuardrailsUserRaw" | Out-Null
        Write-Host "[DEBUG] Sent raw user data to Log Analytics."
    } else {
        Write-Warning "No user data to send to Log Analytics."
    }

    # Return a minimal result object for orchestrator compatibility
    return [PSCustomObject]@{
        RawUserCount = $allUsers.Count
        Status = if ($allUsers.Count -gt 0) { "Success" } else { "NoData" }
    }

