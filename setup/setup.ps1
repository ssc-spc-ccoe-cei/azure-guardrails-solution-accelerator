param (
    [Parameter(Mandatory = $true)]
    [string]
    $configFilePath,
    [Parameter(Mandatory = $false)]
    [string]
    $userId = '',
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

# test
if (!$update)
{
    #Configuration Variables
    $randomstoragechars = -join ((97..122) | Get-Random -Count 4 | ForEach-Object { [char]$_ })
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
    $storageaccountName = "$($config.storageaccountName)$randomstoragechars"
    $logAnalyticsworkspaceName = $config.logAnalyticsworkspaceName + $tenantIDtoAppend
    $autoMationAccountName = $config.autoMationAccountName + $tenantIDtoAppend
    $keyVaultRG = $resourcegroup #initially, same RG.
    $logAnalyticsWorkspaceRG = $resourcegroup #initially, same RG.
    $deployKV = 'true'
    $deployLAW = 'true'
    $bga1 = $config.FirstBreakGlassAccountUPN #Break glass account 1
    $bga2 = $config.SecondBreakGlassAccountUPN #Break glass account 2
    $PBMMPolicyID = $config.PBMMPolicyID
    $AllowedLocationPolicyId = $config.AllowedLocationPolicyId
    $DepartmentNumber = $config.DepartmentNumber

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
    if ((Get-AzStorageAccountNameAvailability -Name $storageaccountName).NameAvailable -eq $false) {
        Write-Error "Storage account $storageaccountName not available."
        break
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

    $tenantDomainUPN = Get-AzTenant -TenantId $tenantId | Select-Object -Expand DefaultDomain

    #region  Template Deployment
    # gets tags information from tags.json, including version and release date.
    $tags = get-content ./tags.json | convertfrom-json
    $tagstable = @{}
    $tags.psobject.properties | Foreach { $tagstable[$_.Name] = $_.Value }

    Write-Output "Creating bicep parameters file for this deployment."
    $parameterTemplate = get-content .\parameters_template.json
    $parameterTemplate = $parameterTemplate.Replace("%kvName%", $keyVaultName)
    $parameterTemplate = $parameterTemplate.Replace("%location%", $region)
    $parameterTemplate = $parameterTemplate.Replace("%storageAccountName%", $storageaccountName)
    $parameterTemplate = $parameterTemplate.Replace("%logAnalyticsWorkspaceName%", $logAnalyticsworkspaceName)
    $parameterTemplate = $parameterTemplate.Replace("%automationAccountName%", $autoMationAccountName)
    $parameterTemplate = $parameterTemplate.Replace("%subscriptionId%", (Get-AzContext).Subscription.Id)
    $parameterTemplate = $parameterTemplate.Replace("%PBMMPolicyID%", $PBMMPolicyID)
    $parameterTemplate = $parameterTemplate.Replace("%deployKV%", $deployKV)
    $parameterTemplate = $parameterTemplate.Replace("%deployLAW%", $deployLAW)
    $parameterTemplate = $parameterTemplate.Replace("%AllowedLocationPolicyId%", $AllowedLocationPolicyId)
    $parameterTemplate = $parameterTemplate.Replace("%DepartmentNumber%", $DepartmentNumber)
    $parameterTemplate = $parameterTemplate.Replace("%CBSSubscriptionName%", $config.CBSSubscriptionName)
    $parameterTemplate = $parameterTemplate.Replace("%SecurityLAWResourceId%", $config.SecurityLAWResourceId)
    $parameterTemplate = $parameterTemplate.Replace("%HealthLAWResourceId%", $config.HealthLAWResourceId)
    $parameterTemplate = $parameterTemplate.Replace("%version%", $tags.ReleaseVersion)
    $parameterTemplate = $parameterTemplate.Replace("%releasedate%", $tags.ReleaseDate)
    $parameterTemplate = $parameterTemplate.Replace("%Locale%", $config.Locale)
    $parameterTemplate = $parameterTemplate.Replace("%tenantDomainUPN%", $tenantDomainUPN)
    $parameterTemplate = $parameterTemplate.Replace("%lighthouseTargetManagementGroupID%", $lighthouseTargetManagementGroupID)
    #writes the file
    $parameterTemplate | out-file .\parameters.json -Force
    #endregion

    #region bicep deployment

    # create a parameter object for dynamically passing a CustomModulesBaseURL value to bicep
    $templateParameterObject = @{}
    $paramFileContent = Get-Content .\parameters.json | ConvertFrom-Json -Depth 20
    $paramFileContent.parameters | Get-Member -MemberType Properties | ForEach-Object {
        $templateParameterObject += @{ $_.name = $paramFileContent.parameters.$($_.name).value }
    }

    If (![string]::IsNullOrEmpty($alternatePSModulesURL)) {
        If ($alternatePSModulesURL -match 'https://github.com/.+?/raw/.*?/psmodules') {
            $templateParameterObject += @{CustomModulesBaseURL = $alternatePSModulesURL }
        }
        Else {
            Write-Error "-alternatePSModulesURL provided, but does not match pattern 'https://github.com/.+?/raw/.*?/psmodules'" -ErrorAction Stop
        }
    }

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
        $secretvalue = ConvertTo-SecureString $bga1 -AsPlainText -Force 
        $secret = Set-AzKeyVaultSecret -VaultName $keyVaultName -Name "BGA1" -SecretValue $secretvalue
        $secretvalue = ConvertTo-SecureString $bga2 -AsPlainText -Force 
        $secret = Set-AzKeyVaultSecret -VaultName $keyVaultName -Name "BGA2" -SecretValue $secretvalue
        #endregion

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

    #Tests if logged in:
    $subs = Get-AzSubscription -ErrorAction SilentlyContinue
    if (-not($subs)) {
        Connect-AzAccount
        $subs = Get-AzSubscription -ErrorAction SilentlyContinue
    }
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
    
    #$tenantIDtoAppend="-"+$($env:ACC_TID).Split("-")[0]
    $tenantIDtoAppend = "-" + $((Get-AzContext).Tenant.Id).Split("-")[0]
    $keyVaultName = $config.keyVaultName + $tenantIDtoAppend
    $resourcegroup = $config.resourcegroup + $tenantIDtoAppend
    $region = $config.region
    #$storageaccountName = "$($config.storageaccountName)$randomstoragechars"
    $logAnalyticsworkspaceName = $config.logAnalyticsworkspaceName + $tenantIDtoAppend
    $autoMationAccountName = $config.autoMationAccountName + $tenantIDtoAppend
    $storageaccountname=(Get-AzAutomationVariable -ResourceGroupName $resourceGroup -AutomationAccountName $autoMationAccountName | Where-Object {$_.Name -eq "StorageAccountName"}).value 
    $keyVaultRG = $resourcegroup #initially, same RG.
    $logAnalyticsWorkspaceRG = $resourcegroup #initially, same RG.
    $deployKV = 'false' # it is an update, so, don't change LAW or KV.
    $deployLAW = 'false'
    $bga1 = $config.FirstBreakGlassAccountUPN #Break glass account 1
    $bga2 = $config.SecondBreakGlassAccountUPN #Break glass account 2
    $PBMMPolicyID = $config.PBMMPolicyID
    $AllowedLocationPolicyId = $config.AllowedLocationPolicyId
    $DepartmentNumber = $config.DepartmentNumber
    if ($config.SecurityLAWResourceId.split("/").Count -ne 9 -or $config.HealthLAWResourceId.Split("/").Count -ne 9) {
        Write-Output "Error in SecurityLAWResourceId or HealthLAWResourceId ID. Parameter needs to be a full resource Id. (/subscriptions/<subid>/...)"
        Break
    }

    #region Let's deal with existing stuff...
    #Storage verification
    if ((Get-AzStorageAccountNameAvailability -Name $storageaccountName).NameAvailable -eq $false) {
        Write-Output "Storage account $storageaccountName found. This is good news!"    
    }
    else {
        "Specified Storage account not found."
    }
    #endregion
    #before deploying anything, check if current user can be found.
    $begin = get-date
    
    #region  Template Deployment
    # gets tags information from tags.json, including version and release date.
    $tags = get-content ./tags.json | convertfrom-json
    $tagstable = @{}
    $tags.psobject.properties | Foreach { $tagstable[$_.Name] = $_.Value }

    Write-Output "Creating bicep parameters file for this deployment."
    $parameterTemplate = get-content .\parameters_template.json
    $parameterTemplate = $parameterTemplate.Replace("%kvName%", $keyVaultName)
    $parameterTemplate = $parameterTemplate.Replace("%location%", $region)
    $parameterTemplate = $parameterTemplate.Replace("%storageAccountName%", $storageaccountName)
    $parameterTemplate = $parameterTemplate.Replace("%logAnalyticsWorkspaceName%", $logAnalyticsworkspaceName)
    $parameterTemplate = $parameterTemplate.Replace("%automationAccountName%", $autoMationAccountName)
    $parameterTemplate = $parameterTemplate.Replace("%subscriptionId%", (Get-AzContext).Subscription.Id)
    $parameterTemplate = $parameterTemplate.Replace("%PBMMPolicyID%", $PBMMPolicyID)
    $parameterTemplate = $parameterTemplate.Replace("%deployKV%", $deployKV)
    $parameterTemplate = $parameterTemplate.Replace("%deployLAW%", $deployLAW)
    $parameterTemplate = $parameterTemplate.Replace("%AllowedLocationPolicyId%", $AllowedLocationPolicyId)
    $parameterTemplate = $parameterTemplate.Replace("%DepartmentNumber%", $DepartmentNumber)
    $parameterTemplate = $parameterTemplate.Replace("%CBSSubscriptionName%", $config.CBSSubscriptionName)
    $parameterTemplate = $parameterTemplate.Replace("%SecurityLAWResourceId%", $config.SecurityLAWResourceId)
    $parameterTemplate = $parameterTemplate.Replace("%HealthLAWResourceId%", $config.HealthLAWResourceId)
    $parameterTemplate = $parameterTemplate.Replace("%version%", $tags.ReleaseVersion)
    $parameterTemplate = $parameterTemplate.Replace("%releasedate%", $tags.ReleaseDate)
    $parameterTemplate = $parameterTemplate.Replace("%Locale%", $config.Locale)
    #writes the file
    $parameterTemplate | out-file .\parameters.json -Force
    #endregion

    #region bicep deployment

    # create a parameter object for dynamically passing a CustomModulesBaseURL value to bicep
    $templateParameterObject = @{}
    $paramFileContent = Get-Content .\parameters.json | ConvertFrom-Json -Depth 20
    $paramFileContent.parameters | Get-Member -MemberType Properties | ForEach-Object {
        $templateParameterObject += @{ $_.name = $paramFileContent.parameters.$($_.name).value }
    }

    If (![string]::IsNullOrEmpty($alternatePSModulesURL)) {
        $templateParameterObject += @{CustomModulesBaseURL = $alternatePSModulesURL }
    }

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
    $grfunctions | foreach { Remove-AzOperationalInsightsSavedSearch -ResourceGroupName $resourcegroup -WorkspaceName $logAnalyticsworkspaceName -SavedSearchId $_.Name}

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
    
# SIG # Begin signature block
# MIInoQYJKoZIhvcNAQcCoIInkjCCJ44CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDHmL3eTSO+QbWN
# Tf7CMHxaaT1yGl09PVaDoidSaSfNr6CCDYEwggX/MIID56ADAgECAhMzAAACzI61
# lqa90clOAAAAAALMMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjIwNTEyMjA0NjAxWhcNMjMwNTExMjA0NjAxWjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQCiTbHs68bADvNud97NzcdP0zh0mRr4VpDv68KobjQFybVAuVgiINf9aG2zQtWK
# No6+2X2Ix65KGcBXuZyEi0oBUAAGnIe5O5q/Y0Ij0WwDyMWaVad2Te4r1Eic3HWH
# UfiiNjF0ETHKg3qa7DCyUqwsR9q5SaXuHlYCwM+m59Nl3jKnYnKLLfzhl13wImV9
# DF8N76ANkRyK6BYoc9I6hHF2MCTQYWbQ4fXgzKhgzj4zeabWgfu+ZJCiFLkogvc0
# RVb0x3DtyxMbl/3e45Eu+sn/x6EVwbJZVvtQYcmdGF1yAYht+JnNmWwAxL8MgHMz
# xEcoY1Q1JtstiY3+u3ulGMvhAgMBAAGjggF+MIIBejAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUiLhHjTKWzIqVIp+sM2rOHH11rfQw
# UAYDVR0RBEkwR6RFMEMxKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMRYwFAYDVQQFEw0yMzAwMTIrNDcwNTI5MB8GA1UdIwQYMBaAFEhu
# ZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNpZ1BDQTIwMTFfMjAxMS0w
# Ny0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUFBzAChkVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0NvZFNpZ1BDQTIwMTFfMjAx
# MS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAeA8D
# sOAHS53MTIHYu8bbXrO6yQtRD6JfyMWeXaLu3Nc8PDnFc1efYq/F3MGx/aiwNbcs
# J2MU7BKNWTP5JQVBA2GNIeR3mScXqnOsv1XqXPvZeISDVWLaBQzceItdIwgo6B13
# vxlkkSYMvB0Dr3Yw7/W9U4Wk5K/RDOnIGvmKqKi3AwyxlV1mpefy729FKaWT7edB
# d3I4+hldMY8sdfDPjWRtJzjMjXZs41OUOwtHccPazjjC7KndzvZHx/0VWL8n0NT/
# 404vftnXKifMZkS4p2sB3oK+6kCcsyWsgS/3eYGw1Fe4MOnin1RhgrW1rHPODJTG
# AUOmW4wc3Q6KKr2zve7sMDZe9tfylonPwhk971rX8qGw6LkrGFv31IJeJSe/aUbG
# dUDPkbrABbVvPElgoj5eP3REqx5jdfkQw7tOdWkhn0jDUh2uQen9Atj3RkJyHuR0
# GUsJVMWFJdkIO/gFwzoOGlHNsmxvpANV86/1qgb1oZXdrURpzJp53MsDaBY/pxOc
# J0Cvg6uWs3kQWgKk5aBzvsX95BzdItHTpVMtVPW4q41XEvbFmUP1n6oL5rdNdrTM
# j/HXMRk1KCksax1Vxo3qv+13cCsZAaQNaIAvt5LvkshZkDZIP//0Hnq7NnWeYR3z
# 4oFiw9N2n3bb9baQWuWPswG0Dq9YT9kb+Cs4qIIwggd6MIIFYqADAgECAgphDpDS
# AAAAAAADMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMTAeFw0xMTA3MDgyMDU5MDlaFw0yNjA3MDgyMTA5MDla
# MH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMT
# H01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQCr8PpyEBwurdhuqoIQTTS68rZYIZ9CGypr6VpQqrgG
# OBoESbp/wwwe3TdrxhLYC/A4wpkGsMg51QEUMULTiQ15ZId+lGAkbK+eSZzpaF7S
# 35tTsgosw6/ZqSuuegmv15ZZymAaBelmdugyUiYSL+erCFDPs0S3XdjELgN1q2jz
# y23zOlyhFvRGuuA4ZKxuZDV4pqBjDy3TQJP4494HDdVceaVJKecNvqATd76UPe/7
# 4ytaEB9NViiienLgEjq3SV7Y7e1DkYPZe7J7hhvZPrGMXeiJT4Qa8qEvWeSQOy2u
# M1jFtz7+MtOzAz2xsq+SOH7SnYAs9U5WkSE1JcM5bmR/U7qcD60ZI4TL9LoDho33
# X/DQUr+MlIe8wCF0JV8YKLbMJyg4JZg5SjbPfLGSrhwjp6lm7GEfauEoSZ1fiOIl
# XdMhSz5SxLVXPyQD8NF6Wy/VI+NwXQ9RRnez+ADhvKwCgl/bwBWzvRvUVUvnOaEP
# 6SNJvBi4RHxF5MHDcnrgcuck379GmcXvwhxX24ON7E1JMKerjt/sW5+v/N2wZuLB
# l4F77dbtS+dJKacTKKanfWeA5opieF+yL4TXV5xcv3coKPHtbcMojyyPQDdPweGF
# RInECUzF1KVDL3SV9274eCBYLBNdYJWaPk8zhNqwiBfenk70lrC8RqBsmNLg1oiM
# CwIDAQABo4IB7TCCAekwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFEhuZOVQ
# BdOCqhc3NyK1bajKdQKVMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1Ud
# DwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO
# 4eqnxzHRI4k0MFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwubWljcm9zb2Z0
# LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcmwwXgYIKwYBBQUHAQEEUjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcnQwgZ8GA1UdIASBlzCBlDCBkQYJKwYBBAGCNy4DMIGDMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2RvY3MvcHJpbWFyeWNw
# cy5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AcABvAGwAaQBjAHkA
# XwBzAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAGfyhqWY
# 4FR5Gi7T2HRnIpsLlhHhY5KZQpZ90nkMkMFlXy4sPvjDctFtg/6+P+gKyju/R6mj
# 82nbY78iNaWXXWWEkH2LRlBV2AySfNIaSxzzPEKLUtCw/WvjPgcuKZvmPRul1LUd
# d5Q54ulkyUQ9eHoj8xN9ppB0g430yyYCRirCihC7pKkFDJvtaPpoLpWgKj8qa1hJ
# Yx8JaW5amJbkg/TAj/NGK978O9C9Ne9uJa7lryft0N3zDq+ZKJeYTQ49C/IIidYf
# wzIY4vDFLc5bnrRJOQrGCsLGra7lstnbFYhRRVg4MnEnGn+x9Cf43iw6IGmYslmJ
# aG5vp7d0w0AFBqYBKig+gj8TTWYLwLNN9eGPfxxvFX1Fp3blQCplo8NdUmKGwx1j
# NpeG39rz+PIWoZon4c2ll9DuXWNB41sHnIc+BncG0QaxdR8UvmFhtfDcxhsEvt9B
# xw4o7t5lL+yX9qFcltgA1qFGvVnzl6UJS0gQmYAf0AApxbGbpT9Fdx41xtKiop96
# eiL6SJUfq/tHI4D1nvi/a7dLl+LrdXga7Oo3mXkYS//WsyNodeav+vyL6wuA6mk7
# r/ww7QRMjt/fdW1jkT3RnVZOT7+AVyKheBEyIXrvQQqxP/uozKRdwaGIm1dxVk5I
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZdjCCGXICAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAsyOtZamvdHJTgAAAAACzDAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgOl7pyD26
# 9p+al/rqfJkqWG4CAoUFjsMZIngIYAWY2YswQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQA2m+0hTxjFWrZbejcrdSazT9MF+dF7PI3U0iVdsavf
# zhQJL+LjUwq837wWX2CSHRzNumffFh6K11wk2M+DXlGPwr9QP/nlLSkryVokNGFx
# rQMGkwuoMd3rcii6KaLGfbLRLao4SN0LXJSv4h0hxDVWlRLr1rf0lYd0lkSHPOCr
# 2PsN5GfmI8NLzdtprGuvX4uNVHh0HgB50J6rVk9WCyGaqG53J7s0yAt8t5cz7/Lk
# Frc7H3jWzqutob9imkLyZvrZO7NLhblnMHw0Jx1iPP4bESJ7hMlieeva58cyzcpP
# H/rrzFAQXKXwbnzByFiQkPlJrMXPvD8HcZgaBWf9Z1FioYIXADCCFvwGCisGAQQB
# gjcDAwExghbsMIIW6AYJKoZIhvcNAQcCoIIW2TCCFtUCAQMxDzANBglghkgBZQME
# AgEFADCCAVEGCyqGSIb3DQEJEAEEoIIBQASCATwwggE4AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEILwhSZvNVa/bKtI49AO4tNfT3thAkQcE6tZ/+bMW
# IJ/hAgZjIwNPqxQYEzIwMjIxMDA0MTQzOTE0LjE5MlowBIACAfSggdCkgc0wgcox
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1p
# Y3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJjAkBgNVBAsTHVRoYWxlcyBUU1Mg
# RVNOOkREOEMtRTMzNy0yRkFFMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNloIIRVzCCBwwwggT0oAMCAQICEzMAAAGcD6ZNYdKeSygAAQAAAZww
# DQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcN
# MjExMjAyMTkwNTE5WhcNMjMwMjI4MTkwNTE5WjCByjELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2Eg
# T3BlcmF0aW9uczEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046REQ4Qy1FMzM3LTJG
# QUUxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDbUioMGV1JFj+s612s02mKu23KPUNs
# 71OjDeJGtxkTF9rSWTiuA8XgYkAAi/5+2Ff7Ck7JcKQ9H/XD1OKwg1/bH3E1qO1z
# 8XRy0PlpGhmyilgE7KsOvW8PIZCf243KdldgOrxrL8HKiQodOwStyT5lLWYpMsuT
# 2fH8k8oihje4TlpWiFPaCKLnFDaAB0Ccy6vIdtHjYB1Ie3iOZPisquL+vNdCx7gO
# hB8iiTmTdsU8OSUpC8tBTeTIYPzmhaxQZd4moNk6qeCJyi7fiW4fyXdHrZ3otmgx
# xa5pXz5pUUr+cEjV+cwIYBMkaY5kHM9c6dEGkgHn0ZDJvdt/54FOdSG61WwHh4+e
# vUhwvXaB4LCMZIdCt5acOfNvtDjV3CHyFOp5AU/qgAwGftHU9brv4EUwcuteEAKH
# 46NufE20l/WjlNUh7gAvt2zKMjO4zXRxCUTh/prBQwXJiUZeFSrEXiOfkuvSlBni
# yAYYZp5kOnaxfCKdGYjvr4QLA93vQJ6p2Ox3IHvOdCPaCr8LsKVcFpyp8MEhhJTM
# +1LwqHJqFDF5O1Z9mjbYvm3R9vPhkG+RDLKoTpr7mTgkaTljd9xvm94Obp8BD9Hk
# 4mPi51mtgLiuN8/6aZVESVZXtvSuNkD5DnIJQerIy5jaRKW/W2rCe9ngNDJadS7R
# 96GGRl7IIE37lwIDAQABo4IBNjCCATIwHQYDVR0OBBYEFLtpCWdTXY5dtddkspy+
# oxjCA/qyMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRY
# MFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01p
# Y3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEF
# BQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
# a2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAo
# MSkuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZI
# hvcNAQELBQADggIBAKcAKqYjGEczTWMs9z0m7Yo23sgqVF3LyK6gOMz7TCHAJN+F
# vbvZkQ53VkvrZUd1sE6a9ToGldcJnOmBc6iuhBlpvdN1BLBRO8QSTD1433VTj4XC
# Qd737wND1+eqKG3BdjrzbDksEwfG4v57PgrN/T7s7PkEjUGXfIgFQQkr8TQi+/HZ
# Z9kRlNccgeACqlfb4uGPxn5sdhQPoxdMvmC3qG9DONJ5UsS9KtO+bey+ohUTDa9L
# vEToc4Qzy5fuHj2H1JsmCaKG78nXpfWpwBLBxZYSpfml29onN8jcG7KD8nGSS/76
# PDlb2GMQsvv+Ra0JgL6FtGRGgYmHCpM6zVrf4V/a+SoHcC+tcdGYk2aKU5KOlv+f
# FE3n024V+z54tDAKR9z78rejdCBWqfvy5cBUQ9c5+3unHD08BEp7qP2rgpoD856v
# NDgEwO77n7EWT76nl/IyrbK2kjbHLzUMphFpXKnV1fYWJI2+E/0LHvXFGGqF4OvM
# BRxbrJVn03T2Dy5db6s5TzJzSaQvCrXYqA4HKvstQWkqkpvBHTX8M09+/vyRbVXN
# xrPdeXw6oD2Q4DksykCFfn8N2j2LdixE9wG5iilv69dzsvHIN/g9A9+thkAQCVb9
# DUSOTaMIGgsOqDYFjhT6ze9lkhHHGv/EEIkxj9l6S4hqUQyWerFkaUWDXcnZMIIH
# cTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAAAAAAFTANBgkqhkiG9w0BAQsFADCB
# iDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMp
# TWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMjEw
# OTMwMTgyMjI1WhcNMzAwOTMwMTgzMjI1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAOThpkzntHIh
# C3miy9ckeb0O1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDivbk+F2Az/1xPx2b3lVNx
# WuJ+Slr+uDZnhUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU88V29YZQ3MFEyHFc
# UTE3oAo4bo3t1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqYO7oaezOtgFt+jBAc
# nVL+tuhiJdxqD89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzpcGkNyjYtcI4xyDUo
# veO0hyTD4MmPfrVUj9z6BVWYbWg7mka97aSueik3rMvrg0XnRm7KMtXAhjBcTyzi
# YrLNueKNiOSWrAFKu75xqRdbZ2De+JKRHh09/SDPc31BmkZ1zcRfNN0Sidb9pSB9
# fvzZnkXftnIv231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZNN3SUHDSCD/AQ8rdH
# GO2n6Jl8P0zbr17C89XYcz1DTsEzOUyOArxCaC4Q6oRRRuLRvWoYWmEBc8pnol7X
# KHYC4jMYctenIPDC+hIK12NvDMk2ZItboKaDIV1fMHSRlJTYuVD5C4lh8zYGNRiE
# R9vcG9H9stQcxWv2XFJRXRLbJbqvUAV6bMURHXLvjflSxIUXk8A8FdsaN8cIFRg/
# eKtFtvUeh17aj54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB2TASBgkrBgEEAYI3
# FQEEBQIDAQABMCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSavoKRPEY1Kc8Q/y8E7jAd
# BgNVHQ4EFgQUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0gBFUwUzBRBgwrBgEE
# AYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUFBwMI
# MBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMB
# Af8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1Ud
# HwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3By
# b2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQRO
# MEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2Vy
# dHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MA0GCSqGSIb3DQEBCwUAA4IC
# AQCdVX38Kq3hLB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOXPTEztTnXwnE2P9pk
# bHzQdTltuw8x5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjYNi6cqYJWAAOwBb6J6Gng
# ugnue99qb74py27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/zjj3G82jfZfakVqr3
# lbYoVSfQJL1AoL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz/AyeixmJ5/ALaoHC
# gRlCGVJ1ijbCHcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyRgNI95ko+ZjtPu4b6
# MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdUbZ1jdEgssU5HLcEU
# BHG/ZPkkvnNtyo4JvbMBV0lUZNlz138eW0QBjloZkWsNn6Qo3GcZKCS6OEuabvsh
# VGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4Ku+xBZj1p/cvBQUl+
# fpO+y/g75LcVv7TOPqUxUYS8vwLBgqJ7Fx0ViY1w/ue10CgaiQuPNtq6TPmb/wrp
# NPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9vMvpe784cETRkPHI
# qzqKOghif9lwY1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGCAs4wggI3AgEBMIH4
# oYHQpIHNMIHKMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUw
# IwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMSYwJAYDVQQLEx1U
# aGFsZXMgVFNTIEVTTjpERDhDLUUzMzctMkZBRTElMCMGA1UEAxMcTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAzdlp6t3ws/bnErbm
# 9c0M+9dvU0CggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAN
# BgkqhkiG9w0BAQUFAAIFAObmjaUwIhgPMjAyMjEwMDQxODQ3MDFaGA8yMDIyMTAw
# NTE4NDcwMVowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA5uaNpQIBADAKAgEAAgIe
# WgIB/zAHAgEAAgIR8TAKAgUA5uffJQIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgor
# BgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBBQUA
# A4GBAGOp8lVJ5ZWoSqf0a+E6aMxpRJ8yxVYgWmhYVpmI56Yi9x61vdrzQsL5SrtA
# WnWrgXUn4/TGv5UOsCmKweSxQhj0erSzisTmUIhet5eD4Gco4yVei6VeARDbmuCh
# 8sG0MpAMu8tLvtjTPuYTYCKa8l5F7R2PWV+cF9KrTBC7ekYaMYIEDTCCBAkCAQEw
# gZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGcD6ZNYdKeSygA
# AQAAAZwwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0B
# CRABBDAvBgkqhkiG9w0BCQQxIgQgwZMNX/B0VxB6p8khLCmJKc5jGjqgLvh6SfWr
# c5mGSTUwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCA3D0WFII0syjoRd/Xe
# EIG0WUIKzzuy6P6hORrb0nqmvDCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwAhMzAAABnA+mTWHSnksoAAEAAAGcMCIEIKZnsyzHZcfSLVt8Woy6
# 35NuaT53kugLSyWbf74O9poHMA0GCSqGSIb3DQEBCwUABIICADWndYlYKazOP4Mk
# cxl1ROZ7q4g4UF0Ldw0qD4BzCqwcAwllvO4YhS/eHcoRQK3DrZgcDfWDAy+Gwrjb
# T7YFytNCZ5eg5ryVYMbdFPbiQfVr8z6gldygF9HUQQd7XRl1NO9/++pTkuMoDRjN
# Dz4xo0wNGazKcGQvecnW7cnNNr7y0SWKGQrTBt2VXI6RulRdQW1GKDGYDI8viUC6
# 5Nm122RO5WU3YCxHemAnmTEZCg4txiccmjPGjVlANyCopg2crrGdCUCNtiKcaTSU
# +cAnfojfylGO1yQFniCVWXm6rtaDFcbHVfywXL5pn0WMHHymdYxYD4/xjTBs4moH
# 0mc71kWBCylkqOb0VrzmPu/BhtqLBrR4ahq5dESePj6+8H3IRJDIb9bFE/TC1Qa/
# gtLnsZRAITom3U/VJstYwkFYxGrCXaT+0JmR+dtMtjRPuLvTYLd/GnQZu4v/DRnZ
# +MuuKtGOXZ4KsghkDSqsCrsE8Be9CzxlqmqoYDHtW8QzxPgCfNo5FsT0e/C7cUZo
# zI/S9ZVunYZx1ryVsDt7BS4vjbS9PdMkp3mR+Odw9WHe9OvFfVMxwflcdk4wJh2r
# tFIMetltSwUT7eb+1XwG7DSmgH3G7n2lckfXdM61+ZhzYsTDAJZaa2+k86bFoP9e
# dyUVx7r1kr6ZIsXxAe0ME0dB5uCs
# SIG # End signature block
