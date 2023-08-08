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

- Run the following PowerShell script to download the latest release and prepare for configuration:

```
# get the latest released version
$latestRelease = Invoke-RestMethod 'https://api.github.com/repos/Azure/GuardrailsSolutionAccelerator/releases/latest'

# download the latest released version's Zip archive
[System.Net.WebClient]::new().DownloadFile("https://github.com/Azure/GuardrailsSolutionAccelerator/archive/refs/tags/$($latestRelease.name).zip","$pwd/guardrailsSolution_$($latestRelease.name).zip")

# extract the downloaded Zip
Expand-Archive -Path "./guardrailsSolution_$($latestRelease.name).zip"

# change location to the 'setup' directory of the downloaded release
cd "./guardrailsSolution_$($latestRelease.name)/GuardrailsSolutionAccelerator-$($latestRelease.name.trim('v'))"
```

### Use prerelease code

In certain testing or evaluation scenarios, it may make sense to deploy the solution from pre-release code. This is not recommended in most scenarios. See [Installing or Updating from Prerelease](./prerelease.md)

## Configuration

Edit config.json with:
```
code ./setup/config.json
```
Adjust parameters as required.

All named resources will have the first 6 characters of the tenant Id appended to their names.

|Parameter|Description|Is Required| Default Value | Validation Pattern |
|---------|-----------|-----------|---------------|---------|
|keyVaultName|Name prefix for the KeyVault resource | True | 'guardrails' | '^[a-z0-9]{3,12}$' |
|resourcegroup|Resource Group name prefix for the deployed the solution| True | 'guardrails' | '^[a-z0-9][a-z0-9-_]{2,64}$' |
|region|Location to deploy. 'canadacentral' is the default| False | 'canadacentral' | _Azure Region Name_|
|storageaccountName|name prefix of the storage account to be used. 4 random characters will be added to this name to avoid conflicts| True | 'guardrails' | '^[a-z0-9][a-z0-9]{2,11}$' |
|logAnalyticsworkspaceName| name prefix for the Log Analytics workspace| True | 'guardrails' | '^[a-z0-9][a-z0-9-_]{2,51}[a-z0-9]$' |
|autoMationAccountName| Name prefix for the Automation Account | True | 'guardrails' | '^[a-z0-9][a-z0-9-_]{2,40}[a-z0-9]$' |
|FirstBreakGlassAccountUPN| User principal name of the first break glass account (ex: breakglass@contoso.com) | True | | '^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$' |
|SecondBreakGlassAccountUPN| User principal name of the second break glass account (ex: breakglass@contoso.com) | True | | '^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$' |
|PBMMPolicyID|Guid of the PBMM applied policy. 4c4a5f27-de81-430b-b4e5-9cbd50595a87 is the default Id but a customized version may have been used.| True |'4c4a5f27-de81-430b-b4e5-9cbd50595a87' | '^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$' |
|AllowedLocationPolicyId|Guid for the Allowed Location policy. e56962a6-4747-49cd-b67b-bf8b01975c4c is the default| True |'e56962a6-4747-49cd-b67b-bf8b01975c4c' | '^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$' |
|DepartmentNumber| The office Government of Canada department number - see: https://open.canada.ca/data/en/dataset/22090865-f8a6-4b83-9bad-e9d61f26a821 | True | | integer 1-999 |
|CBSSubscriptionName|Subscription Name containing the CBS solution. This subscription will be used to find the required components. **This subscription will also be excluded from checks.**| False | 'N/A' | string |
|SecurityLAWResourceId|Full resource Id of the Log analytics workspace used for Security (/subscriptions/...)| True | | '^\/subscriptions\/[a-fA-F0-9]{8}-([a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}\/resourceGroups\/[^\/]+\/providers\/[^\/]+(\/[^\/]+)*$'|
|HealthLAWResourceId|Full resource Id of the Log analytics workspace used for resource Health (/subscriptions/...)| True | | '^\/subscriptions\/[a-fA-F0-9]{8}-([a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}\/resourceGroups\/[^\/]+\/providers\/[^\/]+(\/[^\/]+)*$'|
|Locale|Language of the messages in the solution. At the moment, supported languages are english or french and default is english (en-CA or fr-CA)| True | 'en-CA' | '^(en\|fr)-CA$' |
|lighthouseServiceProviderTenantID| If using Lighthouse cross-tenant delegated access to Guardrails data, specify the Azure AD tenant ID (GUID) of the managing tenant| False | | '^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$' |
|lighthousePrincipalDisplayName| If using Lighthouse cross-tenant delegated access to Guardrails data, specify the display name of the Azure AD principal (group or user) to be delegated access to your Guardrails resource group| False | | string |
|lighthousePrincipalId|If using Lighthouse cross-tenant delegated access to Guardrails data, specify the object ID (GUID) of the Azure AD principal (group or user) to be delegated access to your Guardrails resource group| False | | '^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$'|
|lighthouseTargetManagementGroupID|If using Lighthouse cross-tenant delegated access to Guardrails data, specify the name of the Management Group under which all subscriptions will grant Defender for Cloud access to the managing tenant| False | | string |
|securityRetentionDays | Defines the minimum number retention days for the Security Log Analytics workspace provided. 730 days by default. Can be changed to accommodate other scenarios.| False | 730 | integer 0-730 |
|cloudUsageProfiles| Specifies the [Cloud Usage Profiles](https://github.com/canada-ca/cloud-guardrails/blob/master/EN/00_Applicable-Scope.md) as a comma-separated string. Example: "1,2,3" | False | 'default' | '^(default|[0-9](,[0-9])+?)$'|

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

In many organizations, Tags may be required in order for Resource Groups to be created. The Guardrails setup uses a file called `./setup/tags.json` to create tags for the Resource Group (only).

The only default and required tags are:

```json
    {
        "Solution":"Guardrails Accelerator",
        "ReleaseVersion": "1.0.4",
        "ReleaseDate": "2022/09/01"
    }
```

Add tags as required per your policies in a json array format.
Please do not delete the default required tags

## Deployment

Import the GuardrailsSolutionAcceleratorSetup module from the downloaded code:

```powershell

Import-Module ./src/GuardrailsSolutionAcceleratorSetup

```

Start the Guardrails Solution Accelerator deployment with the default configuration (core resources only):

```powershell
Deploy-GuardrailsSolutionAccelerator -configFilePath ./setup/config.json
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
