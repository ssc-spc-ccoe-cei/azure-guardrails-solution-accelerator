param kvName string
param location string
param releaseVersion string
param releaseDate string
param vaultUri string
param tenantId string
param deployKV bool

resource guardrailsKV 'Microsoft.KeyVault/vaults@2021-06-01-preview' = if (deployKV) {
  name: kvName
  location: location
  tags: {
    releaseVersion:releaseVersion
    releasedate: releaseDate
  }
  properties: {
    sku: {
      family: 'A'
      name:  'standard'
    }
    //tenantId: guardrailsAC.identity.tenantId
    tenantId: tenantId
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
