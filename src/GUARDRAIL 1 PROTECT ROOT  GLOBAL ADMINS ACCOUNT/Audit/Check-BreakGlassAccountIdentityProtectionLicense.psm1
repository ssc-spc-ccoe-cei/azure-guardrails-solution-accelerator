<#
.SYNOPSIS
   The module will look for a P2 equivalent licensing, Once the solution find any of the following "String Id", the check mark status will be changed from (❌) to (✔️).

Product name: AZURE ACTIVE DIRECTORY PREMIUM P2, String ID: AAD_PREMIUM_P2
Product name: ENTERPRISE MOBILITY + SECURITY E5, String ID: EMSPREMIUM
Product name: Microsoft 365 E5, String ID: SPE_E5

.DESCRIPTION
The module will look for a P2 equivalent licensing, Once the solution find any of the following "String Id", the check mark status will be changed from (❌) to (✔️).

Product name: AZURE ACTIVE DIRECTORY PREMIUM P2, String ID: AAD_PREMIUM_P2
Product name: ENTERPRISE MOBILITY + SECURITY E5, String ID: EMSPREMIUM
Product name: Microsoft 365 E5, String ID: SPE_E5
.PARAMETER Name
        token : auth token 
        FirstBreakGlassUPN: UPN for the first Break Glass account 
        SecondBreakGlassUPN: UPN for the second Break Glass account
        ControlName :-  GUARDRAIL 1 PROTECT ROOT  GLOBAL ADMINS ACCOUNT
        ItemName, 
        WorkSpaceID : Workspace ID to ingest the logs 
        WorkSpaceKey: Workspace Key for the Workdspace 
        LogType: GuardrailsCompliance, it will show in log Analytics search as GuardrailsCompliance_CL
#>
function Get-BreakGlassAccountLicense {
    param (
       [string] $token, 
       [string] $FirstBreakGlassUPN,
       [string] $SecondBreakGlassUPN, 
       [string] $ControlName, 
       [string] $ItemName, 
       [string] $WorkSpaceID, 
       [string] $workspaceKey, 
       [string] $LogType,
       [Parameter(Mandatory=$true)]
       [string]
       $ReportTime
       )
    [bool] $IsCompliant= $false
    [string] $Comments= $null

    [PSCustomObject] $BGAccounts = New-Object System.Collections.ArrayList
     
    $FirstBreakGlassAcct= [PSCustomObject]@{
        UserPrincipalName     = $FirstBreakGlassUPN
        ID = $null
        LicenseDetails= "NOT ASSIGNED"
    }
    $SecondBreakGlassAcct= [PSCustomObject]@{
        UserPrincipalName     = $SecondBreakGlassUPN
        ID = $null
        LicenseDetails= "NOT ASSIGNED"
    }
        $BGAccounts.add( $FirstBreakGlassAcct)
        $BGAccounts.add( $SecondBreakGlassAcct)
        
    
   foreach ($BGAccount in $BGAccounts){
        
        $apiUrl=  $("https://graph.microsoft.com/beta/users/"+ $BGAccount.UserPrincipalName)
        $Data = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)"} -Uri $apiUrl -Method Get
        $BGAccount.ID =  $Data.id

        $apiUrl = $("https://graph.microsoft.com/beta/users/"+$BGAccount.ID+"/licenseDetails")
        $Data = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)"} -Uri $apiUrl -Method Get

        if(($data.value).Length -gt 0 ){
             $BGAccount.LicenseDetails= ($Data.value).skuPartNumber
    }
   }
        if((($FirstBreakGlassAcct.LicenseDetails -match  "EMSPREMIUM") -or ($FirstBreakGlassAcct.LicenseDetails -match  "ENTERPRISEPREMIUM")) -and `
           (($SecondBreakGlassAcct.LicenseDetails -match "EMSPREMIUM") -or ($SecondBreakGlassAcct.LicenseDetails -match "ENTERPRISEPREMIUM"))){

            $IsCompliant= $true
            $Comments= $FirstBreakGlassAcct.UserPrincipalName +" Assigned License = "+  $FirstBreakGlassAcct.LicenseDetails +
                       $SecondBreakGlassAcct.UserPrincipalName +" Assigned License = "+  $SecondBreakGlassAcct.LicenseDetails 
   }    else {
             $Comments= $FirstBreakGlassAcct.UserPrincipalName +" Assigned License = "+  $FirstBreakGlassAcct.LicenseDetails +" & "+
             $SecondBreakGlassAcct.UserPrincipalName +" Assigned License = "+  $SecondBreakGlassAcct.LicenseDetails 
   }

   $PsObject = [PSCustomObject]@{
    ComplianceStatus= $IsCompliant
    ControlName = $ControlName
    Comments= $Comments
    ItemName= $ItemName
    ReportTime = $ReportTime
 }
 $JsonObject = convertTo-Json -inputObject $PsObject 

 Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
                           -sharedkey $workspaceKey `
                           -body $JsonObject `
                           -logType $LogType `
                           -TimeStampField Get-Date 
   
}
