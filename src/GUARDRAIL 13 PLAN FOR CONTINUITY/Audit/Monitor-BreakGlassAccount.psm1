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
  

  function Get-LastSuccessfulSignIn {
    param (
      [string] $UserPrincipalName
    )

    if([string]::IsNullOrWhiteSpace($UserPrincipalName)){
      return $null
    }

    $upn = $UserPrincipalName.Trim()

    try{
      #Getting Last SignIn info from MS Graph
      $userID = "/users/{0}?`$select=id" -f $upn #This is required to get last sign in info
      $response1 = Invoke-GraphQueryEX -urlPath $userID -ErrorAction Stop

      $lastUserSignIn = "/users/{0}?`$select=userPrincipalName,signInActivity" -f $response1.Content.id
      $response = Invoke-GraphQueryEX -urlPath $lastUserSignIn -ErrorAction Stop
      $userData = $response.Content

      if($null -ne $userData -and $null -ne $userData.signInActivity){
        return $userData.signInActivity.lastSuccessfulSignInDateTime
      }
      else{
        return $null
      }
    }
    catch{
      $ErrorList.Add("Failed to query lastSuccessfulSignInDateTime for '$upn': $_")
      return $null
    }
  }

  function Check-DateWithinDays {
    param (
      [string] $dateToCheck
    )

    if([string]::IsNullOrEmpty($dateToCheck)){
      return $false
    }

    $lastSignIn = [System.DateTimeOffset]$dateToCheck
    $currentDate = [System.DateTimeOffset]::UtcNow
    $difference = ($currentDate - $lastSignIn).TotalDays

    return ($difference -le 365)
  }

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
  # Validate unique BG accounts
  elseif(($bgCountConfig -eq 2) -and $FirstBreakGlassUPN -eq $SecondBreakGlassUPN){
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
      if($FirstBreakGlassUPN -ne ""){
        $response = Invoke-GraphQuery -urlPath $FirstBreakGlassAcct.apiURL -ErrorAction Stop
        $data = $response.Content
        
        if ($null -ne  $data) {
          $FirstBreakGlassAcct.existStatus = $true
        } 
      }
    }
    catch {
      $ErrorList.Add("Failed to call Microsoft Graph for '$($FirstBreakGlassAcct.UserPrincipalName)': $_")
      Write-Warning "Graph error for BG1 '$($FirstBreakGlassAcct.UserPrincipalName)': $_"
    }

    # get 2nd break glass account
    try {
      if($SecondBreakGlassUPN -ne ""){
        $response2 = Invoke-GraphQuery -urlPath $SecondBreakGlassAcct.apiURL -ErrorAction Stop
        $data2 = $response2.Content
        
        if ($null -ne  $data2) {
          $SecondBreakGlassAcct.existStatus = $true
        } 
      }
    }
    catch {
      $ErrorList.Add("Failed to call Microsoft Graph for '$($SecondBreakGlassAcct.UserPrincipalName)': $_")
      Write-Warning "Graph error for BG1 '$($SecondBreakGlassAcct.UserPrincipalName)': $_"
    }

    [bool] $validBG =
      if ($bgCountConfig -eq 2){
        $FirstBreakGlassAcct.existStatus -and $SecondBreakGlassAcct.existStatus
      }
      else {
        $FirstBreakGlassAcct.existStatus -or $SecondBreakGlassAcct.existStatus
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
      $firstLastSuccess = Get-LastSuccessfulSignIn -UserPrincipalName $FirstBreakGlassUPN
      $secondLastSuccess = Get-LastSuccessfulSignIn -UserPrincipalName $SecondBreakGlassUPN

      $firstCompliant = Check-DateWithinDays -dateToCheck $firstLastSuccess
      $secondCompliant = Check-DateWithinDays -dateToCheck $secondLastSuccess

      if($bgCountConfig -eq 2){
        $IsCompliant = $firstCompliant -and $secondCompliant
      }
      else {
        $IsCompliant = $false
      }

      if($IsCompliant){
        Write-Host "step 2 validate BG accounts last login compliance status:  $IsCompliant"
        $commentsArray += $msgTable.isCompliant + " " + $msgTable.bgAccountLoginValid
      }
      else {
        Write-Host "step 2 validate BG accounts last login compliance status:  $IsCompliant"
        $commentsArray += $msgTable.isNotCompliant + " " + $msgTable.bgAccountLoginNotValid
      }
    }
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


