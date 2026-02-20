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
param updateCoreResources bool = false
param enableMultiCloudProfiles bool
var wb = loadTextContent('gr.workbook')
var wbConfig2='"/subscriptions/${subscriptionId}/resourceGroups/${rg}/providers/Microsoft.OperationalInsights/workspaces/${logAnalyticsWorkspaceName}"]}'
//var wbConfig3='''
//'''
// var wbConfig='${wbConfig1}${wbConfig2}${wbConfig3}'
var wbConfig='${wb}${wbConfig2}'

resource guardrailsLogAnalytics 'Microsoft.OperationalInsights/workspaces@2021-06-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
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

// Custom tables required by DCR-based log ingestion; must exist before DCR is created
resource dcrTableGuardrailsCompliance 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  parent: guardrailsLogAnalytics
  name: 'Custom-GuardrailsCompliance_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 90
    totalRetentionInDays: 90
    schema: {
      name: 'Custom-GuardrailsCompliance_CL'
      columns: [
        { name: 'TimeGenerated' type: 'dateTime' }
        { name: 'RawData' type: 'string' }
      ]
    }
  }
}
resource dcrTableGuardrailsComplianceException 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  parent: guardrailsLogAnalytics
  name: 'Custom-GuardrailsComplianceException_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 90
    totalRetentionInDays: 90
    schema: {
      name: 'Custom-GuardrailsComplianceException_CL'
      columns: [
        { name: 'TimeGenerated' type: 'dateTime' }
        { name: 'RawData' type: 'string' }
      ]
    }
  }
}
resource dcrTableGR_TenantInfo 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  parent: guardrailsLogAnalytics
  name: 'Custom-GR_TenantInfo_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 90
    totalRetentionInDays: 90
    schema: {
      name: 'Custom-GR_TenantInfo_CL'
      columns: [
        { name: 'TimeGenerated' type: 'dateTime' }
        { name: 'RawData' type: 'string' }
      ]
    }
  }
}
resource dcrTableGR_Results 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  parent: guardrailsLogAnalytics
  name: 'Custom-GR_Results_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 90
    totalRetentionInDays: 90
    schema: {
      name: 'Custom-GR_Results_CL'
      columns: [
        { name: 'TimeGenerated' type: 'dateTime' }
        { name: 'RawData' type: 'string' }
      ]
    }
  }
}
resource dcrTableGR_VersionInfo 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  parent: guardrailsLogAnalytics
  name: 'Custom-GR_VersionInfo_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 90
    totalRetentionInDays: 90
    schema: {
      name: 'Custom-GR_VersionInfo_CL'
      columns: [
        { name: 'TimeGenerated' type: 'dateTime' }
        { name: 'RawData' type: 'string' }
      ]
    }
  }
}
resource dcrTableGRITSGControls 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  parent: guardrailsLogAnalytics
  name: 'Custom-GRITSGControls_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 90
    totalRetentionInDays: 90
    schema: {
      name: 'Custom-GRITSGControls_CL'
      columns: [
        { name: 'TimeGenerated' type: 'dateTime' }
        { name: 'RawData' type: 'string' }
      ]
    }
  }
}
resource dcrTableGuardrailsTenantsCompliance 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  parent: guardrailsLogAnalytics
  name: 'Custom-GuardrailsTenantsCompliance_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 90
    totalRetentionInDays: 90
    schema: {
      name: 'Custom-GuardrailsTenantsCompliance_CL'
      columns: [
        { name: 'TimeGenerated' type: 'dateTime' }
        { name: 'RawData' type: 'string' }
      ]
    }
  }
}
resource dcrTableCaCDebugMetrics 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  parent: guardrailsLogAnalytics
  name: 'Custom-CaCDebugMetrics_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 90
    totalRetentionInDays: 90
    schema: {
      name: 'Custom-CaCDebugMetrics_CL'
      columns: [
        { name: 'TimeGenerated' type: 'dateTime' }
        { name: 'RawData' type: 'string' }
      ]
    }
  }
}
resource dcrTableGuardrailsUserRaw 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  parent: guardrailsLogAnalytics
  name: 'Custom-GuardrailsUserRaw_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 90
    totalRetentionInDays: 90
    schema: {
      name: 'Custom-GuardrailsUserRaw_CL'
      columns: [
        { name: 'TimeGenerated' type: 'dateTime' }
        { name: 'RawData' type: 'string' }
      ]
    }
  }
}
resource dcrTableGuardrailsCrossTenantAccess 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  parent: guardrailsLogAnalytics
  name: 'Custom-GuardrailsCrossTenantAccess_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 90
    totalRetentionInDays: 90
    schema: {
      name: 'Custom-GuardrailsCrossTenantAccess_CL'
      columns: [
        { name: 'TimeGenerated' type: 'dateTime' }
        { name: 'RawData' type: 'string' }
      ]
    }
  }
}
resource dcrTableGR2UsersWithoutGroups 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  parent: guardrailsLogAnalytics
  name: 'Custom-GR2UsersWithoutGroups_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 90
    totalRetentionInDays: 90
    schema: {
      name: 'Custom-GR2UsersWithoutGroups_CL'
      columns: [
        { name: 'TimeGenerated' type: 'dateTime' }
        { name: 'RawData' type: 'string' }
      ]
    }
  }
}
resource dcrTableGR2ExternalUsers 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  parent: guardrailsLogAnalytics
  name: 'Custom-GR2ExternalUsers_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 90
    totalRetentionInDays: 90
    schema: {
      name: 'Custom-GR2ExternalUsers_CL'
      columns: [
        { name: 'TimeGenerated' type: 'dateTime' }
        { name: 'RawData' type: 'string' }
      ]
    }
  }
}

resource f2 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_data'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_data'
    query: 'let itsgcodes=GRITSGControls_CL | summarize arg_max(TimeGenerated, *) by itsgcode_s;\nGuardrailsCompliance_CL\n| where column_ifexists("ControlName_s", "") has ctrlprefix and column_ifexists("ReportTime_s", "") == ReportTime and column_ifexists("Required_s", "") != tostring(showNonRequired)\n| where TimeGenerated > ago (24h)\n|join kind=leftouter (itsgcodes) on itsgcode_s\n| project ["Item Name"]=strcat(iff(column_ifexists("Required_s", "")=="False","(R) ", "(M) "), column_ifexists("ItemName_s", "")),\n    Comments=column_ifexists("Comments_s", ""),\n    Status=case(column_ifexists("ComplianceStatus_b", bool(null)) == true, \'🟢\', column_ifexists("ComplianceStatus_b", bool(null)) == false, \'🔴\', \'➖\'),\n    ["ITSG Control"]=column_ifexists("itsgcode_s", ""),\n    Remediation=gr_geturl(replace_string(ctrlprefix," ",""),column_ifexists("itsgcode_s", "")),\n    Profile=iff(isnotempty(column_ifexists("Profile_d", "")), tostring(toint(column_ifexists("Profile_d", ""))), "")\n'
    functionAlias: 'gr_data'
    functionParameters: 'ctrlprefix:string, ReportTime:string, showNonRequired:string'
    version: 2
  }
}
resource gr3 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_data3'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_data3'
    query: 'let enableMultiCloudProfiles = ${enableMultiCloudProfiles}; \n let itsgcodes=GRITSGControls_CL | summarize arg_max(TimeGenerated, *) by itsgcode_s;\nGuardrailsCompliance_CL\n| where column_ifexists("ControlName_s", "") has ctrlprefix and column_ifexists("ReportTime_s", "") == ReportTime and column_ifexists("Required_s", "") != tostring(showNonRequired)\n| where TimeGenerated > ago (24h)\n | where enableMultiCloudProfiles == false or toint(column_ifexists("Profile_d","")) != 1 \n|join kind=leftouter (itsgcodes) on itsgcode_s\n| project ["Item Name"]=strcat(iff(column_ifexists("Required_s", "")=="False","(R) ", "(M) "), column_ifexists("ItemName_s", "")),\n    Comments=column_ifexists("Comments_s", ""),\n    Status=case(column_ifexists("ComplianceStatus_b", bool(null)) == true, \'🟢\', column_ifexists("ComplianceStatus_b", bool(null)) == false, \'🔴\', \'➖\'),\n    ["ITSG Control"]=column_ifexists("itsgcode_s", ""),\n    Remediation=gr_geturl(replace_string(ctrlprefix," ",""),column_ifexists("itsgcode_s", "")),\n    Profile=iff(isnotempty(column_ifexists("Profile_d", "")), tostring(toint(column_ifexists("Profile_d", ""))), "")\n'
    functionAlias: 'gr_data3'
    functionParameters: 'ctrlprefix:string, ReportTime:string, showNonRequired:string'
    version: 2
  }
}
resource grpie 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_pie'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_pie'
    // NOTE: No interpolation used inside this query block. 
    query: '''
GuardrailsCompliance_CL
| where column_ifexists("ReportTime_s", "") == ReportTime
  and column_ifexists("Required_s", "") == tostring(Required)
  and column_ifexists("ControlName_s", "") has ctrlprefix
| extend Status = case(
      column_ifexists("ComplianceStatus_b", bool(null)) == true,  'Compliant Items',
      column_ifexists("ComplianceStatus_b", bool(null)) == false, 'Non-compliant Items',
      'Not Applicable Items'
  ),
  Title = 'Items by Compliance'
| summarize Total = count() by Status, Title
'''
    functionAlias: 'gr_pie'
    functionParameters: 'ctrlprefix:string, ReportTime:string, Required:string'
    version: 2
  }
} 
resource grpie3 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_pie3'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_pie3'
    // NOTE: No interpolation used inside this query block. 
    query: 'let enableMultiCloudProfiles = ${enableMultiCloudProfiles}; \n GuardrailsCompliance_CL | where enableMultiCloudProfiles == false or toint(column_ifexists("Profile_d","")) != 1 \n | where column_ifexists("ReportTime_s", "") == ReportTime and column_ifexists("Required_s", "") == tostring(Required) and column_ifexists("ControlName_s", "") has ctrlprefix \n | extend Status = case(column_ifexists("ComplianceStatus_b", bool(null)) == true, "Compliant Items", column_ifexists("ComplianceStatus_b", bool(null)) == false, "Non-compliant Items", "Not Applicable Items"), Title = "Items by Compliance" \n | summarize Total = count() by Status, Title'
    functionAlias: 'gr_pie3'
    functionParameters: 'ctrlprefix:string, ReportTime:string, Required:string'
    version: 2
  }
} 
resource grpie56 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_pie56'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_pie56'
    // NOTE: No interpolation used inside this query block. 
    query: 'let enableMultiCloudProfiles = ${enableMultiCloudProfiles};\n GuardrailsCompliance_CL | where enableMultiCloudProfiles == false or toint(column_ifexists("Profile_d","")) !in (1, 2) \n | where column_ifexists("ReportTime_s", "") == ReportTime and column_ifexists("Required_s", "") == tostring(Required) and column_ifexists("ControlName_s", "") has ctrlprefix \n | extend Status = case(column_ifexists("ComplianceStatus_b", bool(null)) == true, "Compliant Items", column_ifexists("ComplianceStatus_b", bool(null)) == false, "Non-compliant Items", "Not Applicable Items"), Title = "Items by Compliance" \n | summarize Total = count() by Status, Title'
    functionAlias: 'gr_pie56'
    functionParameters: 'ctrlprefix:string, ReportTime:string, Required:string'
    version: 2
  }
} 
resource grpieall 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_pie_all'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_pie_all'
    // NOTE: No interpolation used inside this query block. 
    query: '''
union 
    gr_pie("GUARDRAIL 1",ReportTime,  Required ),
    gr_pie("GUARDRAIL 2",ReportTime,  Required ),
    gr_pie3("GUARDRAIL 3",ReportTime,  Required ),
    gr_pie("GUARDRAIL 4",ReportTime,  Required ),
    gr_pie56("GUARDRAIL 5",ReportTime,  Required ),
    gr_pie56("GUARDRAIL 6",ReportTime,  Required ),
    gr_pie3("GUARDRAIL 7",ReportTime,  Required ),
    gr_pie("GUARDRAIL 8",ReportTime,  Required ),
    gr_pie3("GUARDRAIL 9",ReportTime,  Required ),
    gr_pie3("GUARDRAIL 10",ReportTime,  Required ),
    gr_pie3("GUARDRAIL 11",ReportTime,  Required ),
    gr_pie("GUARDRAIL 12",ReportTime,  Required ),
    gr_pie3("GUARDRAIL 13",ReportTime,  Required )
| summarize Total = sum(Total) by Status, Title
    '''
    functionAlias: 'gr_pie_all'
    functionParameters: 'ReportTime:string, Required:string'
    version: 2
  }
} 
resource f1 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
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
resource f3 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_data567'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_data567'
    query: 'let itsgcodes=GRITSGControls_CL | summarize arg_max(TimeGenerated, *) by itsgcode_s;\nGuardrailsCompliance_CL\n| where column_ifexists("ControlName_s", "") has ctrlprefix and column_ifexists("ReportTime_s", "") == ReportTime and column_ifexists("Required_s", "") != tostring(showNonRequired)\n| where TimeGenerated > ago (24h)\n|join kind=leftouter (itsgcodes) on itsgcode_s\n| project ["Item Name"]=strcat(iff(column_ifexists("Required_s", "")=="False","(R) ", "(M) "), column_ifexists("ItemName_s", "")),\n    ["Subscription Name"]=column_ifexists("DisplayName_s", ""),\n    Comments=column_ifexists("Comments_s", ""),\n    Status=case(column_ifexists("ComplianceStatus_b", bool(null)) == true, \'🟢\', column_ifexists("ComplianceStatus_b", bool(null)) == false, \'🔴\', \'➖\'),\n    ["ITSG Control"]=column_ifexists("itsgcode_s", ""),\n    Remediation=gr_geturl(replace_string(ctrlprefix," ",""),column_ifexists("itsgcode_s", "")),\n    Profile=iff(isnotempty(column_ifexists("Profile_d", "")), tostring(toint(column_ifexists("Profile_d", ""))), "")\n'
    functionAlias: 'gr_data567'
    functionParameters: 'ctrlprefix:string, ReportTime:string, showNonRequired:string'
    version: 2
  }
}
resource grdata56 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_data56'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_data56'
    query: 'let enableMultiCloudProfiles = ${enableMultiCloudProfiles}; \n let itsgcodes=GRITSGControls_CL | summarize arg_max(TimeGenerated, *) by itsgcode_s;\nGuardrailsCompliance_CL\n| where column_ifexists("ControlName_s", "") has ctrlprefix and column_ifexists("ReportTime_s", "") == ReportTime and column_ifexists("Required_s", "") != tostring(showNonRequired)\n| where TimeGenerated > ago (24h)\n|where enableMultiCloudProfiles == false or toint(column_ifexists("Profile_d","")) !in (1, 2) \n|join kind=leftouter (itsgcodes) on itsgcode_s\n| project ["Item Name"]=strcat(iff(column_ifexists("Required_s", "")=="False","(R) ", "(M) "), column_ifexists("ItemName_s", "")),\n    ["Subscription Name"]=column_ifexists("DisplayName_s", ""),\n    Comments=column_ifexists("Comments_s", ""),\n    Status=case(column_ifexists("ComplianceStatus_b", bool(null)) == true, \'🟢\', column_ifexists("ComplianceStatus_b", bool(null)) == false, \'🔴\', \'➖\'),\n    ["ITSG Control"]=column_ifexists("itsgcode_s", ""),\n    Remediation=gr_geturl(replace_string(ctrlprefix," ",""),column_ifexists("itsgcode_s", "")),\n    Profile=iff(isnotempty(column_ifexists("Profile_d", "")), tostring(toint(column_ifexists("Profile_d", ""))), "")\n'
    functionAlias: 'gr_data56'
    functionParameters: 'ctrlprefix:string, ReportTime:string, showNonRequired:string'
    version: 2
  }
}
resource grdata7 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_data7'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_data7'
    query: 'let enableMultiCloudProfiles = ${enableMultiCloudProfiles}; \nlet itsgcodes=GRITSGControls_CL | summarize arg_max(TimeGenerated, *) by itsgcode_s;\nGuardrailsCompliance_CL\n| where column_ifexists("ControlName_s", "") has ctrlprefix and column_ifexists("ReportTime_s", "") == ReportTime and column_ifexists("Required_s", "") != tostring(showNonRequired)\n| where TimeGenerated > ago (24h)\n|where enableMultiCloudProfiles == false or toint(column_ifexists("Profile_d","")) != 1 \n|join kind=leftouter (itsgcodes) on itsgcode_s\n| project ["Item Name"]=strcat(iff(column_ifexists("Required_s", "")=="False","(R) ", "(M) "), column_ifexists("ItemName_s", "")),\n    ["Subscription Name"]=column_ifexists("DisplayName_s", ""),\n    Comments=column_ifexists("Comments_s", ""),\n    Status=case(column_ifexists("ComplianceStatus_b", bool(null)) == true, \'🟢\', column_ifexists("ComplianceStatus_b", bool(null)) == false, \'🔴\', \'➖\'),\n    ["ITSG Control"]=column_ifexists("itsgcode_s", ""),\n    Remediation=gr_geturl(replace_string(ctrlprefix," ",""),column_ifexists("itsgcode_s", "")),\n    Profile=iff(isnotempty(column_ifexists("Profile_d", "")), tostring(toint(column_ifexists("Profile_d", ""))), "")\n'
    functionAlias: 'gr_data7'
    functionParameters: 'ctrlprefix:string, ReportTime:string, showNonRequired:string'
    version: 2
  }
}
resource grdata9 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_data9'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_data9'
    query: 'let enableMultiCloudProfiles = ${enableMultiCloudProfiles}; \n let itsgcodes=GRITSGControls_CL | where TimeGenerated == toscalar(GRITSGControls_CL | summarize by TimeGenerated | top 2 by TimeGenerated desc | top 1 by TimeGenerated asc | project TimeGenerated);\n GuardrailsCompliance_CL\n| where column_ifexists("ControlName_s", "") has ctrlprefix  and column_ifexists("ReportTime_s", "") == ReportTime and column_ifexists("Required_s", "") != tostring(showNonRequired)\n| where TimeGenerated > ago (24h)\n|where enableMultiCloudProfiles == false or toint(column_ifexists("Profile_d","")) != 1 \n|join kind=leftouter (itsgcodes) on itsgcode_s\r\n| project ["Item Name"]=column_ifexists("ItemName_s", ""), ["Subscription Name"]=column_ifexists("SubscriptionName_s", ""), ["VNet Name"]=column_ifexists("VNETName_s", ""), Status=case(column_ifexists("ComplianceStatus_b", bool(null)) == true, \'🟢\', column_ifexists("ComplianceStatus_b", bool(null)) == false, \'🔴\', \'➖\'), Comments=column_ifexists("Comments_s", ""), ["ITSG Control"]=column_ifexists("itsgcode_s", ""), Remediation=gr_geturl(replace_string(ctrlprefix," ",""),column_ifexists("itsgcode_s", "")), Profile=iff(isnotempty(column_ifexists("Profile_d", "")), tostring(toint(column_ifexists("Profile_d", ""))), "")\n'
    functionAlias: 'gr_data9'
    functionParameters: 'ctrlprefix:string, ReportTime:string, showNonRequired:string'
    version: 2
  }
}
resource f4 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_data11'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_data11'
    query: 'let enableMultiCloudProfiles = ${enableMultiCloudProfiles}; \n let itsgcodes=GRITSGControls_CL | summarize arg_max(TimeGenerated, *) by itsgcode_s;\nGuardrailsCompliance_CL\n| where column_ifexists("ControlName_s", "") has ctrlprefix and column_ifexists("ReportTime_s", "") == ReportTime and column_ifexists("Required_s", "") != tostring(showNonRequired)\n| where TimeGenerated > ago (24h)\n|where enableMultiCloudProfiles == false or toint(column_ifexists("Profile_d","")) != 1 \n|join kind=leftouter (itsgcodes) on itsgcode_s\n| project  ["Item Name"]=strcat(iff(column_ifexists("Required_s", "")=="False","(R) ", "(M) "), column_ifexists("ItemName_s", "")), ["Subscription Name"] = column_ifexists("SubscriptionName_s", ""), Comments=column_ifexists("Comments_s", ""), Status=case(column_ifexists("ComplianceStatus_b", bool(null)) == true, \'🟢\', column_ifexists("ComplianceStatus_b", bool(null)) == false, \'🔴\', \'➖\'),["ITSG Control"]=column_ifexists("itsgcode_s", ""), Remediation=gr_geturl(replace_string(ctrlprefix," ",""),column_ifexists("itsgcode_s", "")), Profile=iff(isnotempty(column_ifexists("Profile_d", "")), tostring(toint(column_ifexists("Profile_d", ""))), "")\n'
    functionAlias: 'gr_data11'
    functionParameters: 'ctrlprefix:string, ReportTime:string, showNonRequired:string'
    version: 2
  }
}
resource f5 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_mfa_evaluation'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_mfa_evaluation'
    query: '''
let reportTime = ReportTime;
let locale = toscalar(
    GR_TenantInfo_CL
    | summarize arg_max(ReportTime_s, *) by TenantDomain_s    | project Locale_s
    | take 1
);
let localizedMessages = case(
    locale == "fr-CA", dynamic({
        "allUsersHaveMFA": "Tous les comptes d'utilisateurs natifs ont 2+ méthodes d'authentification.",
        "usersWithoutMFA": "{0} utilisateurs n'ont pas d'AMF appropriée configurée sur {1} utilisateurs totaux",
        "noUsersFound": "Aucun utilisateur trouvé",
        "evaluationError": "Erreur d'évaluation: {0}",
        "dataCollectedForAnalysis": "Données collectées pour {0} utilisateurs. L'analyse détaillée de la conformité AMF sera effectuée dans le classeur."
    }),
    dynamic({
        "allUsersHaveMFA": "Native user accounts have been identified, and all users accounts have 2+ methods of authentication enabled.",
        "usersWithoutMFA": "{0} users do not have proper MFA configured out of {1} total users",
        "noUsersFound": "No users found",
        "evaluationError": "Evaluation error: {0}",
        "dataCollectedForAnalysis": "Data collected for {0} users. Detailed MFA compliance analysis will be performed in the workbook."
    })
);
// Cross-tenant MFA trust: Check if table exists and has data
let crossTenantDataExists = toscalar(
    union isfuzzy=true (
        GuardrailsCrossTenantAccess_CL | take 1 | summarize count()
    ), (
        print count_ = 0
    )
    | summarize sum(count_) > 0
);
let crossTenantSettings = union isfuzzy=true (
    GuardrailsCrossTenantAccess_CL
    | where column_ifexists("ReportTime_s", "") == reportTime
    | extend 
        PartnerTenantId = coalesce(
            tostring(column_ifexists("PartnerTenantId_g", "")),
            column_ifexists("PartnerTenantId_s", "")
        ),
        InboundMfaTrust = tobool(coalesce(column_ifexists("InboundTrustMfa_b", bool(null)), false)),
        HasGuestMfaPolicy = tobool(coalesce(column_ifexists("HasGuestMfaPolicy_b", bool(null)), false))
    | where isnotempty(PartnerTenantId)
    | summarize arg_max(TimeGenerated, *) by PartnerTenantId
), (
    print PartnerTenantId = "", InboundMfaTrust = false, HasGuestMfaPolicy = false, TimeGenerated = datetime(null)
    | where 1 == 0  // Empty result if table doesn't exist
);
let defaultMfaTrustSetting = toscalar(
    crossTenantSettings
    | where PartnerTenantId == "default"
    | project InboundMfaTrust
    | union (print InboundMfaTrust = false)
    | take 1
);
let hasGuestMfaPolicyConfigured = toscalar(
    crossTenantSettings
    | summarize HasPolicy = coalesce(max(HasGuestMfaPolicy), false)
    | project HasPolicy
);
let crossTenantFeatureEnabled = crossTenantDataExists and hasGuestMfaPolicyConfigured;
let rawUserData = GuardrailsUserRaw_CL
| extend ReportTime = column_ifexists("ReportTime_s", ""),
         guardrailsExcluded = tobool(coalesce(column_ifexists("guardrailsExcludedMfa_b", bool(null)), false)),
         userType = column_ifexists("userType_s", ""),
         homeTenantId = coalesce(
             tostring(column_ifexists("homeTenantId_g", "")),
             column_ifexists("homeTenantId_s", "")
         ),
         homeTenantResolved = tobool(coalesce(column_ifexists("homeTenantResolved_b", bool(null)), false))
| where ReportTime == reportTime;
let excludedUsers = rawUserData
| where guardrailsExcluded == true;
let guestUsers = rawUserData
| where guardrailsExcluded == false and userType == "Guest";
let memberUsers = rawUserData
| where guardrailsExcluded == false and userType != "Guest";
// Match each guest to their home tenant's MFA trust setting (only if feature is enabled)
let guestsWithTrustInfo = guestUsers
| extend guestHomeTenantId = case(
    // If resolution succeeded and no explicit tenant policy, use default
    homeTenantResolved == true and (isempty(homeTenantId) or isnull(homeTenantId)), "default",
    // If resolution succeeded and we have a tenant ID, use it
    homeTenantResolved == true and isnotempty(homeTenantId), homeTenantId,
    // If resolution failed, mark as unresolved (do NOT trust by default)
    homeTenantResolved == false, "unresolved",
    // Fallback for unexpected cases
    "unresolved"
)
| join kind=leftouter (
    crossTenantSettings
    | project PartnerTenantId, InboundMfaTrust
) on $left.guestHomeTenantId == $right.PartnerTenantId
| extend 
    effectiveMfaTrust = iff(crossTenantFeatureEnabled and guestHomeTenantId != "unresolved", coalesce(InboundMfaTrust, defaultMfaTrustSetting, false), false),
    shouldExcludeGuest = iff(crossTenantFeatureEnabled and guestHomeTenantId != "unresolved", 
        hasGuestMfaPolicyConfigured and coalesce(InboundMfaTrust, defaultMfaTrustSetting, false), 
        false);
let guestsToExclude = guestsWithTrustInfo
| where shouldExcludeGuest == true;
let guestsToEvaluate = guestsWithTrustInfo
| where shouldExcludeGuest == false
| project-away PartnerTenantId, InboundMfaTrust, effectiveMfaTrust, shouldExcludeGuest, guestHomeTenantId;
let excludedGuestCount = toscalar(guestsToExclude | summarize count());
let userData = union memberUsers, guestsToEvaluate;
let validSystemMethods = dynamic(["Fido2", "HardwareOTP"]);
let validMfaMethods = dynamic(["microsoftAuthenticatorPush", "mobilePhone", "softwareOneTimePasscode", "passKeyDeviceBound", "windowsHelloForBusiness", "fido2SecurityKey", "passKeyDeviceBoundAuthenticator", "passKeyDeviceBoundWindowsHello", "temporaryAccessPass"]);
let mfaAnalysis = userData
| extend 
    sysPreferredValue = column_ifexists("systemPreferredAuthenticationMethods_s", ""),
    methodsRegisteredValue = column_ifexists("methodsRegistered_s", ""),
    isSystemPreferredEnabled = tobool(column_ifexists("isSystemPreferredAuthenticationMethodEnabled_b", "false"))
| extend
    systemPreferredMethodsArray = iff(
        isnotempty(sysPreferredValue) and sysPreferredValue startswith "[",
        parse_json(sysPreferredValue),
        iff(isnotempty(sysPreferredValue), pack_array(sysPreferredValue), dynamic([]))
    ),
    methodsRegisteredArray = iff(isnotempty(methodsRegisteredValue), parse_json(methodsRegisteredValue), dynamic([]))
| extend
    hasValidSystemPreferred = iff(
        isSystemPreferredEnabled == true and isnotempty(systemPreferredMethodsArray),
        array_length(set_intersect(systemPreferredMethodsArray, validSystemMethods)) > 0,
        false
    ),
    hasMfaRegistered = tobool(column_ifexists("isMfaRegistered_b", "false"))
| extend
    validMfaMethodsCount = iff(
        hasMfaRegistered == true and isnotempty(methodsRegisteredArray),
        array_length(set_intersect(methodsRegisteredArray, validMfaMethods)),
        0
    )
| extend
    isMfaCompliant = hasValidSystemPreferred or (hasMfaRegistered == true and validMfaMethodsCount >= 1);
let summary = mfaAnalysis
| summarize 
    TotalUsers = count(),
    CompliantUsers = countif(isMfaCompliant == true),
    NonCompliantUsers = countif(isMfaCompliant == false) 
| extend 
    IsCompliant = NonCompliantUsers == 0,
    Comments = case(
        TotalUsers == 0, localizedMessages["noUsersFound"],
        NonCompliantUsers == 0, localizedMessages["allUsersHaveMFA"],
        NonCompliantUsers > 0, strcat(
            iff(locale == "fr-CA", 
                strcat(tostring(NonCompliantUsers), " utilisateurs n'ont pas d'AMF appropriée configurée sur ", tostring(TotalUsers), " utilisateurs totaux"),
                strcat(tostring(NonCompliantUsers), " users do not have proper MFA configured out of ", tostring(TotalUsers), " total users")
            ), 
            " (", tostring(NonCompliantUsers), " non-compliant, ", tostring(CompliantUsers), " compliant)"
        ),
        "Unknown error"
    );
let excludedCount = toscalar(excludedUsers | summarize count());
let finalSummary = summary
| extend Comments = iff(coalesce(excludedCount, 0) > 0,
        strcat(Comments, "; ", iff(locale == "fr-CA",
            strcat("Exclusion de ", tostring(coalesce(excludedCount, 0)), " comptes de service via l'attribut de sécurité GCCloudGuardrails.ExcludeFromMFA"),
            strcat("Excluded ", tostring(coalesce(excludedCount, 0)), " service accounts via GCCloudGuardrails.ExcludeFromMFA custom security attribute"))),
        Comments)
| extend Comments = iff(crossTenantFeatureEnabled and excludedGuestCount > 0,
        strcat(Comments, "; ", iff(locale == "fr-CA",
            strcat("Exclusion de ", tostring(excludedGuestCount), " comptes invités avec confiance AMF inter-locataire et politique d'accès conditionnel"),
            strcat("Excluded ", tostring(excludedGuestCount), " guest accounts with cross-tenant MFA trust and conditional access policy"))),
        Comments);
finalSummary
| project 
    ControlName = iff(locale == "fr-CA", "GUARDRAIL 1: PROTÉGER LES COMPTES ET LES IDENTITÉS DES UTILISATEURS", "GUARDRAIL 1: PROTECT USER ACCOUNTS AND IDENTITIES"),
    ItemName = iff(locale == "fr-CA", "Vérification de l'AMF de tous les comptes d'utilisateurs infonuagiques", "All Cloud User Accounts MFA Check"),
    ReportTime = reportTime,
    ComplianceStatus = IsCompliant,
    Comments = Comments,
    itsgcode = "IA2(1)",
    TimeGenerated = now()
'''
    functionAlias: 'gr_mfa_evaluation'
    functionParameters: 'ReportTime:string'
    version: 2
  }
}

resource f6 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_non_mfa_users'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_non_mfa_users'
    query: '''
let reportTime = ReportTime;
let locale = toscalar(
    GR_TenantInfo_CL
    | summarize arg_max(ReportTime_s, *) by TenantDomain_s
    | project Locale_s
    | take 1
);
let localizedMessages = case(
    locale == "fr-CA", dynamic({
        "systemPreferred": "Authentification préférée du système : ",
        "mfaRegistered": "AMF enregistrée avec les méthodes : ",
        "onlyOneMethod": "Seulement 1 méthode AMF trouvée : ",
        "atLeastTwoRequired": ". Au moins 2 requises.",
        "noValidMethods": "Aucune méthode AMF valide trouvée. Au moins 2 requises.",
        "noMfaConfigured": "Aucune AMF configurée",
        "neverSignedIn": "Jamais connecté",
        "noNonCompliantUsers": "Aucun utilisateur non conforme trouvé"
    }),
    dynamic({
        "systemPreferred": "System preferred authentication: ",
        "mfaRegistered": "MFA registered with methods: ",
        "onlyOneMethod": "Only 1 MFA method found: ",
        "atLeastTwoRequired": ". At least 2 required.",
        "noValidMethods": "No valid MFA methods found. At least 2 required.",
        "noMfaConfigured": "No MFA configured",
        "neverSignedIn": "Never Signed In",
        "noNonCompliantUsers": "No non-compliant users found"
    })
);
// Cross-tenant MFA trust: Check if table exists and has data
let crossTenantDataExists = toscalar(
    union isfuzzy=true (
        GuardrailsCrossTenantAccess_CL | take 1 | summarize count()
    ), (
        print count_ = 0
    )
    | summarize sum(count_) > 0
);
let crossTenantSettings = union isfuzzy=true (
    GuardrailsCrossTenantAccess_CL
    | where column_ifexists("ReportTime_s", "") == reportTime
    | extend 
        PartnerTenantId = coalesce(
            tostring(column_ifexists("PartnerTenantId_g", "")),
            column_ifexists("PartnerTenantId_s", "")
        ),
        InboundMfaTrust = tobool(coalesce(column_ifexists("InboundTrustMfa_b", bool(null)), false)),
        HasGuestMfaPolicy = tobool(coalesce(column_ifexists("HasGuestMfaPolicy_b", bool(null)), false))
    | where isnotempty(PartnerTenantId)
    | summarize arg_max(TimeGenerated, *) by PartnerTenantId
), (
    print PartnerTenantId = "", InboundMfaTrust = false, HasGuestMfaPolicy = false, TimeGenerated = datetime(null)
    | where 1 == 0  // Empty result if table doesn't exist
);
let defaultMfaTrustSetting = toscalar(
    crossTenantSettings
    | where PartnerTenantId == "default"
    | project InboundMfaTrust
    | union (print InboundMfaTrust = false)
    | take 1
);
let hasGuestMfaPolicyConfigured = toscalar(
    crossTenantSettings
    | summarize HasPolicy = coalesce(max(HasGuestMfaPolicy), false)
    | project HasPolicy
);
let crossTenantFeatureEnabled = crossTenantDataExists and hasGuestMfaPolicyConfigured;
let userData = GuardrailsUserRaw_CL
| extend ReportTime = column_ifexists("ReportTime_s", ""),
         guardrailsExcluded = tobool(coalesce(column_ifexists("guardrailsExcludedMfa_b", bool(null)), false)),
         userType = column_ifexists("userType_s", ""),
         homeTenantId = coalesce(
             tostring(column_ifexists("homeTenantId_g", "")),
             column_ifexists("homeTenantId_s", "")
         ),
         homeTenantResolved = tobool(coalesce(column_ifexists("homeTenantResolved_b", bool(null)), false))
| where ReportTime == reportTime
| where guardrailsExcluded == false;
let validSystemMethods = dynamic(["Fido2", "HardwareOTP"]);
let validMfaMethods = dynamic(["microsoftAuthenticatorPush", "mobilePhone", "softwareOneTimePasscode", "passKeyDeviceBound", "windowsHelloForBusiness", "fido2SecurityKey", "passKeyDeviceBoundAuthenticator", "passKeyDeviceBoundWindowsHello", "temporaryAccessPass"]);
let mfaAnalysis = userData
| extend 
    sysPreferredValue = column_ifexists("systemPreferredAuthenticationMethods_s", ""),
    methodsRegisteredValue = column_ifexists("methodsRegistered_s", ""),
    isSystemPreferredEnabled = tobool(column_ifexists("isSystemPreferredAuthenticationMethodEnabled_b", "false"))
| extend
    systemPreferredMethodsArray = iff(
        isnotempty(sysPreferredValue) and sysPreferredValue startswith "[",
        parse_json(sysPreferredValue),
        iff(isnotempty(sysPreferredValue), pack_array(sysPreferredValue), dynamic([]))
    ),
    methodsRegisteredArray = iff(isnotempty(methodsRegisteredValue), parse_json(methodsRegisteredValue), dynamic([]))
| extend
    hasValidSystemPreferred = iff(
        isSystemPreferredEnabled == true and isnotempty(systemPreferredMethodsArray),
        array_length(set_intersect(systemPreferredMethodsArray, validSystemMethods)) > 0,
        false
    ),
    hasMfaRegistered = tobool(column_ifexists("isMfaRegistered_b", "false"))
| extend
    validMfaMethodsCount = iff(
        hasMfaRegistered == true and isnotempty(methodsRegisteredArray),
        array_length(set_intersect(methodsRegisteredArray, validMfaMethods)),
        0
    )
| extend
    isMfaCompliant = hasValidSystemPreferred or (hasMfaRegistered == true and validMfaMethodsCount >= 1),
    complianceReason = case(
        hasValidSystemPreferred, strcat(tostring(localizedMessages["systemPreferred"]), strcat_array(set_intersect(systemPreferredMethodsArray, validSystemMethods), ", ")),
        hasMfaRegistered == true and validMfaMethodsCount >= 1, strcat(tostring(localizedMessages["mfaRegistered"]), strcat_array(set_intersect(methodsRegisteredArray, validMfaMethods), ", ")),
        hasMfaRegistered == true and validMfaMethodsCount == 0, tostring(localizedMessages["noValidMethods"]),
        tostring(localizedMessages["noMfaConfigured"])
    );
let nonCompliantUsers = mfaAnalysis
| where isMfaCompliant == false
| extend guestHomeTenantId = case(
    // If resolution succeeded and no explicit tenant policy, use default
    homeTenantResolved == true and (isempty(homeTenantId) or isnull(homeTenantId)), "default",
    // If resolution succeeded and we have a tenant ID, use it
    homeTenantResolved == true and isnotempty(homeTenantId), homeTenantId,
    // If resolution failed, mark as unresolved (do NOT trust by default)
    homeTenantResolved == false, "unresolved",
    // Fallback for unexpected cases
    "unresolved"
)
| join kind=leftouter (
    crossTenantSettings
    | project PartnerTenantId, InboundMfaTrust
) on $left.guestHomeTenantId == $right.PartnerTenantId
| extend 
    effectiveMfaTrust = iff(crossTenantFeatureEnabled and guestHomeTenantId != "unresolved", coalesce(InboundMfaTrust, defaultMfaTrustSetting, false), false),
    shouldExcludeGuest = iff(crossTenantFeatureEnabled and userType == "Guest" and guestHomeTenantId != "unresolved",
        hasGuestMfaPolicyConfigured and coalesce(InboundMfaTrust, defaultMfaTrustSetting, false),
        false)
| where shouldExcludeGuest == false
| sort by signInActivity_lastSignInDateTime_t
| project 
    DisplayName = column_ifexists("displayName_s", ""), 
    UserPrincipalName = column_ifexists("userPrincipalName_s", ""), 
    UserType = column_ifexists("userType_s", ""), 
    CreatedTimeRaw = column_ifexists("createdDateTime_t", datetime(null)), 
    LastSignInRaw = column_ifexists("signInActivity_lastSignInDateTime_t", datetime(null)),
    Comments = complianceReason
| extend CreatedTime = iff(isnull(CreatedTimeRaw), "N/A", format_datetime(CreatedTimeRaw, 'yyyy-MM-dd HH:mm:ss')),
        LastSignIn = iff(isnull(LastSignInRaw), tostring(localizedMessages["neverSignedIn"]), format_datetime(LastSignInRaw, 'yyyy-MM-dd HH:mm:ss'))
| project DisplayName, UserPrincipalName, UserType, CreatedTime, LastSignIn, Comments
| take 100;
union
(
    nonCompliantUsers
),
(
    nonCompliantUsers
    | summarize count() 
    | where count_ == 0
    | project 
        DisplayName = "N/A", 
        UserPrincipalName = "N/A", 
        UserType = "N/A", 
        CreatedTime = "N/A", 
        LastSignIn = "N/A",
        Comments = tostring(localizedMessages["noNonCompliantUsers"])
)
'''
    functionAlias: 'gr_non_mfa_users'
    functionParameters: 'ReportTime:string'
    version: 2
  }
}
resource guarrailsWorkbooks 'Microsoft.Insights/workbooks@2021-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
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

resource grSummaryByPrefix 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_summary_by_prefix'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_summary_by_prefix'
    // KQL function: summarize per Guardrail (e.g., GR1, GR2, ...)
    // Parameters:
    //  - ReportTime: exact report timestamp (string) to match records
    //  - TimeWindowHours: lookback window in hours
    //  - showNonRequired: string toggle; when "False", only mandatory (Required_s == "True")
    query: 'let windowHours = toint(TimeWindowHours);\nlet base = GuardrailsCompliance_CL\n| where TimeGenerated > ago(windowHours * 1h)\n| where column_ifexists("ReportTime_s","") == ReportTime\n| where column_ifexists("ControlName_s","") has Guardrail\n| where isempty(showIfRequired) or column_ifexists("Required_s","") == tostring(showIfRequired);\nbase\n| extend ComplianceStatus = column_ifexists("ComplianceStatus_b", bool(null))\n| summarize TotalControls = count(), NonCompliantItems = countif(ComplianceStatus == false), UnknownItems = countif(isnull(ComplianceStatus))\n| extend HasNonCompliance = NonCompliantItems > 0\n| extend Status = iff(HasNonCompliance, "🔴", "🟢")\n| project Guardrail, ["Total # Controls"]=TotalControls, ["NonCompliant Items"]=NonCompliantItems, ["Unknown Items"]=UnknownItems, Status'
    functionAlias: 'gr_summary_by_prefix'
    functionParameters: 'Guardrail:string, ReportTime:string, TimeWindowHours:int, showIfRequired:string'
    version: 2 
  }
}
resource grSummaryByPrefixa 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_summary_by_prefix_a'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_summary_by_prefix_a'
    // KQL function: summarize per Guardrail, nonCompliant number includes both mandatory and recommended controls, but status only reflects mandatory controls
    query: 'let windowHours = toint(TimeWindowHours);\nlet base = GuardrailsCompliance_CL\n| where TimeGenerated > ago(windowHours * 1h)\n| where column_ifexists("ReportTime_s","") == ReportTime\n| where column_ifexists("ControlName_s","") has Guardrail\n| where isempty(showIfRequired) or column_ifexists("Required_s","") == tostring(showIfRequired);\nbase\n| extend ComplianceStatus = column_ifexists("ComplianceStatus_b", bool(null))\n| summarize TotalControls = count(), NonCompliantItems = countif(ComplianceStatus == false), NonCompliantItems1 = countif(ComplianceStatus == false  and column_ifexists("Required_s","") == "True"), UnknownItems = countif(isnull(ComplianceStatus))\n| extend HasNonCompliance = NonCompliantItems1 > 0\n| extend Status = iff(HasNonCompliance, "🔴", "🟢")\n| project Guardrail, ["Total # Controls"]=TotalControls, ["NonCompliant Items"]=NonCompliantItems, ["Unknown Items"]=UnknownItems, Status'
    functionAlias: 'gr_summary_by_prefix_a'
    functionParameters: 'Guardrail:string, ReportTime:string, TimeWindowHours:int, showIfRequired:string'
    version: 2 
  }
}
resource grSummaryByPrefix3 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_summary_by_prefix3'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_summary_by_prefix3'
    // KQL function: summarize per Guardrail (e.g., GR1, GR2, ...)
    // Parameters:
    //  - ReportTime: exact report timestamp (string) to match records
    //  - TimeWindowHours: lookback window in hours
    //  - showNonRequired: string toggle; when "False", only mandatory (Required_s == "True")
    query: 'let enableMultiCloudProfiles = ${enableMultiCloudProfiles}; \n let windowHours = toint(TimeWindowHours);\nlet base = GuardrailsCompliance_CL\n| where enableMultiCloudProfiles == false or toint(column_ifexists("Profile_d","")) != 1 \n | where TimeGenerated > ago(windowHours * 1h)\n| where column_ifexists("ReportTime_s","") == ReportTime\n| where column_ifexists("ControlName_s","") has Guardrail\n| where isempty(showIfRequired) or column_ifexists("Required_s","") == tostring(showIfRequired);\nbase\n| extend ComplianceStatus = column_ifexists("ComplianceStatus_b", bool(null))\n| summarize TotalControls = count(), NonCompliantItems = countif(ComplianceStatus == false), UnknownItems = countif(isnull(ComplianceStatus))\n| extend HasNonCompliance = NonCompliantItems > 0\n| extend Status = iff(HasNonCompliance, "🔴", "🟢")\n| project Guardrail, ["Total # Controls"]=TotalControls, ["NonCompliant Items"]=NonCompliantItems, ["Unknown Items"]=UnknownItems, Status'
    functionAlias: 'gr_summary_by_prefix3'
    functionParameters: 'Guardrail:string, ReportTime:string, TimeWindowHours:int, showIfRequired:string'
    version: 2 
  }
}
resource grSummaryByPrefix3a 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_summary_by_prefix3a'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_summary_by_prefix3a'
    // KQL function: summarize per Guardrail (e.g., GR1, GR2, ...)
    // Parameters:
    //  - ReportTime: exact report timestamp (string) to match records
    //  - TimeWindowHours: lookback window in hours
    //  - showNonRequired: string toggle; when "False", only mandatory (Required_s == "True")
    // status only reflects mandatory controls
    query: 'let enableMultiCloudProfiles = ${enableMultiCloudProfiles}; \n let windowHours = toint(TimeWindowHours);\nlet base = GuardrailsCompliance_CL\n| where enableMultiCloudProfiles == false or toint(column_ifexists("Profile_d","")) != 1 \n | where TimeGenerated > ago(windowHours * 1h)\n| where column_ifexists("ReportTime_s","") == ReportTime\n| where column_ifexists("ControlName_s","") has Guardrail\n| where isempty(showIfRequired) or column_ifexists("Required_s","") == tostring(showIfRequired);\nbase\n| extend ComplianceStatus = column_ifexists("ComplianceStatus_b", bool(null))\n| summarize TotalControls = count(), NonCompliantItems = countif(ComplianceStatus == false), NonCompliantItems1 = countif(ComplianceStatus == false and column_ifexists("Required_s","") == "True"), UnknownItems = countif(isnull(ComplianceStatus))\n| extend HasNonCompliance = NonCompliantItems1 > 0\n| extend Status = iff(HasNonCompliance, "🔴", "🟢")\n| project Guardrail, ["Total # Controls"]=TotalControls, ["NonCompliant Items"]=NonCompliantItems, ["Unknown Items"]=UnknownItems, Status'
    functionAlias: 'gr_summary_by_prefix3a'
    functionParameters: 'Guardrail:string, ReportTime:string, TimeWindowHours:int, showIfRequired:string'
    version: 2 
  }
}
resource grSummaryByPrefix56 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_summary_by_prefix56'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_summary_by_prefix56'
    // KQL function: summarize per Guardrail (e.g., GR1, GR2, ...)
    // Parameters:
    //  - ReportTime: exact report timestamp (string) to match records
    //  - TimeWindowHours: lookback window in hours
    //  - showNonRequired: string toggle; when "False", only mandatory (Required_s == "True")
    query: 'let enableMultiCloudProfiles = ${enableMultiCloudProfiles}; \n let windowHours = toint(TimeWindowHours);\nlet base = GuardrailsCompliance_CL\n| where enableMultiCloudProfiles == false or toint(column_ifexists("Profile_d","")) !in (1, 2) \n | where TimeGenerated > ago(windowHours * 1h)\n| where column_ifexists("ReportTime_s","") == ReportTime\n| where column_ifexists("ControlName_s","") has Guardrail\n| where isempty(showIfRequired) or column_ifexists("Required_s","") == tostring(showIfRequired);\nbase\n| extend ComplianceStatus = column_ifexists("ComplianceStatus_b", bool(null))\n| summarize TotalControls = count(), NonCompliantItems = countif(ComplianceStatus == false), UnknownItems = countif(isnull(ComplianceStatus))\n| extend HasNonCompliance = NonCompliantItems > 0\n| extend Status = iff(HasNonCompliance, "🔴", "🟢")\n| project Guardrail, ["Total # Controls"]=TotalControls, ["NonCompliant Items"]=NonCompliantItems, ["Unknown Items"]=UnknownItems, Status'
    functionAlias: 'gr_summary_by_prefix56'
    functionParameters: 'Guardrail:string, ReportTime:string, TimeWindowHours:int, showIfRequired:string'
    version: 2 
  }
}
resource grSummaryByPrefix56a 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_summary_by_prefix56a'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_summary_by_prefix56a'
    // KQL function: summarize per Guardrail (e.g., GR1, GR2, ...)
    // Parameters:
    //  - ReportTime: exact report timestamp (string) to match records
    //  - TimeWindowHours: lookback window in hours
    //  - showNonRequired: string toggle; when "False", only mandatory (Required_s == "True")
    // status only reflects mandatory controls
    query: 'let enableMultiCloudProfiles = ${enableMultiCloudProfiles}; \n let windowHours = toint(TimeWindowHours);\nlet base = GuardrailsCompliance_CL\n| where enableMultiCloudProfiles == false or toint(column_ifexists("Profile_d","")) !in (1, 2) \n | where TimeGenerated > ago(windowHours * 1h)\n| where column_ifexists("ReportTime_s","") == ReportTime\n| where column_ifexists("ControlName_s","") has Guardrail\n| where isempty(showIfRequired) or column_ifexists("Required_s","") == tostring(showIfRequired);\nbase\n| extend ComplianceStatus = column_ifexists("ComplianceStatus_b", bool(null))\n| summarize TotalControls = count(), NonCompliantItems = countif(ComplianceStatus == false), NonCompliantItems1 = countif(ComplianceStatus == false and column_ifexists("Required_s","") == "True"), UnknownItems = countif(isnull(ComplianceStatus))\n| extend HasNonCompliance = NonCompliantItems1 > 0\n| extend Status = iff(HasNonCompliance, "🔴", "🟢")\n| project Guardrail, ["Total # Controls"]=TotalControls, ["NonCompliant Items"]=NonCompliantItems, ["Unknown Items"]=UnknownItems, Status'
    functionAlias: 'gr_summary_by_prefix56a'
    functionParameters: 'Guardrail:string, ReportTime:string, TimeWindowHours:int, showIfRequired:string'
    version: 2 
  }
}
resource grSummaryByPrefixAll 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_summary_by_prefix_all'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_summary_by_prefix_all'
    // KQL function: summarize per Guardrail (e.g., GR1, GR2, ...)
    // Parameters:
    //  - ReportTime: exact report timestamp (string) to match records
    //  - showIfRequired: string toggle; when "False", only mandatory (Required_s == "True")
    query: '''
union
    gr_summary_by_prefix("GUARDRAIL 1", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix("GUARDRAIL 2", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix3("GUARDRAIL 3", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix("GUARDRAIL 4", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix56("GUARDRAIL 5", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix56("GUARDRAIL 6", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix3("GUARDRAIL 7", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix("GUARDRAIL 8", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix3("GUARDRAIL 9", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix3("GUARDRAIL 10", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix3("GUARDRAIL 11", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix("GUARDRAIL 12", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix3("GUARDRAIL 13", ReportTime, TimeWindowHours, showIfRequired)
| order by toint(extract(@"\d+", 0, Guardrail)) asc
'''
    functionAlias: 'gr_summary_by_prefix_all'
    functionParameters: 'ReportTime:string, TimeWindowHours:int, showIfRequired:string'
    version: 2
  }
}
resource grSummaryByPrefixAlla 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_summary_by_prefix_alla'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_summary_by_prefix_alla'
    // KQL function: summarize per Guardrail (e.g., GR1, GR2, ...)
    // Parameters:
    //  - ReportTime: exact report timestamp (string) to match records
    //  - showIfRequired: string toggle; when "False", only mandatory (Required_s == "True")
    // status only reflects mandatory controls
    query: '''
union
    gr_summary_by_prefix_a("GUARDRAIL 1", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix_a("GUARDRAIL 2", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix3a("GUARDRAIL 3", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix_a("GUARDRAIL 4", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix56a("GUARDRAIL 5", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix56a("GUARDRAIL 6", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix3a("GUARDRAIL 7", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix_a("GUARDRAIL 8", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix3a("GUARDRAIL 9", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix3a("GUARDRAIL 10", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix3a("GUARDRAIL 11", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix_a("GUARDRAIL 12", ReportTime, TimeWindowHours, showIfRequired),
    gr_summary_by_prefix3a("GUARDRAIL 13", ReportTime, TimeWindowHours, showIfRequired)
| order by toint(extract(@"\d+", 0, Guardrail)) asc
'''
    functionAlias: 'gr_summary_by_prefix_alla'
    functionParameters: 'ReportTime:string, TimeWindowHours:int, showIfRequired:string'
    version: 2
  }
}
resource grSummaryAll 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_summary_all'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_summary_all'
    // KQL function: summarize for all Guardrail (e.g., GR1, GR2, ...)
    // status only reflects mandatory controls
    query: '''
union isfuzzy=true
  (gr_summary_by_prefix_a("GUARDRAIL 1",  ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix_a("GUARDRAIL 2",  ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix3a("GUARDRAIL 3", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix_a("GUARDRAIL 4",  ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix56a("GUARDRAIL 5", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix56a("GUARDRAIL 6", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix3a("GUARDRAIL 7", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix_a("GUARDRAIL 8",  ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix3a("GUARDRAIL 9", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix3a("GUARDRAIL 10", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix3a("GUARDRAIL 11", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix_a("GUARDRAIL 12", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix3a("GUARDRAIL 13", ReportTime, TimeWindowHours, showIfRequired))
| project
    TotalControls_norm     = tolong(column_ifexists("TotalControls",      column_ifexists("Total # Controls", 0))),
    NonCompliantItems_norm = tolong(column_ifexists("NonCompliantItems",  column_ifexists("NonCompliant Items", 0))),
    UnknownItems_norm      = tolong(column_ifexists("UnknownItems",       column_ifexists("Unknown Items", 0)))
| summarize
    TotalControls     = sum(TotalControls_norm),
    NonCompliantItems = sum(NonCompliantItems_norm),
    UnknownItems      = sum(UnknownItems_norm)
| extend HasNonCompliance = NonCompliantItems > 0
| extend Status = iff(HasNonCompliance, "🔴", "🟢")
| project ["Guardrail"] = "All Guardrails",
         ["Total # Controls"] = TotalControls,
         ["NonCompliant Items"] = NonCompliantItems,
         ["Unknown Items"] = UnknownItems,
         Status
'''


    functionAlias: 'gr_summary_all'
    functionParameters: 'ReportTime:string, TimeWindowHours:int, showIfRequired:string'
    version: 2
  }
}
resource grSummaryMandatory 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_summary_mandatory'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_summary_mandatory'
    // KQL function: summarize per Guardrail (e.g., GR1, GR2, ...)
    // Parameters:
    //  - ReportTime: exact report timestamp (string) to match records
    //  - showIfRequired: string toggle; when "False", only mandatory (Required_s == "True")
    query: '''
union isfuzzy=true
  (gr_summary_by_prefix("GUARDRAIL 1",  ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix("GUARDRAIL 2",  ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix3("GUARDRAIL 3", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix("GUARDRAIL 4",  ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix56("GUARDRAIL 5", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix56("GUARDRAIL 6", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix3("GUARDRAIL 7", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix("GUARDRAIL 8",  ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix3("GUARDRAIL 9", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix3("GUARDRAIL 10", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix3("GUARDRAIL 11", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix("GUARDRAIL 12", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix3("GUARDRAIL 13", ReportTime, TimeWindowHours, showIfRequired))
| project
    TotalControls_norm     = tolong(column_ifexists("TotalControls",      column_ifexists("Total # Controls", 0))),
    NonCompliantItems_norm = tolong(column_ifexists("NonCompliantItems",  column_ifexists("NonCompliant Items", 0))),
    UnknownItems_norm      = tolong(column_ifexists("UnknownItems",       column_ifexists("Unknown Items", 0)))
| summarize
    TotalControls     = sum(TotalControls_norm),
    NonCompliantItems = sum(NonCompliantItems_norm),
    UnknownItems      = sum(UnknownItems_norm)
| extend HasNonCompliance = NonCompliantItems > 0
| extend Status = iff(HasNonCompliance, "🔴", "🟢")
| project ["Guardrail"] = "Mandatory Guardrails",
         ["Total # Controls"] = TotalControls,
         ["NonCompliant Items"] = NonCompliantItems,
         ["Unknown Items"] = UnknownItems,
         Status
'''


    functionAlias: 'gr_summary_mandatory'
    functionParameters: 'ReportTime:string, TimeWindowHours:int, showIfRequired:string'
    version: 2
  }
}
resource grSummaryRecommended 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_summary_recommended'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_summary_recommended'
    // KQL function: summarize per Guardrail (e.g., GR1, GR2, ...)
    // Parameters:
    //  - ReportTime: exact report timestamp (string) to match records
    //  - showIfRequired: string toggle; when "False", only mandatory (Required_s == "True")
    query: '''
union isfuzzy=true
  (gr_summary_by_prefix("GUARDRAIL 1",  ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix("GUARDRAIL 2",  ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix3("GUARDRAIL 3", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix("GUARDRAIL 4",  ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix56("GUARDRAIL 5", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix56("GUARDRAIL 6", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix3("GUARDRAIL 7", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix("GUARDRAIL 8",  ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix3("GUARDRAIL 9", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix3("GUARDRAIL 10", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix3("GUARDRAIL 11", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix("GUARDRAIL 12", ReportTime, TimeWindowHours, showIfRequired)),
  (gr_summary_by_prefix3("GUARDRAIL 13", ReportTime, TimeWindowHours, showIfRequired))
| project
    TotalControls_norm     = tolong(column_ifexists("TotalControls",      column_ifexists("Total # Controls", 0))),
    NonCompliantItems_norm = tolong(column_ifexists("NonCompliantItems",  column_ifexists("NonCompliant Items", 0))),
    UnknownItems_norm      = tolong(column_ifexists("UnknownItems",       column_ifexists("Unknown Items", 0)))
| summarize
    TotalControls     = sum(TotalControls_norm),
    NonCompliantItems = sum(NonCompliantItems_norm),
    UnknownItems      = sum(UnknownItems_norm)
| extend HasNonCompliance = NonCompliantItems > 0
| extend Status = iff(HasNonCompliance, "🔴", "🟢")
| project ["Guardrail"] = "Recommended Guardrails",
         ["Total # Controls"] = TotalControls,
         ["NonCompliant Items"] = NonCompliantItems,
         ["Unknown Items"] = UnknownItems,
         Status
'''


    functionAlias: 'gr_summary_recommended'
    functionParameters: 'ReportTime:string, TimeWindowHours:int, showIfRequired:string'
    version: 2
  }
}
resource grSummary 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook || updateCoreResources) {
  name: 'gr_summary'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_summary'
    // KQL function: summarize per Guardrail (e.g., GR1, GR2, ...)
    // Parameters:
    //  - ReportTime: exact report timestamp (string) to match records
    //  - showIfRequired: string toggle; when "False", only mandatory (Required_s == "True")
    query: '''
union
    gr_summary_all(ReportTime, TimeWindowHours, ""),
    gr_summary_mandatory(ReportTime, TimeWindowHours, true),
    gr_summary_recommended(ReportTime, TimeWindowHours, false)
'''
    functionAlias: 'gr_summary'
    functionParameters: 'ReportTime:string, TimeWindowHours:int'
    version: 2
  }
}
output logAnalyticsWorkspaceId string = guardrailsLogAnalytics.properties.customerId 
output logAnalyticsResourceId string = guardrailsLogAnalytics.id
