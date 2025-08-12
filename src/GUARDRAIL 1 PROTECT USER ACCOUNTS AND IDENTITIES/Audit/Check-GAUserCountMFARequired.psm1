function get-MFACount{
    param (      
        [array] $globalAdminUserAccounts
    )

    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    ## Proceed with MFA check

    ## *****************************************##
    ## ****** Member user as Global Admin ******##
    ## *****************************************##
    $memberUsers = $globalAdminUserAccounts | Where-Object { $_.userPrincipalName -notlike "*#EXT#*" }

    # Get GA member users UPNs
    $memberUsersUPNs= $memberUsers | Select-Object userPrincipalName, mail
    Write-Host "GA memberUsersUPNs are $($memberUsersUPNs.userPrincipalName)"
    Write-Host "GA memberUsersUPNs count is $($memberUsersUPNs.Count)"

    if(!$null -eq $memberUsersUPNs){
        $result = Get-AllUserAuthInformation -allUserList $memberUsersUPNs
        $memberUserUPNsBadMFA = $result.userUPNsBadMFA
        $memberUserUPNsValidMFA = $result.userUPNsValidMFA
        if($result.ErrorList){
            $ErrorList.Add($result.ErrorList)
        }
        $userValidMFACounter = $result.userValidMFACounter
    }
    Write-Host "userValidMFACounter count from memberUsersUPNs count is $userValidMFACounter"
    

    ## *******************************************##
    ## ****** External user as Global Admin ******##
    ## *******************************************##
    $extUsers = $globalAdminUserAccounts | Where-Object { $_.userPrincipalName -like "*#EXT#*" }
    Write-Host "extUsers count is $($extUsers.Count)"
    Write-Host "extUsers UPNs are $($extUsers.userPrincipalName)"
    if(!$null -eq $extUsers){
        # Get external users UPNs and emails
        $extUsersUPN = $extUsers | Select-Object userPrincipalName, mail
        $result2 = Get-AllUserAuthInformation -allUserList $extUsersUPN
        $extUserUPNsBadMFA = $result2.userUPNsBadMFA
        $extUserUPNsValidMFA = $result2.userUPNsValidMFA
        if($result2.ErrorList){
            $ErrorList.Add($result2.ErrorList)
        }
        
        # combined list
        $userValidMFACounter = $userValidMFACounter + $result2.userValidMFACounter
    }

    Write-Host "GA accounts auth method check done"
    Write-Host "userValidMFACounter count is $userValidMFACounter"
    Write-Host "userValidMFA member UPNs are $($memberUserUPNsValidMFA.UPN) and external UPNs are $($extUserUPNsValidMFA.UPN)"

    if($null -eq $extUserUPNsBadMFA -or $extUserUPNsBadMFA.Count -eq 0 -and (!$null -eq $memberUserUPNsBadMFA)){
        $userUPNsBadMFA =  $memberUserUPNsBadMFA 
    }elseif(($null -eq $memberUserUPNsBadMFA -or $memberUserUPNsBadMFA.Count -eq 0) -and (!$null -eq $extUserUPNsBadMFA)){
        $userUPNsBadMFA =  $extUserUPNsBadMFA
    }elseif(!$null -eq $extUserUPNsBadMFA -and (!$null -eq $memberUserUPNsBadMFA)){
        $userUPNsBadMFA =  $memberUserUPNsBadMFA +  $extUserUPNsBadMFA
    }

    Write-Host "userUPNsBadMFA count is $($userUPNsBadMFA.Count)"
    Write-Host "userUPNsBadMFA UPNs are $($userUPNsBadMFA.UPN)"

    $result = [PSCustomObject]@{
        userValidMFACounter = $userValidMFACounter
        userUPNsBadMFA = $userUPNsBadMFA
        ErrorList = $ErrorList
    }

    return $result

}

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
    Write-Host "allGAUserUPNs count is $($allGAUserUPNs.Count)"
    Write-Host "allGAUserUPNs user UPNs are $allGAUserUPNs"

    if($allGAUserUPNs.Count -eq 0){
        ## ASSUMPTION: There are two BG accounts
        Write-Host "allGAUserUPNs count is $($allGAUserUPNs.Count)"
        Write-Host "The solution is assuming that the user is using eligible Global Administrator Accounts and including the two Break Glass accounts in order to be compliant. "
        $commentsArray =  $msgTable.isCompliant + ' ' + $msgTable.globalAdminAccntsMinimum
        $IsCompliant = $true
    }
    elseif ($allGAUserUPNs.Count -gt 5){
        $commentsArray =  $msgTable.isNotCompliant + ' ' + $msgTable.globalAdminAccntsSurplus
        $IsCompliant = $false  
    }
    else {
        ## Proceed with MFA check
        $MFAresult = get-MFACount($globalAdminUserAccounts)

        $userValidMFACounter = $MFAresult.userValidMFACounter
        $userUPNsBadMFA = $MFAresult.userUPNsBadMFA
        if($MFAresult.ErrorList){
            $ErrorList.Add($MFAresult.ErrorList)
        }

        if ($allGAUserUPNs.Count -eq 1) {
            ## Proceed with MFA check for the non-BG account with the following assumption
            Write-Host "There is 1 GA account"
            # Compliant: The solution is assuming that the user is using eligible Global Administrator Accounts and including the two Break Glass accounts in order to be compliant. "

            # Condition: The non-BG user has enabled MFA enabled
            if($userValidMFACounter -eq $allGAUserUPNs.Count) {
                $commentsArray = $msgTable.isCompliant + ' ' + $msgTable.globalAdminAccntsMinimum
                $IsCompliant = $true
            }
            else{
                # the non-BG user has not enabled MFA
                $commentsArray = $msgTable.isNotCompliant + ' ' + $msgTable.globalAdminAccntsMinimum
                $upnString = ($userUPNsBadMFA | ForEach-Object { $_.UPN }) -join ', '
                $commentsArray += ' ' + $msgTable.gaUserMisconfiguredMFA -f $upnString
                $IsCompliant = $false
            }
        }
        else{
            ## Global Admin counts are within the range 2>= GA account <=5 
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

    # Add profile information if MCUP feature is enabled
    if ($EnableMultiCloudProfiles) {
        $result = Add-ProfileInformation -Result $PsObject -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId -ErrorList $ErrorList
        Write-Host "$result"
    }
    
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput   
}



