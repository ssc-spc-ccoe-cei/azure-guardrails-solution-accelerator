Function Remove-GSAExistingDeployment {
    <#
    .SYNOPSIS
        Removes an existing Guardrails Solution Accelerator deployment so that a fresh deployment can proceed.
    .DESCRIPTION
        Intended for CI/CD pipelines that deploy into a subscription where the Guardrails Solution Accelerator was
        previously installed, for example by hand. A fresh deployment fails its prerequisite checks when the earlier
        installation left behind a Lighthouse registration for the managing tenant, Defender for Cloud role
        assignments at the management group, a soft-deleted Key Vault holding the configured name, or the core
        resource group itself. Deleting the resource group by hand is not enough because the Lighthouse and
        management group resources live outside it.

        This function finds the existing deployment, then removes it in the same order the removal commands are
        documented for manual cleanup:
          1. Remove-GSACentralizedReportingCustomerComponents (Lighthouse delegation for the managing tenant)
          2. Remove-GSACentralizedDefenderCustomerComponents (management group role assignments and custom role)
          3. Remove-GSACoreResources (data collection rules, Log Analytics workspace, resource group), waiting for
             the resource group to disappear
          4. Purge of the soft-deleted Key Vault when the new deployment reuses the same Key Vault name

        The existing deployment is located by the resource group name derived from the supplied configuration and
        by resource groups tagged with the Guardrails 'Solution' tag. A resource group is only deleted when it
        shows evidence of being a Guardrails deployment: the Solution tag, an exported configuration secret in its
        Key Vault, or the 'main' and 'backend' runbooks in its Automation Account. When more than one candidate is
        found, the function stops and asks for -existingResourceGroupName, unless -all is specified.

        The Log Analytics workspace and all compliance history it contains are permanently deleted. Use the -update
        flow of Deploy-GuardrailsSolutionAccelerator instead when the existing installation should be kept.
    .PARAMETER config
        Validated configuration hashtable, as returned by Confirm-GSAConfigurationParameters. Used internally by
        Deploy-GuardrailsSolutionAccelerator.
    .PARAMETER configFilePath
        Path to the config.json for the new deployment.
    .PARAMETER configString
        Configuration as a JSON string, for example from Get-GSAExportedConfig.
    .PARAMETER existingResourceGroupName
        Name of the resource group holding the existing deployment. Use this when automatic discovery finds more
        than one candidate or when the existing installation used a different uniqueNameSuffix and is not tagged.
    .PARAMETER newComponents
        Components the new deployment will install. The core resource group is only removed when CoreComponents
        is included. Failures while removing Lighthouse components are terminating only when the matching
        component is about to be redeployed; otherwise they are reported as warnings.
    .PARAMETER all
        Remove every Guardrails deployment discovered in the subscription instead of stopping when more than one is
        found. Intended for CI/CD pipelines whose subscription may hold both the pipeline's previous deployment and a
        manual installation. Each resource group must still pass the evidence check.
    .PARAMETER force
        Skip the confirmation prompt. Required for unattended pipeline execution.
    .EXAMPLE
        Remove-GSAExistingDeployment -configFilePath ./config.json -force
    .EXAMPLE
        # CI/CD: remove the pipeline's previous deployment and any manually installed one before redeploying.
        Remove-GSAExistingDeployment -configFilePath ./config.json -newComponents CoreComponents,CentralizedCustomerReportingSupport -all -force
    .EXAMPLE
        Remove-GSAExistingDeployment -configFilePath ./config.json -existingResourceGroupName guardrails-manual-1234 -force
    .EXAMPLE
        Deploy-GuardrailsSolutionAccelerator -configFilePath ./config.json -newComponents CoreComponents,CentralizedCustomerReportingSupport -removeExistingDeployment -yes
    #>
    [CmdletBinding(DefaultParameterSetName = 'configFile')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'config')]
        [hashtable]
        $config,

        [Parameter(Mandatory = $true, ParameterSetName = 'configFile')]
        [string]
        [Alias('configFileName')]
        $configFilePath,

        [Parameter(Mandatory = $true, ParameterSetName = 'configString', ValueFromPipelineByPropertyName = $true)]
        [string]
        $configString,

        [Parameter(Mandatory = $false)]
        [string]
        $existingResourceGroupName,

        [Parameter(Mandatory = $false)]
        [ValidateSet('CoreComponents', 'CentralizedCustomerReportingSupport', 'CentralizedCustomerDefenderForCloudSupport')]
        [string[]]
        $newComponents = @('CoreComponents'),

        [Parameter(Mandatory = $false)]
        [switch]
        $all,

        [Parameter(Mandatory = $false)]
        [switch]
        $force
    )
    $ErrorActionPreference = 'Stop'

    $modulesRoot = Split-Path $PSScriptRoot -Parent
    # Imported here rather than at module load so this module can be loaded by
    # Deploy-GuardrailsSolutionAccelerator without creating an import cycle.
    # Commands already available (for example from the parent setup module) are reused.
    $dependencies = @{
        'Confirm-GSAConfigurationParameters'               = 'Confirm-GSAConfigurationParameters/Confirm-GSAConfigurationParameters.psd1'
        'Remove-GSACoreResources'                          = 'Remove-GSACoreResources/Remove-GSACoreResources.psd1'
        'Remove-GSACentralizedReportingCustomerComponents' = 'Remove-GSACentralizedReportingCustomerComponents/Remove-GSACentralizedReportingCustomerComponents.psd1'
        'Remove-GSACentralizedDefenderCustomerComponents'  = 'Remove-GSACentralizedDefenderCustomerComponents/Remove-GSACentralizedDefenderCustomerComponents.psd1'
    }
    ForEach ($dependency in $dependencies.GetEnumerator()) {
        If (-not (Get-Command -Name $dependency.Key -ErrorAction SilentlyContinue)) {
            Import-Module (Join-Path $modulesRoot $dependency.Value) -Function $dependency.Key
        }
    }

    If ($PSCmdlet.ParameterSetName -eq 'configString') {
        If (-not (Test-Json -Json $configString)) {
            throw "The -configString value is not valid JSON."
        }
        $config = ConvertFrom-Json -InputObject $configString -AsHashtable
    }
    ElseIf ($PSCmdlet.ParameterSetName -eq 'configFile') {
        $config = Confirm-GSAConfigurationParameters -configFilePath $configFilePath
    }

    If (-not $config['runtime'] -or -not $config['runtime']['resourceGroup']) {
        throw "The configuration does not contain runtime values. Pass the output of Confirm-GSAConfigurationParameters or a config file path."
    }

    $subscriptionId = $config['runtime']['subscriptionId']
    If (-not $subscriptionId) { $subscriptionId = $config.subscriptionId }
    If (-not $subscriptionId) { $subscriptionId = (Get-AzContext).Subscription.Id }
    $removeCoreResources = $newComponents -contains 'CoreComponents'

    # --- Locate the existing deployment(s) -------------------------------------------------------

    $existingDeployments = @(Find-GSAExistingDeployment -config $config -subscriptionId $subscriptionId -existingResourceGroupName $existingResourceGroupName)

    If ($existingDeployments.Count -eq 0) {
        Write-Host "No existing Guardrails Solution Accelerator deployment found in subscription '$subscriptionId'. Nothing to remove." -ForegroundColor Green
        return
    }

    If ($existingDeployments.Count -gt 1 -and -not $all.IsPresent) {
        throw ("More than one Guardrails Solution Accelerator resource group was found in subscription '{0}': {1}. Specify the one to remove with -existingResourceGroupName, or use -all to remove every one of them." -f `
            $subscriptionId, ($existingDeployments.ResourceGroupName -join ', '))
    }

    # --- Confirm ----------------------------------------------------------------------------------

    $summary = @("Existing Guardrails Solution Accelerator deployment(s) found in subscription '$subscriptionId':")
    ForEach ($existingDeployment in $existingDeployments) {
        $summary += "    - Resource group: $($existingDeployment.ResourceGroupName) (detected by: $($existingDeployment.Evidence -join ', '))"
        $summary += "        Log Analytics workspace: $($existingDeployment.Config['runtime']['logAnalyticsWorkspaceName'])"
        $summary += "        Configuration source: $($existingDeployment.ConfigSource)"
        If ($existingDeployment.Config.lighthouseServiceProviderTenantID) {
            $summary += "        Lighthouse delegation 'SSC CSPM - Read Guardrail Status' for managing tenant '$($existingDeployment.Config.lighthouseServiceProviderTenantID)' will be removed."
        }
        If ($existingDeployment.Config.lighthouseTargetManagementGroupID) {
            $summary += "        Defender for Cloud role assignments and custom role at management group '$($existingDeployment.Config.lighthouseTargetManagementGroupID)' will be removed if present."
        }
    }
    If ($removeCoreResources) {
        $summary += "Each resource group and all resources in it will be deleted, including permanent deletion of the Log Analytics workspace data."
    }
    Else {
        $summary += "CoreComponents is not being deployed, so the resource group(s) are kept. Only Lighthouse components matching the requested components are removed."
    }
    Write-Warning ($summary -join "`n")

    If (!$force.IsPresent) {
        do { $prompt = Read-Host -Prompt 'Do you want to continue? (y/n)' }
        until ($prompt -match '[yn]')

        if ($prompt -ieq 'n') {
            Write-Output "Exiting without removing the existing Guardrails Solution Accelerator deployment..."
            return
        }
    }

    # --- Remove ----------------------------------------------------------------------------------

    $oldKeyVaultNames = @()
    ForEach ($existingDeployment in $existingDeployments) {
        $oldKeyVaultNames += Remove-GSADiscoveredDeployment -existingDeployment $existingDeployment -newComponents $newComponents -removeCoreResources $removeCoreResources
    }

    If (-not $removeCoreResources) {
        Write-Host "Completed removal of existing Lighthouse components. Resource group(s) $(($existingDeployments.ResourceGroupName | ForEach-Object { "'$_'" }) -join ', ') were kept." -ForegroundColor Green
        return
    }

    # --- Soft-deleted Key Vault -------------------------------------------------------------------

    $newKeyVaultName = $config['runtime']['keyVaultName']
    If ($newKeyVaultName -and ($oldKeyVaultNames -contains $newKeyVaultName)) {
        Clear-GSASoftDeletedKeyVault -vaultName $newKeyVaultName -subscriptionId $subscriptionId
    }

    Write-Host "Completed removal of the existing Guardrails Solution Accelerator deployment(s)." -ForegroundColor Green
}

Function Remove-GSADiscoveredDeployment {
    <#
    .SYNOPSIS
        Removes one discovered Guardrails deployment: Lighthouse components first, then the core resource group.
        Returns the names of the Key Vaults the resource group held, for soft-delete purging by the caller.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [psobject]
        $existingDeployment,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]
        $newComponents,

        [Parameter(Mandatory = $true)]
        [bool]
        $removeCoreResources
    )
    $ErrorActionPreference = 'Stop'

    $oldConfig = $existingDeployment.Config
    $oldResourceGroup = $existingDeployment.ResourceGroupName
    $oldConfigJson = ConvertTo-Json -InputObject $oldConfig -Depth 10

    # --- 1. Lighthouse delegation (subscription scope) -------------------------------------------

    If ($oldConfig.lighthouseServiceProviderTenantID) {
        Write-Host "Removing Lighthouse reporting delegation for managing tenant '$($oldConfig.lighthouseServiceProviderTenantID)'..." -ForegroundColor Green
        try {
            Remove-GSACentralizedReportingCustomerComponents -configString $oldConfigJson -force
        }
        catch {
            If ($newComponents -contains 'CentralizedCustomerReportingSupport') {
                throw "Failed to remove the existing Lighthouse reporting delegation, which blocks deployment of CentralizedCustomerReportingSupport. $_"
            }
            Write-Warning "Failed to remove the existing Lighthouse reporting delegation. Continuing because CentralizedCustomerReportingSupport is not being deployed. $_"
        }
    }

    # --- 2. Defender for Cloud role assignments (management group scope) -------------------------

    If ($oldConfig.lighthouseTargetManagementGroupID) {
        Write-Host "Removing Defender for Cloud Lighthouse role assignments at management group '$($oldConfig.lighthouseTargetManagementGroupID)'..." -ForegroundColor Green
        try {
            Remove-GSACentralizedDefenderCustomerComponents -configString $oldConfigJson -force
        }
        catch {
            If ($newComponents -contains 'CentralizedCustomerDefenderForCloudSupport') {
                throw "Failed to remove the existing Defender for Cloud role assignments, which blocks deployment of CentralizedCustomerDefenderForCloudSupport. $_"
            }
            Write-Warning "Failed to remove the existing Defender for Cloud role assignments. Continuing because CentralizedCustomerDefenderForCloudSupport is not being deployed. $_"
        }
    }

    If (-not $removeCoreResources) {
        return @()
    }

    # --- 3. Core resources ------------------------------------------------------------------------

    # Record which Key Vaults the old resource group held before it is deleted, so the
    # soft-deleted vault can be purged if the new deployment reuses the name.
    $oldKeyVaultNames = @(Get-AzKeyVault -ResourceGroupName $oldResourceGroup -ErrorAction SilentlyContinue | Select-Object -ExpandProperty VaultName)

    Write-Host "Removing Guardrails core resources in resource group '$oldResourceGroup'..." -ForegroundColor Green
    Remove-GSACoreResources -configString $oldConfigJson -force -wait

    # The old Automation Account identity held Reader at the tenant root management group and on the
    # Microsoft.aadiam and Microsoft.Marketplace providers. Deleting the account leaves those behind as
    # 'Identity not found'. They do not block the new deployment, so this cleanup is best effort.
    If ($oldConfig.guardrailsAutomationAccountMSI) {
        Remove-GSAOrphanedIdentityRoleAssignments -principalId $oldConfig.guardrailsAutomationAccountMSI
    }

    return $oldKeyVaultNames
}

Function Find-GSAExistingDeployment {
    <#
    .SYNOPSIS
        Locates an existing Guardrails deployment and returns its resource group, evidence, and best-known configuration.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]
        $config,

        [Parameter(Mandatory = $true)]
        [string]
        $subscriptionId,

        [Parameter(Mandatory = $false)]
        [string]
        $existingResourceGroupName
    )
    $ErrorActionPreference = 'Stop'

    $configuredResourceGroup = $config['runtime']['resourceGroup']

    If ($existingResourceGroupName) {
        $candidates = @(Get-AzResourceGroup -Name $existingResourceGroupName -ErrorAction SilentlyContinue)
        If ($candidates.Count -eq 0) {
            throw "Resource group '$existingResourceGroupName' specified with -existingResourceGroupName was not found in subscription '$subscriptionId'."
        }
    }
    Else {
        $candidates = @()
        # Same names as the new deployment: the usual case when config.json is reused.
        $byName = Get-AzResourceGroup -Name $configuredResourceGroup -ErrorAction SilentlyContinue
        If ($byName) { $candidates += $byName }

        # Different uniqueNameSuffix: fall back to the Solution tag applied by every installer.
        $byTag = @(Get-AzResourceGroup -Tag @{ Solution = 'Guardrails Accelerator' } -ErrorAction SilentlyContinue)
        ForEach ($rg in $byTag) {
            If ($candidates.ResourceGroupName -notcontains $rg.ResourceGroupName) { $candidates += $rg }
        }
    }

    $deployments = @()
    ForEach ($candidate in ($candidates | Sort-Object -Property ResourceGroupName)) {
        $deployments += Resolve-GSAExistingDeployment -config $config -subscriptionId $subscriptionId -resourceGroup $candidate
    }
    return $deployments
}

Function Resolve-GSAExistingDeployment {
    <#
    .SYNOPSIS
        Verifies that a resource group is a Guardrails deployment and returns the best-known configuration for removing it.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]
        $config,

        [Parameter(Mandatory = $true)]
        [string]
        $subscriptionId,

        [Parameter(Mandatory = $true)]
        [psobject]
        $resourceGroup
    )
    $ErrorActionPreference = 'Stop'

    $resourceGroupName = $resourceGroup.ResourceGroupName
    $evidence = @()

    If ($resourceGroup.Tags -and $resourceGroup.Tags['Solution'] -like 'Guardrails*') {
        $evidence += "Solution tag '$($resourceGroup.Tags['Solution'])'"
    }

    # The exported configuration is the most reliable description of the old deployment,
    # because its resource names may differ from the new config.json.
    $exportedConfig = $null
    $exportedConfigVault = $null
    ForEach ($vault in @(Get-AzKeyVault -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue)) {
        try {
            [string]$secretValue = Get-AzKeyVaultSecret -VaultName $vault.VaultName -Name 'gsaConfigExportLatest' -AsPlainText -ErrorAction Stop
        }
        catch {
            Write-Verbose "Could not read 'gsaConfigExportLatest' from Key Vault '$($vault.VaultName)': $($_.Exception.Message)"
            continue
        }
        If ($secretValue -and (Test-Json -Json $secretValue -ErrorAction SilentlyContinue)) {
            $exportedConfig = ConvertFrom-Json -InputObject $secretValue -AsHashtable
            $exportedConfigVault = $vault.VaultName
            $evidence += "exported configuration in Key Vault '$($vault.VaultName)'"
            break
        }
    }

    If ($evidence.Count -eq 0) {
        $runbooks = @()
        ForEach ($automationAccount in @(Get-AzAutomationAccount -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue)) {
            $runbooks += @(Get-AzAutomationRunbook -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccount.AutomationAccountName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
        }
        If (($runbooks -contains 'main') -and ($runbooks -contains 'backend')) {
            $evidence += "Guardrails runbooks 'main' and 'backend'"
        }
    }

    If ($evidence.Count -eq 0) {
        throw "Resource group '$resourceGroupName' does not look like a Guardrails Solution Accelerator deployment (no Solution tag, exported configuration, or Guardrails runbooks). It was not removed. Review and remove it manually if it is a leftover installation."
    }

    If ($exportedConfig -and $exportedConfig['runtime'] -and $exportedConfig['runtime']['resourceGroup'] -eq $resourceGroupName) {
        $oldConfig = $exportedConfig
        $configSource = "Key Vault '$exportedConfigVault' secret 'gsaConfigExportLatest'"
    }
    Else {
        # Build the minimum configuration the Remove-GSA* commands need from what is in the resource group.
        $workspaces = @(Get-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue)
        $workspaceName = $config['runtime']['logAnalyticsWorkspaceName']
        If ($workspaces.Count -gt 0 -and $workspaces.Name -notcontains $workspaceName) {
            $workspaceName = $workspaces[0].Name
        }

        $oldConfig = @{
            subscriptionId                    = $subscriptionId
            lighthouseServiceProviderTenantID = $config.lighthouseServiceProviderTenantID
            lighthouseTargetManagementGroupID = $config.lighthouseTargetManagementGroupID
            runtime                           = @{
                subscriptionId            = $subscriptionId
                resourceGroup             = $resourceGroupName
                logAnalyticsWorkspaceName = $workspaceName
            }
        }

        # Capture the Automation Account identity before the resource group is deleted so its
        # tenant-level role assignments can be cleaned up afterwards.
        $automationIdentity = @(Get-AzAutomationAccount -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue) |
            Where-Object { $_.Identity -and $_.Identity.PrincipalId } | Select-Object -First 1
        If ($automationIdentity) {
            $oldConfig['guardrailsAutomationAccountMSI'] = $automationIdentity.Identity.PrincipalId
        }
        $configSource = 'resources discovered in the resource group (no exported configuration available)'
    }

    # The removal commands select the subscription from these values; keep them consistent with the discovery scope.
    $oldConfig['subscriptionId'] = $subscriptionId
    If (-not $oldConfig['runtime']) { $oldConfig['runtime'] = @{} }
    $oldConfig['runtime']['subscriptionId'] = $subscriptionId
    $oldConfig['runtime']['resourceGroup'] = $resourceGroupName

    return [pscustomobject]@{
        ResourceGroupName = $resourceGroupName
        Evidence          = $evidence
        Config            = $oldConfig
        ConfigSource      = $configSource
    }
}

Function Remove-GSAOrphanedIdentityRoleAssignments {
    <#
    .SYNOPSIS
        Best-effort removal of role assignments left behind by the previous Automation Account identity.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $principalId
    )
    $ErrorActionPreference = 'Stop'

    try {
        $assignments = @(Get-AzRoleAssignment -ObjectId $principalId -ErrorAction Stop -WarningAction SilentlyContinue)
    }
    catch {
        Write-Warning "Could not list role assignments for the previous Automation Account identity '$principalId'. Orphaned 'Identity not found' assignments may remain. $_"
        return
    }

    ForEach ($assignment in $assignments) {
        try {
            Write-Verbose "Removing orphaned role assignment '$($assignment.RoleDefinitionName)' at '$($assignment.Scope)' for previous identity '$principalId'."
            Remove-AzRoleAssignment -ObjectId $principalId -RoleDefinitionId $assignment.RoleDefinitionId -Scope $assignment.Scope -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
        }
        catch {
            Write-Warning "Could not remove orphaned role assignment '$($assignment.RoleDefinitionName)' at '$($assignment.Scope)' for previous identity '$principalId'. $_"
        }
    }

    If ($assignments.Count -gt 0) {
        Write-Host "Removed $($assignments.Count) role assignment(s) left behind by the previous Automation Account identity." -ForegroundColor Green
    }
}

Function Clear-GSASoftDeletedKeyVault {
    <#
    .SYNOPSIS
        Purges a soft-deleted Key Vault and waits until its name is available again.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $vaultName,

        [Parameter(Mandatory = $true)]
        [string]
        $subscriptionId
    )
    $ErrorActionPreference = 'Stop'

    # The vault can take a short time to appear in the deleted view after the resource group is removed.
    $deletedVault = $null
    $deadline = (Get-Date).AddMinutes(5)
    do {
        $deletedVault = Get-AzKeyVault -VaultName $vaultName -InRemovedState -ErrorAction SilentlyContinue
        If ($deletedVault) { break }
        If ((Get-Date) -ge $deadline) { break }
        Write-Verbose "Waiting for Key Vault '$vaultName' to appear in the soft-deleted state..."
        Start-Sleep -Seconds 15
    } while ($true)

    If (-not $deletedVault) {
        Write-Warning "Key Vault '$vaultName' was not found in the soft-deleted state. If the deployment later reports that the Key Vault name is unavailable, purge the vault manually or choose a different keyVaultName."
        return
    }

    If ($deletedVault.EnablePurgeProtection) {
        throw "Key Vault '$vaultName' from the previous deployment is soft-deleted with purge protection enabled, so its name cannot be reused until the retention period ends. Choose a different keyVaultName or uniqueNameSuffix in config.json."
    }

    Write-Host "Purging soft-deleted Key Vault '$vaultName' so the name can be reused..." -ForegroundColor Green
    try {
        Remove-AzKeyVault -VaultName $vaultName -Location $deletedVault.Location -InRemovedState -Force -ErrorAction Stop
    }
    catch {
        throw "Failed to purge soft-deleted Key Vault '$vaultName'. The deploying identity needs the 'Microsoft.KeyVault/locations/deletedVaults/purge/action' permission (included in Key Vault Contributor and Owner). Alternatively choose a different keyVaultName or uniqueNameSuffix in config.json. $_"
    }

    # Purge is asynchronous; the installer's name-availability check must not race it.
    $deadline = (Get-Date).AddMinutes(5)
    do {
        $payload = @{ name = $vaultName; type = 'Microsoft.KeyVault/vaults' } | ConvertTo-Json -Compress
        $response = Invoke-AzRestMethod -Method POST -Path "/subscriptions/$subscriptionId/providers/Microsoft.KeyVault/checkNameAvailability?api-version=2021-11-01-preview" -Payload $payload -ErrorAction SilentlyContinue
        $availability = $null
        If ($response -and $response.Content) { $availability = ($response.Content | ConvertFrom-Json).nameAvailable }
        If ($availability -eq $true) {
            Write-Verbose "Key Vault name '$vaultName' is available."
            return
        }
        If ((Get-Date) -ge $deadline) {
            Write-Warning "Key Vault '$vaultName' was purged but Azure has not yet reported the name as available. The deployment will retry the name check."
            return
        }
        Write-Verbose "Waiting for Key Vault name '$vaultName' to become available after purge..."
        Start-Sleep -Seconds 15
    } while ($true)
}

Export-ModuleMember -Function 'Remove-GSAExistingDeployment'
