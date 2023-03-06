# Debugging Guardrail Modules

Running the Guardrails modules in Azure Automation account make them difficult to debug. The solution provides an alternative to attempting to debug the modules running in the Automation Account by enabling you to execute the solution locally. 

## Prerequisites

- Visual Studio Code
- VSCode's PowerShell extension
- The latest version of the [Azure PowerShell modules](https://learn.microsoft.com/powershell/azure/install-az-ps)
- Access to the Guardrail deployment's KeyVault (secret reader added)
- At least Reader permissions on the target Subscription and Azure AD Tenant 

## Local Debugging Process

> **NOTE**: Local debugging will use the configuration variable values exported during the last solution deployment or update operation. If you have updated values in the Automation Account Variables directly, you may need to manually update the exported config secret value to reflect the same change. 

1. Clone the deployed version of the solution on your local system, either using `git clone` and `git checkout v1.10.0` (for example) or downloading the appropriate release from the [GuardrailsSolutionAccelerator Releases](https://github.com/Azure/GuardrailsSolutionAccelerator/releases) page (downloading the source.zip file)
1. Open the solution directory in Visual Studio Code
1. Navigate to the module to be debugged in the `./src` directory and place a breakpoint at an appropriate location
1. In the Powershell Extension's Integrated Terminal, login to the target Azure Subscription (if you are not already signed in): `Connect-AzAccount -Scope Process`
1. After signing in to Azure, navigate to the `./setup` directory then execute the solution locally: 
  ```powershell
    ./main.ps1 -localExecution -KeyVaultName <name of the Guardrails deployment KV>
  ```
1. To filter the modules to execute, add the `-modulesToExecute <moduleNameFromModules.json>[,<moduleNameFromModules.json>]`
1. The modules in `./modules.json` will execute and your previously-set breakpoint should be hit. If the breakpoint is not working, try: `Set-PSBreakpoint -Path <module .PSM1 file> -Line <line number for breakpoint>`

See [Using Visual Studio Code for PowerShell Development](https://learn.microsoft.com/powershell/scripting/dev-cross-plat/vscode/using-vscode) for more information