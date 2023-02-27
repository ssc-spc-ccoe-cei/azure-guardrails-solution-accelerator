param kvName string
param location string
param version string
param releaseDate string
param vaultUri string
param customerId string
param storageAccountName string

resource guardrailsKV 'Microsoft.KeyVault/vaults@2021-06-01-preview' = {
  name: kvName
  location: location
  tags: {
    version: version
    releasedate: releaseDate
  }
  properties: {
    sku: {
      family: 'A'
      name:  'standard'
    }
    tenantId: subscription().tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableSoftDelete: false
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: true
    vaultUri: vaultUri
    provisioningState: 'Succeeded'
    publicNetworkAccess: 'Enabled'
  }
}
resource kvsecret1 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  name: 'WorkspaceId'
  parent: guardrailsKV
  properties: {
    attributes: {
      enabled: true
    }
    contentType: 'string'
    value: customerId
  }
}
resource kvsecret2 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  name: 'StorageAccountName'
  parent: guardrailsKV
  properties: {
    attributes: {
      enabled: true
    }
    contentType: 'string'
    value: storageAccountName
  }
}
resource kvsecret3 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  name: 'ApplicationId'
  parent: guardrailsKV
  properties: {
    attributes: {
      enabled: true
    }
    contentType: 'string'
    value: ''
  }
}
resource kvsecret4 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  name: 'SecurePassword'
  parent: guardrailsKV
  properties: {
    attributes: {
      enabled: true
    }
    contentType: 'string'
    value: ''
  }
}
