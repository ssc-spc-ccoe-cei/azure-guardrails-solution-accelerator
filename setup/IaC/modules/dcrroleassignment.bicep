// Grants the automation account managed identity:
//   - Reader on the DCE and both DCRs (for runtime ARM lookup of endpoint/stream metadata)
//   - Monitoring Metrics Publisher on both DCRs (for DCR-based log ingestion)
//   - Log Analytics Reader on the LAW workspace (for Invoke-AzOperationalInsightsQuery in runbooks)
// This is a separate module because the DCR resources and automation account MSI must both exist
// before these role assignments can be created.
// Role GUIDs:
//   Reader                       : acdd72a7-3385-48ef-bd42-f606fba81ae7
//   Monitoring Metrics Publisher : 3913510d-42f4-4e42-8a64-420c390055eb
//   Log Analytics Reader         : 73c42c96-874c-492b-b04d-ab87d138a893

param dceResourceId string
param dcrResourceId string
param dcrResourceId2 string
param automationAccountMSI string
param logAnalyticsWorkspaceResourceId string

var readerRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'
var logAnalyticsReaderRoleId = '73c42c96-874c-492b-b04d-ab87d138a893'

resource dce 'Microsoft.Insights/dataCollectionEndpoints@2022-06-01' existing = {
  name: last(split(dceResourceId, '/'))
}

resource dcr1 'Microsoft.Insights/dataCollectionRules@2024-03-11' existing = {
  name: last(split(dcrResourceId, '/'))
}

resource dcr2 'Microsoft.Insights/dataCollectionRules@2024-03-11' existing = {
  name: last(split(dcrResourceId2, '/'))
}

resource dceReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dceResourceId, automationAccountMSI, readerRoleId)
  scope: dce
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
    principalId: automationAccountMSI
    principalType: 'ServicePrincipal'
  }
}

resource dcrReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dcrResourceId, automationAccountMSI, readerRoleId)
  scope: dcr1
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
    principalId: automationAccountMSI
    principalType: 'ServicePrincipal'
  }
}

resource dcr2ReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dcrResourceId2, automationAccountMSI, readerRoleId)
  scope: dcr2
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
    principalId: automationAccountMSI
    principalType: 'ServicePrincipal'
  }
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

resource guardrailsLogAnalytics 'Microsoft.OperationalInsights/workspaces@2021-06-01' existing = {
  name: last(split(logAnalyticsWorkspaceResourceId, '/'))
}

resource lawReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logAnalyticsWorkspaceResourceId, automationAccountMSI, logAnalyticsReaderRoleId)
  scope: guardrailsLogAnalytics
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', logAnalyticsReaderRoleId)
    principalId: automationAccountMSI
    principalType: 'ServicePrincipal'
  }
}
