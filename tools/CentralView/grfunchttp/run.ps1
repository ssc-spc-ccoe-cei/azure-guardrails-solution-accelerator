using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
# Interact with query parameters or the body of the request.
$body = "This HTTP triggered function executed successfully. Pass a name in the query string or in the request body for a personalized response."
Connect-AzAccount -Identity
$rg=$env:ResourceGroup #"ssc-centralview"
$KeyvaultName=$env:KEYVAULTNAME #"ssccentralview"
#"RG: $rg"
"KV: $KeyvaultName"
$KV=Get-AzKeyVault -ResourceGroupName $rg -VaultName $keyVaultName 
$ApplicationId=Get-AzKeyVaultSecret -VaultName $keyVaultName -Name "ApplicationId" -asplaintext
$SecuredPassword=Get-AzKeyVaultSecret -VaultName $keyVaultName -Name "SecurePassword" -asplaintext
$workspaceId=Get-AzKeyVaultSecret -VaultName $keyVaultName -Name "WorkspaceId" -asplaintext
$WorkspaceKey=Get-AzKeyVaultSecret -VaultName $keyVaultName -Name "WorkspaceKey" -asplaintext
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
    get-tenantdata -workspaceID $workspaceId -workspacekey $WorkspaceKey -ReportTime $ReportTime `
        -tenantName $TenantName -tenantDomainUPN $TenantDomainUPN -tenantId $TenantId
}
catch {
    Write-Output "Error running get-tenantdata"
}
# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $body
})
