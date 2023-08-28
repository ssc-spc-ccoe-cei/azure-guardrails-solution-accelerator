param AllowedLocationPolicyId string
param automationAccountName string
param CBSSubscriptionName string
param containername string
param ModuleBaseURL string
param DepartmentNumber string
param DepartmentName string
param guardrailsKVname string
param guardrailsLogAnalyticscustomerId string
param guardrailsStoragename string
param HealthLAWResourceId string
param lighthouseTargetManagementGroupID string
param Locale string
param location string
param newDeployment bool = true
param PBMMPolicyID string
param releaseDate string
param releaseVersion string
param SecurityLAWResourceId string
param SSCReadOnlyServicePrincipalNameAPPID string
param TenantDomainUPN string
param updatePSModules bool = false
param updateCoreResources bool = false
param securityRetentionDays string
param cloudUsageProfiles string = 'default'

resource guardrailsAC 'Microsoft.Automation/automationAccounts@2021-06-22' = if (newDeployment || updatePSModules || updateCoreResources) {
  name: automationAccountName
  location: location
  tags: {
    releaseVersion:releaseVersion
    releasedate: releaseDate
  }
  identity: {
     type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: true
    disableLocalAuth: false
    sku: {
        name: 'Basic'
    }
    encryption: {
        keySource: 'Microsoft.Automation'
        identity: {}
    }
  }
  resource OMSModule 'modules' = if (newDeployment || updatePSModules) {
    name: 'OMSIngestionAPI'
    properties: {
      contentLink: {
        uri: 'https://devopsgallerystorage.blob.core.windows.net/packages/omsingestionapi.1.6.0.nupkg'
        version: '1.6.0'
      }
    }
  }
  resource module1 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-BreakGlassAccountOwnersInformation'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-BreakGlassAccountOwnersInformation.zip'
        version: '1.0.0'

      }
    }
  }
resource module2 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-BreakGlassAccountIdentityProtectionLicense'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-BreakGlassAccountIdentityProtectionLicense.zip'
        version: '1.0.0'
      }
    }
  }
resource module4 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-DeprecatedAccounts'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-DeprecatedAccounts.zip'
        version: '1.0.0'
      }
    }
  }
resource module5 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-ExternalAccounts'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-ExternalAccounts.zip'
        version: '1.0.0'
      }
    }
  }
resource module7 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-MonitorAccount'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-MonitorAccount.zip'
        version: '1.0.0'
      }
    }
  }
resource module8 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-PBMMPolicy'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-PBMMPolicy.zip'
        version: '1.0.0'
      }
    }
  }
resource module9 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-SubnetComplianceStatus'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-SubnetComplianceStatus.zip'
        version: '1.0.0'
      }
    }
  }
resource module10 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-VNetComplianceStatus'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-VNetComplianceStatus.zip'
        version: '1.0.0'
      }
    }
  }
resource module11 'modules' = if (newDeployment || updatePSModules) {
    name: 'Detect-UserBGAUsersAuthMethods'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Detect-UserBGAUsersAuthMethods.zip'
        version: '1.0.0'
      }
    }
  }
resource module12 'modules' = if (newDeployment || updatePSModules) {
    name: 'Get-AzureADLicenseType'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Get-AzureADLicenseType.zip'
        version: '1.0.0'
      }
    }
  }
resource module13 'modules' = if (newDeployment || updatePSModules) {
    name: 'GR-Common'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/GR-Common.zip'
        version: '1.1.2'
      }
    }
  }
resource module14 'modules' = if (newDeployment || updatePSModules) {
    name: 'Validate-BreakGlassAccount'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Validate-BreakGlassAccount.zip'
        version: '1.0.0'
      }
    }
  }
  resource module15 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-AllowedLocationPolicy'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-AllowedLocationPolicy.zip'
        version: '1.0.0'
      }
    }
  }
  resource module16 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-PrivateMarketPlace'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-PrivateMarketPlace.zip'
        version: '1.0.0'
      }
    }
  }
  resource module17 'modules' = if (newDeployment || updatePSModules) {
    name: 'Az.Marketplace'
    properties: {
      contentLink: {
        uri: 'https://devopsgallerystorage.blob.core.windows.net:443/packages/az.marketplace.0.3.0.nupkg'
        version: '0.3.0'
      }
    }
  }
  resource module19 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-CyberSecurityServices'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-CyberSecurityServices.zip'
        version: '1.0.0'
      }
    }
  }
  resource module20 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-DefenderForCloudConfig'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-DefenderForCloudConfig.zip'
        version: '1.0.0'
      }
    }
  }
  resource module21 'modules' = if (newDeployment || updatePSModules) {
    name: 'GR-ComplianceChecks'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/GR-ComplianceChecks.zip'
        version: '1.0.0'
      }
    }
  }
  resource module22 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-ProtectionDataAtRest'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-ProtectionDataAtRest.zip'
        version: '1.0.0'
      }
    }
  }
  resource module23 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-ProtectionOfDataInTransit'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-ProtectionOfDataInTransit.zip'
        version: '1.0.0'
      }
    }
  }
  resource module24 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-CloudConsoleAccess'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-CloudConsoleAccess.zip'
        version: '1.0.0'
      }
    }
  }
  resource module25 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-HealthMonitoring'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-HealthMonitoring.zip'
        version: '1.0.0'
      }
    }
  }
  resource module26 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-NetworkWatcherEnabled'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-NetworkWatcherEnabled.zip'
        version: '1.0.0'
      }
    }
  }
  resource module27 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-SecurityMonitoring'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-SecurityMonitoring.zip'
        version: '1.0.0'
      }
    }
  }
  resource module28 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-MFARequired'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-MFARequired.zip'
        version: '1.0.0'
      }
    }
  }
  resource module29 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-ServicePrincipal'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-ServicePrincipal.zip'
        version: '1.0.0'
      }
    }
  }
  resource module30 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-ServicePrincipalSecrets'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-ServicePrincipalSecrets.zip'
        version: '1.0.0'
      }
    }
  }
  resource variable1 'variables' = if (newDeployment || updateCoreResources) {
    name: 'KeyvaultName'
    properties: {
        isEncrypted: true
        value: '"${guardrailsKVname}"'
    }
  }
  resource variable2 'variables' = if (newDeployment || updateCoreResources) {
    name: 'WorkSpaceID'
    properties: {
        isEncrypted: true
        value: '"${guardrailsLogAnalyticscustomerId}"'
    }
  }
  resource variable3 'variables' = if (newDeployment || updateCoreResources) {
    name: 'LogType'
    properties: {
        isEncrypted: true
        value: '"GuardrailsCompliance"'
    }
  }
  resource variable4 'variables' = if (newDeployment || updateCoreResources) {
    name: 'PBMMPolicyID'
    properties: {
        isEncrypted: true
        value: '"/providers/Microsoft.Authorization/policySetDefinitions/${PBMMPolicyID}"'
    }
  }
  resource variable5 'variables' = if (newDeployment || updateCoreResources) {
    name: 'GuardrailWorkspaceIDKeyName'
    properties: {
        isEncrypted: true
        value: '"WorkSpaceKey"'
    }
  }
  resource variable6 'variables' = if (newDeployment || updateCoreResources) {
    name: 'StorageAccountName'
    properties: {
        isEncrypted: false
        value: '"${guardrailsStoragename}"'
    }
  }
  resource variable7 'variables' = if (newDeployment || updateCoreResources) {
    name: 'ContainerName'
    properties: {
        isEncrypted: true
        value: '"${containername}"'
    }
  }
  resource variable8 'variables' = if (newDeployment || updateCoreResources) {
    name: 'ResourceGroupName'
    properties: {
        isEncrypted: true
        value: '"${resourceGroup().name}"'
    }
  }
  resource variable9 'variables' = if (newDeployment || updateCoreResources) {
    name: 'AllowedLocationPolicyId'
    properties: {
        isEncrypted: true
        value: '"/providers/Microsoft.Authorization/policyDefinitions/${AllowedLocationPolicyId}"'
    }
  }
  resource variable10 'variables' = if (newDeployment || updateCoreResources) {
    name: 'DepartmentNumber'
    properties: {
      isEncrypted: true
      value: '"${DepartmentNumber}"'
  }
  }
  resource variable11 'variables' = if (newDeployment || updateCoreResources) {
    name: 'CBSSubscriptionName'
    properties: {
      isEncrypted: true
      value: '"${CBSSubscriptionName}"'
    }
  }
  resource variable12 'variables' = if (newDeployment || updateCoreResources) {
    name: 'SecurityLAWResourceId'
    properties: {
      isEncrypted: true
      value: '"${SecurityLAWResourceId}"'
    }
  }
  resource variable13 'variables' = if (newDeployment || updateCoreResources) {
    name: 'HealthLAWResourceId'
    properties: {
      isEncrypted: true
      value: '"${HealthLAWResourceId}"'
    }
  }
  resource variable14 'variables' = if (newDeployment || updateCoreResources) {
    name: 'TenantDomainUPN'
    properties: {
      isEncrypted: true
      value: '"${TenantDomainUPN}"'
    }
  }
  resource variable15 'variables' = if (newDeployment || updateCoreResources) {
    name: 'GuardRailsLocale'
    properties: {
      isEncrypted: true
      value: '"${Locale}"'
  }
  }

  resource variable16 'variables' = if (newDeployment || updateCoreResources) {
    name: 'lighthouseTargetManagementGroupID'
    'properties': {
      'isEncrypted': true
      'value': '"${lighthouseTargetManagementGroupID}"'
  }
  }

  resource variable17 'variables' = if (newDeployment || updateCoreResources) {
    name: 'DepartmentName'
    'properties': {
      'isEncrypted': true
      'value': '"${DepartmentName}"'
  }
  }
  resource variable18 'variables' = if (newDeployment || updateCoreResources) {
    name: 'reservedSubnetList'
    'properties': {
      'isEncrypted': true
      'value': '"GatewaySubnet,AzureFirewallSubnet,AzureBastionSubnet,AzureFirewallManagementSubnet,RouteServerSubnet"'
  }
  }
  
  resource variable19 'variables' = if (newDeployment || updateCoreResources) {
    name: 'SSCReadOnlyServicePrincipalNameAPPID'
    'properties': {
      'isEncrypted': true
      'value': '"${SSCReadOnlyServicePrincipalNameAPPID}"'
  }
  }
  resource variable20 'variables' = if (newDeployment || updateCoreResources) {
    name: 'securityRetentionDays'
    'properties': {
      'isEncrypted': true
      'value': '"${securityRetentionDays}"'
  }
  }
  resource variable21 'variables' = if (newDeployment || updateCoreResources) {
    name: 'cloudUsageProfiles'
    'properties': {
      'isEncrypted': true
      'value': '"${cloudUsageProfiles}"'
  }
  }
}
output guardrailsAutomationAccountMSI string = guardrailsAC.identity.principalId
