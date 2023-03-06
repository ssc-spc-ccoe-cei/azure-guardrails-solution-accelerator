# Guardrails - Controls

How the controls work.

## GUARDRAIL 1 PROTECT ROOT  GLOBAL ADMINS ACCOUNT
In this control the solution tries to validate multiple items as follow.

1. #### Break Glass accounts Creation

      The solution will verify the existence of the two Break Glass accounts that you have  entered in the config.json during the setup process.Once the solution detects both accounts the check mark status will be changed from (❌) to (✔️).

2. Break Glass accounts Procedure

      If you have completed the break glass accounts procedure, make sure to upload an empty Text file with the name "BreakGlassAccountProcedure.txt" to the container name "guardrailsstorage" in the storage account created by the setup. this file tell the solution that you have completed this task. please do not upload the break glass account procedure it self, once the solution detects the file,  the check mark status will be changed from (❌) to (✔️).

      ![BreakGlassAccountProcedure.txt uploaded to the storage account](/docs/media/BreakGlassAccountProcedure.png)

3. Break Glass Accounts Owners contacts information
      
      Break Glass Account must be owned by  in the organization, the owner is the manager of the accounts , the solution will verify if the manager information for both Break Glass Accounts is populated, once the solution detects the manager information for both accounts,  the check mark status will be changed from (❌) to (✔️).

      ![BreakGlassAccountProcedure.txt uploaded to the storage account](/docs/media/BreakGlassAccountOwnersContactInformation.png)
      
4. Responsibility of Break Glass accounts 

    After you confirm that the person(s) responsible of the Break Glass accounts is not technical and and has a director level or above make sure to upload an empty Text file with the name "ConfirmBreakGlassAccountResponsibleIsNotTechnical.txt" to the container name "guardrailsstorage" in the storage account created by the setup. this file tells the solution that you have completed this task. Once the solution detects the file,  the check mark status will be changed from (❌) to (✔️).

      ![BreakGlassAccountProcedure.txt uploaded to the storage account](/docs/media/ConfirmBreakGlassAccountResponsibleIsNotTechnical.png)

5. AD License Type

      The module will look for a P2 equivalent licensing, Once the solution find any of the following "String Id",  the check mark status will be changed from (❌) to (✔️).

      * Product name: AZURE ACTIVE DIRECTORY PREMIUM P2,  String ID: AAD_PREMIUM_P2 
      * Product name: ENTERPRISE MOBILITY + SECURITY E5,  String ID: EMSPREMIUM    	
      * Product name: Microsoft 365 E5, 	                String ID: SPE_E5  	

6. Break Glass Accounts Restricted Access 

      The module checks if the multi-factor authentication (MFA) is enable on the break glass account, if MFA is not enabled the check mark status will be changed from (❌) to (✔️).

7. Break Glass Accounts must be created in the tenant Azure Active Directory

      The solution checks if both break glass accounts are member of the Azure Active Directory, and not guest account or from another directory. if the solution finds both break glass accounts are member of the Azure Active Directory it will change the check mark status from (❌) to (✔️).


## GUARDRAIL 2 MANAGEMENT OF ADMINISTRATIVE PRIVILEGES
    
1. Check Deleted and Disabled Users
2. Check Deprecated Accounts
3. Check External User Accounts

## GUARDRAIL 3 CLOUD CONSOLE ACCESS
    
This Module module verifies the following items:
- The existance of at least one Conditional Access Named Location that only contains Canada. If no Location is defined or no locations have just Canada in it, the control will be considered non-Compliant.
- If the above is Compliant, the solution with check if there is at least one conditional access policy that uses any of the Canada only named locations determined before. If no policies with this criteria are found, the control will be considered non-compliant.
- The existence of a file named 'PrivilegedAccountManagementPlan.txt' (case-sensitive) in the Guardrails Solution Accelerator storage account, providing attestation that the organization has the required privileged account management plan documented.

## GUARDRAIL 4 ENTERPRISE MONITORING ACCOUNTS

This modules will look for the existance of an account in the following format:
`"SSC-CBS-Reporting@" + DepartmentNumber + "gc.onmicrosoft.com"`
The Department number is provided as a parameter in the config.json during deployment and can be updated in the Automation Account variables.
If no account is found in Azure AD as per above, the control will be considered non-compliant.


## GUARDRAIL 5 DATA LOCATION

### Check-DataLocation

This Module will verify the existence of an  assignment of the 'Allowed Locations' policy in the multiple subscriptions and management groups. The standard guid for this Policy is:
`e56962a6-4747-49cd-b67b-bf8b01975c4c`. 
If the built-in policy is used for this purpose, no configuration is required. If a custom policy is being used for this purpose (define allowed locations), this guid can be specified in the config.json file during deployment of in the Automation Account variables.

### Check-PBMMPolicy
    
This Module will detect the PBMM Initiative. The detection will happen at the Root Tenant management group and down, looking for all subscriptions and management groups. Any subscription of MG without the applied initial will be marked as non compliant.

The standard guid for this Policy is:
`4c4a5f27-de81-430b-b4e5-9cbd50595a87`. 
If the built-in policy is used for this purpose, no configuration is required. If a custom policy is being used for this purpose (PBMM initiative), this guid can be specified in the config.json file during deployment of in the Automation Account variables.

## GUARDRAIL 6 PROTECTION OF DATA-AT-REST
    
This module will detect the PBMM and look for specific policies not to be exempted. The compliance will fail right away if the PBMM policy is not applied. If applied, the following policies will be checked for exemptions:

- "TransparentDataEncryptionOnSqlDatabasesShouldBeEnabled"
- "DiskEncryptionShouldBeAppliedOnVirtualMachines"

## GUARDRAIL 7 PROTECTION OF DATA-IN-TRANSIT
    
This module will detect the PBMM and look for specific policies not to be exempted. The compliance will fail right away if the PBMM policy is not applied. If applied, the following policies will be checked for exemptions:

- "FunctionAppShouldOnlyBeAccessibleOverHttps"
- "WebApplicationShouldOnlyBeAccessibleOverHttps"
- "ApiAppShouldOnlyBeAccessibleOverHttps"
- "OnlySecureConnectionsToYourRedisCacheShouldBeEnabled"
- "SecureTransferToStorageAccountsShouldBeEnabled"
   

## Guardrails 8  Separation and Segmentation

This module will retrieve the list of subnets in all available VNets (all VNets visible to the managed identity, according to the permissions assigned (Typically, all since permissions are assigned at the Root Management Group level))

For each subnet the following items will be evaluated:

### Segmentation


- Existence of an NSG attached to the subnet.
- In the said NSG, there must be a rule, set as the last rule in the custom rules, and configured to deny all traffic.

If any of the above rules is not true, the subnet will be considered non compliant

### Separation

- Existence of an UDR (Route table) assigned to the subnet
- The UDR must have a default (0.0.0.0/0) route set to a Virtual Appliance.

If any of the above rules is not true, the subnet will be considered not compliant.

#### Exclusion

Subnets can be excluded from the compliance check in four different ways:

Automatically:

- The following subnets are considered reserved and are automatically excluded:
      GatewaySubnet,AzureFirewallSubnet,AzureBastionSubnet,AzureFirewallManagementSubnet,RouteServerSubnet
      This configuration is contained in the 'reservedSubnetList' variable in the Automation Account and can be updated as needed.

The whole VNet:

  - If a tag named "GR8-ExcludeVNetFromCompliance" is found in the VNet, all subnets are ignored.

One or more specific subnets: 

- A tag called "GR-ExcludedSubnets" is found, containing a list of subnets separated by commas, each of those subnets will be excluded from the compliance check.

- A list of subnet names can be provided as a parameter to the module ($ExcludedSubnetsList). All subnets in this list will be excluded from the compliance check, from all VNets.

### Network Architecture Diagram

* If you have created a network diagram and it meets ITSG-33 controls, make sure to upload an empty text file with the name "ConfirmNetworkDiagramExists.txt" to the container name "guardrailsstorage" in the storage account created by the setup. This file tells the solution that you have completed this task. Please do not upload the network diagram itself. Once the solution detects the file, the check mark status will be changed from (❌) to (✔️).

![ConfirmNetworkDiagramExists.txt uploaded to the storage account](/docs/media/ConfirmNetworkDiagramExists.png)


## GUARDRAIL 9 NETWORK SECURITY SERVICES

This module will retrieve the list of all VNets (all VNets visible to the managed identity, according to the permissions assigned (Typically, all since permissions are assigned at the Root Management Group level))

For each VNet the following items will be evaluated.

- DDos Protection set to Standard (*Enabling DDos standard protection on your Azure environment will have a financial impact on your monthly billing*) 

If any of the above rules is not true, the VNet will be considered not compliant.

If the Vnet object containts a tag "GR9-ExcludeVNetFromCompliance" the VNet will be excluded from the compliance check.

## GUARDRAIL 10 CYBER DEFENSE SERVICES
    
  The solution will verify the existence of the [Cyber Defence Services resources](https://github.com/canada-ca/cloud-guardrails/blob/master/EN/10_Cyber-Defense-Services.md) in the dedicated Cyber Defence Services subscription in the config.json during the setup process. Once the solution detects these resources the check mark status will be changed from (❌) to (✔️).
## GUARDRAIL 11 LOGGING AND MONITORING
    
This module will detect the items below:

| Item | Description |
| ----------- | ----------- |
| SECURITY ||
|Create a RG for security monitoring | Implied since the Log Analytics workspace needs to be informed as a parameter |
|Create LAW, Retention needs to be 2 years.|Checks the retention of the provided LAW|
|Workspace summary, add the log types:  activity log analytics. Ensure to add all subscriptions except sandbox|Checks for a data source set to Activity Logs |
|Workspace summary, add, anti-malware assessment|Checks for the presence of the anti-malware solution|
|Workspace summary, add, KeyVault analytics|This solution has been deprecated. KeyVault insights is recommended. **Not being detected at the moment**|
|Create a resource, automation account | Checks for a connected automation account in the provided LAW|
|Go to RG. Select the account, update management, select the LAW and enable| Checks for the Update Management solution in the provided LAW|
|In the tenant, select diagnostic setting. Select the LAW and select audit logs, sigint logs |**TBD - Not functional right now**|
|Need to redirect blueprint to this LAW |**TBD**|
|Go to Azure sentinel and select the LAW and add it to sentinel. Go to data connectors. Add azure activity, office 365 and anything we use |**TBD**|
|HEALTH||
|create a RG for performance and health monitoring. Create LAW, Retention needs to be 90 days.   |Checks for the specific retention in the provided health LAW|
|Workspace summary, add the log types . Make sure to add all subscriptions except sandbox |Right now all subscriptions are tested, **no exceptions.**|
|Workspace summary, add, Azure Log Analytics Agent Health |Checks for the solution|
|Create a resource, automation account |Checks for a connected automation account in the provided LAW|
|Go to RG. Select the account, update management, select the LAW and enable |Checks for the Update Management solution in the provided LAW|
|In the tenant, select diagnostic setting. Select the LAW and select ….. |**TBD**|
|Need to redirect blueprint to this LAW |**TBD**|
|DEFENDER FOR CLOUD||
|Standard tier | Considered compliant if all tiers are enabled.|
|Data collection  -  Send all events |**TBD**|
|Email notification - enter email and phone number (select send email for high severity alerts) | **Any email or telephone** found is considered compliant.|
|Threat detection – enable |**TBD**|

## GUARDRAIL 12 CONFIGURATION OF CLOUD MARKETPLACES
    
The solution will verify if the private market place has been created, Once the solution detects the private market place the check mark status will be changed from (❌) to (✔️).
