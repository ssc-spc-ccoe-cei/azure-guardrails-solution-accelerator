
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
# MIInrQYJKoZIhvcNAQcCoIInnjCCJ5oCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCADGAK6sGwAuzmL
# rlO0LJHns0fhEWZSyNZmPzDs8SYjG6CCDYEwggX/MIID56ADAgECAhMzAAACzI61
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
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgirESOvPb
# 2tsTE0DbpEGJFPXJGfFJl1MvwqoVmTE56nowQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQAw1QmoDjJONpJwQTlTYECwHRS2CG62xrBf3LoWduYd
# z2q82T8mvJ+PuYNDTI7sC1MbyNX/gz2T8LAUcjkWJ7srvUteKSacN8J7fwnWlUxc
# yEmG1OO4qbvAZSyN3mnVMVFdGU3IG4vkadqqp4rj0Jec3fZ8j48Lh4u+sHCgLxY2
# vXr68D3Lk9GDa2HsAcDixyUndmlphZbVKdSvuOjKve11UeKOjtHNI85FfWt5yOgD
# O35t/KB/w1xpvCKY8VR0o3rJz7BsNnUy43kRnpvdkQH33VtXklxvOr0K7H9sL2+x
# WebtRhZtvYqh2QSTbnRx+d1Ph7TS+XjFNlMdEvZCQW+ioYIXDDCCFwgGCisGAQQB
# gjcDAwExghb4MIIW9AYJKoZIhvcNAQcCoIIW5TCCFuECAQMxDzANBglghkgBZQME
# AgEFADCCAVUGCyqGSIb3DQEJEAEEoIIBRASCAUAwggE8AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIIdi7Yocq9quQ77IXzIqnVOZqmRFmr3h1TEtYsP8
# owhbAgZjxox1g80YEzIwMjMwMjA2MTUwOTIyLjc4OFowBIACAfSggdSkgdEwgc4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1p
# Y3Jvc29mdCBPcGVyYXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMg
# VFNTIEVTTjozMkJELUUzRDUtM0IxRDElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgU2VydmljZaCCEV8wggcQMIIE+KADAgECAhMzAAABrfzfTVjjXTLpAAEA
# AAGtMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# MB4XDTIyMDMwMjE4NTEzNloXDTIzMDUxMTE4NTEzNlowgc4xCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVy
# YXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjozMkJE
# LUUzRDUtM0IxRDElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vydmlj
# ZTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAOieUyqlTSrVLhvY7TO8
# vgC+T5N/y/MXeR3oNwE0rLI1Eg/gM5g9NhP+KqqJc/7uPL4TsoALb+RVf6roYNll
# yQrYmquUjwsq262MD5L9l9rU1plz2tMPehP8addVlNIjYIBh0NC4CyME6txVppQr
# 7eFd/bW0X9tnZy1aDW+zoaJB2FY8haokq5cRONEW4uoVsTTXsICkbYOAYffIIGak
# MFXVvB30NcsuiDn6uDk83XXTs0tnSr8FxzPoD8SgPPIcWaWPEjCQLr5I0BxfdUli
# wNPHIPEglqosrClRjXG7rcZWbWeODgATi0i6DUsv1Wn0LOW4svK4/Wuc/v9dlmuI
# ramv9whbgCykUuYZy8MxTzsQqU2Rxcm8h89CXA5jf1k7k3ZiaLUJ003MjtTtNXzl
# gb+k1A5eL17G3C4Ejw5AoViM+UBGQvxuTxpFeaGoQFqeOGGtEK0qk0wdUX9p/4Au
# 9Xsle5D5fvypBdscXBslUBcT6+CYq0kQ9smsTyhV4DK9wb9Zn7ObEOfT0AQyppI6
# jwzBjHhAGFyrKYjIbglMaEixjRv7XdNic2VuYKyS71A0hs6dbbDx/V7hDbdv2srt
# Z2VTO0y2E+4QqMRKtABv4AggjYKz5TYGuQ4VbbPY8fBO9Xqva3Gnx1ZDOQ3nGVFK
# HwarGDcNdB3qesvtJbIGJgJjAgMBAAGjggE2MIIBMjAdBgNVHQ4EFgQUfVB0HQS8
# qiFabmqEqOV9LrLGwVkwHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIw
# XwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
# cy9jcmwvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3Js
# MGwGCCsGAQUFBwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENB
# JTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcD
# CDANBgkqhkiG9w0BAQsFAAOCAgEAi9AdRbsx/gOSdBXndwRejQuutQqce3k3bgs1
# slPjZSx6FDXp1IZzjOyT1Jo/3eUWDBFJdi+Heu1NoyDdGn9vL6rxly1L68K4MnfL
# Bm+ybyjN+xa1eNa4+4cOoOuxE2Kt8jtmZbIhx2jvY7F9qY/lanR5PSbUKyClhNQh
# xsnNUp/JSQ+o7nAuQJ+wsCwPCrXYE7C+TvKDja6e6WU0K4RiBXFGU1z6Mt3K9wlM
# D/QGU4+/IGZDmE+/Z/k0JfJjZyxCAlcmhe3rgdhDzAsGxJYq4PblGZTBdr8wkQwp
# P2jggyMMawMM5DggwvXaDbrqCQ8gksNhCZzTqfS2dbgLF0m7HfwlUMrcnzi/bdTS
# RWzIXg5QsH1t5XaaIH+TZ1uZBtwXJ8EOXr6S+2A6q8RQVY10KnBH6YpGE9OhXPfu
# Iu882muFEdh4EXbPdARUR1IMSIxg88khSBC/YBwQhCpjTksq5J3Z+jyHWZ4MnXX5
# R42mAR584iRYc7agYvuotDEqcD0U9lIjgW31PqfqZQ1tuYZTiGcKE9QcYGvZFKnV
# dkqK8V0M9e+kF5CqDOrMMYRV2+I/FhyQsJHxK/G53D0O5bvdIh2gDnEHRAFihdZj
# 29Z7W0paGPotGX0oB5r9wqNjM3rbvuEe6FJ323MPY1x9/N1g126T/SokqADJBTKq
# yBYN4zMwggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3
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
# MSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjozMkJELUUzRDUtM0IxRDElMCMGA1UE
# AxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUA
# QJLRrUVR4ZbBDgWPjuNqVctUzpCggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMDANBgkqhkiG9w0BAQUFAAIFAOeLaAgwIhgPMjAyMzAyMDYxNTUw
# MzJaGA8yMDIzMDIwNzE1NTAzMlowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA54to
# CAIBADAKAgEAAgIN/gIB/zAHAgEAAgIRuTAKAgUA54y5iAIBADA2BgorBgEEAYRZ
# CgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0G
# CSqGSIb3DQEBBQUAA4GBAAKNbsD3nd0fXbOca+ypM7rfWzvYJmLMFs3dqdIBEGdD
# YAVLqOAlHsCgrdtKq6Q9fcQisIWgJC3uBxQYttgh/BsOijIcDF5luTEt8lrzxsdW
# 2VhTdPeK+wyAi5Pg5I/SdRGFEQd4KQ4Rh0qk+v3AIcG8sf8Pcom7HzUGE8M7GgJq
# MYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMA
# AAGt/N9NWONdMukAAQAAAa0wDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJ
# AzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgF768GdmdW4//RP/fkoCB
# LnT/akamF5iO3ueis+GyXc8wgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCCf
# 6nw9CR5e1+Ottcn1w992Kmn8YMTY/DWPIHeMbMtQgjCBmDCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABrfzfTVjjXTLpAAEAAAGtMCIEIFRJ
# nB3EP6SqFEFFIJShIN18hWwmoj4NWmFmp2bHNGmaMA0GCSqGSIb3DQEBCwUABIIC
# AODBeyJ0ebC+k4V2IbvmEHlCLcUn7SvFNQw8vI4RtGQ5AXhCv2GslKaNEtQtufkh
# pdYBeLl0dZ1G0tHKS3GHapdm3RtYQXwpXgZif/AYGy6RR0zgSF6GSyl1DvG/pJSq
# 20/EY4FJ7r/A+K1gp0tY9gNo51Pjyrpav8ctkw/Rq+GhPOilm06WgoFtuSkSI5rj
# lkJbrWmD0kvEfJiz297coD19bTBuYCpUlKWvzI/jsg7gpWAe3WvUuSxxTNMea3cm
# nQEOgLuErhwDZmqqco+s3LfgTiqbv5aQ9/Moi3jd2xnsVWQXhsLPMI/xRNLZGbO9
# KTk3fG/dfTXSZEGQXzu78W6JQhHTKsc1MkHWb+LMf0NzVwUFZPBJ4szrcVFdUPQu
# EYQ63Alxu6W6ypkcUk00EZrjPupyuLe5/11V0yIphFwFO5lmCBLMNLJH7oltiFTq
# FxUHZ0VXSSAZ769bSIOoodLg39kOLhHwc7Bfb6iixYJgWVIjJnoeVt4YthQV8s3F
# bXbqKrzp3nIMRUU8hrPQ/2ctMxkoWuA1Gn3R0tOZbl7ajIf1vcTvIwQK/kE5BZ8G
# RfwlipGBfWDGanDASJ+YoGIA5T1U65p5P4mg9qgkmQFAFjTmmo5/Zc597CWTwxW8
# A10LYXsnIlduOS6yW1C/3mq841e7rcX2THJfL8zfcqw9
# SIG # End signature block
