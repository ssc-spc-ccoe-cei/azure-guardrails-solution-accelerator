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
            $isLastAttempt = $deploymentAttempt -gt $deploymentRetryDelaysInSeconds.Count
            if (-not $isDcrTableReadinessError -or $isLastAttempt) {
                Write-Error "Failed to deploy main Guardrails Accelerator template with error: $deploymentErrorText"
                Exit
            }

            $retryDelayInSeconds = $deploymentRetryDelaysInSeconds[$deploymentAttempt - 1]
            Write-Warning "Core deployment hit DCR table readiness error (InvalidOutputTable) on attempt $deploymentAttempt. Waiting $retryDelayInSeconds seconds before retrying."
            Start-Sleep -Seconds $retryDelayInSeconds
        }
    }
    # add automation account msi to config object
    $config['guardrailsAutomationAccountMSI'] = $mainBicepDeployment.Outputs.guardrailsAutomationAccountMSI.value

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

    <#
    .SYNOPSIS
    Idempotently creates a role assignment with retry for transient MSI propagation errors.

    .DESCRIPTION
    Newly-created Automation Account MSIs can take seconds to minutes to propagate.
    Role assignments using the MSI object ID during that window can fail with
    BadRequest or PrincipalNotFound. This wrapper sets ObjectType to
    ServicePrincipal to bypass the principal-type lookup that can fail during
    MSI propagation, skips existing assignments, re-checks after errors in case
    creation succeeded, retries bounded transient failures, and fails fast on
    non-retryable errors.
    #>
    function Set-GSARoleAssignment {
        param (
            [Parameter(Mandatory = $true)]
            [string]
            $ObjectId,

            [Parameter(Mandatory = $true)]
            [string]
            $RoleDefinitionName,

            [Parameter(Mandatory = $true)]
            [string]
            $Scope,

            [Parameter(Mandatory = $true)]
            [string]
            $Description
        )

        $retryDelaysInSeconds = @(30, 60, 120, 180)
        for ($attempt = 1; $attempt -le ($retryDelaysInSeconds.Count + 1); $attempt++) {
            try {
                $existingAssignment = Get-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleDefinitionName -Scope $Scope -ErrorAction SilentlyContinue
                if ($existingAssignment) {
                    Write-Verbose "`tRole assignment already exists: $Description"
                    return
                }

                New-AzRoleAssignment -ObjectId $ObjectId -ObjectType ServicePrincipal -RoleDefinitionName $RoleDefinitionName -Scope $Scope -ErrorAction Stop | Out-Null
                Write-Verbose "`tCreated role assignment: $Description"
                return
            }
            catch {
                $errorMessage = $_.Exception.Message
                $existingAssignment = Get-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleDefinitionName -Scope $Scope -ErrorAction SilentlyContinue
                if ($existingAssignment) {
                    Write-Verbose "`tRole assignment exists after retryable error: $Description"
                    return
                }

                # BadRequest is broad, but Azure also uses it for fresh MSI
                # propagation lag. The post-error assignment check and bounded
                # retry budget keep real BadRequest failures from being hidden.
                $isRetryableRoleAssignmentError = $errorMessage -match 'BadRequest|PrincipalNotFound|does not exist in the directory|not found|RoleAssignmentExists|Conflict'
                $isLastAttempt = $attempt -gt $retryDelaysInSeconds.Count
                if (-not $isRetryableRoleAssignmentError -or $isLastAttempt) {
                    throw "Failed to assign role '$RoleDefinitionName' on scope '$Scope' to Automation Account MSI object '$ObjectId' for '$Description'. Error: $errorMessage"
                }

                $retryDelayInSeconds = $retryDelaysInSeconds[$attempt - 1]
                Write-Warning "Role assignment '$Description' failed on attempt $attempt of $($retryDelaysInSeconds.Count + 1), likely while the new Automation Account MSI is propagating. Waiting $retryDelayInSeconds seconds before retrying. Error: $errorMessage"
                Start-Sleep -Seconds $retryDelayInSeconds
            }
        }
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
        Set-GSARoleAssignment -ObjectId $config.guardrailsAutomationAccountMSI -RoleDefinitionName Reader -Scope $config['runtime']['tenantRootManagementGroupId'] -Description "Reader on root management group '$($rootmg.DisplayName)'"

        Write-Verbose "`tAssigning 'Reader and Data Access' role to Automation Account MSI on Guardrails Storage Account '$($config['runtime']['StorageAccountName'])'"
        $StorageAccountID = (Get-AzStorageAccount -ResourceGroupName $config['runtime']['resourceGroup'] -Name $config['runtime']['storageaccountName']).Id
        Set-GSARoleAssignment -ObjectId $config.guardrailsAutomationAccountMSI -RoleDefinitionName "Reader and Data Access" -Scope $StorageAccountID -Description "Reader and Data Access on Guardrails Storage Account '$($config['runtime']['StorageAccountName'])'"

        Write-Verbose "`tAssigning 'Reader' role to the Automation Account MSI for the Azure AD IAM scope"
        Set-GSARoleAssignment -ObjectId $config.guardrailsAutomationAccountMSI -RoleDefinitionName Reader -Scope '/providers/Microsoft.aadiam' -Description "Reader on Azure AD IAM scope"

        Write-Verbose "`tAssigning 'Reader' role to the Automation Account MSI for the Azure MarketPlace"
        Set-GSARoleAssignment -ObjectId $config.guardrailsAutomationAccountMSI -RoleDefinitionName Reader -Scope '/providers/Microsoft.Marketplace' -Description "Reader on Azure Marketplace scope"
    }
    catch {
        Write-Error "Error assigning root management group permissions. $_"
        break
    }
    Write-Verbose "Completed granting Automation Account required permissions."

    Write-Verbose "Core resource deployment completed"
}