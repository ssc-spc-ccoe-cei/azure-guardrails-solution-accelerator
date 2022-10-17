param (
    [Parameter(Mandatory = $true)]
    [string]
    $configFilePath,
    [Parameter(Mandatory = $false)]
    [string]
    $existingKeyVaultName,
    # Configure lighthouse delegation - requires lighthousePrincipalDisplayName, lighthousePrincipalDisplayName, and lighthouseServiceProviderTenantID in config.json
    [Parameter(Mandatory = $false)]
    [switch]
    $configureLighthouseAccessDelegation,
    [Parameter(Mandatory = $false)]
    [string]
    $existingKeyVaultRG,
    [Parameter(Mandatory = $false)]
    [string]
    $existingWorkspaceName,
    [Parameter(Mandatory = $false)]
    [string]
    $existingWorkSpaceRG,
    [Parameter(Mandatory = $false)]
    [switch]
    $skipDeployment,
    # alternate custom powershell modules URL -- use for module development/testing
    [Parameter(mandatory = $false)]
    [uri]
    $alternatePSModulesURL,
    [Parameter(Mandatory = $false)]
    [switch]
    $update,
    [string] $subscriptionId
)
#region Configuration and initialization
#Other Variables
$mainRunbookName = "main"
$RunbookPath = '.\'
$mainRunbookDescription = "Guardrails Main Runbook"
$backendRunbookName = "backend"
$backendRunbookDescription = "Guardrails Backend Runbook"
$tenantId = (Get-AzContext).Tenant.Id

# get tenant default domain - use Graph to support SPNs
$response = Invoke-AzRestMethod -Method get -uri 'https://graph.microsoft.com/v1.0/organization' | Select-Object -expand Content | convertfrom-json -Depth 10
$tenantDomainUPN = $response.value.verifiedDomains | Where-Object {$_.isDefault} | Select-Object -ExpandProperty name # onmicrosoft.com is verified and default by default

#before deploying anything, check if current user can be found.
$begin = get-date
$context = Get-AzContext
If ($context.Account -match '^MSI@') {
    # running in Cloud Shell, finding delegated user ID
    $userId = (Get-AzAdUser -SignedIn).Id
}
ElseIf ($context.Account.Type -eq 'ServicePrincipal') {
    $sp = Get-AzADServicePrincipal -ApplicationId $context.Account.Id
    $userId = $sp.Id
}
Else {
    # running locally
    $userId = $context.Account.Id
}

#region  Template Deployment
# gets tags information from tags.json, including version and release date.
$tags = get-content ./tags.json | convertfrom-json
$tagstable = @{}
$tags.psobject.properties | ForEach-Object { $tagstable[$_.Name] = $_.Value }


Write-Output "Reading Config file:"
try {
    $config = get-content $configFilePath | convertfrom-json
}
catch {
    "Error reading config file."
    break
}
#$tenantIDtoAppend="-"+$($env:ACC_TID).Split("-")[0]
$tenantIDtoAppend = "-" + $((Get-AzContext).Tenant.Id).Split("-")[0]
$randomstoragechars = -join ((97..122) | Get-Random -Count 4 | ForEach-Object { [char]$_ })

$keyVaultName = $config.keyVaultName + $tenantIDtoAppend
$resourcegroup = $config.resourcegroup + $tenantIDtoAppend
$region = $config.region
$logAnalyticsworkspaceName = $config.logAnalyticsworkspaceName + $tenantIDtoAppend
$autoMationAccountName = $config.autoMationAccountName + $tenantIDtoAppend
$bga1 = $config.FirstBreakGlassAccountUPN #Break glass account 1
$bga2 = $config.SecondBreakGlassAccountUPN #Break glass account 2
$PBMMPolicyID = $config.PBMMPolicyID
$AllowedLocationPolicyId = $config.AllowedLocationPolicyId
$DepartmentNumber = $config.DepartmentNumber
$keyVaultRG = $resourcegroup #initially, same RG.
$logAnalyticsWorkspaceRG = $resourcegroup #initially, same RG.
$storageaccountName = "$($config.storageaccountName)$randomstoragechars"
$deployKV = $true
$deployLAW = $true

if ($config.SecurityLAWResourceId.split("/").Count -ne 9 -or $config.HealthLAWResourceId.Split("/").Count -ne 9) {
    Write-Output "Error in SecurityLAWResourceId or HealthLAWResourceId ID. Parameter needs to be a full resource Id. (/subscriptions/<subid>/...)"
    Break
}

# Checks permissions, now for both update and setup
$tenantRootMgmtGroupId = '/providers/Microsoft.Management/managementGroups/{0}' -f $tenantId
Write-Verbose "Checking that user '$userId' has role 'User Access Administrator' or 'Owner' assigned at the root management group scope (id: '$tenantRootMgmtGroupId')"
Write-Verbose "`t Getting role assignments with cmd: Get-AzRoleAssignment -Scope $tenantRootMgmtGroupId -RoleDefinitionName 'User Access Administrator' -ObjectId $userId -ErrorAction Continue"
Write-Verbose "`t Getting role assignments with cmd: Get-AzRoleAssignment -Scope $tenantRootMgmtGroupId -RoleDefinitionName 'Owner' -ObjectId $userId -ErrorAction Continue"
$roleAssignments = @()
$roleAssignments += Get-AzRoleAssignment -Scope $tenantRootMgmtGroupId -RoleDefinitionName 'User Access Administrator' -ObjectId "$userId" -ErrorAction Continue
$roleAssignments += Get-AzRoleAssignment -Scope $tenantRootMgmtGroupId -RoleDefinitionName 'Owner' -ObjectId "$userId" -ErrorAction Continue

Write-Verbose "`t Count of role assignments '$($roleAssignments.Count)'"
if ($roleAssignments.count -eq 0) {
    Write-Error "Specified user ID '$userId' does not have role 'User Access Administrator' or 'Owner' assigned at the root management group scope!"
    Break                                                
}
Else {
    Write-Verbose "`t Sufficent role assignment for current user exists..."
}

#checks if logged in.
$subs = Get-AzSubscription -ErrorAction SilentlyContinue
if (-not($subs)) {
    Connect-AzAccount
}
if ([string]::IsNullOrEmpty($subscriptionId)){
    $subs = Get-AzSubscription -ErrorAction SilentlyContinue
    if ($subs.count -gt 1) {
        Write-output "More than one subscription detected. Current subscription $((get-azcontext).Name)"
        Write-output "Please select subscription for deployment or Enter to keep current one:"
        $i = 1
        $subs | ForEach-Object { Write-output "$i - $($_.Name) - $($_.SubscriptionId)"; $i++ }
        [int]$selection = Read-Host "Select Subscription number: (1 - $($i-1))"
    }
    else { $selection = 0 }
    if ($selection -ne 0) {
        if ($selection -gt 0 -and $selection -le ($i - 1)) { 
            Select-AzSubscription -SubscriptionObject $subs[$selection - 1]
        }
        else {
            Write-output "Invalid selection. ($selection)"
            break
        }
    }
    else {
        Write-host "Keeping current subscription."
    }
}
else {
    Write-Output "Selecting $subcriptionId subscription:"
    try {
        Select-AzSubscription -Subscription $subscriptionId
    }
    catch {
        Write-error "Error selecting provided subscription."
        break
    }
}

Write-Output "Creating bicep parameters file for this deployment."
    $templateParameterObject = @{
        'kvName' = $keyVaultName
        'location' = $region
        'storageAccountName' = $storageaccountName
        'logAnalyticsWorkspaceName' = $logAnalyticsworkspaceName
        'automationAccountName' = $autoMationAccountName
        'subscriptionId' = (Get-AzContext).Subscription.Id
        'PBMMPolicyID' = $PBMMPolicyID
        'deployKV' = $deployKV
        'deployLAW' = $deployLAW
        'AllowedLocationPolicyId' = $AllowedLocationPolicyId
        'DepartmentNumber' = $DepartmentNumber
        'CBSSubscriptionName' = $config.CBSSubscriptionName
        'SecurityLAWResourceId' = $config.SecurityLAWResourceId
        'HealthLAWResourceId' = $config.HealthLAWResourceId
        'releaseVersion' = $tags.ReleaseVersion
        'releasedate' = $tags.ReleaseDate
        'Locale' = $config.Locale
        'tenantDomainUPN' = $tenantDomainUPN
        'lighthouseTargetManagementGroupID' = $config.lighthouseTargetManagementGroupID
    }
    # Adding URL parameter if specified
    If (![string]::IsNullOrEmpty($alternatePSModulesURL)) {
        If ($alternatePSModulesURL -match 'https://github.com/.+?/raw/.*?/psmodules') {
            $templateParameterObject += @{CustomModulesBaseURL = $alternatePSModulesURL }
        }
        Else {
            Write-Error "-alternatePSModulesURL provided, but does not match pattern 'https://github.com/.+?/raw/.*?/psmodules'" -ErrorAction Stop
        }
    }
    Write-Verbose "templateParameterObject: `n$($templateParameterObject | ConvertTo-Json)"

#checks if update or not.
#   # #### #   #   ##### ##### ##### #   # #####
##  # #    #   #   #     #       #   #   # #   #
# # # ###  # # #   ##### ####    #   #   # #####
#  ## #    ## ##       # #       #   #   # #   
#   # #### #   #   ##### #####   #   ##### #   
if (!$update)
{
    #Configuration Variables
    Write-Output "Reading Config file:"
    try {
        $config = get-content $configFilePath | convertfrom-json
    }
    catch {
        "Error reading config file."
        break
    }
    $tenantId = (Get-AzContext).Tenant.Id
    $tenantIDtoAppend = "-" + $tenantId.Split("-")[0]
    $keyVaultName = $config.keyVaultName + $tenantIDtoAppend
    $resourcegroup = $config.resourcegroup + $tenantIDtoAppend
    $region = $config.region

    #lighthouse config variables
    $lighthouseServiceProviderTenantID = $config.lighthouseServiceProviderTenantID
    $lighthousePrincipalDisplayName = $config.lighthousePrincipalDisplayName
    $lighthousePrincipalId = $config.lighthousePrincipalId
    $lighthouseTargetManagementGroupID = $config.lighthouseTargetManagementGroupID
    If ($configureLighthouseAccessDelegation.isPresent) {
        # verify input from config.json
        if ([string]::IsNullOrEmpty($lighthouseServiceProviderTenantID) -or !($lighthouseServiceProviderTenantID -as [guid])) {
            Write-Error "Lighthouse delegation cannot be configured when config.json parameter 'lighthouseServiceProviderTenantID' has a value of '$lighthouseServiceProviderTenantID'"
            break
        }
        if ([string]::IsNullOrEmpty($lighthousePrincipalDisplayName)) {
            Write-Error "Lighthouse delegation cannot be configured when config.json parameter 'lighthousePrincipalDisplayName' has a value of '$lighthousePrincipalDisplayName'"
            break
        }
        if ([string]::IsNullOrEmpty($lighthousePrincipalId) -or !($lighthousePrincipalId -as [guid])) {
            Write-Error "Lighthouse delegation cannot be configured when config.json parameter 'lighthousePrincipalId' has a value of '$lighthousePrincipalId'"
            break
        }
        if ([string]::IsNullOrEmpty($lighthouseTargetManagementGroupID)) {
            Write-Error "Lighthouse delegation cannot be configured when config.json parameter 'lighthouseTargetManagementGroupID' has a value of '$lighthouseTargetManagementGroupID'"
            break
        }

        # check that user has correct permissions if deploying to tenant root mgmt group
        if ($lighthouseTargetManagementGroupID -eq (Get-AzContext).Tenant.Id) {
            Write-Verbose "lighthouseTargetManagementGroupID is the tenant root managment group, which requires explicit owner permissions for the exeucting user; verifying..."

            $existingAssignment = Get-AzRoleAssignment -Scope '/' -RoleDefinitionName Owner -UserPrincipalName (get-azaduser -SignedIn).UserPrincipalName | Where-Object {$_.Scope -eq '/'}
            If (!$existingAssignment) {
                Write-Error "In order to deploy resources at the Tenant Root Management Group '$lighthouseTargetManagementGroupID', the exeucting user must be explicitly granted Owner 
                rights at the root level. To create this role assignment, run 'New-AzRoleAssignment -Scope '/' -RoleDefinitionName Owner -UserPrincipalName $((get-azaduser -SignedIn).UserPrincipalName)' 
                then execute this script again. This role assignment only needs to exist during the Lighthouse resource deployments and can (and should) be removed after this script completes."
                Exit
            }
        }

        If ($lighthouseTargetManagementGroupID -eq (Get-AzContext).Tenant.Id) {
            $assignmentScopeMgmtmGroupId = '/'
        }
        Else {
            $assignmentScopeMgmtmGroupId = $lighthouseTargetManagementGroupID
        }

        # check if a lighthouse defender for cloud policy MSI role assignment already exists - assignment name always 2cb8e1b1-fcf1-439e-bab7-b1b8b008c294 
        Write-Verbose "Checking for role assignments at management group '$assignmentScopeMgmtmGroupId' for role 'Owner'"
        $uri = 'https://management.azure.com/providers/Microsoft.Management/managementGroups/{0}/providers/Microsoft.Authorization/roleAssignments/{1}?&api-version=2015-07-01' -f $lighthouseTargetManagementGroupID,'2cb8e1b1-fcf1-439e-bab7-b1b8b008c294'
        $roleAssignments = Invoke-AzRestMethod -Uri $uri -Method GET | Select-Object -Expand Content | ConvertFrom-Json
        If ($roleAssignments.id) {
            Write-Verbose "role assignment: $(($roleAssignments).id)"
            Write-Error "A role assignment exists with the name '2cb8e1b1-fcf1-439e-bab7-b1b8b008c294' at the Management group '$lighthouseTargetManagementGroupID'. This was likely
            created by a previous Guardrails deployment and must be removed. Navigate to the Managment Group in the Portal and delete the Owner role assignment listed as 'Identity Not Found'"
            Exit
        }

        # check if lighthouse Custom-RegisterLighthouseResourceProvider exists at a different scope
        Write-Verbose "Checking for existing role definitions with name 'Custom-RegisterLighthouseResourceProvider'"
        $roleDef = Get-AzRoleDefinition -Name 'Custom-RegisterLighthouseResourceProvider'
        $targetAssignableScope = "/providers/Microsoft.Management/managementGroups/$lighthouseTargetManagementGroupID"
        
        Write-Verbose "Found '$($roleDef.count)' role definitions with name 'Custom-RegisterLighthouseResourceProvider'. Verifying assignable scopes includes '$targetAssignableScope'"
        If ($roleDef -and $roleDef.AssignableScopes -notcontains $targetAssignableScope) {
            Write-Error "Role definition name 'Custom-RegisterLighthouseResourceProvider' already exists and has an assignable scope of '$($roleDef.AssignableScopes)'. Assignable scopes
            should include '$targetAssignableScope'. Delete the role definition (and any assignments) and run the script again."
            Exit
        }

        # check if a lighthouse Azure Automation MSI role assignment to register the Lighthouse resource provider already exists - assignment name always  5de3f84b-8866-4432-8811-24859ccf8146
        Write-Verbose "Checking for role assignments at management group '$assignmentScopeMgmtmGroupId' for role 'Custom-RegisterLighthouseResourceProvider'"
        $uri = 'https://management.azure.com/providers/Microsoft.Management/managementGroups/{0}/providers/Microsoft.Authorization/roleAssignments/{1}?&api-version=2015-07-01' -f $lighthouseTargetManagementGroupID, '5de3f84b-8866-4432-8811-24859ccf8146'
        $roleAssignments = Invoke-AzRestMethod -Uri $uri -Method GET | Select-Object -Expand Content | ConvertFrom-Json   
        If ($roleAssignments.id) {  
            Write-Verbose "role assignment: $(($roleAssignments).id)"  
            Write-Error "A role assignment exists with the name '5de3f84b-8866-4432-8811-24859ccf8146' at the Management group '$lighthouseTargetManagementGroupID'. This was likely
            created by a previous Guardrails deployment and must be removed. Navigate to the Managment Group in the Portal and delete the 'Custom-RegisterLighthouseResourceProvider' role assignment listed as 'Identity Not Found'"
            Exit
        }
    }

    #config item validation
    Write-Verbose "Checking that the provided resource ID for SecurityLAWResourceId is valid..."
    if ($config.SecurityLAWResourceId.split("/").Count -ne 9) {
        Write-Error "Error in SecurityLAWResourceId. Parameter needs to be a full resource Id. (/subscriptions/<subid>/...)"
        Break
    }
    Write-Verbose "Checking that the provided resource ID for HealthLAWResourceId is valid..."
    if ($config.HealthLAWResourceId.Split("/").Count -ne 9) {
        Write-Error "Error in HealthLAWResourceId ID. Parameter needs to be a full resource Id. (/subscriptions/<subid>/...)"
        Break
    }

    $context = Get-AzContext
    If ($context.Account -match '^MSI@') {
        # running in Cloud Shell, finding delegated user ID
        $userId = (Get-AzAdUser -SignedIn).Id
    }
    ElseIf ($context.Account.Type -eq 'ServicePrincipal') {
        $sp = Get-AzADServicePrincipal -ApplicationId $context.Account.Id
        $userId = $sp.Id
    }
    Else {
        # running locally
        $userId = $context.Account.Id
    }
    $tenantRootMgmtGroupId = '/providers/Microsoft.Management/managementGroups/{0}' -f $tenantId
    Write-Verbose "Checking that user '$userId' has role 'User Access Administrator' or 'Owner' assigned at the root management group scope (id: '$tenantRootMgmtGroupId')"
    Write-Verbose "`t Getting role assignments with cmd: Get-AzRoleAssignment -Scope $tenantRootMgmtGroupId -RoleDefinitionName 'User Access Administrator' -ObjectId $userId -ErrorAction Continue"
    Write-Verbose "`t Getting role assignments with cmd: Get-AzRoleAssignment -Scope $tenantRootMgmtGroupId -RoleDefinitionName 'Owner' -ObjectId $userId -ErrorAction Continue"
    $roleAssignments = @()
    $roleAssignments += Get-AzRoleAssignment -Scope $tenantRootMgmtGroupId -RoleDefinitionName 'User Access Administrator' -ObjectId "$userId" -ErrorAction Continue
    $roleAssignments += Get-AzRoleAssignment -Scope $tenantRootMgmtGroupId -RoleDefinitionName 'Owner' -ObjectId "$userId" -ErrorAction Continue

    Write-Verbose "`t Count of role assignments '$($roleAssignments.Count)'"
    if ($roleAssignments.count -eq 0) {
        Write-Error "Specified user ID '$userId' does not have role 'User Access Administrator' or 'Owner' assigned at the root management group scope!"
        Break                                                
    }
    Else {
        Write-Verbose "`t Sufficent role assignment for current user exists..."
    }
    #Tests if logged in:
    Write-Verbose "Verifying that the user is logged in and that the correct subscription is selected..."
    $subs = Get-AzSubscription -ErrorAction SilentlyContinue
    if (-not($subs)) {
        Connect-AzAccount
    }
    if ([string]::IsNullOrEmpty($subscriptionId)){
        $subs = Get-AzSubscription -ErrorAction SilentlyContinue
        if ($subs.count -gt 1) {
            Write-output "More than one subscription detected. Current subscription $((get-azcontext).Name)"
            Write-output "Please select subscription for deployment or Enter to keep current one:"
            $i = 1
            $subs | ForEach-Object { Write-output "$i - $($_.Name) - $($_.SubscriptionId)"; $i++ }
            [int]$selection = Read-Host "Select Subscription number: (1 - $($i-1))"
        }
        else { $selection = 0 }
        if ($selection -ne 0) {
            if ($selection -gt 0 -and $selection -le ($i - 1)) { 
                Select-AzSubscription -SubscriptionObject $subs[$selection - 1]
            }
            else {
                Write-output "Invalid selection. ($selection)"
                break
            }
        }
        else {
            Write-host "Keeping current subscription."
        }
    }
    else {
        Write-Output "Selecting $subcriptionId subscription:"
        try {
            Select-AzSubscription -Subscription $subscriptionId | Out-Null
        }
        catch {
            Write-error "Error selecting provided subscription."
            break
        }
    }
    #region Let's deal with existing stuff...
    # Keyvault first
    if (!([string]::IsNullOrEmpty($existingKeyVaultName))) {
        Write-Output "Will try to use an existing Keyvault."
        $keyVaultName = $existingKeyVaultName
        $keyVaultRG = $existingKeyVaultRG
        $deployKV = 'false'
    }
    #log analytics now...
    if (!([string]::IsNullOrEmpty($existingWorkspaceName))) {
        Write-Output "Will try to use an existing Log Analytics workspace."
        $logAnalyticsworkspaceName = $existingWorkspaceName
        $logAnalyticsWorkspaceRG = $existingWorkSpaceRG
        $deployLAW = 'false' #it will be passed to bicep.
    }
    #endregion
    #Storage verification
    Write-Verbose "Verifying that storage account name '$storageAccountName' is available"
    if ((Get-AzStorageAccountNameAvailability -Name $storageaccountName).NameAvailable -eq $false) {
        Write-Error "Storage account $storageaccountName not available."
        break
    }
    Else {
        Write-Verbose "Storage account name '$storageAccountName' is available"
    }
    if ($storageaccountName.Length -gt 24 -or $storageaccountName.Length -lt 3) {
        Write-Error "Storage account name must be between 3 and 24 lowercase characters."
        break
    }
    #endregion
    #region keyvault verification
    $kvContent = ((Invoke-AzRest -Uri "https://management.azure.com/subscriptions/$((Get-AzContext).Subscription.Id)/providers/Microsoft.KeyVault/checkNameAvailability?api-version=2021-11-01-preview" `
                -Method Post -Payload "{""name"": ""$keyVaultName"",""type"": ""Microsoft.KeyVault/vaults""}").Content | ConvertFrom-Json).NameAvailable
    if (!($kvContent) -and $deployKV) {
        write-output "Error: keyvault name $keyVaultName is not available."
        break
    }
    #endregion
    #before deploying anything, check if current user can be found.
    $begin = get-date

    #region  Template Deployment
    # gets tags information from tags.json, including version and release date.
    $tags = get-content ./tags.json | convertfrom-json
    $tagstable = @{}
    $tags.psobject.properties | ForEach-Object { $tagstable[$_.Name] = $_.Value }

    Write-Verbose "Creating $resourceGroup in $region location."
    try {
        New-AzResourceGroup -Name $resourceGroup -Location $region -Tags $tagstable -ErrorAction Stop | Out-Null
    }
    catch { 
        throw "Error creating resource group. $_" 
    }
    Write-Output "Deploying solution through bicep."
    try { 
        $mainBicepDeployment = New-AzResourceGroupDeployment -ResourceGroupName $resourcegroup -Name "guardraildeployment$(get-date -format "ddmmyyHHmmss")" `
            -TemplateParameterObject $templateParameterObject -TemplateFile .\guardrails.bicep -WarningAction SilentlyContinue -ErrorAction Stop
    }
    catch {
        Write-error "Failed to deploy main Guardrails Accelerator template with error: $_" 
        Exit
    }
    $guardrailsAutomationAccountMSI = $mainBicepDeployment.Outputs.guardrailsAutomationAccountMSI.value
    #endregion

    #region lighthouse configuration
    If ($configureLighthouseAccessDelegation.isPresent) {
        #build lighthouse parameter object for resource group delegation
        $bicepParams = @{
            'rgName' = $resourcegroup
            'managedByTenantId' = $lighthouseServiceProviderTenantID
            'managedByName' = 'SSC CSPM - Read Guardrail Status'
            'managedByDescription' = 'SSC CSPM - Read Guardrail Status'
            'authorizations' = @(
                @{
                    'principalIdDisplayName' = $lighthousePrincipalDisplayName
                    'principalId' = $lighthousePrincipalId
                    'roleDefinitionId' = 'acdd72a7-3385-48ef-bd42-f606fba81ae7' # Reader
                }
                @{
                    "principalId" = $lighthousePrincipalId
                     "roleDefinitionId" = "43d0d8ad-25c7-4714-9337-8ba259a9fe05"
                     "principalIdDisplayName" = $lighthousePrincipalDisplayName
                }
                @{
                    'principalIdDisplayName' = $lighthousePrincipalDisplayName
                    'principalId' = $lighthousePrincipalId
                    'roleDefinitionId' = '91c1777a-f3dc-4fae-b103-61d183457e46' # Managed Services Registration assignment Delete Role
                }
            )
        }

        #deploy Guardrails resource group permission delegation
        try {
            $null = New-AzDeployment -Location $region `
                -TemplateFile ./lighthouse/lighthouse_rg.bicep `
                -TemplateParameterObject $bicepParams `
                -ErrorAction Stop
        }
        catch {
            Write-Error "Failed to deploy lighthouse delegation template with error: $_"
            break
        }

        #build parameter object for subscription Defender for Cloud access delegation
        $bicepParams = @{
            'managedByTenantId' = $lighthouseServiceProviderTenantID
            'location' = $region
            'managedByName' = 'SSC CSPM - Defender for Cloud Access'
            'managedByDescription' = 'SSC CSPM - Defender for Cloud Access'
            'managedByAuthorizations' = @(
                @{
                    'principalIdDisplayName' = $lighthousePrincipalDisplayName
                    'principalId' = $lighthousePrincipalId
                    'roleDefinitionId' = '91c1777a-f3dc-4fae-b103-61d183457e46' # Managed Services Registration assignment Delete Role
                }
                @{
                    'principalIdDisplayName' = $lighthousePrincipalDisplayName
                    'principalId' = $lighthousePrincipalId
                    'roleDefinitionId' = '39bc4728-0917-49c7-9d2c-d95423bc2eb4' # Security Reader
                }
            )
        }

        #deploy a custom role definition at the lighthouseTargetManagementGroupID, which will later be used to grant the Automation Account MSI permissions to register the Lighthouse Resource Provider
        try {
            $roleDefinitionDeployment = New-AzManagementGroupDeployment -ManagementGroupId $lighthouseTargetManagementGroupID `
                -Location $region `
                -TemplateFile ./lighthouse/lighthouse_registerRPRole.bicep `
                -Confirm:$false `
                -ErrorAction Stop
        }
        catch {
            Write-Error "Failed to deploy lighthouse resource provider registration custom role template with error: $_"
            break
        }
        $lighthouseRegisterRPRoleDefinitionID = $roleDefinitionDeployment.Outputs.roleDefinitionId.value

        #deploy Guardrails Defender for Cloud permission delegation - this delegation adds a role assignment to every subscription under the target management group
        try {
            $policyDeployment = New-AzManagementGroupDeployment -ManagementGroupId $lighthouseTargetManagementGroupID `
                -Location $region `
                -TemplateFile ./lighthouse/lighthouseDfCPolicy.bicep `
                -TemplateParameterObject $bicepParams `
                -Confirm:$false `
                -ErrorAction Stop
        }
        catch {
            If ($_.Exception.message -like "*Status Message: Principal * does not exist in the directory *. Check that you have the correct principal ID.*") {
                Write-Warning "Deployment role assignment failed due to AAD replication delay, attempting to proceed with role assignment anyway..."
            }
            Else {
                Write-Error "Failed to deploy Lighthouse Defender for Cloud delegation by Azure Policy template with error: $_"
                break
            }
        }

        ### wait up to 5 minutes to ensure AAD has time to propagate MSI identities before assigning a roles ###
        $i = 0
        do {
            Write-Verbose "Waiting for Policy assignment MSI to be available..."
            Start-Sleep 5

            $i++
            If ($i -gt '60') {
                Write-Error "[$i/60]Timeout while waiting for MSI '$($policyDeployment.Outputs.policyAssignmentMSIRoleAssignmentID.value)' to exist in Azure AD"
                break
            }
        }
        until ((Get-AzADServicePrincipal -id $policyDeployment.Outputs.policyAssignmentMSIRoleAssignmentID.value -ErrorAction SilentlyContinue))

        # deploy an 'Owner' role assignment for the MSI associated with the Policy Assignment created in the previous step
        # Owner rights are required so that the MSI can then assign the requested 'Security Reader' role on each subscription under the target management group
        try {
            $null = New-AzManagementGroupDeployment -ManagementGroupId $lighthouseTargetManagementGroupID `
                -Location $region `
                -TemplateFile ./lighthouse/lighthouseDfCPolicyRoleAssignment.bicep `
                -TemplateParameterObject @{policyAssignmentMSIPrincipalID = $policyDeployment.Outputs.policyAssignmentMSIRoleAssignmentID.value} `
                -Confirm:$false `
                -ErrorAction Stop
        }
        catch {
            Write-Error "Failed to deploy template granting the Defender for Cloud delegation policy rights to configure role assignments with error: $_"
            break   
        } 

        # deploy a custom role assignment, granting the Automation Account MSI permissions to register the Lighthouse resource provider on each subscription under the target management group
        try {
            $null = New-AzManagementGroupDeployment -ManagementGroupId $lighthouseTargetManagementGroupID `
                -Location $region `
                -TemplateFile ./lighthouse/lighthouse_assignRPRole.bicep `
                -TemplateParameterObject @{lighthouseRegisterRPRoleDefinitionID = $lighthouseRegisterRPRoleDefinitionID; guardrailsAutomationAccountMSI = $guardrailsAutomationAccountMSI } `
                -Confirm:$false `
                -ErrorAction Stop
        }
        catch {
            Write-Error "Failed to deploy template granting the Azure Automation account rights to register the Lighthouse resource provider with error: $_"
            break   
        } 

        ### TO DO ### The remediation task created by the Bicep template should be all that is required, but does not seem to execute
        try{
            $ErrorActionPreference = 'Stop'
            $null = Start-AzPolicyRemediation -Name Redemdiation -ManagementGroupName $lighthouseTargetManagementGroupID -PolicyAssignmentId $policyDeployment.Outputs.policyAssignmentId.value
        }
        catch {
            Write-Error "Failed to create Remediation Task for policy assignment '$($policyDeployment.Outputs.policyAssignmentId.value)' with the following error: $_"
        }
    }
    #endregion

    #Add current user as a Keyvault administrator (for setup)
    try { $kv = Get-AzKeyVault -ResourceGroupName $keyVaultRG -VaultName $keyVaultName } catch { "Error fetching KV object. $_"; break }
    try { $null = New-AzRoleAssignment -ObjectId $userId -RoleDefinitionName "Key Vault Administrator" -Scope $kv.ResourceId }catch { "Error assigning permissions to KV. $_"; break }
    Write-Output "Sleeping 30 seconds to allow for permissions to be propagated."
    Start-Sleep -Seconds 30
    #region Secret Setup
    # Adds keyvault secret user permissions to the Automation account
    Write-Verbose "Adding automation account Keyvault Secret User."
    try {
        New-AzRoleAssignment -ObjectId $guardrailsAutomationAccountMSI -RoleDefinitionName "Key Vault Secrets User" -Scope $kv.ResourceId
    }
    catch {
        "Error assigning permissions to Automation account (for keyvault). $_"
        break
    }

    Write-Verbose "Adding workspacekey secret to keyvault."
    try {
        $workspaceKey = (Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $logAnalyticsWorkspaceRG -Name $logAnalyticsworkspaceName).PrimarySharedKey
        $secretvalue = ConvertTo-SecureString $workspaceKey -AsPlainText -Force 
        $secret = Set-AzKeyVaultSecret -VaultName $keyVaultName -Name "WorkSpaceKey" -SecretValue $secretvalue
    }
    catch { "Error adding WS secret to KV. $_"; break }
    #endregion
    #region Copy modules definition to recently created Storage account
    import-module "../src/Guardrails-Common/GR-Common.psm1"
    copy-toBlob -FilePath ./modules.json -storageaccountName $storageaccountName -resourcegroup $resourceGroup -force -containerName "configuration"
    #endregion

    #region Import main runbook
    Write-Verbose "Importing Runbook." #main runbook, runs the modules.
    try {
        Import-AzAutomationRunbook -Name $mainRunbookName -Path "$Runbookpath\main.ps1" -Description $mainRunbookDescription -Type PowerShell -Published `
            -ResourceGroupName $resourcegroup -AutomationAccountName $autoMationAccountName -Tags @{version = $tags.ReleaseVersion }
        #Create schedule
        New-AzAutomationSchedule -ResourceGroupName $resourcegroup -AutomationAccountName $autoMationAccountName -Name "GR-Every6hours" -StartTime (get-date).AddHours(1) -HourInterval 6
        #Register
        Register-AzAutomationScheduledRunbook -Name $mainRunbookName -ResourceGroupName $resourcegroup -AutomationAccountName $autoMationAccountName -ScheduleName "GR-Every6hours"
    }
    catch {
        "Error importing Runbook. $_"
        break
    }
    #endregion
    #region Import main runbook
    Write-Verbose "Importing Backend Runbook." #backend runbooks. gets information about tenant, version and itsgcontrols.
    try {
        Import-AzAutomationRunbook -Name $backendRunbookName -Path "$Runbookpath\backend.ps1" -Description "Backend Runbook" -Type PowerShell -Published `
            -ResourceGroupName $resourcegroup -AutomationAccountName $autoMationAccountName -Tags @{version = $tags.ReleaseVersion }
        #Create schedule for backend runbook
        New-AzAutomationSchedule -ResourceGroupName $resourcegroup -AutomationAccountName $autoMationAccountName -Name "GR-Daily" -StartTime (get-date).AddHours(1) -HourInterval 24
        #Register
        Register-AzAutomationScheduledRunbook -Name $backendRunbookName -ResourceGroupName $resourcegroup -AutomationAccountName $autoMationAccountName -ScheduleName "GR-Daily"
    }
    catch {
        "Error importing Runbook. $_"
        break
    }
    #endregion
    #region Other secrects
    #Breakglass accounts and UPNs
    try {
        $ErrorActionPreference = 'Stop'

        $secretvalue = ConvertTo-SecureString $bga1 -AsPlainText -Force 
        $secret = Set-AzKeyVaultSecret -VaultName $keyVaultName -Name "BGA1" -SecretValue $secretvalue
        $secretvalue = ConvertTo-SecureString $bga2 -AsPlainText -Force 
        $secret = Set-AzKeyVaultSecret -VaultName $keyVaultName -Name "BGA2" -SecretValue $secretvalue
    }
    catch {
        "Error adding Breakglass secrets to KeyVault. $_"
        break
    }
    #endregion
    
    try {
        #region Assign permissions>
        $graphAppId = "00000003-0000-0000-c000-000000000000"
        $graphAppSP = Get-AzADServicePrincipal -ApplicationId $graphAppId
        $appRoleIds = @("Organization.Read.All", "User.Read.All", "UserAuthenticationMethod.Read.All", "Policy.Read.All")

        foreach ($approleidName in $appRoleIds) {
            Write-Output "Adding permission to $approleidName"
            $appRoleId = ($graphAppSP.AppRole | Where-Object { $_.Value -eq $approleidName }).Id
            if ($null -ne $approleid) {
                try {
                    $body = @{
                        "principalId" = $guardrailsAutomationAccountMSI
                        "resourceId" = $graphAppSP.Id
                        "appRoleId" = $appRoleId
                    } | ConvertTo-Json

                    $uri = "https://graph.microsoft.com/v1.0/servicePrincipals/{0}/appRoleAssignments" -f $guardrailsAutomationAccountMSI
                    $response = Invoke-AzRest -Method POST -Uri $uri -Payload $body -ErrorAction Stop
                }
                catch {
                    Write-Error "Error assigning permissions $approleid to $approleidName. $_"
                    Break
                }

                If ([int]($response.StatusCode) -gt 299) {
                    Write-Error "Error assigning permissions $approleid to $approleidName. $($response.Error)"
                    Break
                }
            }
            else {
                Write-Output "App Role Id $approleidName ID Not found... :("
            }
        }
        
    }
    catch {
        "Error assigning permissions to graph API. $_"
        break 
    }
    #endregion
    try {
        Write-Output "Assigning reader access to the Automation Account Managed Identity for MG: $($rootmg.DisplayName)"
        $rootmg = get-azmanagementgroup | ? { $_.Id.Split("/")[4] -eq (Get-AzContext).Tenant.Id }

        New-AzRoleAssignment -ObjectId $guardrailsAutomationAccountMSI -RoleDefinitionName Reader -Scope $rootmg.Id
        New-AzRoleAssignment -ObjectId $guardrailsAutomationAccountMSI -RoleDefinitionName "Reader and Data Access" -Scope (Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageaccountName).Id
        New-AzRoleAssignment -ObjectId $guardrailsAutomationAccountMSI -RoleDefinitionName Reader -Scope /providers/Microsoft.aadiam
    }
    catch {
        "Error assigning root management group permissions. $_"
        break
    }
    Write-Output "Waiting 60 seconds to allow for management group permissions to be applied."
    Start-Sleep -Seconds 60
    try {
        Start-AzAutomationRunbook -Name "main" -AutomationAccountName $autoMationAccountName -ResourceGroupName $resourcegroup
    }
    catch { 
        "Error starting runbook. $_"
    }
    try {
        Start-AzAutomationRunbook -Name "backend" -AutomationAccountName $autoMationAccountName -ResourceGroupName $resourcegroup
    }
    catch { 
        "Error starting runbook. $_"
    }
    $timetaken = ((get-date) - $begin) 
    "Time to deploy: $([Math]::Round($timetaken.TotalMinutes,0)) Minutes."
}
else {
#  # #### ###  #### #### ####
#  # #  # #  # #  #  ##  #
#  # #### #  # ####  ##  ###
#  # #    #  # #  #  ##  #
#### #    ###  #  #  ##  ###
    #Configuration Variables
    Write-Output "Update selected!"
    Write-Output "Reading Existing config file:"
    try {
        $config = get-content $configFilePath | convertfrom-json
    }
    catch {
        "Error reading config file."
        break
    }
    $storageaccountname=(Get-AzAutomationVariable -ResourceGroupName $resourceGroup -AutomationAccountName $autoMationAccountName | Where-Object {$_.Name -eq "StorageAccountName"}).value 
    $keyVaultRG = $resourcegroup #initially, same RG.
    $logAnalyticsWorkspaceRG = $resourcegroup #initially, same RG.
    $deployKV = 'false' # it is an update, so, don't change KV.
    $deployLAW = 'true'
    $bga1 = $config.FirstBreakGlassAccountUPN #Break glass account 1
    $bga2 = $config.SecondBreakGlassAccountUPN #Break glass account 2
    $PBMMPolicyID = $config.PBMMPolicyID
    $AllowedLocationPolicyId = $config.AllowedLocationPolicyId
    $DepartmentNumber = $config.DepartmentNumber
    if ($config.SecurityLAWResourceId.split("/").Count -ne 9 -or $config.HealthLAWResourceId.Split("/").Count -ne 9) {
        Write-Output "Error in SecurityLAWResourceId or HealthLAWResourceId ID. Parameter needs to be a full resource Id. (/subscriptions/<subid>/...)"
        Break
    }

    #Storage verification - need to find existing storage.
    if ((Get-AzStorageAccountNameAvailability -Name $storageaccountName).NameAvailable -eq $false) {
        Write-Output "Storage account $storageaccountName found. This is good news!"    
    }
    else {
        "Specified Storage account not found."
    }
    #endregion
    #region bicep deployment
    $templateParameterObject.storageAccountName=$storageaccountname #needs to set this again since it is an update.
    Write-Verbose "Checking if $resourceGroup in $region location already exists."
    try {
        Get-AzResourceGroup -Name $resourceGroup -Location $region
    }
    catch { 
        throw "Error fetching resource group. $_"
        break 
    }
    #removing any saved search in the gr_functions category since an incremental deployment fails...
    $grfunctions=(Get-AzOperationalInsightsSavedSearch -ResourceGroupName $resourcegroup -WorkspaceName $logAnalyticsworkspaceName).Value | where {$_.Properties.Category -eq 'gr_functions'}
    $grfunctions | ForEach-Object { Remove-AzOperationalInsightsSavedSearch -ResourceGroupName $resourcegroup -WorkspaceName $logAnalyticsworkspaceName -SavedSearchId $_.Name}

    Write-Output "(Re)Deploying solution through bicep."
    try { 
        New-AzResourceGroupDeployment -ResourceGroupName $resourcegroup -Name "guardraildeployment$(get-date -format "ddmmyyHHmmss")" `
            -TemplateParameterObject $templateParameterObject -TemplateFile .\guardrails.bicep -WarningAction SilentlyContinue
    }
    catch {
        Write-error "Error deploying solution to Azure. $_"
    }
    #endregion
    #region Import updated main runbook
    Write-Output "Importing updated Runbooks."
    Import-AzAutomationRunbook -Name $mainRunbookName -Path ./main.ps1 -AutomationAccountName $autoMationAccountName -ResourceGroupName $resourcegroup `
     -Force -Type PowerShell -Description "$mainRunbookDescription V.$newversion" -Tags @{version=$tags.ReleaseVersion; releaseDate=$tags.ReleaseDate} -Published 
    Import-AzAutomationRunbook -Name $backendRunbookName -Path ./backend.ps1 -AutomationAccountName $autoMationAccountName -ResourceGroupName $resourcegroup `
     -Force -Type PowerShell -Description "$backendRunbookDescription V.$newversion" -Tags @{version=$tags.ReleaseVersion; releaseDate=$tags.ReleaseDate} -Published 
    
    #uploads new modules.json
    import-module "../src/Guardrails-Common/GR-Common.psm1"
    Write-Output "Updating modules.json file."
    copy-toBlob -FilePath ./modules.json -resourcegroup $resourceGroup -storageaccountName $storageaccountname -containerName "configuration" -force
     #expand all modules to temp folder
        
    #endregion

    #region Other secrects
    #endregion

    Write-Output "Updating Tags."
    $rg=Get-AzResourceGroup -name $resourceGroup
    update-AzTag @{releaseversion=$tags.ReleaseVersion; releaseDate=$tags.ReleaseDate} -ResourceId $rg.ResourceId -Operation Merge
    $resources=Get-AzResource -ResourceGroupName $resourcegroup 
    foreach ($r in $resources)
    {
        update-AzTag @{releaseVersion=$tags.ReleaseVersion; releaseDate=$tags.ReleaseDate} -ResourceId $r.ResourceId -Operation Merge
    }
    $timetaken = ((get-date) - $begin) 
    "Time to update: $([Math]::Round($timetaken.TotalMinutes,0)) Minutes."
}
    
