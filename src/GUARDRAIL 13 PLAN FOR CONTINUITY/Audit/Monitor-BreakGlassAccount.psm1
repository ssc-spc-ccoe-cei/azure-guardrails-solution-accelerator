<#
.SYNOPSIS
   
The solution will ensures that Break Glass accounts remain active and secure by monitoring the last login date.
.DESCRIPTION
The solution will ensures that Break Glass accounts remain active and secure by monitoring the last login date.
.PARAMETER Name
        token : auth token 
        ControlName :-  GUARDRAIL 13 PLAN FOR CONTINUITY
        FirstBreakGlassUPN: UPN for the first Break Glass account 
        SecondBreakGlassUPN: UPN for the second Break Glass account
        ItemName, 
        WorkSpaceID : Workspace ID to ingest the logs 
        WorkSpaceKey: Workspace Key for the Workdspace 
        LogType: GuardrailsCompliance, it will show in log Analytics search as GuardrailsCompliance_CL
#>
function Test-BreakGlassAccounts {
   
  param (
    [string] $FirstBreakGlassUPN, 
    [string] $SecondBreakGlassUPN,
    [hashtable] $msgTable,
    [string] $itsgcode,
    [string] $ControlName, 
    [string] $ItemName,
    [Parameter(Mandatory=$true)]
    [string]
    $ReportTime,
    [string] 
    $CloudUsageProfiles = "3",  # Passed as a string
    [string] $ModuleProfiles,  # Passed as a string
    [switch] $EnableMultiCloudProfiles # New feature flag, default to false    
  )

  [bool] $IsCompliant = $false
  [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList

  [String] $FirstBreakGlassUPNUrl = $("/users/" + $FirstBreakGlassUPN + "?$" + "select=userPrincipalName,id,userType")
  [String] $SecondBreakGlassUPNUrl = $("/users/" + $SecondBreakGlassUPN + "?$" + "select=userPrincipalName,id,userType")

  # Validate two BG accounts exist
  if($FirstBreakGlassUPN -eq "" -or $SecondBreakGlassUPN -eq ""){
    $IsCompliant = $false
    $PsObject = [PSCustomObject]@{
      ComplianceStatus = $IsCompliant
      ControlName      = $ControlName
      ItemName         = $ItemName
      Comments         = $msgTable.isNotCompliant + " " + $msgTable.bgAccountNotExist
      ReportTime       = $ReportTime
      itsgcode = $itsgcode
    }
  }
  elseif(($FirstBreakGlassUPN -ne "" -or $SecondBreakGlassUPN -ne "") -and $FirstBreakGlassUPN -eq $SecondBreakGlassUPN){
    $IsCompliant = $false
    $PsObject = [PSCustomObject]@{
      ComplianceStatus = $IsCompliant
      ControlName      = $ControlName
      ItemName         = $ItemName
      Comments         = $msgTable.isNotCompliant + " " + $msgTable.bgAccountNotExist
      ReportTime       = $ReportTime
      itsgcode = $itsgcode
    }
  }
  else{
    # Validate listed BG accounts as members
    $FirstBreakGlassAcct = [PSCustomObject]@{
      UserPrincipalName  = $FirstBreakGlassUPN
      apiUrl             = $FirstBreakGlassUPNUrl
      ComplianceStatus   = $false
    }
    $SecondBreakGlassAcct = [PSCustomObject]@{
      UserPrincipalName   = $SecondBreakGlassUPN
      apiUrl              = $SecondBreakGlassUPNUrl
      ComplianceStatus    = $false
    }
      
    # get 1st break glass account
    try {
      $urlPath = $FirstBreakGlassAcct.apiUrl
      $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop

      $data = $response.Content
      
      if ($data.userType -eq "Member") {
        $FirstBreakGlassAcct.ComplianceStatus = $true
      } 
    }
    catch {
      $ErrorList.Add("Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_")
      Write-Warning "Error: Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"
    }

    # get 2nd break glass account
    try {
      $urlPath = $SecondBreakGlassAcct.apiURL
      $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop

      $data = $response.Content

      if ($data.userType -eq "Member") {
        $SecondBreakGlassAcct.ComplianceStatus = $true
      } 
    }
    catch {
      $ErrorList.Add("Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_")
      Write-Warning "Error: Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"
    }

    # compliance status
    $IsCompliant = $FirstBreakGlassAcct.ComplianceStatus -and $SecondBreakGlassAcct.ComplianceStatus
    # if not compliant
    if(-not $IsCompliant){
      $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        ItemName         = $ItemName
        Comments         = $msgTable.isNotCompliant + " " + $msgTable.bgAccountNotExist
        ReportTime       = $ReportTime
        itsgcode = $itsgcode
      }
    }
    else{
      $IsSigninCompliant = $false
      $oneYear = (Get-Date).AddYears(-1)

      # Validate BG account Sign-in activity
      [String] $FirstBreakGlassUPNSigninUrl = "/users/auditLogs/signIns?$filter=userPrincipalName eq '$FirstBreakGlassUPN'"
      [String] $SecondBreakGlassUPNSigninUrl = "/users/auditLogs/signIns?$filter=userPrincipalName eq '$SecondBreakGlassUPN'"

      # check 1st break glass account signin
      try {
        $urlPath = $FirstBreakGlassUPNSigninUrl.apiUrl
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
        
        $data = $response.Content.value | ForEach-Object{
          $_ | Select-Object id, userDisplayName, userPrincipalName, createdDateTime,
          @{Name='signInDate'; Expression={($_.createdDateTime).ToString("yyyy-MM-dd")}},
          @{Name='IsWithinLastYear'; Expression={$createdDate -ge $oneYearAgo}}
        }
      }
      catch {
        $ErrorList.Add("Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_")
        Write-Warning "Error: Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"
      }

      # check 2nd break glass account signin
      try {
        $urlPath = $SecondBreakGlassUPNSigninUrl.apiUrl
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
  
        
        $data = $response.Content.value | ForEach-Object{
          $_ | Select-Object id, userDisplayName, userPrincipalName, createdDateTime,
          @{Name='signInDate'; Expression={($_.createdDateTime).ToString("yyyy-MM-dd")}},
          @{Name='IsWithinLastYear'; Expression={$createdDate -ge $oneYearAgo}}
        } 
      }
      catch {
        $ErrorList.Add("Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_")
        Write-Warning "Error: Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"
      }
    
  
      $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        ItemName         = $ItemName
        Comments         = $msgTable.bgAccountsCompliance -f $FirstBreakGlassAcct.ComplianceStatus, $SecondBreakGlassAcct.ComplianceStatus
        ReportTime       = $ReportTime
        itsgcode = $itsgcode
      }
    }
    
  }
  

  if ($EnableMultiCloudProfiles) {        
    $result = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
    if ($result -eq 0) {
        Write-Output "No matching profile found or error occurred."
        $PsObject.ComplianceStatus = "Not Applicable"
    } elseif ($result -is [int] -and $result -gt 0) {
        Write-Output "Valid profile returned: $result"
        $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $result
    } else {
        Write-Error "Unexpected result from Get-EvaluationProfile: $result"
        $ErrorList.Add("Unexpected result from Get-EvaluationProfile: $result")
    }
  }

  $moduleOutput= [PSCustomObject]@{ 
    ComplianceResults = $PsObject
    Errors=$ErrorList
    AdditionalResults = $AdditionalResults
  }
  return $moduleOutput   
}    


