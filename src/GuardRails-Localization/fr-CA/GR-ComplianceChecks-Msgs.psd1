ConvertFrom-StringData @'

# French strings

CtrName1 = GUARDRAIL 1: PROTÉGER LES COMPTES ET LES IDENTITÉS DES UTILISATEURS
CtrName2 = GUARDRAIL 2: GÉRER L'ACCÈS
CtrName3 = GUARDRAIL 3: SÉCURISER LES POINTS D'EXTRÉMITÉ
CtrName4 = GUARDRAIL 4: COMPTES DE SURVEILLANCE DE L'ORGANISATION
CtrName5 = GUARDRAIL 5: EMPLACEMENT DES DONNÉES
CtrName6 = GUARDRAIL 6: PROTECTION DES DONNÉES INACTIVES
CtrName7 = GUARDRAIL 7: PROTECTION DES DONNÉES EN TRANSIT
CtrName8 = GUARDRAIL 8: SEGMENTER ET SÉPARER
CtrName9 = GUARDRAIL 9: SERVICES DE SÉCURITÉ DES RÉSEAUX
CtrName10 = GUARDRAIL 10: SERVICES DE CYBER DÉFENSE
CtrName11 = GUARDRAIL 11: JOURNALISATION ET SURVEILLANCE
CtrName12 = GUARDRAIL 12: CONFIGURATION DES MARCHÉS DE L'INFORMATIQUE EN NUAGE
CtrName13 = GUARDRAIL 13: PLANIFIER LA CONTINUITÉ

# Global
isCompliant = Conforme.
isNotCompliant = Non conforme.

# Guardrail #1
MSEntIDLicense = Type de licence Microsoft Entra ID
mfaEnabledFor =  L'authentication MFA ne devrait pas être activée pour le compte brise-glace: {0} 
mfaDisabledFor =  L'authentication MFA n'est pas activée pour {0} 
gaAccntsMFACheck = AMF et compte pour des comptes d'administrateur général

globalAdminAccntsSurplus = Il doit y avoir cinq comptes d'administrateur général ou moins.
globalAdminAccntsMinimum = Il n'y a pas assez de comptes d'administrateur général. Il doit y avoir au moins deux, mais pas plus de cinq comptes d'administrateur général actifs.
allGAUserHaveMFA = Tous les comptes natifs d'administrateur général Azure ont été identifiés et sécurisés à l'aide d'au moins deux méthodes d'authentification.
gaUserMisconfiguredMFA = Certains comptes natifs d'administrateur général Azure (un ou plusieurs) n'ont pas correctement configurés l'authentification multifacteur : {0}

alertsMonitor = Alertes pour signaler l'utilisation abusive et les activités suspectes
signInlogsNotCollected = Les journaux de connexion « SignInLogs » ne sont actuellement pas activés. Les « SignInLogs » doivent être activés pour surveiller et enregistrer les activités de connexion des utilisateurs dans l'environnement.
auditlogsNotCollected = Les journaux d'audit « AuditLogs » ne sont actuellement pas activés. Les « AuditLogs » doivent être activés pour capturer et enregistrer tous les événements d'audit significatifs dans l'environnement.
noAlertRules = Aucune règle d'alerte n'a été trouvée pour les journaux de connexion « SignInLogs » ou les journaux d'audit « AuditLogs ». Assurez-vous que des règles d'alerte sont créées et configurées pour surveiller ces journaux à la recherche d'activités suspectes.
noActionGroupsForBGaccts = Aucun groupe d'action n'a été identifié pour les activités de connexion au compte de bris de verre. Les groupes d'action doivent être configurés pour recevoir des alertes en cas de tentatives de connexion au compte de bris de verre.
noActionGroupsForAuditLogs = Aucun groupe d'action n'a été trouvé pour les modifications et les mises à jour de la politique d'accès conditionnel. Des groupes d'action doivent être créés pour recevoir des alertes pour les modifications et les mises à jour de la politique d'accès conditionnel.
has context menu
noActionGroups = Aucun groupe d'action n'a été configuré pour le groupe de ressources « {0} ». Assurez-vous que les groupes d'action sont configurés pour recevoir des alertes pour les activités surveillées du groupe de ressources correspondant.
compliantAlerts = Les alertes pour les comptes de bris de verre et les journaux d'audit « AuditLogs » sont conformes. Les groupes d'action appropriés ont été configurés et reçoivent correctement des alertes pour chaque activité surveillée.
noAlertRuleforBGaccts = Créez une alerte pour les comptes de bris de verre en utilisant « SignInLogs ». Il manque une des alertes requises.
noAlertRuleforCaps = Créez une alerte pour les modifications et les mises à jour de la politique d'accès conditionnel en utilisant « AuditLogs ». Il manque une des alertes requises.

allCloudUserAccountsMFACheck = Tous les comptes d'utilisateurs infonuagiques stratégie d'accès conditionnel AMF
allUserAccountsMFACheck = Vérification de l'AMF de tous les comptes d'utilisateurs infonuagiques
allUserHaveMFA = Tous les comptes d'utilisateurs natifs ont 2+ méthodes d'authentification.
userMisconfiguredMFA = Un ou plusieurs comptes d'utilisateurs natifs n'ont pas été configuré(s) correctement pour l'AMF: {0}

retentionNotMet = Le {0} identifié ne répond pas aux exigences de conservation des données.
readOnlyLaw = Il manque un verrou en lecture seule pour l'espace de travail {0} [Log Analytics Workspace (LAW)] identifié. Ajoutez le verrou en lecture seule pour éviter des suppressions accidentelles.
nonCompliantLaw = Le LAW {0} identifié ne correspond pas au fichier config.json.
logsNotCollected = Tous les journaux requis ne sont pas collectés.
gcEventLogging = Vérification de la journalisation des événements du GC du compte utilisateur
gcEventLoggingCompliantComment = Les journaux sont recueillis, stockés et conservés pour répondre aux exigences de ce contrôle.

dedicatedAdminAccountsCheck = Comptes d'utilisateurs dédiés pour l'administration
invalidUserFile = Mettez à jour le fichier {0} et répertoriez les noms principaux d'utilisateurs (UPN) de rôles à privilèges élevés et leurs UPN de rôle régulier.
invalidFileHeader = Mettez à jour les en-têtes du fichier {0} et répertoriez les noms principaux d'utilisateurs (UPN) de rôles à privilèges élevés et leurs UPN de rôle régulier.
dedicatedAdminAccNotExist = Il y a des utilisateurs privilégiés identifiés sans rôle hautement privilégié. Examinez les attributions de rôles « Administrateur général » et « Administrateur de rôle privilégié » dans l'environnement et assurez-vous qu'il existe des comptes d'utilisateurs dédiés pour les rôles hautement privilégiés.
regAccHasHProle = Il y a des utilisateurs non privilégiés identifiés avec un rôle hautement privilégié. Examinez les attributions de rôles « Administrateur général » et « Administrateur de rôle privilégié » dans l'environnement et assurez-vous qu'il existe des comptes d'utilisateurs dédiés pour les rôles hautement privilégiés.
dedicatedAccExist = Tous les administrateurs infonuagiques utilisent des comptes dédiés pour des rôles hautement privilégiés.
bgAccExistInUPNlist = Des noms principaux d'utilisateurs (UPN) de bris de verre existent dans le fichier de .csv téléchargé. Examinez les comptes d'utilisateurs .csv fichier et supprimez les UPN du compte bris de verre.
hpAccNotGA = Un ou plusieurs administrateurs hautement privilégiés identifiés dans le fichier .csv n'utilisent pas activement leurs attributions de rôle d'administrateur général pour le moment. Confirmez que ces utilisateurs disposent d'une attribution d'administrateur général éligible.
dupHPAccount = Examinez les noms d'utilisateur principaux [User Principal Names (UPNs)] de compte à privilèges élevés fournis pour tout doublon. Supprimez tous les UPN, qui sont répétés.
dupRegAccount = Examinez les noms d'utilisateur principaux [User Principal Names (UPNs)] de compte réguliers fournis pour tout doublon. Supprimez tous les UPN, qui sont répétés.
missingHPaccUPN = Données manquantes dans la colonne « HP_admin_account_UPN ». Veuillez vous assurer que cette colonne est remplie avant de continuer.
missingRegAccUPN = Données manquantes dans la colonne « regular_account_UPN ». Veuillez vous assurer que cette colonne est remplie avant de continue.

# GuardRail #2
MSEntIDLicenseTypeFound = Type de licence Microsoft Entra ID trouvé 
MSEntIDLicenseTypeNotFound = Type de licence requis Microsoft Entra ID non trouvé
accountNotDeleted = Ce compte d'utilisateur a été supprimé mais n'a pas encore été SUPPRIMÉ DÉFINITIVEMENT d'Azure Microsoft Entra ID
MSEntIDDeletedUser = Utilisateur Microsoft Entra ID Supprimé
MSEntIDDisabledUsers = Utilisateur Microsoft Entra ID désactivé
apiError = Erreur API
apiErrorMitigation = Vérifiez l'existence des utilisateurs ou les permissions de l'application.
compliantComment = Aucun utilisateur non synchronisé ou désactivé trouvé

mitigationCommands = Vérifiez si les utilisateurs trouvés sont obsolètes. 
noncompliantComment = Nombre d'utilisateurs non-conformes {0}. 
noncompliantUsers = Les utilisateurs suivants sont désactivés et ne sont pas synchronisés avec Microsoft Entra ID: - 

removeDeletedAccount = Supprimez définitivement les comptes supprimés
removeDeprecatedAccount = Supprimez les comptes obsolètes

privilegedAccountManagementPlanLifecycle = Plan de gestion des comptes privilégiés (Cycle de vie de la gestion des comptes)
privilegedAccountManagementPlanLPRoleAssignment = Plan de gestion des comptes privilégiés (Attribution de rôle aux privilèges minimum)

onlineAttackCounterMeasures = Vérification de mesures pour contrer les attaques en ligne: Verrouillage et listes de mots de passe interdits
onlineAttackNonCompliantC1 = Le seuil de verrouillage de compte ne respecte pas l'Orientation sur les mots de passe du GC.
onlineAttackNonCompliantC2 = La liste des mots de passe interdits n'a pas été configurée dans cet environnement. Examinez l'Orientation sur les mots de passe du GC.
onlineAttackIsCompliant = Le seuil de verrouillage de compte et la liste des mots de passe interdits répondent à l'Orientation sur les mots de passe du GC.
onlineAttackNonCompliantC1C2 = Ni le verrouillage de compte ni la liste des mots de passe interdits ne répondent à l'Orientation sur les mots de passe du GC. Examinez et corrigez.

noGuestAccounts = Il n'y a présentement aucun compte d'utilisateur invité dans votre environnement locataire.
guestAccountsNoPermission = Il y a des comptes d'utilisateurs invités dans l'environnement locataire et ils n'ont aucune permission dans le(s) abonnement(s) Azure du locataire.
guestAssigned = Ce compte d'utilisateur invité a une attribution de rôle dans le(s) abonnement(s) Azure du locataire.
guestNotAssigned = Ce compte d'utilisateur invité n'a pas d'attribution de rôle dans les abonnement(s) Azure du locataire.
existingGuestAccounts = Comptes d'utilisateurs invités existants
existingGuestAccountsComment = Examinez et validez la liste fournie des comptes d'utilisateurs invités. Supprimez les comptes d'utilisateurs invités selon les procédures et les politiques ministérielles, au besoin.

guestAccountsNoPrivilegedPermission =  Il existe des comptes d'utilisateurs invités dans l'environnement locataire et ils ne disposent d'aucune autorisation considérée comme « privilégiée » au niveau de l'abonnement.
existingPrivilegedGuestAccounts = Comptes d'utilisateurs invités privilégiés
existingPrivilegedGuestAccountsComment = Examinez et validez la liste fournie des comptes d'utilisateurs invités privilégiés. Supprimez les comptes d'utilisateurs invités privilégiés selon les procédures et les politiques de votre ministère, au besoin.
guestHasPrivilegedRole = Ce compte d'utilisateur invité a un ou plusieurs rôles privilégiés.

accManagementUserGroupsCheck = Gestion des comptes : Groupes d'utilisateurs
userCountGroupNoMatch = Tous les utilisateurs n'ont pas été assignés à un groupe d'utilisateurs privilégiés ou non privilégiés.
noCAPforAnyGroups = Aucune des politiques d'accès conditionnel ne fait référence à l'un de vos groupes d'utilisateurs (privilégiés ou non privilégiés).
userCountOne = Il n'y a seulement un utilisateur dans l'environnement. Des groupes d'utilisateurs ne sont pas nécessaires.
userGroupsMany =  Le nombre de groupes d'utilisateurs est insuffisant par rapport au nombre actuel d'utilisateurs. Au moins 2 groupes d'utilisateurs sont nécessaires.
reqPolicyUserGroupExists = Tous les utilisateurs ont été assignés à un groupe d'utilisateurs et au moins une politique d'accès conditionnel fait référence à un groupe d'utilisateurs pour le contrôle d'accès.

riskBasedConditionalPolicy = Mécanismes d'authentification : politiques d'accès conditionnel basées sur les risques
nonCompliantC1= Configurez la politique d'accès conditionnel pour forcer les changements de mot de passe en fonction du risque utilisateur.
nonCompliantC2= Configurez la politique d'accès conditionnel pour empêcher les connexions à partir des emplacements nommés non approuvés.
nonCompliantC1C2 = Configurez les politiques d'accès conditionnel décrites dans les conseils de remédiation.
compliantC1C2 = Les deux politiques d'accès conditionnel ont été configurées.

automatedRoleForUsers = Révisions automatisées des rôles : Attributions de rôles pour les utilisateurs et les administrateurs généraux
noAutomatedAccessReview = L'environnement n'a pas été intégré aux révisions automatisées de MS Access « MS Access Reviews ». Assurez-vous que l'environnement utilise les fonctionnalités de « Microsoft Entra Identity », incluant les révisions d'accès.
noInProgressAccessReview = L'environnement a au moins une révision d'accès de rôle planifiée pour les administrateurs généraux ou un autre rôle intégré Azure. Par contre, la révision d'accès a été identifiée comme « terminée » ou « non commencée ». Créez une nouvelle révision d'accès d'administrateur général/rôle intégré Azure pour qu'elle se reproduise et soit « en cours ».
noScheduledUserAccessReview = L'environnement n'a aucune révision d'accès de rôle planifiée créée pour les utilisateurs ou les groupes. Créez une révision d'accès pour l'attribution de rôle d'administrateur général et/ou un autre rôle intégré à Azure.
compliantRecurrenceReviews = Les révisions d'accès existantes répondent aux exigences du contrôle.
nonCompliantRecurrenceReviews = Une ou plusieurs révisions d'accès existantes ne répondent pas aux exigences de récurrence du contrôle. Assurez-vous que la révision automatisée est « en cours » et planifiée pour se reproduire.

automatedRoleForGuests = Révisions automatisées des utilisateurs invités : Attributions de rôles et exigences d'accès
noInProgressGuestAccessReview = L'environnement a au moins une révision d'accès planifiée pour les utilisateurs invités. Par contre, la révision d'accès a été identifiée comme « terminée » ou « non démarrée ». Créez une nouvelle révision d'accès invité planifiée pour se reproduire et soit « en cours ».
noScheduledGuestAccessReview = L'environnement n'a aucune révision d'accès d'invité planifiée. Configurez une révision d'utilisateur invité pour tous les groupes d'utilisateurs.
compliantRecurrenceGuestReviews = Les révision d'accès d'invité existantes répondent aux exigences requises pour le contrôle.


# GuardRail #3
noCompliantPoliciesfound=Aucune stratégie conforme n'a été trouvée. Les politiques doivent avoir un emplacement unique et cet emplacement doit être réservé au Canada.
allPoliciesAreCompliant=Toutes les politiques sont conformes.
adminAccessConditionalPolicy = Restrictions d'accès administrateur appliquées - gestion des appareils/emplacements approuvés
noLocationsCompliant=Aucun endroit n'a seulement le Canada en eux.
consoleAccessConditionalPolicy = Stratégie d'accès conditionnel pour l'accès à la console.

mfaRequiredForAllUsers = Authentification multifacteur requise pour tous les utilisateurs par accès conditionnel
noMFAPolicyForAllUsers = Aucune stratégie d'accès conditionnel nécessitant MFA pour tous les utilisateurs et applications n'a été trouvée. Une politique d'accès conditionnel répondant aux exigences suivantes doit être configurée: 1. state =  'enabled'; 2. includedUsers = 'All'; 3. includedApplications = 'All'; 4. grantControls.builtInControls contains 'mfa'; 5. clientAppTypes contains 'all'; 6. userRiskLevels = @(); 7. signInRiskLevels = @(); 8. platforms = null; 9. locations = null; 10. devices = null; 11. clientApplications = null
noDeviceFilterPolicies = Une politique d'accès conditionnel requise est manquante. Au moins une politique doit avoir des filtres d'appareil activés avec des ressources cibles, des rôles d'administrateur inclus et activés.
noLocationFilterPolicies = Une politique d'accès conditionnel requise est manquante. Au moins une politique doit vérifier les emplacements nommés/approuvés avec des rôles d'administrateur inclus et activés.
hasRequiredPolicies = Les politiques d'accès conditionnel requises pour l'accès administrateur existent.
noCompliantPoliciesAdmin = Aucune politique conforme n'a été trouvée pour les filtres d'appareils et les emplacements nommés/approuvés. Veuillez vous assurer qu'il existe au moins une politique pour chacun. Une pour les filtres d'appareil avec une ressource cible et l'autre pour les emplacements nommés/approuvés.


# GuardRail #4
monitorAccount = Surveiller la création de compte
checkUserExistsError = L'appel API a retourné l'erreur {0}. Veuillez vérifier si l'utilisateur existe.
checkUserExists = Veuillez vérifier si l'utilisateur existe.
ServicePrincipalNameHasNoReaderRole = SPN n'a pas de rôle de lecteur sur le groupe de gestion ROOT.
ServicePrincipalNameHasReaderRole = SPN a le rôle de lecteur sur le groupe de gestion ROOT.
ServicePrincipalNameHasNoMarketPlaceAdminRole = SPN n'a pas de rôle d'administrateur de Marketplace.
ServicePrincipalNameHasMarketPlaceAdminRole = SPN a pas le rôle d'administrateur de Marketplace.
NoSPN = SPN n'existe pas. 
SPNCredentialsCompliance = Statut de conformité des clés SPN
SPNSingleValidCredential = SPN a une seule clé valide. {0}
SPNMultipleValidCredentials = SPN a plusieurs clés valides. {0}
SPNNoValidCredentials = SPN n'a pas de clés valides. {0}

FinOpsToolStatus = Statut de l'outil FinOps
SPNNotExist = Le principal de service 'CloudabilityUtilizationDataCollector' n'existe pas.
SPNIncorrectPermissions = Le principal de service n'a pas le rôle de Lecteur requis.
SPNIncorrectRoles = Le principal de service n'a pas les rôles requis d'Administrateur d'application cloud et de Lecteur de rapports.
FinOpsToolCompliant = L'outil FinOps est conforme à toutes les exigences.
FinOpsToolNonCompliant = L'outil FinOps n'est pas conforme. Raisons: {0}

# GuardRail #5
pbmmCompliance = Conformité PBMMPolicy
policyNotAssigned = La politique ou l'initiative n'est pas affectée au {0}
excludeFromScope = {0} est exclu de la portée de l'affectation

policyNotAssignedRootMG = La politique ou l'initiative n'est pas affectée aux groupes de gestion racine
rootMGExcluded = Ce groupe de gestion racine est exclu de la portée de l'affectation
subscription  = abonnement
managementGroup = Groupes de gestion
notAllowedLocation =  L'emplacement est en dehors des emplacements autorisés. 
allowLocationPolicy = Politique de localisation autorisée
dataAtRest = PROTECTION DES DONNÉES-AU-REPOS


# GuardRail #6
pbmmApplied = L'initiative PBMM a été appliquée.
pbmmNotApplied = L'initiative PBMM n'a pas été appliquée. Appliquez l'initiative PBMM.
reqPolicyApplied = Toutes les politiques requises sont appliquées.
reqPolicyNotApplied = L'initiative PBMM manque une ou quelques-unes des politiques sélectionnées pour l'évaluation. Consultez le Livre de jeu de correction pour plus d'informations.
grExemptionFound = Supprimez l'exemption trouvée pour {0}. 
grExemptionNotFound = Les définitions des politiques requises ne sont pas exemptées.
noResource = Aucune ressource applicable à l'évaluation des politiques de l'initiative PBMM sélectionnée.
allCompliantResources = Toutes les ressources sont conformes.
allNonCompliantResources = Toutes les ressources ne sont pas conformes.
hasNonComplianceResource = {0} des ressources {1} applicables ne sont pas conformes aux politiques sélectionnées. Suivez les recommandations de correction de Microsoft.


# GuardRail #7

appGatewayCertValidity = Validité du certificat : Passerelle d'application
noSslListenersFound = Aucun écouteur Secure Socket Layer (SSL) trouvé/configuré pour la passerelle d'application : {0}. 
expiredCertificateFound = Certificat expiré trouvé pour l'écouteur '{0}' dans la passerelle d'application '{1}'. 
unapprovedCAFound = Autorité de certification (AC) non approuvée trouvée pour l'écouteur '{0}' dans la passerelle d'application '{1}'. Émetteur : {2}. 
unableToProcessCertData = Incapable de traiter les données de certificat pour l'écouteur '{0}' dans la passerelle d'application '{1}'. Erreur : {2}. 
unableToRetrieveCertData = Incapable de récupérer les données de certificat pour l'écouteur '{0}' dans la passerelle d'application '{1}'. 
noHttpsBackendSettingsFound = Aucun paramètre principal HTTPS n'a été trouvé/configuré pour la passerelle d'application : {0}. 
manualTrustedRootCertsFound = Certificats racines de confiance manuels trouvés pour la passerelle d'application '{0}', paramètre principal '{1}'. 
allBackendSettingsUseWellKnownCA = Tous les paramètres principaux de la passerelle d'application '{0}' utilisent des certificats d'autorité de certification (AC) bien connus. 
noAppGatewayFound = Aucune passerelle d'application trouvée dans aucun abonnement.
allCertificatesValid = Tous les certificats sont valides et provenant d'autorités de certification (AC) approuvées. 
approvedCAFileFound = Approved Certificate Authority (CA) file '{0}' not found in container '{1}' of storage account '{2}'. Unable to verify certificate authorities.
approvedCAFileNotFound = Le fichier des Autorités de certification (AC) approuvées '{0}' n'a pas été trouvé dans le conteneur '{1}' du compte de stockage '{2}'. Incapable de vérifier les autorités de certification.
appServiceHttpsConfig = « Azure App Service » : Configuration d'application HTTPS
dataInTransit = PROTECTION DES DONNÉES-EN-TRANSIT

storageAccTLS12 = Comptes de stockage TLS 1.2
storageAccValidTLS = Tous les comptes de stockage utilisent TLS1.2 ou version ultérieure. 
storageAccNotValidTLS = Un ou plusieurs comptes de stockage utilisent TLS1.1 ou une version antérieure. Mettez à jour les comptes de stockage vers TLS1.2 ou version ultérieure.

functionAppHttpsConfig = « Azure Functions » : Configuration d'application HTTPS

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
subnetExcludedByTag = Subnet '{0}' is excluded from compliance because VNET '{1}' has tag '{2}' with a value of 'true'
subnetExcludedByReservedName = Subnet '{0}' is excluded from compliance because its name is in the reserved subnet list '{1}'
subnetExcludedByVNET = Subnet '{0}' is not being checked for compliance because the VNET '{1}' has tag '{2}' with a value of 'true'
networkDiagram = Diagramme d'architecture réseau
highLevelDesign = Documentation de Conception de haut niveau
noSubnets = Aucun sous-réseau n'est présent.
cloudInfrastructureDeployGuide = Guide de déploiement de l'infrastructure cloud ou détails de la zone d'atterrissage applicable

# GuardRail #9
ddosEnabled = Protection DDos activée. 
ddosNotEnabled = Protection DDos non activée.

networkWatcherEnabled=Network Watcher existe pour la région '{0}'
networkWatcherNotEnabled=Network Watcher non activé pour la région '{0}'
noVNets = Aucun VNet n'est présent.
vnetDDosConfig = Configuration DDos VNet
vnetExcludedByParameter = VNet '{0}' is excluded from compliance because it is in the excluded VNet list '{1}'
vnetExcludedByTag = VNet '{0}' is excluded from compliance because it has tag '{1}' with a value of 'true'
networkWatcherConfig = Configuration de Network Watcher
networkWatcherConfigNoRegions = En raison d'aucun VNETs ou de tous les VNETs étant exclus, il n'y a aucune région pour vérifier la configuration de Network Watcher
noFirewallOrGateway = Cet abonnement n'a pas de pare-feu ni de passerelle d'application en utilisation.
noFirewallOrGatewayCompliant = Cet abonnement est conforme en raison de la présence d'un pare-feu ou d'une passerelle d'application (avec un pare-feu d'application Web) dans un autre abonnement. Assurez-vous que cet abonnement route les adresses IP sources correctement.
wAFNotEnabled = La passerelle d'application attribuée n'a pas de pares-feux d'application Web (WAF) configuré. Activez un WAF sur la passerelle d'application.
firewallFound = Il y a un {0} associé à cet abonnement.
wAFEnabled = Il y a une passerelle d'application associée à cet abonnement avec les configurations appropriées.
networkSecurityTools = Outils utilisés pour limiter l'accès aux adresses IP sources autorisées

# GuardRail #10
cbsSubDoesntExist = L'abonnement CBS n'existe pas
cbcSensorsdontExist = Les capteurs CBC attendus n'existent pas
cbssMitigation = Vérifiez l'abonnement fourni: {0} ou vérifiez l'existence de la solution CBS dans l'abonnement fourni.
cbssCompliant = Ressources trouvées dans ces abonnements: 
MOUwithCCCS = Attestation que le protocole d'entente avec CCCS est reconnu.

# GuardRail #11
serviceHealthAlerts = Alertes de santé du service et vérification des événements

createLAW = Veuillez créer un espace de travail d'analyse de journaux conformément aux directives.
connectAutoAcct = Veuillez connecter un compte d'automatisation à l'espace de travail fourni.
setRetention60Days = Définir la rétention de l'espace de travail sur au moins 90 jours pour l'espace de travail: 
setRetention730Days = Définir la rétention de l'espace de travail à 730 jours pour l'espace de travail: 
addActivityLogs = Veuillez ajouter la solution Activity Logs à l'espace de travail: 
addUpdatesAndAntiMalware = Veuillez ajouter à la fois la solution Mises à jour et Anti-Malware à l'espace de travail: 
configTenantDiag = Veuillez configurer les diagnostics de locataire pour qu'ils pointent vers l'espace de travail fourni: 
addAuditAndSignInsLogs = Veuillez activer les journaux d'audit et SignInLogs dans les paramètres de Tenant Dianostics.

logsAndMonitoringCompliantForDefender = Les journaux et la surveillance sont conformes pour Defender.
createHealthLAW = Veuillez créer un espace de travail pour la surveillance de la santé conformément aux directives de Guardrails.
enableAgentHealthSolution = Veuillez activer la solution d'évaluation de l'état de santé de l'agent dans l'espace de travail.
lawEnvironmentCompliant = L'environnement est conforme.

setSecurityContact = Veuillez définir un contact de sécurité pour Defender for Cloud dans l'abonnement. {0}
setDfCToStandard = Veuillez définir les forfaits Defender pour le cloud sur Standard. ({0})

noServiceHealthActionGroups = Il manque un groupe d'action pour les alertes de santé du service « Service Health Alerts » associées à l'abonnement : {0}
NotAllSubsHaveAlerts = Les alertes de santé du service « Service Health Alerts » ne sont pas activées pour tous les abonnements. Assurez-vous que les alertes d'état du service sont configurées sur tous les abonnements et que le groupe d'action associé à l'alerte a au moins deux contacts différents.
EventTypeMissingForAlert = L'alerte manque un type d'événement requis (problème de service, avis de santé ou avis de sécurité) « Service Issue, Health Advisory or Security Advisory » pour l'abonnement : {0}
noServiceHealthAlerts = Ne peut pas récupérer les alertes configurées pour l'abonnement : "{0}". Assurez-vous que les alertes de santé du service « Service Health Alerts » sont configurées sur tous les abonnements et que le groupe d'action associé à l'alerte a au moins deux contacts différents.
nonCompliantActionGroups = Toutes les alertes de santé du service « Service Health Alerts » sont configurées sur tous les abonnements. Par contre, tous les groupes d'action associés ne sont pas configurés correctement. Au moins deux adresses de courriel ou propriétaires d'abonnement sont requis pour le groupe d'action.
compliantServiceHealthAlerts = Les alertes de santé du service « Service Health Alerts » sont configurées sur tous les abonnements et le groupe d'action associé à l'alerte a au moins deux contacts différents.

monitoringChecklist = Liste de vérification de surveillance : Cas d'utilisation

msDefenderChecks = Alertes infonuagiques et vérification des événements de Microsoft Defender
NotAllSubsHaveDefenderPlans = Le(s) abonnement(s) suivant(s) n'a/n'ont pas de plan MS Defender : {0} . Activez la surveillance MS Defender pour tous les abonnements.
errorRetrievingNotifications = Les notifications d'alerte MS Defender pour le ou les abonnements ne sont pas configurées. Assurez-vous qu'elles correspondent aux exigences du guide de Remédiation.
EmailsOrOwnerNotConfigured = Les notifications d'alerte MS Defender pour l'abonnement n'incluent pas au moins deux adresses courriel ou propriétaires d'abonnement. Configurez les pour s'assurer que les alertes sont envoyées correctement
AlertNotificationNotConfigured = Les notifications d'alerte MS Defender sont incorrectes. Définissez la gravité à Moyen ou Faible et passez en revue le Guide de Remédiation.
AttackPathNotifictionNotConfigured = Les alertes MS Defender doivent inclure des notifications de chemin d'attaque. Assurez-vous qu'elles sont configurées pour les alertes de chaque abonnement conformément aux instructions du Guide de Remédiation
DefenderCompliant = MS Defender pour l'infonuagique est activé pour tous les abonnements et les notifications par courriel sont correctement configurées.


# GuardRail #12
mktPlaceCreation = Création Place de marché
mktPlaceCreatedEnabled = Le marché privé a été créé et activé.
mktPlaceCreatedNotEnabled = Le marché privé a été créé, mais n'est pas activé.
mktPlaceNotCreated = Le marché privé n'a pas été créé.
enableMktPlace = Activer Azure Private MarketPlace selon: https://docs.microsoft.com/en-us/marketplace/create-manage-private-azure-marketplace-new

# Guardrail #13
bgMSEntID = Attribution Bris de Verre Microsoft Entra ID P2
bgProcedure = Procédure de compte de bris de verre
bgCreation = Création de compte Brise Glace

bgAccountOwnerContact = Coordonnées des titulaires de compte Brise Glace
bgAccountsCompliance = Statut de conformité du premier compte brise-glace = {0}, Statut de conformité du deuxième compte brise-glace = {1}
bgAccountsCompliance2 = Les deux comptes sont identiques, veuillez vérifier le fichier config.json
bgAuthenticationMeth =  Méthodes d'authentification 
firstBgAccount = Premier compte brise-glace
secondBgAccount = Deuxième compte brise-glace
bgNoValidLicenseAssigned = Aucune licence Microsoft Entra ID P2 assignée au 
bgValidLicenseAssigned =  a une licence Microsoft Entra ID P2 valide
bgAccountHasManager = Le compte BG {0} a un responsable
bgAccountNoManager =  Le compte BG {0} n'a pas de gestionnaire 
bgBothHaveManager =  Les deux comptes brise-glace ont un gestionnaire

bgValidSignature = Signatures et approbations valides pour la procédure de compte de bris de verre
bgAccountTesting = Cadence des tests des comptes de bris de verre
bgAccountNotExist = Un ou les deux noms d'utilisateur principal (UPN) du compte de bris de verre fournis n'existent pas dans l'environnement. Vérifiez l'exactitude des UPN du compte de bris de verre fournis.
bgAccountLoginNotValid = La dernière connexion aux comptes de bris de verre fournis est plus qu'un an. Assurez-vous d'effectuer des tests réguliers de la procédure du compte de bris de verre et du processus de connexion.
bgAccountLoginValid = La dernière connexion pour les comptes de bris de verre est moins d'un an. Assurez-vous d'effectuer des tests réguliers de la procédure de bris de verre et du processus de connexion.

# GR-Common
procedureFileFound = Conforme. Le fichier requis a été téléchargé pour examen par les évaluateurs de Conformité à la sécurité infonuagique. « {0} » trouvé.
procedureFileNotFound = Non conforme. N'a pas trouvé « {0} » créer et télécharger le fichier approprié dans le conteneur « {1} » dans le compte de stockage « {2} » pour devenir conforme.
procedureFileNotFoundWithCorrectExtension = Non conforme. Fichier « nomdeFichier » « fileName » '{0}' requis trouvé. Par contre, l'extension n'est pas prise en charge. Créez et téléchargez le fichier approprié dans le conteneur « {1} » dans le compte de stockage « {2} » pour devenir conforme.

procedureFileDataInvalid = Le(s) fichier(s) d'administrateur général contiennent des noms principaux d'utilisateur non valides. Assurez-vous que les noms principaux d'utilisateur commencent par un trait d'union et tapez chacun d'eux sur une nouvelle ligne.
globalAdminFileFound = Fichier {0} trouvé dans le conteneur.
globalAdminFileNotFound = N'a pas trouvé de document pour {0}, veuillez créer et télécharger un fichier avec le nom '{1}' dans le conteneur '{2}' sur le compte de stockage '{3}' pour confirmer que vous avez terminé l'élément dans le contrôle.
globalAdminFileEmpty =  Fichier vide {0} trouvé dans le conteneur.
globalAdminNotExist = Comptes d'administrateur général non trouvés ou déclarés dans le fichier {0}.
globalAdminMFAPassAndMin2Accnts = Deux comptes d'administrateur général ou plus ont été identifiés et l'authentification multifacteur est activée pour chacun d'eux.
globalAdminMinAccnts = Il doit y avoir au moins deux comptes d'administrateur général.

globalAdminAccntsMFADisabled1 = Le compte suivant: {0} n'a pas d'authentification multifacteur activée
globalAdminAccntsMFADisabled2 =  Les comptes suivants: {0} n'ont pas d'authentification multifacteur activée 
globalAdminAccntsMFADisabled3 = Aucun des comptes d'administrateur général n'a l'authentification multifacteur activée 

'@
