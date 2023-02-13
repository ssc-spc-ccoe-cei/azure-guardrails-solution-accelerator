# Updating Guardrails Solution Accelerator Deployments

## Updating Deployed Components

The components which can be updated are:

| Name | Description | Update Source |
|---|---|---|
| GuardrailPowerShellModules | The PowerShell modules that define each guardrail and the required controls. | GitHub Azure/GuardrailsSolutionAccelerator latest full release (override with `-releaseVersion` or `-prerelease` parameters) |
| AutomationAccountRunbooks | The Azure Automation Account runbook definitions which execute the guardrail PowerShell modules | Local clone of the GitHub repo |
| Workbook | The Workbook definition which displays the results guardrail PowerShell module executions, pulling from the Log Analytics workspace | Local clone of the GitHub repo |
| CoreComponents | This process updates the Azure ARM resource configurations based on the Bicep templates for resources not otherwise updated above (such as Automation Account config and variables) | Local clone of the GitHub repo |
| Configuration Variables | Make changes to the configuration values used when the solution was deployed or last updated | Configuration file or config Key Vault secret |

When updating a deployment, the default configuration deploys the PowerShell modules included in the latest full release on GitHub. To deploy a specific release, use the `-releaseVersion` parameter and specify a release name, such as `v1.0.9` or `v1.0.8.1`.

To update a deployment to a pre-release version of the solution, see the steps in [Installing or Updating from Prerelease](./prerelease).

## Configuration Variable Update Process

When updating the configuration variables used in an existing Guardrails deployment, it is important to ensure that the new value is also used during future deployment updates. To achieve this, both update the configuration variable in the Automation Account and in the config file or config Key Vault (depending on the process you use when updating). Another option is to just complete Step 2 below, then run an update deployment, which will update the Automation Account variables.

### Step 1: Updating the Automation Account Variables

1. Navigate to the Automation Account under the Guardrails resource group in the Azure Portal
1. In the Automation Account configuration, under Shared Resources, click Variables
1. Update the variable to the new value and save.

### Step 2: Updating the Configuration Variable Source

If you are using a config.json file that you plan to maintain for future updates, replace the value in that file.

If you are planning to use the configuration stored in the Guardrails Key Vault (recommended), update the config secret following these steps:

1. Navigate to the Key Vault in the Guardrails resource group in the Azure Portal
1. Under Secrets, open the `gsaConfigExportLatest` secret
1. Copy the current secret version value and paste it into a text editor, such as VS Code
1. Update the appropriate value
1. Back in the Azure Portal, create a new version of the `gsaConfigExportLatest` secret with the updated value

## Resource Update Process

Updating the resource components of a previously-deploy Guardrails Solution Accelerator instance is accomplished using the GuardrailsSolutionAcceleratorSetup PowerShell module. It is possible to update individual components of a deployment but recommended to update all components to ensure versions remain synchronized.

1. Ensure you have the latest version of the Guardrails Solution Accelerator though one of the following processes. In most cases, downloading the latest release is the recommended approach. Use the `git` option if you want to deploy updates published between releases or pre-release updates.

    **Option 1: Download the latest release from GitHub**
    Download the latest release with `wget` or `Invoke-WebRequest -outFile`, specifying the release version in the URL (v1.0.6 in examples below)

    Examples:
    `wget https://codeload.github.com/Azure/GuardrailsSolutionAccelerator/zip/refs/tags/v1.0.6`

    `Invoke-WebRequest -Uri https://codeload.github.com/Azure/GuardrailsSolutionAccelerator/zip/refs/tags/v1.0.6 -OutFile GR1.0.6.zip`

    Extract the downloaded release:
    `Expand-Archive -Path <path_to_downloaded_zip>`

    **Option 2: Use Git**
    If you already have a clone of the GuardrailsSolutionAccelerator, navigate to that directory in PowerShell and use `git` to make sure you have the most recent changes:

    ```git
    cd GuardrailsSolutionAccelerator
    git fetch
    git checkout v1.0.6
    ```

    Otherwise, if you do not have a clone of the repo, use the `git` in a PowerShell console to pull a copy down to your system or Cloud Shell:

    ```git
    git clone https://github.com/Azure/GuardrailsSolutionAccelerator.git GuardrailsSolutionAccelerator
    ```

2. Import the GuardrailsSolutionAcceleratorPowershell module from your clone of the repo:

   ```powershell
   cd GuardrailsSolutionAccelerator # navigate to the GuardrailsSolutionAccelerator directory
   Import-Module ./src/GuardrailsSolutionAcceleratorSetup
   ```

3. Run the `Deploy-GuardrailsSolutionAccelerator` function with the `-update` parameter. Either pass in the JSON configuration file you used when deploying the Guardrails solution initially or pull the last used configuration from the specified KeyVault (recommended).

   Get the last used configuration from the specified Guardrails KeyVault (found in your Guardrails Solution resource group). This option is only available to deployments created or updated since release version `v1.0.6` of the solution. The executing user must have permissions to read secrets in the specified KeyVault. 

   ```powershell
      Get-GSAExportedConfig -KeyVaultName guardrails-xxxxx | Deploy-GuardrailsSolutionAccelerator -update
   ```

   If you have the original JSON configuration file (or recreate one), you can pass it to the update process like this:

   ```powershell
      Deploy-GuardrailsSolutionAccelerator -update -componentsToUpdate CoreResources -ConfigFilePath c:/myconfig.json
   ```