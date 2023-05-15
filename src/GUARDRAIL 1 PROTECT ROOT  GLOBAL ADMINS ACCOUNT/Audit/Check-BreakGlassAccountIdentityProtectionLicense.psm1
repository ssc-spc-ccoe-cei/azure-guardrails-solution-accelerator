<#
.SYNOPSIS
   The module will look for a P2 equivalent licensing assigned to the BG accounts.


.DESCRIPTION
    The module will look for the AAD_PREMIUM_P2 service plan in all of the licences assigned to the user, once it finds "AAD_PREMIUM_P2", the check mark status will be changed from (❌) to (✔️).



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
        [string] $FirstBreakGlassUPN,
        [string] $SecondBreakGlassUPN, 
        [string] $ControlName, 
        [string] $ItemName, 
        [string] $itsgcode,
        [hashtable] $msgTable,      
        [Parameter(Mandatory = $true)]
        [string]
        $ReportTime
    )
    [bool] $IsCompliant = $false
    [string] $Comments = $null

    [PSCustomObject] $BGAccounts = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
     
    $FirstBreakGlassAcct = [PSCustomObject]@{
        UserPrincipalName = $FirstBreakGlassUPN
        ID                = $null
        LicenseAADP2Found = $false
    }
    $SecondBreakGlassAcct = [PSCustomObject]@{
        UserPrincipalName = $SecondBreakGlassUPN
        ID                = $null
        LicenseAADP2Found = $false
    }
    $BGAccounts.add( $FirstBreakGlassAcct) | Out-Null
    $BGAccounts.add( $SecondBreakGlassAcct) | Out-Null

    foreach ($BGAccount in $BGAccounts) {
        
        $urlPath = '/users/' + $BGAccount.UserPrincipalName

        try {
            $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
        }
        catch {
            $ErrorList.Add("Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_")
            Write-Error "Error: Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"
        }
        $data = $response.Content
        $BGAccount.ID = $data.id

        # if BGA account exists, check for license details
        If ($BGAccount.ID) {
            $urlPath = '/users/' + $BGAccount.UserPrincipalName + '/licenseDetails'

            try {
                $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
            }
            catch {
                If ($response.statusCode -eq 404) { continue }
                $ErrorList.Add("Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_")
                Write-Error "Error: Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"
            }

            $data = $response.Content

            # A user can have multiple licences, so we need to look for all license sku that have AAD_PREMIUM_P2 in the service plans included
            # https://docs.microsoft.com/en-us/azure/active-directory/enterprise-users/licensing-service-plan-reference
            if (($data.value).Length -gt 0 ) {
                $BGAccount.LicenseAADP2Found = $data.value.servicePlans.ServicePlanName -contains 'AAD_PREMIUM_P2'
            }
        }
    }
    if (($FirstBreakGlassAcct.LicenseAADP2Found) -and ($SecondBreakGlassAcct.LicenseAADP2Found)) {
        $IsCompliant = $true
        $Comments = $msgTable.firstBgAccount + ' ' + $msgTable.bgValidLicenseAssigned + " & " +
        $msgTable.secondBgAccount + ' ' + $msgTable.bgValidLicenseAssigned 
    }
    else {
        if (!$FirstBreakGlassAcct.LicenseAADP2Found) {
            $Comments = $msgTable.bgNoValidLicenseAssigned + ' ' + $msgTable.firstBgAccount
        }
        if (!$SecondBreakGlassAcct.LicenseAADP2Found) {
            $Comments += ' ' + $msgTable.bgNoValidLicenseAssigned + ' ' + $msgTable.secondBgAccount
        }
    }

    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        Comments         = $Comments
        ItemName         = $ItemName
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }
    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors            = $ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput
}


