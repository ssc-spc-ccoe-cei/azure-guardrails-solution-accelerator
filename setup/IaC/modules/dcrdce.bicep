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

// DCR allows max 10 data flows per rule; we have 12 tables so use two DCRs (10 + 2).
// Stream declarations require at least one column (e.g. RawData string for custom JSON).

// DCR 1: first 10 custom log streams
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
      { 
        streams: ['Custom-GuardrailsCompliance'] 
        destinations: ['guardrails-law'] 
        transformKql: 'source' 
        outputStream: 'Custom-GuardrailsCompliance_CL' 
      }
      { 
        streams: ['Custom-GuardrailsComplianceException'] 
        destinations: ['guardrails-law'] 
        transformKql: 'source' 
        outputStream: 'Custom-GuardrailsComplianceException_CL' 
      }
      { 
        streams: ['Custom-GR_TenantInfo'] 
        destinations: ['guardrails-law'] 
        transformKql: 'source' 
        outputStream: 'Custom-GR_TenantInfo_CL' 
      }
      { 
        streams: ['Custom-GR_Results'] 
        destinations: ['guardrails-law'] 
        transformKql: 'source' 
        outputStream: 'Custom-GR_Results_CL' 
      }
      { 
        streams: ['Custom-GR_VersionInfo'] 
        destinations: ['guardrails-law'] 
        transformKql: 'source' 
        outputStream: 'Custom-GR_VersionInfo_CL' 
      }
      { 
        streams: ['Custom-GRITSGControls'] 
        destinations: ['guardrails-law'] 
        transformKql: 'source' 
        outputStream: 'Custom-GRITSGControls_CL' 
      }
      { 
        streams: ['Custom-GuardrailsTenantsCompliance'] 
        destinations: ['guardrails-law'] 
        transformKql: 'source' 
        outputStream: 'Custom-GuardrailsTenantsCompliance_CL' 
      }
      { 
        streams: ['Custom-CaCDebugMetrics'] 
        destinations: ['guardrails-law'] 
        transformKql: 'source' 
        outputStream: 'Custom-CaCDebugMetrics_CL' 
      }
      { 
        streams: ['Custom-GuardrailsUserRaw'] 
        destinations: ['guardrails-law'] 
        transformKql: 'source' 
        outputStream: 'Custom-GuardrailsUserRaw_CL' 
      }
      { 
        streams: ['Custom-GuardrailsCrossTenantAccess'] 
        destinations: ['guardrails-law'] 
        transformKql: 'source' 
        outputStream: 'Custom-GuardrailsCrossTenantAccess_CL' 
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
        columns: [
          { 
            name: 'RawData' 
            type: 'string' 
          }
        ] 
      }
      'Custom-GuardrailsComplianceException': { 
        columns: [
          { 
            name: 'RawData' 
            type: 'string' 
          }
        ] 
      }
      'Custom-GR_TenantInfo': { 
        columns: [
          { 
            name: 'RawData' 
            type: 'string' 
          }
        ] 
      }
      'Custom-GR_Results': { 
        columns: [
          { 
            name: 'RawData' 
            type: 'string' 
          }
        ] 
      }
      'Custom-GR_VersionInfo': { 
        columns: [
          { 
            name: 'RawData' 
            type: 'string' 
          }
        ] 
      }
      'Custom-GRITSGControls': { 
        columns: [
          { 
            name: 'RawData' 
            type: 'string' 
          }
        ] 
      }
      'Custom-GuardrailsTenantsCompliance': { 
        columns: [
          { 
            name: 'RawData' 
            type: 'string' 
          }
        ] 
      }
      'Custom-CaCDebugMetrics': { 
        columns: [
          { 
            name: 'RawData' 
            type: 'string' 
          }
        ] 
      }
      'Custom-GuardrailsUserRaw': { 
        columns: [
          { 
            name: 'RawData' 
            type: 'string' 
          }
        ] 
      }
      'Custom-GuardrailsCrossTenantAccess': { 
        columns: [
          { 
            name: 'RawData' 
            type: 'string' 
          }
        ] 
      }
    }
  }
}

// DCR 2: remaining 2 streams (API limit 10 flows per DCR)
resource dataCollectionRule2 'Microsoft.Insights/dataCollectionRules@2024-03-11' = if (newDeployment || updateCoreResources) {
  name: '${dcrName}-2'
  location: location
  tags: {
    releaseVersion: releaseVersion
    releaseDate: releaseDate
  }
  kind: 'Direct'
  properties: {
    dataCollectionEndpointId: dataCollectionEndpoint.id
    dataFlows: [
      { 
        streams: ['Custom-GR2UsersWithoutGroups'] 
        destinations: ['guardrails-law'] 
        transformKql: 'source' 
        outputStream: 'Custom-GR2UsersWithoutGroups_CL' 
      }
      { 
        streams: ['Custom-GR2ExternalUsers'] 
        destinations: ['guardrails-law'] 
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
      'Custom-GR2UsersWithoutGroups': { 
        columns: [
          { 
            name: 'RawData' 
            type: 'string' 
          }
        ] 
      }
      'Custom-GR2ExternalUsers': { 
        columns: [
          { 
            name: 'RawData' 
            type: 'string' 
          }
        ] 
      }
    }
  }
}

// Outputs
output dceEndpoint string = (newDeployment || updateCoreResources) ? 'https://${dataCollectionEndpoint.name}.${location}.ingest.monitor.azure.com' : ''
output dcrImmutableId string = (newDeployment || updateCoreResources) ? dataCollectionRule.properties.immutableId : ''
output dcrImmutableId2 string = (newDeployment || updateCoreResources) ? dataCollectionRule2.properties.immutableId : ''
output dceResourceId string = (newDeployment || updateCoreResources) ? dataCollectionEndpoint.id : ''
output dcrResourceId string = (newDeployment || updateCoreResources) ? dataCollectionRule.id : ''
