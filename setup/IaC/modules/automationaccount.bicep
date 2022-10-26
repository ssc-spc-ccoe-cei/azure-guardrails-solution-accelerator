param automationAccountName string
param location string
param releaseVersion string
param releaseDate string
param CustomModulesBaseURL string
param guardrailsLogAnalyticscustomerId string
param guardrailsKVname string
param guardrailsStoragename string
param PBMMPolicyID string
param containername string
param AllowedLocationPolicyId string
param DepartmentNumber string
param CBSSubscriptionName string
param SecurityLAWResourceId string
param HealthLAWResourceId string
param TenantDomainUPN string
param Locale string
param lighthouseTargetManagementGroupID string

resource guardrailsAC 'Microsoft.Automation/automationAccounts@2021-06-22' = {
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
  resource OMSModule 'modules' ={
    name: 'OMSIngestionAPI'
    properties: {
      contentLink: {
        uri: 'https://devopsgallerystorage.blob.core.windows.net/packages/omsingestionapi.1.6.0.nupkg'
        version: '1.6.0'
      }
    }
  }
  resource module1 'modules' ={
    name: 'Check-BreakGlassAccountOwnersInformation'
    properties: {
      contentLink: {
        uri: '${CustomModulesBaseURL}/Check-BreakGlassAccountOwnersInformation.zip'
        version: '1.0.0'

      }
    }
  }
resource module2 'modules' ={
    name: 'Check-BreakGlassAccountIdentityProtectionLicense'
    properties: {
      contentLink: {
        uri: '${CustomModulesBaseURL}/Check-BreakGlassAccountIdentityProtectionLicense.zip'
        version: '1.0.0'
      }
    }
  }
resource module4 'modules' ={
    name: 'Check-DeprecatedAccounts'
    properties: {
      contentLink: {
        uri: '${CustomModulesBaseURL}/Check-DeprecatedAccounts.zip'
        version: '1.0.0'
      }
    }
  }
resource module5 'modules' ={
    name: 'Check-ExternalAccounts'
    properties: {
      contentLink: {
        uri: '${CustomModulesBaseURL}/Check-ExternalAccounts.zip'
        version: '1.0.0'
      }
    }
  }
resource module7 'modules' ={
    name: 'Check-MonitorAccount'
    properties: {
      contentLink: {
        uri: '${CustomModulesBaseURL}/Check-MonitorAccount.zip'
        version: '1.0.0'
      }
    }
  }
resource module8 'modules' ={
    name: 'Check-PBMMPolicy'
    properties: {
      contentLink: {
        uri: '${CustomModulesBaseURL}/Check-PBMMPolicy.zip'
        version: '1.0.0'
      }
    }
  }
  resource module22 'modules' ={
    name: 'Check-ProtectionDataAtRest'
    properties: {
      contentLink: {
        uri: '${CustomModulesBaseURL}/Check-ProtectionDataAtRest.zip'
        version: '1.0.0'
      }
    }
  }
  resource module23 'modules' ={
    name: 'Check-ProtectionOfDataInTransit'
    properties: {
      contentLink: {
        uri: '${CustomModulesBaseURL}/Check-ProtectionOfDataInTransit.zip'
        version: '1.0.0'
      }
    }
  }
resource module9 'modules' ={
    name: 'Check-SubnetComplianceStatus'
    properties: {
      contentLink: {
        uri: '${CustomModulesBaseURL}/Check-SubnetComplianceStatus.zip'
        version: '1.0.0'
      }
    }
  }
resource module10 'modules' ={
    name: 'Check-VNetComplianceStatus'
    properties: {
      contentLink: {
        uri: '${CustomModulesBaseURL}/Check-VNetComplianceStatus.zip'
        version: '1.0.0'
      }
    }
  }
resource module11 'modules' ={
    name: 'Detect-UserBGAUsersAuthMethods'
    properties: {
      contentLink: {
        uri: '${CustomModulesBaseURL}/Detect-UserBGAUsersAuthMethods.zip'
        version: '1.0.0'
      }
    }
  }
resource module12 'modules' ={
    name: 'Get-AzureADLicenseType'
    properties: {
      contentLink: {
        uri: '${CustomModulesBaseURL}/Get-AzureADLicenseType.zip'
        version: '1.0.0'
      }
    }
  }
resource module13 'modules' ={
    name: 'GR-Common'
    properties: {
      contentLink: {
        uri: '${CustomModulesBaseURL}/GR-Common.zip'
        version: '1.1.2'
      }
    }
  }
resource module14 'modules' ={
    name: 'Validate-BreakGlassAccount'
    properties: {
      contentLink: {
        uri: '${CustomModulesBaseURL}/Validate-BreakGlassAccount.zip'
        version: '1.0.0'
      }
    }
  }
  resource module15 'modules' ={
    name: 'Check-AllowedLocationPolicy'
    properties: {
      contentLink: {
        uri: '${CustomModulesBaseURL}/Check-AllowedLocationPolicy.zip'
        version: '1.0.0'
      }
    }
  }
  resource module16 'modules' ={
    name: 'Check-PrivateMarketPlace'
    properties: {
      contentLink: {
        uri: '${CustomModulesBaseURL}/Check-PrivateMarketPlace.zip'
        version: '1.0.0'
      }
    }
  }
  resource module17 'modules' ={
    name: 'Az.Marketplace'
    properties: {
      contentLink: {
        uri: 'https://devopsgallerystorage.blob.core.windows.net:443/packages/az.marketplace.0.3.0.nupkg'
        version: '0.3.0'
      }
    }
  }
  resource module19 'modules' ={
    name: 'Check-CyberSecurityServices'
    properties: {
      contentLink: {
        uri: '${CustomModulesBaseURL}/Check-CyberSecurityServices.zip'
        version: '1.0.0'
      }
    }
  }
  resource module20 'modules' ={
    name: 'Check-LoggingAndMonitoring'
    properties: {
      contentLink: {
        uri: '${CustomModulesBaseURL}/Check-LoggingAndMonitoring.zip'
        version: '1.0.0'
      }
    }
  }
  resource module21 'modules' ={
    name: 'GR-ComplianceChecks'
    properties: {
      contentLink: {
        uri: '${CustomModulesBaseURL}/GR-ComplianceChecks.zip'
        version: '1.0.0'
      }
    }
  }
  resource module24 'modules' ={
    name: 'Check-CloudConsoleAccess'
    properties: {
      contentLink: {
        uri: '${CustomModulesBaseURL}/Check-CloudConsoleAccess.zip'
        version: '1.0.0'
      }
    }
  }
  resource variable1 'variables' = {
    name: 'KeyvaultName'
    properties: {
        isEncrypted: true
        value: '"${guardrailsKVname}"'
    }
  }
    
  resource variable2 'variables' = {
    name: 'WorkSpaceID'
    properties: {
        isEncrypted: true
        value: '"${guardrailsLogAnalyticscustomerId}"'
    }
  }
  resource variable3 'variables' = {
    name: 'LogType'
    properties: {
        isEncrypted: true
        value: '"GuardrailsCompliance"'
    }
  }
  resource variable4 'variables' = {
    name: 'PBMMPolicyID'
    properties: {
        isEncrypted: true
        value: '"/providers/Microsoft.Authorization/policySetDefinitions/${PBMMPolicyID}"'
    }
  }
  resource variable5 'variables' = {
    name: 'GuardrailWorkspaceIDKeyName'
    properties: {
        isEncrypted: true
        value: '"WorkSpaceKey"'
    }
  }
  resource variable6 'variables' = {
    name: 'StorageAccountName'
    properties: {
        isEncrypted: false
        value: '"${guardrailsStoragename}"'
    }
  }
  resource variable7 'variables' = {
    name: 'ContainerName'
    properties: {
        isEncrypted: true
        value: '"${containername}"'
    }
  }
  resource variable8 'variables' = {
    name: 'ResourceGroupName'
    properties: {
        isEncrypted: true
        value: '"${resourceGroup().name}"'
    }
  }
  resource variable9 'variables' = {
    name: 'AllowedLocationPolicyId'
    properties: {
        isEncrypted: true
        value: '"/providers/Microsoft.Authorization/policyDefinitions/${AllowedLocationPolicyId}"'
    }
  }
  resource variable10 'variables' = {
    name: 'DepartmentNumber'
    properties: {
      isEncrypted: true
      value: '"${DepartmentNumber}"'
  }
  }
  resource variable11 'variables' = {
    name: 'CBSSubscriptionName'
    properties: {
      isEncrypted: true
      value: '"${CBSSubscriptionName}"'
    }
  }
  resource variable12 'variables' = {
    name: 'SecurityLAWResourceId'
    properties: {
      isEncrypted: true
      value: '"${SecurityLAWResourceId}"'
    }
  }
  resource variable13 'variables' = {
    name: 'HealthLAWResourceId'
    properties: {
      isEncrypted: true
      value: '"${HealthLAWResourceId}"'
    }
  }
  resource variable14 'variables' = {
    name: 'TenantDomainUPN'
    properties: {
      isEncrypted: true
      value: '"${TenantDomainUPN}"'
    }
  }
  resource variable15 'variables' = {
    name: 'GuardRailsLocale'
    properties: {
      isEncrypted: true
      value: '"${Locale}"'
  }
  }

  resource variable16 'variables' = {
    name: 'lighthouseTargetManagementGroupID'
    'properties': {
      'isEncrypted': true
      'value': '"${lighthouseTargetManagementGroupID}"'
  }
  }
}
output guardrailsAutomationAccountMSI string = guardrailsAC.identity.principalId
