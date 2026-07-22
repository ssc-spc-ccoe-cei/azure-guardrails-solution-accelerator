targetScope = 'resourceGroup'

// The installer already uses Azure Resource Manager (ARM) to create the solution. Saving the
// config through ARM avoids asking for a separate Key Vault token near the end of the install.
// It does not bypass Conditional Access; the installer's existing Azure session must still work.
param keyVaultName string

// The config contains deployment details that should not appear in ARM deployment history.
// Marking the parameter secure masks its value while Azure passes it to the Key Vault secret.
@secure()
param configValue string

param deploymentTimestamp string
param deployerLocalUsername string
param deployerAzureId string

resource keyVault 'Microsoft.KeyVault/vaults@2021-06-01-preview' existing = {
  name: keyVaultName
}

// Keep the same secret name, content type, and audit tags used by the old PowerShell export.
// Only the route used to save the secret changes: ARM now performs the write for the installer.
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
