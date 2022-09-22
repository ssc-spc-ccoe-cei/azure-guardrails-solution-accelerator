ConvertFrom-StringData @'

# French strings

CtrName1 = GUARDRAIL 1: PROTÉGER LE COMPTE RACINE / ADMINISTRATEURS GLOBAUX
CtrName2 = GUARDRAIL 2: GESTION DES PRIVILÈGES ADMINISTRATIFS
CtrName3 = GUARDRAIL 3: ACCÈS À LA CONSOLE CLOUD
CtrName4 = GUARDRAIL 4: COMPTES DE SURVEILLANCE D'ENTREPRISE
CtrName5 = GUARDRAIL 5: EMPLACEMENT DES DONNÉES
CtrName6 = GUARDRAIL 6: PROTECTION DES DONNÉES AU REPOS
CtrName7 = GUARDRAIL 7: PROTECTION DES DONNÉES EN TRANSIT
CtrName8 = GUARDRAIL 8: SEGMENTATION ET SÉPARATION DU RÉSEAU
CtrName9 = GUARDRAIL 9: SERVICES DE SÉCURITÉ RÉSEAU
CtrName10 = GUARDRAIL 10: SERVICES DE CYBER DÉFENSE
CtrName11 = GUARDRAIL 11: ENREGISTREMENT ET SURVEILLANCE
CtrName12 = GUARDRAIL 12: CONFIGURATION DES MARKETPLACES

# Guardrail 1
adLicense = Type de licence AD
mfaEnforcement = Application MFA
mfaEnabledFor =  L'authentication MFA ne devrait pas être activée pour le compte brise-glace: {0} 
mfaDisabledFor =  L'authentication MFA n'est pas activée pour {0} 
m365Assignment = Affectation Microsoft 365 E5
bgProcedure = Procédure de compte Brise Glass
bgCreation = Création de compte Brise Glass
bgAccountResponsibility = La responsabilité des comptes bris de glace doit incomber à une personne non technique, de niveau directeur ou supérieur
bgAccountOwnerContact = Coordonnées des titulaires de compte Brise Glass
bgAccountsCompliance = {0} Statut de conformité = {1}, {2} Statut de conformité = {3}
bgAuthenticationMeth =  Méthodes d'authentification 
bgLicenseNotAssigned = NON ASSIGNÉ
bgAssignedLicense =  Licence attribuée = 
bgAccountHasManager = Le compte BG {0} a un responsable
bgAccountNoManager =  Le compte BG {0} n'a pas de gestionnaire 
bgBothHaveManager =  Les deux comptes BreakGlass ont un gestionnaire

# GuardRail #2
removeDeletedAccount = Supprimez définitivement les comptes supprimés
removeDeprecatedAccount = Supprimez les comptes obsolètes
removeGuestAccounts = Supprimez les comptes invités.
accountNotDeleted = Ce compte d'utilisateur a été supprimé mais n'a pas encore été SUPPRIMÉ DÉFINITIVEMENT d'Azure Active Directory
guestMustbeRemoved = Ce comptes invité ne devraient pas avoir de rôles dans les abonnements Azure
removeGuestAccountsComment = Supprimez les comptes invités d'Azure AD ou supprimez leurs permissions dans les abonnements Azure.
noGuestAccounts = Il n'y a aucun compte invité dans votre tenant
guestAccountsNoPermission = Il y a des comptes invités dans le tenant mais ils n'ont pas de permissions dans les abonnements Azure.
ADDeletedUser = Utilisateur AD Supprimé
ADDisabledUsers = Utilisateur AD désactivé
noncompliantUsers = Les utilisateurs suivants sont désactivés et ne sont pas synchronisés avec AD: - 
noncompliantComment = Nombre d'utilisateurs non-conformes {0}. 
compliantComment = Aucun utilisateur non synchronisé ou désactivé trouvé
mitigationCommands = Vérifiez si les utilisateurs trouvés sont obsolètes. 
apiError = Erreur API
apiErrorMitigation = Vérifiez l'existence des utilisateurs ou les permissions de l'application.


# GuardRail #3
noCompliantPoliciesfound=Aucune stratégie conforme n'a été trouvée. Les politiques doivent avoir un emplacement unique et cet emplacement doit être réservé au Canada.
allPoliciesAreCompliant=Toutes les politiques sont conformes.
noLocationsCompliant=Aucun endroit n'a seulement le Canada en eux.
consoleAccessConditionalPolicy = Stratégie d'accès conditionnel pour l'accès à la console.

# GuardRail #4
monitorAccount = Surveiller la création de compte
checkUserExistsError = L'appel API a retourné l'erreur {0}. Veuillez vérifier si l'utilisateur existe.
checkUserExists = Veuillez vérifier si l'utilisateur existe.

# GuardRail #5-6
pbmmCompliance = Conformité PBMMPolicy
policyNotAssigned = La politique ou l'initiative n'est pas affectée au {0}
excludeFromScope = {0} est exclu de la portée de l'affectation
isCompliant = Conforme
policyNotAssignedRootMG = La politique ou l'initiative n'est pas affectée aux groupes de gestion racine
rootMGExcluded = Ce groupe de gestion racine est exclu de la portée de l'affectation
pbmmNotApplied = L'initiative PBMM n'est pas appliquée.
grexemptionFound = excemption pour {0} {1} trouvée
subscription  = abonnement
managementGroup = Groupes de gestion
notAllowedLocation =  L'emplacement est en dehors des emplacements autorisés. 
allowLocationPolicy = Politique de localisation autorisée
dataAtRest = PROTECTION DES DONNÉES-AU-REPOS
dataInTransit = PROTECTION DES DONNÉES-EN-TRANSIT

# GuardRail #8
noNSG=Aucun NSG n'est présent.
subnetCompliant = Le sous-réseau est conforme.
nsgConfigDenyAll = NSG est présent mais n'est pas correctement configuré (dernière règle de refus manquante).
nsgCustomRule = NSG est présent mais n'est pas correctement configuré (règles personnalisées manquantes).
networkSegmentation = Segmentation
networkSeparation = Séparation
routeNVA = Route présente mais non dirigée vers une appliance virtuelle.
routeNVAMitigation = Mettre à jour la route pour pointer vers une appliance virtuelle
noUDR = Aucune route définie par l'utilisateur configurée.
noUDRMitigation = Veuillez appliquer une route personnalisée à ce sous-réseau, pointant vers une appliance virtuelle.
subnetExcluded = Sous-réseau exclu (nom manuel ou réservé).
networkDiagram = Existence d'un diagramme d'architecture réseau 

# GuardRail # 9
vnetDDosConfig = Configuration DDos VNet
ddosEnabled = Protection DDos activée. 
ddosNotEnabled = Protection DDos non activée.

# GuardRail #10
cbsSubDoesntExist = L'abonnement CBS n'existe pas
cbcSensorsdontExist = Les capteurs CBC attendus n'existent pas
cbssMitigation = Vérifiez l'abonnement fourni: {0} ou vérifiez l'existence de la solution CBS dans l'abonnement fourni.
cbssCompliant = Ressources trouvées dans ces abonnements: 

# GuardRail #11
securityMonitoring = Surveillance de la sécurité
HealthMonitoring = Surveillance Santé
defenderMonitoring =Surveillance Defender
securityLAWNotFound = L'espace de travail Log Analytics spécifié pour la surveillance de la sécurité est introuvable.
lawRetention730Days = La rétention n'est pas définie sur 730 jours.
lawNoActivityLogs = WorkSpace n'est pas configuré pour ingérer les journaux d'activité.
lawSolutionNotFound = Les solutions requises ne sont pas présentes dans l'espace de travail Log Analytics.
lawNoAutoAcct = Aucun compte d'automatisation lié n'a été trouvé.
lawNoTenantDiag = Les paramètres de diagnostic des locataires ne pointent pas vers l'espace de travail d'analyse des journaux fourni.
lawMissingLogTypes = L'espace de travail est défini dans la configuration du locataire, mais tous les types de journaux requis ne sont pas activés (audit et connexion).
healthLAWNotFound = L'espace de travail Log Analytics spécifié pour la surveillance de la santé est introuvable.
lawRetention90Days = La rétention n'est pas définie sur au moins 90 jours.
lawHealthNoSolutionFound = Les solutions requises ne sont pas présentes dans l'espace de travail Health Log Analytics.
createLAW = Veuillez créer un espace de travail d'analyse de journaux conformément aux directives.
connectAutoAcct = Veuillez connecter un compte d'automatisation à l'espace de travail fourni.
setRetention60Days = Définir la rétention de l'espace de travail sur au moins 90 jours pour l'espace de travail: 
setRetention730Days = Définir la rétention de l'espace de travail à 730 jours pour l'espace de travail: 
addActivityLogs = Veuillez ajouter la solution Activity Logs à l'espace de travail: 
addUpdatesAndAntiMalware = Veuillez ajouter à la fois la solution Mises à jour et Anti-Malware à l'espace de travail: 
configTenantDiag = Veuillez configurer les diagnostics de locataire pour qu'ils pointent vers l'espace de travail fourni: 
addAuditAndSignInsLogs = Veuillez activer les journaux d'audit et SignInLogs dans les paramètres de Tenant Dianostics.
logsAndMonitoringCompliantForSecurity = Les journaux et la surveillance sont conformes pour la sécurité.
logsAndMonitoringCompliantForHealth = Les journaux et la surveillance sont conformes pour la santé.
logsAndMonitoringCompliantForDefender = Les journaux et la surveillance sont conformes pour Defender.
createHealthLAW = Veuillez créer un espace de travail pour la surveillance de la santé conformément aux directives de Guardrails.
enableAgentHealthSolution = Veuillez activer la solution d'évaluation de l'état de santé de l'agent dans l'espace de travail.
lawEnvironmentCompliant = L'environnement est conforme.
noSecurityContactInfo = L'abonnement {0} manque d'informations de contact.
setSecurityContact = Veuillez définir un contact de sécurité pour Defender for Cloud dans l'abonnement. {0}
notAllDfCStandard = Toutes les options de plan de tarification ne sont pas définies sur Standard pour l'abonnement {0}
setDfCToStandard = Veuillez définir les forfaits Defender pour le cloud sur Standard. ({0})

# GuardRail #12
mktPlaceCreation = Création Place de marché
mktPlaceCreated = Le marché privé a été créé.
mktPlaceNotCreated = Le marché privé n'a pas été créé.
enableMktPlace = Activer Azure Private MarketPlace selon: https://docs.microsoft.com/en-us/marketplace/create-manage-private-azure-marketplace-new

# GR-Common
procedureFileFound = Fichier {0} trouvé.
procedureFileNotFound = Impossible de trouver le document pour {0}, veuillez créer et télécharger un fichier avec le nom {1} dans le conteneur {2} du compte de stockage {3} pour confirmer que vous avez terminé l'élément dans le contrôle.

'@
# SIG # Begin signature block
# MIIntwYJKoZIhvcNAQcCoIInqDCCJ6QCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBzISTess8dUe6R
# WXMdTlLVxa/VZjenBc/ginTwaOsBfKCCDYEwggX/MIID56ADAgECAhMzAAACzI61
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
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZjDCCGYgCAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAsyOtZamvdHJTgAAAAACzDAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgz2448HLQ
# YXvVyVqJSypxR+Ro7BohsOJeNdRE+zkPJZwwQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQBRoDZijm1JthowkhfPbE/ShoIBBQeAK0Op1FklXKBA
# cTIlrLGcqCQXfqObmdanH3IzW7KHjOP8kNsoXFqj3Ma/fyjMYrJqOh9HVZjF6T0E
# AEtXoedamoyGUP20j9c4Em1xl3pnzJyWqQEJOZqnIcDnvjKlq8pJeTBNH8brpner
# xSMAeCXFQ23zvfQfPwjPZdgi4oE1HwTDVcc7PuB0PM1tej6XROBxZKlm/drnpmUM
# LUricrXBOqQ+UpvS6ydhh1lHud/qv6I2OfCsE9GCylTgQ3w3sp6u3sywb0tY41Qo
# 6/rYfgr9T63xHPzMsgTte7MwK27naYX6BfjA4HhBHX/moYIXFjCCFxIGCisGAQQB
# gjcDAwExghcCMIIW/gYJKoZIhvcNAQcCoIIW7zCCFusCAQMxDzANBglghkgBZQME
# AgEFADCCAVkGCyqGSIb3DQEJEAEEoIIBSASCAUQwggFAAgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIMynEJ9nt8DaffkLDrMprAiR0Ye0HNXx8ZwewTrY
# aQcoAgZjEWDk2VsYEzIwMjIwOTE1MjIxMzA4Ljc1OVowBIACAfSggdikgdUwgdIx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1p
# Y3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhh
# bGVzIFRTUyBFU046MkFENC00QjkyLUZBMDExJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WgghFlMIIHFDCCBPygAwIBAgITMwAAAYZ45RmJ+CRL
# zAABAAABhjANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDAeFw0yMTEwMjgxOTI3MzlaFw0yMzAxMjYxOTI3MzlaMIHSMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQg
# SXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1Mg
# RVNOOjJBRDQtNEI5Mi1GQTAxMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAwI3G2Wpv
# 6B4IjAfrgfJpndPOPYO1Yd8+vlfoIxMW3gdCDT+zIbafg14pOu0t0ekUQx60p7Pa
# dH4OjnqNIE1q6ldH9ntj1gIdl4Hq4rdEHTZ6JFdE24DSbVoqqR+R4Iw4w3GPbfc2
# Q3kfyyFyj+DOhmCWw/FZiTVTlT4bdejyAW6r/Jn4fr3xLjbvhITatr36VyyzgQ0Y
# 4Wr73H3gUcLjYu0qiHutDDb6+p+yDBGmKFznOW8wVt7D+u2VEJoE6JlK0EpVLZus
# dSzhecuUwJXxb2uygAZXlsa/fHlwW9YnlBqMHJ+im9HuK5X4x8/5B5dkuIoX5lWG
# jFMbD2A6Lu/PmUB4hK0CF5G1YaUtBrME73DAKkypk7SEm3BlJXwY/GrVoXWYUGEH
# yfrkLkws0RoEMpoIEgebZNKqjRynRJgR4fPCKrEhwEiTTAc4DXGci4HHOm64EQ1g
# /SDHMFqIKVSxoUbkGbdKNKHhmahuIrAy4we9s7rZJskveZYZiDmtAtBt/gQojxbZ
# 1vO9C11SthkrmkkTMLQf9cDzlVEBeu6KmHX2Sze6ggne3I4cy/5IULnHZ3rM4ZpJ
# c0s2KpGLHaVrEQy4x/mAn4yaYfgeH3MEAWkVjy/qTDh6cDCF/gyz3TaQDtvFnAK7
# 0LqtbEvBPdBpeCG/hk9l0laYzwiyyGY/HqMCAwEAAaOCATYwggEyMB0GA1UdDgQW
# BBQZtqNFA+9mdEu/h33UhHMN6whcLjAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoG
# CCsGAQUFBwMIMA0GCSqGSIb3DQEBCwUAA4ICAQDD7mehJY3fTHKC4hj+wBWB8544
# uaJiMMIHnhK9ONTM7VraTYzx0U/TcLJ6gxw1tRzM5uu8kswJNlHNp7RedsAiwviV
# QZV9AL8IbZRLJTwNehCwk+BVcY2gh3ZGZmx8uatPZrRueyhhTTD2PvFVLrfwh2li
# DG/dEPNIHTKj79DlEcPIWoOCUp7p0ORMwQ95kVaibpX89pvjhPl2Fm0CBO3pXXJg
# 0bydpQ5dDDTv/qb0+WYF/vNVEU/MoMEQqlUWWuXECTqx6TayJuLJ6uU7K5QyTkQ/
# l24IhGjDzf5AEZOrINYzkWVyNfUOpIxnKsWTBN2ijpZ/Tun5qrmo9vNIDT0lobgn
# ulae17NaEO9oiEJJH1tQ353dhuRi+A00PR781iYlzF5JU1DrEfEyNx8CWgERi90L
# KsYghZBCDjQ3DiJjfUZLqONeHrJfcmhz5/bfm8+aAaUPpZFeP0g0Iond6XNk4YiY
# bWPFoofc0LwcqSALtuIAyz6f3d+UaZZsp41U4hCIoGj6hoDIuU839bo/mZ/AgESw
# GxIXs0gZU6A+2qIUe60QdA969wWSzucKOisng9HCSZLF1dqc3QUawr0C0U41784K
# o9vckAG3akwYuVGcs6hM/SqEhoe9jHwe4Xp81CrTB1l9+EIdukCbP0kyzx0WZzte
# eiDN5rdiiQR9mBJuljCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUw
# DQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhv
# cml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg
# 4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aO
# RmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41
# JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5
# LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL
# 64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9
# QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj
# 0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqE
# UUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0
# kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435
# UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB
# 3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTE
# mr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwG
# A1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93
# d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNV
# HSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNV
# HQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo
# 0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29m
# dC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5j
# cmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDAN
# BgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4
# sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th54
# 2DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRX
# ud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBew
# VIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0
# DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB62FD+Cljd
# QDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFr
# DZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFh
# bHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7n
# tdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+
# oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6Fw
# ZvKhggLUMIICPQIBATCCAQChgdikgdUwgdIxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJh
# dGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046MkFENC00Qjky
# LUZBMDExJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoB
# ATAHBgUrDgMCGgMVAAGu2DRzWkKljmXySX1korHL4fMnoIGDMIGApH4wfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZIhvcNAQEFBQACBQDmzarQMCIY
# DzIwMjIwOTE1MjE0NDQ4WhgPMjAyMjA5MTYyMTQ0NDhaMHQwOgYKKwYBBAGEWQoE
# ATEsMCowCgIFAObNqtACAQAwBwIBAAICDkEwBwIBAAICEZEwCgIFAObO/FACAQAw
# NgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgC
# AQACAwGGoDANBgkqhkiG9w0BAQUFAAOBgQAqu5tbHLJpYYPKqs23GWAlJhu2huSH
# wonZvOCJh1tgVhf9V1M3XkJlN2/GL/eQLjLRbuaRd2m7y1qHk23KslL5DgklTCHd
# ciemFywazzIebWkyqqh7NhEs/1iMGvaCKQ7f4kfrA+d1kq06jGND1EpOE89pUMqO
# ult+QnAOmnNupDGCBA0wggQJAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAABhnjlGYn4JEvMAAEAAAGGMA0GCWCGSAFlAwQCAQUAoIIBSjAa
# BgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIEXLxNIe
# d6rn/eJ89rva97L7D1GC5LcPV3jDUweCfv7bMIH6BgsqhkiG9w0BCRACLzGB6jCB
# 5zCB5DCBvQQgGpmI4LIsCFTGiYyfRAR7m7Fa2guxVNIw17mcAiq8Qn4wgZgwgYCk
# fjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
# Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAYZ45RmJ+CRLzAAB
# AAABhjAiBCAM7/9+Nx3qXVsNd3nSssdRUZrx30kLQMoYlkrqE5o8XDANBgkqhkiG
# 9w0BAQsFAASCAgBXyXawc/8AxJrI6GnIu+UJDioj1cUMCpN9KvVGXBPKCa8ox8+g
# 6VbcO/KgiwBPyjDF2sVu/gWNqdYiFg+Nq/CFmQz3jAZ8NdgGZzYcy/+5bMug2Zea
# DKQWouj9rTvgGflyKsP/2WeMeYvczmwe0826hTIPPsdmpitg8OZQu4jU0KwZ7lO2
# VY/tr4zw1WXGNo8SdZoOkX1t7AC0JFLYE/IBaHr3+jcmUZ5ZYM1JfS31sychFxgj
# aK/Z6UdhJuPlYSolE+eVxxBI1Ti2hCUryUOwEJMHtOPWUZ1GsQFvcQW0tuDlE3Le
# SSE1i7FKPARwShxsZ3nxWfFc6EKKC6gPu5JKHBvfXXBtL2tg1VXnD6M4OXS/9Dwf
# b9UjbtV3BPLBdXynNlHW0BzQIhpDyDiW7cZcbsAyiV/d6haulXhsA9w52jzug6F1
# m3rcV4eTb698ZEPnoFtFV1J9Z1zFALdCVCbj00cRtjEIyUJ0oVzho7VqBNOHU2o+
# AK6LEfON7dJ2BYQsl1g91PmKGz/MUEBiW3eeCeIWPPK5tt2lnfIbCTkf8UkLmRZB
# +kZrGnnbVOZawkCJVt4Hb/lYNJ44xtcF6HUVYJAdNUproWqByY2d+jUYfNEgamw3
# e5mlENv38W5gsXOBy0+HW+PQU9dZ7WJtIejUflIkmBHM7Chw8Sf8E4PN6g==
# SIG # End signature block
