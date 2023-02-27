# 30 Guardrails solution accelerator - Central Departments View


## Setup
Like guardrails, configure config.json.

Optionally, the ApplicationId and SecurePassword can be set in the config.json file. If not set, the user will need to update KeyVault secrets manually.

## After the setup
After the setup, configure the SPN`s application Id and Secure password need to be set in the Keyvault, if not specified in the config.json file.

## Installing Grafana Dashboards

During setup, the Grafana Dashboard files are modified and made available in the ~/setup/grafana folder. In the Grafana Dashboard, do the following to install the dashboards:
- Customize the Datasource to point to the right workspace (the newly created one)
- Open the Departmentsview.json file, copy the contents.
- Click on Dashboards -> Manage -> Import and paste the contents of the Departmentsview.json file.
- Configure parameters
  - Data sources should map to the just modified data source.
  - Constants should be set with any value (single space recommended)
  - Save.
  - Repeat for the other dashboards (Departments Details and Tenant Details)
  - Favorite the Departments View dashboard.
