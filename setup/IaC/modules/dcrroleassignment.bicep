// Grants the automation account managed identity the Monitoring Metrics Publisher role on both DCRs.
// This is a separate module to avoid a circular dependency between the automationaccount and dcrdce modules
// (automationaccount needs DCR outputs; dcrdce cannot also depend on automationaccount).
// Role: Monitoring Metrics Publisher (3913510d-42f4-4e42-8a64-420c390055eb)

param dcrResourceId string
param dcrResourceId2 string
param automationAccountMSI string

var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'

resource dcr1 'Microsoft.Insights/dataCollectionRules@2024-03-11' existing = {
  name: last(split(dcrResourceId, '/'))
}

resource dcr2 'Microsoft.Insights/dataCollectionRules@2024-03-11' existing = {
  name: last(split(dcrResourceId2, '/'))
}

resource dcrRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dcrResourceId, automationAccountMSI, monitoringMetricsPublisherRoleId)
  scope: dcr1
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
    principalId: automationAccountMSI
    principalType: 'ServicePrincipal'
  }
}

resource dcrRoleAssignment2 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dcrResourceId2, automationAccountMSI, monitoringMetricsPublisherRoleId)
  scope: dcr2
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
    principalId: automationAccountMSI
    principalType: 'ServicePrincipal'
  }
}
