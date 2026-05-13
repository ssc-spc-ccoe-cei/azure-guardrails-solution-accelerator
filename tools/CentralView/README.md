# CentralView — Guardrails Central Reporting

CentralView aggregates **Guardrails Solution Accelerator (CaC)** compliance data from many client (department) Azure tenants into a single Log Analytics workspace inside the SSC service-provider tenant, and exposes it through an Azure Workbook (the "Central Departments View").

It runs as an Azure Function App that, on a schedule, reads each delegated client's `GuardrailsTenantsCompliance_CL` table via Azure Lighthouse, summarizes it, and posts the result to a central Data Collection Rule (DCR) using the modern **Logs Ingestion API**.

```
client tenant A     client tenant B     ...     client tenant N
   LAW_A              LAW_B                        LAW_N
     ▲                  ▲                            ▲
     │  read via Lighthouse delegation (Log Analytics Reader)
     │
   ┌─┴─────────────────────────────────────────────────┐
   │ CentralView Function App (PowerShell)             │
   │   - timer-trigger: scheduled aggregation          │
   │   - HTTP-trigger: on-demand aggregation           │
   │ Authenticates as the aggregation Service Principal│
   │ (ApplicationId + SecurePassword from Key Vault)   │
   └─────────────────┬─────────────────────────────────┘
                     │ POST to central DCR (Logs Ingestion API)
                     │ Bearer = SP token for https://monitor.azure.com
                     ▼
              ┌──────────────────────────────┐
              │ Central DCR (Direct-kind)    │
              │   built-in logsIngestion EP  │
              │   transformKql               │
              └──────┬───────────────────────┘
                     ▼
              ┌──────────────────────────────┐
              │ Central Log Analytics WS     │
              │   GuardrailsTenantsCompliance_CL
              │ + Azure Workbook (Departments view)
              └──────────────────────────────┘
```

A full technical reference of the DCR pipeline is in [`DCR_Log_Ingestion_Architecture.html`](../../DCR_Log_Ingestion_Architecture.html) at the repository root.

---

## 1. Prerequisites

CentralView is deployed in the **SSC service-provider tenant** (the same tenant that hosts the central reporting workspace). Before you start, make sure each item below is in place.

### 1.1 Tooling (deployment host)

| Tool | Min version | Notes |
|---|---|---|
| PowerShell | **7.2+** | `pwsh` on Cloud Shell or local. Windows PowerShell 5.1 is not supported. |
| Az PowerShell modules | `Az.Accounts ≥ 3.x`, `Az.KeyVault ≥ 5.x`, `Az.Resources ≥ 7.x`, `Az.Websites ≥ 3.x`, `Az.Monitor ≥ 5.x` | `Install-Module Az -Scope CurrentUser -Force` |
| Bicep CLI | `0.20+` | `winget install -e --id Microsoft.Bicep` (Windows) — Cloud Shell already has it. `setup.ps1` validates this before deploying. |
| Git | any recent | Clone the accelerator repo. |

### 1.2 Azure identity and roles

You — the **deploying user** — need the following in the **SSC service-provider tenant** (where CentralView lives):

| Scope | Role |
|---|---|
| Target subscription | **Owner** (or *Contributor* **plus** *User Access Administrator*) |
| Tenant directory (Entra ID) | **Application Administrator** *or* **Cloud Application Administrator** — needed only to create / rotate the aggregation app registration. Skip if a platform team provides the App ID & secret. |

### 1.3 Aggregation Service Principal and central security group

CentralView authenticates to client tenants and to the central DCR as an **App Registration / Service Principal** (not as a managed identity, because MSI cannot cross tenants). However, on the SSC enterprise tenant the SP is **not** delegated to clients directly — it is a **member of a central Entra ID security group**, and clients delegate `Log Analytics Reader` to that **group** through their Lighthouse offers. This indirection means SSC can rotate / replace the SP without touching every client's Lighthouse delegation.

```
SSC Enterprise tenant                  Client tenant
─────────────────────                  ─────────────
[Entra ID security group]   ◄────── Lighthouse offer:
   e.g. "GcPc-CTO-Guardrails           "Log Analytics Reader"
        _Compliance-Owners"             granted to <group ObjectId>
        ▲
        │ member
        │
[Aggregation Service Principal]
  (ApplicationId + SecurePassword
   in CentralView Key Vault)
```

Before deployment, confirm the following with the SSC platform team:

| Item | Where it lives | Notes |
|---|---|---|
| Central security group (already exists) | SSC enterprise tenant — Entra ID | Display name follows the convention `<dept>-<role>-Guardrails_Compliance-Owners` (e.g. `GcPc-CTO-Guardrails_Compliance-Owners`). Its **Object ID** is what every client publishes in their Guardrails `config.json` as `lighthousePrincipalId`. |
| Aggregation Service Principal — Application ID | SSC enterprise tenant — App registrations | One App registration per CentralView deployment (or shared across deployments). |
| Aggregation Service Principal — client secret | App registration "Certificates & secrets" | Rotation policy: 12 months max. The value populates `config.json` `SecurePassword` *(or is written directly to the Key Vault secret of the same name post-deployment)*. |
| SP membership in the central group | Entra ID → Groups → \<group\> → Members | **The SP must be a member of the central group** — otherwise it has no effective `Log Analytics Reader` rights in any client tenant. SSC platform team typically owns this membership. |

> [!IMPORTANT]
> The Lighthouse offer that clients deploy targets the **group ObjectId**, not the SP ObjectId. The SP gains read access in client tenants **only** via group membership. If a CentralView deployment can't see client data, the very first thing to check is that the SP is still a member of the central group.

The SP needs **no Microsoft Graph permissions** by default — Lighthouse delegation (transitively, via the group) provides ARM/Log Analytics access; Graph is not used by CentralView.

### 1.4 Lighthouse delegation from each client tenant

Each client (department) tenant that you want to pull data from must publish a **Lighthouse offer** that delegates `Log Analytics Reader` over the client's Guardrails resource group (or LAW) to the **central security group** (§1.3) — not to the SP directly. This is bundled with the main Guardrails accelerator's `CentralizedCustomerReportingSupport` deployment option, where the deployer enters the group's Object ID and display name in the client's `config.json`:

```jsonc
// In the client tenant's setup/config.json for the main accelerator
"lighthousePrincipalId":          "<central-group-object-id>",
"lighthousePrincipalDisplayName": "<central-group-display-name>",
"lighthouseServiceProviderTenantID": "<ssc-enterprise-tenant-id>",
"lighthouseTargetManagementGroupID": "<client-tenant-root-mg-id>"
```

When the client runs `Deploy-GuardrailsSolutionAccelerator -newComponents CentralizedCustomerReportingSupport`, the Lighthouse `registrationDefinition` + `registrationAssignment` resources are created in the client tenant, granting the **group** Log Analytics Reader (and a couple of supporting roles) over the Guardrails RG.

Confirm the delegation exists by running, in the SSC enterprise tenant after sign-in:

```powershell
Get-AzManagedServicesAssignment -Scope "/subscriptions/<client-sub-id>"
# Expect to see ManagedByTenantId = <ssc-tenant-id> and the principal display name
# matching the central group.
```

If the client uses a different group (different department), CentralView still works as long as the **same SP is a member of every relevant central group**.

### 1.5 SSC platform standards / policies

CentralView is deployed into an SSC-managed subscription that is subject to tenant-wide policies. The following compliance items apply:

| Standard | What it means for CentralView |
|---|---|
| **Mandatory resource tags** (`Solution`, `ReleaseVersion`, `ReleaseDate`, `ClientOrganization`, `CostCenter`, `DataSensitivity`, `ProjectContact`, `ProjectName`, `ssc_cbrid`, `TechnicalContact`) | Set in [`setup/tags.json`](setup/tags.json). All deployed resources inherit them. **Required** by SSC tagging policy — RG creation will fail without them. |
| **Naming convention** | `setup.ps1` automatically appends the first segment of the tenant GUID (e.g. `-7198d08c`) to RG, KV, LAW, Function App, and storage account names to avoid global collisions. Configure only the base name in `config.json`. |
| **Region** | Default `CanadaCentral`. Override in `config.json` if needed; must be an approved SSC region. |
| **Data classification** | `PB` (Protected B) in `tags.json` — adjust only with platform-team approval. |
| **`SSC-SPC Lockdown Network` policy** | Denies public-network-access storage accounts and key vaults. If your subscription has this policy assigned, **request a policy exemption** for the CentralView RG before deploying (contact: `azurecloudoperations.operationsinfonuagiquesazure@ssc-spc.gc.ca`). Alternatively, the operator can extend the IaC to add private endpoints + VNet integration — not currently included in the templates. |
| **Allowed locations policy** | If a tenant `allowedLocationPolicy` is in effect, ensure the chosen `region` is in the allow-list. |
| **Cost / GLCode / CBRID** | The values in `tags.json` are SSC-specific (`Solution`, `CostCenter`, `ssc_cbrid`). Update them to match the actual chargeback codes for your deployment. |

### 1.6 Network / outbound access

The Function App needs outbound HTTPS access to:

- `*.ods.opinsights.azure.com` and `*.monitor.azure.com` (Logs Ingestion API)
- `*.vault.azure.net` (Key Vault secrets)
- `management.azure.com` (ARM, Resource Graph)
- `login.microsoftonline.com` (token acquisition)
- `graph.microsoft.com` (token validation only)

Outbound to client tenants is via public ARM/Monitor endpoints (Lighthouse routes the request).

---

## 2. Installation

### 2.1 Clone & navigate

```powershell
git clone https://github.com/ssc-spc-ccoe-cei/azure-guardrails-solution-accelerator.git
cd azure-guardrails-solution-accelerator/tools/CentralView/setup
```

### 2.2 Configure

Edit [`setup/config.json`](setup/config.json):

```jsonc
{
  "keyVaultName":              "cacreport",                  // base; -{tenantPrefix} is appended
  "resourcegroup":             "CAC-CentralView-Reporting",
  "region":                    "CanadaCentral",
  "storageaccountName":        "cacreport",                  // base; 4 random chars appended for uniqueness
  "logAnalyticsworkspaceName": "cac-centralview-reporting",
  "functionName":              "cac-centralview-reporting",
  "Locale":                    "en-CA",

  // Aggregation Service Principal (see §1.3). May be empty here and set via Key Vault after deploy.
  "ApplicationId":             "<app-registration-client-id>",
  "SecurePassword":            "<app-registration-secret>",

  // Set true ONLY when the destination GuardrailsTenantsCompliance_CL table already exists
  // (brownfield) and must not be redefined by IaC.
  "deferGuardrailsTenantsComplianceTableProvisioning": false
}
```

Edit [`setup/tags.json`](setup/tags.json) to match SSC-mandated tag values (`CostCenter`, `ssc_cbrid`, `ProjectContact`, `TechnicalContact`, etc.). All deployed resources and the RG inherit these.

### 2.3 Sign in to Azure

> [!IMPORTANT]
> **Cross-tenant Cloud Shell quirk** — Cloud Shell's managed identity is anchored to the user's home tenant. If you are a guest signed into the SSC service-provider tenant, switch the Azure portal directory to that tenant **before** opening Cloud Shell, otherwise Key Vault data-plane calls inside `setup.ps1` will fail with `Timeout waiting for token from portal`.

```powershell
Connect-AzAccount -Tenant <ssc-service-provider-tenant-id>
Set-AzContext   -Subscription <target-subscription-id>
```

### 2.4 Run setup

```powershell
.\setup.ps1 -configFilePath .\config.json
```

The script will:

1. Validate Bicep CLI availability and read `config.json` + `tags.json`.
2. Resolve the current user's object id (for self-grant of Key Vault Administrator).
3. Append the first segment of the tenant GUID to all names (idempotent / deterministic).
4. Generate 4 random lowercase chars to suffix the storage account name (one-time, to satisfy global uniqueness).
5. Resolve the aggregation SP's **object id** from the `ApplicationId` (for the DCR role assignment).
6. Create the resource group with the mandated tags.
7. Deploy [`setup/IaC/grfunc.bicep`](setup/IaC/grfunc.bicep), which creates:
   - LAW + `GuardrailsTenantsCompliance_CL` table (38 columns)
   - Saved searches and the Departments Workbook
   - DCR `guardrails-cv-dcr` (Direct kind, built-in `logsIngestion` endpoint) — no separate DCE
   - Storage account, Key Vault, App Service plan, Function App
   - All required `azure-webjobs-hosts`, `azure-webjobs-secrets` containers + content file share
   - App settings `LOGS_INGESTION_ENDPOINT` and `DCR_IMMUTABLE_ID` on the Function App
   - Role assignment `Monitoring Metrics Publisher` on the DCR → aggregation SP (only if `ApplicationId` was provided in `config.json`)
8. Grant the deploying user **Key Vault Administrator**; grant the Function App MSI **Key Vault Secrets User** + **Key Vault Reader**.
9. Write the four mandatory Key Vault secrets:
   - `WorkspaceId` — the central LAW customer id
   - `WorkspaceKey` — the central LAW primary key
   - `ApplicationId` — aggregation SP App ID *(data-plane, not declared in Bicep)*
   - `SecurePassword` — aggregation SP secret *(data-plane, not declared in Bicep)*
10. Package the `Modules/`, `grfunchttp/`, `grtimerfunction/` folders, and `requirements.psd1` into a zip and publish it to the Function App.
11. Restart the Function App.

Total wall-clock time: ~5–8 minutes.

### 2.5 Verify

```powershell
# Function settings
$f = Get-AzWebApp -ResourceGroupName <rg> -Name <function-name>
$f.SiteConfig.AppSettings | Where-Object Name -in 'LOGS_INGESTION_ENDPOINT','DCR_IMMUTABLE_ID','KEYVAULTNAME'

# Trigger the HTTP function once (replace with your function key from portal)
$code = '<function-key>'
Invoke-WebRequest -Uri "https://<function-name>.azurewebsites.net/api/grfunchttp?code=$code" -UseBasicParsing

# Then check the central LAW
$law  = Get-AzOperationalInsightsWorkspace -ResourceGroupName <rg> -Name <law-name>
Invoke-AzOperationalInsightsQuery -WorkspaceId $law.CustomerId -Query "GuardrailsTenantsCompliance_CL | take 5"
```

### 2.6 Late-binding the SP secrets

If `ApplicationId` / `SecurePassword` were left blank in `config.json`:

1. Set them as Key Vault secrets:

   ```powershell
   Set-AzKeyVaultSecret -VaultName <kv-name> -Name ApplicationId  -SecretValue (ConvertTo-SecureString '<app-id>'  -AsPlainText -Force)
   Set-AzKeyVaultSecret -VaultName <kv-name> -Name SecurePassword -SecretValue (ConvertTo-SecureString '<secret>'  -AsPlainText -Force)
   ```

2. Rerun `.\setup.ps1 -configFilePath .\config.json` (idempotent). On the second pass, the SP object id is resolved and the DCR role assignment is created.

Bicep templates **do not** declare these two secrets — that is intentional so redeploys do not blank them.

---

## 3. How it works

### 3.1 Components

| Resource | Purpose |
|---|---|
| `cac-centralview-reporting-*` (Function App, PowerShell) | Hosts `grfunchttp` (HTTP-trigger) and `grtimerfunction` (timer) entry points. Both call the `ingest-tenantsData` module. |
| `Modules/ingest-tenantsData/ingest-tenantsData.psm1` | Core aggregation logic: discovers client LAWs, pulls the per-tenant compliance summary, posts to the central DCR via `Send-GuardrailsData`. |
| `<lawName>-<tenantPrefix>` Log Analytics workspace | Destination workspace; contains the `GuardrailsTenantsCompliance_CL` table and Workbook. |
| `guardrails-cv-dcr` (DCR, Direct kind) | Exposes its **own** `logsIngestion` endpoint (no separate DCE). Transforms incoming JSON into the canonical 38-column row. |
| `<kvName>-<tenantPrefix>` Key Vault | Stores `ApplicationId`, `SecurePassword`, `WorkspaceId`, `WorkspaceKey`. |
| `<storage>-<rand>` Storage account | Function App backing storage (host blobs, secrets, content share). |
| App Service Plan `P2v2` | Function App compute. |

### 3.2 Execution timeline (one run)

```
1. Trigger fires
   ├─ timer-trigger: schedule defined in grtimerfunction/function.json
   └─ http-trigger:  grfunchttp/run.ps1   (callable with ?code=<key>)
        ↓
2. run.ps1 calls: get-tenantdata -DebugInfo:$true -LogType GuardrailsTenantsCompliance
        ↓
3. get-tenantdata (in Modules/ingest-tenantsData):
   a. Read ApplicationId & SecurePassword from Key Vault (via Function MSI)
   b. Connect-AzAccount -ServicePrincipal -Tenant <home> -Credential $cred
   c. Use Azure Resource Graph to enumerate Log Analytics workspaces
      across every subscription delegated via Lighthouse
   d. For each workspace, run KQL to summarize GuardrailsTenantsCompliance_CL
      into 1 record per (Department, Tenant, Control, ItemName, ...)
   e. Enrich each record with AggregationTenantID/Name/UPN, DeployedVersion,
      AvailableVersion, ReportTime, ...
        ↓
4. Send-GuardrailsData ($records, LogType = 'GuardrailsTenantsCompliance'):
   a. Read LOGS_INGESTION_ENDPOINT and DCR_IMMUTABLE_ID from app settings
   b. Acquire a token for https://monitor.azure.com
      (SP is already signed in; Monitoring Metrics Publisher on the DCR)
   c. Inject TimeGenerated and normalize types on every record
   d. POST JSON array to:
      {LOGS_INGESTION_ENDPOINT}/dataCollectionRules/{immutableId}
         /streams/Custom-GuardrailsTenantsCompliance?api-version=2023-01-01
   e. Expect 204 No Content on success; log full DCE response body on 4xx
        ↓
5. Azure Monitor:
   a. Validates JSON against the DCR streamDeclarations
   b. Runs transformKql (file-backed: law-centralview-tenantscompliance-transform.kql)
   c. Persists rows to GuardrailsTenantsCompliance_CL (38 columns)
        ↓
6. Azure Workbook reads the table and renders the Departments view
```

### 3.3 Identity model

| Step | Principal | How access is granted | Reason |
|---|---|---|---|
| Function App reads Key Vault | Function App **System-Assigned Managed Identity** | Key Vault `Secrets User` + `Reader` granted directly to the MI by `setup.ps1`. | Cannot leave the SSC tenant; only needs access to its own KV. |
| Function App reads client LAW data (cross-tenant) | Aggregation **Service Principal** (creds from KV) | SP is a **member of an SSC-tenant security group**; clients' Lighthouse offers grant `Log Analytics Reader` to that **group** (not to the SP directly). | MSI cannot cross tenants; the group indirection lets SSC rotate the SP without touching client delegations. |
| Function App writes to central DCR (in-tenant) | Same aggregation **Service Principal** | `Monitoring Metrics Publisher` on the central DCR, granted directly to the SP by `centralview-dcr-ingestion-rbac.bicep`. | DCR is in the SSC tenant; direct role assignment is simpler than going through the group. |

In other words: in the **SSC tenant** the SP holds direct roles (KV via MI, DCR via SP); in **client tenants** the SP only ever gets access transitively via the central group.

### 3.4 Data schema

The central table `GuardrailsTenantsCompliance_CL` follows the same `_s` / `_b` / `_d` / `_g` suffix convention as the per-tenant Guardrails LAW tables. Every column projected by the DCR transform is also declared on the table schema in `setup/IaC/modules/law.bicep` — if you add fields to the transform you **must** also add them to the table schema, otherwise LAW silently drops them.

Key columns:

| Column | Type | Source |
|---|---|---|
| `TimeGenerated` | datetime | Injected by `Send-GuardrailsData` |
| `ControlName_s` | string | Per-control identifier (`GUARDRAIL 1: …`) |
| `ItemName_s` | string | Sub-check label |
| `Status_s` | string | `Compliant` / `Non-Compliant` / `Not Applicable` |
| `ComplianceStatus_b` | bool | Derived: `Compliant=true`, `Non-Compliant=false`, `Not Applicable=null` |
| `Count_d` | real | Number of items matching the row |
| `Required_s` | string | `True` / `False` (mandatory vs recommended) |
| `Profile_d` | real | Cloud usage profile |
| `ITSG_Control_s` | string | Mapped ITSG control |
| `DepartmentName_s`, `DepartmentNumber_s`, `TenantDomain_s` | string | Department identifiers |
| `DepartmentTenantID_g` | guid | Client tenant id |
| `AggregationTenantID_s`, `AggregationTenantName_s`, `AggregationTenantUPN_s` | string | Aggregation principal context |
| `DeployedVersion_s`, `AvailableVersion_s`, `UpdatedNeeded_b` | mixed | Client-side accelerator version |

### 3.5 How HTTP vs Timer functions differ

| | `grfunchttp` (HTTP-trigger) | `grtimerfunction` (Timer-trigger) |
|---|---|---|
| Auth | Function key in URL (`?code=…`) | None — internal trigger |
| When | On demand (testing, manual run, smoke tests) | Cron schedule in `grtimerfunction/function.json` |
| Body | None used (parameters ignored) | None |
| Logic | Calls `get-tenantdata -DebugInfo:$true -LogType GuardrailsTenantsCompliance` | Calls the same function |
| Use it for | Verifying a deployment | Production-mode collection |

---

## 4. Operations cheatsheet

### Inspect Function App logs

```powershell
# Recent invocation traces
az functionapp logs tail --name <function-name> --resource-group <rg>
```

Or in the portal: **Function App → Functions → grfunchttp → Monitor**.

### Force a fresh run

```powershell
$code = '<function-key>'
Invoke-WebRequest -Uri "https://<function-name>.azurewebsites.net/api/grfunchttp?code=$code" -UseBasicParsing
```

### Rotate the aggregation SP secret

1. Generate a new client secret on the App Registration in the SSC tenant.
2. Update the Key Vault secret:

   ```powershell
   Set-AzKeyVaultSecret -VaultName <kv-name> -Name SecurePassword `
     -SecretValue (ConvertTo-SecureString '<new-secret>' -AsPlainText -Force)
   ```

3. Restart the Function App (the secret is read on every cold start).

### Re-create the DCR after schema changes

If `streamDeclarations` or the destination table schema needs to be widened or narrowed, re-run `setup.ps1`. The DCR is `kind: 'Direct'` and idempotent. If you need a brand-new immutable id, delete the DCR first:

```powershell
Remove-AzDataCollectionRule -ResourceGroupName <rg> -Name guardrails-cv-dcr -Force
.\setup.ps1 -configFilePath .\config.json
```

After re-create, the Function App's `DCR_IMMUTABLE_ID` app setting is automatically refreshed by Bicep.

---

## 5. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `401 Unauthorized` when calling the HTTP function URL | `function.json` has `authLevel: function`; missing `?code=` | Append the function key (portal → Function App → Functions → grfunchttp → Function Keys). |
| `400 Bad Request — InvalidStream` from `Send-GuardrailsData` | Stream name mismatch, or a PowerShell `[switch]` parameter accidentally passed as positional `$LogType` (e.g. `-DebugInfo $true` rather than `-DebugInfo:$true`). | Use colon syntax for switches; verify stream name matches `streamDeclarations` exactly. |
| `400 Bad Request — InvalidTransformQuery` mentioning `column_ifexists` | DCR transform KQL uses an unsupported function. | Replace with direct column reference; declare optional fields as `string` in `streamDeclarations`. |
| Table only shows `TimeGenerated` / `Type` / `TenantId` | Output table missing column declarations that the transform projects. | Add the missing columns to the table schema in `setup/IaC/modules/law.bicep`. |
| Function logs show `ContainerNotFound` on first start | Storage account missing `azure-webjobs-hosts` / `azure-webjobs-secrets` or content share. | Already fixed in `setup/IaC/modules/function.bicep` (containers + share declared explicitly + `dependsOn`). Re-run `setup.ps1`. |
| `Set-AzKeyVaultSecret … Timeout waiting for token from portal` during `setup.ps1` | Running in Cloud Shell signed into a different home tenant than the target tenant. | Switch the portal directory to the target tenant **before** opening Cloud Shell, or run from local PowerShell with `Connect-AzAccount -Tenant <target>`. |
| `RequestDisallowedByPolicy — SSC-SPC Lockdown Network` | Tenant policy blocks public-network storage / KV. | Request a policy exemption for the CentralView RG (see §1.5), or add private endpoints + VNet integration (not in current templates). |
| `Connect-AzAccount … ClientSecretCredential authentication failed` in Function logs | Aggregation SP secret expired or wrong tenant. | Rotate the secret (§4) and update the Key Vault secret. |
| Lighthouse-delegated subscriptions invisible to Resource Graph, or LAW queries return zero rows in CentralView even though the client LAW has data | The aggregation SP is **not a member of the central security group** that the client's Lighthouse offer delegates to. The Lighthouse delegation targets the **group**, not the SP, so without membership the SP has no effective `Log Analytics Reader` rights in client tenants. | In the SSC enterprise tenant: **Entra ID → Groups → `<central-group>` → Members → Add** → select the aggregation SP. Wait ~5 minutes for replication, then re-run. |
| Client tenant never appears in CentralView output at all | Client never deployed the Lighthouse offer, **or** they deployed it with a different `lighthousePrincipalId` (group object id). | Verify the client ran `Deploy-GuardrailsSolutionAccelerator -newComponents CentralizedCustomerReportingSupport` and that their `config.json` `lighthousePrincipalId` matches the central group object id you intend to use. Confirm with `Get-AzManagedServicesAssignment -Scope "/subscriptions/<client-sub-id>"`. |
| Workbook shows nothing | Either no Lighthouse delegations are in place, or no Guardrails data has yet been ingested in the central LAW. | Run a manual ingestion (§4 "Force a fresh run") and re-check after 2–3 minutes. |

---

## 6. File layout

```
tools/CentralView/
├── README.md                                       ← this document
├── grfunchttp/                                     HTTP-trigger function
│   ├── function.json
│   └── run.ps1
├── grtimerfunction/                                Timer-trigger function
│   ├── function.json
│   └── run.ps1
├── Modules/ingest-tenantsData/
│   └── ingest-tenantsData.psm1                     Core aggregation + Send-GuardrailsData
├── requirements.psd1                               Managed dependencies (Az.* major-version wildcards)
└── setup/
    ├── setup.ps1                                   Orchestrates deployment
    ├── config.json                                 Per-deployment inputs (sample)
    ├── tags.json                                   SSC-mandated tags
    └── IaC/
        ├── grfunc.bicep                            Top-level Bicep module
        └── modules/
            ├── law.bicep                           LAW + table + DCR + Workbook + saved searches
            ├── function.bicep                      Function App + plan + storage containers/share
            ├── keyvault.bicep                      Key Vault + initial WorkspaceId/StorageAccountName secrets
            ├── centralview-dcr-ingestion-rbac.bicep DCR Monitoring Metrics Publisher → aggregation SP
            └── law-centralview-tenantscompliance-transform.kql
                                                    DCR transform KQL (loaded by law.bicep)
```

---

## 7. Related documents
- Microsoft Docs:
  - [Logs Ingestion API overview](https://learn.microsoft.com/azure/azure-monitor/logs/logs-ingestion-api-overview)
  - [Data Collection Rule structure](https://learn.microsoft.com/azure/azure-monitor/essentials/data-collection-rule-structure)
  - [Azure Lighthouse — onboard a subscription](https://learn.microsoft.com/azure/lighthouse/how-to/onboard-customer)
