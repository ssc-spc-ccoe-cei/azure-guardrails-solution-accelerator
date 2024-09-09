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

    # Find how many users there are in the environment
    # list all users in the tenant
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

    
    ## ***************************##
    ## ****** External user ******##
    ## ***************************##
    $extUsers = $users | Where-Object { $_.userPrincipalName -like "*#EXT#*" }
    Write-Output "DEBUG: extUsers count is $($extUsers.Count)"
    Write-Output "DEBUG: extUsers UPNs are $($extUsers.userPrincipalName)"


    # Check if more than 1 user in the tenant
    $userCount = $users.Count
    Write-Output "DEBUG: userCount is $userCount"
    if ( $userCount -gt 1){
        # Find how many user groups there are in the environment
        $urlPath = "/groups"
        try {
            $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
            # portal
            $data = $response.Content
            # # localExecution
            # $data = $response

            if ($null -ne $data -and $null -ne $data.value) {
                $groups = $data.value #| Select-Object userPrincipalName , displayName, givenName, surname, id, mail
            }
        }
        catch {
            $errorMsg = "Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"                
            $ErrorList.Add($errorMsg)
            Write-Error "Error: $errorMsg"
        }
        Write-Error "DEBUG: group count is $($groups.Count)"
    }

    Write-Output "DEBUG: ***************************************************************"

    
    # Condition: 
    if($userCount -le 1) {
        $commentsArray = "Compliant"
        $IsCompliant = $true
    }
    # Condition: 
    else {
        
        $commentsArray = "There are more than one user in the tenant"
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