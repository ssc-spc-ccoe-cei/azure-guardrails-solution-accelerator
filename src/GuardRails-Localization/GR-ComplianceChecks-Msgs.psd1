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
noAlertRules = No alert rules were found for either SignInLogs or AuditLogs. Please ensure that alert rules are created and configured to monitor these logs for suspicious activities.
noActionGroupsForBGaccts = No action groups were identified for Break Glass account sign-in activities. Action groups must be configured to receive alerts for Break Glass account sign-in attempts.
noActionGroupsForAuditLogs = No action groups were found for AuditLogs. Action groups must be created to receive alerts for important auditable events.
noActionGroups = No action groups were configured for the resource group “{0}”. Ensure that action groups are set up to receive alerts for the corresponding resource group's monitored activities.
compliantAlerts = The alerts for Break Glass accounts and audit logs are compliant. Appropriate action groups have been configured and are correctly receiving alerts for each monitored activity.

globalAdminAccntsSurplus = There must be five or fewer global administrator accounts.
globalAdminAccntsMinimum = There are not enough Global Administrator Accounts. There must be at least two but no more than five Active Global Administrator Accounts.
allGAUserHaveMFA = All Azure native global administrator accounts have been identified and secured with at least two authentication methods.
gaUserMisconfiguredMFA = Some (one or more) Azure native global administrator accounts have not properly configured Multi-Factor Authentication (MFA): {0}

allCloudUserAccountsMFACheck = All Cloud User Accounts MFA Conditional Access Policy
allUserAccountsMFACheck = All Cloud User Accounts MFA Check
allUserHaveMFA = Native user accounts have been identified, and all users accounts have 2+ methods of authentication enabled.
userMisconfiguredMFA = One or more Native User Accounts have not configured MFA properly: {0}

retentionNotMet = The LAW {0} does not meet data retention requirements
readOnlyLaw = The {0} LAW identified is missing a read-only lock. Add the read-only lock to prevent accidental deletions.
nonCompliantLaw = The LAW {0} does not match the config.json file.
logsNotCollected = Not all of the required logs are being collected.
gcEventLogging = User Account GC Event Logging Check
gcEventLoggingCompliantComment = Logs are collected, stored and retained to meet this control's requirements.

dedicatedAdminAccountsCheck = Dedicated user accounts for administration
invalidUserFile = Update the {0} file and list the highly privileged role User Principal Names (UPNs) and their regular role UPNs.
dedicatedAdminAccNotExist = There are privileged users identified without a highly privileged role. Review 'Global Administrator' and 'Privileged Role Administrator' role assignments in the environment and ensure that there are dedicated user accounts for highly privileged roles. 
regAccHasHProle = There are non-privileged users identified with a highly privileged role. Review 'Global Administrator' and 'Privileged Role Administrator' role assignments in the environment and ensure that there are dedicated user accounts for highly privileged roles.
dedicatedAccExist = All Cloud Administrators are using dedicated accounts for highly privileged roles.
bgAccExistInUPNlist = Break Glass (BG) User Principal Names (UPNs) exist in the uploaded .csv file. Review the user accounts .csv file and remove the Break Glass (BG) account UPNs.
hpAccNotGA = One or more highly privileged administrators identified in the .csv file are not actively using their Global Administrator role assignments at this time. Confirm that these users have an Eligible Global Administrator Assignment.

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

riskBasedConditionalPolicy = Authentication Mechanisms: Risk Based Conditional Access Policies
nonCompliantC1= Configure the conditional access policy to force password changes based on user risk.
nonCompliantC2= Configure the conditional access policy to prevent sign-in's from unapproved named locations.
nonCompliantC1C2 = Configure the conditional access policies outlined in the remediation guidance.
compliantC1C2 = Both conditional access policies have been configured.


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
hasNonComplianceResounce = {0} out of the {1} applicable resources are non-compliant against the selected policies. Follow the Microsoft remediation recommendations.


# GuardRail #7
enableTLS12 = TLS 1.2+ is enabled whereever possible to secure data in transit
appGatewayCertValidity = Application Gateway Certificate Validity
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
dataInTransit = PROTECTION OF DATA-IN-TRANSIT

storageAccTLS12 = Storage Accounts TLS 1.2
storageAccValidTLS = All storage accounts are using TLS1.2 or higher. 
storageAccNotValidTLS= One or more storage accounts are using TLS1.1 or less. Update the storage accounts to TLS1.2 or higher.

functionAppHttpsConfig = Azure Functions: HTTPS Application Configuration

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
noWAFEnabled = The application gateway assigned does not have configured Web Application Firewalls (WAFs). Enable a WAF on the application gateway.
firewallFound = There is a {0} associated to this subscription.
wAFEnabled = There is an application gateway associated to this subscription with the appropriate configurations.
networkSecurityTools = Tools In Use For Limiting Access To Authorized Source IP Addresses

# GuardRail #10
cbsSubDoesntExist = CBS Subscription doesnt exist
cbcSensorsdontExist = The expected CBC sensors do not exist
cbssMitigation = Check subscription provided: {0} or check existence of the CBS solution in the provided subscription.
cbssCompliant = Found resources in these subscriptions: 
MOUwithCCCS = Attestation that the MOU with CCCS is acknowledged.

# GuardRail #11
securityMonitoring =SecurityMonitoring
healthMonitoring = HealthMonitoring
defenderMonitoring =DefenderMonitoring
securityLAWNotFound = The specified Log Analytics Workspace for Security monitoring has not been found.
lawRetentionSecDays = Retention not set to {0} days.
lawNoActivityLogs = WorkSpace not configured to ingest activity Logs.
lawSolutionNotFound = Required solutions not present in the Log Analytics Workspace.
lawNoAutoAcct = No linked automation account has been found.
lawNoTenantDiag = Tenant Diagnostics settings are not pointing to the provided log analytics workspace.
lawMissingLogTypes = Workspace set in tenant config but not all required log types are enabled (Audit and signin).
healthLAWNotFound = The specified Log Analytics Workspace for Health monitoring has not been found.
lawRetentionHealthDays = Retention not set to at least {0} days.
lawHealthNoSolutionFound = Required solutions not present in the Health Log Analytics Workspace.
createLAW = Please create a log analytics workspace according to guidelines.
connectAutoAcct = Please connect an automation account to the provided workspace.
setRetention730Days = Set retention of the workspace to 730 days for workspace: 
addActivityLogs = Please add the Activity Logs solution to the workspace: 
addUpdatesAndAntiMalware = Please add the both the Updates and Anti-Malware solution to the workspace: 
configTenantDiag = Please configure the Tenant diagnostics to point to the provided workspace: 
addAuditAndSignInsLogs = Please enable Audit Logs and SignInLogs in the Tenant Dianostics settings.
logsAndMonitoringCompliantForHealth= The Logs and Monitoring are compliant for Health.
logsAndMonitoringCompliantForSecurity = The Logs and Monitoring are compliant for Security.
logsAndMonitoringCompliantForDefender = The Logs and Monitoring are compliant for Defender.
createHealthLAW = Please create a workspace for Health Monitoring according to the Guardrails guidelines.
enableAgentHealthSolution = Please enable the Agent Health Assessment solution in the workspace.
lawEnvironmentCompliant = The environment is compliant.
noSecurityContactInfo = Subscription {0} is missing Contact Information.
setSecurityContact = Please set a security contact for Defender for Cloud in the subscription. {0}
notAllDfCStandard = Not all pricing plan options are set to Standard for subscription {0}
setDfCToStandard = Please set Defender for Cloud plans to Standard. ({0})
passwordNotificationsConfigured = Notifications Enabled
severityNotificationToEmailConfigured = Severity Notifications to a Primary Email

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

# GR-Common
procedureFileFound = Compliant. Required file has been uploaded for review by Cloud Security Compliance assessors. '{0}' found.
procedureFileNotFound = Non-compliant. Could not find '{0}'. Create and upload the appropriate file in Container '{1}' in Storage Account '{2}' to become compliant.

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
