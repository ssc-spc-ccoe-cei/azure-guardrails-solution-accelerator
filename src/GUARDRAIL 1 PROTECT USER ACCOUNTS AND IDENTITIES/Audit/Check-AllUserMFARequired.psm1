
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
        [string] $SecondBreakGlassUPN
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

    ## *************************##
    ## ****** Member user ******##
    ## *************************##
    $memberUsers = $users | Where-Object { $_.userPrincipalName -notlike "*#EXT#*" }

    # Check all users for MFA
    $allUserUPNs = $users.userPrincipalName

    # Get member users UPNs
    $memberUserList = $memberUsers | Select-Object userPrincipalName, mail
    # Exclude the breakglass account UPNs from the list
    if ($memberUserList.userPrincipalName -contains $FirstBreakGlassUPN){
        $memberUserList = $memberUserList | Where-Object { $_.userPrincipalName -ne $FirstBreakGlassUPN }
    }
    if ($memberUserList.userPrincipalName -contains $SecondBreakGlassUPN){
        $memberUserList = $memberUserList | Where-Object { $_.userPrincipalName -ne $SecondBreakGlassUPN }

    }
    $result = Get-AllUserAuthInformation -allUserList $memberUserList
    $memberUserUPNsBadMFA = $result.userUPNsBadMFA
    if( !$null -eq $result.ErrorList){
        $ErrorList =  $ErrorList.Add($result.ErrorList)
    }
    $userValidMFACounter = $result.userValidMFACounter

    ## ***************************##
    ## ****** External user ******##
    ## ***************************##
    $extUsers = $users | Where-Object { $_.userPrincipalName -like "*#EXT#*" }

    # Get external users UPNs and emails
    $extUserList = $extUsers | Select-Object userPrincipalName, mail
    $result2 = Get-AllUserAuthInformation -allUserList $extUserList
    $extUserUPNsBadMFA = $result2.userUPNsBadMFA
    if( !$null -eq $result2.ErrorList){
        $ErrorList =  $ErrorList.Add($result2.ErrorList)
    }
    # combined list
    $userValidMFACounter = $userValidMFACounter + $result2.userValidMFACounter
    $userUPNsBadMFA =  $memberUserUPNsBadMFA +  $extUserUPNsBadMFA

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
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput   
}

