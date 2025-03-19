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
        [string] $LAWResourceId,
        [string] 
        $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] 
        $EnableMultiCloudProfiles # New feature flag, default to false
    )

    [PSCustomObject] $ErrorList = @()
    [PSCustomObject] $nonMfaUsers = New-Object System.Collections.ArrayList
    [bool] $IsCompliant = $false
    [string] $Comments = $null
    [string] $UserComments = $null

    # Parse LAW Resource ID
    $lawParts = $LAWResourceId -split '/'
    $subscriptionId = $lawParts[2]
    $resourceGroupName = $lawParts[4] 
    $workspaceId = $lawParts[8]

    # list all users
    $usersSignIn = '/users?$select=displayName,signInActivity,userPrincipalName,id,createdDateTime,userType,accountEnabled'
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
            $ErrorList += $result.ErrorList
        }
        $userValidMFACounter = $result.userValidMFACounter
    }
    Write-Host "userValidMFACounter count from memberUsersUPNs count is $userValidMFACounter"
    Write-Host "memberUserUPNsBadMFA count is $($memberUserUPNsBadMFA.Count)"

    if(!$null -eq $extUserList){
        $result2 = Get-AllUserAuthInformation -allUserList $extUserList
        $extUserUPNsBadMFA = $result2.userUPNsBadMFA
        if( !$null -eq $result2.ErrorList){
            $ErrorList += $result2.ErrorList
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
    
    $matchingBadUsers = $allUsers | Where-Object {$userUPNsBadMFA.UPN -eq $_.userPrincipalName}

    # Condition: all users are MFA enabled
    if(($userValidMFACounter + 2) -eq $allUserUPNs.Count) {
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


        $badUpns = $matchingBadUsers | Select-Object -ExpandProperty UserPrincipalName
        $badUpnString = ($badUpns | ForEach-Object {$_.ToLower()}) -join "','"

            # Retrieve the log data and check the data retention period for sign in
        $kqlQuery = @"
SigninLogs
| where tolower(UserPrincipalName) in ('$($badUpnString)')
| where TimeGenerated > ago(365d)
| summarize arg_max(TimeGenerated, CreatedDateTime) by UserPrincipalName
| project LastSignIn=TimeGenerated, UserPrincipalName, CreatedTime = CreatedDateTime
| order by LastSignIn desc
"@

        # get context
        try{
        Select-AzSubscription -Subscription $subscriptionId -ErrorAction Stop | Out-Null
        }
        catch {
            $ErrorList.Add("Failed to execute the 'Select-AzSubscription' command with subscription ID '$($subscription)'--`
                ensure you have permissions to the subscription, the ID is correct, and that it exists in this tenant; returned `
                error message: $_")
            throw "Error: Failed to execute the 'Select-AzSubscription' command with subscription ID '$($subscription)'--ensure `
                you have permissions to the subscription, the ID is correct, and that it exists in this tenant; returned error message: $_"
        }

        try {
            $workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -Name $workspaceId
            $queryResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspace.CustomerId -Query $kqlQuery -ErrorAction Stop
            
            # Access the Results property of the query output
            $results = $queryResults.Results
    
            # check break glass account signin
            #$dataMostRecentSignInFirstBG = $results | Where-Object {$_.UserPrincipalName -eq $FirstBreakGlassUPN} | Select-Object -First 1
            #$dataMostRecentSignInSecondBG = $results | Where-Object {$_.UserPrincipalName -eq $SecondBreakGlassUPN} | Select-Object -First 1
        }
        catch {
          if ($null -eq $workspace) {
            $IsCompliant = $false
            $commentsArray += "Workspace not found in the specified resource group"
            $ErrorList += "Workspace not found in the specified resource group: $_"
          }
          if($_.Exception.Message -like "*ResourceNotFound*"){
    
          }
          else{
            # Handle errors and exceptions
            $IsCompliant = $false
            Write-Host "Error occurred retrieving the sign-in log data: $_"
          }
        }

        foreach($badUser in $matchingBadUsers){

            if($null -eq $badUser.signInActivity.lastSignInDateTime){
                $UserComments = $msgTable.nativeUserNoSignIn
            }
            elseif($null -ne $badUser.signInActivity.lastSignInDateTime){
                $daysLastSignIn = lastLoginInDays -LastSignIn $badUser.signInActivity.lastSignInDateTime
                $UserComments = $msgTable.nativeUserNonMfa -f $daysLastSignIn
            }
            $nonMfaUser = [PSCustomObject] @{
                DisplayName = $badUser.DisplayName
                UserPrincipalName = $badUser.userPrincipalName
                User_Enabled = $badUser.accountEnabled
                User_Type = $badUser.userType
                CreatedTime = $badUser.createdDateTime
                LastSignIn = $badUser.signInActivity.lastSignInDateTime
                Comments = $UserComments
                ItemName= $ItemName 
                ReportTime = $ReportTime
                itsgcode = $itsgcode
            }
            $nonMfaUsers.add($nonMfaUser)
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

