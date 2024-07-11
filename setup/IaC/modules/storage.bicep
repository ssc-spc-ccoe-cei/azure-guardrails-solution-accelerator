param storageAccountName string
param location string
param containername string
 
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
}
 
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2021-06-01' = {
  name: 'default'
  parent: guardrailsStorage
  properties: {
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      enabled: false
    }
  }
}
 
resource container1 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-06-01' = {
  name: '${guardrailsStorage.name}/default/${containername}'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    denyEncryptionScopeOverride: false
    defaultEncryptionScope: '$account-encryption-key'
    publicAccess: 'None'
  }
  dependsOn: [
    blobServices
  ]
}
 
resource container2 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-06-01' = {
  name: '${guardrailsStorage.name}/default/configuration'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    denyEncryptionScopeOverride: false
    defaultEncryptionScope: '$account-encryption-key'
    publicAccess: 'None'
  }
  dependsOn: [
    blobServices
  ]
}
