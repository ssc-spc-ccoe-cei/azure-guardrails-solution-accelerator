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
        [Parameter(Mandatory=$true)]
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string] $ReportTime,
        [Parameter(Mandatory=$true)]
        [string] $FirstBreakGlassUPN,
        [Parameter(Mandatory=$true)] 
        [string] $SecondBreakGlassUPN,
        [string] 
        $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] 
        $EnableMultiCloudProfiles # default to false
    )

    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    [bool] $IsCompliant = $false
    [string] $Comments = $null
    [PSCustomObject] $nonMfaUsers = New-Object System.Collections.ArrayList
    $UserComments = $null

    $usersSignIn = '/users?$select=displayName,signInActivity,userPrincipalName,id,mail,createdDateTime,userType,accountEnabled'
    try {
        $response = Invoke-GraphQuery -urlPath $usersSignIn -ErrorAction Stop
        $allUsers = $response.Content.value
    }
    catch {
        $Errorlist.Add("Failed to call Microsoft Graph REST API at URL '$usersSignIn'; returned error message: $_")
        Write-Warning "Error: Failed to call Microsoft Graph REST API at URL '$usersSignIn'; returned error message: $_"
    }
    # Check all users for MFA
    $allUsers = $allUsers | Where-Object {$_.accountEnabled -ne $false}
    $allUserUPNs = $allUsers.userPrincipalName

    Write-Host "allUserUPNs count is $($allUserUPNs.Count)"

    # list of guest users
    $extUsers = $allUsers | Where-Object { $_.userType -eq 'Guest'}
    if(!$null -eq $extUsers){
        $extUserList =  $extUsers | Select-Object userPrincipalName , displayName, id, mail
    }

    $extUserUPNs = $extUserList.userPrincipalName
    Write-Host "extUsers count is $($extUsers.Count)"
    Write-Host "extUsers UPNs are $($extUsers.userPrincipalName)"
    
    # List of member users
    $memberUsers = $allUsers | Where-Object { $extUserUPNs -notcontains $_.UserPrincipalName }

    # Get member users UPNs
    $memberUserList = $memberUsers | Select-Object userPrincipalName, mail
    # Exclude the breakglass account UPNs from the list
    if ($memberUserList.userPrincipalName -contains $FirstBreakGlassUPN){
        $memberUserList = $memberUserList | Where-Object { $_.userPrincipalName -ne $FirstBreakGlassUPN }
    }
    if ($memberUserList.userPrincipalName -contains $SecondBreakGlassUPN){
        $memberUserList = $memberUserList | Where-Object { $_.userPrincipalName -ne $SecondBreakGlassUPN }
    }
    Write-Host "memberUserList count is $($memberUserList.Count)"

    # Get MFA information for member and external users
    if(!$null -eq $memberUserList){
        $result = Get-AllUserAuthInformation -allUserList $memberUserList
        $memberUserUPNsBadMFA = $result.userUPNsBadMFA
        if($result.ErrorList){
            $ErrorList.Add($result.ErrorList)
        }
        $userValidMFACounter = $result.userValidMFACounter
    }
    Write-Host "userValidMFACounter count from memberUsersUPNs count is $userValidMFACounter"
    Write-Host "memberUserUPNsBadMFA count is $($memberUserUPNsBadMFA.Count)"

    if(!$null -eq $extUserList){
        $result2 = Get-AllUserAuthInformation -allUserList $extUserList
        $extUserUPNsBadMFA = $result2.userUPNsBadMFA
        if($result2.ErrorList){
            $ErrorList.Add($result2.ErrorList)
        }
        # combined list
        $userValidMFACounter = $userValidMFACounter + $result2.userValidMFACounter
    }
    Write-Host "extUserUPNsBadMFA count is $($extUserUPNsBadMFA.Count)"
    Write-Host "accounts auth method check done"
    Write-Host "userValidMFACounter count is $userValidMFACounter"
    
    if(!$null -eq $extUserUPNsBadMFA -and !$null -eq $memberUserUPNsBadMFA){
        $userUPNsBadMFA =  $memberUserUPNsBadMFA +  $extUserUPNsBadMFA
    }elseif($null -eq $extUserUPNsBadMFA -or $extUserUPNsBadMFA.Count -eq 0){
        $userUPNsBadMFA =  $memberUserUPNsBadMFA 
    }elseif($null -eq $memberUserUPNsBadMFA -or $memberUserUPNsBadMFA.Count -eq 0){
        $userUPNsBadMFA =  $extUserUPNsBadMFA
    }
    Write-Host "userUPNsBadMFA count is $($userUPNsBadMFA.Count)"
    Write-Host "userUPNsBadMFA UPNs are $($userUPNsBadMFA.UPN)"
       

    $matchingBadUsers = $allUsers | Where-Object {$userUPNsBadMFA.UPN -contains $_.userPrincipalName}

    if($null -eq $allUsers){
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
            ItemName= $ItemName 
            ReportTime = $ReportTime
            itsgcode = $itsgcode
        }
        $nonMfaUsers.add($Customuser)
    }

    # Condition: all users are MFA enabled
    elseif(($userValidMFACounter + 2) -eq $allUserUPNs.Count) {
        $commentsArray = $msgTable.allUserHaveMFA
        $IsCompliant = $true

        #If all users are mfa compliant, display a ghost user with mfa enabled comment displayed
        $Customuser = [PSCustomObject] @{
            DisplayName = "N/A"
            UserPrincipalName = "N/A"
            User_Enabled = "N/A"
            User_Type = "N/A"
            CreatedTime = "N/A"
            LastSignIn = "N/A"
            Comments = $commentsArray
            ItemName= $ItemName 
            ReportTime = $ReportTime
            itsgcode = $itsgcode
        }
        $nonMfaUsers.add($Customuser)
    }
    # Condition: Not all user UPNs are MFA enabled or MFA is not configured properly
    else {
        $commentsArray = $msgTable.userMisconfiguredMFA
        $IsCompliant = $false

        foreach($badExtUser in $matchingBadUsers){

            if($null -eq $badExtUser.signInActivity.lastSignInDateTime){
                $UserComments = $msgTable.nativeUserNoSignIn
            }
            elseif($null -ne $badExtUser.signInActivity.lastSignInDateTime){
                $daysLastSignIn = lastLoginInDays -LastSignIn $badExtUser.signInActivity.lastSignInDateTime
                $UserComments = $msgTable.nativeUserNonMfa -f $daysLastSignIn
            }
            $nonMfaExtUser = [PSCustomObject] @{
                DisplayName = $badExtUser.DisplayName
                UserPrincipalName = $badExtUser.userPrincipalName
                User_Enabled = $badExtUser.accountEnabled
                User_Type = $badExtUser.userType
                CreatedTime = $badExtUser.createdDateTime
                LastSignIn = $badExtUser.signInActivity.lastSignInDateTime
                Comments = $UserComments
                ItemName= $ItemName 
                ReportTime = $ReportTime
                itsgcode = $itsgcode
            }
            $nonMfaUsers.add($nonMfaExtUser)
        }
    }

    $Comments = $commentsArray -join ";"
    
    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        ItemName         = $ItemName
        Comments         = $Comments
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }

    $AdditionalResults = [PSCustomObject]@{
        records = $nonMfaUsers
        logType = "GR1NonMfaUsers"
    }

    # Add profile information if MCUP feature is enabled
    if ($EnableMultiCloudProfiles) {
        $result = Add-ProfileInformation -Result $PsObject -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId
        Write-Host "$result"
    }
    
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput   
}

