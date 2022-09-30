param (
    [Parameter(Mandatory = $true)]
    [string]
    $configFilePath,
    [Parameter(Mandatory = $true)]
    [string]
    $userId,
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
    #$tenantIDtoAppend="-"+$($env:ACC_TID).Split("-")[0]
    $tenantIDtoAppend = "-" + $((Get-AzContext).Tenant.Id).Split("-")[0]
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
    if ($config.SecurityLAWResourceId.split("/").Count -ne 9 -or $config.HealthLAWResourceId.Split("/").Count -ne 9) {
        Write-Output "Error in SecurityLAWResourceId or HealthLAWResourceId ID. Parameter needs to be a full resource Id. (/subscriptions/<subid>/...)"
        Break
    }
    if ( $null -eq (Get-AzRoleAssignment | Where-Object { $_.RoleDefinitionName -eq "User Access Administrator"`
                -and $_.SignInName -eq $userId -and $_.Scope -eq "/" })) {
        Write-Output $userId + " doesn't have Access Management for Azure Resource permissions,please refer to the requirements section in the setup document"
        Break                                                
    }
    #Tests if logged in:
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
    Write-Verbose "Adding current user as a Keyvault administrator (for setup)."
    if ($userId -eq "") {
        $currentUserId = (get-azaduser -SignedIn).Id 
    }
    else {
        $currentUserId = (get-azaduser -UserPrincipalName $userId).Id
    }
    if ($null -eq $currentUserId) {
        Write-Error "Error: no current user could be found in current Tenant. Context: $((Get-AzAdUser -SignedIn).UserPrincipalName). Override specified: $userId."
        break;
    }
    $tenantDomainUPN=$userId.Split("@")[1]
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

        ### wait 30 seconds to ensure AAD has time to propagate MSI identities before assigning a roles ###
        Start-Sleep -Seconds 30

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
    try { $null = New-AzRoleAssignment -ObjectId $currentUserId -RoleDefinitionName "Key Vault Administrator" -Scope $kv.ResourceId }catch { "Error assigning permissions to KV. $_"; break }
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

        #region Assign permissions
        $GraphAppId = "00000003-0000-0000-c000-000000000000"
        Write-Output "Adding Permissions to Automation Account - Managed Identity"
        import-module AzureAD.Standard.Preview
        AzureAD.Standard.Preview\Connect-AzureAD -Identity -TenantID $env:ACC_TID
        $MSI = (Get-AzureADServicePrincipal -Filter "displayName eq '$autoMationAccountName'")
        #Start-Sleep -Seconds 10
        $graph = Get-AzureADServicePrincipal -Filter "appId eq '$GraphAppId'"
        $appRoleIds = @("Organization.Read.All", "User.Read.All", "UserAuthenticationMethod.Read.All", "Policy.Read.All")
        foreach ($approleidName in $appRoleIds) {
            Write-Output "Adding permission to $approleidName"
            $approleid = ($graph.AppRoles | Where-Object { $_.Value -eq $approleidName }).Id
            if ($null -ne $approleid) {
                try {
                    New-AzureAdServiceAppRoleAssignment -ObjectId $MSI.ObjectId -PrincipalId $MSI.ObjectId -ResourceId $graph.ObjectId -Id $approleid
                }
                catch {
                    "Error assigning permissions $approleid to $approleidName. $_"
                }
            }
            else {
                Write-Output "App Role Id $approleid Not found... :("
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
    Write-Verbose "Adding current user as a Keyvault administrator (for setup)."
    if ($userId -eq "") {
        $currentUserId = (get-azaduser -UserPrincipalName (Get-AzAccessToken).UserId).Id 
    }
    else {
        $currentUserId = (get-azaduser -UserPrincipalName $userId).Id
    }
    if ($null -eq $currentUserId) {
        Write-Error "Error: no current user could be found in current Tenant. Context: $((Get-AzAccessToken).UserId). Override specified: $userId."
        break;
    }
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
# MIIntwYJKoZIhvcNAQcCoIInqDCCJ6QCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBiA03Gl93anbbn
# +YonJrM/LHn0BvMFeqXU/B1LQcICqqCCDYEwggX/MIID56ADAgECAhMzAAACzI61
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
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZjDCCGYgCAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAsyOtZamvdHJTgAAAAACzDAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQglN0EJ2Ht
# pCH7jZdbKrx291G2/9fKXpAIjHoxfMVLxY8wQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQCJ+ZyOeG4VJyOpT3MfGc4cIKnApVYvgzOXYogxwiw/
# /s5E+4JfOmtthmGW5tkPx1rNrEwr5h0zRhZr2qhgDkzkrbKx0Bqci18EDSHPJl21
# yJWdU5dPi0wFf3mBA3PdWT1bhVN2rKzreQEo6bnaAohIijN/vuPRgWFkAmEgorny
# QxNv4mM3M9O0sp4Gsrg2grF6i5wZ4+OzycCOH8Kvwq425IrGt+lD+313wb9LNWal
# KIzWd34r2UPiolxSUQ5kqLreGqgB0uXC/NVWGYUVl+PlnJ4MaM9AnDccoYEGJaN9
# v+CshBXvPBH51Hf9FNPKz8N3WDRM7in5R9HmdwCB0eUNoYIXFjCCFxIGCisGAQQB
# gjcDAwExghcCMIIW/gYJKoZIhvcNAQcCoIIW7zCCFusCAQMxDzANBglghkgBZQME
# AgEFADCCAVkGCyqGSIb3DQEJEAEEoIIBSASCAUQwggFAAgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIJ/533LE9x4mBQGJhXfNSsp56ggK/73gETCt+KY+
# NbtOAgZjEWDk2YwYEzIwMjIwOTE1MjIxMzA5LjM3OFowBIACAfSggdikgdUwgdIx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1p
# Y3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhh
# bGVzIFRTUyBFU046MkFENC00QjkyLUZBMDExJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WgghFlMIIHFDCCBPygAwIBAgITMwAAAYZ45RmJ+CRL
# zAABAAABhjANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDAeFw0yMTEwMjgxOTI3MzlaFw0yMzAxMjYxOTI3MzlaMIHSMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQg
# SXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1Mg
# RVNOOjJBRDQtNEI5Mi1GQTAxMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAwI3G2Wpv
# 6B4IjAfrgfJpndPOPYO1Yd8+vlfoIxMW3gdCDT+zIbafg14pOu0t0ekUQx60p7Pa
# dH4OjnqNIE1q6ldH9ntj1gIdl4Hq4rdEHTZ6JFdE24DSbVoqqR+R4Iw4w3GPbfc2
# Q3kfyyFyj+DOhmCWw/FZiTVTlT4bdejyAW6r/Jn4fr3xLjbvhITatr36VyyzgQ0Y
# 4Wr73H3gUcLjYu0qiHutDDb6+p+yDBGmKFznOW8wVt7D+u2VEJoE6JlK0EpVLZus
# dSzhecuUwJXxb2uygAZXlsa/fHlwW9YnlBqMHJ+im9HuK5X4x8/5B5dkuIoX5lWG
# jFMbD2A6Lu/PmUB4hK0CF5G1YaUtBrME73DAKkypk7SEm3BlJXwY/GrVoXWYUGEH
# yfrkLkws0RoEMpoIEgebZNKqjRynRJgR4fPCKrEhwEiTTAc4DXGci4HHOm64EQ1g
# /SDHMFqIKVSxoUbkGbdKNKHhmahuIrAy4we9s7rZJskveZYZiDmtAtBt/gQojxbZ
# 1vO9C11SthkrmkkTMLQf9cDzlVEBeu6KmHX2Sze6ggne3I4cy/5IULnHZ3rM4ZpJ
# c0s2KpGLHaVrEQy4x/mAn4yaYfgeH3MEAWkVjy/qTDh6cDCF/gyz3TaQDtvFnAK7
# 0LqtbEvBPdBpeCG/hk9l0laYzwiyyGY/HqMCAwEAAaOCATYwggEyMB0GA1UdDgQW
# BBQZtqNFA+9mdEu/h33UhHMN6whcLjAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoG
# CCsGAQUFBwMIMA0GCSqGSIb3DQEBCwUAA4ICAQDD7mehJY3fTHKC4hj+wBWB8544
# uaJiMMIHnhK9ONTM7VraTYzx0U/TcLJ6gxw1tRzM5uu8kswJNlHNp7RedsAiwviV
# QZV9AL8IbZRLJTwNehCwk+BVcY2gh3ZGZmx8uatPZrRueyhhTTD2PvFVLrfwh2li
# DG/dEPNIHTKj79DlEcPIWoOCUp7p0ORMwQ95kVaibpX89pvjhPl2Fm0CBO3pXXJg
# 0bydpQ5dDDTv/qb0+WYF/vNVEU/MoMEQqlUWWuXECTqx6TayJuLJ6uU7K5QyTkQ/
# l24IhGjDzf5AEZOrINYzkWVyNfUOpIxnKsWTBN2ijpZ/Tun5qrmo9vNIDT0lobgn
# ulae17NaEO9oiEJJH1tQ353dhuRi+A00PR781iYlzF5JU1DrEfEyNx8CWgERi90L
# KsYghZBCDjQ3DiJjfUZLqONeHrJfcmhz5/bfm8+aAaUPpZFeP0g0Iond6XNk4YiY
# bWPFoofc0LwcqSALtuIAyz6f3d+UaZZsp41U4hCIoGj6hoDIuU839bo/mZ/AgESw
# GxIXs0gZU6A+2qIUe60QdA969wWSzucKOisng9HCSZLF1dqc3QUawr0C0U41784K
# o9vckAG3akwYuVGcs6hM/SqEhoe9jHwe4Xp81CrTB1l9+EIdukCbP0kyzx0WZzte
# eiDN5rdiiQR9mBJuljCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUw
# DQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhv
# cml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg
# 4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aO
# RmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41
# JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5
# LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL
# 64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9
# QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj
# 0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqE
# UUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0
# kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435
# UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB
# 3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTE
# mr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwG
# A1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93
# d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNV
# HSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNV
# HQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo
# 0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29m
# dC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5j
# cmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDAN
# BgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4
# sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th54
# 2DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRX
# ud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBew
# VIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0
# DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB62FD+Cljd
# QDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFr
# DZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFh
# bHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7n
# tdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+
# oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6Fw
# ZvKhggLUMIICPQIBATCCAQChgdikgdUwgdIxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJh
# dGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046MkFENC00Qjky
# LUZBMDExJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoB
# ATAHBgUrDgMCGgMVAAGu2DRzWkKljmXySX1korHL4fMnoIGDMIGApH4wfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZIhvcNAQEFBQACBQDmzarQMCIY
# DzIwMjIwOTE1MjE0NDQ4WhgPMjAyMjA5MTYyMTQ0NDhaMHQwOgYKKwYBBAGEWQoE
# ATEsMCowCgIFAObNqtACAQAwBwIBAAICDkEwBwIBAAICEZEwCgIFAObO/FACAQAw
# NgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgC
# AQACAwGGoDANBgkqhkiG9w0BAQUFAAOBgQAqu5tbHLJpYYPKqs23GWAlJhu2huSH
# wonZvOCJh1tgVhf9V1M3XkJlN2/GL/eQLjLRbuaRd2m7y1qHk23KslL5DgklTCHd
# ciemFywazzIebWkyqqh7NhEs/1iMGvaCKQ7f4kfrA+d1kq06jGND1EpOE89pUMqO
# ult+QnAOmnNupDGCBA0wggQJAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAABhnjlGYn4JEvMAAEAAAGGMA0GCWCGSAFlAwQCAQUAoIIBSjAa
# BgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEICX3FxNM
# kbNOqwmyBnnJrogjyAiCNzkPRrvVKfYktF30MIH6BgsqhkiG9w0BCRACLzGB6jCB
# 5zCB5DCBvQQgGpmI4LIsCFTGiYyfRAR7m7Fa2guxVNIw17mcAiq8Qn4wgZgwgYCk
# fjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
# Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAYZ45RmJ+CRLzAAB
# AAABhjAiBCAM7/9+Nx3qXVsNd3nSssdRUZrx30kLQMoYlkrqE5o8XDANBgkqhkiG
# 9w0BAQsFAASCAgCGNPxsEmJXIrqAWWo7yhYQci4Fn3Ll6LWE/Qr7bMXN6Ck5Ge8F
# FlixJHbbIHEMmDb6cV28FxiBYHlm94mdU0WTSnsxOVTOjE9k4eUeXxGp5d+MU0Gh
# pTTczwApsBOL1aaBYJWBeI5Sz9MBYSW01FJMnocxa3wpVbMO3r54qEuPnkUqcAVT
# kYuCQSuZNrnhW2AmNY8EdTOirhQHluCb94qrBHeje8EEHSHVbWcHjYgzpr8APVJD
# a6e+0UFegFUPdd5uuD3ILvQuS7L4aGMP64a6AU0qqgPFHgo7AFNYDi9GLOb8ORTi
# gx1ytIf6pM3/W3SFBtlxNfTXnWzRVgifY/k01KGBePgnYgQjjKVz2bKQzCjOCiWP
# ltaFYc9U4xgY9KZhh2+d9MRdVvlBtNrohX7SvYMS7CLJzXOm7xpatPZJ10L5x+B8
# e0VBGr7Ec3ZDfKwIbwCZdv1eJnWh4sbS3IxqPCETxY4qtyPX0+hJFxxeO+Rdfznp
# U+6dSTsierKzGVZKxlVH/4K2GZp5BlSs0Z5vtCuUmSSPYh398lf3G4q9UZPK8vDP
# DQcG+9M/fsfaGpN0dvGrhHF9FIHfpPy8+Y2fb1bs7RnK3rZoXWISOnguUHyfZoEY
# SXALaiYQLtxj5k2QM63bsTizOZuGX0hzwjrAzftWJt6/pr+L3ms8JCFjag==
# SIG # End signature block
