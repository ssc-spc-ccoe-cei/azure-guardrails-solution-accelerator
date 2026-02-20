param AllowedLocationPolicyId string
param AllowedLocationInitiativeId string
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
param dceEndpoint string = ''
param dcrImmutableId string = ''

resource guardrailsAC 'Microsoft.Automation/automationAccounts@2023-11-01' = if (newDeployment || updatePSModules || updateCoreResources) {
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
  resource OMSModule 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'OMSIngestionAPI'
    properties: {
      contentLink: {
        uri: 'https://devopsgallerystorage.blob.core.windows.net/packages/omsingestionapi.1.6.0.nupkg'
        version: '1.6.0'
      }}
  }
  resource module1 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-BreakGlassAccountOwnersInformation'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-BreakGlassAccountOwnersInformation.zip'
        version: '1.1.9'        
      }}
  }
  resource module2 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-BreakGlassAccountIdentityProtectionLicense'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-BreakGlassAccountIdentityProtectionLicense.zip'
        version: '1.2.0'
      }}
  }
  resource module3 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-DeprecatedAccounts'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-DeprecatedAccounts.zip'
        version: '1.2.6'
      }}
  }
  resource module4 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-ExternalAccounts'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-ExternalAccounts.zip'
        version: '1.2.10'
      }}
  }
  resource module5 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-PrivilegedExternalAccounts'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-PrivilegedExternalAccounts.zip'
        version: '1.0.7'
      }}
  }
  resource module7 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-SubnetComplianceStatus'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-SubnetComplianceStatus.zip'
        version: '1.1.13'
      }}
  }
  resource module8 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-VNetComplianceStatus'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-VNetComplianceStatus.zip'
        version: '1.1.12'
      }}
  }
  resource module9 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Detect-UserBGAUsersAuthMethods'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Detect-UserBGAUsersAuthMethods.zip'
        version: '1.2.8'
      }}
  }
  resource module10 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Get-AzureADLicenseType'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Get-AzureADLicenseType.zip'
        version: '1.1.11'
      }
    }
  }
  resource module11 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'GR-Common'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/GR-Common.zip'
        version: '1.4.3'
      }}
  }
  resource module12 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Validate-BreakGlassAccount'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Validate-BreakGlassAccount.zip'
        version: '1.1.0'
      }}
  }
  resource module13 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-AllowedLocationPolicy'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-AllowedLocationPolicy.zip'
        version: '1.2.3'
      }
    }
  }
  resource module14 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-PrivateMarketPlace'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-PrivateMarketPlace.zip'
        version: '1.1.9'
      }}
  }
  resource module15 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Az.Marketplace'
    properties: {
      contentLink: {
        uri: 'https://devopsgallerystorage.blob.core.windows.net:443/packages/az.marketplace.0.3.0.nupkg'
        version: '0.3.0'
      }}
  }
  resource module16 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-CyberSecurityServices'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-CyberSecurityServices.zip'
        version: '1.1.8'
      }
    }
  }
  resource module18 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'GR-ComplianceChecks'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/GR-ComplianceChecks.zip'
        version: '1.4.17'
      }}
  }
  resource module19 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-ProtectionDataAtRest'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-ProtectionDataAtRest.zip'
        version: '1.3.8'
      }}
  }
  resource module20 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-SecureConnectionInTransit'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-SecureConnectionInTransit.zip'
        version: '1.2.13'
      }}
  }
  resource module21 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-CloudConsoleAccess'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-CloudConsoleAccess.zip'
        version: '1.0.10'
      }}
  }
  resource module23 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-NetworkWatcherEnabled'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-NetworkWatcherEnabled.zip'
        version: '1.0.8'
      }}
  }
  resource module26 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-ServicePrincipal'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-ServicePrincipal.zip'
        version: '1.3.5'
      }}
  }
  resource module27 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-ServicePrincipalSecrets'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-ServicePrincipalSecrets.zip'
        version: '1.0.4'
      }}
  }
  resource module28 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-AllUserMFARequired'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-AllUserMFARequired.zip'
        version: '1.0.10'
      }}
  }
  resource module29 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-GAUserCountMFARequired'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-GAUserCountMFARequired.zip'
        version: '1.0.7'
      }
    }
  }
  resource module30 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-AdminAccess'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-AdminAccess.zip'
        version: '1.0.6'
      }}
  }
  resource module31 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-UserAccountGCEventLogging'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-UserAccountGCEventLogging.zip'
        version: '1.0.7'
      }}
  }
  resource module32 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-UserGroups'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-UserGroups.zip'
        version: '1.0.6'
      }
    }
  }
  resource module33 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-OnlineAttackCountermeasures'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-OnlineAttackCountermeasures.zip'
        version: '1.0.5'
      }
    }
  }

  resource module34 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-ApplicationGatewayCertificateValidity'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-ApplicationGatewayCertificateValidity.zip'
        version: '1.0.5'
      }}
  }
        
  resource module35 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-CloudAccountsMFA'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-CloudAccountsMFA.zip'
        version: '1.0.3'
      }
    }
  }

  resource module36 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-DedicatedAdminAccounts'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-DedicatedAdminAccounts.zip'
        version: '1.0.9'
      }
    }
  }

  // Splitting Module37
  resource module37a 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-UserRiskBasedCAP'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-UserRiskBasedCAP.zip'
        version: '1.0.2'
      }
    }
  }

  resource module37b 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-LocationBasedCAP'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-LocationBasedCAP.zip'
        version: '1.0.1'
      }}
  }

  resource module38 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Monitor-BreakGlassAccount'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Monitor-BreakGlassAccount.zip'
        version: '1.1.1'
      }}
  }

  resource module39 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-NetworkSecurityTools'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-NetworkSecurityTools.zip'
        version: '1.0.3'
      }}
  }
        
  resource module40 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-AlertsMonitor'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-AlertsMonitor.zip'
        version: '1.0.9'
      }}
  }

  resource module41 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-StorageAccountTLSversion'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-StorageAccountTLSversion.zip'
        version: '1.0.4'
      }}
  }

  resource module42 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-AppServiceHTTPSConfiguration'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-AppServiceHTTPSConfiguration.zip'
        version: '1.0.0'
      }}
  }

  resource module43 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-FunctionAppHTTPSConfiguration'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-FunctionAppHTTPSConfiguration.zip'
        version: '1.0.0'
      }}
  }

  resource module44 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-FinOpsToolStatus'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-FinOpsToolStatus.zip'
        version: '1.0.4'
      }}
  }
  
  resource module45 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-UserRoleReviews'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-UserRoleReviews.zip'
        version: '1.0.5'
      }
    }
  }

  resource module46 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-ServiceHealthAlerts'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-ServiceHealthAlerts.zip'
        version: '1.0.7'
      }
    }
  }
  
  resource module47 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-DefenderForCloudAlerts'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-DefenderForCloudAlerts.zip'
        version: '1.1.1'
      }
    }
  }

  resource module48 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-GuestRoleReviews'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-GuestRoleReviews.zip'
        version: '1.0.5'
      }
    }
  }

  resource module49 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-TLSConfiguration'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-TLSConfiguration.zip'
        version: '1.0.0'
      }}
  }

  resource module50 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Az.ResourceGraph'
    properties: {
      contentLink: {
        uri: 'https://devopsgallerystorage.blob.core.windows.net:443/packages/az.resourcegraph.1.1.0.nupkg'
        version: '1.1.0'
      }}
  }

  resource module51 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Az.Accounts'
    properties: {
      contentLink: {
        uri: 'https://devopsgallerystorage.blob.core.windows.net:443/packages/az.accounts.4.0.2.nupkg'
        version: '4.0.2'
      }}
  }

  resource module52 'powerShell72Modules' = if (newDeployment || updatePSModules) {
    name: 'Check-NetworkInterfaceIPs'
    properties: {
      contentLink: {
        uri: '${ModuleBaseURL}/Check-NetworkInterfaceIPs.zip'
        version: '1.0.1'
      }}
  }

  // Variables for Runbooks

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
  resource variable22 'variables' = if (newDeployment || updateCoreResources) {
    name: 'AllowedLocationInitiativeId'
    properties: {
        isEncrypted: true
        value: '"${AllowedLocationInitiativeId}"'
    }
  }
  resource variable23 'variables' = if (newDeployment || updateCoreResources) {
    name: 'ENABLE_DEBUG_METRICS'
    properties: {
        isEncrypted: true
        value: '"true"'
    }
  }
  
  // DCR-based Log Ingestion API variables
  resource variable24 'variables' = if ((newDeployment || updateCoreResources) && dceEndpoint != '') {
    name: 'DCE_ENDPOINT'
    properties: {
      isEncrypted: true
      value: '"${dceEndpoint}"'
    }
  }
  
  resource variable25 'variables' = if ((newDeployment || updateCoreResources) && dcrImmutableId != '') {
    name: 'DCR_IMMUTABLE_ID'
    properties: {
      isEncrypted: true
      value: '"${dcrImmutableId}"'
    }
  }
}
output guardrailsAutomationAccountMSI string = guardrailsAC.identity.principalId
