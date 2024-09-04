
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

    # Get the list of GA users
    $urlPath = "/directoryRoles"
    try {
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
        # portal
        $data = $response.Content
        # # localExecution
        # $data = $response

        if ($null -ne $data -and $null -ne $data.value) {
            $rolesResponse  = $data.value
            # # Find the Global Administrator role ID
            # $globalAdminRoleId = ($roles.value | Where-Object { $_.displayName -eq "Global Administrator" }).id
        }
    }
    catch {
        $errorMsg = "Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"                
        $ErrorList.Add($errorMsg)
        Write-Error "Error: $errorMsg"
    }

    # # Filter the Global Administrator role ID
    # $globalAdminRole = $rolesResponse | Where-Object { $_.displayName -eq "Global Administrator" }

    # Get directory roles for each user and filter the global admin users
    $globalAdminUserAccounts = @()
    $roleAssignments = @()

    foreach ($role in $rolesResponse) {
        $roleId = $role.id
        $roleName = $role.displayName
        if ($roleName -eq "Global Administrator"){
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
                    $membersResponse  = $data.value
                }
            }
            catch {
                $errorMsg = "Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"                
                $ErrorList.Add($errorMsg)
                Write-Error "Error: $errorMsg"
            }
            # Get member users UPNs
            $memberUserList = $membersResponse 
            # Exclude the breakglass account UPNs from the list
            if ($memberUserList.userPrincipalName -contains $FirstBreakGlassUPN){
                $memberUserList = $memberUserList | Where-Object { $_.userPrincipalName -ne $FirstBreakGlassUPN }
            }
            if ($memberUserList.userPrincipalName -contains $SecondBreakGlassUPN){
                $memberUserList = $memberUserList | Where-Object { $_.userPrincipalName -ne $SecondBreakGlassUPN }

            }

            foreach ($member in $memberUserList) {
                $roleAssignments = [PSCustomObject]@{
                    roleId              = $roleId
                    roleName            = $roleName
                    userId              = $member.id
                    displayName         = $member.displayName
                    mail                = $member.mail
                    userPrincipalName   = $member.userPrincipalName
                }
                $globalAdminUserAccounts +=  $roleAssignments
            }
        } else {
            Write-Host "Skipping the role name is $roleName"

        }
        
    }

    $userValidMFACounter = @()

    ## **********************************************##
    ## ****All Global Admin Accounts except BG ******##
    ## **********************************************##
    $allGAUserUPNs = $globalAdminUserAccounts.userPrincipalName
    if (($allGAUserUPNs.Count -gt 6) -or ($allGAUserUPNs.Count -lt 2)){
        $commentsArray =  $msgTable.isNotCompliant + ' ' + $msgTable.globalAdminAccntsSurplus
    }
    else{
        ## Global Admin counts are within the range - proceed with MFA check

        ## *****************************************##
        ## ****** Member user as Global Admin ******##
        ## *****************************************##
        $memberUsers = $globalAdminUserAccounts | Where-Object { $_.userPrincipalName -notlike "*#EXT#*" }

        # Get GA member users UPNs
        $memberUsersUPN= $memberUsers | Select-Object userPrincipalName, mail
        Write-Error "memberUsersUPN count is $($memberUsersUPN.Count)"

        if(!$null -eq $memberUsersUPN){
            $result = Get-AllUserAuthInformation -allUserList $memberUsersUPN
            $memberUserUPNsBadMFA = $result.userUPNsBadMFA
            if( !$null -eq $result.ErrorList){
                $ErrorList =  $ErrorList.Add($result.ErrorList)
            }
            $userValidMFACounter = $result.userValidMFACounter
        }
        

        ## *******************************************##
        ## ****** External user as Global Admin ******##
        ## *******************************************##
        $extUsers = $globalAdminUserAccounts | Where-Object { $_.userPrincipalName -like "*#EXT#*" }
        Write-Error "extUsers count is $($extUsers.Count)"
        if(!$null -eq $extUsers){
             # Get external users UPNs and emails
            $extUsersUPN = $extUsers | Select-Object userPrincipalName, mail
            $result2 = Get-AllUserAuthInformation -allUserList $extUsersUPN
            $extUserUPNsBadMFA = $result2.userUPNsBadMFA
            if( !$null -eq $result2.ErrorList){
                $ErrorList =  $ErrorList.Add($result2.ErrorList)
            }
            
            # combined list
            $userValidMFACounter = $userValidMFACounter + $result2.userValidMFACounter
        }

        Write-Error "userValidMFACounter count is $userValidMFACounter"
        Write-Error "allGAUserUPNs count is $($allGAUserUPNs.Count)"

        if(!$null -eq $extUserUPNsBadMFA -and !$null -eq $memberUserUPNsBadMFA){
            $userUPNsBadMFA =  $memberUserUPNsBadMFA +  $extUserUPNsBadMFA
        }elseif($null -eq $extUserUPNsBadMFA){
            $userUPNsBadMFA =  $memberUserUPNsBadMFA 
        }elseif($null -eq $memberUserUPNsBadMFA){
            $userUPNsBadMFA =  $extUserUPNsBadMFA
        }

        Write-Error "userUPNsBadMFA count is $($userUPNsBadMFA.Count)"
        Write-Error "userUPNsBadMFA $($userUPNsBadMFA.userPrincipalName) "
       
        # Condition: all users are MFA enabled
        if($userValidMFACounter -eq $allGAUserUPNs.Count) {
            $commentsArray += ' ' + $msgTable.allUserHaveMFA
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
                $commentsArray += ' ' + $msgTable.userMisconfiguredMFA -f $upnString
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



