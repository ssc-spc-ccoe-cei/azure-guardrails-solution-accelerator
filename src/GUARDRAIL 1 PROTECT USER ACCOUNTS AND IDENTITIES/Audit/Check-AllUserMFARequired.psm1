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
    $urlPath = "/users"
    try {
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
        # portal
        $data = $response.Content
        # # localExecution
        # $data = $response

        if ($null -ne $data -and $null -ne $data.value) {
            $users = $data.value | Select-Object userPrincipalName , displayName, givenName, surname, id, mail
        }
    }
    catch {
        $errorMsg = "Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"                
        $ErrorList.Add($errorMsg)
        Write-Error "Error: $errorMsg"
    }

    # Check all users for MFA
    $allUserUPNs = $users.userPrincipalName
    Write-Host "DEBUG: allUserUPNs count is $($allUserUPNs.Count)"

    ## *************************##
    ## ****** Member user ******##
    ## *************************##
    $memberUsers = $users | Where-Object { $_.userPrincipalName -notlike "*#EXT#*" }

    # Get member users UPNs
    $memberUserList = $memberUsers | Select-Object userPrincipalName, mail
    # Exclude the breakglass account UPNs from the list
    if ($memberUserList.userPrincipalName -contains $FirstBreakGlassUPN){
        $memberUserList = $memberUserList | Where-Object { $_.userPrincipalName -ne $FirstBreakGlassUPN }
    }
    if ($memberUserList.userPrincipalName -contains $SecondBreakGlassUPN){
        $memberUserList = $memberUserList | Where-Object { $_.userPrincipalName -ne $SecondBreakGlassUPN }
    }
    Write-Host "DEBUG: memberUserList count is $($memberUserList.Count)"

    if(!$null -eq $memberUserList){
        $result = Get-AllUserAuthInformation -allUserList $memberUserList
        $memberUserUPNsBadMFA = $result.userUPNsBadMFA
        if( !$null -eq $result.ErrorList){
            $ErrorList =  $ErrorList.Add($result.ErrorList)
        }
        $userValidMFACounter = $result.userValidMFACounter
    }
    Write-Host "DEBUG: userValidMFACounter count from memberUsersUPNs count is $userValidMFACounter"


    ## ***************************##
    ## ****** External user ******##
    ## ***************************##
    $extUsers = $users | Where-Object { $_.userPrincipalName -like "*#EXT#*" }
    Write-Output "DEBUG: extUsers count is $($extUsers.Count)"
    Write-Output "DEBUG: extUsers UPNs are $($extUsers.userPrincipalName)"
    if(!$null -eq $extUsers){
        # Get external users UPNs and emails
        $extUserList = $extUsers | Select-Object userPrincipalName, mail
        $result2 = Get-AllUserAuthInformation -allUserList $extUserList
        $extUserUPNsBadMFA = $result2.userUPNsBadMFA
        if( !$null -eq $result2.ErrorList){
            $ErrorList =  $ErrorList.Add($result2.ErrorList)
        }
        # combined list
        $userValidMFACounter = $userValidMFACounter + $result2.userValidMFACounter
    }
    
    Write-Output "DEBUG: accounts auth method check done"
    Write-Host "DEBUG: userValidMFACounter count is $userValidMFACounter"
    
    if(!$null -eq $extUserUPNsBadMFA -and !$null -eq $memberUserUPNsBadMFA){
        $userUPNsBadMFA =  $memberUserUPNsBadMFA +  $extUserUPNsBadMFA
    }elseif($null -eq $extUserUPNsBadMFA -or $extUserUPNsBadMFA.Count -eq 0){
        $userUPNsBadMFA =  $memberUserUPNsBadMFA 
    }elseif($null -eq $memberUserUPNsBadMFA -or $memberUserUPNsBadMFA.Count -eq 0){
        $userUPNsBadMFA =  $extUserUPNsBadMFA
    }
    Write-Output "DEBUG: userUPNsBadMFA count is $($userUPNsBadMFA.Count)"
    Write-Output "DEBUG: userUPNsBadMFA UPNs are $($userUPNsBadMFA.UPN)"
       

    # Condition: all users are MFA enabled
    if($userValidMFACounter -eq $allUserUPNs.Count) {
        $commentsArray = $msgTable.allUserHaveMFA
        $IsCompliant = $true
    }
    # Condition: Not all user UPNs are MFA enabled or MFA is not configured properly
    else {
        # This will be used for debugging
        if($userUPNsBadMFA.Count -eq 0){
            Write-Error "Something is wrong as userUPNsBadMFA Count equals 0. This output should only execute if there is an error populating userUPNsBadMFA"
        }
        else {
            $upnString = ($userUPNsBadMFA | ForEach-Object { $_.UPN }) -join ', '
            $commentsArray = $msgTable.userMisconfiguredMFA -f $upnString
            $IsCompliant = $false
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

    # Conditionally add the Profile field based on the feature flag
    if ($EnableMultiCloudProfiles) {
        $result = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        if ($result -eq 0) {
            Write-Output "No matching profile found"
            $PsObject.ComplianceStatus = "Not Applicable"
        } else {
            Write-Output "Valid profile returned: $result"
            $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $result
        }
    }
    
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput   
}

