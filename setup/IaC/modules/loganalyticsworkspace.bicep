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
    query: 'let itsgcodes=GRITSGControls_CL | summarize arg_max(TimeGenerated, *) by itsgcode_s;\nGuardrailsCompliance_CL\n| where column_ifexists("ControlName_s", "") has ctrlprefix and column_ifexists("ReportTime_s", "") == ReportTime and column_ifexists("Required_s", "") != tostring(showNonRequired)\n| where TimeGenerated > ago (24h)\n|join kind=leftouter (itsgcodes) on itsgcode_s\n| project ["Item Name"]=strcat(column_ifexists("ItemName_s", ""), iff(column_ifexists("Required_s", "")=="False"," (R)", " (M)")),\n    Comments=column_ifexists("Comments_s", ""),\n    Status=case(column_ifexists("ComplianceStatus_b", bool(null)) == true, \'🟢\', column_ifexists("ComplianceStatus_b", bool(null)) == false, \'🔴\', \'➖\'),\n    ["ITSG Control"]=column_ifexists("itsgcode_s", ""),\n    Remediation=gr_geturl(replace_string(ctrlprefix," ",""),column_ifexists("itsgcode_s", "")),\n    Profile=iff(isnotempty(column_ifexists("Profile_d", "")), tostring(toint(column_ifexists("Profile_d", ""))), "")\n'
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
    query: 'let itsgcodes=GRITSGControls_CL | summarize arg_max(TimeGenerated, *) by itsgcode_s;\nGuardrailsCompliance_CL\n| where column_ifexists("ControlName_s", "") has ctrlprefix and column_ifexists("ReportTime_s", "") == ReportTime and column_ifexists("Required_s", "") != tostring(showNonRequired)\n| where TimeGenerated > ago (24h)\n|join kind=leftouter (itsgcodes) on itsgcode_s\n| project ["Item Name"]=strcat(column_ifexists("ItemName_s", ""), iff(column_ifexists("Required_s", "")=="False"," (R)", " (M)")),\n    ["Subscription Name"]=column_ifexists("DisplayName_s", ""),\n    Comments=column_ifexists("Comments_s", ""),\n    Status=case(column_ifexists("ComplianceStatus_b", bool(null)) == true, \'🟢\', column_ifexists("ComplianceStatus_b", bool(null)) == false, \'🔴\', \'➖\'),\n    ["ITSG Control"]=column_ifexists("itsgcode_s", ""),\n    Remediation=gr_geturl(replace_string(ctrlprefix," ",""),column_ifexists("itsgcode_s", "")),\n    Profile=iff(isnotempty(column_ifexists("Profile_d", "")), tostring(toint(column_ifexists("Profile_d", ""))), "")\n'
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
    query: 'let itsgcodes=GRITSGControls_CL | summarize arg_max(TimeGenerated, *) by itsgcode_s;\nGuardrailsCompliance_CL\n| where column_ifexists("ControlName_s", "") has ctrlprefix and column_ifexists("ReportTime_s", "") == ReportTime and column_ifexists("Required_s", "") != tostring(showNonRequired)\n| where TimeGenerated > ago (24h)\n|join kind=leftouter (itsgcodes) on itsgcode_s\n| project  ["Item Name"]=strcat(column_ifexists("ItemName_s", ""), iff(column_ifexists("Required_s", "")=="False"," (R)", " (M)")), ["Subscription Name"] = column_ifexists("SubscriptionName_s", ""), Comments=column_ifexists("Comments_s", ""), Status=case(column_ifexists("ComplianceStatus_b", bool(null)) == true, \'🟢\', column_ifexists("ComplianceStatus_b", bool(null)) == false, \'🔴\', \'➖\'),["ITSG Control"]=column_ifexists("itsgcode_s", ""), Remediation=gr_geturl(replace_string(ctrlprefix," ",""),column_ifexists("itsgcode_s", "")), Profile=iff(isnotempty(column_ifexists("Profile_d", "")), tostring(toint(column_ifexists("Profile_d", ""))), "")\n'
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

resource f6 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = if ((deployLAW && newDeployment) || updateWorkbook) {
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
