
# import sub-modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Confirm-GSAConfigurationParameters\Confirm-GSAConfigurationParameters.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Confirm-GSAPrerequisites\Confirm-GSAPrerequisites.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Show-GSADeploymentSummary\Show-GSADeploymentSummary.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Deploy-GSACoreResources\Deploy-GSACoreResources.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Add-GSAAutomationRunbooks\Add-GSAAutomationRunbooks.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Deploy-GSACentralizedDefenderCustomerComponents\Deploy-GSACentralizedDefenderCustomerComponents.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Deploy-GSACentralizedReportingCustomerComponents\Deploy-GSACentralizedReportingCustomerComponents.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Deploy-GSACentralizedReportingProviderComponents\Deploy-GSACentralizedReportingProviderComponents.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Update-GSACoreResources\Update-GSACoreResources.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Update-GSAAutomationRunbooks\Update-GSAAutomationRunbooks.psd1")

Function Invoke-GSARunbooks {
    param (
        # config object
        [Parameter(Mandatory = $true)]
        [psobject]
        $config
    )

    try {
        Start-AzAutomationRunbook -Name "main" -AutomationAccountName $config['runtime']['autoMationAccountName'] -ResourceGroupName $config['runtime']['resourceGroup'] -ErrorAction Stop | Out-Null
    }
    catch { 
        Write-Error "Error starting 'main' runbook. $_"
    }
    try {
        Start-AzAutomationRunbook -Name "backend" -AutomationAccountName $config['runtime']['autoMationAccountName'] -ResourceGroupName $config['runtime']['resourceGroup'] -ErrorAction Stop | Out-Null
    }
    catch { 
        Write-Error "Error starting 'backend' runbook. $_"
    }
}

Function New-GSACoreResourceDeploymentParamObject {
    param (
        # config object
        [Parameter(Mandatory = $true)]
        [hashtable]
        $config,

        # alternate module url
        [Parameter(Mandatory = $false)]
        [string]
        $moduleBaseURL
    )
    
    Write-Verbose "Creating bicep parameters file for this deployment."
    $templateParameterObject = @{
        'AllowedLocationPolicyId'           = $config.AllowedLocationPolicyId
        'automationAccountName'             = $config['runtime']['autoMationAccountName']
        'CBSSubscriptionName'               = $config.CBSSubscriptionName
        'DepartmentNumber'                  = $config.DepartmentNumber
        'DepartmentName'                    = $config['runtime']['departmentName']
        'deployKV'                          = $config['runtime']['deployKV']
        'deployLAW'                         = $config['runtime']['deployLAW']
        'HealthLAWResourceId'               = $config.HealthLAWResourceId
        'kvName'                            = $config['runtime']['keyVaultName']
        'lighthouseTargetManagementGroupID' = $config.lighthouseTargetManagementGroupID
        'Locale'                            = $config.Locale
        'location'                          = $config.region
        'logAnalyticsWorkspaceName'         = $config['runtime']['logAnalyticsworkspaceName']
        'PBMMPolicyID'                      = $config.PBMMPolicyID
        'releasedate'                       = $config['runtime']['tagsTable'].ReleaseDate
        'releaseVersion'                    = $config['runtime']['tagsTable'].ReleaseVersion
        'SecurityLAWResourceId'             = $config.SecurityLAWResourceId
        'storageAccountName'                = $config['runtime']['storageaccountName']
        'subscriptionId'                    = (Get-AzContext).Subscription.Id
        'tenantDomainUPN'                   = $config['runtime']['tenantDomainUPN']
    }
    # Adding URL parameter if specified
    [regex]$moduleURIRegex = '(https://github.com/.+?/(raw|archive)/.*?/psmodules)|(https://.+?\.blob\.core\.windows\.net/psmodules)'
    If (![string]::IsNullOrEmpty($moduleBaseURL)) {
        If ($moduleBaseURL -match $moduleURIRegex) {
            $templateParameterObject += @{ModuleBaseURL = $moduleBaseURL }
        }
        Else {
            Write-Error "-moduleBaseURL provided, but does not match pattern '$moduleURIRegex'" -ErrorAction Stop
        }
    }
    Write-Verbose "templateParameterObject: `n$($templateParameterObject | ConvertTo-Json)"

    [hashtable]$templateParameterObject
}

Function Deploy-GuardrailsSolutionAccelerator {
    <#
    .SYNOPSIS
        Deploy or update the Guardrails Solution Accelerator.
    .DESCRIPTION
        This function will deploy or update the Guardrails Solution Accelerator, depending on the specified parameters. It can also be used to verify deployment parameters and prerequisites. 

        For new deployments, a configuration file must be provided using the -configFilePath parameter. This file is a JSON file specifying the deployment configuration
        and resource naming conventions. See this page for details: https://github.com/Azure/GuardrailsSolutionAccelerator/blob/main/docs/setup.md.

        For update deployments to an existing environment, either the -ConfigFilePath should be used, or the Get-GSAExportedConfiguration function can be used to retrieve the current 
        deployment's configuration from the specified KeyVault. 

        In order to enable centralized reporting and/or Defender for Cloud access by a managing tenant, specify CentralizedCustomerDefenderForCloudSupport or CentralizedCustomerReportingSupport. This
        can be done separately from a deployment of the core components. 

        If errors are encountered during deployment and a redeployment does not pass prerequisites due to existing resources, the following modules can perform cleanup tasks:
          - Remove-GSACentralizedDefenderCustomerComponents
          - Remove-GSACentralizedReportingCustomerComponents
          - Remove-GSACoreResources'
    .NOTES
        Information or caveats about the function e.g. 'This function is not supported in Linux'
    .LINK
        https://github.com/Azure/GuardrailsSolutionAccelerator
    .EXAMPLE 
        # Deploy new GSA instance, with core components only:
        Deploy-GuardrailsSolutionAccelerator -configFilePath "C:\config.json"
    .EXAMPLE
        # Deploy new GSA instance, with core components and Defender for Cloud access delegated to a managing tenant:
        Deploy-GuardrailsSolutionAccelerator -configFilePath "C:\config.json" -newComponents CoreComponents,CentralizedCustomerDefenderForCloudSupport
    .EXAMPLE
        # Validate the contents of a configuration file, but do not deploy anything:
        Deploy-GuardrailsSolutionAccelerator -configFilePath "C:\config.json" -validateConfigFile
    .EXAMPLE
        # Validate that the prerequisites are met for the specified deployment configuration:
        Deploy-GuardrailsSolutionAccelerator -configFilePath "C:\config.json" -validatePrerequisites -newComponents CoreComponents,CentralizedCustomerDefenderForCloudSupport,CentralizedCustomerReportingSupport
    .EXAMPLE
        # Update an existing GSA instance (PowerShell modules, workbooks, and runbooks):
        Get-GSAExportedConfig -KeyVaultName guardrails-12345 | Deploy-GuardrailsSolutionAccelerator -update
    .EXAMPLE
        # Add the CentralizedCustomerDefenderForCloudSupport component to an existing deployment, retrieving the configuration from the existing deployment's Key Vault
        Get-GSAExportedConfig -KeyVaultName guardrails-12345 | deploy-GuardrailsSolutionAccelerator -newComponents CentralizedCustomerDefenderForCloudSupport
    #>

    [CmdletBinding(DefaultParameterSetName = 'newDeployment-configFilePath')]
    param (
        # path to the configuration file - for new deployments
        [Parameter(mandatory = $true, ParameterSetName = 'newDeployment-configFilePath')]
        [Parameter(Mandatory = $true, ParameterSetName = 'updateDeployment-configFilePath')]
        [Parameter(mandatory = $true, ParameterSetName = 'validateConfigFile')]
        [Parameter(mandatory = $true, ParameterSetName = 'validatePreReqs-configFilePath')]
        [string]
        [Alias(
            'configFileName'
        )]
        $configFilePath,

        # as an alternative to specifying a config file, you can pass a config object directly. This is useful for updating an existing deployment, where the 
        # config file is stored in the deployment's Key Vault and retrieved using Get-GSAExportedConfig command
        [Parameter(mandatory = $true, ParameterSetName = 'newDeployment-configString', ValueFromPipelineByPropertyName = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = 'updateDeployment-configString', ValueFromPipelineByPropertyName = $true)]
        [Parameter(mandatory = $true, ParameterSetName = 'validatePreReqs-configString', ValueFromPipelineByPropertyName = $true)]
        [string]
        $configString,

        # components to be deployed
        [Parameter(Mandatory = $false, ParameterSetName = 'newDeployment-configFilePath')]
        [Parameter(Mandatory = $false, ParameterSetName = 'newDeployment-configString')]
        [Parameter(mandatory = $false, ParameterSetName = 'validatePreReqs-configFilePath')]
        [Parameter(mandatory = $false, ParameterSetName = 'validatePreReqs-configString')]
        [Parameter(mandatory = $true, ParameterSetName = 'validateConfigFile')]
        [ValidateSet(
            'CoreComponents',
            'CentralizedCustomerReportingSupport',
            'CentralizedCustomerDefenderForCloudSupport'<#, # TODO: add support for provider-side deployment
            'CentralizedReportingProviderComponents'#>
        )]
        [string[]]
        $newComponents = @('CoreComponents'),

        # components to be updated
        [Parameter(Mandatory = $true, ParameterSetName = 'updateDeployment-configFilePath')]
        [Parameter(Mandatory = $true, ParameterSetName = 'updateDeployment-configString')]
        [switch]
        $update,

        # components to be updated - in most cases, this should not be specified and all components should be updated
        [Parameter(Mandatory = $false, ParameterSetName = 'updateDeployment-configFilePath')]
        [Parameter(Mandatory = $false, ParameterSetName = 'updateDeployment-configString')]
        [ValidateSet(
            'CoreComponents',
            'Workbook',
            'GuardrailPowerShellModules',
            'AutomationAccountRunbooks'
        )]
        [string[]]
        $componentsToUpdate = @('Workbook','GuardrailPowerShellModules','AutomationAccountRunbooks', 'CoreComponents'),

        # confirm that config parameters are valid
        [Parameter(mandatory = $true, ParameterSetName = 'validateConfigFile')]
        [switch]
        $validateConfigFile,

        # specify to validate prerequisites without deploying anything (validation always runs when deploying)
        [Parameter(mandatory = $true, ParameterSetName = 'validatePreReqs-configFilePath')]
        [Parameter(mandatory = $true, ParameterSetName = 'validatePreReqs-configString')]
        [switch]
        $validatePrerequisites,

        # specify to source the GSA PowerShell modules from an alternate URL, like a pre-release branch on GitHub (default installs from the 'latest' release on GitHub public repo)
        [Parameter(Mandatory = $false, ParameterSetName = 'newDeployment-configFilePath')]
        [Parameter(Mandatory = $false, ParameterSetName = 'newDeployment-configString')]
        [Parameter(Mandatory = $false, ParameterSetName = 'updateDeployment-configFilePath')]
        [Parameter(Mandatory = $false, ParameterSetName = 'updateDeployment-configString')]
        [string]
        $alternatePSModulesURL,

        # proceed through imput prompts - used for deployment via automation or testing
        [Parameter(Mandatory = $false)]
        [Alias('y')]
        [switch]
        $yes
    )

    $ErrorActionPreference = 'Stop'

    #ensures verbose preference is passed through to sub-modules
    If ($PSBoundParameters.ContainsKey('verbose')) {
        $useVerbose = $true
    }
    Else {
        $useVerbose = $false
    }

    # based on parameters, perform validation or deployment/update
    If ($validateConfigFile.IsPresent) {
        $config = Confirm-GSAConfigurationParameters -configFilePath $configFilePath -Verbose:$useVerbose

        Write-Output "Configuration parameters:"
        $config.GetEnumerator() | Sort-Object -Property Name | Format-Table -AutoSize -Wrap
        break
    }
    ElseIf ($validatePrerequisites.IsPresent) {
        Write-Verbose "Validating config parameters before validating prerequisites..."
        If ($PSCmdlet.ParameterSetName -eq 'validatePreReqs-configString') {
            $config = Confirm-GSAConfigurationParameters -configString $configString -Verbose:$useVerbose
        }
        Else {
            $config = Confirm-GSAConfigurationParameters -configFilePath $configFilePath -Verbose:$useVerbose
        }
        Write-Verbose "Completed validating config parameters."

        Confirm-GSAPrerequisites -config $config -newComponents $newComponents -Verbose:$useVerbose
        break
    }
    Else {
        # new deployment or update deployment
        # confirms the provided values in config.json and appends runtime values, then returns the config object
        If ($PSCmdlet.ParameterSetName -in 'newDeployment-configString','updateDeployment-configString') {
            $config = Confirm-GSAConfigurationParameters -configString $configString -Verbose:$useVerbose
        }
        Else {
            $config = Confirm-GSAConfigurationParameters -configFilePath $configFilePath -Verbose:$useVerbose
        }

        Show-GSADeploymentSummary -deployParams $PSBoundParameters -deployParamSet $PSCmdlet.ParameterSetName -yes:$yes.isPresent -Verbose:$useVerbose

        # set module install or update source URL
        $params = @{}
        If ($alternatePSModulesURL) {
            Write-Verbose "-alternatePSModulesURL specified, using alternate URL for Guardrails PowerShell modules: $alternatePSModulesURL"
            $params = @{ moduleBaseURL = $alternatePSModulesURL }
        }
        Else {
            # getting latest release from GitHub
            $latestRelease = Invoke-RestMethod 'https://api.github.com/repos/Azure/GuardrailsSolutionAccelerator/releases/latest'
            $moduleBaseURL = "https://github.com/Azure/GuardrailsSolutionAccelerator/raw/{0}/psmodules" -f $latestRelease.tag_name

            Write-Verbose "Using latest release from GitHub for Guardrails PowerShell modules: $moduleBaseURL"
            $params = @{ moduleBaseURL = $moduleBaseURL }
        }
        $paramObject = New-GSACoreResourceDeploymentParamObject -config $config @params -Verbose:$useVerbose

        If (!$update.IsPresent) {
            Write-Host "Deploying Guardrails Solution Accelerator components ($($newComponents -join ','))..." -ForegroundColor Green
            Write-Verbose "Performing a new deployment of the Guardrails Solution Accelerator..."

            # confirms that prerequisites are met and that deployment can proceed
            Confirm-GSAPrerequisites -config $config -newComponents $newComponents -Verbose:$useVerbose

            If ($newComponents -contains 'CoreComponents') {
                # deploy core resources
                Deploy-GSACoreResources -config $config -paramObject $paramObject -Verbose:$useVerbose
                
                # add runbooks to AA
                Add-GSAAutomationRunbooks -config $config -Verbose:$useVerbose
            }
            
            # deploy Lighthouse components
            If ($newComponents -contains 'CentralizedCustomerReportingSupport') {
                Deploy-GSACentralizedReportingCustomerComponents -config $config -Verbose:$useVerbose
            }
            If ($newComponents -contains 'CentralizedCustomerDefenderForCloudSupport') {
                Deploy-GSACentralizedDefenderCustomerComponents -config $config -Verbose:$useVerbose
            }

            Write-Verbose "Completed new deployment."
        }
        Else {
            Write-Host "Updating Guardrails Solution Accelerator components ($($componentsToUpdate -join ','))..." -ForegroundColor Green
            Write-Verbose "Updating an existing deployment of the Guardrails Solution Accelerator..."
        
            # skip deployment of LAW and KV as they should exist already
            $paramObject.deployKV = $false
            $paramObject.deployLAW = $false
            $paramObject += @{newDeployment = $false }

            If ($PSBoundParameters.ContainsKey('componentsToUpdate')) {
                Write-Warning "Specifying individual components to update with -componentsToUpdate risks deploying out-of-sync components; ommiting this parameter and updating all components is recommended. You selected to update $($componentsToUpdate -join ', '). Updating individual components should be done with caution. `n`nPress ENTER to continue or CTRL+C to cancel..."
                Read-Host
            }

            $updateBicep = $false # if true, the bicep template will be deploy with the parameters in $paramObject
            # update workbook definitions
            If ($componentsToUpdate -contains 'Workbook') {
                #removing any saved search in the gr_functions category since an incremental deployment fails...
                Write-Verbose "Removing any saved searches in the gr_functions category prior to update (which will redeploy them)..."
                $savedSearches = Get-AzOperationalInsightsSavedSearch -WorkspaceName $config['runtime']['logAnalyticsWorkspaceName'] -ResourceGroupName $config['runtime']['resourceGroup']
                $grfunctions = $savedSearches.Value | Where-Object {
                    $_.Properties.Category -eq 'gr_functions'
                }

                Write-Verbose "Found $($grfunctions.Count) saved searches in the gr_functions category to be removed."
                $grfunctions | ForEach-Object { 
                    Write-Verbose "`tRemoving saved search $($_.Name)..."
                    Remove-AzOperationalInsightsSavedSearch -ResourceGroupName $config['runtime']['resourceGroup'] -WorkspaceName $config['runtime']['logAnalyticsworkspaceName'] -SavedSearchId $_.Name
                }

                $paramObject += @{updateWorkbook = $true }

                $updateBicep = $true
            }

            # update Guardrail powershell modules in AA
            If ($componentsToUpdate -contains 'GuardrailPowerShellModules') {
                $paramObject += @{updatePSModules = $true }

                $updateBicep = $true
            }

            # deploy core resources update
            If ($componentsToUpdate -contains 'CoreComponents') {
                $paramObject += @{updateCoreResources = $true }

                $updateBicep = $true
            }

            # deploy the bicep template with the specified parameters
            If ($updateBicep) {
                Write-Verbose "Deploying core Bicep template with update parameters '$($paramObject.Keys.Where({$_ -like 'update*'}) -join ',')'..."
                Update-GSACoreResources -config $config -paramObject $paramObject -Verbose:$useVerbose
            }
            
            # update runbook definitions in AA
            If ($componentsToUpdate -contains 'AutomationAccountRunbooks') {
                Update-GSAAutomationRunbooks -config $config -Verbose:$useVerbose
            }

            Write-Verbose "Completed update deployment."
        }

        # after successful deployment or update
        Write-Verbose "Invoking manual execution of Azure Automation runbooks..."
        Invoke-GSARunbooks -config $config -Verbose:$useVerbose

        Write-Verbose "Exporting configuration to GSA KeyVault '$($config['runtime']['keyVaultName'])' as secret 'gsaConfigExportLatest'..."
        $configSecretName = 'gsaConfigExportLatest'
        $secretTags = @{
            'deploymentTimestamp'   = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
            'deployerLocalUsername' = $env:USERNAME
            'deployerAzureID'       = $config['runtime']['userId']
        }
        $secretValue = (ConvertTo-SecureString -String (ConvertTo-Json $config -Depth 10) -AsPlainText -Force)
        Set-AzKeyVaultSecret -VaultName $config['runtime']['keyVaultName'] -Name $configSecretName -SecretValue $secretValue -Tag $secretTags -ContentType 'application/json' -Verbose:$useVerbose | Out-Null

        Write-Host "Completed deployment of the Guardrails Solution Accelerator!" -ForegroundColor Green
    }
}

# list functions to export from module for public consumption; also update in GuardrailsSolutionAcceleratorSetup.psm1 when making changes
$functionsToExport = @(
    #'Add-GSAAutomationRunbooks'
    'Confirm-GSAConfigurationParameters'
    'Confirm-GSAPrerequisites'
    'Confirm-GSASubscriptionSelection'
    #'Deploy-GSACentralizedDefenderCustomerComponents'
    #'Deploy-GSACentralizedReportingCustomerComponents'
    #'Deploy-GSACentralizedReportingProviderComponents'
    #'Deploy-GSACoreResources'
    'Deploy-GuardrailsSolutionAccelerator'
    #'Remove-GSACentralizedDefenderCustomerComponents'
    #'Remove-GSACentralizedReportingCustomerComponents'
    #'Remove-GSACoreResources'
    #'Show-GSADeploymentSummary'
    #'Update-GSAAutomationRunbooks'
    #'Update-GSAGuardrailPSModules'
    #'Update-GSAWorkbookDefintion
)

Export-ModuleMember -Function $functionsToExport
# SIG # Begin signature block
# MIInygYJKoZIhvcNAQcCoIInuzCCJ7cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB67++VoKSHF84+
# nMSHam2Me8fxHidYjvSMBtborsD4gqCCDYEwggX/MIID56ADAgECAhMzAAACzI61
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
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZnzCCGZsCAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAsyOtZamvdHJTgAAAAACzDAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg1/RZSMPa
# EnMlvXcO0B9rY6hGPOm0Uz2dWWhphWd0D28wQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQAUSQAkz+jMpZxKdx0QoF7nP7ev001S5C+1PeTMR0ue
# XZlLKFspnm78iZ+r6pwKrvZInzwAgF4xa1mWfS6e9epm8FuVIs608jgbS9PApGmd
# Yvgqv8+tQtC3gatBGiDNtVHGyF+Y1Q5tFF5jmgPVl8FFIPu83YxP7PmYBlkantrw
# meyB8iCLm7Ji4lhFDmvuR/wm1W6Bj3xfEue/7Tr2fiZNdDpN/JwC5NNs0oDRpTsR
# IXeilz92mEWZ4kNBRkXRZLhu5tfMdwjCqE1gtWklxtTQsr3Cr0oy66en720qMDHf
# pTEpSJre0QqftDkAN5CVJnts4VofeFbeuRE8IO3jezlpoYIXKTCCFyUGCisGAQQB
# gjcDAwExghcVMIIXEQYJKoZIhvcNAQcCoIIXAjCCFv4CAQMxDzANBglghkgBZQME
# AgEFADCCAVkGCyqGSIb3DQEJEAEEoIIBSASCAUQwggFAAgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIBkE6zjPmhQ+WIcTTvJjnMfQDWX/JZ/Gkloq40CQ
# ymAXAgZjx90lcfEYEzIwMjMwMTI1MjIyNTQzLjYxNlowBIACAfSggdikgdUwgdIx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1p
# Y3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhh
# bGVzIFRTUyBFU046MDg0Mi00QkU2LUMyOUExJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WgghF4MIIHJzCCBQ+gAwIBAgITMwAAAbJuQAN/bqmU
# kgABAAABsjANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDAeFw0yMjA5MjAyMDIyMDFaFw0yMzEyMTQyMDIyMDFaMIHSMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQg
# SXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1Mg
# RVNOOjA4NDItNEJFNi1DMjlBMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAyqJlMh17
# +VDisL4GaXl/9a6r/EpPGt9sbbceh+ZD6pkA3gbI7vc8XfL04B+m3tB/aNyV1Y4Z
# QH4fMG7CWVjI/d/HgxjzO+4C4HfsW+jK2c0LYMqdWtWUc5VwZQv0KeaEM0wDb+ey
# SMh/YiiIb0nSotivx268d1An0uLY+r2C7JJv2a9QvrSiCyUI72CSHoWIQPAyvBSv
# xaNrqMWlROfLy2DQ3RycI3bDh8qSnmplxtRgViJwtJv/oDukcK1frGeOrCGYmiJv
# e+QonJXFu4UtGFVfEf3lvQsd42GJ+feO+jaP7/hBXXSMSldVb6IL0GxO1Hr3G9ON
# TnVmA/sFHhgMRarsmzKVI6/kHlMdMNdF/XzhRHMWFPJvw5lApjuaoyHtzwnzDWwQ
# zhcNQXZRk3Lzb01ULMba190RdlofEXxGbGlBgHHKFnBjWui24hL6B83Z6r6GQBPe
# Kkafz8qYPAO3MBud+5eMCmB5mrCBxgnykMn7L/FTqi7MnPUG97lNOKGSIDvBCxB7
# pHrRmT10903PDQwrmeJHO5BkC3gYj3oWGOGVRZxRk4KS/8lcz84a7+uBKmVjB2Y8
# vPN8O1fK7L8YJTkjiXTyDqKJ9fKkyChiSRx44ADPi/HXHQE6dlZ8jd9LCo1S+g3u
# dxNP4wHhWm9/VAGmmMEBBS6+6Lp4IbQwJU0CAwEAAaOCAUkwggFFMB0GA1UdDgQW
# BBSZ8ieAXNkRmU+SMM5WW4FIMNpqcTAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQM
# MAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEA
# 3Ee27cXMhptoNtaqzB0oGUCEpdEI37kJIyK/ZNhriLZC5Yib732mLACEOEAN9uqi
# vXPIuL3ljoZCe8hZSB14LugvVm1nJ73bNgr4Qh/BhmaFL4IfiKd8DNS+xwdkXfCW
# slR89QgMZU/SUJhWx72aC68bR2qRjhrJA8Qc68m5uBllo52D83x0id3p8Z45z7QO
# gbMH4uJ45snZDQC0S3dc3eJfwKnr51lNfzHAT8u+FHA+lv/6cqyE7tNW696fB1PC
# oH8tPoI09oSXAV4rEqupFM8xsd6D6L4qcEt/CaERewyDazVBfskjF+9P3qZ3R6Iy
# OIwQ7bYts7OYsw13csg2jACdEEAm1f7f97f3QH2wwYwen5rVX6GCzrYCikGXSn/T
# SWLfQM3nARDkh/flmTtv9PqkTHqslQNgK2LvMJuKSMpNqcGc5z33MYyV6Plf58L+
# TkTFQKs6zf9XMZEJm3ku9VBJ1aqr9AzNMSaKbixvMBIr2KYSSM21lnK8LUKxRwPW
# +gWS2V3iYoyMT64MRXch10P4OtGT3idXM09K5ld7B9U6dcdJ6obvEzdXt+XZovi/
# U6Evb4nA7VPHcHSKs7U72ps10mTfnlue13VFJUqAzbYoUEeegvsmzulGEGJoqZVN
# Aag5v6PVBrur5yLEajjxWH2TfkEOwlL8MuhcVI8OXiYwggdxMIIFWaADAgECAhMz
# AAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9v
# dCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAeFw0yMTA5MzAxODIyMjVaFw0z
# MDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIICIjAN
# BgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA5OGmTOe0ciELeaLL1yR5vQ7VgtP9
# 7pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/XE/HZveVU3Fa4n5KWv64NmeFRiMM
# tY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1hlDcwUTIcVxRMTegCjhuje3XD9gm
# U3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7M62AW36MEBydUv626GIl3GoPz130
# /o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3KNi1wjjHINSi947SHJMPgyY9+tVSP
# 3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy1cCGMFxPLOJiss254o2I5JasAUq7
# vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF803RKJ1v2lIH1+/NmeRd+2ci/bfV+A
# utuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQcNIIP8BDyt0cY7afomXw/TNuvXsLz
# 1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahhaYQFzymeiXtcodgLiMxhy16cg8ML6
# EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkLiWHzNgY1GIRH29wb0f2y1BzFa/Zc
# UlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV2xo3xwgVGD94q0W29R6HXtqPnhZy
# acaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIGCSsGAQQBgjcVAQQFAgMBAAEwIwYJ
# KwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUpzxD/LwTuMB0GA1UdDgQWBBSfpxVd
# AF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBTMFEGDCsGAQQBgjdMg30BATBBMD8G
# CCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3Mv
# UmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYBBAGCNxQC
# BAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYD
# VR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZF
# aHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9v
# Q2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcw
# AoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJB
# dXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcNAQELBQADggIBAJ1VffwqreEsH2cB
# MSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1OdfCcTY/2mRsfNB1OW27DzHkwo/7
# bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYAA7AFvonoaeC6Ce5732pvvinLbtg/
# SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbzaN9l9qRWqveVtihVJ9AkvUCgvxm2
# EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6LGYnn8AtqgcKBGUIZUnWKNsIdw2Fz
# Lixre24/LAl4FOmRsqlb30mjdAy87JGA0j3mSj5mO0+7hvoyGtmW9I/2kQH2zsZ0
# /fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0SCyxTkctwRQEcb9k+SS+c23Kjgm9
# swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxkoJLo4S5pu+yFUa2pFEUep8beuyOiJ
# Xk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFmPWn9y8FBSX5+k77L+DvktxW/tM4+
# pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC4822rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW
# 4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7vzhwRNGQ8cirOoo6CGJ/2XBjU02N
# 7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIC1DCCAj0CAQEwggEAoYHYpIHVMIHSMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxl
# cyBUU1MgRVNOOjA4NDItNEJFNi1DMjlBMSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQCOEn4R7JJF+fYoI2yOf1wX
# 0BRJOqCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
# SIb3DQEBBQUAAgUA53uV9jAiGA8yMDIzMDEyNTE5NTAxNFoYDzIwMjMwMTI2MTk1
# MDE0WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDne5X2AgEAMAcCAQACAiBkMAcC
# AQACAhFLMAoCBQDnfOd2AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkK
# AwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQEFBQADgYEAYSv5
# 9tSKtXDhfP4F2UK/1jXDBq3G1zMhvcegtiJfjdDhZIrjng434G3dsOVdFuFlMYvD
# vPvFGEn1u5F5g/VRVYH+n09SMtnJBC9ctYZ7o/wS/rpn+iTj/dGsaE/4Zgb5ariI
# jrD6CgfWTFMYCUz/WdK0TPAQFQoBXRc3EJl7x3MxggQNMIIECQIBATCBkzB8MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNy
# b3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAbJuQAN/bqmUkgABAAABsjAN
# BglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8G
# CSqGSIb3DQEJBDEiBCCFPtDgJbakkx2Q1W3LrTRFtV1eczqq4NdlTRJi+oyOxjCB
# +gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIFN4zjzn4T63g8RWJ5SgUpfs9XIu
# j+fO76G0k8IbTj41MIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIw
# MTACEzMAAAGybkADf26plJIAAQAAAbIwIgQgK0Lv0IEUbEQIdXpkzRZMiVCMbxEY
# ogAuheEu3cPoF/UwDQYJKoZIhvcNAQELBQAEggIABQqNHYs0ZXjuPXeLURxIe23g
# 8iZFh2KfGqtBqE1w4empulE+AYj1CIvuTibAxEbIcm98w38hQy2bPNogUQdqIWhm
# hAHP0iAYETEW3Z1DIg8RXXiA+pQQ96mJIzdUTNhkjDauCytSYzae9L3rYw6nWfti
# JT0tpcaXzE9tBl7SuFVrCE7EkhW+Muvi2ot283u2IsvmFXis8yr4JMea0bSXFgpN
# IBx1w6jXrkP7JpZmWTn6n58JS5i/vKmt7sydLKccxqD+C+V+HssR764SW7Vlvihf
# ZNNw3mx8EKbN3TQtZxfgcEaXNMa6XnC8MwK+hkxGU7C6KVjs93vjpyWOdW18g0MO
# QyyGBVXE7+bIGMGmsFE0oZwcAyXQlPGHziHncM24F1ZcNRodELQDckF9pMtv2UD5
# EbsBrZOjJOHUY8UuT0HV6QaQReRICJa82SKHQCnnBriI7eBZkWm6uIG7NpOpPzz0
# LoP9Ws8cL+62wJ6UtHy59tSKCORi9LyGir4Cg68dk7IbRolJnM/KkeUD1FyDaToi
# ksQDhkeZKB0xVJKzxegIfoeJPmM3rIyE0krxs/9vslIFBIyyTRA8gzKJDAr4H8kM
# CDqARaoYmcMBQBupvPKlDZyZekAURpfrNPRNYMQ/NUnJmzlLfmmKn5XdmlmdBgPq
# 1ULEDC+GyXyXGGaFd7U=
# SIG # End signature block
