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
        ControlName :-  GUARDRAIL 1 PROTECT ROOT  GLOBAL ADMINS ACCOUNT
        ItemName, 
        WorkSpaceID : Workspace ID to ingest the logs 
        WorkSpaceKey: Workspace Key for the Workdspace 
        LogType: GuardrailsCompliance, it will show in log Analytics search as GuardrailsCompliance_CL
#>

function Get-ADLicenseType {
    
 param (
     [string] $token, 
     [string] $ControlName,
     [string] $WorkSpaceID, 
     [string] $workspaceKey, 
     [string] $LogType,
     [string] $ItemName,
    [Parameter(Mandatory=$true)]
    [string]
    $ReportTime
)
    $ADLicenseType  = "N/A"
    $IsCompliant = $false
    $apiUrl = "https://graph.microsoft.com/v1.0/subscribedSkus"
    $Data = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)"} -Uri $apiUrl -Method Get
    $subscribedSkus = $Data.Value
    $servicePlans=  $subscribedSkus.servicePlans
    #https://docs.microsoft.com/en-us/azure/active-directory/enterprise-users/licensing-service-plan-reference
    foreach ($servicePlan in $servicePlans) {
        if(($servicePlan.servicePlanName -eq "AAD_PREMIUM_P2") -or`
           ($servicePlan.servicePlanName -eq "EMSPREMIUM")-or`
           ($servicePlan.servicePlanName -eq "SPE_E5")){
            $IsCompliant = $true
            $ADLicenseType  = $servicePlan.servicePlanName
        }
    }

    $PsObject = [PSCustomObject]@{
        ComplianceStatus= $IsCompliant
        ControlName = $ControlName
        ADLicenseType = $ADLicenseType
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

