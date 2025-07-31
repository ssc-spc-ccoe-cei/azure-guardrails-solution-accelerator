
function Invoke-GraphQueryEx {
    <#
    .SYNOPSIS
    Executes a Microsoft Graph API GET request with optional beta version, headers, and automatic pagination.

    .PARAMETER urlPath
    Relative Graph API path (e.g., /users or /users?$filter=...).

    .PARAMETER Headers
    Optional HTTP headers to include in the request (e.g., ConsistencyLevel=eventual).

    .PARAMETER UseBeta
    Switch to use the beta Graph API endpoint.

    .OUTPUTS
    A hashtable with a 'Content' key containing a list of combined results from all pages.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^(?!https://graph.microsoft.com/(v1|beta)/)')]
        [string] $urlPath,

        [Parameter()]
        [hashtable] $Headers = @{},  # Optional Graph headers

        [switch] $UseBeta  # Use /beta endpoint if specified
    )

    $fullResults = @()
    $baseUri = if ($UseBeta) { "https://graph.microsoft.com/beta" } else { "https://graph.microsoft.com/v1.0" }
    $uri = "$baseUri$urlPath"

    try {
        do {
            $response = Invoke-AzRestMethod -Uri $uri -Method GET -Headers $Headers -ErrorAction Stop
            $parsed = $response.Content | ConvertFrom-Json

            if ($parsed.value) {
                $fullResults += $parsed.value
            }

            $uri = $parsed.'@odata.nextLink'
        } while ($null -ne $uri)

        return @{ Content = @{ value = $fullResults } }
    }
    catch {
        Write-Warning "Graph API call failed: $_"
        throw $_
    }
}

function lastLoginInDays {
    param ($LastSignIn)

    $lastSignInDate = Get-Date $LastSignIn
    $todayDate = Get-Date
    return ($todayDate - $lastSignInDate).Days
}

function Check-AllUserMFARequired {
    <#
    .SYNOPSIS
    Evaluates whether MFA is enforced for all eligible users.

    .DESCRIPTION
    Retrieves users from Microsoft Graph using advanced filtering and pagination, categorizes them by type,
    checks authentication methods, and returns compliance results.

    .OUTPUTS
    PSCustomObject with MFA compliance data.
    #>

    param (
       <# [Parameter(Mandatory = $true)][string] $ControlName,
        [Parameter(Mandatory = $true)][string] $ItemName,
        [Parameter(Mandatory = $true)][string] $itsgcode,
        [Parameter(Mandatory = $true)][hashtable] $msgTable,
        [Parameter(Mandatory = $true)][string] $ReportTime, #>
        [Parameter(Mandatory = $true)][string] $FirstBreakGlassUPN,
        [Parameter(Mandatory = $true)][string] $SecondBreakGlassUPN#,
      <#  [string] $CloudUsageProfiles = "3",
        [string] $ModuleProfiles,
        [switch] $EnableMultiCloudProfiles #>
    )

    $ErrorList = [System.Collections.ArrayList]::new()
    $IsCompliant = $false
    $Comments = $null
    $UserComments = $null
    $userValidMFACounter = 0

    # Optimized Microsoft Graph query with filtering and count
    $usersSignIn = "/users?\$count=true&`$filter=accountEnabled eq true&`$select=displayName,signInActivity,userPrincipalName,id,mail,createdDateTime,userType,accountEnabled&`$orderby=userPrincipalName"
    $headers = @{ ConsistencyLevel = "eventual" }

    try {
        $response = Invoke-GraphQueryEx -urlPath $usersSignIn -Headers $headers
        $allUsers = $response.Content.value
    } catch {
        $ErrorList.Add("Failed to call Microsoft Graph API at URL '$usersSignIn'; returned error: $_")
        Write-Warning "Graph call failed: $_"
        $Comments = $msgTable.MSEntIDLicenseTypeNotFound
        return
    }

    # Separate guests and members
    $extUsers = $allUsers | Where-Object { $_.userType -eq 'Guest' }
    $memberUsers = $allUsers | Where-Object {
        $_.userType -ne 'Guest' -and
        $_.userPrincipalName -ne $FirstBreakGlassUPN -and
        $_.userPrincipalName -ne $SecondBreakGlassUPN
    }

    Write-Verbose "Total users fetched: $($allUsers.Count)"
    Write-Verbose "Guest users: $($extUsers.Count), Member users: $($memberUsers.Count)"

    # MFA evaluation
    if ($memberUsers.Count -gt 0) {
        $result = Get-AllUserAuthInformation -allUserList $memberUsers
        $memberUserUPNsBadMFA = $result.userUPNsBadMFA
        if ($result.ErrorList) { $ErrorList.Add($result.ErrorList) }
        $userValidMFACounter += $result.userValidMFACounter
    }

    if ($extUsers.Count -gt 0) {
        $result2 = Get-AllUserAuthInformation -allUserList $extUsers
        $extUserUPNsBadMFA = $result2.userUPNsBadMFA
        if ($result2.ErrorList) { $ErrorList.Add($result2.ErrorList) }
        $userValidMFACounter += $result2.userValidMFACounter
    }

    # Merge bad MFA lists
    $userUPNsBadMFA = @()
    if ($memberUserUPNsBadMFA) { $userUPNsBadMFA += $memberUserUPNsBadMFA }
    if ($extUserUPNsBadMFA)    { $userUPNsBadMFA += $extUserUPNsBadMFA }

    Write-Verbose "Users without compliant MFA: $($userUPNsBadMFA.Count)"

    # Match full user objects
    $matchingBadUsers = $allUsers | Where-Object {
        $userUPNsBadMFA.UPN -contains $_.userPrincipalName
    }

    # Compliance evaluation
    if (-not $allUsers -or $userUPNsBadMFA.Count -gt 0) {
        $IsCompliant = $false
        $Comments = $msgTable.MFAEnforcementPartialOrMissing
    } else {
        $IsCompliant = $true
        $Comments = $msgTable.MFAEnabled
    }

    return [PSCustomObject]@{
        ControlName             = $ControlName
        ItemName                = $ItemName
        ItsGCode                = $itsgcode
        Comments                = $Comments
        ReportTime              = $ReportTime
        IsCompliant             = $IsCompliant
        UserComments            = $UserComments
        nonMfaUsers             = $matchingBadUsers
        GR1NonMfaUsers          = $matchingBadUsers
        EnableMultiCloudProfiles= $EnableMultiCloudProfiles.IsPresent
        ErrorList               = $ErrorList
    }
}
