function Check-ADDeletedUsers {
    Param (
        
        [string] $token, 
        [string] $ControlName, 
        [string] $ItemName, 
        [string] $WorkSpaceID, 
        [string] $workspaceKey, 
        [string] $LogType,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime
    )
    [bool] $IsCompliant = $false
    [string] $UComments = "The following Users are:- "
    [string] $CComments = "Didnt find any unsynced deprecated users"


    [PSCustomObject] $AllUsers = New-Object System.Collections.ArrayList
    [PSCustomObject] $DeprecatedUsers = New-Object System.Collections.ArrayList
    try {
        $apiUrl = "https://graph.microsoft.com/beta/users"

        $Users = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)" } -Uri $apiUrl -Method Get
        foreach ($user in $Users.value) {
            [void]  $AllUsers.Add($user )
        }
        $NextLink = $users.'@odata.nextLink'
        While ($Null -ne $NextLink) {
            $Users = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)" } -Uri $NextLink 
            foreach ($user in $Users.value) {
                [void]  $AllUsers.Add($user )
            }
            $NextLink = $users.'@odata.nextLink'
        }
    }
    catch { 
        $DepracteUserStatus = [PSCustomObject]@{
            ComplianceStatus = $IsCompliant
            ControlName      = $ControlName
            Comments         = "API Error"
            ItemName         = $ItemName
            ReportTime = $ReportTime        
        }
        $JasonDepracteUserStatus = ConvertTo-Json -inputObject $DepracteUserStatus
        
        Send-OMSAPIIngestionFile  -customerId $WorkSpaceID -sharedkey $workspaceKey `
            -body $JasonDepracteUserStatus   -logType $LogType -TimeStampField Get-Date  
    }

    if ($AllUsers.count -gt 0) {
        foreach ($user in $AllUsers) {
            if (!($user.accountEnabled) -and ($null -eq $user.onPremisesSyncEnabled)) {
                [void] $DeprecatedUsers.add($user)
                $UComments =  $UComments + $user.userPrincipalName + "  "
            }
        }
        $Comments = "Total Number of users  " + $DeprecatedUsers.count +" "+ $UComments 
    }
    else {
        $Comments = $CComments
        $IsCompliant = $true
    }

    $DepracteUserStatus = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        Comments         = $Comments
        ItemName         = $ItemName
        ReportTime = $ReportTime
    }

    $JasonDepracteUserStatus = ConvertTo-Json -inputObject $DepracteUserStatus
        
    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID -sharedkey $workspaceKey `
        -body $JasonDepracteUserStatus   -logType $LogType -TimeStampField Get-Date  
}
       
