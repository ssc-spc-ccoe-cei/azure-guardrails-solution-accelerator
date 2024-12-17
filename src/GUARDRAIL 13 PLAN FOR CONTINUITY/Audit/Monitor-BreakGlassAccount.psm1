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
    [string] $ControlName, 
    [string] $ItemName,
    [string] $FirstBreakGlassUPN, 
    [string] $SecondBreakGlassUPN,
    [Parameter(Mandatory=$true)]
    [string] $LAWResourceId,
    [hashtable] $msgTable,
    [string] $itsgcode,
    [Parameter(Mandatory=$true)]
    [string] $ReportTime,
    [string] $CloudUsageProfiles = "3",  # Passed as a string
    [string] $ModuleProfiles,  # Passed as a string
    [switch] $EnableMultiCloudProfiles # New feature flag, default to false    
  )

  [bool] $IsCompliant = $false
  [bool] $IsSigninCompliant = $false
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
      # # Validate BG account Sign-in activity

      # Parse LAW Resource ID
      $lawParts = $LAWResourceId -split '/'
      $subscriptionId = $lawParts[2]
      $resourceGroupName = $lawParts[4] 
      $workspaceId = $lawParts[8] 

      # get context
      try{
        Select-AzSubscription -Subscription $subscriptionId -ErrorAction Stop | Out-Null
      }
      catch {
          $ErrorList.Add("Failed to execute the 'Select-AzSubscription' command with subscription ID '$($subscription)'--`
              ensure you have permissions to the subscription, the ID is correct, and that it exists in this tenant; returned `
              error message: $_")
          throw "Error: Failed to execute the 'Select-AzSubscription' command with subscription ID '$($subscription)'--ensure `
              you have permissions to the subscription, the ID is correct, and that it exists in this tenant; returned error message: $_"
      }

      # Validate singnIns log is enabled
      try {
        # logs to check
        $SignInLogs = @('SignInLogs')

        #Retrieve diagnostic settings to check for logs
        $diagnosticSettings = get-AADDiagnosticSettings
        $matchingSetting = $diagnosticSettings | Where-Object { $_.properties.workspaceId -eq $LAWResourceId } | Select-Object -First 1

        if($matchingSetting){
            $enabledLogs = $matchingSetting.properties.logs | Where-Object { $_.enabled -eq $true } | Select-Object -ExpandProperty category
            $missingSignInLogs = $SignInLogs | Where-Object { $_ -notin $enabledLogs }
        }
        else{
            $missingSignInLogs = $SignInLogs
        }

        # Check missing logs for SignInLogs
        if ($missingSignInLogs.Count -gt 0) {
            $IsCompliant = $false
            $Comments += $msgTable.signInlogsNotCollected + " Missing logs: $($missingSignInLogs -join ', ')"
        }
        
      }
      catch {
          if ($_.Exception.Message -like "*ResourceNotFound*") {
              $IsCompliant = $false
              $Comments += $msgTable.nonCompliantLaw -f $lawName
              $ErrorList += "Log Analytics Workspace not found: $_"
          }
          else {
              $IsCompliant = $false
              $ErrorList += "Error accessing Log Analytics Workspace: $_"
          }
      }

      # Retrieve the log data and check the data retention period for sign in
      $kqlQuery = "SigninLogs
      | where TimeGenerated > ago(365d)
      | order by TimeGenerated desc"

      try{
        $workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -Name $workspaceId
        $queryResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspace.CustomerId -Query $kqlQuery

        $BGdata = $queryResults.Results | Where-Object {$_.UserPrincipalName -eq $FirstBreakGlassUPN -or $_.UserPrincipalName -eq $SecondBreakGlassUPN}
        
        # check break glass account signin
        $dataMostRecentSignInFirstBG = $BGdata | Where-Object {$_.UserPrincipalName -eq $FirstBreakGlassUPN} | Sort-Object TimeGenerated -Descending
        $dataMostRecentSignInSecondBG = $BGdata | Where-Object {$_.UserPrincipalName -eq $SecondBreakGlassUPN} | Sort-Object createdDateTime -Descending
      
        if ($null -ne $dataMostRecentSignInFirstBG -and $null -ne $dataMostRecentSignInSecondBG ){
          $IsSigninCompliant = $true
        }

      }
      catch {
        if ($null -eq $workspace) {
          $IsCompliant = $false
          $Comments += "Workspace not found in the specified resource group"
          $ErrorList += "Workspace not found in the specified resource group: $_"
        }
        if($_.Exception.Message -like "*ResourceNotFound*"){

        }
        else{
          # Handle errors and exceptions
          $IsCompliant = $false
          Write-Host "Error occurred retrieving the sign-in log data: $_"
        }

      }

      if($IsSigninCompliant){
        $PsObject = [PSCustomObject]@{
          ComplianceStatus = $IsCompliant
          ControlName      = $ControlName
          ItemName         = $ItemName
          Comments         = $msgTable.isCompliant + " " + $msgTable.bgAccountLoginValid
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
    Errors            = $ErrorList
    AdditionalResults = $AdditionalResults
  }
  return $moduleOutput   
}    


