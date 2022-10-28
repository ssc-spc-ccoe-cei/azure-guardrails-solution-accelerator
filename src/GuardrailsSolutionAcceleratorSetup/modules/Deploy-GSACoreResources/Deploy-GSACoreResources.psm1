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
    # add automation account msi to config object
    $config['guardrailsAutomationAccountMSI'] = $mainBicepDeployment.Outputs.guardrailsAutomationAccountMSI.value
    Write-Verbose "Core resource deployment complete!"

    # grant current user permissions to the new key vault
    Write-Verbose "Adding current user '$($config['runtime']['userId'])' access to the GSA KeyVault..."
    try { 
        $kv = Get-AzKeyVault -ResourceGroupName $config['runtime']['resourceGroup'] -VaultName $config['runtime']['keyVaultName'] -ErrorAction Stop
    }
    catch { 
        Write-Error "Error fetching KV '$($config['runtime']['KeyVaultName'])'. $_"
        break 
    }

    try { 
        $null = New-AzRoleAssignment -ObjectId $config['runtime']['userId'] -RoleDefinitionName "Key Vault Administrator" -Scope $kv.ResourceId -ErrorAction Stop
    }
    catch { 
        Write-Error "Error assigning permissions to KV '$($config['runtime']['KeyVaultName'])'. $_"
        break 
    }

    Write-Verbose "Sleeping 30 seconds to allow KeyVault permissions to be propagated."
    Start-Sleep -Seconds 30

    # Adds keyvault secret user permissions for the Automation account MSI
    Write-Verbose "Adding automation account Keyvault Secret User."
    try {
        $null = New-AzRoleAssignment -ObjectId $config.guardrailsAutomationAccountMSI -RoleDefinitionName "Key Vault Secrets User" -Scope $kv.ResourceId
    }
    catch {
        Write-Error "Error assigning permissions to Automation account (for keyvault). $_"
        break
    }
    Write-Verbose "Completed adding user access to Key Vault"

    Write-Verbose "Adding workspacekey secret to key vault."
    try {
        $workspaceKey = (Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $config['runtime']['resourceGroup'] -Name $config['runtime']['logAnalyticsworkspaceName']).PrimarySharedKey
        $secretvalue = ConvertTo-SecureString $workspaceKey -AsPlainText -Force 
        $secret = Set-AzKeyVaultSecret -VaultName $config['runtime']['keyVaultName'] -Name "WorkSpaceKey" -SecretValue $secretvalue
    }
    catch { 
        Write-Error "Error adding WS secret to KV. $_" 
        break 
    }

    Write-Verbose "Adding Breakglass account names to Key Vault"
    try {
        $ErrorActionPreference = 'Stop'

        $secretvalue = ConvertTo-SecureString $config.FirstBreakGlassAccountUPN -AsPlainText -Force 
        $secret = Set-AzKeyVaultSecret -VaultName $config['runtime']['keyVaultName'] -Name "BGA1" -SecretValue $secretvalue
        $secretvalue = ConvertTo-SecureString $config.SecondBreakGlassAccountUPN -AsPlainText -Force 
        $secret = Set-AzKeyVaultSecret -VaultName $config['runtime']['keyVaultName'] -Name "BGA2" -SecretValue $secretvalue
    }
    catch {
        Write-Error "Error adding Breakglass secrets to KeyVault. $_"
        break
    }

    Write-Verbose "Granting Automation Account MSI permission to the Graph API"
    try {
        #region Assign permissions>
        $graphAppId = "00000003-0000-0000-c000-000000000000"
        $graphAppSP = Get-AzADServicePrincipal -ApplicationId $graphAppId
        $appRoleIds = @("Organization.Read.All", "User.Read.All", "UserAuthenticationMethod.Read.All", "Policy.Read.All")

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

        Write-Verbose "`tAssigning 'Reader and Data Access' role to Automation Account MSI on Guardrails Storage Account '$($config['runtime']['StorageAccountName'])'"
        $StorageAccountID = (Get-AzStorageAccount -ResourceGroupName $config['runtime']['resourceGroup'] -Name $config['runtime']['storageaccountName']).Id
        New-AzRoleAssignment -ObjectId $config.guardrailsAutomationAccountMSI -RoleDefinitionName "Reader and Data Access" -Scope $StorageAccountID | Out-Null

        Write-Verbose "`tAssigning 'Reader' role to the Automation Account MSI for the Azure AD IAM scope"
        New-AzRoleAssignment -ObjectId $config.guardrailsAutomationAccountMSI -RoleDefinitionName Reader -Scope '/providers/Microsoft.aadiam' | Out-Null
    }
    catch {
        Write-Error "Error assigning root management group permissions. $_"
        break
    }
    Write-Verbose "Completed granting Automation Account required permissions."

    # sleep 60 seconds to ensure Automation Account delegations have applied before next steps
    Write-Verbose "Sleeping 60 seconds to ensure Automation Account delegations have applied..."
    Start-Sleep -Seconds 60

    Write-Verbose "Core resource deployment completed"
}