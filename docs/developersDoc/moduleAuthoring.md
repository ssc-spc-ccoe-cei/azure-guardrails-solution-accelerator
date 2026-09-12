# Creating a new module

Checks to run are configured in `setup/modules.json`, with the structure described below. PowerShell modules to install are listed separately in `setup/automation-runtime-modules.json`.

{
  "ModuleName": "",
  "Control":"Name of GR module",
  "ModuleType": "Builtin",
  "Status": "Enabled",
  "Script": "the line to be run",
  "variables":
  [
    {
      "Name":"",
      "Value":""
    }
  ],
  "secrets":
    [
      {
        "Name":"",
        "Value":""
      }
    ],
  "localVariables":
    [
      {
        "Name":"",
        "Value":""
      }
    ]
}

The general steps to create a module are:

- Write PowerShell Module, sign it and zip it.
- Store the compress file in the psmodules folder
- Add the module's name to `setup/automation-runtime-modules.json`, for example `{ "name": "Check-BreakGlassAccountOwnersInformation" }`. The installer reads its version from the matching source `.psd1` and supplies it to Bicep's existing module resource loop.

- Update modules.json file with the modules information:
{
    "ModuleName": "",
    "Control":"Guardrails",
    "ModuleType": "Builtin",
    "Status": "Enabled",
    "Script": "",
    "variables":
    [
      {
        "Name":"",
        "Value":""
      }
    ],
  "secrets":
     [
       {
         "Name":"",
         "Value":""
       }
     ],
  "localVariables":
     [
       {
         "Name":"",
         "Value":""
       }
     ]
  }

All variables, localvariables and secrets are added to `$vars.xxxxx' (where xxxxx is the name in the definition above) and can be used as module parameters.

variables: references to automation account variables. Use the name of the automation account variable in the Name and its content will be populates in $vars.<Value>
for example:
    "variables":
    [
      {
        "Name":"variable1",
        "Value":"myvariable"
      }
    ],
can be referenced as $vars.myvariable in the script call.

localvariables: variables added to the `$vars` object, only local to the execution of the module. 

secrets: references to keyvault secrets.


- Add automation account variable to the bicep file and update setup/config/etc if required.
    - Config.json file needs to receive a new entry.
    - In setup.ps1, the entry must be referred and, if needed, replaced in the bicep parameters template file.

## Module versions and deployment

For a Guardrails module update, increment `ModuleVersion` in its source `.psd1` once for the feature or fix, then rebuild its ZIP. JSON contains only its name, so there is no second version to edit. External modules such as `Az.Marketplace` retain their version and HTTPS download URL in JSON because they have no source manifest in this repository.

```text
JSON installation list + source .psd1 versions + matching ZIPs
                            |
              Installer validation
                            |
            One resolved list, held in memory
                            |
               Bicep and readiness checks
```

The installer uses `Get-GSAExpectedAutomationRuntimeModules` in `Manage-GSAAutomationRuntime.psm1` to resolve source versions and validate local ZIPs. It rejects missing or ambiguous manifests, invalid entries, and stale ZIP versions before deployment.

Use source files and ZIPs from the same selected release or branch. With alternate module URLs, publish the matching ZIPs there as well; checking local ZIPs does not verify remote files. Normal runbook execution does not read this installation list. One-off client hotfixes still run from the installed modules, and component-only updates leave module versions alone.

Direct Bicep callers must now supply `guardrailsRuntimeModules` with the resolved array instead of relying on Bicep to read JSON. Obtain that array with the exported `Get-GSAExpectedAutomationRuntimeModules` function after importing `Manage-GSAAutomationRuntime.psd1`. Supply an empty array only for updates where both `newDeployment` and `updatePSModules` are false. The normal installer handles this automatically.

## Standard variables

These variables can be used in the module calls without the needs of creating custom variables in the modules.json file.

- $WorkSpaceID : log analytics
- $LogType : the type of logs
- $KeyVaultName: name of the keyvault
- $GuardrailWorkspaceIDKeyName : Name of the variable object name in the AA containing the keyvault key.
- $ResourceGroupName : name of the resource group for guardrails.
- $StorageAccountName : Name of the Storage Account.
- $ReportTime: the unified report time for all modules in each execution.
- $Locale: the specified local (en-CA is default)
- $SubID: id of the installed subscription
- $TenantId: id of the Azure AD tenant


## Exception Handling

Exception handing in modules is implemented using try/catch blocks and the custom function `Add-LogEntry`. `Add-LogEntry` adds an event to the custom GuardrailsComplianceException table in the Guardrails Log Analytics Workspace. When calling `Add-LogEntry`, keep the following in mind:

- Within a try/catch block, not all errors for a given cmdlet are terminating--add the `-ErrorAction Stop` parameter and value to ensure errors are caught
- Including the original exception at the end of a custom message ensures that those details are also logged. For example, `-message 'Code execution hit a error. Error message: $_'`
- `Add-LogEntry` requires a `-workspaceKey` and `-workspaceGUID` parameter be passed, in addition to `-severity` and `-message` parameters
- `Add-LogEntry` does not terminate the script or write to the host; add either a `Write-Error` or `throw` to log to the host or terminate the script

## Testing

From your fork (which will be public due to visibility inheritance) you can clone to the Cloud Shell storage normally. After that, you may edit the guardrails.bicep file and adjust the **ModuleBaseURL** parameter and point to the base URL of you repo. Make sure to test downloading a module to confirm the raw URL. Alternatively, add an entry to the parameters_template.json file, as per below:

`"ModuleBaseURL": {
      "value": "<your github base url"
    }`
