param subscriptionId string
param rg string
param logAnalyticsWorkspaceName  string
param location  string
param releaseVersion  string
param releaseDate string
param deployLAW bool
param GRDocsBaseUrl string
param newDeployment bool = true
param updateWorkbook bool = false
var wb = loadTextContent('gr.workbook')
var wbConfig2='"/subscriptions/${subscriptionId}/resourceGroups/${rg}/providers/Microsoft.OperationalInsights/workspaces/${logAnalyticsWorkspaceName}"]}'
//var wbConfig3='''
//'''
// var wbConfig='${wbConfig1}${wbConfig2}${wbConfig3}'
var wbConfig='${wb}${wbConfig2}'

resource guardrailsLogAnalytics 'Microsoft.OperationalInsights/workspaces@2021-06-01' = if ((deployLAW && newDeployment) || updateWorkbook) {
  name: logAnalyticsWorkspaceName
  location: location
  tags: {
    releaseVersion:releaseVersion
    releasedate: releaseDate
  }
  properties: {
    retentionInDays:90
    sku: {
      name: 'PerGB2018'
    }
  }
}
resource f2 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook) {
  name: 'gr_data'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_data'
    query: 'let itsgcodes=GRITSGControls_CL | summarize arg_max(TimeGenerated, *) by itsgcode_s;\nGuardrailsCompliance_CL\n| where ControlName_s has ctrlprefix and ReportTime_s == ReportTime and Required_s != tostring(showNonRequired)\n| where TimeGenerated > ago (24h)\n|join kind=inner (itsgcodes) on itsgcode_s\n| project ItemName=strcat(ItemName_s, iff(Required_s=="False"," (R)", " (M)")), Comments=Comments_s, Status=iif(tostring(ComplianceStatus_b)=="True", \'✔️ \', \'❌ \'),["ITSG Control"]=itsgcode_s, Definition=Definition_s,Mitigation=gr_geturl(replace_string(ctrlprefix," ",""),itsgcode_s)'
    functionAlias: 'gr_data'
    functionParameters: 'ctrlprefix:string, ReportTime:string, showNonRequired:string'
    version: 2
  }
}
resource f1 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook) {
  name: 'gr_geturl'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_geturl'
    query: 'let baseurl="${GRDocsBaseUrl}";\nlet Link=strcat(baseurl,control,"-", replace_string(replace_string(itsgcode,"(","-"),")",""),".md");\nLink\n'
    functionAlias: 'gr_geturl'
    functionParameters: 'control:string, itsgcode:string'
    version: 2
  }
}
resource f3 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook) {
  name: 'gr_data567'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_data567'
    query: 'let itsgcodes=GRITSGControls_CL | summarize arg_max(TimeGenerated, *) by itsgcode_s;\nGuardrailsCompliance_CL\n| where ControlName_s has ctrlprefix and ReportTime_s == ReportTime and Required_s != tostring(showNonRequired)\n| where TimeGenerated > ago (24h)\n|join kind=inner (itsgcodes) on itsgcode_s\n| project Type=Type_s, Name=DisplayName_s, ItemName=strcat(ItemName_s, iff(Required_s=="False"," (R)", " (M)")), Comments=Comments_s, Status=iif(tostring(ComplianceStatus_b)=="True", \'✔️ \', \'❌ \'),["ITSG Control"]=itsgcode_s, Definition=Definition_s,Mitigation=gr_geturl(replace_string(ctrlprefix," ",""),itsgcode_s)'
    functionAlias: 'gr_data567'
    functionParameters: 'ctrlprefix:string, ReportTime:string, showNonRequired:string'
    version: 2
  }
}
resource guarrailsWorkbooks 'Microsoft.Insights/workbooks@2021-08-01' = if ((deployLAW && newDeployment) || updateWorkbook) {
  location: location
  kind: 'shared'
  name: guid('guardrails')
  properties:{
    displayName: 'Guardrails'
    serializedData: wbConfig
    version: releaseVersion
    category: 'workbook'
    sourceId: guardrailsLogAnalytics.id
  }
}

output logAnalyticsWorkspaceId string = guardrailsLogAnalytics.properties.customerId 

