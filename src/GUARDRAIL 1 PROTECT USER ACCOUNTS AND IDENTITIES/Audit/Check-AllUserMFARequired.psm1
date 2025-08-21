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

    # Fetch users (raw)
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

    # For each user, fetch authentication methods and attach to the record (flattened for ingestion)
    $augmentedUsers = @()
    foreach ($u in $allUsers) {
        $flatMethods = @()
        try {
            $authUrl = "/users/$($u.id)/authentication/methods"
            $authResp = Invoke-GraphQueryEX -urlPath $authUrl -ErrorAction Stop
            if ($authResp -is [System.Array]) {
                $authResp = $authResp | Where-Object { $_.Content -ne $null -or $_.StatusCode -ne $null } | Select-Object -Last 1
            }
            $methods = @($authResp.Content.value)

            foreach ($m in $methods) {
                $flatMethods += [PSCustomObject]@{
                    type             = $m.'@odata.type'
                    id               = $m.id
                    displayName      = $m.displayName
                    phoneType        = $m.phoneType
                    phoneNumber      = $m.phoneNumber
                    isDefault        = $m.isDefault
                    keyStrength      = $m.keyStrength
                    appDisplayName   = $m.appDisplayName
                    createdDateTime  = $m.createdDateTime
                }
            }
        }
        catch {
            Write-Warning "Failed to get authentication methods for user $($u.userPrincipalName): $_"
            $ErrorList += "Failed auth methods for $($u.userPrincipalName): $_"
        }

        # Build a composite object, preserving user properties and adding flattened methods
        $augmentedUsers += [PSCustomObject]@{
            id                     = $u.id
            userPrincipalName      = $u.userPrincipalName
            displayName            = $u.displayName
            mail                   = $u.mail
            createdDateTime        = $u.createdDateTime
            userType               = $u.userType
            accountEnabled         = $u.accountEnabled
            signInActivity         = $u.signInActivity
            authenticationMethods  = $flatMethods
            ReportTime             = $ReportTime
            ItemName               = $ItemName
            itsgcode               = $itsgcode
        }
    }

    # Prepare a minimal compliance-shaped object so main.ps1 can process uniformly
    $PsObject = [PSCustomObject]@{
        ComplianceStatus = "Not Evaluated"
        ControlName      = $ControlName
        ItemName         = $ItemName
        Comments         = "Raw export of users and authentication methods"
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }

    # Return in the expected envelope; main.ps1 will send AdditionalResults to Log Analytics
    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = @($PsObject)  # ensure array for ingestion
        Errors            = @($ErrorList)
        AdditionalResults = [PSCustomObject]@{
            records = @($augmentedUsers)
            logType = "GuardrailsUserRaw"
        }
    }
    return $moduleOutput   
}

