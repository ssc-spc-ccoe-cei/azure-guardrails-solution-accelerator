function Check-MonitorAccountCreation {
  param (
    [string] $token, 
    [string] $DepartmentNumber,
    [string] $ControlName, 
    [string] $ItemName, 
    [string] $WorkSpaceID, 
    [string] $workspaceKey, 
    [string] $LogType,
    [string] $itsgcode,
    [hashtable] $msgTable,
    [Parameter(Mandatory=$true)]
    [string]
    $ReportTime)

  [bool] $IsCompliant = $false
  [string] $Comments = $null

  [string] $MonitoringAccount = "SSC-CBS-Reporting@" + $DepartmentNumber + "gc.onmicrosoft.com"

  $apiUrl = $("https://graph.microsoft.com/beta/users/" + $MonitoringAccount)

  try {
    $Data = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)" } -Uri $apiUrl
    $IsCompliant = $true
    $MitigationCommands = "N/A"
  }
  catch {
    $StatusCode = $_.Exception.Response.StatusCode.value__ 
    $Comments = $msgTable.checkUserExistsError -f $StatusCode
    $MitigationCommands = $msgTable.checkUserExists

    Add-LogEntry 'Error' "Failed to call Microsoft Graph REST API at URL '$apiURL'; returned error message: $_" -workspaceGuid $WorkSpaceID -workspaceKey $WorkSpaceKey
    Write-Error "Error: Failed to call Microsoft Graph REST API at URL '$apiURL'; returned error message: $_"
  }
       
  $Results = [pscustomobject]@{
    ControlName = $ControlName  
    ComplianceStatus   = $IsCompliant
    ItemName    = $ItemName
    itsgcode    = $itsgcode
    Comments    = $Comments
    ReportTime  = $ReportTime
    MitigationCommands = $MitigationCommands
  }
       
  $Results_Jason = ConvertTo-json -inputObject $Results

  Send-OMSAPIIngestionFile  -customerId $WorkSpaceID -sharedkey $workspaceKey `
    -body $Results_Jason -logType $LogType -TimeStampField Get-Date  
      
}
