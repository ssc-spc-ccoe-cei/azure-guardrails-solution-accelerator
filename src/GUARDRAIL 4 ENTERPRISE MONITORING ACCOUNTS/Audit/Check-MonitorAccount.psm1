function Check-MonitorAccountCreation {
  param (
    [string] $token, 
    [string] $DepartmentNumner,
    [string] $ControlName, 
    [string] $ItemName, 
    [string] $WorkSpaceID, 
    [string] $workspaceKey, 
    [string] $LogType,
    [Parameter(Mandatory=$true)]
    [string]
    $ReportTime)

  [bool] $IsCompliant = $false
  [string] $Comments = $null

  [string] $MonitoringAccount = "SSC-CBS-Reporting@" + $DepartmentNumner + "gc.onmicrosoft.com"

  $apiUrl = $("https://graph.microsoft.com/beta/users/" + $MonitoringAccount)

  try {
    $Data = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)" } -Uri $apiUrl
    $IsCompliant = $true

  }
  catch {
    $StatusCode = $_.Exception.Response.StatusCode.value__ 
    $Comments = "API call returns Error " + $StatusCode + " Please Check if the user exists"
  }
       
  $Results = [pscustomobject]@{
    ControlName = $ControlName  
    ComplianceStatus   = $IsCompliant
    ItemName    = $ItemName
    Comments    = $Comments
    ReportTime  = $ReportTime
  }
       
  $Results_Jason = ConvertTo-json -inputObject $Results

  Send-OMSAPIIngestionFile  -customerId $WorkSpaceID -sharedkey $workspaceKey `
    -body $Results_Jason -logType $LogType -TimeStampField Get-Date  
      
}
