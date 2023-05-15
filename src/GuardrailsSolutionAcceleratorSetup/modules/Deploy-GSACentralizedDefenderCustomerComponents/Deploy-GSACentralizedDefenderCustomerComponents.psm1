
Function Deploy-GSACentralizedDefenderCustomerComponents {
    param (
        # config
        [Parameter(mandatory = $true)]
        [psobject]
        $config
    )
    $ErrorActionPreference = 'Stop'

    Write-Verbose "Initiating deployment of components Lighthouse delegation of access to Defender for Cloud"
    $lighthouseBicepPath = "$PSScriptRoot/../../../../setup/lighthouse/"

    #build parameter object for subscription Defender for Cloud access delegation
    $bicepParams = @{
        'managedByTenantId'       = $config.lighthouseServiceProviderTenantID
        'location'                = $config.region
        'managedByName'           = 'SSC CSPM - Defender for Cloud Access'
        'managedByDescription'    = 'SSC CSPM - Defender for Cloud Access'
        'managedByAuthorizations' = @(
            @{
                'principalIdDisplayName' = $config.lighthousePrincipalDisplayName
                'principalId'            = $config.lighthousePrincipalId
                'roleDefinitionId'       = '91c1777a-f3dc-4fae-b103-61d183457e46' # Managed Services Registration assignment Delete Role
            }
            @{
                'principalIdDisplayName' = $config.lighthousePrincipalDisplayName
                'principalId'            = $config.lighthousePrincipalId
                'roleDefinitionId'       = '39bc4728-0917-49c7-9d2c-d95423bc2eb4' # Security Reader
            }
        )
    }

    #deploy a custom role definition at the lighthouseTargetManagementGroupID, which will later be used to grant the Automation Account MSI permissions to register the Lighthouse Resource Provider
    try {
        $roleDefinitionDeployment = New-AzManagementGroupDeployment -ManagementGroupId $config.lighthouseTargetManagementGroupID `
            -Location $config.region `
            -TemplateFile $lighthouseBicepPath/lighthouse_registerRPRole.bicep `
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
        $policyDeployment = New-AzManagementGroupDeployment -ManagementGroupId $config.lighthouseTargetManagementGroupID `
            -Location $config.region `
            -TemplateFile $lighthouseBicepPath/lighthouseDfCPolicy.bicep `
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
        $null = New-AzManagementGroupDeployment -ManagementGroupId $config.lighthouseTargetManagementGroupID `
            -Location $config.region `
            -TemplateFile $lighthouseBicepPath/lighthouseDfCPolicyRoleAssignment.bicep `
            -TemplateParameterObject @{policyAssignmentMSIPrincipalID = $policyDeployment.Outputs.policyAssignmentMSIRoleAssignmentID.value } `
            -Confirm:$false `
            -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to deploy template granting the Defender for Cloud delegation policy rights to configure role assignments with error: $_"
        break   
    } 

    # deploy a custom role assignment, granting the Automation Account MSI permissions to register the Lighthouse resource provider on each subscription under the target management group
    try {
        $null = New-AzManagementGroupDeployment -ManagementGroupId $config.lighthouseTargetManagementGroupID `
            -Location $config.region `
            -TemplateFile $lighthouseBicepPath/lighthouse_assignRPRole.bicep `
            -TemplateParameterObject @{lighthouseRegisterRPRoleDefinitionID = $lighthouseRegisterRPRoleDefinitionID; guardrailsAutomationAccountMSI = $config.guardrailsAutomationAccountMSI } `
            -Confirm:$false `
            -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to deploy template granting the Azure Automation account rights to register the Lighthouse resource provider with error: $_"
        break   
    } 

    ### TO DO ### The remediation task created by the Bicep template should be all that is required, but does not seem to execute
    try {
        $ErrorActionPreference = 'Stop'
        $null = Start-AzPolicyRemediation -Name Redemdiation -ManagementGroupName $config.lighthouseTargetManagementGroupID -PolicyAssignmentId $policyDeployment.Outputs.policyAssignmentId.value
    }
    catch {
        Write-Error "Failed to create Remediation Task for policy assignment '$($policyDeployment.Outputs.policyAssignmentId.value)' with the following error: $_"
    }

    Write-Verbose "Completing deployment of components Lighthouse delegation of access to Defender for Cloud"
}
