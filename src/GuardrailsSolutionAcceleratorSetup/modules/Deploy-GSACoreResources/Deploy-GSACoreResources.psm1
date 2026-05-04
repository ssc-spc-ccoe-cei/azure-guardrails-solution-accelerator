function Ensure-GSAStorageRoleAssignment {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $ObjectId,
        [Parameter(Mandatory = $true)]
        [string]
        $RoleDefinitionName,
        [Parameter(Mandatory = $true)]
        [string]
        $Scope
    )

    # Reuse a role assignment only when this scope already reports one, so create/remove behavior stays simple.
    $existingAssignment = Get-AzRoleAssignment -ObjectId $ObjectId -Scope $Scope -ErrorAction SilentlyContinue |
        Where-Object { $_.RoleDefinitionName -eq $RoleDefinitionName } |
        Select-Object -First 1

    if ($existingAssignment) {
        return $false
    }

    # Creating role assignments requires the deployer to have Owner, User Access Administrator, or equivalent rights at this scope.
    New-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleDefinitionName -Scope $Scope -ErrorAction Stop | Out-Null
    return $true
}

Function Deploy-GSACoreResources {
    param (
        # config
        [Parameter(mandatory = $true)]
        [psobject]
        $config,

        # parameter object
        [Parameter(mandatory = $true)]
        [psobject]
        $paramObject
    )
    $ErrorActionPreference = 'Stop'

    Write-Verbose "Initating deployment of core GSA resources..."

    # create resource broup
    Write-Verbose "Creating resource group '$($config['runtime']['resourceGroup'])' in '$($config.region)' location."
    try {
        New-AzResourceGroup -Name $config['runtime']['resourceGroup'] -Location $config.region -Tags $config['runtime']['tagstable'] -ErrorAction Stop -Force | Out-Null
    }
    catch { 
        throw "Error creating resource group. $_" 
    }

    # deploy primary bicep template
    Write-Verbose "Deploying GSA core resource via bicep template..."
    try { 
        $mainBicepDeployment = New-AzResourceGroupDeployment -ResourceGroupName $config['runtime']['resourceGroup'] -Name "guardraildeployment$(get-date -format "ddmmyyHHmmss")" `
            -TemplateParameterObject $paramObject -TemplateFile "$PSScriptRoot/../../../../setup/IaC/guardrails.bicep" -WarningAction SilentlyContinue -ErrorAction Stop
    }
    catch {
        Write-error "Failed to deploy main Guardrails Accelerator template with error: $_" 
        Exit
    }
    # Look up the storage account after deployment so later blob RBAC and upload steps use a real resource id.
    try {
        $storageAccount = Get-AzStorageAccount -ResourceGroupName $config['runtime']['resourceGroup'] -Name $config['runtime']['storageaccountName'] -ErrorAction Stop
        $config['runtime']['storageAccountId'] = $storageAccount.Id
    }
    catch {
        throw "Failed to find Guardrails storage account '$($config['runtime']['storageaccountName'])' after deployment. $_"
    }

    # Look up the automation account so we can confirm its system-assigned identity exists before granting blob access.
    try {
        $automationAccount = Get-AzAutomationAccount -ResourceGroupName $config['runtime']['resourceGroup'] -Name $config['runtime']['automationAccountName'] -ErrorAction Stop
    }
    catch {
        throw "Failed to find Guardrails Automation Account '$($config['runtime']['automationAccountName'])' after deployment. $_"
    }

    # Stop early if the automation account was created without the MSI this release depends on.
    if ($null -eq $automationAccount.Identity -or [string]::IsNullOrWhiteSpace($automationAccount.Identity.PrincipalId)) {
        throw "Guardrails Automation Account '$($config['runtime']['automationAccountName'])' does not have a system-assigned managed identity."
    }

    # Keep the confirmed MSI object id in config so later deployment steps and runbooks use the same value.
    $config['guardrailsAutomationAccountMSI'] = $automationAccount.Identity.PrincipalId

    # Persist DCE endpoint and DCR immutable IDs into config['runtime'] so they are included in the
    # gsaConfigExportLatest Key Vault secret. The local execution flow reads this secret and sets all
    # runtime properties as environment variables, making these available to Send-GuardrailsData.
    if ($mainBicepDeployment.Outputs.ContainsKey('dceEndpoint') -and -not [string]::IsNullOrEmpty($mainBicepDeployment.Outputs['dceEndpoint'].value)) {
        $config['runtime']['DCE_ENDPOINT'] = $mainBicepDeployment.Outputs['dceEndpoint'].value
        Write-Verbose "Captured DCE endpoint from deployment: $($config['runtime']['DCE_ENDPOINT'])"
    }
    if ($mainBicepDeployment.Outputs.ContainsKey('dcrImmutableId') -and -not [string]::IsNullOrEmpty($mainBicepDeployment.Outputs['dcrImmutableId'].value)) {
        $config['runtime']['DCR_IMMUTABLE_ID'] = $mainBicepDeployment.Outputs['dcrImmutableId'].value
        Write-Verbose "Captured DCR immutable ID from deployment: $($config['runtime']['DCR_IMMUTABLE_ID'])"
    }
    if ($mainBicepDeployment.Outputs.ContainsKey('dcrImmutableId2') -and -not [string]::IsNullOrEmpty($mainBicepDeployment.Outputs['dcrImmutableId2'].value)) {
        $config['runtime']['DCR_IMMUTABLE_ID_2'] = $mainBicepDeployment.Outputs['dcrImmutableId2'].value
        Write-Verbose "Captured DCR immutable ID 2 from deployment: $($config['runtime']['DCR_IMMUTABLE_ID_2'])"
    }

    # persist MSI object id as automation variable for runbooks
    $automationVariableName = 'GuardrailsAutomationAccountMSI'
    $automationAccountName = $config['runtime']['automationAccountName']
    $automationAccountResourceGroup = $config['runtime']['resourceGroup']
    try {
        $existingVariable = Get-AzAutomationVariable -ResourceGroupName $automationAccountResourceGroup -AutomationAccountName $automationAccountName -Name $automationVariableName -ErrorAction SilentlyContinue
        if ($existingVariable) {
            Set-AzAutomationVariable -ResourceGroupName $automationAccountResourceGroup -AutomationAccountName $automationAccountName -Name $automationVariableName -Value $config['guardrailsAutomationAccountMSI'] -Encrypted:$true -ErrorAction Stop | Out-Null
        }
        else {
            New-AzAutomationVariable -ResourceGroupName $automationAccountResourceGroup -AutomationAccountName $automationAccountName -Name $automationVariableName -Value $config['guardrailsAutomationAccountMSI'] -Encrypted:$true -ErrorAction Stop | Out-Null
        }
    }
    catch {
        Write-Warning "Failed to persist automation account MSI id to variable '$automationVariableName'. Telemetry MSI scan will be skipped until this is set. $_"
    }
    Write-Verbose "Core resource bicep deployment complete!"

    Write-Verbose "Granting Automation Account MSI permission to the Graph API"
    try {
        #region Assign permissions>
        $graphAppId = "00000003-0000-0000-c000-000000000000"
        $graphAppSP = Get-AzADServicePrincipal -ApplicationId $graphAppId
        $appRoleIds = @(
            "Organization.Read.All",
            "User.Read.All",
            "UserAuthenticationMethod.Read.All",
            "Policy.Read.All",
            "Directory.Read.All",
            "AuditLog.Read.All",
            "AccessReview.Read.All",
            "CustomSecAttributeAssignment.Read.All"
        )

        foreach ($approleidName in $appRoleIds) {
            Write-Verbose "`tAdding permission to $approleidName"
            $appRoleId = ($graphAppSP.AppRole | Where-Object { $_.Value -eq $approleidName }).Id
            if ($null -ne $approleid) {
                try {
                    $body = @{
                        "principalId" = $config.guardrailsAutomationAccountMSI
                        "resourceId"  = $graphAppSP.Id
                        "appRoleId"   = $appRoleId
                    } | ConvertTo-Json

                    $uri = "https://graph.microsoft.com/v1.0/servicePrincipals/{0}/appRoleAssignments" -f $config.guardrailsAutomationAccountMSI
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
        Write-Error "Error assigning permissions to graph API. $_"
        break 
    }
    Write-Verbose "Completed grant Automation Account MSI Graph permissions."

    Write-Verbose "Granting the Automation Account required permissions to the deployed environment (for scanning)..."
    try {
        Write-Verbose "`tAssigning reader access to the Automation Account Managed Identity for MG: $($rootmg.DisplayName)"
        New-AzRoleAssignment -ObjectId $config.guardrailsAutomationAccountMSI -RoleDefinitionName Reader -Scope $config['runtime']['tenantRootManagementGroupId'] | Out-Null

        # Give the Automation Account identity blob read access because the storage account no longer accepts Shared Key auth.
        Write-Verbose "`tEnsuring 'Storage Blob Data Reader' role exists for Automation Account MSI on Guardrails Storage Account '$($config['runtime']['StorageAccountName'])'"
        $null = Ensure-GSAStorageRoleAssignment -ObjectId $config.guardrailsAutomationAccountMSI -RoleDefinitionName "Storage Blob Data Reader" -Scope $config['runtime']['storageAccountId']

        # Give the deployment user or service principal temporary blob write access so modules.json can be uploaded with Entra auth.
        Write-Verbose "`tEnsuring temporary 'Storage Blob Data Contributor' role exists for deployer '$($config['runtime']['userId'])' on Guardrails Storage Account '$($config['runtime']['StorageAccountName'])'"
        $config['runtime']['temporaryDeployerBlobContributorAssigned'] = Ensure-GSAStorageRoleAssignment -ObjectId $config['runtime']['userId'] -RoleDefinitionName "Storage Blob Data Contributor" -Scope $config['runtime']['storageAccountId']

        Write-Verbose "`tAssigning 'Reader' role to the Automation Account MSI for the Azure AD IAM scope"
        New-AzRoleAssignment -ObjectId $config.guardrailsAutomationAccountMSI -RoleDefinitionName Reader -Scope '/providers/Microsoft.aadiam' | Out-Null

        Write-Verbose "`tAssigning 'Reader' role to the Automation Account MSI for the Azure MarketPlace"
        New-AzRoleAssignment -ObjectId $config.guardrailsAutomationAccountMSI -RoleDefinitionName Reader -Scope '/providers/Microsoft.Marketplace' | Out-Null
    }
    catch {
        Write-Error "Error assigning root management group permissions. $_"
        break
    }
    Write-Verbose "Completed granting Automation Account required permissions."

    Write-Verbose "Core resource deployment completed"
}