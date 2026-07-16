param AllowedLocationPolicyId string
param AllowedLocationInitiativeId string
param automationAccountName string
// These values create the named PowerShell 7.6 environment and select its Azure-managed Az module version.
param automationRuntimeAzVersion string
param automationRuntimeEnvironmentName string
param automationRuntimeVersion string
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
param mfaGracePeriod string

// The 7.6 Runtime Environment replaces the old list of separate PowerShell 7.2 module resources.
// Bicep and the deployment scripts share this manifest so they deploy and validate the same module set.
var guardrailsRuntimeModules = loadJsonContent('../../automation-runtime-modules.json')

// guardrailsAC is the Bicep symbol used to reference this resource within the template.
// The Automation Account name shown in Azure comes from automationAccountName.
// The parent account stays on its existing 2023-11-01 contract; the 7.6 child resources below
// use 2024-10-23 because that contract exposes Runtime Environments and their modules.
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

  // Create the environment on a fresh install and reconcile it only when modules are selected for update.
  // Core-only updates leave its Az and Guardrails module versions unchanged, including one-off client hotfixes.
  resource guardrailsRuntimeEnvironment 'runtimeEnvironments@2024-10-23' = if (newDeployment || updatePSModules) {
    name: automationRuntimeEnvironmentName
    location: location
    tags: {
      releaseVersion: releaseVersion
      releasedate: releaseDate
    }
    properties: {
      description: 'Guardrails PowerShell runtime environment'
      runtime: {
        language: 'PowerShell'
        version: automationRuntimeVersion
      }
      defaultPackages: {
        // Azure calls this property defaultPackages, but Az is the default PowerShell module for this environment.
        // The Az rollup supplies Az.Accounts and Az.ResourceGraph, avoiding separate older copies.
        Az: automationRuntimeAzVersion
      }
    }

    // The old PowerShell 7.2 setup used separate legacy module resources, so it did not need this batching.
    // Azure's Runtime Environment API calls PowerShell modules "packages" and accepts up to ten additions at a time.
    // Deploy every Guardrails module in sequential groups of ten instead of sending the entire set at once.
    @batchSize(10)
    resource guardrailsModules 'packages@2024-10-23' = [for runtimeModule in guardrailsRuntimeModules: if (newDeployment || updatePSModules) {
      name: runtimeModule.name
      properties: {
        contentLink: {
          // Most modules come from the selected Guardrails release. A manifest entry can provide a different
          // source for an external module such as Az.Marketplace.
          #disable-next-line no-hardcoded-env-urls
          uri: runtimeModule.?uri ?? '${ModuleBaseURL}/${runtimeModule.name}.zip'
          version: runtimeModule.version
        }
      }
    }]
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
  resource variable24 'variables' = if (newDeployment || updateCoreResources) {
    name: 'MFAGracePeriod'
    properties: {
      isEncrypted: true
      value: '"${mfaGracePeriod}"'
    }
  }
}
output guardrailsAutomationAccountMSI string = guardrailsAC.identity.principalId
