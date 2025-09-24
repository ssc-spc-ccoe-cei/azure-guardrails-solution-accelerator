ConvertFrom-StringData @'

# English strings

CtrName1 = GUARDRAIL 1: PROTECT USER ACCOUNTS AND IDENTITIES
CtrName2 = GUARDRAIL 2: MANAGE ACCESS
CtrName3 = GUARDRAIL 3: SECURE ENDPOINTS
CtrName4 = GUARDRAIL 4: ENTERPRISE MONITORING ACCOUNTS
CtrName5 = GUARDRAIL 5: DATA LOCATION
CtrName6 = GUARDRAIL 6: PROTECTION OF DATA-AT-REST
CtrName7 = GUARDRAIL 7: PROTECTION OF DATA-IN-TRANSIT
CtrName8 = GUARDRAIL 8: SEGMENT AND SEPARATE
CtrName9 = GUARDRAIL 9: NETWORK SECURITY SERVICES
CtrName10 = GUARDRAIL 10: CYBER DEFENSE SERVICES
CtrName11 = GUARDRAIL 11: LOGGING AND MONITORING
CtrName12 = GUARDRAIL 12: CONFIGURATION OF CLOUD MARKETPLACES
CtrName13 = GUARDRAIL 13: PLAN FOR CONTINUITY

# Global
isCompliant = Compliant.
isNotCompliant = Non-compliant.

# Guardrail #1
MSEntIDLicense = Microsoft Entra ID License Type
mfaEnabledFor =  MFA Authentication should not be enabled for BreakGlass account: {0} 
mfaDisabledFor =  MFA Authentication is not enabled for {0}
gaAccntsMFACheck = MFA and Count for Global Administrator Accounts

alertsMonitor = Alerts to Flag Misuse and Suspicious Activities
signInlogsNotCollected = The SignInLogs are currently not enabled. SignInLogs must be enabled to monitor and log user sign-in activities in the environment.
auditlogsNotCollected = The AuditLogs are currently not enabled. AuditLogs must be enabled to capture and log all significant audit events within the environment.
noAlertRules = No alert rules were found for SignInLogs or AuditLogs for the resource group "{0}". Please ensure that alert rules are created and configured to monitor these logs for suspicious activities.
noActionGroupsForBGaccts = No action groups were identified for Break Glass account sign-in activities. Action groups must be configured to receive alerts for Break Glass account sign-in attempts.
noActionGroupsForAuditLogs = No action groups were found for Conditional Access Policy changes and updates. Action groups must be created to receive alerts for Conditional Access Policy changes and updates.
noActionGroups = No action groups were configured for the resource group "{0}". Ensure that action groups are set up to receive alerts for the corresponding resource group's monitored activities.
compliantAlerts = The alerts for Break Glass accounts and audit logs are compliant. Appropriate action groups have been configured and are correctly receiving alerts for each monitored activity.
noAlertRuleforBGaccts = Create an alert for the Breakglass accounts using the SignInLogs. Missing one of the required alerts.
NoAlertRuleforCaps = Create an alert for the Conditional Access Policy changes and updates using the AuditLogs. Missing one of the required alerts.

globalAdminAccntsSurplus = There must be five or fewer global administrator accounts.
globalAdminAccntsMinimum = There are not enough Global Administrator Accounts found with an active status. The solution is assuming that you are using eligible Global Administrator Accounts.
allGAUserHaveMFA = All Azure native global administrator accounts have been identified and secured with at least two authentication methods.
gaUserMisconfiguredMFA = Some (one or more) Azure native global administrator accounts have not properly configured Multi-Factor Authentication (MFA): {0}

allCloudUserAccountsMFACheck = All Cloud User Accounts MFA Conditional Access Policy
allUserAccountsMFACheck = All Cloud User Accounts MFA Check
allUserHaveMFA = Native user accounts have been identified, and all users accounts have 2+ methods of authentication enabled.

userMisconfiguredMFA = One or more Native User Accounts have not configured MFA properly

retentionNotMet = The LAW {0} does not meet data retention requirements
readOnlyLaw = The {0} LAW identified is missing a read-only lock. Add the read-only lock to prevent accidental deletions.
nonCompliantLaw = The LAW {0} does not match the config.json file.
logsNotCollected = Not all of the required logs are being collected.
gcEventLogging = User Account GC Event Logging Check
gcEventLoggingCompliantComment = Logs are collected, stored and retained to meet this control's requirements.
lockLevelApproved = The Log Analytics Workspace {0} has an approved lock level of {1}. 
lockLevelNotApproved = The Log Analytics Workspace {0} has a lock level of {1} which is not approved. Approved lock levels are 'ReadOnly' or 'DeleteOnly'.
tagFound = The Log Analytics Workspace {0} has a resource tag 'sentinel' with a value of 'true' which indicates that it is being used for Sentinel. 'DeleteOnly' lock is recommended. 
sentinelTablesFound = The Log Analytics Workspace {0} has Sentinel tables configured. The Log Analytics Workspace is missing the Sentinel resource tag expected, please update or add the tag to: sentinel=true.
noLockNoTagNoTables = The Log Analytics Workspace {0} does not have an approved  'ReadOnly' or 'DeleteOnly' lock in place. Refer to the Remediation Guide for more information.

dedicatedAdminAccountsCheck = Dedicated user accounts for administration
invalidUserFile = Update the {0} file and list the highly privileged role User Principal Names (UPNs) and their regular role UPNs.
invalidFileHeader = Update the {0} file headers and list the highly privileged role User Principal Names (UPNs) and their regular role UPNs.
dedicatedAdminAccNotExist = There are privileged users identified without a highly privileged role. Review 'Global Administrator' and 'Privileged Role Administrator' role assignments in the environment and ensure that there are dedicated user accounts for highly privileged roles. 
regAccHasHProle = There are non-privileged users identified with a highly privileged role. Review 'Global Administrator' and 'Privileged Role Administrator' role assignments in the environment and ensure that there are dedicated user accounts for highly privileged roles.
dedicatedAccExist = All Cloud Administrators are using dedicated accounts for highly privileged roles.
bgAccExistInUPNlist = Break Glass (BG) User Principal Names (UPNs) exist in the uploaded .csv file. Review the user accounts .csv file and remove the Break Glass (BG) account UPNs.
hpAccNotGA = One or more highly privileged administrators identified in the .csv file are not actively using their Global Administrator role assignments at this time. Confirm that these users have an Eligible Global Administrator Assignment.
dupHPAccount = Review the highly privileged account User Principal Names (UPNs) provided for any duplicates. Remove any UPNs that are repeated.
dupRegAccount = Review the regular account User Principal Names (UPNs) provided for any duplicates. Remove any UPNs that are repeated.
missingHPaccUPN = Missing data in the 'HP_admin_account_UPN' column. Please ensure that this column is filled out before proceeding.
missingRegAccUPN = Missing data in the 'regular_account_UPN' column. Please ensure that this column is filled out before proceeding.

# GuardRail #2
MSEntIDLicenseTypeFound = Found correct license type
MSEntIDLicenseTypeNotFound = Required Microsoft Entra ID license type not found
accountNotDeleted = This user account has been deleted but has not yet been DELETED PERMANENTLY from Microsoft Entra ID
MSEntIDDeletedUser =  Microsoft Entra ID Deleted User
MSEntIDDisabledUsers = Microsoft Entra ID Disabled Users
apiError = API Error
apiErrorMitigation = Please verify existance of the user (more likely) or application permissions.
compliantComment = Didnt find any unsynced deprecated users

mitigationCommands = Verify is the users reported are deprecated.
noncompliantComment = Total Number of non-compliant users {0}. 
noncompliantUsers = The following Users are disabled and not synchronized with Microsoft Entra ID: -

removeDeletedAccount = Permanently remove deleted accounts
removeDeprecatedAccount = Remove deprecated accounts

privilegedAccountManagementPlanLifecycle = Privileged Account Management Plan (Lifecycle of Account Management)
privilegedAccountManagementPlanLPRoleAssignment = Privileged Account Management Plan (Least Privilege Role Assignment)

onlineAttackCounterMeasures = Measures to Counter Online Attacks Check: Lockouts and Banned Password Lists
onlineAttackNonCompliantC1 = The account lockout threshold does not meet the GC Password Guidance.
onlineAttackNonCompliantC2 = The banned password list does not meet the GC Password Guidance.
onlineAttackIsCompliant = The account lockout threshold and banned password list meets the GC Password Guidance. 
onlineAttackNonCompliantC1C2 = Neither the accounts lockouts or the banned password list meets the GC Password Guidance. Review and remediate.

noGuestAccounts = There are currently no GUEST User Accounts in your tenant environment.
guestAccountsNoPermission = There are GUEST User Accounts in the tenant environment and they do not have any permissions in the tenant's Azure subscription(s).
guestAssigned = This GUEST User Account has a role assignment in the tenant's Azure subscriptions.
guestNotAssigned = This GUEST User Account does not have any role assignment in the tenant's Azure subscription(s).
existingGuestAccounts = Existing Guest User Accounts
existingGuestAccountsComment = Review and validate the provided list of GUEST User Accounts. Remove GUEST User Accounts according to your departmental procedures and policies, as needed.

guestAccountsNoPrivilegedPermission = There are GUEST User Accounts in the tenant environment and they do not have any permissions that are considered "privileged" at the Subscription level.
existingPrivilegedGuestAccounts = Privileged Guest User Accounts
existingPrivilegedGuestAccountsComment = Review and validate the provided list of Privileged GUEST User Accounts. Remove Privileged GUEST User Accounts according to your departmental procedures and policies, as needed.
guestHasPrivilegedRole = This Guest user account has one or more privileged roles


accManagementUserGroupsCheck = Account Management: User Groups
userCountGroupNoMatch = Not all users have been assigned to a privileged or non-privileged user group.
noCAPforAnyGroups = None of the conditional access policies refer to one of your user groups (privileged or non-privileged).
userCountOne = There is only one user in the environment. User groups are not required. 
userGroupsMany = The number of user groups is insufficient for the current number of users. At least 2 user groups are needed. 
reqPolicyUserGroupExists = All users have been assigned to a user group, and at least one conditional access policy references a user group for access control. 
userStats = User stats - Total Users: {0}; Group Users (Total - Unique): {1}; Members in Tenants: {2}; Guests in Tenants: {3}
userNotInGroup = User is not associated with any user group.
userInGroup = No users without groups

riskBasedConditionalPolicy = Authentication Mechanisms: Risk Based Conditional Access Policies
nonCompliantC1= Configure the conditional access policy to force password changes based on user risk.
nonCompliantC2= Configure the conditional access policy to prevent sign-in's from unapproved named locations.
nonCompliantC1C2 = Configure the conditional access policies outlined in the remediation guidance.
compliantC1C2 = Both conditional access policies have been configured.

automatedRoleForUsers = Automated Role Reviews: Role Assignments for Users and Global Administrators
noAutomatedAccessReviewForUsers = There are no automated access reviews configured for Microsoft Entra ID directory roles. Set up an annual access review for a highly privileged role.
noInProgressAccessReview = The environment has at least one scheduled role access review for Global Administrators or another Azure built-in role. However, the access review has been identified as either 'completed' or 'not started'. Create a new Global Administrator/Azure built-in role access review to reoccur and be 'in progress'.
noScheduledUserAccessReview = There are no recurring or current automated access reviews for Microsoft Entra ID directory roles. Ensure that reviews are set to recur.
compliantRecurrenceReviews = Existing access reviews meet the requirements for the control.
nonCompliantRecurrenceReviews = One or more existing Access Reviews do not meet the recurrence requirements for the control. Ensure the automated review is 'in progress' and scheduled to reoccur.

automatedRoleForGuests = Automated Guest User Reviews: Role Assignments and Access Requirements
noAutomatedAccessReviewForGuests = There are no automated access reviews configured for Guest User Accounts. Set up an annual access review for Guest Users.
noInProgressGuestAccessReview = The environment has at least one scheduled access review for guest users. However, the access review has been identified as either 'completed' or 'not started'. Create a new guest access review to reoccur and be 'in progress'.
noScheduledGuestAccessReview = The environment has no scheduled guest user access reviews. Configure a guest user access review for all user groups. 
compliantRecurrenceGuestReviews = Existing guest access reviews meet the requirements for the control.


# GuardRail #3
consoleAccessConditionalPolicy = Conditional Access Policy for Cloud Console Access.
adminAccessConditionalPolicy = Administrator Access Restrictions Applied - device management/trusted locations
noCompliantPoliciesfound=No compliant policies found. Policies need to have a single location and that location must be Canada Only.
allPoliciesAreCompliant=All policies are compliant.
noLocationsCompliant=No locations have only Canada in them.

mfaRequiredForAllUsers = Multi-Factor authentication required for all users by Conditional Access Policy
noMFAPolicyForAllUsers = No conditional access policy requiring MFA for all users and applications was found. A Conditional Access Policy meeting the following requirements must be configured: 1. state =  'enabled'; 2. includedUsers = 'All'; 3. includedApplications = 'All'; 4. grantControls.builtInControls contains 'mfa'; 5. clientAppTypes contains 'all'; 6. userRiskLevels = @(); 7. signInRiskLevels = @(); 8. platforms = null; 9. locations = null; 10. devices = null; 11. clientApplications = null
noDeviceFilterPolicies = Missing a required conditional access policy. At least one policy needs to have device filters enabled with target resources, administrator roles included and enabled.
noLocationFilterPolicies = Missing a required conditional access policy. At least one policy needs to check for named/trusted locations with administrator roles included and enabled.
hasRequiredPolicies = Required conditional access policies for administrator access exist. 
noCompliantPoliciesAdmin = No compliant policies found for device filters and named/trusted locations. Please ensure that there is at least one policy of each. One for device filters with a target resource and another for named/trusted locations.

# GuardRail #4
monitorAccount = Monitor Account Creation
checkUserExistsError = API call returned Error {0}. Please Check if the user exists.
checkUserExists = Please Check if the user exists.
ServicePrincipalNameHasNoReaderRole = SPN doesnt have Reader Role on the ROOT Management Group.
ServicePrincipalNameHasReaderRole = SPN has Reader Role on the ROOT Management Group.
ServicePrincipalNameHasNoMarketPlaceAdminRole = SPN doesnt have Marketplace Admin Role on the Marketplace.
ServicePrincipalNameHasMarketPlaceAdminRole = SPN has Marketplace Admin Role on the Marketplace.
NoSPN = SPN doesnt exist.
SPNCredentialsCompliance = SPN Credentials Compliance

SPNSingleValidCredential = SPN has a single valid credential. {0}
SPNMultipleValidCredentials = SPN has multiple valid credentials. {0}
SPNNoValidCredentials = SPN has no valid credentials. {0}
FinOpsToolStatus = FinOps Tool Status
SPNNotExist = Service Principal 'CloudabilityUtilizationDataCollector' does not exist
SPNIncorrectPermissions = Service Principal 'CloudabilityUtilizationDataCollector' does not have the required Reader role
SPNIncorrectRoles = Service Principal does not have the required Cloud Application Administrator and Reports Reader roles.
FinOpsToolCompliant = The FinOps tool is compliant with all requirements.
FinOpsToolNonCompliant = The FinOps tool is not compliant. Reasons: {0}

# GuardRail #5
pbmmCompliance = PBMMPolicy Compliance
policyNotAssigned = The Policy or Initiative is not assigned to the {0}
excludedFromScope = {0} is excluded from the scope of the assignment

policyNotAssignedRootMG = The Policy or Initiative is not assigned on the Root Management Groups
rootMGExcluded =This Root Management Groups is excluded from the scope of the assignment
subscription = subscription
managementGroup = Management Groups
notAllowedLocation =  Location is outside of the allowed locations. 
allowedLocationPolicy = AllowedLocationPolicy
dataAtRest = PROTECTION OF DATA-AT-REST


# GuardRail #6
pbmmApplied = PBMM initiative has been applied.
pbmmNotApplied = PBMM initiative has not been applied. Apply the PBMM initiative.
reqPolicyApplied = All required policies are applied.
reqPolicyNotApplied = The PBMM initiative is missing one or a few of the selected policies for evaluation. Consult the remediation Playbook for more information.
grExemptionFound = Remove the exemption found for {0}. 
grExemptionNotFound = Required Policy Definitions are not exempt.
noResource = No applicable resources for the selected PBMM Initiative's policies to evaluate.
allCompliantResources = All resources are compliant.
allNonCompliantResources = All resources are non-compliant.
hasNonComplianceResource = {0} out of the {1} applicable resources are non-compliant against the selected policies. Follow the Microsoft remediation recommendations.


# GuardRail #7
appGatewayCertValidity = Application Gateway Certificate Validity
noSslListenersFound = No SSL listener found/configured for Application Gateway: {0}. 
expiredCertificateFound = Expired certificate found for listener '{0}' in Application Gateway '{1}'.
unapprovedCAFound = Unapproved Certificate Authority (CA) found for listener '{0}' in Application Gateway '{1}'. Issuer: {2}.
unableToProcessCertData = Unable to process certificate data for listener '{0}' in Application Gateway '{1}'. Error: {2}.
unableToRetrieveCertData = Unable to retrieve certificate data for listener '{0}' in Application Gateway '{1}'.
noHttpsBackendSettingsFound = No HTTPS backend settings found/configured for Application Gateway: {0}.
manualTrustedRootCertsFound = Manual trusted root certificates found for Application Gateway '{0}', backend setting '{1}'.
allBackendSettingsUseWellKnownCA = All backend settings for Application Gateway '{0}' use well‑known Certificate Authority (CA) certificates.
noAppGatewayFound = No Application Gateways found in any subscription.
allCertificatesValid = All certificates are valid and from approved Certificate Authorities (CAs).
approvedCAFileFound = Approved Certificate Authority (CA) list file '{0}' found and processed
approvedCAFileNotFound = Approved Certificate Authority (CA) file '{0}' not found in container '{1}' of storage account '{2}'. Unable to verify certificate authorities
appServiceHttpsConfig = Azure App Service: HTTPS Application Configuration
keyVaultCertValidationFailed = Certificate stored in Key Vault for listener '{0}' in Application Gateway '{1}' could not be validated. The CAC solution requires 'Key Vault Secrets User' permissions on the customer Key Vault to validate certificates. If the vault is in Access Policy mode, grant the Automation Account managed identity the 'Get' permission on Secrets for this Key Vault. Contact your administrator to grant the CAC Automation Account managed identity access to this Key Vault if desired.
keyVaultCertRetrievalFailed = Unable to retrieve certificate from Key Vault for listener '{0}' in Application Gateway '{1}'. Certificate may be stored in Key Vault and requires proper permissions to access.

dataInTransit = Secure Connections for Redis Cache and Storage Accounts

storageAccTLS12 = Storage Accounts TLS 1.2
storageAccValidTLS = All storage accounts are using TLS1.2 or higher. 
storageAccNotValidTLS= One or more storage accounts are using TLS1.1 or less. Update the storage accounts to TLS1.2 or higher.
storageAccNotValidList = The following storage accounts are not valid: {0}

functionAppHttpsConfig = Azure Functions: HTTPS Application Configuration

appServiceTLSConfig = Azure App Service TLS Configuration
functionAppTLSConfig = Azure Functions App TLS Configuration
sqlDbTLSConfig = Azure SQL Database TLS Configuration
appGatewayWAFConfig = Application Gateway WAF TLS Configuration
policyNotConfigured = Required policy is not assigned at tenant level. Please assign the policy to ensure compliance.
policyCompliant = All resources are compliant with the required policy.
policyNotCompliant = Resource is not compliant with the required policy. Please review and remediate.
policyHasExemptions = Policy has exemptions configured. All resources must be evaluated by this policy.
policyNoApplicableResources = No applicable resources found. Policy is assigned at tenant level.


# GuardRail #8
noNSG=No NSG is present.
subnetCompliant = Subnet is compliant.
nsgConfigDenyAll = NSG is present but not properly configured (Missing Deny all last Rule).
nsgCustomRule = NSG is present but not properly configured (Missing Custom Rules).
networkSegmentation = Segmentation
networkSeparation = Separation
routeNVA = Route present but not directed to a Virtual Appliance.
routeNVAMitigation = Update the route to point to a virtual appliance
noUDR = No User defined Route configured.
noUDRMitigation = Please apply a custom route to this subnet, pointing to a virtual appliance.
subnetExcludedByTag = Subnet '{0}' is excluded from compliance because VNET '{1}' has tag '{2}' with a value of 'true'
subnetExcludedByReservedName = Subnet '{0}' is excluded from compliance because its name is in the reserved subnet list '{1}'
subnetExcludedByVNET = Subnet '{0}' is not being checked for compliance because the VNET '{1}' has tag '{2}' with a value of 'true'
networkDiagram = Network architecture diagram
highLevelDesign = High level design documentation
noSubnets = No subnets found in the subscription.
cloudInfrastructureDeployGuide = Cloud Infrastructure Deployment Guide or Applicable Landing Zone Details

# GuardRail #9
ddosEnabled=DDos Protection Enabled. 
ddosNotEnabled=DDos Protection not enabled.

networkWatcherEnabled=Network Watcher exists for region '{0}'
networkWatcherNotEnabled=Network Watcher not enabled for region '{0}'
noVNets = No VNet found in the subscription.
vnetExcludedByParameter = VNet '{0}' is excluded from compliance because it is in the excluded VNet list '{1}'
vnetExcludedByTag = VNet '{0}' is excluded from compliance because it has tag '{1}' with a value of 'true'
vnetDDosConfig = VNet DDos configuration
networkWatcherConfig = VNet Network Watcher configuration
networkWatcherConfigNoRegions = Either due to no VNETs or all VNETs being excluded, there are no regions to check for Network Watcher configuration
noFirewallOrGateway = This subscription does not have a firewall or an application gateway in use.
noFirewallOrGatewayCompliant = This subscription is compliant due to the presence of a Firewall, or a Application Gateway (with a Web Application Firewall) in another subscription. Ensure that this subscription is routing source IP Addresses appropriately.
wAFNotEnabled = The application gateway assigned does not have configured Web Application Firewalls (WAFs). Enable a WAF on the application gateway.
firewallFound = There is a {0} associated to this subscription.
wAFEnabled = There is an application gateway associated to this subscription with the appropriate configurations.
networkSecurityTools = Tools In Use For Limiting Access To Authorized Source IP Addresses
networkInterfaceIPs = Policy for Limiting Public IPs
policyNoApplicableResourcesSub = Policy is assigned at the subscription level. No applicable resources found
policyNotConfiguredSub = Required policy is not assigned to this subscription: {0}. Please assign the policy to ensure compliance.

# GuardRail #10
cbsSubDoesntExist = CBS Subscription doesnt exist
cbcSensorsdontExist = The expected CBC sensors do not exist
cbssMitigation = Check subscription provided: {0} or check existence of the CBS solution in the provided subscription.
cbssCompliant = Found resources in these subscriptions: 

# GuardRail #11
serviceHealthAlerts = Service Health Alerts and Events Check

createLAW = Please create a log analytics workspace according to guidelines.
connectAutoAcct = Please connect an automation account to the provided workspace.
setRetention730Days = Set retention of the workspace to 730 days for workspace: 
addActivityLogs = Please add the Activity Logs solution to the workspace: 
addUpdatesAndAntiMalware = Please add the both the Updates and Anti-Malware solution to the workspace: 
configTenantDiag = Please configure the Tenant diagnostics to point to the provided workspace: 
addAuditAndSignInsLogs = Please enable Audit Logs and SignInLogs in the Tenant Dianostics settings.

logsAndMonitoringCompliantForDefender = The Logs and Monitoring are compliant for Defender.
createHealthLAW = Please create a workspace for Health Monitoring according to the Guardrails guidelines.
enableAgentHealthSolution = Please enable the Agent Health Assessment solution in the workspace.
lawEnvironmentCompliant = The environment is compliant.

setSecurityContact = Please set a security contact for Defender for Cloud in the subscription. {0}
setDfCToStandard = Please set Defender for Cloud plans to Standard. ({0})

noServiceHealthActionGroups = Missing an action group for Service Health Alerts associated with the subscription: {0}
NotAllSubsHaveAlerts = Service Health Alerts are not enabled for this subscription. Ensure that service health alerts are configured on this subscription and that the action group associated with the alert has at least two different contacts.
EventTypeMissingForAlert = Missing a required event type (Service Issue, Health Advisory, or Security Advisory) for the subscription: {0}
noServiceHealthAlerts = Could not retrieve any configured alerts for the subscription: "{0}". Ensure all subscriptions have Service Health Alerts configured and the action group associated to the alert  has at least two different contacts.
nonCompliantActionGroups = This subscription has Service Health Alerts, but not all action groups are correctly configured. A minimum of two email addresses or subscription owners are required for the action group.
compliantServiceHealthAlerts = This subscription has Service Health Alerts, and the action group has at least two different contacts.

msDefenderChecks = Microsoft Defender for Cloud Alerts and Events Check
NotAllSubsHaveDefenderPlans = The subscription {0} lack a defender plan. Enable Defender monitoring for this subscription.
errorRetrievingNotifications = Defender alert notifications for this subscription is not configured. Ensure they match the Remediation Guidance requirements.
EmailsOrOwnerNotConfigured = Defender alert notifications for the subscription {0} do not include at least two email addresses or subscription owners. Configure this to ensure alerts are sent correctly.
AlertNotificationNotConfigured = Defender alert notifications are incorrect. Set the severity to Medium or Low and review the Remediation Guidance.
AttackPathNotificationNotConfigured = Defender alerts must include attack path notifications. Ensure that the severity is set to Medium or Low for each subscription's alerts, following the guidelines provided in the Remediation Guidance.
DefenderCompliant = MS Defender for Cloud is enabled for this subscription, and email notifications are properly configured.

monitoringChecklist = Monitoring Checklist: Use Cases

# GuardRail #12
mktPlaceCreation = MarketPlaceCreation
mktPlaceCreatedEnabled = The Private Marketplace has been created and enabled.
mktPlaceCreatedNotEnabled = The Private Marketplace has been created but not enabled.
mktPlaceNotCreated = The Private Marketplace has not been created.
enableMktPlace = Enable Azure Private MarketPlace as per: https://docs.microsoft.com/en-us/marketplace/create-manage-private-azure-marketplace-new

# Guardrail #13
bgMSEntID = Break Glass Microsoft Entra ID P2
bgProcedure = Break Glass Account Procedure
bgCreation = Break Glass account Creation

bgAccountOwnerContact = Break Glass Account Owners Contact information
bgAccountsCompliance = First Break Glass Account Compliance status = {0}, Second Break Glass Account Compliance status = {1}
bgAccountsCompliance2 = Both accounts are identical, please check the config.json file
bgAuthenticationMeth =  Authentication Methods 
firstBgAccount = First Break Glass Account
secondBgAccount = Second Break Glass Account
bgNoValidLicenseAssigned = No Microsoft Entra ID P2 license assigned to
bgValidLicenseAssigned =  has a valid Microsoft Entra ID P2 assigned
bgAccountHasManager = BG Account {0} has a Manager
bgAccountNoManager = BG Account {0} doesn't have a Manager 
bgBothHaveManager = Both BreakGlass accounts have manager

bgValidSignature = Valid Signatures and Approvals for Break Glass Account Procedure
bgAccountTesting = Break Glass Account Testing Cadence
bgAccountNotExist = One or both of the Break Glass Account User Principal Names (UPNs) provided do not exist in the environment. Review the provided Break Glass Account UPNs for accuracy.
bgAccountLoginNotValid = Last login for the provided Break Glass Accounts is greater than a year. Ensure regular testing of the Break Glass Account procedure and login process.
bgAccountLoginValid = Last login for the provided Break Glass Accounts is within a year. Ensure regular testing of the Break Glass Account procedure and login process.

# GR-Common
procedureFileFound = Compliant. Required file has been uploaded for review by Cloud Security Compliance assessors. '{0}' found.
procedureFileNotFound = Non-compliant. Could not find '{0}'. Create and upload the appropriate file in Container '{1}' in Storage Account '{2}' to become compliant.
procedureFileNotFoundWithCorrectExtension = Non-compliant. Required fileName '{0}' found. However, the extension is not supported. Create and upload the appropriate file in Container '{1}' in Storage Account '{2}' to become compliant.

procedureFileDataInvalid = The global administrator file(s) contain(s) invalid User Principal Names (UPNs). Ensure that UPNs start with a hyphen, and type each of them on a new line.
globalAdminFileFound = File {0} found in Container.
globalAdminFileNotFound = Could not find document for {0}, please create and upload a file with the name '{1}' in Container '{2}' on Storage Account '{3}' to confirm you have completed the Item in the control.
globalAdminFileEmpty = Empty file {0} found in Container.
globalAdminNotExist = Global Administrator accounts not found or declared in file {0}.
globalAdminMFAPassAndMin2Accnts = Two or more global administrator accounts have been identified, and multi-factor authentication (MFA) is enabled for all of them.
globalAdminMinAccnts = There must be at least two global administrator accounts.

globalAdminAccntsMFADisabled1 = The following account: {0} does not have multi-factor authentication (MFA) enabled
globalAdminAccntsMFADisabled2 = The following accounts: {0} do not have multi-factor authentication (MFA) enabled 
globalAdminAccntsMFADisabled3 = None of the global administrator accounts have multi-factor authentication (MFA) enabled 

'@
