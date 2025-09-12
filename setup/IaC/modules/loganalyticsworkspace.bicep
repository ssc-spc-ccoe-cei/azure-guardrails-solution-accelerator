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
    query: 'let itsgcodes=GRITSGControls_CL | summarize arg_max(TimeGenerated, *) by itsgcode_s;\nGuardrailsCompliance_CL\n| where ControlName_s has ctrlprefix and ReportTime_s == ReportTime and Required_s != tostring(showNonRequired)\n| where TimeGenerated > ago (24h)\n|join kind=inner (itsgcodes) on itsgcode_s\n| project ["Item Name"]=strcat(ItemName_s, iff(Required_s=="False"," (R)", " (M)")), Comments=Comments_s, Status=case(ComplianceStatus_b == true, \'✔️\', ComplianceStatus_b == false, \'❌\', \'➖\'),["ITSG Control"]=itsgcode_s, Remediation=gr_geturl(replace_string(ctrlprefix," ",""),itsgcode_s), Profile=iff(isnotempty(column_ifexists("Profile_d", "")), tostring(toint(column_ifexists("Profile_d", ""))), "")\n'
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
    query: 'let itsgcodes=GRITSGControls_CL | summarize arg_max(TimeGenerated, *) by itsgcode_s;\nGuardrailsCompliance_CL\n| where ControlName_s has ctrlprefix and ReportTime_s == ReportTime and Required_s != tostring(showNonRequired)\n| where TimeGenerated > ago (24h)\n|join kind=inner (itsgcodes) on itsgcode_s\n| project ["Item Name"]=strcat(ItemName_s, iff(Required_s=="False"," (R)", " (M)")), ["Subscription Name"]=DisplayName_s, Comments=Comments_s, Status=case(ComplianceStatus_b == true, \'✔️\', ComplianceStatus_b == false, \'❌\', \'➖\'),["ITSG Control"]=itsgcode_s, Remediation=gr_geturl(replace_string(ctrlprefix," ",""),itsgcode_s), Profile=iff(isnotempty(column_ifexists("Profile_d", "")), tostring(toint(column_ifexists("Profile_d", ""))), "")\n'
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
    query: 'let itsgcodes=GRITSGControls_CL | summarize arg_max(TimeGenerated, *) by itsgcode_s;\nGuardrailsCompliance_CL\n| where ControlName_s has ctrlprefix and ReportTime_s == ReportTime and Required_s != tostring(showNonRequired)\n| where TimeGenerated > ago (24h)\n|join kind=inner (itsgcodes) on itsgcode_s\n| project  ["Item Name"]=strcat(ItemName_s, iff(Required_s=="False"," (R)", " (M)")), ["Subscription Name"] = SubscriptionName_s, Comments=Comments_s, Status=case(ComplianceStatus_b == true, \'✔️\', ComplianceStatus_b == false, \'❌\', \'➖\'),["ITSG Control"]=itsgcode_s, Remediation=gr_geturl(replace_string(ctrlprefix," ",""),itsgcode_s), Profile=iff(isnotempty(column_ifexists("Profile_d", "")), tostring(toint(column_ifexists("Profile_d", ""))), "")\n'
    functionAlias: 'gr_data11'
    functionParameters: 'ctrlprefix:string, ReportTime:string, showNonRequired:string'
    version: 2
  }
}
resource f5 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook) {
  name: 'gr_mfa_evaluation'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'gr_functions'
    displayName: 'gr_mfa_evaluation'
    query: '// MFA Compliance Evaluation Function\n// This function evaluates MFA compliance using KQL and returns data in GuardrailsCompliance_CL format\nlet reportTime = ReportTime;\n\n// Get locale from the raw data (passed from PowerShell module)\nlet locale = toscalar(\n    GuardrailsUserRaw_CL\n    | where ReportTime_s == reportTime\n    | project Locale_s\n    | take 1\n);\n\n// Localized messages based on locale\nlet localizedMessages = case(\n    locale == "fr-CA", dynamic({\n        "allUsersHaveMFA": "Tous les comptes d\'utilisateurs natifs ont 2+ méthodes d\'authentification.",\n        "usersWithoutMFA": "{0} utilisateurs n\'ont pas d\'AMF appropriée configurée sur {1} utilisateurs totaux",\n        "noUsersFound": "Aucun utilisateur trouvé",\n        "evaluationError": "Erreur d\'évaluation: {0}",\n        "dataCollectedForAnalysis": "Données collectées pour {0} utilisateurs. L\'analyse détaillée de la conformité AMF sera effectuée dans le classeur."\n    }),\n    // Default to English\n    dynamic({\n        "allUsersHaveMFA": "Native user accounts have been identified, and all users accounts have 2+ methods of authentication enabled.",\n        "usersWithoutMFA": "{0} users do not have proper MFA configured out of {1} total users",\n        "noUsersFound": "No users found",\n        "evaluationError": "Evaluation error: {0}",\n        "dataCollectedForAnalysis": "Data collected for {0} users. Detailed MFA compliance analysis will be performed in the workbook."\n    })\n);\n\n// Get all user data for the specified report time\nlet userData = GuardrailsUserRaw_CL\n| where ReportTime_s == reportTime\n| extend \n    // Parse arrays\n    systemPreferredMethodsArray = parse_json(systemPreferredAuthenticationMethods_s),\n    methodsRegisteredArray = parse_json(methodsRegistered_s);\n\n// Define valid methods\nlet validSystemMethods = dynamic(["Fido2", "HardwareOTP"]);\nlet validMfaMethods = dynamic(["microsoftAuthenticatorPush", "mobilePhone", "softwareOneTimePasscode", "passKeyDeviceBound"]);\n\n// MFA Compliance Analysis\nlet mfaAnalysis = userData\n| extend \n    // Check system preferred authentication\n    isSystemPreferredEnabled = isSystemPreferredAuthenticationMethodEnabled_b,\n    hasValidSystemPreferred = iff(\n        isSystemPreferredEnabled == true and isnotempty(systemPreferredMethodsArray),\n        array_length(array_intersect(systemPreferredMethodsArray, validSystemMethods)) > 0,\n        false\n    ),\n    \n    // Check traditional MFA methods\n    hasMfaRegistered = isMfaRegistered_b,\n    validMfaMethodsCount = iff(\n        hasMfaRegistered == true and isnotempty(methodsRegisteredArray),\n        array_length(array_intersect(methodsRegisteredArray, validMfaMethods)),\n        0\n    ),\n    \n    // Determine compliance\n    isMfaCompliant = hasValidSystemPreferred or (hasMfaRegistered == true and validMfaMethodsCount >= 2);\n\n// Calculate summary statistics\nlet summary = mfaAnalysis\n| summarize \n    TotalUsers = count(),\n    CompliantUsers = countif(isMfaCompliant == true),\n    NonCompliantUsers = countif(isMfaCompliant == false)\n| extend \n    IsCompliant = NonCompliantUsers == 0,\n    Comments = case(\n        TotalUsers == 0, localizedMessages["noUsersFound"],\n        NonCompliantUsers == 0, localizedMessages["allUsersHaveMFA"],\n        NonCompliantUsers > 0, strcat(localizedMessages["usersWithoutMFA"], " (", NonCompliantUsers, " non-compliant, ", CompliantUsers, " compliant)")\n    );\n\n// Return in GuardrailsCompliance_CL format\nsummary\n| project \n    ControlName_s = "GUARDRAIL 1",\n    ItemName_s = "All Cloud User Accounts MFA Check",\n    ReportTime_s = reportTime,\n    Required_s = "True",\n    ComplianceStatus_b = IsCompliant,\n    Comments_s = Comments,\n    itsgcode_s = \"IA2(1)\",\n    TimeGenerated = now()\n'
    functionAlias: 'gr_mfa_evaluation'
    functionParameters: 'ReportTime:string'
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

