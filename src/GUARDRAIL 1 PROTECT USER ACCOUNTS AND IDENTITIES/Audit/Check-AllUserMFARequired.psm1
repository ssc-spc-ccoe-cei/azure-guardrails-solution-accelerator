# Calculates the number of days since the user's last sign-in
function lastLoginInDays {
    param(
        $LastSignIn
    )

    $lastSignInDate = Get-Date $LastSignIn
    $todayDate = Get-Date
    $daysLastLogin = ($todayDate - $lastSignInDate).Days

    return $daysLastLogin
}

# Main function to check if all users have MFA enabled and report compliance
function Check-AllUserMFARequired {
    param (
        # Control metadata parameters
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
        # Optional parameters for multi-cloud profile evaluation
        [string] $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] $EnableMultiCloudProfiles # default to false
    )

    # Initialize variables for results and error tracking
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    [bool] $IsCompliant = $false
    [string] $Comments = $null
    [PSCustomObject] $nonMfaUsers = New-Object System.Collections.ArrayList
    $UserComments = $null

    # Get the automation variable for paging through users
    $nextLinkVar = Get-AutomationVariable -Name "MFAUsersNextLink"
    $usersSignIn = '/users?$select=displayName,signInActivity,userPrincipalName,id,mail,createdDateTime,userType,accountEnabled&$top=100'

    # Retrieve the next page link if available (handles encrypted variable)
    try {
        $secureNextLink = Get-AutomationVariable -Name $nextLinkVar -ErrorAction SilentlyContinue
        if ($secureNextLink -is [System.Security.SecureString]) {
            $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureNextLink)
            $nextLink = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        } else {
            $nextLink = $secureNextLink
        }
    } catch {
        $nextLink = $null
    }

    # Build the query path for Microsoft Graph API
    if ([string]::IsNullOrEmpty($nextLink)) {
        $queryPath = $usersSignIn
    } else {
        $queryPath = $nextLink.Replace("https://graph.microsoft.com/v1.0", "")
    }

    # Query Microsoft Graph API for user data
    try {
        $response = Invoke-GraphQuery -urlPath $queryPath -ErrorAction Stop
        $allUsers = $response.Content.value
        $nextPage = $response.Content.'@odata.nextLink'
        # Handle paging: save next link and exit if more pages exist
        if ($null -ne $nextPage -and $nextPage -ne "") {
            Set-AutomationVariable -Name $nextLinkVar -Value $nextPage
            Write-Output "More pages exist. Next link saved. Please re-run the runbook."
            Exit
        } else {
            Set-AutomationVariable -Name $nextLinkVar -Value ""
            Write-Output "All users processed."
        }
    } catch {
        $ErrorList.Add("Failed to call Microsoft Graph REST API at URL '$queryPath'; returned error message: $_")
        Write-Warning "Error: Failed to call Microsoft Graph REST API at URL '$queryPath'; returned error message: $_"
    }

    # Filter out disabled accounts
    $allUsers = $allUsers | Where-Object { $_.accountEnabled -ne $false }
    $allUserUPNs = $allUsers.userPrincipalName

    Write-Host "allUserUPNs count is $($allUserUPNs.Count)"

    # Identify guest users
    $extUsers = $allUsers | Where-Object { $_.userType -eq 'Guest' }
    if ($null -ne $extUsers) {
        $extUserList = $extUsers | Select-Object userPrincipalName, displayName, id, mail
    }

    $extUserUPNs = $extUserList.userPrincipalName
    Write-Host "extUsers count is $($extUsers.Count)"
    Write-Host "extUsers UPNs are $($extUsers.userPrincipalName)"

    # Identify member users (excluding guests)
    $memberUsers = $allUsers | Where-Object { $extUserUPNs -notcontains $_.UserPrincipalName }

    # Get member users UPNs and exclude breakglass accounts
    $memberUserList = $memberUsers | Select-Object userPrincipalName, mail
    if ($memberUserList.userPrincipalName -contains $FirstBreakGlassUPN) {
        $memberUserList = $memberUserList | Where-Object { $_.userPrincipalName -ne $FirstBreakGlassUPN }
    }
    if ($memberUserList.userPrincipalName -contains $SecondBreakGlassUPN) {
        $memberUserList = $memberUserList | Where-Object { $_.userPrincipalName -ne $SecondBreakGlassUPN }
    }
    Write-Host "memberUserList count is $($memberUserList.Count)"

    # Get MFA status for member users
    if ($null -ne $memberUserList) {
        $result = Get-AllUserAuthInformation -allUserList $memberUserList
        $memberUserUPNsBadMFA = $result.userUPNsBadMFA
        if ($result.ErrorList) {
            $ErrorList.Add($result.ErrorList)
        }
        $userValidMFACounter = $result.userValidMFACounter
    }
    Write-Host "userValidMFACounter count from memberUsersUPNs count is $userValidMFACounter"
    Write-Host "memberUserUPNsBadMFA count is $($memberUserUPNsBadMFA.Count)"

    # Get MFA status for guest users
    if ($null -ne $extUserList) {
        $result2 = Get-AllUserAuthInformation -allUserList $extUserList
        $extUserUPNsBadMFA = $result2.userUPNsBadMFA
        if ($result2.ErrorList) {
            $ErrorList.Add($result2.ErrorList)
        }
        # Combine valid MFA counters
        $userValidMFACounter = $userValidMFACounter + $result2.userValidMFACounter
    }
    Write-Host "extUserUPNsBadMFA count is $($extUserUPNsBadMFA.Count)"
    Write-Host "accounts auth method check done"
    Write-Host "userValidMFACounter count is $userValidMFACounter"

    # Merge lists of users with bad MFA
    if ($null -ne $extUserUPNsBadMFA -and $null -ne $memberUserUPNsBadMFA) {
        $userUPNsBadMFA = $memberUserUPNsBadMFA + $extUserUPNsBadMFA
    } elseif ($null -eq $extUserUPNsBadMFA -or $extUserUPNsBadMFA.Count -eq 0) {
        $userUPNsBadMFA = $memberUserUPNsBadMFA
    } elseif ($null -eq $memberUserUPNsBadMFA -or $memberUserUPNsBadMFA.Count -eq 0) {
        $userUPNsBadMFA = $extUserUPNsBadMFA
    }
    Write-Host "userUPNsBadMFA count is $($userUPNsBadMFA.Count)"
    Write-Host "userUPNsBadMFA UPNs are $($userUPNsBadMFA.UPN)"

    # Find users with bad MFA configuration
    $matchingBadUsers = $allUsers | Where-Object { $userUPNsBadMFA.UPN -contains $_.userPrincipalName }

    # Handle case: No users found
    if ($null -eq $allUsers) {
        $IsCompliant = $false
        $commentsArray = $msgTable.MSEntIDLicenseTypeNotFound

        $Customuser = [PSCustomObject] @{
            DisplayName = "N/A"
            UserPrincipalName = "N/A"
            User_Enabled = "N/A"
            User_Type = "N/A"
            CreatedTime = "N/A"
            LastSignIn = "N/A"
            Comments = $commentsArray
            ItemName = $ItemName
            ReportTime = $ReportTime
            itsgcode = $itsgcode
        }
        $nonMfaUsers.add($Customuser)
    }
    # Handle case: All users are MFA compliant
    elseif (($userValidMFACounter + 2) -eq $allUserUPNs.Count) {
        $commentsArray = $msgTable.allUserHaveMFA
        $IsCompliant = $true

        # Add a placeholder user to indicate full compliance
        $Customuser = [PSCustomObject] @{
            DisplayName = "N/A"
            UserPrincipalName = "N/A"
            User_Enabled = "N/A"
            User_Type = "N/A"
            CreatedTime = "N/A"
            LastSignIn = "N/A"
            Comments = $commentsArray
            ItemName = $ItemName
            ReportTime = $ReportTime
            itsgcode = $itsgcode
        }
        $nonMfaUsers.add($Customuser)
    }
    # Handle case: Some users are not MFA compliant
    else {
        $commentsArray = $msgTable.userMisconfiguredMFA
        $IsCompliant = $false

        foreach ($badExtUser in $matchingBadUsers) {
            # If user has never signed in
            if ($null -eq $badExtUser.signInActivity.lastSignInDateTime) {
                $UserComments = $msgTable.nativeUserNoSignIn
            }
            # If user has signed in, calculate days since last sign-in
            elseif ($null -ne $badExtUser.signInActivity.lastSignInDateTime) {
                $daysLastSignIn = lastLoginInDays -LastSignIn $badExtUser.signInActivity.lastSignInDateTime
                $UserComments = $msgTable.nativeUserNonMfa -f $daysLastSignIn
            }
            # Add user to non-MFA users list
            $nonMfaExtUser = [PSCustomObject] @{
                DisplayName = $badExtUser.DisplayName
                UserPrincipalName = $badExtUser.userPrincipalName
                User_Enabled = $badExtUser.accountEnabled
                User_Type = $badExtUser.userType
                CreatedTime = $badExtUser.createdDateTime
                LastSignIn = $badExtUser.signInActivity.lastSignInDateTime
                Comments = $UserComments
                ItemName = $ItemName
                ReportTime = $ReportTime
                itsgcode = $itsgcode
            }
            $nonMfaUsers.add($nonMfaExtUser)
        }
    }

    # Combine comments for output
    $Comments = $commentsArray -join ";"

    # Build output object for compliance results
    $PsObject = [PSCustomObject] @{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        ItemName         = $ItemName
        Comments         = $Comments
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }

    # Build additional results object for logging
    $AdditionalResults = [PSCustomObject] @{
        records = $nonMfaUsers
        logType = "GR1NonMfaUsers"
    }

    # Optionally add profile information if multi-cloud profiles are enabled
    if ($EnableMultiCloudProfiles) {
        $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        if (!$evalResult.ShouldEvaluate) {
            if ($evalResult.Profile -gt 0) {
                $PsObject.ComplianceStatus = "Not Applicable"
                $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                $PsObject.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
            } else {
                $ErrorList.Add("Error occurred while evaluating profile configuration")
            }
        } else {
            $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
        }
    }

    # Final output object
    $moduleOutput = [PSCustomObject] @{
        ComplianceResults = $PsObject
        Errors = $ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput
}

