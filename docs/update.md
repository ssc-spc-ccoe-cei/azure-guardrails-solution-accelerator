# Guardrails - Update

Updating the components of a previously-deploy Guardrails Solution Accelerator instance is accomplished using the GuardrailsSolutionAcceleratorSetup PowerShell module. It is possible to update individual components of a deployment but recommended to update all components to ensure versions remain synchronized. 

The components which can be updated are:

| Name | Description | Update Source |
|---|---|---|
| GuardrailPowerShellModules | The PowerShell modules that define each guardrail and the required controls. | GitHub Azure/GuardrailsSolutionAccelerator 'main' branch |
| AutomationAccountRunbooks | The Azure Automation Account runbook definitions which execute the guardrail PowerShell modules | Local clone of the GitHub repo |
| Workbook | The Workbook definition which displays the results guardrail PowerShell module executions, pulling from the Log Analytics workspace | Local clone of the GitHub repo |
| CoreComponents | This step updates the Azure ARM resource configurations based on the Bicep templates for resources not otherwise updated above (such as Automation Account config and variables) | Local clone of the GitHub repo |

## Update Process

1. Ensure you have the latest version of the Guardrails Solution Accelerator though one of the following processes. In most cases, downloading the latest release is the recommended approach. Use the `git` option if you want to deploy updates published between releases or pre-release updates.

    **Download the latest release from GitHub**
    Download the latest release with `wget` or `Invoke-WebRequest -outFile`, specifying the release version in the URL (v1.0.6 in examples below)

    Examples:
    `wget https://codeload.github.com/Azure/GuardrailsSolutionAccelerator/zip/refs/tags/v1.0.6`

    `Invoke-WebRequest -Uri https://codeload.github.com/Azure/GuardrailsSolutionAccelerator/zip/refs/tags/v1.0.6 -OutFile GR1.0.6.zip`

    Extract the downloaded release:
    `Expand-Archive -Path <path_to_downloaded_zip>`

    **Use Git**
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