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

function Ensure-GSAAutomationAccountMsiRoles {
    param (
        [Parameter(Mandatory = $true)]
        [psobject]
        $Config,
        [Parameter(Mandatory = $true)]
        [string]
        $AutomationAccountMsi
    )

    $resourceGroupName = $Config['runtime']['resourceGroup']

    $law = Get-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -Name $Config['runtime']['logAnalyticsWorkspaceName'] -ErrorAction Stop
    $null = Ensure-GSARoleAssignment -ObjectId $AutomationAccountMsi -RoleDefinitionName 'Log Analytics Reader' -Scope $law.ResourceId

    foreach ($dcrName in @('guardrails-dcr', 'guardrails-dcr-2')) {
        $dcr = Get-AzDataCollectionRule -ResourceGroupName $resourceGroupName -Name $dcrName -ErrorAction SilentlyContinue
        if ($dcr) {
            $null = Ensure-GSARoleAssignment -ObjectId $AutomationAccountMsi -RoleDefinitionName 'Monitoring Metrics Publisher' -Scope $dcr.Id
        }
    }

    if ($Config['runtime']['storageAccountId']) {
        $null = Ensure-GSARoleAssignment -ObjectId $AutomationAccountMsi -RoleDefinitionName 'Storage Blob Data Reader' -Scope $Config['runtime']['storageAccountId']
    }

    $keyVaultName = $Config['runtime']['keyVaultName']
    if (-not [string]::IsNullOrWhiteSpace($keyVaultName)) {
        $keyVault = Get-AzKeyVault -VaultName $keyVaultName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
        if ($keyVault) {
            $null = Ensure-GSARoleAssignment -ObjectId $AutomationAccountMsi -RoleDefinitionName 'Key Vault Secrets User' -Scope $keyVault.ResourceId
        }
    }

    if ($Config['runtime']['tenantRootManagementGroupId']) {
        $null = Ensure-GSARoleAssignment -ObjectId $AutomationAccountMsi -RoleDefinitionName 'Reader' -Scope $Config['runtime']['tenantRootManagementGroupId']
    }

    foreach ($scope in @('/providers/Microsoft.aadiam', '/providers/Microsoft.Marketplace')) {
        $null = Ensure-GSARoleAssignment -ObjectId $AutomationAccountMsi -RoleDefinitionName 'Reader' -Scope $scope
    }
}

function Deploy-GSAVersionAvailableAlert {
    param (
        [Parameter(Mandatory = $true)]
        [psobject]
        $Config
    )

    if ($Config['runtime']['deployLAW'] -eq $false) {
        Write-Verbose 'Skipping version alert deployment because deployLAW is false.'
        return
    }

    $resourceGroupName = $Config['runtime']['resourceGroup']
    $deployerId = $Config['runtime']['userId']
    $alertTemplate = Join-Path $PSScriptRoot '../../../../setup/IaC/modules/alert.bicep'
    $versionAlertQuery = "GR_VersionInfo_CL | summarize total=count() by UpdateAvailable=iff(DeployedVersion_s != AvailableVersion_s, 'Yes','No') | where UpdateAvailable == 'Yes'"

    try {
        $law = Get-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -Name $Config['runtime']['logAnalyticsWorkspaceName'] -ErrorAction Stop

        $null = Ensure-GSARoleAssignment -ObjectId $deployerId -RoleDefinitionName 'Log Analytics Reader' -Scope $law.ResourceId
        $null = Ensure-GSARoleAssignment -ObjectId $deployerId -RoleDefinitionName 'Monitoring Contributor' -Scope $law.ResourceId

        Write-Verbose 'Waiting 30 seconds for deployer workspace RBAC to propagate before version alert deployment...'
        Start-Sleep -Seconds 30

        $alertParams = @{
            alertRuleDescription   = 'Alerts when a new version of the Guardrails Solution Accelerator is available'
            alertRuleName          = 'GuardrailsNewVersion'
            alertRuleDisplayName   = 'Guardrails New Version Available.'
            alertRuleSeverity      = 3
            location               = $Config.region
            query                  = $versionAlertQuery
            scope                  = $law.ResourceId
            autoMitigate           = $true
            evaluationFrequency    = 'PT6H'
            windowSize             = 'PT6H'
        }

        $retryDelaysInSeconds = @(30, 60, 120)
        for ($attempt = 1; $attempt -le ($retryDelaysInSeconds.Count + 1); $attempt++) {
            try {
                $null = New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName `
                    -Name "guardrails-alert$(Get-Date -Format 'ddMMyyHHmmss')" `
                    -TemplateFile $alertTemplate `
                    -TemplateParameterObject $alertParams `
                    -ErrorAction Stop
                Write-Verbose 'Guardrails new-version alert deployed successfully.'
                return
            }
            catch {
                if ($attempt -gt $retryDelaysInSeconds.Count) {
                    throw
                }

                $delayInSeconds = $retryDelaysInSeconds[$attempt - 1]
                Write-Verbose "Version alert deployment attempt $attempt failed. Retrying in $delayInSeconds seconds. Error: $_"
                Start-Sleep -Seconds $delayInSeconds
            }
        }
    }
    catch {
        Write-Warning "Guardrails new-version alert deployment failed (non-fatal). Core deployment succeeded. Error: $_"
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
                    if ($_.Exception.Message -notmatch 'Permission being assigned already exists') {
                        Write-Error "Error assigning permissions $appRoleId to $approleidName. $_"
                        Break
                    }
                }

                If ($response -and [int]($response.StatusCode) -gt 299) {
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
        Ensure-GSAAutomationAccountMsiRoles -Config $config -AutomationAccountMsi $config.guardrailsAutomationAccountMSI

        Write-Verbose "`tEnsuring temporary 'Storage Blob Data Contributor' role exists for deployer '$($config['runtime']['userId'])' on Guardrails Storage Account '$($config['runtime']['storageAccountName'])'"
        $config['runtime']['temporaryDeployerBlobContributorAssigned'] = Ensure-GSAStorageRoleAssignment -ObjectId $config['runtime']['userId'] -RoleDefinitionName "Storage Blob Data Contributor" -Scope $config['runtime']['storageAccountId']
    }
    catch {
        Write-Error "Error assigning Automation Account Azure RBAC permissions. $_"
        break
    }
    Write-Verbose "Completed granting Automation Account required permissions."

    Deploy-GSAVersionAvailableAlert -Config $config

    Write-Verbose "Core resource deployment completed"
}