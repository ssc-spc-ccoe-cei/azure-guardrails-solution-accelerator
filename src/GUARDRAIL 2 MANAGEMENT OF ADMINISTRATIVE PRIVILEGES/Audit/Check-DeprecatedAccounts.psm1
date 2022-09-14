function Check-DeprecatedUsers {
    Param (
        
        [string] $token, 
        [string] $ControlName, 
        [string] $ItemName, 
        [string] $WorkSpaceID, 
        [string] $workspaceKey, 
        [string] $LogType,
        [string] $itsgcode,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime
    )
    [bool] $IsCompliant = $false
    [string] $UComments = $msgTable.noncompliantUsers
    [string] $CComments = $msgTable.compliantComment

    [PSCustomObject] $DeprecatedUsers = New-Object System.Collections.ArrayList

    # A Deprecated account is an account that is disabled and not synchronized to AD
    $DeprecatedUsers = Get-AzADUser -Filter "accountEnabled eq false" | Where-Object {$null -eq $_.onPremisesSyncEnabled}

    if ($DeprecatedUsers.count -gt 0) {
        foreach ($user in $DeprecatedUsers) {
            $UComments =  $UComments + $user.userPrincipalName + "  "
        }
        $Comments = $msgTable.noncompliantComment -f $DeprecatedUsers.count +" "+ $UComments
        $MitigationCommands = $msgTable.mitigationCommands 
    }
    else {
        $Comments = $CComments
        $IsCompliant = $true
        $MitigationCommands = "N/A"
    }

    $DeprecatedUserStatus = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        Comments         = $Comments
        ItemName         = $ItemName
        MitigationCommands = $MitigationCommands
        ReportTime = $ReportTime
        itsgcode = $itsgcode
    }

    $JasonDeprecatedUserStatus = ConvertTo-Json -inputObject $DeprecatedUserStatus
        
    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID -sharedkey $workspaceKey `
        -body $JasonDeprecatedUserStatus   -logType $LogType -TimeStampField Get-Date  
}
       
