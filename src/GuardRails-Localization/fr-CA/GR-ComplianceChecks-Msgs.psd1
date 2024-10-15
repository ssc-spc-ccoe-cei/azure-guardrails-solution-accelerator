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
dedicatedAdminAccNotExist = Il y a des utilisateurs privilégiés identifiés sans rôle hautement privilégié. Examinez les attributions de rôles « Administrateur général » et « Administrateur de rôle privilégié » dans l'environnement et assurez-vous qu'il existe des comptes d'utilisateurs dédiés pour les rôles hautement privilégiés.
regAccHasHProle = Il y a des utilisateurs non privilégiés identifiés avec un rôle hautement privilégié. Examinez les attributions de rôles « Administrateur général » et « Administrateur de rôle privilégié » dans l'environnement et assurez-vous qu'il existe des comptes d'utilisateurs dédiés pour les rôles hautement privilégiés.
dedicatedAccExist = Tous les administrateurs infonuagiques utilisent des comptes dédiés pour des rôles hautement privilégiés.
bgAccExistInUPNlist = Des noms principaux d'utilisateurs (UPN) de bris de verre existent dans le fichier de .csv téléchargé. Examinez les comptes d'utilisateurs .csv fichier et supprimez les UPN du compte bris de verre.
hpAccNotGA = Un ou plusieurs administrateurs hautement privilégiés identifiés dans le fichier .csv n'utilisent pas activement leurs attributions de rôle d'administrateur général pour le moment. Confirmez que ces utilisateurs disposent d'une attribution d'administrateur général éligible.

# GuardRail #2
MSEntIDLicenseTypeFound = Type de licence Microsoft Entra ID trouvé 
MSEntIDLicenseTypeNotFound = Type de licence requis Microsoft Entra ID non trouvé
accountNotDeleted = Ce compte d'utilisateur a été supprimé mais n'a pas encore été SUPPRIMÉ DÉFINITIVEMENT d'Azure Microsoft Entra ID
MSEntIDDeletedUser = Utilisateur Microsoft Entra ID Supprimé
MSEntIDDisabledUsers = Utilisateur Microsoft Entra ID désactivé
apiError = Erreur API
apiErrorMitigation = Vérifiez l'existence des utilisateurs ou les permissions de l'application.
compliantComment = Aucun utilisateur non synchronisé ou désactivé trouvé
gcPasswordGuidanceDoc = Document d'orientation sur les mots de passe du GC
mitigationCommands = Vérifiez si les utilisateurs trouvés sont obsolètes. 
noncompliantComment = Nombre d'utilisateurs non-conformes {0}. 
noncompliantUsers = Les utilisateurs suivants sont désactivés et ne sont pas synchronisés avec Microsoft Entra ID: - 
privilegedAccountManagementPlan = Plan de gestion des comptes privilégiés 
removeDeletedAccount = Supprimez définitivement les comptes supprimés
removeDeprecatedAccount = Supprimez les comptes obsolètes

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

# GuardRail #3
noCompliantPoliciesfound=Aucune stratégie conforme n'a été trouvée. Les politiques doivent avoir un emplacement unique et cet emplacement doit être réservé au Canada.
allPoliciesAreCompliant=Toutes les politiques sont conformes.
adminAccessConditionalPolicy = Restrictions d'accès administrateur appliquées - gestion des appareils/emplacements approuvés
noLocationsCompliant=Aucun endroit n'a seulement le Canada en eux.
consoleAccessConditionalPolicy = Stratégie d'accès conditionnel pour l'accès à la console.
authorizedProcessedByCSO = Accès Autorisé
mfaRequiredForAllUsers = Authentification multifacteur requise pour tous les utilisateurs par accès conditionnel
noMFAPolicyForAllUsers = Aucune stratégie d'accès conditionnel nécessitant MFA pour tous les utilisateurs et applications n'a été trouvée. Une politique d'accès conditionnel répondant aux exigences suivantes doit être configurée: 1. state =  'enabled'; 2. includedUsers = 'All'; 3. includedApplications = 'All'; 4. grantControls.builtInControls contains 'mfa'; 5. clientAppTypes contains 'all'; 6. userRiskLevels = @(); 7. signInRiskLevels = @(); 8. platforms = null; 9. locations = null; 10. devices = null; 11. clientApplications = null
noDeviceFilterPolicies = Une politique d'accès conditionnel requise est manquante. Au moins une politique doit avoir des filtres d'appareil activés avec des ressources cibles, des rôles d'administrateur inclus et activés.
noLocationFilterPolicies = Une politique d'accès conditionnel requise est manquante. Au moins une politique doit vérifier les emplacements nommés/approuvés avec des rôles d'administrateur inclus et activés.
hasRequiredPolicies = Les politiques d'accès conditionnel requises pour l'accès administrateur existent.
noCompliantPoliciesAdmin = Aucune politique conforme n'a été trouvée pour les filtres d'appareils et les emplacements nommés/approuvés. Veuillez vous assurer qu'il existe au moins une politique pour chacun. Une pour les filtres d'appareil avec une ressource cible et l'autre pour les emplacements nommés/approuvés.


riskBasedConditionalPolicy = Mécanismes d'authentification : politiques d'accès conditionnel basées sur les risques

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
CSPMEncryptedEmailConfirmation= Confirmacion d'email encrypté envoyé

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
dataInTransit = PROTECTION DES DONNÉES-EN-TRANSIT

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
hasNonComplianceResounce = {0} des ressources {1} applicables ne sont pas conformes aux politiques sélectionnées. Suivez les recommandations de correction de Microsoft.


# GuardRail #7
enableTLS12 = TLS 1.2+ est activé dans la mesure du possible pour sécuriser les données en transit

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
authSourceIPPolicyConfirm = Attestation que la politique IPs de la source d'authentification est respectée
ddosEnabled = Protection DDos activée. 
ddosNotEnabled = Protection DDos non activée.
limitPublicIPsPolicy = Attestation que la politique de limitation des IPs publiques est respectée.
networkBoundaryProtectionPolicy = Attestation que la politique de protection des limites du réseau est respectée.
networkWatcherEnabled=Network Watcher existe pour la région '{0}'
networkWatcherNotEnabled=Network Watcher non activé pour la région '{0}'
noVNets = Aucun VNet n'est présent.
vnetDDosConfig = Configuration DDos VNet
vnetExcludedByParameter = VNet '{0}' is excluded from compliance because it is in the excluded VNet list '{1}'
vnetExcludedByTag = VNet '{0}' is excluded from compliance because it has tag '{1}' with a value of 'true'
networkWatcherConfig = Configuration de Network Watcher
networkWatcherConfigNoRegions = En raison d'aucun VNETs ou de tous les VNETs étant exclus, il n'y a aucune région pour vérifier la configuration de Network Watcher

# GuardRail #10
cbsSubDoesntExist = L'abonnement CBS n'existe pas
cbcSensorsdontExist = Les capteurs CBC attendus n'existent pas
cbssMitigation = Vérifiez l'abonnement fourni: {0} ou vérifiez l'existence de la solution CBS dans l'abonnement fourni.
cbssCompliant = Ressources trouvées dans ces abonnements: 
MOUwithCCCS = Attestation que le protocole d'entente avec CCCS est reconnu.

# GuardRail #11
securityMonitoring = Surveillance de la sécurité
HealthMonitoring = Surveillance Santé
defenderMonitoring =Surveillance Defender
securityLAWNotFound = L'espace de travail Log Analytics spécifié pour la surveillance de la sécurité est introuvable.
lawRetentionSecDays = La rétention n'est pas définie sur {0} jours.
lawNoActivityLogs = WorkSpace n'est pas configuré pour ingérer les journaux d'activité.
lawSolutionNotFound = Les solutions requises ne sont pas présentes dans l'espace de travail Log Analytics.
lawNoAutoAcct = Aucun compte d'automatisation lié n'a été trouvé.
lawNoTenantDiag = Les paramètres de diagnostic des locataires ne pointent pas vers l'espace de travail d'analyse des journaux fourni.
lawMissingLogTypes = L'espace de travail est défini dans la configuration du locataire, mais tous les types de journaux requis ne sont pas activés (audit et connexion).
healthLAWNotFound = L'espace de travail Log Analytics spécifié pour la surveillance de la santé est introuvable.
lawRetentionHealthDays = La rétention n'est pas définie sur au moins {0} jours.
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
passwordNotificationsConfigured = Notifications activées
severityNotificationToEmailConfigured = Notifications de sévérité à un e-mail principal

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
bgAccountResponsibility = Responsabilité BV suit la procédure du ministère
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

# GR-Common
procedureFileFound = Conforme. Le fichier requis a été téléchargé pour examen par les évaluateurs de Conformité à la sécurité infonuagique. « {0} » trouvé.
procedureFileNotFound = Non conforme. N'a pas trouvé « {0} » créer et télécharger le fichier approprié dans le conteneur « {1} » dans le compte de stockage « {2} » pour devenir conforme.


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
