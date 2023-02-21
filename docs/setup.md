# Guardrails - Setup

## Requirements

- Azure Subscription
- Global admin permissions
- Configure user (the one used to setup ) to have "Access Management for Azure Resource" permissions. (https://docs.microsoft.com/en-us/azure/role-based-access-control/elevate-access-global-admin). The permission can be removed after the setup.

## Downloading

Navigate to Cloud Shell (from the Azure Portal) and authenticate as a user that has Azure and Azure AD Permissions (To assign permissions to the Automation Account Managed Identity).

Please make sure to select **PowerShell** as shell type.

<p align="center">
<img src="./media/AzurePortalCloudShell.png" />
</p>

### Use Released Code (Recommended)

- Navigate to the repository main page and look for the Releases. Select the desired release and download the appropriate asset:
For example:
```
wget https://github.com/Azure/GuardrailsSolutionAccelerator/archive/refs/tags/relasenumber.zip
```
Then unzip the files and change directories (Example. Folder names will vary depending the release):
```
Expand-Archive ./v1.0.1.zip
```
```
cd ./v1.0.1/GuardrailsSolutionAccelerator-1.0.1/setup/
```

### Use prerelease code

See [Installing or Updating from Prerelease](./prerelease.md)

## Configuration

Edit config.json with:
```
code ./config.json
```
Adjust parameters as required.

All named resources will have the first 6 characters of the tenant Id appended to their names.

|Parameter|Description|
|---------|-----------|
|keyVaultName|Name for the KeyVault resource|
|resourcegroup|Resource Group to deploy the solution|
|region|Location to deploy. Canadacentral is the default|
|storageaccountName|name of the storage account to be used. 4 random characters will be added to this name to avoid conflicts|
|logAnalyticsworkspaceName| base name for the log analytics workspace|
|autoMationAccountName| base name for the automation account |
|FirstBreakGlassAccountUPN| UPN for the first break glass account|
|SecondBreakGlassAccountUPN| UPN for the second break glass account|
|PBMMPolicyID|Guid of the PBMM applied policy. 4c4a5f27-de81-430b-b4e5-9cbd50595a87 is the default Id but a customized version may have been used.|
|AllowedLocationPolicyId|Guid for the Allowed Location policy. e56962a6-4747-49cd-b67b-bf8b01975c4c is the default|
|DepartmentNumber| The office Government of Canada department number - see: https://open.canada.ca/data/en/dataset/22090865-f8a6-4b83-9bad-e9d61f26a821 |
|CBSSubscriptionName|Subscription Name containing the CBS solution. This subscription will be used to find the required components. **This subscription will also be excluded from checks.**|
|SecurityLAWResourceId|Full resource Id of the Log analytics workspace used for Security (/subscriptions/...)|
|HealthLAWResourceId|Full resource Id of the Log analytics workspace used for resource Health (/subscriptions/...)|
|Locale|Language of the messages in the solution. At the moment, supported languages are english or french and default is english (en-CA or fr-CA)|
|lighthouseServiceProviderTenantID| If using Lighthouse cross-tenant delegated access to Guardrails data, specify the Azure AD tenant ID (GUID) of the managing tenant|
|lighthousePrincipalDisplayName| If using Lighthouse cross-tenant delegated access to Guardrails data, specify the display name of the Azure AD principal (group or user) to be delegated access to your Guardrails resource group|
|lighthousePrincipalId|If using Lighthouse cross-tenant delegated access to Guardrails data, specify the object ID (GUID) of the Azure AD principal (group or user) to be delegated access to your Guardrails resource group|
|lighthouseTargetManagementGroupID|If using Lighthouse cross-tenant delegated access to Guardrails data, specify the name of the Management Group under which all subscriptions will grant Defender for Cloud access to the managing tenant|

Save the file and exit VSCode [Ctrl+S] & [Ctrl+Q] .

Note about policy definitions:

In the standard configuration file, the following parameters are pre-configured:
```
"PBMMPolicyID":"4c4a5f27-de81-430b-b4e5-9cbd50595a87",

"AllowedLocationPolicyId": "e56962a6-4747-49cd-b67b-bf8b01975c4c",
```
These are the default GUIDs for the "Canada Federal PBMM" Initiative and for the "Allowed Location" policy, respectively. If any other custom Initiative or Policy are used, please update the file as required. To list Initiative definitions and policies, use, respectively:
```
Get-AzPolicySetDefinition | Select-Object Name -ExpandProperty Properties | select Name,DisplayName | Out-GridView`

Get-AzPolicyDefinition | Select-Object Name -ExpandProperty Properties | select Name,DisplayName | Out-GridView`
```

## Adding Tags to the Resource Group

In many organizations, Tags may be required in order for Resource Groups to be created. The Guardrails setup uses a file called `tags.json` to create tags for the Resource Group (only).

The only default and required tags are:
      
    {
        "Solution":"Guardrails Accelerator",
        "ReleaseVersion": "1.0.4",
        "ReleaseDate": "2022/09/01"
    }

Add tags as required per your policies in a json array format.
Please do not delete the default required tags 

## Deployment

Import the GuardrailsSolutionAcceleratorSetup module from the downloaded code:

```powershell
cd ./GuardrailsSolutionAccelerator # navigate to the solution directory
Import-Module ./src/GuardrailsSolutionAcceleratorSetup

```

Start the Guardrails Solution Accelerator deployment with the default configuration (core resources only):
```powershell
Deploy-GuardrailsSolutionAccelerator -configFilePath .\setup\config.json
```

Alternatively, these parameters can be used to verify a deployment or to deploy additional components:

`-newComponents`: This parameter defaults to 'coreComponents', but additional components can be specified (see Centralized Reporting section below)

`-validatePrerequisites`: Add this switch parameter to validate the target environment (but take no action)

`-validateConfigFile`: Add this switch parameter to validate the values in the -configFilePath file (but take no action)

To see additional examples and parameter details run:

```powershell
Get-Help Deploy-GuardrailsSolutionAccelerator -Detailed
```

### Centralized Reporting (Lighthouse) Configuration

 The accelerator implements two different scenarios for centralized management, detailed below. Azure Lighthouse is used to delegate access to a managed tenant by a managing tenant. These components can be added to an existing deployment or included in a new deployment. 

#### Centralized Customer Reporting Support

This option grants the remote tenant identity specified in the configuration file access to the Guardrails reporting data in the Guardrails resource group. This enables the remote managing tenant to centrally run reports against multiple managed tenants. The summary of this Lighthouse delegation is:

   **Scope:** The Guardrails solution resource group in the managed tenant (where the Guardrails solution is being deployed)

   **Permissions:**

- Managed Services Registration assignment Delete Role (this role allows the managed tenant to delete the Lighthouse delegation)
- Reader
- Monitoring Reader

#### [PREVIEW] Centralized Customer Defender for Cloud Support

[This feature is in preview and is intented to support features which are not yet implemented, which a managing tenant pulls Defender for Cloud data from managed tenants.] This option grants the remote tenant identity specified in the configuration file access to the Defender for Cloud data in every subscription under the Management Group ID, also specified in the configuration file. This configuration enables the remote managing tenant to access the Defender for Cloud data in the managed tenant (where setup is being executed).  

   **Scope:** The Guardrails solution resource group in the managed tenant (where the Guardrails solution is being deployed)

   **Permissions:**

- Managed Services Registration assignment Delete Role (this role allows the managed tenant to delete the Lighthouse delegation)
- Security Reader

#### Lighthouse Configuration Deployment

If this Guardrails Accelerator solution will be deployed in a scenario where a central Azure tenant will report on the Guardrails data of this Azure tenant, include the `-newComponents` parameter when calling `Deploy-GuardrailsSolutionAccelerator` and specify the centralized reporting components (along with CoreComponents) to be deployed. This same command will work to add the Lighthouse configurations to an existing deployment. 

For example:

```powershell
 Deploy-GuardrailsSolutionAccelerator -configFilePath "C:\config.json" -validatePrerequisites -newComponents CoreComponents,CentralizedCustomerDefenderForCloudSupport,CentralizedCustomerReportingSupport. 
```

For this feature to deploy, the following values must also existing the config.json file:

- lighthouseServiceProviderTenantID
- lighthousePrincipalDisplayName
- lighthousePrincipalId
- lighthouseTargetManagementGroupID

#### Troubleshooting Lighthouse Configuration

The Defender for Cloud automated Lighthouse delegation deployment to each subscription may take up to 24 hours to apply. If, after 24 hours, all subscriptions are not showing as properly delegated, ensure that the the Microsoft.ManagedServices and Microsoft.PolicyInsights Resource Providers are registered in each target subscription. Check that a Remediation Task exists at the target management group (on the customer side), and review it for deployment failures.

## Removing an existing deployment

In the event that an existing Guardrails deployment needs to be removed, the GuardrailsSolutionAcceleratorSetup has built-in modules to ensure a complete clean up. The modules are not imported automatically, but can be manually imported as shown below:

> **Warning**
> Removing your deployment permanently deletes your Log Analytics data. To retain the data, move the Log Analytics workspace to a different resource group before executing the Remove-GSACoreResource command!

```powershell
Import-Module src\GuardrailsSolutionAcceleratorSetup\modules\Remove-GSACoreResources
Import-Module src\GuardrailsSolutionAcceleratorSetup\modules\Remove-GSACentralizedDefenderCustomerComponents
Import-Module src\GuardrailsSolutionAcceleratorSetup\modules\Remove-GSACentralizedReportingCustomerComponents
```

To remove components, use the `Get-GSAExportedConfig` command to retrieve the deployment's configuration from the Key Vault and pass the config to the appropriate removal command over the pipeline. For example:

```powershell
Get-GSAExportedConfig -KeyVaultName <keyVaultName> | Remove-GSACoreResources
```
