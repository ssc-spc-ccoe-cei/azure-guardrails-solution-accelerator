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
    query: 'let itsgcodes=GRITSGControls_CL | summarize arg_max(TimeGenerated, *) by itsgcode_s;\nGuardrailsCompliance_CL\n| where column_ifexists("ControlName_s", "") has ctrlprefix and column_ifexists("ReportTime_s", "") == ReportTime and column_ifexists("Required_s", "") != tostring(showNonRequired)\n| where TimeGenerated > ago (24h)\n|join kind=leftouter (itsgcodes) on itsgcode_s\n| project ["Item Name"]=strcat(column_ifexists("ItemName_s", ""), iff(column_ifexists("Required_s", "")=="False"," (R)", " (M)")), Comments=column_ifexists("Comments_s", ""), Status=case(column_ifexists("ComplianceStatus_b", false) == true, \'✔️\', column_ifexists("ComplianceStatus_b", false) == false, \'❌\', \'➖\'),["ITSG Control"]=column_ifexists("itsgcode_s", ""), Remediation=gr_geturl(replace_string(ctrlprefix," ",""),column_ifexists("itsgcode_s", "")), Profile=iff(isnotempty(column_ifexists("Profile_d", "")), tostring(toint(column_ifexists("Profile_d", ""))), "")\n'
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
    //query: 'let baseurl="${GRDocsBaseUrl}";\nlet Link=strcat(baseurl,control,"-", replace_string(replace_string(itsgcode,"(","-"),")",""),".md");\nLink\n'
    query: 'let baseurl="${GRDocsBaseUrl}";\nlet Link=baseurl;\nLink\n'
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
    query: 'let itsgcodes=GRITSGControls_CL | summarize arg_max(TimeGenerated, *) by itsgcode_s;\nGuardrailsCompliance_CL\n| where column_ifexists("ControlName_s", "") has ctrlprefix and column_ifexists("ReportTime_s", "") == ReportTime and column_ifexists("Required_s", "") != tostring(showNonRequired)\n| where TimeGenerated > ago (24h)\n|join kind=leftouter (itsgcodes) on itsgcode_s\n| project ["Item Name"]=strcat(column_ifexists("ItemName_s", ""), iff(column_ifexists("Required_s", "")=="False"," (R)", " (M)")), ["Subscription Name"]=column_ifexists("DisplayName_s", ""), Comments=column_ifexists("Comments_s", ""), Status=case(column_ifexists("ComplianceStatus_b", false) == true, \'✔️\', column_ifexists("ComplianceStatus_b", false) == false, \'❌\', \'➖\'),["ITSG Control"]=column_ifexists("itsgcode_s", ""), Remediation=gr_geturl(replace_string(ctrlprefix," ",""),column_ifexists("itsgcode_s", "")), Profile=iff(isnotempty(column_ifexists("Profile_d", "")), tostring(toint(column_ifexists("Profile_d", ""))), "")\n'
    functionAlias: 'gr_data567'
    functionParameters: 'ctrlprefix:string, ReportTime:string, showNonRequired:string'
    version: 2
  }
}
resource f4 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook) {
  name: 'gr_data11'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_data11'
    query: 'let itsgcodes=GRITSGControls_CL | summarize arg_max(TimeGenerated, *) by itsgcode_s;\nGuardrailsCompliance_CL\n| where column_ifexists("ControlName_s", "") has ctrlprefix and column_ifexists("ReportTime_s", "") == ReportTime and column_ifexists("Required_s", "") != tostring(showNonRequired)\n| where TimeGenerated > ago (24h)\n|join kind=leftouter (itsgcodes) on itsgcode_s\n| project  ["Item Name"]=strcat(column_ifexists("ItemName_s", ""), iff(column_ifexists("Required_s", "")=="False"," (R)", " (M)")), ["Subscription Name"] = column_ifexists("SubscriptionName_s", ""), Comments=column_ifexists("Comments_s", ""), Status=case(column_ifexists("ComplianceStatus_b", false) == true, \'✔️\', column_ifexists("ComplianceStatus_b", false) == false, \'❌\', \'➖\'),["ITSG Control"]=column_ifexists("itsgcode_s", ""), Remediation=gr_geturl(replace_string(ctrlprefix," ",""),column_ifexists("itsgcode_s", "")), Profile=iff(isnotempty(column_ifexists("Profile_d", "")), tostring(toint(column_ifexists("Profile_d", ""))), "")\n'
    functionAlias: 'gr_data11'
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
output logAnalyticsResourceId string = guardrailsLogAnalytics.id
