//Scope
targetScope = 'resourceGroup'
//Parameters and variables
param storageAccountName string
param subscriptionId string
param location string = 'canadacentral'
param kvName string = 'guardrails-kv'
param automationAccountName string = 'guardrails-AC'
param logAnalyticsWorkspaceName string = 'guardrails-LAW'
param PBMMPolicyID string = '4c4a5f27-de81-430b-b4e5-9cbd50595a87'
param AllowedLocationPolicyId string = 'e56962a6-4747-49cd-b67b-bf8b01975c4c'
param DepartmentNumber string
param deployKV bool = true
param deployLAW bool = true
param CBSSubscriptionName string 
param SecurityLAWResourceId string
param HealthLAWResourceId string
param CustomModulesBaseURL string = 'https://github.com/Azure/GuardrailsSolutionAccelerator/raw/main/psmodules'
param DeployTelemetry bool = true
param Locale string = 'EN'
param releaseVersion string
param releaseDate string 
param TenantDomainUPN string
param lighthouseTargetManagementGroupID string
param newDeployment bool = true
param updateWorkbook bool = false
param updatePSModules bool = false
var containername = 'guardrailsstorage'
var GRDocsBaseUrl='https://github.com/Azure/GuardrailsSolutionAccelerator/docs/'
var vaultUri = 'https://${kvName}.vault.azure.net/'
var rg=resourceGroup().name
//Resources:
//KeyVault
module telemetry './nested_telemetry.bicep' = if (DeployTelemetry) {
  name: 'pid-9c273620-d12d-4647-878a-8356201c7fe8'
  params: {}
}
module aa 'modules/automationaccount.bicep' = if (newDeployment || updatePSModules) {
  name: 'guardrails-automationaccount'
  params: {
    automationAccountName: automationAccountName
    location: location
    containername: containername
    PBMMPolicyID: PBMMPolicyID
    AllowedLocationPolicyId: AllowedLocationPolicyId
    DepartmentNumber: DepartmentNumber
    CBSSubscriptionName: CBSSubscriptionName
    SecurityLAWResourceId: SecurityLAWResourceId
    HealthLAWResourceId: HealthLAWResourceId
    CustomModulesBaseURL: CustomModulesBaseURL
    Locale: Locale
    guardrailsKVname: kvName
    guardrailsLogAnalyticscustomerId: LAW.outputs.logAnalyticsWorkspaceId
    guardrailsStoragename: storageAccountName
    releaseVersion: releaseVersion
    releaseDate: releaseDate
    TenantDomainUPN: TenantDomainUPN
    lighthouseTargetManagementGroupID: lighthouseTargetManagementGroupID
    newDeployment: newDeployment
    updatePSModules: updatePSModules
  }
}
module KV 'modules/keyvault.bicep' = if (newDeployment && deployKV) {
  name: 'guardrails-keyvault'
  params: {
    kvName: kvName
    location: location
    vaultUri: vaultUri
    releaseVersion: releaseVersion
    releaseDate: releaseDate
    deployKV: deployKV
    tenantId: subscription().tenantId
  }
}
module LAW 'modules/loganalyticsworkspace.bicep' = if ((deployLAW && newDeployment) || updateWorkbook) {
  name: 'guardrails-loganalytics'
  params: {
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    location: location
    releaseVersion: releaseVersion
    releaseDate: releaseDate
    rg: rg
    deployLAW: deployLAW
    subscriptionId: subscription().subscriptionId
    GRDocsBaseUrl: GRDocsBaseUrl
    newDeployment: newDeployment
    updateWorkbook: updateWorkbook
  }
}
module storageaccount 'modules/storage.bicep' = if (newDeployment) {
  name: 'guardrails-storageaccount'
  params: {
    storageAccountName: storageAccountName
    location: location
    containername: containername
  }
}

output guardrailsAutomationAccountMSI string = newDeployment ? aa.outputs.guardrailsAutomationAccountMSI : ''
