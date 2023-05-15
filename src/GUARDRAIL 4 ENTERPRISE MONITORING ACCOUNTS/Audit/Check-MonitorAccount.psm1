function Check-MonitorAccountCreation {
  param (
    [string] $DepartmentNumber,
    [string] $ControlName, 
    [string] $ItemName, 
    [string] $itsgcode,
    [hashtable] $msgTable,
    [Parameter(Mandatory=$true)]
    [string]
    $ReportTime)

  [bool] $IsCompliant = $false
  [string] $Comments = $null
  [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList

  [string] $MonitoringAccount = "SSC-CBS-Reporting@" + $DepartmentNumber + "gc.onmicrosoft.com"

  $urlPath = $("/users/" + $MonitoringAccount)

  try {
    $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
  }
  catch {
    $Comments = $msgTable.checkUserExistsError -f $response.StatusCode
    $MitigationCommands = $msgTable.checkUserExists

    $Errorlist.Add("Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_")
    Write-Error "Error: Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"
  }

  If ($response.StatusCode -eq 200) {
    # the monitoring user was found
    $IsCompliant = $true
    $Comments = $msgTable.checkUserExistsSuccess
    $MitigationCommands = "N/A"
  }
  ElseIf ($response.StatusCode -eq 404) {
    # the monitoring user was not found
    $Comments = $msgTable.checkUserExistsError -f $response.statusCode
    $MitigationCommands = $msgTable.checkUserExists
  }
  Else {
    $Comments = $msgTable.checkUserExistsError -f $response.statusCode
    $MitigationCommands = $msgTable.checkUserExists

    $ErrorList.Add("An unhandled status code '$($response.StatusCode)' was returned when calling URI '$urlPath' to find the Monitoring Account")
    Write-Error "Error: An unhandled status code '$($response.StatusCode)' was returned when calling URI '$urlPath' to find the Monitoring Account"
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

  $moduleOutput= [PSCustomObject]@{ 
    ComplianceResults = $Results 
    Errors=$ErrorList
    AdditionalResults = $AdditionalResults
  }
  return $moduleOutput  
}

