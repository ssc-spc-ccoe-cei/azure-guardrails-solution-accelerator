// Data Collection Endpoint (DCE) and Data Collection Rule (DCR) for DCR-based Log Ingestion API
// This module creates the infrastructure needed for migrating from Data Collector API to DCR-based ingestion

param location string
param logAnalyticsWorkspaceResourceId string
param dceName string = 'guardrails-dce'
param dcrName string = 'guardrails-dcr'
param releaseVersion string
param releaseDate string
param newDeployment bool = true
param updateCoreResources bool = false

// Data Collection Endpoint (DCE)
// Create/update DCE on new deployments or when updating core resources (for migration)
resource dataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2022-06-01' = if (newDeployment || updateCoreResources) {
  name: dceName
  location: location
  tags: {
    releaseVersion: releaseVersion
    releaseDate: releaseDate
  }
  kind: 'Logs'
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

// Data Collection Rule (DCR) - Maps custom log streams to Log Analytics workspace tables
// Create/update DCR on new deployments or when updating core resources (for migration)
resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2024-03-11' = if (newDeployment || updateCoreResources) {
  name: dcrName
  location: location
  tags: {
    releaseVersion: releaseVersion
    releaseDate: releaseDate
  }
  kind: 'Direct'
  properties: {
    dataCollectionEndpointId: dataCollectionEndpoint.id
    dataFlows: [
      // GuardrailsCompliance table
      {
        streams: [
          'Custom-GuardrailsCompliance'
        ]
        destinations: [
          'guardrails-law'
        ]
        transformKql: 'source'
        outputStream: 'Custom-GuardrailsCompliance_CL'
      }
      // GuardrailsComplianceException table
      {
        streams: [
          'Custom-GuardrailsComplianceException'
        ]
        destinations: [
          'guardrails-law'
        ]
        transformKql: 'source'
        outputStream: 'Custom-GuardrailsComplianceException_CL'
      }
      // GR_TenantInfo table
      {
        streams: [
          'Custom-GR_TenantInfo'
        ]
        destinations: [
          'guardrails-law'
        ]
        transformKql: 'source'
        outputStream: 'Custom-GR_TenantInfo_CL'
      }
      // GR_Results table
      {
        streams: [
          'Custom-GR_Results'
        ]
        destinations: [
          'guardrails-law'
        ]
        transformKql: 'source'
        outputStream: 'Custom-GR_Results_CL'
      }
      // GR_VersionInfo table
      {
        streams: [
          'Custom-GR_VersionInfo'
        ]
        destinations: [
          'guardrails-law'
        ]
        transformKql: 'source'
        outputStream: 'Custom-GR_VersionInfo_CL'
      }
      // GRITSGControls table
      {
        streams: [
          'Custom-GRITSGControls'
        ]
        destinations: [
          'guardrails-law'
        ]
        transformKql: 'source'
        outputStream: 'Custom-GRITSGControls_CL'
      }
      // GuardrailsTenantsCompliance table
      {
        streams: [
          'Custom-GuardrailsTenantsCompliance'
        ]
        destinations: [
          'guardrails-law'
        ]
        transformKql: 'source'
        outputStream: 'Custom-GuardrailsTenantsCompliance_CL'
      }
      // CaCDebugMetrics table
      {
        streams: [
          'Custom-CaCDebugMetrics'
        ]
        destinations: [
          'guardrails-law'
        ]
        transformKql: 'source'
        outputStream: 'Custom-CaCDebugMetrics_CL'
      }
      // GuardrailsUserRaw table
      {
        streams: [
          'Custom-GuardrailsUserRaw'
        ]
        destinations: [
          'guardrails-law'
        ]
        transformKql: 'source'
        outputStream: 'Custom-GuardrailsUserRaw_CL'
      }
      // GuardrailsCrossTenantAccess table
      {
        streams: [
          'Custom-GuardrailsCrossTenantAccess'
        ]
        destinations: [
          'guardrails-law'
        ]
        transformKql: 'source'
        outputStream: 'Custom-GuardrailsCrossTenantAccess_CL'
      }
      // GR2UsersWithoutGroups table
      {
        streams: [
          'Custom-GR2UsersWithoutGroups'
        ]
        destinations: [
          'guardrails-law'
        ]
        transformKql: 'source'
        outputStream: 'Custom-GR2UsersWithoutGroups_CL'
      }
      // GR2ExternalUsers table
      {
        streams: [
          'Custom-GR2ExternalUsers'
        ]
        destinations: [
          'guardrails-law'
        ]
        transformKql: 'source'
        outputStream: 'Custom-GR2ExternalUsers_CL'
      }
    ]
    destinations: {
      logAnalytics: [
        {
          name: 'guardrails-law'
          workspaceResourceId: logAnalyticsWorkspaceResourceId
        }
      ]
    }
    streamDeclarations: {
      'Custom-GuardrailsCompliance': {
        columns: []
      }
      'Custom-GuardrailsComplianceException': {
        columns: []
      }
      'Custom-GR_TenantInfo': {
        columns: []
      }
      'Custom-GR_Results': {
        columns: []
      }
      'Custom-GR_VersionInfo': {
        columns: []
      }
      'Custom-GRITSGControls': {
        columns: []
      }
      'Custom-GuardrailsTenantsCompliance': {
        columns: []
      }
      'Custom-CaCDebugMetrics': {
        columns: []
      }
      'Custom-GuardrailsUserRaw': {
        columns: []
      }
      'Custom-GuardrailsCrossTenantAccess': {
        columns: []
      }
      'Custom-GR2UsersWithoutGroups': {
        columns: []
      }
      'Custom-GR2ExternalUsers': {
        columns: []
      }
    }
  }
}

// Outputs
// Note: The logsIngestion endpoint is available in the DCE properties after deployment
// Format: https://<dce-name>.<region>.ingest.monitor.azure.com
output dceEndpoint string = (newDeployment || updateCoreResources) ? 'https://${dataCollectionEndpoint.name}.${location}.ingest.monitor.azure.com' : ''
output dcrImmutableId string = (newDeployment || updateCoreResources) ? dataCollectionRule.properties.immutableId : ''
output dceResourceId string = (newDeployment || updateCoreResources) ? dataCollectionEndpoint.id : ''
output dcrResourceId string = (newDeployment || updateCoreResources) ? dataCollectionRule.id : ''
