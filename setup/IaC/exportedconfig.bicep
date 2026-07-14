targetScope = 'resourceGroup'

// Use ARM so the installer does not need a separate Key Vault data-plane token.
param keyVaultName string

// Keep the exported configuration out of ARM deployment history.
@secure()
param configValue string

param deploymentTimestamp string
param deployerLocalUsername string
param deployerAzureId string

resource keyVault 'Microsoft.KeyVault/vaults@2021-06-01-preview' existing = {
  name: keyVaultName
}

resource exportedConfig 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault
  name: 'gsaConfigExportLatest'
  tags: {
    deploymentTimestamp: deploymentTimestamp
    deployerLocalUsername: deployerLocalUsername
    deployerAzureID: deployerAzureId
  }
  properties: {
    contentType: 'application/json'
    value: configValue
  }
}
