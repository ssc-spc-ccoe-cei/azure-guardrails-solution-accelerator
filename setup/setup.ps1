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
# MIInrQYJKoZIhvcNAQcCoIInnjCCJ5oCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAsmi5mEI10dW2O
# JeOhJjCvpRKTKugDGU0Bf3VCj6kiBaCCDYEwggX/MIID56ADAgECAhMzAAACzI61
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
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZgjCCGX4CAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAsyOtZamvdHJTgAAAAACzDAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgDvHqOpHe
# dpUipFeJqtIVrU2kd2uDY/P1Zm23hT2gm54wQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQB1KxYsrkUjJ1C7Gd7IWvuzOg8M5bUedSkFfoiSpTqe
# 13Nf9v2NOqR36qpSF7NFdevCzhQUgtm7BGdGtZyEjcT2zyGkcAqHhwP3GKl8V5oz
# 5fmzuwc15Gclt0np/Y7Z/Zwb3JaJ2BO7pL2i7YLf0cDaYs25X/vF4SDdIvjwD1DC
# HNK022gxsStXfLYW4vYTAOXW4IIbLXQltufKewNj6RDjIGfiJLUjWRWp4dbv/g4b
# RzDpgm31A5zbcTyqBstYYsc6Ope+DRqp/gIVhpn1pLhCuLYnLe1hDP0w7TV5I971
# vxwmS4trDqd4PYuD7eedLSrYolFV9/zPda5H4g9LxoLEoYIXDDCCFwgGCisGAQQB
# gjcDAwExghb4MIIW9AYJKoZIhvcNAQcCoIIW5TCCFuECAQMxDzANBglghkgBZQME
# AgEFADCCAVUGCyqGSIb3DQEJEAEEoIIBRASCAUAwggE8AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEICy/hxnwh0nwK2aWLSdwbxn/vf+NStmYjCWNq6cw
# FOqjAgZjKfNSwMYYEzIwMjIwOTMwMTQwMzA4LjI2OFowBIACAfSggdSkgdEwgc4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1p
# Y3Jvc29mdCBPcGVyYXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMg
# VFNTIEVTTjo4OTdBLUUzNTYtMTcwMTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgU2VydmljZaCCEV8wggcQMIIE+KADAgECAhMzAAABqwkJ76tj1OipAAEA
# AAGrMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# MB4XDTIyMDMwMjE4NTEyOFoXDTIzMDUxMTE4NTEyOFowgc4xCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVy
# YXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjo4OTdB
# LUUzNTYtMTcwMTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vydmlj
# ZTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAMmdS1o5dehASUsscLqy
# x2wm/WirNUfqkGBymDItYzEnoKtkhrd7wNsJs4g+BuM3uBX81WnO270lkrC0e1mm
# DqQt420Tmb8lwsjQKM6mEaNQIfXDronrVN3aw1lx9bAf7VZEA3kHFql6YAO3kjQ6
# PftA4iVHX3JVv98ntjkbtqzKeJMaNWd8dBaAD3RCliMoajTDGbyYNKTvxBhWILyJ
# 8WYdJ/NBDpqPzQl+pxm6ZZVSeBQAIOubZjU0vfpECxHC5vI1ErrqapG+0oBhhON+
# gllVklPAWZv2iv0mgjCTj7YNKX7yL2x2TvrvHVq5GPNa5fNbpy39t5cviiYqMf1R
# ZVZccdr+2vApk5ib5a4O8SiAgPSUwYGoOwbZG1onHij0ATPLkgKUfgaPzFfd5JZS
# bRl2Xg347/LjWQLR+KjAyACFb06bqWzvHtQJTND8Y0j5Y2SBnSCqV2zNHSVts4+a
# UfkUhsKS+GAXS3j5XUgYA7SMNog76Nnss5l01nEX7sHDdYykYhzuQKFrT70XVTZe
# X25tSBfy3VaczYd1JSI/9wOGqbFU52NyrlsA1qimxOhsuds7Pxo+jO3RjV/kC+AE
# OoVaXDdminsc3PtlBCVh/sgYno9AUymblSRmee1gwlnlZJ0uiHKI9q2HFgZWM10y
# PG5gVt0prXnJFi1Wxmmg+BH/AgMBAAGjggE2MIIBMjAdBgNVHQ4EFgQUFFvO8o1e
# NcSCIQZMvqGfdNL+pqowHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIw
# XwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
# cy9jcmwvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3Js
# MGwGCCsGAQUFBwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENB
# JTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcD
# CDANBgkqhkiG9w0BAQsFAAOCAgEAykuUgTc1KMszMgsHbhgjgEGv/dCHFf0by99C
# 45SR770/udCNNeqlT610Ehz13xGFU6Hci+TLUPUnhvUnSuz7xkiWRru5RjZZmSon
# EVv8npa3z1QveUfngtyi0Jd6qlSykoEVJ6tDuR1Kw9xU9yvthZWhQs/ymyOwh+mx
# t0C9wbeLJ92er2vc9ly12pFxbCNDJ+mQ7v520hAvreWqZ02GOJhw0R4c1iP39iNB
# zHOoz+DsO0sYjwhaz9HrvYMEzOD1MJdLPWfUFsZ//iTd3jzEykk02WjnZNzIe2EN
# fmQ/KblGXHeSe8JYqimTFxl5keMfLUELjAh0mhQ1vLCJZ20BwC4O57Eg7yO/YuBn
# o+4RrV0CD2gp4BO10KFW2SQ/MhvRWK7HbgS6Bzt70rkIeSUto7pRkHMqrnhubITc
# Xddky6GtZsmwM3hvqXuStMeU1W5NN3HA8ypjPLd/bomfGx96Huw8OrftcQvk7thd
# Nu4JhAyKUXUP7dKMCJfrOdplg0j1tE0aiE+pDTSQVmPzGezCL42slyPJVXpu4xxE
# 0hpACr2ua0LHv/LB6RV5C4CO4Ms/pfal//F3O+hJZe5ixevzKNkXXbxPOa1R+SIr
# W/rHZM6RIDLTJxTGFDM1hQDyafGu9S/a7umkvilgBHNxZfk0IYE7RRWJcG7oiY+F
# Gdx1cs0wggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3
# DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIw
# MAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAx
# MDAeFw0yMTA5MzAxODIyMjVaFw0zMDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
# 5OGmTOe0ciELeaLL1yR5vQ7VgtP97pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/
# XE/HZveVU3Fa4n5KWv64NmeFRiMMtY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1
# hlDcwUTIcVxRMTegCjhuje3XD9gmU3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7
# M62AW36MEBydUv626GIl3GoPz130/o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3K
# Ni1wjjHINSi947SHJMPgyY9+tVSP3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy
# 1cCGMFxPLOJiss254o2I5JasAUq7vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF80
# 3RKJ1v2lIH1+/NmeRd+2ci/bfV+AutuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQc
# NIIP8BDyt0cY7afomXw/TNuvXsLz1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahha
# YQFzymeiXtcodgLiMxhy16cg8ML6EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkL
# iWHzNgY1GIRH29wb0f2y1BzFa/ZcUlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV
# 2xo3xwgVGD94q0W29R6HXtqPnhZyacaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIG
# CSsGAQQBgjcVAQQFAgMBAAEwIwYJKwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUp
# zxD/LwTuMB0GA1UdDgQWBBSfpxVdAF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBT
# MFEGDCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYI
# KwYBBQUHAwgwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGG
# MA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186a
# GMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3Br
# aS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsG
# AQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcN
# AQELBQADggIBAJ1VffwqreEsH2cBMSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1
# OdfCcTY/2mRsfNB1OW27DzHkwo/7bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYA
# A7AFvonoaeC6Ce5732pvvinLbtg/SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbz
# aN9l9qRWqveVtihVJ9AkvUCgvxm2EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6L
# GYnn8AtqgcKBGUIZUnWKNsIdw2FzLixre24/LAl4FOmRsqlb30mjdAy87JGA0j3m
# Sj5mO0+7hvoyGtmW9I/2kQH2zsZ0/fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0
# SCyxTkctwRQEcb9k+SS+c23Kjgm9swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxko
# JLo4S5pu+yFUa2pFEUep8beuyOiJXk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFm
# PWn9y8FBSX5+k77L+DvktxW/tM4+pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC482
# 2rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7
# vzhwRNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIC0jCC
# AjsCAQEwgfyhgdSkgdEwgc4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1ZXJ0byBSaWNv
# MSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjo4OTdBLUUzNTYtMTcwMTElMCMGA1UE
# AxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUA
# W6h6/24WCo7WZz6CEVAeLztcmD6ggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMDANBgkqhkiG9w0BAQUFAAIFAObg98EwIhgPMjAyMjA5MzAwOTA2
# MDlaGA8yMDIyMTAwMTA5MDYwOVowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA5uD3
# wQIBADAKAgEAAgIFSQIB/zAHAgEAAgIRZzAKAgUA5uJJQQIBADA2BgorBgEEAYRZ
# CgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0G
# CSqGSIb3DQEBBQUAA4GBAB5gFOV4vNU8YCAN8WQPtEXMq8Nk9rlhu/VsMt3UoE2B
# AM9yaVD6H1Syxpfa/+v6fiuO/CdN8IwtyRa4wQ9fAvpg99lZetSK4XQFft/iZT7w
# MLFmu6KicwBI/WDCIc6muLeZWtfCMU1gihNprKHdwfNaSlJSgCFuu1EGxwzJnp2o
# MYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMA
# AAGrCQnvq2PU6KkAAQAAAaswDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJ
# AzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgrrQ3Nl7J9a+SqCIWhNcR
# iIKYRUuM3uHvUlonjua8TJMwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAO
# HK/6sIVgEVSVD3Arvk6OyQKvRxFHKyraUzbN1/AKVzCBmDCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABqwkJ76tj1OipAAEAAAGrMCIEIGY5
# Vfs3e/PasPuPlyEBZaJRdjPQjkmF2XGUdcNSheh9MA0GCSqGSIb3DQEBCwUABIIC
# AJWoLASEtGAy767L0dl6l5Tb1FSajBJ2IDGSP1UeBrtPhYnUWDtjGTwPRTzLgJR8
# U/gkdAbnbx2k2m6v1SCUCbLvI+tzqtK5nktZEc8/2zV8LHJa01zFT9uaTZ8GoaG7
# +cwq+T8iXjPcRrUEbEXjXQiscUvzFDmDJXNXw0Z/zo96ZDEiGRul2UD569QkfhtQ
# oKgqSBhTkN6XI6x2nqqnmy+BzGdiUJrEWiRhlaMhRoFkHi64/bveDOgEyNRO2mST
# N2wvfQ16u7yCWPNxWU3TRpWVWAkn9z23FkG/3SBbX1b+ucDuA/HSngLd1XI+Gj5e
# vDg+qtmELTM6ersMD0gyprgNgpZ56btT2jf32fsHpylaZuxswtvQwLYE6YoZabK1
# oYh9KOHsNjw23o7Et6XyCWwtCYqZtQr+gOBhOlOMJRq3ZhMdGhoo6DUXY2bbQQTv
# u1amtmZu2xb24eYfP83ujHTIeODvnYCLAwHihkNAVy9GG0iU6TXcrXf2dg/tCyJR
# 55SsgGChR1qnrmwBfMC1tN4RunkXoAResMalyxx1Oueq3qLopQNXqTRjDBloshLB
# BC2u0HcGwvdx9JmC8eIuS0rbWJg//81E+ugKCGMx4cpFlIB6PLxvqqcnjjJMol05
# vy19bFudwmf7o+DGScpYsgqhXvOotEDtGLI7wKAJyjM+
# SIG # End signature block
