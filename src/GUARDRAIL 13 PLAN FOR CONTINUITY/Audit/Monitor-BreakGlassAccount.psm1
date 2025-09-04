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
  $commentsArray = @()
  [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList

  [String] $FirstBreakGlassUPNUrl = $("/users/" + $FirstBreakGlassUPN + "?$" + "select=userPrincipalName,id,userType")
  [String] $SecondBreakGlassUPNUrl = $("/users/" + $SecondBreakGlassUPN + "?$" + "select=userPrincipalName,id,userType")
  
  $bgCountConfig = 0
  if ($FirstBreakGlassUPN -ne ""){$bgCountConfig += 1}
  if ($SecondBreakGlassUPN -ne ""){$bgCountConfig += 1}

  # Validate at least one unique BG accounts exist in config.json
  if($FirstBreakGlassUPN -eq "" -and $SecondBreakGlassUPN -eq ""){
    $IsCompliant = $false
    $PsObject = [PSCustomObject]@{
      ComplianceStatus = $IsCompliant
      ControlName      = $ControlName
      ItemName         = $ItemName
      Comments         = $msgTable.isNotCompliant + " " + $msgTable.bgAccountNotExist
      ReportTime       = $ReportTime
      itsgcode         = $itsgcode
    }
  }
  elseif (($bgCountConfig -eq 2) -and $FirstBreakGlassUPN -eq $SecondBreakGlassUPN){
      $IsCompliant = $false
      $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        ItemName         = $ItemName
        Comments         = $msgTable.isNotCompliant + " " + $msgTable.bgAccountNotExist
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
      }
  }
  else{
    # Step 1: Validate listed BG accounts as members
    $FirstBreakGlassAcct = [PSCustomObject]@{
      UserPrincipalName  = $FirstBreakGlassUPN
      apiUrl             = $FirstBreakGlassUPNUrl
      existStatus        = $false
    }
    $SecondBreakGlassAcct = [PSCustomObject]@{
      UserPrincipalName   = $SecondBreakGlassUPN
      apiUrl              = $SecondBreakGlassUPNUrl
      existStatus         = $false
    }
    # get 1st break glass account
    try {
      $urlPath = $FirstBreakGlassAcct.apiUrl
      $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop

      $data = $response.Content
      
      if ($null -ne  $data) {
        $FirstBreakGlassAcct.existStatus = $true
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

      if ($null -ne  $data) {
        $SecondBreakGlassAcct.existStatus = $true
      } 
    }
    catch {
      $ErrorList.Add("Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_")
      Write-Warning "Error: Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"
    }

    if ($bgCountConfig -eq 2){
      $validBG = $FirstBreakGlassAcct.existStatus -and $SecondBreakGlassAcct.existStatus
    }
    else {
      $validBG = $FirstBreakGlassAcct.existStatus -or $SecondBreakGlassAcct.existStatus
    }
    
    Write-Host "step 1 validate listed BG accounts compliance status:  $validBG"
    # if not compliant
    if(-not $validBG){
      $PsObject = [PSCustomObject]@{
        ComplianceStatus = $validBG
        ControlName      = $ControlName
        ItemName         = $ItemName
        Comments         = $msgTable.isNotCompliant + " " + $msgTable.bgAccountNotExist
        ReportTime       = $ReportTime
        itsgcode = $itsgcode
      }
    }
    else {
      # Step 2: Validate BG account Sign-in activity
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

      # Validate signIn log is enabled
      try {
        # the log name to validate
        $SignInLogs = @('SignInLogs')

        # Retrieve diagnostic settings to check for logs
        $diagnosticSettings = get-AADDiagnosticSettings
        $matchingSetting = $diagnosticSettings | Where-Object { $_.properties.workspaceId -eq $LAWResourceId } | Select-Object -First 1

        if($matchingSetting){
          $enabledLogs = $matchingSetting.properties.logs | Where-Object { $_.enabled -eq $true } | Select-Object -ExpandProperty category
          $missingSignInLogs = $SignInLogs | Where-Object { $_ -notin $enabledLogs }
        }
        else{
          $missingSignInLogs = $SignInLogs
        }

        # Check missing logs for SignInLogs, if missing/not enabled, non-compliant
        if ($missingSignInLogs.Count -gt 0) {
          $IsCompliant = $false
          $commentsArray += $msgTable.isNotCompliant + " " + $msgTable.signInlogsNotCollected
        }
      }
      catch {
        # catch exceptions
        if ($_.Exception.Message -like "*ResourceNotFound*") {
          $IsCompliant = $false
          $commentsArray += $msgTable.nonCompliantLaw -f $workspaceId
          $ErrorList += "Log Analytics Workspace not found: $_"
        }
        else {
          $IsCompliant = $false
          $ErrorList += "Error accessing Log Analytics Workspace: $_"
        }
      }
    }

    # Retrieve the log data and check the data retention period for sign in
    $kqlQuery = @"
SigninLogs
| where UserPrincipalName in ('$($FirstBreakGlassUPN)', '$($SecondBreakGlassUPN)')
| project TimeGenerated, UserPrincipalName, CreatedDateTime
| where TimeGenerated > ago(365d)
| order by TimeGenerated desc
"@

    try {
        $workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -Name $workspaceId
        $queryResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspace.CustomerId -Query $kqlQuery -ErrorAction Stop
        
        # Access the Results property of the query output
        $results = $queryResults.Results

        # check break glass account signin
        $dataMostRecentSignInFirstBG = $results | Where-Object {$_.UserPrincipalName -eq $FirstBreakGlassUPN} | Select-Object -First 1
        $dataMostRecentSignInSecondBG = $results | Where-Object {$_.UserPrincipalName -eq $SecondBreakGlassUPN} | Select-Object -First 1
    
        if ($null -ne $dataMostRecentSignInFirstBG -or $null -ne $dataMostRecentSignInSecondBG) {
            $IsCompliant = $true
        }
    }
    catch {
      if ($null -eq $workspace) {
        $IsCompliant = $false
        $commentsArray += "Workspace not found in the specified resource group"
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
    

    if($IsCompliant){
      $commentsArray = $msgTable.isCompliant + " " + $msgTable.bgAccountLoginValid
    }
    else {
      $commentsArray = $msgTable.isNotCompliant + " " + $msgTable.bgAccountLoginNotValid
    }
    
    $Comments = $commentsArray -join ";"

    $PsObject = [PSCustomObject]@{
      ComplianceStatus = $IsCompliant
      ControlName      = $ControlName
      ItemName         = $ItemName
      Comments         = $Comments
      ReportTime       = $ReportTime
      itsgcode         = $itsgcode
    }
    
  }

  # Add profile information if MCUP feature is enabled
  if ($EnableMultiCloudProfiles) {
      $result = Add-ProfileInformation -Result $PsObject -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId -ErrorList $ErrorList
      Write-Host "$result"
  }

  $moduleOutput= [PSCustomObject]@{ 
    ComplianceResults = $PsObject
    Errors            = $ErrorList
    AdditionalResults = $AdditionalResults
  }
  return $moduleOutput   
}    


