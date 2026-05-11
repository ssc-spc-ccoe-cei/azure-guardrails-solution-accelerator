param functionname string
param location string
param storageAccountName string
param kvname string
param lawresourceid string
param appInsightsLocation string
param dceEndpoint string
param dcrImmutableId string

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
    minimumTlsVersion: 'TLS1_2'
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
  resource fileServices 'fileServices' = {
    name: 'default'
  }
}

// Containers and file share required by the Azure Functions runtime. If these don't exist
// the host fails on first start with 'ContainerNotFound' (Azure.RequestFailedException 404)
// because PublishAsync writes lock/secret blobs before checking-and-creating the container.
// Declaring them in Bicep guarantees they exist on every deploy.
resource hostsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-06-01' = {
  parent: guardrailsStorage::blobServices
  name: 'azure-webjobs-hosts'
  properties: {
    publicAccess: 'None'
  }
}
resource secretsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-06-01' = {
  parent: guardrailsStorage::blobServices
  name: 'azure-webjobs-secrets'
  properties: {
    publicAccess: 'None'
  }
}
// Function content share. WEBSITE_CONTENTSHARE below points to the storage account name,
// so the share has to be named exactly that (lowercased to satisfy share naming rules).
resource contentShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2021-06-01' = {
  parent: guardrailsStorage::fileServices
  name: toLower(guardrailsStorage.name)
  properties: {
    shareQuota: 5120
  }
}


resource serverfarm 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: '${functionname}-farm'
  location: location
  sku: {
    name: 'P2v2'
    tier: 'PremiumV2'
    size: 'P2v2'
    family: 'Pv2'
    capacity: 1
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
          minTlsVersion: '1.2'
          minTlsCipherSuite: 'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384'
          //minTlsCipherSuite: 'TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384' -> this is the requested option but seems to be causing issues when deploying.
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
      httpsOnly: true
      redundancyMode: 'None'
      storageAccountRequired: false
      keyVaultReferenceIdentity: 'SystemAssigned'
  }
}
resource azfunctionsiteconfig 'Microsoft.Web/sites/config@2021-03-01' = {
  name: 'appsettings'
  parent: azfunctionsite
  // Don't apply app settings (which start the function host) until the runtime's required
  // blob containers and file share exist on the backing storage account.
  dependsOn: [
    hostsContainer
    secretsContainer
    contentShare
  ]
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
    'DCE_ENDPOINT': dceEndpoint
    'DCR_IMMUTABLE_ID': dcrImmutableId
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
