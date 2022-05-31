<#
.SYNOPSIS
   
The module checks if the mutifactor authentication (MFA) is enable on the break glass account, if MFA is not enabled the check mark status will be changed from (❌) to (✔️).
.DESCRIPTION
    The module checks if the mutifactor authentication (MFA) is enable on the break glass account, if MFA is not enabled the check mark status will be changed from (❌) to (✔️).
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
function Get-UserAuthenticationMethod { 
    param (
        [string] $token, 
        [string] $ControlName,
        [string] $WorkSpaceID, 
        [string] $workspaceKey, 
        [string] $LogType,
        [string] $ItemName,
        [string] $FirstBreakGlassEmail,
        [string] $SecondBreakGlassEmail,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime
   )
   $IsCompliant = $true
   $Comments=$null
   
    $BGAccountList = @($FirstBreakGlassEmail,$SecondBreakGlassEmail )
    
    foreach($BGAcct in $BGAccountList){
        $apiUrl = "https://graph.microsoft.com/beta/users/"+$BGAcct+"/authentication/methods"
        $Data = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)"} -Uri $apiUrl
        $authenticationmethods =  $Data.value

        foreach($authmeth in $authenticationmethods){
           if( $($authmeth.'@odata.type') -eq "#microsoft.graph.phoneAuthenticationMethod" ){
            $IsCompliant= $IsCompliant -and $false
            $Comments = $Comments +" "+ $BGAcct + " Authentication Methods " + $($authmeth.'@odata.type')+ "  "
           }
        } 
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
