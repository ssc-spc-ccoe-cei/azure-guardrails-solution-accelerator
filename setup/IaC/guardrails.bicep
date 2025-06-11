//Scope
targetScope = 'resourceGroup'
//Parameters and variables
param AllowedLocationPolicyId string = 'e56962a6-4747-49cd-b67b-bf8b01975c4c'
param AllowedLocationInitiativeId string = '/providers/microsoft.management/managementgroups/252afaf3-eb71-4f05-8da2-279c8b2466b7/providers/microsoft.authorization/policysetdefinitions/6c7429039715412f9438cb15'
param automationAccountName string = 'guardrails-AC'
param CBSSubscriptionName string 
param currentUserObjectId string = ''
param ModuleBaseURL string
param DepartmentNumber string
param DepartmentName string
param deployKV bool = true
param deployLAW bool = true
param DeployTelemetry bool = true
param HealthLAWResourceId string
param kvName string = 'guardrails-kv'
param lighthouseTargetManagementGroupID string
param Locale string = 'EN'
param location string = 'canadacentral'
param logAnalyticsWorkspaceName string = 'guardrails-LAW'
param newDeployment bool = true
param PBMMPolicyID string = '4c4a5f27-de81-430b-b4e5-9cbd50595a87'
param releaseDate string 
param releaseVersion string
param SecurityLAWResourceId string
param SSCReadOnlyServicePrincipalNameAPPID string
param storageAccountName string
param subscriptionId string
param TenantDomainUPN string
param updateCoreResources bool = false
param updatePSModules bool = false
param updateWorkbook bool = false
param securityRetentionDays string 
param cloudUsageProfiles string = 'default'
@secure()
param breakglassAccount1 string = ''
@secure()
param breakglassAccount2 string = ''

var containername = 'guardrailsstorage'
// var GRDocsBaseUrl='https://github.com/ssc-spc-ccoe-cei/azure-guardrails-solution-accelerator/tree/main/docs'
var GRDocsBaseUrl='https://gcxgce.sharepoint.com/teams/10001628/Shared%20Documents/Forms/AllItems.aspx?id=%2Fteams%2F10001628%2FShared%20Documents%2FGeneral%2FAzure%20CaC%20%2D%20Guardrail%20Controls%20Remediation%20Guide&p=true&ga=1'
var vaultUri = 'https://${kvName}.vault.azure.net/'
var rg=resourceGroup().name

//Resources:
//KeyVault
var telemetryInfo = json(loadTextContent('./modules/telemetry.json'))

module telemetry './nested_telemetry.bicep' =  if (telemetryInfo.customerUsageAttribution.enabled) {
  name: telemetryInfo.customerUsageAttribution.SolutionIdentifier
  params: {}
}
module aa 'modules/automationaccount.bicep' = if (newDeployment || updatePSModules || updateCoreResources) {
  name: 'guardrails-automationaccount'
  params: {
    AllowedLocationPolicyId: AllowedLocationPolicyId
    AllowedLocationInitiativeId: AllowedLocationInitiativeId
    automationAccountName: automationAccountName
    CBSSubscriptionName: CBSSubscriptionName
    containername: containername
    ModuleBaseURL: ModuleBaseURL
    DepartmentNumber: DepartmentNumber
    DepartmentName: DepartmentName
    guardrailsKVname: kvName
    guardrailsLogAnalyticscustomerId: LAW.outputs.logAnalyticsWorkspaceId
    guardrailsStoragename: storageAccountName
    HealthLAWResourceId: HealthLAWResourceId
    lighthouseTargetManagementGroupID: lighthouseTargetManagementGroupID
    Locale: Locale
    location: location
    newDeployment: newDeployment
    PBMMPolicyID: PBMMPolicyID
    releaseDate: releaseDate
    releaseVersion: releaseVersion
    SecurityLAWResourceId: SecurityLAWResourceId
    SSCReadOnlyServicePrincipalNameAPPID:SSCReadOnlyServicePrincipalNameAPPID
    TenantDomainUPN: TenantDomainUPN
    updatePSModules: updatePSModules
    updateCoreResources: updateCoreResources
    securityRetentionDays: securityRetentionDays
    cloudUsageProfiles: cloudUsageProfiles
  }
}
module KV 'modules/keyvault.bicep' = if (newDeployment && deployKV) {
  name: 'guardrails-keyvault'
  params: {
    kvName: kvName
    location: location
    currentUserObjectId: currentUserObjectId
    automationAccountMSI: aa.outputs.guardrailsAutomationAccountMSI
    breakglassAccount1: breakglassAccount1
    breakglassAccount2: breakglassAccount2
    logAnalyticsWorkspaceName: split(LAW.outputs.logAnalyticsResourceId,'/')[8]
    vaultUri: vaultUri
    releaseVersion: releaseVersion
    releaseDate: releaseDate
    deployKV: deployKV
    tenantId: subscription().tenantId
  }
}
module LAW 'modules/loganalyticsworkspace.bicep' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
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
module storageaccount 'modules/storage.bicep' = if (newDeployment || updateCoreResources) {
  name: 'guardrails-storageaccount'
  params: {
    storageAccountName: storageAccountName
    location: location
    containername: containername
  }
}

module alertNewVersion 'modules/alert.bicep' = {
  name: 'guardrails-alertNewVersion'
  dependsOn: [
    aa
    LAW
  ]
  params: {
    alertRuleDescription: 'Alerts when a new version of the Guardrails Solution Accelerator is available'
    alertRuleName: 'GuardrailsNewVersion'
    alertRuleDisplayName: 'Guardrails New Version Available.'
    alertRuleSeverity: 3
    location: location
    query: 'GR_VersionInfo_CL | summarize total=count() by UpdateNeeded_b=iff(DeployedVersion_s != AvailableVersion_s, "Yes",\'No\') | where UpdateAvailable == \'Yes\''
    scope: LAW.outputs.logAnalyticsResourceId
    autoMitigate: true
    evaluationFrequency: 'PT6H'
    windowSize: 'PT6H'
  }
}
output guardrailsAutomationAccountMSI string = newDeployment ? aa.outputs.guardrailsAutomationAccountMSI : ''
