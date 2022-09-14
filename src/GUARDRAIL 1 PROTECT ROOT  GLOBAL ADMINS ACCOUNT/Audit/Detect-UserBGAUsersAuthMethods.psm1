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
        [hashtable] $msgTable,
        [string] $LogType,
        [string] $ItemName,
        [string] $itsgcode,
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

        try {
            $Data = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)"} -Uri $apiUrl -ErrorAction Stop
        }
        catch {
            Add-LogEntry 'Error' "Failed to call Microsoft Graph REST API at URL '$apiURL'; returned error message: $_" -workspaceGuid $WorkSpaceID -workspaceKey $WorkSpaceKey
            Write-Error "Error: Failed to call Microsoft Graph REST API at URL '$apiURL'; returned error message: $_"
        }
        $authenticationmethods =  $Data.value

        # To check if MFA is setup for a user, we're looking for either :
        #    #microsoft.graph.microsoftAuthenticatorAuthenticationMethod or
        #    #microsoft.graph.phoneAuthenticationMethod
        Write-Host $authenticationmethods
        $mfaEnabled = $false

        foreach ($authmeth in $authenticationmethods) {
           if (($($authmeth.'@odata.type') -eq "#microsoft.graph.phoneAuthenticationMethod") -or `
                ($($authmeth.'@odata.type') -eq "#microsoft.graph.microsoftAuthenticatorAuthenticationMethod")) {
                $mfaEnabled = $true
            }
        }
        # MFA is enabled for this Breakglass account, we don't want that
        if ($mfaEnabled) {
            $Comments = $Comments + $msgTable.mfaEnabledFor -f $BGAcct
        }

        # This is the compliance status of the current user
        $isCompliant = $isCompliant -and !$mfaEnabled
    }

    $PsObject = [PSCustomObject]@{
        ComplianceStatus= $IsCompliant
        ControlName = $ControlName
        Comments= $Comments
        ItemName= $ItemName
        ReportTime = $ReportTime
        itsgcode = $itsgcode
     }
     $JsonObject = convertTo-Json -inputObject $PsObject 

     Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
                               -sharedkey $workspaceKey `
                               -body $JsonObject `
                               -logType $LogType `
                               -TimeStampField Get-Date 
   }
