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
        $EnableMultiCloudProfiles # New feature flag, default to false
    )

    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    [bool] $IsCompliant = $false
    [string] $Comments = $null


    # list all users
    $usersSignIn = '/users?$select=displayName,signInActivity,userPrincipalName,id,mail'
    try {
        $response = Invoke-GraphQuery -urlPath $usersSignIn -ErrorAction Stop
        $allUsers = $response.Content.value
    }
    catch {
        $Errorlist.Add("Failed to call Microsoft Graph REST API at URL '$usersSignIn'; returned error message: $_")
        Write-Warning "Error: Failed to call Microsoft Graph REST API at URL '$usersSignIn'; returned error message: $_"
    }

    # Check all users for MFA
    $allUserUPNs = $allUsers.userPrincipalName
    Write-Host "allUserUPNs count is $($allUserUPNs.Count)"

    # list of guest users
    $extUsers = Get-AzADUser -Filter "usertype eq 'guest'"
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
        if( !$null -eq $result.ErrorList){
            $ErrorList =  $ErrorList.Add($result.ErrorList)
        }
        $userValidMFACounter = $result.userValidMFACounter
    }
    Write-Host "userValidMFACounter count from memberUsersUPNs count is $userValidMFACounter"
    Write-Host "memberUserUPNsBadMFA count is $($memberUserUPNsBadMFA.Count)"

    if(!$null -eq $extUserList){
        $result2 = Get-AllUserAuthInformation -allUserList $extUserList
        $extUserUPNsBadMFA = $result2.userUPNsBadMFA
        if( !$null -eq $result2.ErrorList){
            $ErrorList =  $ErrorList.Add($result2.ErrorList)
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
       

    # Condition: all users are MFA enabled
    if(($userValidMFACounter + 2) -eq $allUserUPNs.Count) {
        $commentsArray = $msgTable.allUserHaveMFA
        $IsCompliant = $true
    }
    # Condition: Not all user UPNs are MFA enabled or MFA is not configured properly
    else {
        $upnString = ($userUPNsBadMFA | ForEach-Object { $_.UPN }) -join ', '
        $commentsArray = $msgTable.userMisconfiguredMFA -f $upnString
        $IsCompliant = $false
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

    # Conditionally add the Profile field based on the feature flag
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
    
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput   
}

