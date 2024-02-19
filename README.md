# Azure Compliance as Code Solution (Guardrails Solution Accelerator) for Canadian Public Sector

## Introduction

The purpose of this reference implementation is to help Canadian Public Sector departments and agencies to identify and remediate the [GC Cloud Guardrails] (https://github.com/canada-ca/cloud-guardrails#gc-cloud-guardrails) to ensure on-going compliance with the GC Cloud Guardrail Policy validations. The GC Cloud Guardrail policy and validations for version 1 can be found in the [Treasury Board Secretariat GC Cloud Guardrail Policy] (https://github.com/canada-ca/cloud-guardrails/tree/3a148ddc8451a04fc8bd870cf32130dec4c6cb9a).
 
## Project Background

The GC Cloud Guardrails are the minimum required security controls defined by Treasure Board of Canada Secretariat (TBS) to protect and secure data to maintain the security posture of cloud environments. GC customers must implement the 12 guardrails within the first 30 days of the cloud account creation. The guardrails have been mapped on to six different cloud usage profiles.

It provides a starting point for project teams and was selected to achieve the following objectives:

* comply with the applicable mandatory procedures in the Directive on Security Management

* meet the requirements of the Direction on the Secure Use of Commercial Cloud Services: Security Policy Implementation Notice (SPIN)

* address the Communications Security Establishment’s (CSE’s) Top 10 Security Actions

* align with Government of Canada Security Control Profile for Cloud-Based GC Services

* focus on the selection of security controls to those implemented in software components of information system solutions

* achieve threat protection objectives specified in the ITSG-33 generic PBMM profile and the Government of Canada Security Control Profile for Cloud-Based GC Services

The primary purpose of Compliance as Code (CaC) Guardrails automation is for effectively reporting the compliance data of GoC GCP Organizations to TBS.

Compliance as Code (CaC) Guardrails Automation helps the Canadian Public Sector departments and agencies to identify and remediate the GC Cloud Guardrails to ensure on-going compliance with the Guardrails requirements. The GC Cloud Guardrails requirements can be found in the Canadian Governments public GitHub repository.

CaC Automation Objectives:

* Develop automated processes for TBS GC guardrails monitoring and reporting

* Automate the monitoring of customer compliance to mandatory cloud security guardrails (i.e., minimum required security controls to protect and secure data).

* Expand compliance monitoring to additional guardrails & build compliancy dashboards (IaaS/ PaaS) to support reporting

* Support the growing and evolving adoption of cloud services within the GC.

* Strengthen and optimize existing cloud security processes and services

## Architecture

Refer to gcxchange Azure Onboarding Presentation. https://gcxgce.sharepoint.com/teams/10001628

## Setup

The Azure Installation Playbook can be found on gcxchange. https://gcxgce.sharepoint.com/teams/10001628

## How it works

The solution has multiple modules, each module verifies specific set of settings in the environment and compares them with the validations [GC guardrails settings] (https://github.com/canada-ca/cloud-guardrails#gc-cloud-guardrails) mandated by [Treasury Board of Canada] (https://www.canada.ca/en/treasury-board-secretariat.html) and [Shared Services Canada] (https://www.canada.ca/en/shared-services.html). To understand what the modules are looking for please check the Remediation Playbook on gcxchange https://gcxgce.sharepoint.com/teams/10001628.

## Contributing

This project welcomes contributions and suggestions via GitHub’s issue/bug submission.

Note: If there are any questions related but do not involve a code bug or issue you can email SSC Cloud Security Compliance: cloudsecuritycompliance-conformiteinfonuagiquesecurise@ssc-spc.gc.ca

Most contributions require you to agree to a Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

Commits are not accepted to the main branch. You may do a Pull Request from a forked repository. You will not be able to push a branch directly. We also have two SSC reviewers required to review all PRs.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the Microsoft Open-Source Code of Conduct. For more information see the Code of Conduct FAQ or contact opencode@microsoft.com with any additional questions or comments.

## Telemetry

Telemetry is set to false by default. If you wish to send usage data to Microsoft, you can set the customerUsageAttribution.enabled setting to true in setup/IaC/modules/telemetry.json. Learn more in our Azure DevOps Pipelines onboarding guide.

Microsoft can correlate these resources used to support the deployments. Microsoft collects this information to provide the best experiences with their products and to operate their business. The telemetry is collected through customer usage attribution. The data is collected and governed by Microsoft's privacy policies, located at https://www.microsoft.com/trustcenter.

Project Bicep collects telemetry in some scenarios as part of improving the product.

## License

All files except for Super-Linter in the repository are subject to the MIT license.

Super-Linter in this project is provided as an example for enabling source code linting capabilities. It is subjected to the license based on its repository.

## Trademark

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft trademarks or logos is subject to and must follow Microsoft's Trademark & Brand Guidelines. Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship. Any use of third-party trademarks or logos are subject to those third-party's policies.

## gcxchange

All documentation to support the solution can be found on gcxchange- including the Architecture, Installation Playbook, and Remediation Playbook.

https://gcxgce.sharepoint.com/teams/10001628

Note: If you have never used gcxchange you will need to register first (VPN required for registration). Register for gcxchange: https://www.gcx-gce.gc.ca/