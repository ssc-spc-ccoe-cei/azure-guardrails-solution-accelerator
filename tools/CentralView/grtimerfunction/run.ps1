# Input bindings are passed in via param block.
param($Timer)

# Import the ingest-tenantsData module
Import-Module "$PSScriptRoot\..\Modules\ingest-tenantsData\ingest-tenantsData.psm1" -Force

# Write to the Azure Functions log stream.
Write-Host "PowerShell timer trigger function processed a request."
Connect-AzAccount -Identity
$rg=$env:ResourceGroup #"ssc-centralview"
$KeyvaultName=$env:KEYVAULTNAME #"ssccentralview"
#"RG: $rg"
"KV: $KeyvaultName"
$KV=Get-AzKeyVault -ResourceGroupName $rg -VaultName $keyVaultName 
$ApplicationId=Get-AzKeyVaultSecret -VaultName $keyVaultName -Name "ApplicationId" -asplaintext
$SecuredPassword=Get-AzKeyVaultSecret -VaultName $keyVaultName -Name "SecurePassword" -asplaintext
#New variables to store the tenant ID and tenant name for the aggreation tenant.
$TenantId=Get-AzKeyVaultSecret -VaultName $keyVaultName -Name "TenantId" -asplaintext
$TenantName=Get-AzKeyVaultSecret -VaultName $keyVaultName -Name "TenantName" -asplaintext
$tenantDomainUPN=Get-AzKeyVaultSecret -VaultName $keyVaultName -Name "tenantDomainUPN" -asplaintext
#Write-Output "App Id: $ApplicationId"
#Write-Output "SP: $SecurePassword"
#Write-Output "Tenant: $TenantId"

$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ApplicationId, $(ConvertTo-SecureString $SecuredPassword -AsPlainText -Force)

try {Connect-AzAccount -ServicePrincipal -TenantId $TenantId -Credential $Credential}
catch {
    Write-Output "Error connecting to Azure with SPN."
    break 
}
$ReportTime=(get-date).tostring("yyyy-MM-dd HH:mm:ss")
"Report Time: $ReportTime"
try {
    # Updated function call without workspace parameters (DCR ingestion doesn't need them)
    get-tenantdata -ReportTime $ReportTime -tenantName $TenantName -tenantDomainUPN $TenantDomainUPN -tenantId $TenantId -DebugInfo:$true
}
catch {
    Write-Output "Error running get-tenantdata: $($_.Exception.Message)"
    Write-Output "ScriptStackTrace: $($_.ScriptStackTrace)"
    if ($_.Exception.InnerException) {
        Write-Output "InnerException: $($_.Exception.InnerException.Message)"
    }
}
# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"