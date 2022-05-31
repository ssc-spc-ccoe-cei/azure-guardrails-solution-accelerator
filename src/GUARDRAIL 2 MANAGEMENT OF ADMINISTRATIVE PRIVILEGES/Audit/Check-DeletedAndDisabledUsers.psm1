
function Check-ADDeletedUsers  {
    Param (
        [string] $Token,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime
        )

    [psCustomOBject] $deletedUsersArray = New-Object System.Collections.ArrayList
    [psCustomOBject] $guestUsersArray = New-Object System.Collections.ArrayList
    [bool] $IsCompliant= $false
    [string] $Comment1= "This user account has been deleted; it has not yet been DELETED PERMANENTLY from Azure Active Directory"
    [string] $Comment2= "This is a GUEST account and needs to be removed from your Azure Active Directory"

    $apiUrl= "https://graph.microsoft.com/beta/directory/deleteditems/microsoft.graph.user"
    $Data = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)"} -Uri $apiUrl
    $AllUsers = $Data.value
      
      forEach ($User in $AllUsers) {
          $Customuser = [pscustomobject]@{
          DisplayName = $User.displayName
          Mail = $User.mail
          DeletedDate = $User.deletedDateTime
          Comments = $Comment1
          ReportTime = $ReportTime
          }
        $deletedUsersArray.add($Customuser)
        }


    $JSONDeletedUsers = ConvertTo-Json -inputObject $deletedUsersArray

    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
   -sharedkey $workspaceKey `
   -body $JSONDeletedUsers `
   -logType $LogType `
   -TimeStampField Get-Date 
 
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
             ReportTime = $ReportTime
        }
        
        $guestUsersArray.add($Customuser)
        }     
    }      

    $JSONGuestUsers = ConvertTo-Json -inputObject $guestUsersArray

    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
   -sharedkey $workspaceKey `
   -body $JSONGuestUsers `
   -logType $LogType `
   -TimeStampField Get-Date 

}
