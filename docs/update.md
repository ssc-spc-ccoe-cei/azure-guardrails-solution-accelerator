# Guardrails - Update

Script: uses the same syntax of the setup, but adding the `-update` switch. For example:

`.\setup.ps1 -configFilePath .\config.json -userId <currentuserUPN> -update`

The setup.ps1, when called with the `-update` switch, will:
- Reuse the same parameters from the config.json file
- redeploy the guardrails.bicep template
- Re-import both runbooks (main and backend).
- Upload the modules.json file to the storage account.