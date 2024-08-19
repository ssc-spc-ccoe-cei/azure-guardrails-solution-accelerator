
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
        $data = $response.Content
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
    # Exclude the breakglass account UPNs from the list
    if ($allUserUPNs -contains $FirstBreakGlassUPN){
        $allUserUPNs = $allUserUPNs | Where-Object { $_ -ne $FirstBreakGlassUPN }
    }
    if ($allUserUPNs -contains $SecondBreakGlassUPN){
        $allUserUPNs = $allUserUPNs | Where-Object { $_ -ne $SecondBreakGlassUPN }

    }

    $mfaCounter = 0
    $userUPNsMFA = @()

    ForEach ($userAccount in $allUserUPNs) {
        $urlPath = '/users/' + $userAccount + '/authentication/methods'
        
        # create hidden format UPN
        $hiddenUPN = Hide-Email -email $userAccount
        
        try {
            $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop

        }
        catch {
            $errorMsg = "Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"                
            $ErrorList.Add($errorMsg)
            Write-Error "Error: $errorMsg"
        }

        # # To check if MFA is setup for a user, we're checking various authentication methods:
        # # 1. #microsoft.graph.microsoftAuthenticatorAuthenticationMethod
        # # 2. #microsoft.graph.phoneAuthenticationMethod
        # # 3. #microsoft.graph.passwordAuthenticationMethod - not considered for MFA
        # # 4. #microsoft.graph.emailAuthenticationMethod - not considered for MFA
        # # 5. #microsoft.graph.fido2AuthenticationMethod
        # # 6. #microsoft.graph.softwareOathAuthenticationMethod
        # # 7. #microsoft.graph.temporaryAccessPassAuthenticationMethod
        # # 8. #microsoft.graph.windowsHelloForBusinessAuthenticationMethod

        if ($null -ne $response) {
            $data = $response.Content
            if ($null -ne $data -and $null -ne $data.value) {
                $authenticationmethods = $data.value
                
                $authFound = $false
                foreach ($authmeth in $authenticationmethods) {                        
                    if (($($authmeth.'@odata.type') -eq "#microsoft.graph.phoneAuthenticationMethod") -or `
                        ($($authmeth.'@odata.type') -eq "#microsoft.graph.microsoftAuthenticatorAuthenticationMethod") -or`
                        ($($authmeth.'@odata.type') -eq "#microsoft.graph.fido2AuthenticationMethod" ) -or`
                        ($($authmeth.'@odata.type') -eq "#microsoft.graph.temporaryAccessPassAuthenticationMethod" ) -or`
                        ($($authmeth.'@odata.type') -eq "#microsoft.graph.windowsHelloForBusinessAuthenticationMethod" ) -or`
                        ($($authmeth.'@odata.type') -eq "#microsoft.graph.softwareOathAuthenticationMethod" ) ) {
                            
                            #need to keep track of user account mfa in a counter and compare it with the total user count
                            $mfaCounter += 1
                            $authFound = $true
                            # MFA auth method is true - so we move to the next UPN 
                            break
                    }
                }
                if($authFound){
                    # This message is being used for debugging
                    Write-Host "Auth method found for $userAccount"
                }
                else{
                    # This message is being used for debugging
                    Write-Host "$userAccount does not have MFA enabled"

                    # Create an instance of inner list object
                    $userUPNtemplate = [PSCustomObject]@{
                        UPN  = $userAccount
                        MFAStatus   = $false
                        MFAComments = $hiddenUPN 
                    }
                    # Add the list to user accounts MFA list
                    $userUPNsMFA += $userUPNtemplate
                }
            }
            else {
                $errorMsg = "No authentication methods data found for $userAccount"                
                $ErrorList.Add($errorMsg)
                # Write-Error "Error: $errorMsg"    
            }
        }
        else {
            $errorMsg = "Failed to get response from Graph API for $userAccount"                
            $ErrorList.Add($errorMsg)
            Write-Error "Error: $errorMsg"    
        }    
    }

    # Condition: all users are MFA enabled
    if($mfaCounter -eq $allUserUPNs.Count) {
        $commentsArray += ' ' + $msgTable.allUserHaveMFA
        $IsCompliant = $true
    }
    # Condition: Not all user UPNs are MFA enabled or MFA is not configured properly
    else {
        # This will be used for debugging
        if($userUPNsMFA.Count -eq 0){
            Write-Host "Something is wrong as userUPNsMFA Count equals 0. This output should only execute if there is an error populating userUPNsMFA"
        }
        else {
            $upnString = ($userUPNsMFA | ForEach-Object { $_.UPN }) -join ', '
            $commentsArray += ' ' + $msgTable.userMisconfiguredMFA -f $upnString
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

