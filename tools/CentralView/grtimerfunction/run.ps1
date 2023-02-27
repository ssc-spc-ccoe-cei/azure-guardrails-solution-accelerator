# Input bindings are passed in via param block.
param($Timer)

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
$TenantId=(Get-AzTenant).Id
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
    get-tenantdata -workspaceID $workspaceId -workspacekey $WorkspaceKey -ReportTime $ReportTime
}
catch {
    Write-Output "Error running get-tenantdata"
}
# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"
