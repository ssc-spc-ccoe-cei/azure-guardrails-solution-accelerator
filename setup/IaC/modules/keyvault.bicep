param kvName string
param location string
param currentUserObjectId string = ''
param releaseVersion string
param releaseDate string
param vaultUri string
param tenantId string
param deployKV bool
param logAnalyticsWorkspaceName string = ''
@secure()
param breakglassAccount1 string = ''
@secure()
param breakglassAccount2 string = ''

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: logAnalyticsWorkspaceName
}

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

resource adminUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = if (currentUserObjectId != '') {
  name: 'c5a51db0-f2a7-4832-947e-32359393c190' //random guid 'adminUserRoleAssignment'
  scope: guardrailsKV
  properties: {
    // key vault administrator role definition id
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions','00482a5a-887f-4fb3-b363-3b7fe8e74483')
    principalId: currentUserObjectId
  }
}

resource secretWorkspaceKey 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = if (logAnalyticsWorkspaceName != '') {
  name: 'WorkSpaceKey'
  parent: guardrailsKV
  dependsOn: [
    adminUserRoleAssignment
  ]
  properties: {
    value: logAnalyticsWorkspace.listKeys().primarySharedKey
  }
}

resource secretBreakglassAccount1 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = if (breakglassAccount1 != '') {
  name: 'BGA1'
  parent: guardrailsKV
  dependsOn: [
    adminUserRoleAssignment
  ]
  properties: {
    value: breakglassAccount1
  }
}

resource secretBreakglassAccount2 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = if (breakglassAccount2 != '') {
  name: 'BGA2'
  parent: guardrailsKV
  dependsOn: [
    adminUserRoleAssignment
  ]
  properties: {
    value: breakglassAccount2
  }
}
