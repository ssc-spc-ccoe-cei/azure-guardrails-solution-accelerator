ConvertFrom-StringData @'

# English strings

CtrName1 = GUARDRAIL 1: PROTECT ROOT / GLOBAL ADMINS ACCOUNT
CtrName2 = GUARDRAIL 2: MANAGEMENT OF ADMINISTRATIVE PRIVILEGES
CtrName3 = GUARDRAIL 3: CLOUD CONSOLE ACCESS
CtrName4 = GUARDRAIL 4: ENTERPRISE MONITORING ACCOUNTS
CtrName5 = GUARDRAIL 5: DATA LOCATION
CtrName6 = GUARDRAIL 6: PROTECTION OF DATA-AT-REST
CtrName7 = GUARDRAIL 7: PROTECTION OF DATA-IN-TRANSIT
CtrName8 = GUARDRAIL 8: NETWORK SEGMENTATION AND SEPARATION
CtrName9 = GUARDRAIL 9: NETWORK SECURITY SERVICES
CtrName10 = GUARDRAIL 10: CYBER DEFENSE SERVICES
CtrName11 = GUARDRAIL 11: LOGGING AND MONITORING
CtrName12 = GUARDRAIL 12: CONFIGURATION OF CLOUD MARKETPLACES

# Guardrail 1
adLicense = AD License Type
mfaEnforcement = MFA Enforcement Excl. Break Glass Accounts
mfaEnabledFor =  MFA Authentication should not be enabled for BreakGlass account: {0} 
mfaDisabledFor =  MFA Authentication is not enabled for {0} 
m365Assignment = Microsoft 365 E5 Assignment
bgProcedure = Break Glass Account Non-technical
bgCreation = Break Glass account Creation
bgAccountResponsibility = Responsibility of break glass accounts must be with someone not-technical, director level or above
bgAccountOwnerContact = Break Glass Account Owners Contact information
bgAccountsCompliance = First Break Glass Account Compliance status = {0}, Second Break Glass Account Compliance status = {1}
bgAccountsCompliance2 = Both accounts are identical, please check the config.json file
bgAuthenticationMeth =  Authentication Methods 
firstBgAccount = First Break Glass Account
secondBgAccount = Second Break Glass Account
bgNoValidLicenseAssigned = No AAD P2 license assigned to
bgValidLicenseAssigned =  has a valid AAD P2 assigned
bgAccountHasManager = BG Account {0} has a Manager
bgAccountNoManager = BG Account {0} doesn't have a Manager 
bgBothHaveManager = Both BreakGlass accounts have manager

# GuardRail #2
AADLicenseTypeFound = Found correct license type
AADLicenseTypeNotFound = Required AAD license type not found
accountNotDeleted = This user account has been deleted but has not yet been DELETED PERMANENTLY from Azure Active Directory
ADDeletedUser = AD Deleted User
ADDisabledUsers = AD Disabled Users
apiError = API Error
apiErrorMitigation = Please verify existance of the user (more likely) or application permissions.
compliantComment = Didnt find any unsynced deprecated users
gcPasswordGuidanceDoc = GC Password Guidance Doc
guestAccountsNoPermission = There are Guest accounts in the tenant but they don't have any permission in the subscriptions.
guestMustbeRemoved = This GUEST account should not have any role assignment in the Azure subscriptions
mitigationCommands = Verify is the users reported are deprecated.
noGuestAccounts = There are no GUEST users in your tenant.
noncompliantComment = Total Number of non-compliant users {0}. 
noncompliantUsers = The following Users are disabled and not synchronized with AD: -
privilegedAccountManagementPlan = Privileged Account Management plan
removeDeletedAccount = Permanently remove deleted accounts
removeDeprecatedAccount = Remove deprecated accounts
removeGuestAccounts = Remove guest accounts.
removeGuestAccountsComment = Remove guest accounts from Azure AD or remove their permissions from the Azure subscriptions.

# GuardRail #3
consoleAccessConditionalPolicy = Conditional Access Policy for Cloud Console Access.
noCompliantPoliciesfound=No compliant policies found. Policies need to have a single location and that location must be Canada Only.
allPoliciesAreCompliant=All policies are compliant.
noLocationsCompliant=No locations have only Canada in them.
authorizedProcessedByCSO = Authorized Access
mfaRequiredForAllUsers = Multi-Factor authentication required for all users by Conditional Access Policy
noMFAPolicyForAllUsers = No conditional access policy requiring MFA for all users and applications was found. A Conditional Access Policy meeting the following requirements must be configured: 1. state =  'enabled'; 2. includedUsers = 'All'; 3. includedApplications = 'All'; 4. grantControls.builtInControls contains 'mfa'; 5. clientAppTypes contains 'all'; 6. userRiskLevels = @(); 7. signInRiskLevels = @(); 8. platforms = null; 9. locations = null; 10. devices = null; 11. clientApplications = null

# GuardRail #4
monitorAccount = Monitor Account Creation
checkUserExistsError = API call returned Error {0}. Please Check if the user exists.
checkUserExists = Please Check if the user exists.
ServicePrincipalNameHasNoReaderRole = SPN doesnt have Reader Role on the ROOT Management Group.
ServicePrincipalNameHasReaderRole = SPN has Reader Role on the ROOT Management Group.
ServicePrincipalNameHasNoMarketPlaceAdminRole = SPN doesnt have Marketplace Admin Role on the Marketplace.
ServicePrincipalNameHasMarketPlaceAdminRole = SPN has Marketplace Admin Role on the Marketplace.
NoSPN = SPN doesnt exist.

# GuardRail #5-6
pbmmCompliance = PBMMPolicy Compliance
policyNotAssigned = The Policy or Initiative is not assigned to the {0}
excludedFromScope = {0} is excluded from the scope of the assignment
grexemptionFound = Exemption for {0} {1} found.
isCompliant = Compliant
policyNotAssignedRootMG = The Policy or Initiative is not assigned on the Root Management Groups
rootMGExcluded =This Root Management Groups is excluded from the scope of the assignment
pbmmNotApplied =PBMM Initiative is not applied.
subscription = subscription
managementGroup = Management Groups
notAllowedLocation =  Location is outside of the allowed locations. 
allowedLocationPolicy = AllowedLocationPolicy
dataAtRest = PROTECTION OF DATA-AT-REST
dataInTransit = PROTECTION OF DATA-IN-TRANSIT

# GuardRail #7
enableTLS12 = TLS 1.2+ is enabled whereever possible to secure data in transit

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
noSubnets = No subnets found in the subscription.

# GuardRail # 9
authSourceIPPolicyConfirm = Attestation that the authentication source IP policy is adhered to.
ddosEnabled=DDos Protection Enabled. 
ddosNotEnabled=DDos Protection not enabled.
limitPublicIPsPolicy = Attestation that the limit public IPs policy is adhered to.
networkBoundaryProtectionPolicy = Attestation that the network boundary protection policy is adhered to.
networkWatcherEnabled=Network Watcher exists for region '{0}'
networkWatcherNotEnabled=Network Watcher not enabled for region '{0}'
noVNets = No VNet found in the subscription.
vnetExcludedByParameter = VNet '{0}' is excluded from compliance because it is in the excluded VNet list '{1}'
vnetExcludedByTag = VNet '{0}' is excluded from compliance because it has tag '{1}' with a value of 'true'
vnetDDosConfig = VNet DDos configuration
networkWatcherConfig = VNet Network Watcher configuration
networkWatcherConfigNoRegions = Either due to no VNETs or all VNETs being excluded, there are no regions to check for Network Watcher configuration

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

# GuardRail #12
mktPlaceCreation = MarketPlaceCreation
mktPlaceCreated = The Private Marketplace has been created.
mktPlaceNotCreated = The Private Marketplace has not been created.
enableMktPlace = Enable Azure Private MarketPlace as per: https://docs.microsoft.com/en-us/marketplace/create-manage-private-azure-marketplace-new

# GR-Common
procedureFileFound = File {0} found in Container.
procedureFileNotFound = Could not find document for {0}, please create and upload a file with the name '{1}' in Container '{2}' on Storage Account '{3}' to confirm you have completed the Item in the control.

'@
