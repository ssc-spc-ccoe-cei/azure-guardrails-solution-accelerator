function lastLoginInDays{
    param($LastSignIn)
    $lastSignInDate = Get-Date $LastSignIn
    $todayDate = Get-Date
    return ($todayDate - $lastSignInDate).Days
}

function Check-AllUserMFARequired {
    param(
        [Parameter(Mandatory = $true)] [string] $ControlName,
        [Parameter(Mandatory = $true)] [string] $ItemName,
        [Parameter(Mandatory = $true)] [string] $itsgcode,
        [Parameter(Mandatory = $true)] [hashtable] $msgTable,   
        [Parameter(Mandatory = $true)] [string] $ReportTime,
        [Parameter(Mandatory = $true)] [string] $FirstBreakGlassUPN,
        [Parameter(Mandatory = $true)] [string] $SecondBreakGlassUPN,
        [string] $CloudUsageProfiles = "3",     # Profile usage flag (if needed)
        [string] $ModuleProfiles, # Not used directly in this logic
        [switch] $EnableMultiCloudProfiles # Flag to include profile tagging in output
    )
# Initialize result tracking variables
$ErrorList = New-Object System.Collections.ArrayList
$nonMfaUsers = New-Object System.Collections.ArrayList
$IsCompliant = $false
$Comments = $null

# Read previous Graph pagination link (for resuming long queries)
$nextLinkVarName = "MFAUserNextLink"
$nextLink = Get-AutomationVariable -Name $nextLinkVarName

# Helper function to store pagination progress in Automation Variable
function Save-NextLink($link) {
    Set-AutomationVariable -Name $nextLinkVarName -Value $link
}
# First Graph query URL for users
$baseUrl = "/users?$select=displayName,signInActivity,userPrincipalName,id,mail,createdDateTime,userType,accountEnabled"

do {
        # Use nextLink if available to resume from previous call

        $url = if ($nextLink) { $nextLink } else { $baseUrl }
        try {
            $response = Invoke-NewGraphQuery -urlPath $url -ErrorAction Stop
            $usersPage = $response.Content.value
            $nextLink = $response.Content.'@odata.nextLink'
            Save-NextLink $nextLink
        } catch {
            $ErrorList.Add("Graph API call failed at URL '$url': $_")
            break
        }
        # Remove disabled accounts
        $usersPage = $usersPage | Where-Object { $_.accountEnabled -ne $false }

        $jobs = @()
        foreach ($user in $usersPage) {
            # Run max 10 parallel jobs at a time
            if ($jobs.Count -ge 10) {
                $jobs | ForEach-Object { $_ | Wait-Job | Out-Null }
                $jobs | ForEach-Object { $_ | Receive-Job; Remove-Job $_ }
                $jobs = @()
            }

            $jobs += Start-Job -ScriptBlock {
                param($user, $FirstBreakGlassUPN, $SecondBreakGlassUPN)
                # Skip break-glass accounts
                $isExcluded = $user.userPrincipalName -eq $FirstBreakGlassUPN -or $user.userPrincipalName -eq $SecondBreakGlassUPN
                if (-not $isExcluded) {
                    $methods = (Invoke-GraphQuery -urlPath "/users/$($user.id)/authentication/methods").Content.value

                    # Check for at least one MFA method

                    $hasMfa = $methods | Where-Object {
                        $_.'@odata.type' -match 'microsoft.graph.microsoftAuthenticatorAuthenticationMethod|microsoft.graph.fido2AuthenticationMethod|microsoft.graph.phoneAuthenticationMethod'
                    }
                    
                    # If no MFA, return user object
                    if (-not $hasMfa) {
                        return $user
                    }
                }
            } -ArgumentList $user, $FirstBreakGlassUPN, $SecondBreakGlassUPN
        }
    
        # Collect and process completed jobs
        $jobs | ForEach-Object { $_ | Wait-Job | Out-Null }
        foreach ($job in $jobs) {
            $result = $job | Receive-Job
            if ($result) { $nonMfaUsers.Add($result) | Out-Null }
            Remove-Job $job
        }

    } while ($nextLink)
    # Generate compliance summary
     if ($nonMfaUsers.Count -eq 0) {
        $IsCompliant = $true
        $Comments = "All users require MFA"
    } else {
        $Comments = "$($nonMfaUsers.Count) users do not require MFA"
    }
    # Return final object with metadata and list of non-compliant users

    return [PSCustomObject]@{
        ControlName = $ControlName
        ItemName    = $ItemName
        ITSGCode    = $itsgcode
        TimeChecked = $ReportTime
        IsCompliant = $IsCompliant
        Comments    = $Comments
        ErrorList   = $ErrorList
        Details     = $nonMfaUsers
    }
}

function Invoke-NewGraphQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $urlPath,

        [string] $apiVersion = "v1.0",  # optional version switch
        [string] $accessToken  # optional token reuse
    )

    $uri = "https://graph.microsoft.com/$apiVersion$urlPath"

    try {
        if (-not $accessToken) {
            $accessToken = (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com").Token
        }

        $headers = @{ Authorization = "Bearer $accessToken" }

        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET -ErrorAction Stop

        return @{
            Content = $response
            StatusCode = 200
        }
    }
    catch {
        Write-Error "Invoke-NewGraphQuery failed: $($_.Exception.Message)"
        return @{
            Content = @{}
            StatusCode = 500
        }
    }
}