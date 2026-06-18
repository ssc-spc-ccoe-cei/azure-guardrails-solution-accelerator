function Ensure-GSARoleAssignment {
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

    $existingAssignment = Get-AzRoleAssignment -ObjectId $ObjectId -Scope $Scope -ErrorAction SilentlyContinue |
        Where-Object { $_.RoleDefinitionName -eq $RoleDefinitionName } |
        Select-Object -First 1

    if ($existingAssignment) {
        return $false
    }

    New-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleDefinitionName -Scope $Scope -ErrorAction Stop | Out-Null
    return $true
}

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

    return Ensure-GSARoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleDefinitionName -Scope $Scope
}

function Ensure-GSAAutomationAccountRbac {
    param (
        [Parameter(Mandatory = $true)]
        [psobject]
        $Config,

        [Parameter(Mandatory = $true)]
        [string]
        $AutomationAccountMsi
    )

    $resourceGroupName = $Config['runtime']['resourceGroup']
    $rolesEnsured = [System.Collections.Generic.List[string]]::new()

    $law = Get-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -Name $Config['runtime']['logAnalyticsWorkspaceName'] -ErrorAction Stop
    if (Ensure-GSARoleAssignment -ObjectId $AutomationAccountMsi -RoleDefinitionName 'Log Analytics Reader' -Scope $law.ResourceId) {
        $rolesEnsured.Add('Log Analytics Reader on Log Analytics workspace') | Out-Null
    }

    foreach ($dcrName in @('guardrails-dcr', 'guardrails-dcr-2')) {
        $dcr = Get-AzDataCollectionRule -ResourceGroupName $resourceGroupName -Name $dcrName -ErrorAction SilentlyContinue
        if ($dcr) {
            if (Ensure-GSARoleAssignment -ObjectId $AutomationAccountMsi -RoleDefinitionName 'Monitoring Metrics Publisher' -Scope $dcr.Id) {
                $rolesEnsured.Add("Monitoring Metrics Publisher on $dcrName") | Out-Null
            }
        }
        else {
            Write-Warning "Data Collection Rule '$dcrName' was not found in resource group '$resourceGroupName'. Skipping Monitoring Metrics Publisher assignment."
        }
    }

    if ($Config['runtime']['storageAccountId']) {
        if (Ensure-GSARoleAssignment -ObjectId $AutomationAccountMsi -RoleDefinitionName 'Storage Blob Data Reader' -Scope $Config['runtime']['storageAccountId']) {
            $rolesEnsured.Add('Storage Blob Data Reader on storage account') | Out-Null
        }
    }

    $keyVaultName = $Config['runtime']['keyVaultName']
    if (-not [string]::IsNullOrWhiteSpace($keyVaultName)) {
        $keyVault = Get-AzKeyVault -VaultName $keyVaultName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
        if ($keyVault) {
            if (Ensure-GSARoleAssignment -ObjectId $AutomationAccountMsi -RoleDefinitionName 'Key Vault Secrets User' -Scope $keyVault.ResourceId) {
                $rolesEnsured.Add('Key Vault Secrets User on Key Vault') | Out-Null
            }
        }
    }

    if ($Config['runtime']['tenantRootManagementGroupId']) {
        if (Ensure-GSARoleAssignment -ObjectId $AutomationAccountMsi -RoleDefinitionName 'Reader' -Scope $Config['runtime']['tenantRootManagementGroupId']) {
            $rolesEnsured.Add('Reader on tenant root management group') | Out-Null
        }
    }

    foreach ($scope in @('/providers/Microsoft.aadiam', '/providers/Microsoft.Marketplace')) {
        if (Ensure-GSARoleAssignment -ObjectId $AutomationAccountMsi -RoleDefinitionName 'Reader' -Scope $scope) {
            $rolesEnsured.Add("Reader on $scope") | Out-Null
        }
    }

    if ($rolesEnsured.Count -gt 0) {
        Write-Verbose "Ensured Automation Account MSI role assignments: $($rolesEnsured -join '; ')"
    }
    else {
        Write-Verbose 'Automation Account MSI already has required Azure RBAC role assignments.'
    }
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
    $deploymentRetryDelaysInSeconds = @(60, 120, 180, 240, 300)
    $mainBicepDeployment = $null
    for ($deploymentAttempt = 1; $deploymentAttempt -le ($deploymentRetryDelaysInSeconds.Count + 1); $deploymentAttempt++) {
        try {
            $mainBicepDeployment = New-AzResourceGroupDeployment -ResourceGroupName $config['runtime']['resourceGroup'] -Name "guardraildeployment$(get-date -format "ddmmyyHHmmss")" `
                -TemplateParameterObject $paramObject -TemplateFile "$PSScriptRoot/../../../../setup/IaC/guardrails.bicep" -WarningAction SilentlyContinue -ErrorAction Stop
            break
        }
        catch {
            $deploymentErrorText = $_ | Out-String
            if ([string]::IsNullOrWhiteSpace($deploymentErrorText)) {
                $deploymentErrorText = $_.Exception.Message
            }

            $isDcrTableReadinessError = $deploymentErrorText -match 'InvalidOutputTable'
            $isStorageContainerReadinessError = $deploymentErrorText -match 'ContainerOperationFailure' -and
                $deploymentErrorText -match 'The specified resource does not exist'
            $isLastAttempt = $deploymentAttempt -gt $deploymentRetryDelaysInSeconds.Count
            if (-not ($isDcrTableReadinessError -or $isStorageContainerReadinessError) -or $isLastAttempt) {
                Write-Error "Failed to deploy main Guardrails Accelerator template with error: $deploymentErrorText"
                Exit
            }

            $retryDelayInSeconds = $deploymentRetryDelaysInSeconds[$deploymentAttempt - 1]
            if ($isDcrTableReadinessError) {
                Write-Warning "Core deployment hit DCR table readiness error (InvalidOutputTable) on attempt $deploymentAttempt. Waiting $retryDelayInSeconds seconds before retrying."
            }
            else {
                Write-Warning "Core deployment hit storage container readiness error (ContainerOperationFailure) on attempt $deploymentAttempt. Waiting $retryDelayInSeconds seconds before retrying."
            }
            Start-Sleep -Seconds $retryDelayInSeconds
        }
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
            if ($null -ne $appRoleId) {
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
                    Write-Error "Error assigning permissions $appRoleId to $approleidName. $_"
                    Break
                }

                If ([int]($response.StatusCode) -gt 299) {
                    Write-Error "Error assigning permissions $appRoleId to $approleidName. $($response.Error)"
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
        Ensure-GSAAutomationAccountRbac -Config $config -AutomationAccountMsi $config.guardrailsAutomationAccountMSI

        # Give the deployment user or service principal temporary blob write access so modules.json can be uploaded with Entra auth.
        Write-Verbose "`tEnsuring temporary 'Storage Blob Data Contributor' role exists for deployer '$($config['runtime']['userId'])' on Guardrails Storage Account '$($config['runtime']['StorageAccountName'])'"
        $config['runtime']['temporaryDeployerBlobContributorAssigned'] = Ensure-GSAStorageRoleAssignment -ObjectId $config['runtime']['userId'] -RoleDefinitionName "Storage Blob Data Contributor" -Scope $config['runtime']['storageAccountId']
    }
    catch {
        Write-Error "Error assigning Automation Account Azure RBAC permissions. $_"
        break
    }
    Write-Verbose "Completed granting Automation Account required permissions."

    Write-Verbose "Core resource deployment completed"
}