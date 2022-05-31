
    # PART 2 - Checking for GUEST accounts  
    # Note that this URL only reads from the All-Users (not the deleted accounts) in the directory, 
    # This querly looks for accounts marked as GUEST
    # It does not list GUEST accounts from the list of deleted accounts.
    
    function Check-ExternalUsers  {
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
    
    [string] $Comment2= "This is a GUEST account and needs to be removed from you Azure Active Directory"
    [psCustomOBject] $guestUsersArray = New-Object System.Collections.ArrayList
    [bool] $IsCompliant= $false
    

    $apiUrl= "https://graph.microsoft.com/beta/users/"
    $guestAccountData = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)"} -Uri $apiUrl

    $guestUsers = $guestAccountData.value
    forEach ($User in $guestUsers) {
        if($User.userType -eq "Guest") {

             $Customuser = [pscustomobject]@{
             DisplayName = $User.displayName
             Mail = $User.mail
             Type = $User.userType
             CreatedDate = $User.createdDateTime
             Enabled = $User.accountEnabled
             Comments = $Comment2
             ReportTime = $ReportTime }
            $guestUsersArray.add($Customuser)
        }     
    }      
    # Convert data to JSON format for input in Azure Log Analytics
    $JSONGuestUsers = ConvertTo-Json -inputObject $guestUsersArray
    # Use this line to check $JSON output
   # $JSONGuestUsers > c:\temp\Output\guestUsers.txt
    #$JSONGuestUsers

    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID -sharedkey $workspaceKey `
                            -body $JSONGuestUsers -logType "GR2ExternalUsers" -TimeStampField Get-Date 

    if ($guestUsersArray.Count -eq 0)
        {       
            $IsCompliant= $true
        }
    
        $GuestUserStatus = [PSCustomObject]@{
            ComplianceStatus= $IsCompliant
            ControlName = $ControlName
            Comments= $Comment2
            ItemName= $ItemName
            ReportTime = $ReportTime
        }
        $JasoGuestdUserStatus=   ConvertTo-Json -inputObject $GuestUserStatus

        Send-OMSAPIIngestionFile  -customerId $WorkSpaceID -sharedkey $workspaceKey -body $JasoGuestdUserStatus `
                                    -logType $LogType -TimeStampField Get-Date 

    }
