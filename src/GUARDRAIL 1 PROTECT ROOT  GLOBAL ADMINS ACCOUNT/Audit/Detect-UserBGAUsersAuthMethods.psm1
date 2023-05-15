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
        [string] $ControlName,
        [hashtable] $msgTable,
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
   [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    $BGAccountList = @($FirstBreakGlassEmail,$SecondBreakGlassEmail )
    
    foreach($BGAcct in $BGAccountList){
        $urlPath = '/users/' + $BGAcct + '/authentication/methods'

        try {
            $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
        }
        catch {
            $ErrorList.Add("Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_" )
            Write-Error "Error: Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"
        }

        $data = $response.Content
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
     $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput    
   }

