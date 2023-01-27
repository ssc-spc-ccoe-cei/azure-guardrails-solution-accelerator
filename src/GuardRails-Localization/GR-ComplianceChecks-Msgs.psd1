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
mfaEnforcement = MFA Enforcement
mfaEnabledFor =  MFA Authentication should not be enabled for BreakGlass account: {0} 
mfaDisabledFor =  MFA Authentication is not enabled for {0} 
m365Assignment = Microsoft 365 E5 Assignment
bgProcedure = Break Glass account Procedure
bgCreation = Break Glass account Creation
bgAccountResponsibility = Responsibility of break glass accounts must be with someone not-technical, director level or above
bgAccountOwnerContact = Break Glass Account Owners Contact information
bgAccountsCompliance = First Break Glass Account Compliance status = {0}, Second Break Glass Account Compliance status = {1}
bgAuthenticationMeth =  Authentication Methods 
firstBgAccount = First Break Glass Account
secondBgAccount = Second Break Glass Account
bgNoValidLicenseAssigned = No AAD P2 license assigned to
bgValidLicenseAssigned =  has a valid AAD P2 assigned
bgAccountHasManager = BG Account {0} has a Manager
bgAccountNoManager = BG Account {0} doesn't have a Manager 
bgBothHaveManager = Both BreakGlass accounts have manager

# GuardRail #2
removeDeletedAccount = Permanently remove deleted accounts
removeDeprecatedAccount = Remove deprecated accounts
removeGuestAccounts = Remove guest accounts.
accountNotDeleted = This user account has been deleted but has not yet been DELETED PERMANENTLY from Azure Active Directory
guestMustbeRemoved = This GUEST account should not have any role assignment in the Azure subscriptions
removeGuestAccountsComment = Remove guest accounts from Azure AD or remove their permissions from the Azure subscriptions.
noGuestAccounts = There are no GUEST users in your tenant.
guestAccountsNoPermission = There are Guest accounts in the tenant but they don't have any permission in the subscriptions.
ADDeletedUser = AD Deleted User
ADDisabledUsers = AD Disabled Users
noncompliantUsers = The following Users are disabled and not synchronized with AD: - 
noncompliantComment = Total Number of non-compliant users {0}. 
compliantComment = Didnt find any unsynced deprecated users
mitigationCommands = Verify is the users reported are deprecated.
apiError = API Error
apiErrorMitigation = Please verify existance of the user (more likely) or application permissions.
AADLicenseTypeFound = Found correct license type
AADLicenseTypeNotFound = Required AAD license type not found

# GuardRail #3
consoleAccessConditionalPolicy = Conditional Access Policy for Cloud Console Access.
noCompliantPoliciesfound=No compliant policies found. Policies need to have a single location and that location must be Canada Only.
allPoliciesAreCompliant=All policies are compliant.
noLocationsCompliant=No locations have only Canada in them.

# GuardRail #4
monitorAccount = Monitor Account Creation
checkUserExistsError = API call returned Error {0}. Please Check if the user exists.
checkUserExists = Please Check if the user exists.

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
subnetExcluded = Subnet Excluded (manually or reserved name).
networkDiagram = Network architecture diagram 
noSubnets = No subnets found in the subscription.

# GuardRail # 9
vnetDDosConfig = VNet DDos configuration
ddosEnabled=DDos Protection Enabled. 
ddosNotEnabled=DDos Protection not enabled.
noVNets = No VNet found in the subscription.

# GuardRail #10
cbsSubDoesntExist = CBS Subscription doesnt exist
cbcSensorsdontExist = The expected CBC sensors do not exist
cbssMitigation = Check subscription provided: {0} or check existence of the CBS solution in the provided subscription.
cbssCompliant = Found resources in these subscriptions: 

# GuardRail #11
securityMonitoring =SecurityMonitoring
healthMonitoring = HealthMonitoring
defenderMonitoring =DefenderMonitoring
securityLAWNotFound = The specified Log Analytics Workspace for Security monitoring has not been found.
lawRetention730Days = Retention not set to 730 days.
lawNoActivityLogs = WorkSpace not configured to ingest activity Logs.
lawSolutionNotFound = Required solutions not present in the Log Analytics Workspace.
lawNoAutoAcct = No linked automation account has been found.
lawNoTenantDiag = Tenant Diagnostics settings are not pointing to the provided log analytics workspace.
lawMissingLogTypes = Workspace set in tenant config but not all required log types are enabled (Audit and signin).
healthLAWNotFound = The specified Log Analytics Workspace for Health monitoring has not been found.
lawRetention90Days = Retention not set to at least 90 days.
lawHealthNoSolutionFound = Required solutions not present in the Health Log Analytics Workspace.
createLAW = Please create a log analytics workspace according to guidelines.
connectAutoAcct = Please connect an automation account to the provided workspace.
setRetention60Days = Set retention of the workspace to at least 90 days for workspace: 
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

# GuardRail #12
mktPlaceCreation = MarketPlaceCreation
mktPlaceCreated = The Private Marketplace has been created.
mktPlaceNotCreated = The Private Marketplace has not been created.
enableMktPlace = Enable Azure Private MarketPlace as per: https://docs.microsoft.com/en-us/marketplace/create-manage-private-azure-marketplace-new

# GR-Common
procedureFileFound = File {0} found in Container.
procedureFileNotFound = Coudnt find document for {0}, please create and upload a file with the name {1} in Container {2} on {3} Storage account to confirm you have completed the Item in the control.

'@
# SIG # Begin signature block
# MIInygYJKoZIhvcNAQcCoIInuzCCJ7cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCASGNXSGk02L7XH
# r5g7VxqnT9QlMXL+d5Uk5cG71hidiaCCDYEwggX/MIID56ADAgECAhMzAAACzI61
# lqa90clOAAAAAALMMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjIwNTEyMjA0NjAxWhcNMjMwNTExMjA0NjAxWjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQCiTbHs68bADvNud97NzcdP0zh0mRr4VpDv68KobjQFybVAuVgiINf9aG2zQtWK
# No6+2X2Ix65KGcBXuZyEi0oBUAAGnIe5O5q/Y0Ij0WwDyMWaVad2Te4r1Eic3HWH
# UfiiNjF0ETHKg3qa7DCyUqwsR9q5SaXuHlYCwM+m59Nl3jKnYnKLLfzhl13wImV9
# DF8N76ANkRyK6BYoc9I6hHF2MCTQYWbQ4fXgzKhgzj4zeabWgfu+ZJCiFLkogvc0
# RVb0x3DtyxMbl/3e45Eu+sn/x6EVwbJZVvtQYcmdGF1yAYht+JnNmWwAxL8MgHMz
# xEcoY1Q1JtstiY3+u3ulGMvhAgMBAAGjggF+MIIBejAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUiLhHjTKWzIqVIp+sM2rOHH11rfQw
# UAYDVR0RBEkwR6RFMEMxKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMRYwFAYDVQQFEw0yMzAwMTIrNDcwNTI5MB8GA1UdIwQYMBaAFEhu
# ZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNpZ1BDQTIwMTFfMjAxMS0w
# Ny0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUFBzAChkVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0NvZFNpZ1BDQTIwMTFfMjAx
# MS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAeA8D
# sOAHS53MTIHYu8bbXrO6yQtRD6JfyMWeXaLu3Nc8PDnFc1efYq/F3MGx/aiwNbcs
# J2MU7BKNWTP5JQVBA2GNIeR3mScXqnOsv1XqXPvZeISDVWLaBQzceItdIwgo6B13
# vxlkkSYMvB0Dr3Yw7/W9U4Wk5K/RDOnIGvmKqKi3AwyxlV1mpefy729FKaWT7edB
# d3I4+hldMY8sdfDPjWRtJzjMjXZs41OUOwtHccPazjjC7KndzvZHx/0VWL8n0NT/
# 404vftnXKifMZkS4p2sB3oK+6kCcsyWsgS/3eYGw1Fe4MOnin1RhgrW1rHPODJTG
# AUOmW4wc3Q6KKr2zve7sMDZe9tfylonPwhk971rX8qGw6LkrGFv31IJeJSe/aUbG
# dUDPkbrABbVvPElgoj5eP3REqx5jdfkQw7tOdWkhn0jDUh2uQen9Atj3RkJyHuR0
# GUsJVMWFJdkIO/gFwzoOGlHNsmxvpANV86/1qgb1oZXdrURpzJp53MsDaBY/pxOc
# J0Cvg6uWs3kQWgKk5aBzvsX95BzdItHTpVMtVPW4q41XEvbFmUP1n6oL5rdNdrTM
# j/HXMRk1KCksax1Vxo3qv+13cCsZAaQNaIAvt5LvkshZkDZIP//0Hnq7NnWeYR3z
# 4oFiw9N2n3bb9baQWuWPswG0Dq9YT9kb+Cs4qIIwggd6MIIFYqADAgECAgphDpDS
# AAAAAAADMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMTAeFw0xMTA3MDgyMDU5MDlaFw0yNjA3MDgyMTA5MDla
# MH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMT
# H01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQCr8PpyEBwurdhuqoIQTTS68rZYIZ9CGypr6VpQqrgG
# OBoESbp/wwwe3TdrxhLYC/A4wpkGsMg51QEUMULTiQ15ZId+lGAkbK+eSZzpaF7S
# 35tTsgosw6/ZqSuuegmv15ZZymAaBelmdugyUiYSL+erCFDPs0S3XdjELgN1q2jz
# y23zOlyhFvRGuuA4ZKxuZDV4pqBjDy3TQJP4494HDdVceaVJKecNvqATd76UPe/7
# 4ytaEB9NViiienLgEjq3SV7Y7e1DkYPZe7J7hhvZPrGMXeiJT4Qa8qEvWeSQOy2u
# M1jFtz7+MtOzAz2xsq+SOH7SnYAs9U5WkSE1JcM5bmR/U7qcD60ZI4TL9LoDho33
# X/DQUr+MlIe8wCF0JV8YKLbMJyg4JZg5SjbPfLGSrhwjp6lm7GEfauEoSZ1fiOIl
# XdMhSz5SxLVXPyQD8NF6Wy/VI+NwXQ9RRnez+ADhvKwCgl/bwBWzvRvUVUvnOaEP
# 6SNJvBi4RHxF5MHDcnrgcuck379GmcXvwhxX24ON7E1JMKerjt/sW5+v/N2wZuLB
# l4F77dbtS+dJKacTKKanfWeA5opieF+yL4TXV5xcv3coKPHtbcMojyyPQDdPweGF
# RInECUzF1KVDL3SV9274eCBYLBNdYJWaPk8zhNqwiBfenk70lrC8RqBsmNLg1oiM
# CwIDAQABo4IB7TCCAekwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFEhuZOVQ
# BdOCqhc3NyK1bajKdQKVMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1Ud
# DwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO
# 4eqnxzHRI4k0MFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwubWljcm9zb2Z0
# LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcmwwXgYIKwYBBQUHAQEEUjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcnQwgZ8GA1UdIASBlzCBlDCBkQYJKwYBBAGCNy4DMIGDMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2RvY3MvcHJpbWFyeWNw
# cy5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AcABvAGwAaQBjAHkA
# XwBzAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAGfyhqWY
# 4FR5Gi7T2HRnIpsLlhHhY5KZQpZ90nkMkMFlXy4sPvjDctFtg/6+P+gKyju/R6mj
# 82nbY78iNaWXXWWEkH2LRlBV2AySfNIaSxzzPEKLUtCw/WvjPgcuKZvmPRul1LUd
# d5Q54ulkyUQ9eHoj8xN9ppB0g430yyYCRirCihC7pKkFDJvtaPpoLpWgKj8qa1hJ
# Yx8JaW5amJbkg/TAj/NGK978O9C9Ne9uJa7lryft0N3zDq+ZKJeYTQ49C/IIidYf
# wzIY4vDFLc5bnrRJOQrGCsLGra7lstnbFYhRRVg4MnEnGn+x9Cf43iw6IGmYslmJ
# aG5vp7d0w0AFBqYBKig+gj8TTWYLwLNN9eGPfxxvFX1Fp3blQCplo8NdUmKGwx1j
# NpeG39rz+PIWoZon4c2ll9DuXWNB41sHnIc+BncG0QaxdR8UvmFhtfDcxhsEvt9B
# xw4o7t5lL+yX9qFcltgA1qFGvVnzl6UJS0gQmYAf0AApxbGbpT9Fdx41xtKiop96
# eiL6SJUfq/tHI4D1nvi/a7dLl+LrdXga7Oo3mXkYS//WsyNodeav+vyL6wuA6mk7
# r/ww7QRMjt/fdW1jkT3RnVZOT7+AVyKheBEyIXrvQQqxP/uozKRdwaGIm1dxVk5I
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZnzCCGZsCAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAsyOtZamvdHJTgAAAAACzDAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgel5aSJfq
# vpuzFyQfB5kjgCQ+SXRqPoppJ9F0OV3iYJowQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQCec6lwCGWQwJE7v0kcmALFydLPkYEvAlkyxI4dg+pK
# XeverqPx1sS2p3J1NGJNwHnUaW3f2LMdlgZ10Fvpw+X+AVg1TcJBjGm3/cYkhkr1
# gXFS0tj7ChyGp/Z234q3dtVP53I9vdYUKXuu6gJekRWp42QMvXduC8rXm4S/hROJ
# ROonAR8OofKRIM30q0AX0wSzkJWP5siQZASuL5MHqaY3+8Azb1V6FbVGcvHZMDhJ
# KeB6TNhvX1X8l2RvKUA9jn8EVR2fwK341KCtquQgXYJee562IEensx9zw/faD8kB
# SCfRWOoT443EcRXRn65OIBQocBL36v/m/fJ20IvuXiHIoYIXKTCCFyUGCisGAQQB
# gjcDAwExghcVMIIXEQYJKoZIhvcNAQcCoIIXAjCCFv4CAQMxDzANBglghkgBZQME
# AgEFADCCAVkGCyqGSIb3DQEJEAEEoIIBSASCAUQwggFAAgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIG6cr8DfGaNT0rwocYvnpZrPn5/omO2hnVsfsHOX
# jB7CAgZjx90lce4YEzIwMjMwMTI1MjIyNTQzLjU3MlowBIACAfSggdikgdUwgdIx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1p
# Y3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhh
# bGVzIFRTUyBFU046MDg0Mi00QkU2LUMyOUExJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WgghF4MIIHJzCCBQ+gAwIBAgITMwAAAbJuQAN/bqmU
# kgABAAABsjANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDAeFw0yMjA5MjAyMDIyMDFaFw0yMzEyMTQyMDIyMDFaMIHSMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQg
# SXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1Mg
# RVNOOjA4NDItNEJFNi1DMjlBMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAyqJlMh17
# +VDisL4GaXl/9a6r/EpPGt9sbbceh+ZD6pkA3gbI7vc8XfL04B+m3tB/aNyV1Y4Z
# QH4fMG7CWVjI/d/HgxjzO+4C4HfsW+jK2c0LYMqdWtWUc5VwZQv0KeaEM0wDb+ey
# SMh/YiiIb0nSotivx268d1An0uLY+r2C7JJv2a9QvrSiCyUI72CSHoWIQPAyvBSv
# xaNrqMWlROfLy2DQ3RycI3bDh8qSnmplxtRgViJwtJv/oDukcK1frGeOrCGYmiJv
# e+QonJXFu4UtGFVfEf3lvQsd42GJ+feO+jaP7/hBXXSMSldVb6IL0GxO1Hr3G9ON
# TnVmA/sFHhgMRarsmzKVI6/kHlMdMNdF/XzhRHMWFPJvw5lApjuaoyHtzwnzDWwQ
# zhcNQXZRk3Lzb01ULMba190RdlofEXxGbGlBgHHKFnBjWui24hL6B83Z6r6GQBPe
# Kkafz8qYPAO3MBud+5eMCmB5mrCBxgnykMn7L/FTqi7MnPUG97lNOKGSIDvBCxB7
# pHrRmT10903PDQwrmeJHO5BkC3gYj3oWGOGVRZxRk4KS/8lcz84a7+uBKmVjB2Y8
# vPN8O1fK7L8YJTkjiXTyDqKJ9fKkyChiSRx44ADPi/HXHQE6dlZ8jd9LCo1S+g3u
# dxNP4wHhWm9/VAGmmMEBBS6+6Lp4IbQwJU0CAwEAAaOCAUkwggFFMB0GA1UdDgQW
# BBSZ8ieAXNkRmU+SMM5WW4FIMNpqcTAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQM
# MAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEA
# 3Ee27cXMhptoNtaqzB0oGUCEpdEI37kJIyK/ZNhriLZC5Yib732mLACEOEAN9uqi
# vXPIuL3ljoZCe8hZSB14LugvVm1nJ73bNgr4Qh/BhmaFL4IfiKd8DNS+xwdkXfCW
# slR89QgMZU/SUJhWx72aC68bR2qRjhrJA8Qc68m5uBllo52D83x0id3p8Z45z7QO
# gbMH4uJ45snZDQC0S3dc3eJfwKnr51lNfzHAT8u+FHA+lv/6cqyE7tNW696fB1PC
# oH8tPoI09oSXAV4rEqupFM8xsd6D6L4qcEt/CaERewyDazVBfskjF+9P3qZ3R6Iy
# OIwQ7bYts7OYsw13csg2jACdEEAm1f7f97f3QH2wwYwen5rVX6GCzrYCikGXSn/T
# SWLfQM3nARDkh/flmTtv9PqkTHqslQNgK2LvMJuKSMpNqcGc5z33MYyV6Plf58L+
# TkTFQKs6zf9XMZEJm3ku9VBJ1aqr9AzNMSaKbixvMBIr2KYSSM21lnK8LUKxRwPW
# +gWS2V3iYoyMT64MRXch10P4OtGT3idXM09K5ld7B9U6dcdJ6obvEzdXt+XZovi/
# U6Evb4nA7VPHcHSKs7U72ps10mTfnlue13VFJUqAzbYoUEeegvsmzulGEGJoqZVN
# Aag5v6PVBrur5yLEajjxWH2TfkEOwlL8MuhcVI8OXiYwggdxMIIFWaADAgECAhMz
# AAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9v
# dCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAeFw0yMTA5MzAxODIyMjVaFw0z
# MDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIICIjAN
# BgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA5OGmTOe0ciELeaLL1yR5vQ7VgtP9
# 7pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/XE/HZveVU3Fa4n5KWv64NmeFRiMM
# tY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1hlDcwUTIcVxRMTegCjhuje3XD9gm
# U3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7M62AW36MEBydUv626GIl3GoPz130
# /o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3KNi1wjjHINSi947SHJMPgyY9+tVSP
# 3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy1cCGMFxPLOJiss254o2I5JasAUq7
# vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF803RKJ1v2lIH1+/NmeRd+2ci/bfV+A
# utuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQcNIIP8BDyt0cY7afomXw/TNuvXsLz
# 1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahhaYQFzymeiXtcodgLiMxhy16cg8ML6
# EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkLiWHzNgY1GIRH29wb0f2y1BzFa/Zc
# UlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV2xo3xwgVGD94q0W29R6HXtqPnhZy
# acaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIGCSsGAQQBgjcVAQQFAgMBAAEwIwYJ
# KwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUpzxD/LwTuMB0GA1UdDgQWBBSfpxVd
# AF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBTMFEGDCsGAQQBgjdMg30BATBBMD8G
# CCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3Mv
# UmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYBBAGCNxQC
# BAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYD
# VR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZF
# aHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9v
# Q2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcw
# AoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJB
# dXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcNAQELBQADggIBAJ1VffwqreEsH2cB
# MSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1OdfCcTY/2mRsfNB1OW27DzHkwo/7
# bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYAA7AFvonoaeC6Ce5732pvvinLbtg/
# SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbzaN9l9qRWqveVtihVJ9AkvUCgvxm2
# EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6LGYnn8AtqgcKBGUIZUnWKNsIdw2Fz
# Lixre24/LAl4FOmRsqlb30mjdAy87JGA0j3mSj5mO0+7hvoyGtmW9I/2kQH2zsZ0
# /fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0SCyxTkctwRQEcb9k+SS+c23Kjgm9
# swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxkoJLo4S5pu+yFUa2pFEUep8beuyOiJ
# Xk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFmPWn9y8FBSX5+k77L+DvktxW/tM4+
# pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC4822rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW
# 4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7vzhwRNGQ8cirOoo6CGJ/2XBjU02N
# 7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIC1DCCAj0CAQEwggEAoYHYpIHVMIHSMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxl
# cyBUU1MgRVNOOjA4NDItNEJFNi1DMjlBMSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQCOEn4R7JJF+fYoI2yOf1wX
# 0BRJOqCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
# SIb3DQEBBQUAAgUA53uV9jAiGA8yMDIzMDEyNTE5NTAxNFoYDzIwMjMwMTI2MTk1
# MDE0WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDne5X2AgEAMAcCAQACAiBkMAcC
# AQACAhFLMAoCBQDnfOd2AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkK
# AwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQEFBQADgYEAYSv5
# 9tSKtXDhfP4F2UK/1jXDBq3G1zMhvcegtiJfjdDhZIrjng434G3dsOVdFuFlMYvD
# vPvFGEn1u5F5g/VRVYH+n09SMtnJBC9ctYZ7o/wS/rpn+iTj/dGsaE/4Zgb5ariI
# jrD6CgfWTFMYCUz/WdK0TPAQFQoBXRc3EJl7x3MxggQNMIIECQIBATCBkzB8MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNy
# b3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAbJuQAN/bqmUkgABAAABsjAN
# BglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8G
# CSqGSIb3DQEJBDEiBCAL21U8ydzLBWUNHQeClZk5Z20pFXY3+Rs4Pq3IyWXDPjCB
# +gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIFN4zjzn4T63g8RWJ5SgUpfs9XIu
# j+fO76G0k8IbTj41MIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIw
# MTACEzMAAAGybkADf26plJIAAQAAAbIwIgQgK0Lv0IEUbEQIdXpkzRZMiVCMbxEY
# ogAuheEu3cPoF/UwDQYJKoZIhvcNAQELBQAEggIAA0fMJm+PCmORWPwWNOunULHX
# itgnBrkbcs5l6jMt3e8JwJVYm0yfc5MW6eXznHYT1wEkHzypfazYQ5zg/kZDY7WN
# honW263ruBYqS+36I/sD7pgB4CVR099jStQcFK2s5WwjQ/7SEoaLGWyf6ZXdtrW+
# 3UKp/8Kp9NQ4hWuKqr1uBlvKPn4nBmv/RlBjxz0UhEBj06+jFdtUiuAeMOShfhNE
# pPMtKDwHcVX62SB2kiQr5DCiDDV0T8x8zZUzaN3sFYp8uMPX9l+kc0J+imIOHrwf
# 9XNPk4oLrElJr84AhOYrYsUPNm5iemvkGPl1tuVNhUsAy9LrQr+t/2QzNdxVP9MU
# 5j8X7FWBQeHd8beBDM+42xMZzj7ft9k5V6cHNKgCJsEOtBJMY4EEPTArST6Ckk5n
# Th8S/N/2XTqtB+6A1M2F+m7CajKyj+luy9gaJGa/CM/qiYEKZRlu4iVv4uNljCNY
# G0FQ3w4zu5rMinPfQ4vU2q8hRkcswcNQCLw1bateRGLxvWMEv/8MbqPa4+awM0gJ
# aDz8RhLjyFCwSwVpfEnCmrJl1NUaGXG2i/ODPvubzQ0vtnsI27kgLPzMYioEVfmS
# 5ssOhcYcqE3IqTXywkQ056ws29MNwa4w+0IDhXxkxTnsMQt4aew6JQpcXZhR6LBm
# EAzmTGJBgPlOa1ldIa4=
# SIG # End signature block
