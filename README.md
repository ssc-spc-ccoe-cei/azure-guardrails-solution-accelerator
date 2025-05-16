# Azure Compliance as Code Solution (Guardrails Solution Accelerator) for Canadian Public Sector

## $${\color{Red} Warning \space : \space Beta \space Release \space 2.3.2 \space }$$
The current release (v2.3.2beta) available is undergoing final operations testing. It has passed all unit tests and integration testing but still requires a final quality assurance cycle.
 
As this is a beta release, please install with caution. You can still use version 2.3.1 in the interim. The beta tag will be removed once the final review is completed.
 
Thank you for your understanding.
___________________________________________________________________
## $${\color{Red}  }$$


----------------------------------------------------------------------

## Introduction

The purpose of this implementation is to help Canadian Public Sector departments and agencies to identify and remediate the [GC Cloud Guardrails](https://github.com/canada-ca/cloud-guardrails#gc-cloud-guardrails) to ensure ongoing compliance with the GC Cloud Guardrail policy validations.
 
## Project Background

The GC Cloud Guardrails are the minimum required security controls defined by Treasure Board Secretariat (TBS) to protect and secure data in order to maintain the security posture of Cloud environments. GC clients must implement the guardrails within the first 30 days of a Cloud account creation. The guardrails have been mapped on to six different Cloud usage profiles.

The implementation provides a starting point for project teams and was selected to achieve the following objectives:
* comply with the applicable mandatory procedures in the Directive on Security Management
* meet the requirements of the Direction on the Secure Use of Commercial Cloud Services: [Security Policy Implementation Notice (SPIN)](https://www.canada.ca/en/government/system/digital-government/policies-standards/spin.html)
* apply the Communications Security Establishment’s (CSE’s) Top 10 Security Actions
* align with Government of Canada Security Control Profile for Cloud-Based GC Services
* focus on the selection of security controls to those implemented in software components of information system solutions
* achieve threat protection objectives specified in the Information Technology Security Guidance (ITSG-33) generic Protected B Confidentiality, Medium Integrity, and Medium Availability (PBMM) profile and the Government of Canada Security Control Profile for Cloud-Based GC Services

The primary purpose of Compliance as Code (CaC) Guardrails automation is for effectively reporting the compliance data of GC Azure environments to TBS.

Compliance as Code (CaC) Guardrails Automation helps the Canadian Public Sector departments and agencies to identify and remediate the GC Cloud Guardrails to ensure ongoing compliance with the Guardrails requirements. The GC Cloud Guardrails requirements can be found in the Canadian Government’s public GitHub repository.

CaC Automation Objectives:

* develop automated processes for TBS GC guardrails monitoring and reporting
* automate the monitoring of customer compliance to mandatory cloud security guardrails (i.e., minimum required security controls to protect and secure data)
* expand compliance monitoring to additional guardrails & build compliancy dashboards [Infrastructure as a service (IaaS)/Platform as a service (PaaS)] to support reporting
* support the growing and evolving adoption of Cloud services within the GC
* strengthen and optimize existing Cloud security processes and services

## Architecture

Refer to gcxchange Azure Onboarding Presentation. https://gcxgce.sharepoint.com/teams/10001628

## Configuration and Installation
The Azure Installation Playbook can be found on gcxchange. https://gcxgce.sharepoint.com/teams/10001628

## How it works

The CaC solution has multiple modules. Each module verifies specific set of configurations in the environment and compares them with the validations [GC guardrails](https://github.com/canada-ca/cloud-guardrails#gc-cloud-guardrails) mandated by [Treasury Board Secretariat](https://www.canada.ca/en/treasury-board-secretariat.html) and [Shared Services Canada](https://www.canada.ca/en/shared-services.html). 

To understand what the module is monitoring, consult the Azure Remediation Playbook on gcxchange 
https://gcxgce.sharepoint.com/teams/10001628.

## Contributing

This project welcomes contributions and suggestions via GitHub’s issue/bug submission.

Note: If there are any questions related but do not involve a code bug or issue you can email SSC Cloud Security Compliance: [cloudsecuritycompliance-conformiteinfonuagiquesecurise@ssc-spc.gc.ca](mailto:cloudsecuritycompliance-conformiteinfonuagiquesecurise@ssc-spc.gc.ca).

Most contributions require you to agree to a Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com/.

Commits are not accepted to the main branch. You may do a Pull Request (PR) from a forked repository. You will not be able to push a branch directly. We also have two SSC reviewers required to review all PRs.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the Microsoft Open-Source Code of Conduct. For more information, refer to the Code of Conduct Frequently Asked Questions (FAQs) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Telemetry
Telemetry is set to false by default. If you wish to send usage data to Microsoft, you can set the “customerUsageAttribution.enabled” setting to “true” in “setup/IaC/modules/telemetry.json”. 

Microsoft can correlate these resources used to support the deployments. Microsoft collects this information to provide the best experiences with their products and to operate their business. The telemetry is collected through customer usage attribution. The data is collected and governed by Microsoft's privacy policies, located at https://www.microsoft.com/trustcenter.

Project Bicep collects telemetry in some scenarios as part of improving the product.

## License
All files except for Super-Linter in the repository are subject to the MIT license.

Super-Linter in this project is provided as an example for enabling source code linting capabilities. It is subjected to the license based on its repository.

## Trademark
This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft trademarks or logos is subject to and must follow Microsoft's Trademark & Brand Guidelines. Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship. Any use of third-party trademarks or logos are subject to those third party's policies.

## gcxchange
All documentation to support the solution can be found on gcxchange, including the Architecture, Installation Playbook, and Remediation Playbook.
https://gcxgce.sharepoint.com/teams/10001628

Note: If you have never used gcxchange, you will need to register first (Virtual Private Network (VPN) access is required for registration). Register for gcxchange at https://www.gcx-gce.gc.ca/

 
## Introduction
L’objectif de cette mise en œuvre est d’aider les ministères et agences du secteur public canadien à identifier et remédier les [Mesures de protection du nuage du GC](https://github.com/canada-ca/cloud-guardrails?tab=readme-ov-file#mesures-de-protection-du-nuage-du-gc) afin d’assurer la conformité continue aux validations de la Politique sur les mesures de sécurité infonuagique du GC.

## Contexte du projet 
Les mesures de sécurité infonuagique du GC sont les contrôles de sécurité minimaux requis définis par le Secrétariat du Conseil du trésor (SCT) pour protéger et sécuriser les données afin de maintenir la posture de sécurité des environnements infonuagiques. Les clients de GC doivent mettre en œuvre les mesures de sécurité dans les 30 premiers jours suivant la création du compte infonuagique. Les mesures de sécurité ont été mappés à six différents profils d’utilisation infonuagique. 

Cette mise en œuvre fournit un point de départ pour les équipes de projet et elles ont été sélectionnées pour atteindre les objectifs suivants :

* conformer aux procédures obligatoires applicables dans la Directive sur la gestion de la sécurité
* satisfaire aux exigences de la Directive sur l’utilisation sécurisée des services infonuagiques commerciaux : [Avis de mise en œuvre de la Politique sur la sécurité (AMOPS)](https://www.canada.ca/fr/gouvernement/systeme/gouvernement-numerique/politiques-normes/amops.html)
* appliquer les 10 principales mesures de sécurité du Centre de la sécurité des télécommunications (CST)
* aligner le profil de contrôle de sécurité du gouvernement du Canada avec les services infonuagiques du GC
* concentrer sur la sélection des contrôles de sécurité à ceux mis en œuvre dans les composants logiciels des solutions de systèmes d’information
* atteindre les objectifs de protection contre les menaces précisées dans le profil générique des Conseils en matière de sécurité des technologies de l’information (ITSG-33) Protégé B, intégrité moyenne et disponibilité moyenne (PBMM) et le profil de contrôle de sécurité du gouvernement du Canada pour les services infonuagiques du GC

L’objectif principal de l’automatisation des mesures de sécurité de Conformité en tant que code (CC) est de déclarer efficacement les données de conformité des environnements GC Azure au SCT.

L’automatisation des mesures de sécurité de Conformité en tant que code (CC) aide les ministères et agences du secteur public canadien à identifier et remédier les mesures de sécurité infonuagique du GC afin d’assurer la conformité continue aux exigences relatives aux mesures de sécurité. Les exigences relatives aux mesures de sécurité infonuagique du GC se trouvent dans le référentiel GitHub public du gouvernement canadien.

Objectifs d’automatisation de CC :
* développer des processus automatisés pour la surveillance et la production de rapports sur les mesures de sécurité infonuagique du SCT du GC
* automatiser la surveillance de la conformité des clients aux mesures de sécurité infonuagique obligatoires (c’est-à-dire les contrôles de sécurité minimum requis pour protéger et sécuriser les données).
* étendre la surveillance de la conformité à des mesures de sécurité supplémentaires et créer des tableaux de bord de conformité [Infrastructure en tant que service (IaaS)/Plateforme en tant que service (PaaS)] pour soutenir les rapports
*supporter l’adoption croissante et évolutive des services infonuagiques au sein du GC
* renforcer et optimiser les processus et services de sécurité infonuagique existants

## Architecture
Consultez la présentation d’intégration Azure à gcéchange. https://gcxgce.sharepoint.com/teams/10001628

## Configuration et Installation 
Le Livre de jeu d’installation Azure se trouve sur gcéchange. https://gcxgce.sharepoint.com/teams/10001628

## Comment ça fonctionne
La solution CC comporte plusieurs modules. Chaque module vérifie un ensemble précis de configuration dans l’environnement et les compare aux validations [Mesures de sécurité infonuagique](https://github.com/canada-ca/cloud-guardrails?tab=readme-ov-file#mesures-de-protection-du-nuage-du-gc) mandatées par le [Secrétariat du Conseil du Trésor](https://www.canada.ca/fr/secretariat-conseil-tresor.html) et [Services partagés Canada](https://www.canada.ca/fr/services-partages.html).

Pour comprendre ce que le module surveille, consultez le Livre de jeu de Remédiation Azure sur gcéchange
https://gcxgce.sharepoint.com/teams/10001628. 

## Contribuer
Ce projet accueille les contributions et les suggestions via la soumission de problème / bogue de GitHub.

Remarque : S’il y a des questions liées mais n’impliquent pas de bogue ou de problème de code, vous pouvez envoyer un courriel à Conformité à la sécurité infonuagique de SPC : [cloudsecuritycompliance-conformiteinfonuagiquesecurise@ssc-spc.gc.ca](mailto:cloudsecuritycompliance-conformiteinfonuagiquesecurise@ssc-spc.gc.ca).

La plupart des contributions exigent que vous acceptiez une entente de licence de contributeur « Contributor License Agreement (CLA) » déclarant que vous avez le droit de nous accorder les droits d’utiliser votre contribution, et que vous le faites réellement. Pour plus de détails, visitez https://cla.opensource.microsoft.com/.

Les « commits » ne sont pas acceptés à la branche principale. Vous pouvez effectuer une demande de tirage « pull request (PR) » à partir d’un référentiel fourché. Vous ne pourrez pas pousser une branche directement. Nous avons également deux examinateurs de SPC tenus d’examiner tous les PR.

Lorsque vous soumettez une PR, un robot « bot » CLA déterminera automatiquement si vous devez fournir un CLA et décorer la PR de manière appropriée (par exemple, vérification de l’état, commentaire). Il suffit de suivre les instructions fournies par le « bot ». Vous n’aurez besoin de le faire qu’une seule fois dans tous les référentiels en utilisant notre CLA.

Ce projet a adopté le Code de conduite « open-source » de Microsoft. Pour plus d’informations, consultez la foire aux questions sur le code de conduite ou contactez [opencode@microsoft.com](mailto:opencode@microsoft.com) pour toute question ou commentaire supplémentaire.

## Télémétrie 
La télémétrie est établie à faux par défaut. Si vous souhaitez envoyer des données d’utilisation à Microsoft, vous pouvez définir le paramètre « customerUsageAttribution.enabled » à « vrai » dans « setup/IaC/modules/telemetry.json ».

Microsoft peut corréler ces ressources utilisées pour prendre en charge les déploiements. Microsoft collecte ces informations pour offrir les meilleures expériences avec leurs produits et pour exploiter leur entreprise. La télémétrie est collectée via l’attribution de l’utilisation par le client. Les données sont collectées et régies par les politiques de confidentialité de Microsoft, situées à https://www.microsoft.com/trustcenter.

Le projet « Bicep » recueille la télémétrie dans certains scénarios dans le cadre de l’amélioration du produit.

## Licence
Tous les fichiers à l’exception de « Super-Linter » dans le référentiel sont soumis à la licence « MIT ».

« Super-Linter » dans ce projet est fourni à titre d’exemple pour activer les capacités de « linting » de code source. Il est soumis à la licence basée sur son référentiel.

## Marque de commerce 
Ce projet peut contenir des marques de commerce ou des logos pour des projets, des produits ou des services. L’utilisation autorisée des marques de commerce ou des logos Microsoft est soumise et doit respecter les Directives relatives aux marques de commerce et à la marque de Microsoft. L’utilisation de marques de commerce ou de logos Microsoft dans les versions modifiées de ce projet ne doit pas être source de confusion ni impliquer le parrainage de Microsoft. Toute utilisation de marques de commerce ou de logos de tiers est soumise aux politiques de ces tiers.

## gcéchange
Toute la documentation à l’appui de la solution peut être trouvée sur gcéchange, y compris l’architecture, le Livre de jeu d’installation et le Livre de jeu de remédiation.
https://gcxgce.sharepoint.com/teams/10001628

Remarque : Si vous n’avez jamais utilisé gcéchange, vous devrez d’abord vous inscrire [accès au Réseau privé virtuel (RPV) est requis pour l’enregistrement]. Inscrivez-vous à https://www.gcx-gce.gc.ca/.