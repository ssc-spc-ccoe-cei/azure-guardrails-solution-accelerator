//Scope
targetScope = 'resourceGroup'
//Parameters and variables
param AllowedLocationPolicyId string = 'e56962a6-4747-49cd-b67b-bf8b01975c4c'
param AllowedLocationInitiativeId string = 'N/A'
param automationAccountName string = 'guardrails-AC'
param CBSSubscriptionName string 
param currentUserObjectId string = ''
param ModuleBaseURL string
param DepartmentNumber string
param DepartmentName string
param deployKV bool = true
param deployLAW bool = true
#disable-next-line no-unused-params
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
param enableMultiCloudProfiles bool

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
    #disable-next-line BCP318
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
    #disable-next-line BCP318
    dceEndpoint: (deployLAW && (newDeployment || updateCoreResources)) ? DCRDCE.outputs.dceEndpoint : ''
    #disable-next-line BCP318
    dcrImmutableId: (deployLAW && (newDeployment || updateCoreResources)) ? DCRDCE.outputs.dcrImmutableId : ''
    #disable-next-line BCP318
    dcrImmutableId2: (deployLAW && (newDeployment || updateCoreResources)) ? DCRDCE.outputs.dcrImmutableId2 : ''
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
    enableMultiCloudProfiles: enableMultiCloudProfiles
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    location: location
    releaseVersion: releaseVersion
    releaseDate: releaseDate
    rg: rg
    deployLAW: deployLAW
    subscriptionId: subscriptionId
    GRDocsBaseUrl: GRDocsBaseUrl
    newDeployment: newDeployment
    updateWorkbook: updateWorkbook
    updateCoreResources: updateCoreResources
  }
}

// Data Collection Endpoint (DCE) and Data Collection Rule (DCR) for DCR-based Log Ingestion API
// Create DCE/DCR on new deployments or when updating core resources (for migration from Data Collector API)
module DCRDCE 'modules/dcrdce.bicep' = if (deployLAW && (newDeployment || updateCoreResources)) {
  name: 'guardrails-dcrdce'
  dependsOn: [
    LAW
  ]
  params: {
    location: location
    #disable-next-line BCP318    
    logAnalyticsWorkspaceResourceId: LAW.outputs.logAnalyticsResourceId
    releaseVersion: releaseVersion
    releaseDate: releaseDate
    newDeployment: newDeployment
    updateCoreResources: updateCoreResources
  }
}
// Grants the automation account MSI the Monitoring Metrics Publisher role on both DCRs.
// Separate module to avoid a circular dependency between automationaccount and dcrdce modules.
module DCRRBAC 'modules/dcrroleassignment.bicep' = if (deployLAW && (newDeployment || updateCoreResources)) {
  name: 'guardrails-dcrrbac'
  dependsOn: [
    aa
    DCRDCE
  ]
  params: {
    #disable-next-line BCP318
    dcrResourceId: DCRDCE.outputs.dcrResourceId
    #disable-next-line BCP318
    dcrResourceId2: DCRDCE.outputs.dcrResourceId2
    #disable-next-line BCP318
    automationAccountMSI: aa.outputs.guardrailsAutomationAccountMSI
    #disable-next-line BCP318    
    logAnalyticsWorkspaceResourceId: LAW.outputs.logAnalyticsResourceId

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
    query: 'GR_VersionInfo_CL | summarize total=count() by UpdateAvailable=iff(DeployedVersion_s != AvailableVersion_s, "Yes",\'No\') | where UpdateAvailable == \'Yes\''
    scope: LAW.outputs.logAnalyticsResourceId
    autoMitigate: true
    evaluationFrequency: 'PT6H'
    windowSize: 'PT6H'
  }
}
output guardrailsAutomationAccountMSI string = newDeployment ? aa.outputs.guardrailsAutomationAccountMSI : ''
