<#
.SYNOPSIS
   the module will verify if the manager information for both Break Glass Accounts is populated
   results are sent to the identified log analytics workspace.

.DESCRIPTION
 the module will verify if the manager information for both Break Glass Accounts is populated
   results are sent to the identified log analytics workspace.
.PARAMETER Name
        FirstBreakGlassUPNOwner :- The First Break Glass Account UPN 
        SecondBreakGlassUPNOwner :- The second Break Glass Account UPN
        ControlName :-  GUARDRAIL 1 PROTECT ROOT  GLOBAL ADMINS ACCOUNT
        ItemName, 
        WorkSpaceID : Workspace ID to ingest the logs 
        WorkSpaceKey: Workspace Key for the Workdspace 
        LogType: GuardrailsCompliance, it will show in log Analytics search as GuardrailsCompliance_CL
#>
function Get-BreakGlassOwnerinformation {
    param (
        [string] $FirstBreakGlassUPNOwner,
        [string] $SecondBreakGlassUPNOwner, 
        [string] $ControlName, 
        [string] $ItemName,
        [string] $itsgcode,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime,
        [string] 
        $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] $EnableMultiCloudProfiles # New feature flag, default to false    
    )
    [bool] $IsCompliant = $false
    [string] $Comments = $null
     
    $FirstBreakGlassOwner = [PSCustomObject]@{
        UserPrincipalName  = $FirstBreakGlassUPNOwner
        ComplianceStatus   = $false
        ComplianceComments = $null
    }
    $SecondBreakGlassOwner = [PSCustomObject]@{
        UserPrincipalName  = $SecondBreakGlassUPNOwner
        ComplianceStatus   = $false
        ComplianceComments = $null
    }

    [PSCustomObject] $BGOwners = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    
    $BGOwners.add( $FirstBreakGlassOwner) | Out-Null
    $BGOwners.add( $SecondBreakGlassOwner) | Out-Null
    
    foreach ($BGOwner in $BGOwners) {
        
        $urlPath = '/users/' + $BGOwner.UserPrincipalName + '/manager'
        try {
            $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop

            $hiddenUserPrincipalName = Hide-Email -email $BGOwner.UserPrincipalName

            If ($response.statusCode -eq 200) {
                $BGOwner.ComplianceStatus = $true
                $BGOwner.ComplianceComments = $msgTable.bgAccountHasManager -f $hiddenUserPrincipalName
            }
            ElseIf ($response.statusCode -eq 404) {
                $BGOwner.ComplianceStatus = $false
                $BGOwner.ComplianceComments = $msgTable.bgAccountNoManager -f $hiddenUserPrincipalName
            }
            Else {
                $ErrorList.Add("Failed to call Microsoft Graph REST API at URL '$urlPath'; unhandled status code in response: '$($response.statusCode)'" )
                Write-Error "Error: Failed to call Microsoft Graph REST API at URL '$urlPath'; unhandled status code in response: '$($response.statusCode)'"
            }
        }
        catch {
            $ErrorList.Add("Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_" )
            Write-Error "Error: Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"
        }
    }
    $IsCompliant = $FirstBreakGlassOwner.ComplianceStatus -and $SecondBreakGlassOwner.ComplianceStatus

    if ($IsCompliant) {
        $Comments = $msgTable.bgBothHaveManager
    }
    else {
        if ($FirstBreakGlassOwner.ComplianceStatus -eq $false) {
            $Comments = $BGOwners[0].ComplianceComments
        }
        if ($SecondBreakGlassOwner.ComplianceStatus -eq $false) {
            $Comments = $Comments + $BGOwners[1].ComplianceComments
        }
        #$Comments = "First BreakGlass Owner " + $FirstBreakGlassOwner.UserPrincipalName + " doesnt have a manager listed in the directory or " + `
        #    "Second BreakGlass Owner " + $SecondBreakGlassOwner.UserPrincipalName + " doesnt have a manager listed in the directory ."
    }
    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        Comments         = $Comments
        ItemName         = $ItemName
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }

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


