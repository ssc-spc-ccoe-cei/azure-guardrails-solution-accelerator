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
    Write-Host "step 1 validate listed BG accounts compliance status:  $IsCompliant"
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
      # Validate BG account Sign-in activity
      $IsSigninCompliant = $false
      $oneYearAgo = (Get-Date).AddYears(-1)

      $urlPath = "/auditLogs/signIns"
      try {
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
        Write-Host "step 2 validate BG account Sign-in $($response.Content.Value.Count)"

        # check 1st break glass account signin
        $firstBGdata = $response.Content.Value | Where-Object {$_.userPrincipalName -eq $FirstBreakGlassUPN}
        $dataMostRecentSignInFirstBG = $firstBGdata | Sort-Object createdDateTime -Descending | Select-Object -First 1
        
        $dataSignInFirstBG = $dataMostRecentSignInFirstBG | Select-Object id, userDisplayName, userPrincipalName, createdDateTime, userId
        $firstBGisWithinLastYear =  $dataSignInFirstBG.createdDateTime -ge $oneYearAgo

        Write-Host "step 2 firstBGisWithinLastYear:  $firstBGisWithinLastYear"
        
        # check 2nd break glass account signin
        $secondBGdata = $response.Content.Value | Where-Object {$_.userPrincipalName -eq $SecondBreakGlassUPN}
        $dataMostRecentSignInSecondBG = $secondBGdata | Sort-Object createdDateTime -Descending | Select-Object -First 1
        
        $dataSignInSecondBG = $dataMostRecentSignInSecondBG | Select-Object id, userDisplayName, userPrincipalName, createdDateTime, userId
        $secondBGisWithinLastYear =  $dataSignInSecondBG.createdDateTime -ge $oneYearAgo
        Write-Host "step 2 secondBGisWithinLastYear:  $secondBGisWithinLastYear"
      }
      catch {
        $ErrorList.Add("Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_")
        Write-Warning "Error: Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"
      }

      $IsSigninCompliant = $firstBGisWithinLastYear -and $secondBGisWithinLastYear
      if($IsSigninCompliant){
        $PsObject = [PSCustomObject]@{
          ComplianceStatus = $IsCompliant
          ControlName      = $ControlName
          ItemName         = $ItemName
          Comments         = $msgTable.isCompliant
          ReportTime       = $ReportTime
          itsgcode = $itsgcode
        }
      }
      else{
        $PsObject = [PSCustomObject]@{
          ComplianceStatus = $IsSigninCompliant
          ControlName      = $ControlName
          ItemName         = $ItemName
          Comments         = $msgTable.isNotCompliant + " " + $msgTable.bgAccountLoginNotValid
          ReportTime       = $ReportTime
          itsgcode = $itsgcode
        }
      }
    }
  }

  # Conditionally add the Profile field based on the feature flag
  if ($EnableMultiCloudProfiles) {
    $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
    if (!$evalResult.ShouldEvaluate) {
        if ($evalResult.Profile -gt 0) {
            $PsObject.ComplianceStatus = "Not Applicable"
            $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
            $PsObject.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
        } else {
            $ErrorList.Add("Error occurred while evaluating profile configuration")
        }
    } else {
        
        $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
    }
  }

  $moduleOutput= [PSCustomObject]@{ 
    ComplianceResults = $PsObject
    Errors=$ErrorList
    AdditionalResults = $AdditionalResults
  }
  return $moduleOutput   
}    


