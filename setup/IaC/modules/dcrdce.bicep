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
        transformKql: 'source | extend ControlName_s = tostring(ControlName), ItemName_s = tostring(ItemName), ComplianceStatus_b = tobool(ComplianceStatus), Comments_s = tostring(Comments), ReportTime_s = tostring(ReportTime), itsgcode_s = tostring(itsgcode), Required_s = tostring(Required), Profile_d = todouble(Profile), DisplayName_s = tostring(DisplayName), SubscriptionName_s = tostring(SubscriptionName), VNETName_s = tostring(VNETName) | project TimeGenerated, ControlName_s, ItemName_s, ComplianceStatus_b, Comments_s, ReportTime_s, itsgcode_s, Required_s, Profile_d, DisplayName_s, SubscriptionName_s, VNETName_s'
        outputStream: 'Custom-GuardrailsCompliance_CL'
      }
      {
        streams: ['Custom-GuardrailsComplianceException']
        destinations: ['guardrails-law']
        transformKql: 'source | extend ControlName_s = tostring(ControlName), ItemName_s = tostring(ItemName), ComplianceStatus_b = tobool(ComplianceStatus), Comments_s = tostring(Comments), ReportTime_s = tostring(ReportTime) | project TimeGenerated, ControlName_s, ItemName_s, ComplianceStatus_b, Comments_s, ReportTime_s'
        outputStream: 'Custom-GuardrailsComplianceException_CL'
      }
      {
        streams: ['Custom-GR_TenantInfo']
        destinations: ['guardrails-law']
        transformKql: 'source | extend TenantDomain_s = tostring(TenantDomain), DepartmentTenantID_s = tostring(DepartmentTenantID), DepartmentTenantName_s = tostring(DepartmentTenantName), ReportTime_s = tostring(ReportTime), DepartmentName_s = tostring(DepartmentName), DepartmentNumber_s = tostring(DepartmentNumber), cloudUsageProfiles_s = tostring(cloudUsageProfiles), Locale_s = tostring(Locale) | project TimeGenerated, TenantDomain_s, DepartmentTenantID_s, DepartmentTenantName_s, ReportTime_s, DepartmentName_s, DepartmentNumber_s, cloudUsageProfiles_s, Locale_s'
        outputStream: 'Custom-GR_TenantInfo_CL'
      }
      {
        streams: ['Custom-GR_Results']
        destinations: ['guardrails-law']
        transformKql: 'source | extend ControlName_s = tostring(ControlName), ItemName_s = tostring(ItemName), ComplianceStatus_b = tobool(ComplianceStatus), Comments_s = tostring(Comments), ReportTime_s = tostring(ReportTime), itsgcode_s = tostring(itsgcode), Required_s = tostring(Required), Profile_d = todouble(Profile), DisplayName_s = tostring(DisplayName), SubscriptionName_s = tostring(SubscriptionName), VNETName_s = tostring(VNETName) | project TimeGenerated, ControlName_s, ItemName_s, ComplianceStatus_b, Comments_s, ReportTime_s, itsgcode_s, Required_s, Profile_d, DisplayName_s, SubscriptionName_s, VNETName_s'
        outputStream: 'Custom-GR_Results_CL'
      }
      {
        streams: ['Custom-GR_VersionInfo']
        destinations: ['guardrails-law']
        transformKql: 'source | extend CurrentVersion_s = tostring(DeployedVersion), AvailableVersion_s = tostring(AvailableVersion), ReportTime_s = tostring(ReportTime), UpdateNeeded_b = tobool(UpdateNeeded) | project TimeGenerated, CurrentVersion_s, AvailableVersion_s, ReportTime_s, UpdateNeeded_b'
        outputStream: 'Custom-GR_VersionInfo_CL'
      }
      {
        streams: ['Custom-GRITSGControls']
        destinations: ['guardrails-law']
        transformKql: 'source | extend Name_s = tostring(Name), Definition_s = tostring(Definition), itsgcode_s = tostring(itsgcode) | project TimeGenerated, Name_s, Definition_s, itsgcode_s'
        outputStream: 'Custom-GRITSGControls_CL'
      }
      {
        streams: ['Custom-GuardrailsTenantsCompliance']
        destinations: ['guardrails-law']
        transformKql: 'source | extend ControlName_s = tostring(ControlName), ItemName_s = tostring(ItemName), ComplianceStatus_b = tobool(ComplianceStatus), Comments_s = tostring(Comments), ReportTime_s = tostring(ReportTime), itsgcode_s = tostring(itsgcode), Required_s = tostring(Required), Profile_d = todouble(Profile), DisplayName_s = tostring(DisplayName), SubscriptionName_s = tostring(SubscriptionName), VNETName_s = tostring(VNETName) | project TimeGenerated, ControlName_s, ItemName_s, ComplianceStatus_b, Comments_s, ReportTime_s, itsgcode_s, Required_s, Profile_d, DisplayName_s, SubscriptionName_s, VNETName_s'
        outputStream: 'Custom-GuardrailsTenantsCompliance_CL'
      }
      {
        streams: ['Custom-CaCDebugMetrics']
        destinations: ['guardrails-law']
        transformKql: 'source | extend GuardrailId_s = tostring(GuardrailId), RunbookName_s = tostring(RunbookName), ModuleName_s = tostring(ModuleName), ExecutionScope_s = tostring(ExecutionScope), EventType_s = tostring(EventType), CorrelationId_s = tostring(CorrelationId), JobId_s = tostring(JobId), RunSubscriptionId_s = tostring(RunSubscriptionId), RunTenantId_s = tostring(RunTenantId), ErrorCount_d = todouble(ErrorCount), ItemCount_d = todouble(ItemCount), CompliantCount_d = todouble(CompliantCount), NonCompliantCount_d = todouble(NonCompliantCount), DurationMsReal_d = todouble(DurationMsReal), ReportTime_s = tostring(ReportTime), Message_s = tostring(Message) | project TimeGenerated, GuardrailId_s, RunbookName_s, ModuleName_s, ExecutionScope_s, EventType_s, CorrelationId_s, JobId_s, RunSubscriptionId_s, RunTenantId_s, ErrorCount_d, ItemCount_d, CompliantCount_d, NonCompliantCount_d, DurationMsReal_d, ReportTime_s, Message_s'
        outputStream: 'Custom-CaCDebugMetrics_CL'
      }
      {
        streams: ['Custom-GuardrailsUserRaw']
        destinations: ['guardrails-law']
        transformKql: 'source | extend userPrincipalName_s = tostring(userPrincipalName), displayName_s = tostring(displayName), mail_s = tostring(mail), createdDateTime_s = tostring(createdDateTime), userType_s = tostring(userType), homeTenantId_s = tostring(homeTenantId), homeTenantResolved_b = tobool(homeTenantResolved), accountEnabled_b = tobool(accountEnabled), guardrailsExcludedMfa_b = tobool(guardrailsExcludedMfa), isMfaRegistered_b = tobool(isMfaRegistered), isMfaCapable_b = tobool(isMfaCapable), isSsprEnabled_b = tobool(isSsprEnabled), isSsprRegistered_b = tobool(isSsprRegistered), isSsprCapable_b = tobool(isSsprCapable), isPasswordlessCapable_b = tobool(isPasswordlessCapable), defaultMethod_s = tostring(defaultMethod), isSystemPreferredAuthenticationMethodEnabled_b = tobool(isSystemPreferredAuthenticationMethodEnabled), userPreferredMethodForSecondaryAuthentication_s = tostring(userPreferredMethodForSecondaryAuthentication), ReportTime_s = tostring(ReportTime) | project TimeGenerated, userPrincipalName_s, displayName_s, mail_s, createdDateTime_s, userType_s, homeTenantId_s, homeTenantResolved_b, accountEnabled_b, guardrailsExcludedMfa_b, isMfaRegistered_b, isMfaCapable_b, isSsprEnabled_b, isSsprRegistered_b, isSsprCapable_b, isPasswordlessCapable_b, defaultMethod_s, isSystemPreferredAuthenticationMethodEnabled_b, userPreferredMethodForSecondaryAuthentication_s, ReportTime_s'
        outputStream: 'Custom-GuardrailsUserRaw_CL'
      }
      {
        streams: ['Custom-GuardrailsCrossTenantAccess']
        destinations: ['guardrails-law']
        transformKql: 'source | extend ReportTime_s = tostring(ReportTime), PartnerTenantId_s = tostring(PartnerTenantId), InboundTrustMfa_b = tobool(InboundTrustMfa), InboundTrustCompliantDevice_b = tobool(InboundTrustCompliantDevice), InboundTrustHybridAzureADJoined_b = tobool(InboundTrustHybridAzureADJoined), IsDefault_b = tobool(IsDefault), HasGuestMfaPolicy_b = tobool(HasGuestMfaPolicy) | project TimeGenerated, ReportTime_s, PartnerTenantId_s, InboundTrustMfa_b, InboundTrustCompliantDevice_b, InboundTrustHybridAzureADJoined_b, IsDefault_b, HasGuestMfaPolicy_b'
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
            name: 'TimeGenerated'
            type: 'datetime'
          }
          {
            name: 'ControlName'
            type: 'string'
          }
          {
            name: 'ItemName'
            type: 'string'
          }
          {
            name: 'ComplianceStatus'
            type: 'dynamic'
          }
          {
            name: 'DocumentName'
            type: 'string'
          }
          {
            name: 'Comments'
            type: 'string'
          }
          {
            name: 'ReportTime'
            type: 'string'
          }
          {
            name: 'itsgcode'
            type: 'string'
          }
          {
            name: 'Required'
            type: 'string'
          }
          {
            name: 'Profile'
            type: 'real'
          }
          {
            name: 'DisplayName'
            type: 'string'
          }
          {
            name: 'SubscriptionName'
            type: 'string'
          }
          {
            name: 'VNETName'
            type: 'string'
          }
        ]
      }
      'Custom-GuardrailsComplianceException': {
        columns: [
          {
            name: 'TimeGenerated'
            type: 'datetime'
          }
          {
            name: 'ControlName'
            type: 'string'
          }
          {
            name: 'ItemName'
            type: 'string'
          }
          {
            name: 'ComplianceStatus'
            type: 'dynamic'
          }
          {
            name: 'Comments'
            type: 'string'
          }
          {
            name: 'ReportTime'
            type: 'string'
          }
        ]
      }
      'Custom-GR_TenantInfo': {
        columns: [
          {
            name: 'TimeGenerated'
            type: 'datetime'
          }
          {
            name: 'TenantDomain'
            type: 'string'
          }
          {
            name: 'DepartmentTenantID'
            type: 'string'
          }
          {
            name: 'DepartmentTenantName'
            type: 'string'
          }
          {
            name: 'ReportTime'
            type: 'string'
          }
          {
            name: 'DepartmentName'
            type: 'string'
          }
          {
            name: 'DepartmentNumber'
            type: 'string'
          }
          {
            name: 'cloudUsageProfiles'
            type: 'string'
          }
          {
            name: 'Locale'
            type: 'string'
          }
        ]
      }
      'Custom-GR_Results': {
        columns: [
          {
            name: 'TimeGenerated'
            type: 'datetime'
          }
          {
            name: 'ControlName'
            type: 'string'
          }
          {
            name: 'ItemName'
            type: 'string'
          }
          {
            name: 'ComplianceStatus'
            type: 'dynamic'
          }
          {
            name: 'Comments'
            type: 'string'
          }
          {
            name: 'ReportTime'
            type: 'string'
          }
          {
            name: 'itsgcode'
            type: 'string'
          }
          {
            name: 'Required'
            type: 'string'
          }
          {
            name: 'Profile'
            type: 'real'
          }
          {
            name: 'DisplayName'
            type: 'string'
          }
          {
            name: 'SubscriptionName'
            type: 'string'
          }
          {
            name: 'VNETName'
            type: 'string'
          }
        ]
      }
      'Custom-GR_VersionInfo': {
        columns: [
          {
            name: 'TimeGenerated'
            type: 'datetime'
          }
          {
            name: 'DeployedVersion'
            type: 'string'
          }
          {
            name: 'AvailableVersion'
            type: 'string'
          }
          {
            name: 'UpdateNeeded'
            type: 'boolean'
          }
          {
            name: 'ReportTime'
            type: 'string'
          }
        ]
      }
      'Custom-GRITSGControls': {
        columns: [
          {
            name: 'TimeGenerated'
            type: 'datetime'
          }
          {
            name: 'Name'
            type: 'string'
          }
          {
            name: 'Definition'
            type: 'string'
          }
          {
            name: 'itsgcode'
            type: 'string'
          }
        ]
      }
      'Custom-GuardrailsTenantsCompliance': {
        columns: [
          {
            name: 'TimeGenerated'
            type: 'datetime'
          }
          {
            name: 'ControlName'
            type: 'string'
          }
          {
            name: 'ItemName'
            type: 'string'
          }
          {
            name: 'ComplianceStatus'
            type: 'dynamic'
          }
          {
            name: 'Comments'
            type: 'string'
          }
          {
            name: 'ReportTime'
            type: 'string'
          }
          {
            name: 'itsgcode'
            type: 'string'
          }
          {
            name: 'Required'
            type: 'string'
          }
          {
            name: 'Profile'
            type: 'real'
          }
          {
            name: 'DisplayName'
            type: 'string'
          }
          {
            name: 'SubscriptionName'
            type: 'string'
          }
          {
            name: 'VNETName'
            type: 'string'
          }
        ]
      }
      'Custom-CaCDebugMetrics': {
        columns: [
          {
            name: 'TimeGenerated'
            type: 'datetime'
          }
          {
            name: 'GuardrailId'
            type: 'string'
          }
          {
            name: 'RunbookName'
            type: 'string'
          }
          {
            name: 'ModuleName'
            type: 'string'
          }
          {
            name: 'ExecutionScope'
            type: 'string'
          }
          {
            name: 'EventType'
            type: 'string'
          }
          {
            name: 'CorrelationId'
            type: 'string'
          }
          {
            name: 'JobId'
            type: 'string'
          }
          {
            name: 'RunSubscriptionId'
            type: 'string'
          }
          {
            name: 'RunTenantId'
            type: 'string'
          }
          {
            name: 'ErrorCount'
            type: 'real'
          }
          {
            name: 'ItemCount'
            type: 'real'
          }
          {
            name: 'CompliantCount'
            type: 'real'
          }
          {
            name: 'NonCompliantCount'
            type: 'real'
          }
          {
            name: 'DurationMsReal'
            type: 'real'
          }
          {
            name: 'MemoryStartMb'
            type: 'real'
          }
          {
            name: 'MemoryEndMb'
            type: 'real'
          }
          {
            name: 'MemoryPeakMb'
            type: 'real'
          }
          {
            name: 'MemoryDeltaMb'
            type: 'real'
          }
          {
            name: 'ReportTime'
            type: 'string'
          }
          {
            name: 'Message'
            type: 'string'
          }
        ]
      }
      'Custom-GuardrailsUserRaw': {
        columns: [
          {
            name: 'TimeGenerated'
            type: 'datetime'
          }
          {
            name: 'id'
            type: 'string'
          }
          {
            name: 'userPrincipalName'
            type: 'string'
          }
          {
            name: 'displayName'
            type: 'string'
          }
          {
            name: 'mail'
            type: 'string'
          }
          {
            name: 'createdDateTime'
            type: 'string'
          }
          {
            name: 'userType'
            type: 'string'
          }
          {
            name: 'homeTenantId'
            type: 'string'
          }
          {
            name: 'homeTenantResolved'
            type: 'boolean'
          }
          {
            name: 'accountEnabled'
            type: 'boolean'
          }
          {
            name: 'guardrailsExcludedMfa'
            type: 'boolean'
          }
          {
            name: 'isMfaRegistered'
            type: 'boolean'
          }
          {
            name: 'isMfaCapable'
            type: 'boolean'
          }
          {
            name: 'isSsprEnabled'
            type: 'boolean'
          }
          {
            name: 'isSsprRegistered'
            type: 'boolean'
          }
          {
            name: 'isSsprCapable'
            type: 'boolean'
          }
          {
            name: 'isPasswordlessCapable'
            type: 'boolean'
          }
          {
            name: 'defaultMethod'
            type: 'string'
          }
          {
            name: 'isSystemPreferredAuthenticationMethodEnabled'
            type: 'boolean'
          }
          {
            name: 'userPreferredMethodForSecondaryAuthentication'
            type: 'string'
          }
          {
            name: 'ReportTime'
            type: 'string'
          }
        ]
      }
      'Custom-GuardrailsCrossTenantAccess': {
        columns: [
          {
            name: 'TimeGenerated'
            type: 'datetime'
          }
          {
            name: 'ReportTime'
            type: 'string'
          }
          {
            name: 'PartnerTenantId'
            type: 'string'
          }
          {
            name: 'InboundTrustMfa'
            type: 'boolean'
          }
          {
            name: 'InboundTrustCompliantDevice'
            type: 'boolean'
          }
          {
            name: 'InboundTrustHybridAzureADJoined'
            type: 'boolean'
          }
          {
            name: 'IsDefault'
            type: 'boolean'
          }
          {
            name: 'HasGuestMfaPolicy'
            type: 'boolean'
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
            name: 'TimeGenerated' 
            type: 'datetime' 
          }
          { 
            name: 'RawData' 
            type: 'string' 
          }
        ]
      }
      'Custom-GR2ExternalUsers': {
        columns: [
          { 
            name: 'TimeGenerated' 
            type: 'datetime' 
          }
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
output dceEndpoint string = (newDeployment || updateCoreResources) ? dataCollectionEndpoint.properties.logsIngestion.endpoint : ''
output dcrImmutableId string = (newDeployment || updateCoreResources) ? dataCollectionRule.properties.immutableId : ''
output dcrImmutableId2 string = (newDeployment || updateCoreResources) ? dataCollectionRule2.properties.immutableId : ''
output dceResourceId string = (newDeployment || updateCoreResources) ? dataCollectionEndpoint.id : ''
output dcrResourceId string = (newDeployment || updateCoreResources) ? dataCollectionRule.id : ''
output dcrResourceId2 string = (newDeployment || updateCoreResources) ? dataCollectionRule2.id : ''
