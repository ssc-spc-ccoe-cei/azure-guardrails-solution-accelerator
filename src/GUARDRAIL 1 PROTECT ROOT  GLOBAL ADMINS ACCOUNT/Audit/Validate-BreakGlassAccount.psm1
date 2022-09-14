<#
.SYNOPSIS
   
The solution will verify the existence of the two Break Glass accounts that you have entered in the config.json during the setup process.Once the solution detects both accounts the check mark status will be changed from (❌) to (✔️).
.DESCRIPTION
The solution will verify the existence of the two Break Glass accounts that you have entered in the config.json during the setup process.Once the solution detects both accounts the check mark status will be changed from (❌) to (✔️).
.PARAMETER Name
        token : auth token 
        ControlName :-  GUARDRAIL 1 PROTECT ROOT  GLOBAL ADMINS ACCOUNT
        FirstBreakGlassUPN: UPN for the first Break Glass account 
        SecondBreakGlassUPN: UPN for the second Break Glass account
        ItemName, 
        WorkSpaceID : Workspace ID to ingest the logs 
        WorkSpaceKey: Workspace Key for the Workdspace 
        LogType: GuardrailsCompliance, it will show in log Analytics search as GuardrailsCompliance_CL
#>
function Get-BreakGlassAccounts {
   
  param (
    [string] $FirstBreakGlassUPN, 
    [string] $SecondBreakGlassUPN,
    [string] $token, 
    [hashtable] $msgTable,
    [string] $LogType,
    [string] $itsgcode,
    [string] $WorkSpaceID,
    [string] $WorkspaceKey, 
    [string] $ControlName, 
    [string] $ItemName,
    [Parameter(Mandatory=$true)]
    [string]
    $ReportTime
  )
  [bool] $FirstBGAcctExist = $false
  [bool] $SecondBGAcctExist = $false    
  [bool] $IsCompliant = $false

  [String] $FirstBreakGlassUPNUrl = $("https://graph.microsoft.com/beta/users/" + $FirstBreakGlassUPN)
  [String] $SecondBreakGlassUPNUrl = $("https://graph.microsoft.com/beta/users/" + $SecondBreakGlassUPN)

  $FirstBreakGlassAcct = [PSCustomObject]@{
    UserPrincipalName  = $FirstBreakGlassUPN
    apiUrl             = $FirstBreakGlassUPNUrl
    First_Name         = $null
    Last_Name          = $null
    Mobile_PhoneNumber = $null
    Email_address      = $null
    ComplianceStatus   = $false
  }
  $SecondBreakGlassAcct = [PSCustomObject]@{
    UserPrincipalName  = $SecondBreakGlassUPN
    apiUrl             = $SecondBreakGlassUPNUrl
    First_Name         = $null
    Last_Name          = $null
    Mobile_PhoneNumber = $null
    Email_address      = $null
    ComplianceStatus   = $false
  }
  
  # get 1st break glass account
  try {
    $apiURL = $FirstBreakGlassAcct.apiUrl
    $Data = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)" } -Uri $apiUrl -Method Get
   
    if ($Data.userType -eq "Member") {
      $FirstBGAcctExist = $true
    } 
  }
  catch {
    Add-LogEntry 'Error' "Failed to call Microsoft Graph REST API at URL '$apiURL'; returned error message: $_" -workspaceGuid $WorkSpaceID -workspaceKey $WorkSpaceKey
    Write-Error "Error: Failed to call Microsoft Graph REST API at URL '$apiURL'; returned error message: $_"
  }

  # get 2nd break glass account
  try {
    $apiURL = $SecondBreakGlassAcct.apiURL
    $Data = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)" } -Uri $apiUrl -Method Get
    
    if ($Data.userType -eq "Member") {
      $SecondBGAcctExist = $true
    } 
  }
  catch {
    Add-LogEntry 'Error' "Failed to call Microsoft Graph REST API at URL '$apiURL'; returned error message: $_" -workspaceGuid $WorkSpaceID -workspaceKey $WorkSpaceKey
    Write-Error "Error: Failed to call Microsoft Graph REST API at URL '$apiURL'; returned error message: $_"
  }
  $IsCompliant = $FirstBGAcctExist -and $SecondBGAcctExist

  $PsObject = [PSCustomObject]@{
    ComplianceStatus = $IsCompliant
    ControlName      = $ControlName
    ItemName         = $ItemName
    Comments          = $msgTable.bgAccountsCompliance -f $FirstBreakGlassUPN, $FirstBGAcctExist, $SecondBreakGlassUPN, $SecondBGAcctExist
    ReportTime      = $ReportTime
    itsgcode = $itsgcode
  }

  $JsonObject = convertTo-Json -inputObject $PsObject 

  Send-OMSAPIIngestionFile -customerId $WorkSpaceID `
    -sharedkey $workspaceKey `
    -body $JsonObject `
    -logType $LogType `
    -TimeStampField Get-Date 
}    

