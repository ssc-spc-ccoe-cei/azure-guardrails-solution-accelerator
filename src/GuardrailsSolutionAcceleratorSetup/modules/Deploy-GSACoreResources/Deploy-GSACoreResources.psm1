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
    Write-Verbose "Core resource bicep deployment complete!"

    Write-Verbose "Granting Automation Account MSI permission to the Graph API"
    try {
        #region Assign permissions>
        $graphAppId = "00000003-0000-0000-c000-000000000000"
        $graphAppSP = Get-AzADServicePrincipal -ApplicationId $graphAppId
        $appRoleIds = @("Organization.Read.All", "User.Read.All", "UserAuthenticationMethod.Read.All", "Policy.Read.All","Directory.Read.All")

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
