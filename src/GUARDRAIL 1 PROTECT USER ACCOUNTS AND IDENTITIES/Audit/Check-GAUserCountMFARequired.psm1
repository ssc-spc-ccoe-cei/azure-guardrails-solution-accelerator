
function Check-GAUserCountMFARequired {
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

    # Get the list of GA users (ACTIVE assignments)
    $urlPath = "/directoryRoles"
    try {
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
        # portal
        $data = $response.Content
        # # localExecution
        # $data = $response

        if ($null -ne $data -and $null -ne $data.value) {
            $rolesResponse  = $data.value
        }
    }
    catch {
        $errorMsg = "Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"                
        $ErrorList.Add($errorMsg)
        Write-Error "Error: $errorMsg"
    }

    # Filter the Global Administrator role ID
    $globalAdminRole = $rolesResponse | Where-Object { $_.displayName -eq "Global Administrator" }

    # Get directory roles for each user with the global admin access
    $globalAdminUserAccounts = @()
    $roleAssignments = @()

    $roleId = $globalAdminRole.id
    $roleName = $globalAdminRole.displayName
    Write-Host "The role name is $roleName"
    # Endpoint to get members of the role
    $urlPath = "/directoryRoles/$roleId/members"
    try{
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
        # portal
        $data = $response.Content
        # # localExecution
        # $data = $response

        if ($null -ne $data -and $null -ne $data.value) {
            $gaRoleResponse  = $data.value
        }
    }
    catch {
        $errorMsg = "Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"                
        $ErrorList.Add($errorMsg)
        Write-Error "Error: $errorMsg"
    }
    # Get member users UPNs
    $gaUserList = $gaRoleResponse 
    # Exclude the breakglass account UPNs from the list
    if ($gaUserList.userPrincipalName -contains $FirstBreakGlassUPN){
        $gaUserList = $gaUserList | Where-Object { $_.userPrincipalName -ne $FirstBreakGlassUPN }
    }
    if ($gaUserList.userPrincipalName -contains $SecondBreakGlassUPN){
        $gaUserList = $gaUserList | Where-Object { $_.userPrincipalName -ne $SecondBreakGlassUPN }

    }

    foreach ($gaUser in $gaUserList) {
        $roleAssignments = [PSCustomObject]@{
            roleId              = $roleId
            roleName            = $roleName
            userId              = $gaUser.id
            displayName         = $gaUser.displayName
            mail                = $gaUser.mail
            userPrincipalName   = $gaUser.userPrincipalName
        }
        $globalAdminUserAccounts +=  $roleAssignments
    }

    # Count Users with active GA 
    $userValidMFACounter = @()

    ## **********************************************##
    ## ****All Global Admin Accounts except BG ******##
    ## **********************************************##
    $allGAUserUPNs = $globalAdminUserAccounts.userPrincipalName
    Write-Host "DEBUG: allGAUserUPNs count is $($allGAUserUPNs.Count)"
    Write-Output "DEBUG: allGAUserUPNs count is $($allGAUserUPNs.Count)"
    Write-Output "DEBUG: allGAUserUPNs user UPNs are $allGAUserUPNs"
    if (($allGAUserUPNs.Count -ge 6) -or ($allGAUserUPNs.Count -lt 2)){
        $commentsArray =  $msgTable.isNotCompliant + ' ' + $msgTable.globalAdminAccntsSurplus
    }
    else{
        ## Global Admin counts are within the range - proceed with MFA check

        ## *****************************************##
        ## ****** Member user as Global Admin ******##
        ## *****************************************##
        $memberUsers = $globalAdminUserAccounts | Where-Object { $_.userPrincipalName -notlike "*#EXT#*" }

        # Get GA member users UPNs
        $memberUsersUPNs= $memberUsers | Select-Object userPrincipalName, mail
        Write-Output "DEBUG: GA memberUsersUPNs count is $($memberUsersUPNs.Count)"
        Write-Output "DEBUG: GA memberUsersUPNs are $($memberUsersUPNs.userPrincipalName)"
        Write-Host "DEBUG: GA memberUsersUPNs count is $($memberUsersUPNs.Count)"

        if(!$null -eq $memberUsersUPNs){
            $result = Get-AllUserAuthInformation -allUserList $memberUsersUPNs
            $memberUserUPNsBadMFA = $result.userUPNsBadMFA
            $memberUserUPNsValidMFA = $result.userUPNsValidMFA
            if( !$null -eq $result.ErrorList){
                $ErrorList =  $ErrorList.Add($result.ErrorList)
            }
            $userValidMFACounter = $result.userValidMFACounter
        }
        Write-Host "DEBUG: userValidMFACounter count from memberUsersUPNs count is $userValidMFACounter"
        

        ## *******************************************##
        ## ****** External user as Global Admin ******##
        ## *******************************************##
        $extUsers = $globalAdminUserAccounts | Where-Object { $_.userPrincipalName -like "*#EXT#*" }
        Write-Output "DEBUG: extUsers count is $($extUsers.Count)"
        Write-Output "DEBUG: extUsers UPNs are $($extUsers.userPrincipalName)"
        if(!$null -eq $extUsers){
             # Get external users UPNs and emails
            $extUsersUPN = $extUsers | Select-Object userPrincipalName, mail
            $result2 = Get-AllUserAuthInformation -allUserList $extUsersUPN
            $extUserUPNsBadMFA = $result2.userUPNsBadMFA
            $extUserUPNsValidMFA = $result2.userUPNsValidMFA
            if( !$null -eq $result2.ErrorList){
                $ErrorList =  $ErrorList.Add($result2.ErrorList)
            }
            
            # combined list
            $userValidMFACounter = $userValidMFACounter + $result2.userValidMFACounter
        }
        Write-Output "DEBUG: GA accounts auth method check done"
        Write-Host "DEBUG: userValidMFACounter count is $userValidMFACounter"
        Write-Output "DEBUG: userValidMFACounter count is $userValidMFACounter"
        Write-Output "DEBUG: userValidMFA member UPNs are $($memberUserUPNsValidMFA.UPN) and external UPNs are $($extUserUPNsValidMFA.UPN)"
        

        if(!$null -eq $extUserUPNsBadMFA -and !$null -eq $memberUserUPNsBadMFA){
            $userUPNsBadMFA =  $memberUserUPNsBadMFA +  $extUserUPNsBadMFA
        }elseif($null -eq $extUserUPNsBadMFA){
            $userUPNsBadMFA =  $memberUserUPNsBadMFA 
        }elseif($null -eq $memberUserUPNsBadMFA){
            $userUPNsBadMFA =  $extUserUPNsBadMFA
        }

        Write-Output "DEBUG: userUPNsBadMFA count is $($userUPNsBadMFA.Count)"
        Write-Output "DEBUG: userUPNsBadMFA UPNs are $($userUPNsBadMFA.UPN)"
       
        # Condition: all users are MFA enabled
        if($userValidMFACounter -eq $allGAUserUPNs.Count) {
            $commentsArray += ' ' + $msgTable.allGAUserHaveMFA
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
                $commentsArray += ' ' + $msgTable.gaUserMisconfiguredMFA -f $upnString
                $IsCompliant = $false
            }
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



