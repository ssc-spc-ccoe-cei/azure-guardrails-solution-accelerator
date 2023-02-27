//Scope
targetScope = 'resourceGroup'
//Parameters and variables
param storageAccountName string
param location string = 'canadacentral'
param grafanaregion string = 'eastus'
param kvName string = ''
param functionname string = ''
param logAnalyticsWorkspaceName string = ''
param version string
param releaseDate string 
param appInsightslocation string = 'canadacentral'
param deploygrafana bool = false

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
