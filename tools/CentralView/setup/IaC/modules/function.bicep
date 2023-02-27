param functionname string
param location string
param storageAccountName string
param kvname string
param lawresourceid string
param appInsightsLocation string

//Storage Account
resource guardrailsStorage 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    supportsHttpsTrafficOnly: true
  }
  resource blobServices 'blobServices'={
    name: 'default'
    properties: {
        cors: {
            corsRules: []
        }
        deleteRetentionPolicy: {
            enabled: false
        }
    }
  }
}


resource serverfarm 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: '${functionname}-farm'
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  kind: 'functioapp'
  properties: {
    perSiteScaling: false
    elasticScaleEnabled: false
    maximumElasticWorkerCount: 1
    isSpot: false
    reserved: false
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
    zoneRedundant: false
  }
}
resource azfunctionsite 'Microsoft.Web/sites@2021-03-01' = {
  name: functionname
  location: location
  kind: 'functionapp'
  identity: {
      type: 'SystemAssigned'
  }  
  properties: {
      enabled: true      
      hostNameSslStates: [
          {
              name: '${functionname}.azurewebsites.net'
              sslState: 'Disabled'
              hostType: 'Standard'
          }
          {
              name: '${functionname}.azurewebsites.net'
              sslState: 'Disabled'
              hostType: 'Repository'
          }
      ]
      serverFarmId: serverfarm.id
      reserved: false
      isXenon: false
      hyperV: false
      siteConfig: {
          numberOfWorkers: 1
          acrUseManagedIdentityCreds: false
          alwaysOn: false
          ipSecurityRestrictions: [
              {
                  ipAddress: 'Any'
                  action: 'Allow'
                  priority: 1
                  name: 'Allow all'
                  description: 'Allow all access'
              }
          ]
          scmIpSecurityRestrictions: [
              {
                  ipAddress: 'Any'
                  action: 'Allow'
                  priority: 1
                  name: 'Allow all'
                  description: 'Allow all access'
              }
          ]
          http20Enabled: false
          functionAppScaleLimit: 200
          minimumElasticInstanceCount: 0
      }
      scmSiteAlsoStopped: false
      clientAffinityEnabled: false
      clientCertEnabled: false
      clientCertMode: 'Required'
      hostNamesDisabled: false
      containerSize: 1536
      dailyMemoryTimeQuota: 0
      httpsOnly: false
      redundancyMode: 'None'
      storageAccountRequired: false
      keyVaultReferenceIdentity: 'SystemAssigned'
  }
}
resource azfunctionsiteconfig 'Microsoft.Web/sites/config@2021-03-01' = {
  name: 'appsettings'
  parent: azfunctionsite
  properties: {
    'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING':'DefaultEndpointsProtocol=https;AccountName=${guardrailsStorage.name};AccountKey=${listKeys(guardrailsStorage.id, guardrailsStorage.apiVersion).keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
    'AzureWebJobsStorage':'DefaultEndpointsProtocol=https;AccountName=${guardrailsStorage.name};AccountKey=${listKeys(guardrailsStorage.id, guardrailsStorage.apiVersion).keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
    'WEBSITE_CONTENTSHARE' : guardrailsStorage.name
    'FUNCTIONS_WORKER_RUNTIME':'powershell'
    'FUNCTIONS_EXTENSION_VERSION':'~4'
    'KEYVAULTNAME': kvname
    'ResourceGroup': resourceGroup().name
    'APPINSIGHTS_INSTRUMENTATIONKEY': reference(appinsights.id, '2020-02-02-preview').InstrumentationKey
    'APPLICATIONINSIGHTS_CONNECTION_STRING': 'InstrumentationKey=${reference(appinsights.id, '2020-02-02-preview').InstrumentationKey}'
    'ApplicationInsightsAgent_EXTENSION_VERSION': '~2'
  }
}

resource appinsights 'Microsoft.Insights/components@2020-02-02' = {
  name: functionname
  location: appInsightsLocation
  kind: 'web'
  properties: {
    Application_Type: 'web'
    ApplicationId: guid(functionname)
    Flow_Type: 'Redfield'
    Request_Source: 'IbizaAIExtension'
    PublicNetworkAccessForIngestion: 'Enabled'
    PublicNetworkAccessForQuery: 'Enabled'
    WorkspaceResourceId: lawresourceid
  }
}
