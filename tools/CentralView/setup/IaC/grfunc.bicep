//Scope
targetScope = 'resourceGroup'
//Parameters and variables
param storageAccountName string
param location string = 'canadacentral'
param kvName string = ''
param functionname string = ''
param logAnalyticsWorkspaceName string = ''
param version string
param releaseDate string 
param appInsightslocation string = 'canadacentral'

@description('Object id (Get-AzADServicePrincipal .Id / enterprise app object id) for the CentralView ingestion service principal matching Key Vault ApplicationId. Leave empty to skip automated DCR Monitoring Metrics Publisher role assignment.')
param ingestionServicePrincipalObjectId string = ''

@description('Set true only when GuardrailsTenantsCompliance_CL already exists in the LAW and must not be redefined by IaC.')
param deferGuardrailsTenantsComplianceTableProvisioning bool = false

var vaultUri = 'https://${kvName}.vault.azure.net/'
var rg=resourceGroup().name

//Resources
module law 'modules/law.bicep' = {
  name: 'law'
  params: {
    location: location
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    releaseDate: releaseDate
    rg: resourceGroup().name
    subscriptionId: subscription().subscriptionId
    version: version
    deferGuardrailsTenantsComplianceTableProvisioning: deferGuardrailsTenantsComplianceTableProvisioning
  }
}

module centralviewDcrIngestionRbac 'modules/centralview-dcr-ingestion-rbac.bicep' = if (!empty(ingestionServicePrincipalObjectId)) {
  name: 'centralview-dcr-ingestion-rbac'
  dependsOn: [
    law
  ]
  params: {
    dcrResourceId: law.outputs.dcrResourceId
    principalId: ingestionServicePrincipalObjectId
  }
}

module functionapp 'modules/function.bicep' = {
  name: 'functionapp'
  scope: resourceGroup(rg)
  params: {
    location: location
    functionname: functionname
    kvname: kvName
    storageAccountName: storageAccountName
    lawresourceid: law.outputs.lawresourceid
    appInsightsLocation: appInsightslocation
    dceEndpoint: law.outputs.dceEndpoint
    dcrImmutableId: law.outputs.dcrImmutableId
  }
}
module keyvault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  scope: resourceGroup(rg)
  params: {
    vaultUri: vaultUri
    kvName: kvName
    location: location
    version: version
    releaseDate: releaseDate
    customerId: law.outputs.customerId
    storageAccountName: storageAccountName
  }
}
