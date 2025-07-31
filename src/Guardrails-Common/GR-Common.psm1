
function Invoke-GraphQueryEx {
    <#
    .SYNOPSIS
    Executes Microsoft Graph API GET queries with optional token injection and auto-pagination.

    .DESCRIPTION
    Local testing version using Invoke-RestMethod and AccessToken. Handles optional headers and Graph pagination.

    .PARAMETER urlPath
    Microsoft Graph endpoint path (relative to v1.0 or beta).

    .PARAMETER Headers
    Optional Graph headers (e.g. ConsistencyLevel).

    .PARAMETER UseBeta
    Switches base URI from v1.0 to beta.

    .PARAMETER AccessToken
    Required. Injects Authorization: Bearer header.

    .OUTPUTS
    Hashtable with Content.value (array of Graph items)
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $urlPath,

        [Parameter()]
        [hashtable] $Headers = @{},

        [switch] $UseBeta,
        [Parameter(Mandatory = $true)]
        [string] $AccessToken
    )

    $fullResults = @()
    $baseUri = if ($UseBeta) { "https://graph.microsoft.com/beta" } else { "https://graph.microsoft.com/v1.0" }
    $uri = "$baseUri$urlPath"

    try {
        do {
            $effectiveHeaders = @{}
            foreach ($key in $Headers.Keys) {
                $effectiveHeaders[$key] = $Headers[$key]
            }
            $effectiveHeaders["Authorization"] = "Bearer $AccessToken"

            $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $effectiveHeaders -ErrorAction Stop

            if ($response.value) {
                $fullResults += $response.value
            }

            $uri = $response.'@odata.nextLink'
        } while ($null -ne $uri)

        return @{ Content = @{ value = $fullResults } }
    }
    catch {
        Write-Warning "Graph API call failed: $_"
        throw $_
    }
}

function Check-AllUserMFARequired {
    [CmdletBinding()]
    param (
       <# [Parameter(Mandatory = $true)] [string] $ControlName,
        [Parameter(Mandatory = $true)] [string] $ItemName,
        [Parameter(Mandatory = $true)] [string] $itsgcode,
        [Parameter(Mandatory = $true)] [hashtable] $msgTable,
        [Parameter(Mandatory = $true)] [string] $ReportTime, #>
        [Parameter(Mandatory = $true)] [string] $FirstBreakGlassUPN,
        [Parameter(Mandatory = $true)] [string] $SecondBreakGlassUPN,
        [Parameter(Mandatory = $true)] [string] $AccessToken #,
       <# [string] $CloudUsageProfiles = "3",
        [string] $ModuleProfiles,
        [switch] $EnableMultiCloudProfiles #>
    )

    $ErrorList = New-Object System.Collections.ArrayList
    $nonMfaUsers = New-Object System.Collections.ArrayList
    $headers = @{ ConsistencyLevel = "eventual" }

    $usersSignIn = "/users?\$count=true&\$select=userPrincipalName,userType,id,assignedLicenses,identities,accountEnabled,authentication"

    $response = Invoke-GraphQueryEx -urlPath $usersSignIn -Headers $headers -AccessToken $AccessToken

    if (-not $response.Content.value) {
        $ErrorList.Add($msgTable.MSEntIDLicenseTypeNotFound) | Out-Null
    }

    foreach ($user in $response.Content.value) {
        if ($user.userType -eq 'Member' -and $user.accountEnabled -eq $true) {
            $isMFAEnforced = $false
            if ($user.authentication.methods -and $user.authentication.methods.Count -gt 0) {
                $isMFAEnforced = $true
            }
            if (-not $isMFAEnforced -and
                $user.userPrincipalName -ne $FirstBreakGlassUPN -and
                $user.userPrincipalName -ne $SecondBreakGlassUPN) {
                $nonMfaUsers.Add($user.userPrincipalName) | Out-Null
            }
        }
    }

    if ($nonMfaUsers.Count -gt 0) {
        $ErrorList.Add($msgTable.MFAEnforcementPartialOrMissing) | Out-Null
    } else {
        $ErrorList.Add($msgTable.MFAEnabled) | Out-Null
    }

    return $ErrorList
}
