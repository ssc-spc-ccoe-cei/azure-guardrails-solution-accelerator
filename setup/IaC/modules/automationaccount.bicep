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
      contentLink: retryModuleImport('https://devopsgallerystorage.blob.core.windows.net/packages/omsingestionapi.1.6.0.nupkg', '1.6.0')
    }
  }
  resource module1 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-BreakGlassAccountOwnersInformation'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Check-BreakGlassAccountOwnersInformation.zip', '1.0.0')
      }
  }
resource module2 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-BreakGlassAccountIdentityProtectionLicense'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Check-BreakGlassAccountIdentityProtectionLicense.zip', '1.0.0')
    }
}
resource module4 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-DeprecatedAccounts'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Check-DeprecatedAccounts.zip', '1.0.0')
    }
}
resource module5 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-ExternalAccounts'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Check-ExternalAccounts.zip', '1.0.0')
    }
}
resource module7 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-MonitorAccount'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Check-MonitorAccount.zip', '1.0.0')
    }
  }
resource module8 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-PBMMPolicy'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Check-PBMMPolicy.zip', '1.0.0')
    }
  }
resource module9 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-SubnetComplianceStatus'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Check-SubnetComplianceStatus.zip', '1.0.0')
    }
  }
resource module10 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-VNetComplianceStatus'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Check-VNetComplianceStatus.zip', '1.0.0')
    }
  }
resource module11 'modules' = if (newDeployment || updatePSModules) {
    name: 'Detect-UserBGAUsersAuthMethods'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Detect-UserBGAUsersAuthMethods.zip', '1.0.0')
    }
  }
resource module12 'modules' = if (newDeployment || updatePSModules) {
    name: 'Get-AzureADLicenseType'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Get-AzureADLicenseType.zip', '1.0.0')
    }
  }
resource module13 'modules' = if (newDeployment || updatePSModules) {
    name: 'GR-Common'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/GR-Common.zip', '1.0.0')
    }
  }
resource module14 'modules' = if (newDeployment || updatePSModules) {
    name: 'Validate-BreakGlassAccount'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Validate-BreakGlassAccount.zip', '1.0.0')
    }
  }
  resource module15 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-AllowedLocationPolicy'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Check-AllowedLocationPolicy.zip', '1.0.0')
    }
  }
  resource module16 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-PrivateMarketPlace'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Check-PrivateMarketPlace.zip', '1.0.0')
    }
  }
  resource module17 'modules' = if (newDeployment || updatePSModules) {
    name: 'Az.Marketplace'
    properties: {
      contentLink: retryModuleImport('https://devopsgallerystorage.blob.core.windows.net:443/packages/az.marketplace.0.3.0.nupkg', '1.0.0')
    }
  }
  resource module19 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-CyberSecurityServices'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Check-CyberSecurityServices.zip', '1.0.0')
    }
  }
  resource module20 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-DefenderForCloudConfig'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Check-DefenderForCloudConfig.zip', '1.0.0')
    }
  }
  resource module21 'modules' = if (newDeployment || updatePSModules) {
    name: 'GR-ComplianceChecks'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/GR-ComplianceChecks.zip', '1.0.0')
    }
  }
  resource module22 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-ProtectionDataAtRest'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Check-ProtectionDataAtRest.zip', '1.0.0')
    }
  }
  resource module23 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-ProtectionOfDataInTransit'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Check-ProtectionOfDataInTransit.zip', '1.0.0')
    }
  }
  resource module24 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-CloudConsoleAccess'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Check-CloudConsoleAccess.zip', '1.0.0')
    }
  }
  resource module25 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-HealthMonitoring'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Check-HealthMonitoring.zip', '1.0.0')
    }
  }
  resource module26 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-NetworkWatcherEnabled'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Check-NetworkWatcherEnabled.zip', '1.0.0')
    }
  }
  resource module27 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-SecurityMonitoring'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Check-SecurityMonitoring.zip', '1.0.0')
    }
  }
  resource module28 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-MFARequired'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Check-MFARequired.zip', '1.0.0')
    }
  }
  resource module29 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-ServicePrincipal'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Check-ServicePrincipal.zip', '1.0.0')
    }
  }
  resource module30 'modules' = if (newDeployment || updatePSModules) {
    name: 'Check-ServicePrincipalSecrets'
    properties: {
      contentLink: retryModuleImport('${ModuleBaseURL}/Check-ServicePrincipalSecrets.zip', '1.0.0')
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

function retryModuleImport(uri: string, version: string) = {
  // Retry logic
  for retryCount in range(0, maxRetries) {
    var result = {
      uri: uri,
      version: version
    };

    if (retryCount < maxRetries) {
      delay(delayBetweenRetries);
    } else {
      break;
    }
  }

  result
}


output guardrailsAutomationAccountMSI string = guardrailsAC.identity.principalId
