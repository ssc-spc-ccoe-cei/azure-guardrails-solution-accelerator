// Assigns Monitoring Metrics Publisher on the CentralView DCR so Invoke-AzRestMethod / Send-GuardrailsData
// can ingest when using the aggregation service principal from Key Vault ApplicationId / SecurePassword.
// Role GUID aligns with modules/dcrroleassignment.bicep in the main accelerator.
param dcrResourceId string
param principalId string // Entra ID object id of the service principal (from Get-AzADServicePrincipal.Id)

var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'

resource centralDcr 'Microsoft.Insights/dataCollectionRules@2024-03-11' existing = {
  name: last(split(dcrResourceId, '/'))
}

resource centralDcrMonitoringMetricsPublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dcrResourceId, principalId, monitoringMetricsPublisherRoleId)
  scope: centralDcr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
