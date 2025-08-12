<#
.SYNOPSIS
   
The module will look for the AAD_PREMIUM_P2 service plan in all of the licences available on the tenant.

.DESCRIPTION
    The module will look for the AAD_PREMIUM_P2 service plan in all of the licences available on the tenant, once it finds "AAD_PREMIUM_P2", the check mark status will be changed from (❌) to (✔️).

    All details can be found here: https://docs.microsoft.com/en-us/azure/active-directory/enterprise-users/licensing-service-plan-reference

.PARAMETER Name
        token : auth token 
        ControlName :-  GUARDRAIL 1 PROTECT ROOT  GLOBAL ADMINS ACCOUNT
        ItemName, 
        WorkSpaceID : Workspace ID to ingest the logs 
        WorkSpaceKey: Workspace Key for the Workdspace 
        LogType: GuardrailsCompliance, it will show in log Analytics search as GuardrailsCompliance_CL
#>

function Get-ADLicenseType {
    
 param (
     [string] $ControlName,
     [string] $itsgcode,
     [hashtable] $msgTable,
     [string] $ItemName,
    [Parameter(Mandatory=$true)]
    [string]
    $ReportTime,
    [string] 
    $CloudUsageProfiles = "3",  # Passed as a string
    [string] $ModuleProfiles,  # Passed as a string
    [switch] 
    $EnableMultiCloudProfiles # New feature flag, default to false
)
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    $ADLicenseType  = "N/A"
    $IsCompliant = $false
    $Comments= $msgTable.MSEntIDLicenseTypeNotFound

    $urlPath = '/subscribedSkus'
    try {
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
    }
    catch {
        $ErrorList.Add("Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_")
        Write-Error "Error: Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"
    }

    $data = $response.Content
    
    $licenseAADP2Found = $data.value.servicePlans.ServicePlanName -contains 'AAD_PREMIUM_P2'

    #https://docs.microsoft.com/en-us/azure/active-directory/enterprise-users/licensing-service-plan-reference
    if ($licenseAADP2Found) {
        $IsCompliant = $true
        $ADLicenseType = "AAD_PREMIUM_P2"
        $Comments = $msgTable.MSEntIDLicenseTypeFound
    }

    $PsObject = [PSCustomObject]@{
        ComplianceStatus= $IsCompliant
        ControlName = $ControlName
        ADLicenseType = $ADLicenseType
        ItemName= $ItemName
        ReportTime = $ReportTime
        itsgcode = $itsgcode
        Comments = $Comments
     }

    # Add profile information if MCUP feature is enabled
    if ($EnableMultiCloudProfiles) {
        $result = Add-ProfileInformation -Result $PsObject -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId -ErrorList $ErrorList
        Write-Host "$result"
    }

    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput    
}

