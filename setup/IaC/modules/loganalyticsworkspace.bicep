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
let userData = GuardrailsUserRaw_CL
| where ReportTime_s == reportTime;
let validSystemMethods = dynamic(["Fido2", "HardwareOTP"]);
let validMfaMethods = dynamic(["microsoftAuthenticatorPush", "mobilePhone", "softwareOneTimePasscode", "passKeyDeviceBound"]);
let mfaAnalysis = userData
| extend 
    systemPreferredMethodsArray = parse_json(systemPreferredAuthenticationMethods_s),
    methodsRegisteredArray = parse_json(methodsRegistered_s),
    isSystemPreferredEnabled = isSystemPreferredAuthenticationMethodEnabled_b
| extend
    hasValidSystemPreferred = iff(
        isSystemPreferredEnabled == true and isnotempty(systemPreferredMethodsArray),
        array_length(set_intersect(systemPreferredMethodsArray, validSystemMethods)) > 0,
        false
    ),
    hasMfaRegistered = isMfaRegistered_b
| extend
    validMfaMethodsCount = iff(
        hasMfaRegistered == true and isnotempty(methodsRegisteredArray),
        array_length(set_intersect(methodsRegisteredArray, validMfaMethods)),
        0
    )
| extend
    isMfaCompliant = hasValidSystemPreferred or (hasMfaRegistered == true and validMfaMethodsCount >= 2);
let summary = mfaAnalysis
| summarize 
    TotalUsers = count(),
    CompliantUsers = countif(isMfaCompliant == true),
    NonCompliantUsers = countif(isMfaCompliant == false), 
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
summary
| project 
    ControlName_s = "GUARDRAIL 1",
    ItemName_s = iff(locale == "fr-CA", "Vérification de l'AMF de tous les comptes d'utilisateurs infonuagiques", "All Cloud User Accounts MFA Check"),
    ReportTime_s = reportTime,
    Required_s = "True",
    ComplianceStatus_b = IsCompliant,
    Comments_s = Comments,
    itsgcode_s = "IA2(1)",
    TimeGenerated = now()
'''
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

