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
        'AllowedLocationInitiativeId'           = $config.AllowedLocationInitiativeId
        'AllowedLocationPolicyId'               = $config.AllowedLocationPolicyId
        'automationAccountName'                 = $config['runtime']['autoMationAccountName']
        'breakglassAccount1'                    = $config.firstBreakGlassAccountUPN
        'breakglassAccount2'                    = $config.secondBreakGlassAccountUPN    
        'CBSSubscriptionName'                   = $config.CBSSubscriptionName
        'cloudUsageProfiles'                    = $config.cloudUsageProfiles
        'currentUserObjectId'                   = $config['runtime']['userId']
        'DepartmentNumber'                      = $config.DepartmentNumber
        'DepartmentName'                        = $config['runtime']['departmentName']
        'deployKV'                              = $config['runtime']['deployKV']
        'deployLAW'                             = $config['runtime']['deployLAW']
        'HealthLAWResourceId'                   = $config.HealthLAWResourceId
        'kvName'                                = $config['runtime']['keyVaultName']
        'lighthouseTargetManagementGroupID'     = $config.lighthouseTargetManagementGroupID
        'Locale'                                = $config.Locale
        'location'                              = $config.region
        'logAnalyticsWorkspaceName'             = $config['runtime']['logAnalyticsworkspaceName']
        'PBMMPolicyID'                          = $config.PBMMPolicyID
        'releasedate'                           = $config['runtime']['tagsTable'].ReleaseDate
        'releaseVersion'                        = $config['runtime']['tagsTable'].ReleaseVersion
        'SecurityLAWResourceId'                 = $config.SecurityLAWResourceId
        'SSCReadOnlyServicePrincipalNameAPPID'  = $config.SSCReadOnlyServicePrincipalNameAPPID
        'storageAccountName'                    = $config['runtime']['storageaccountName']
        'subscriptionId'                        = (Get-AzContext).Subscription.Id
        'tenantDomainUPN'                       = $config['runtime']['tenantDomainUPN']
        'securityRetentionDays'                   = $config.securityRetentionDays
        'enableMultiCloudProfiles'              = [bool]$config['runtime']['enableMultiCloudProfiles']
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
        and resource naming conventions. See this page for details: https://github.com/ssc-spc-ccoe-cei/azure-guardrails-solution-accelerator/blob/main/docs/setup.md.

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
        https://github.com/ssc-spc-ccoe-cei/azure-guardrails-solution-accelerator
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
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

        # specify to source the GSA PowerShell modules from an alternate URL - this is useful for development
        [Parameter(Mandatory = $false, ParameterSetName = 'newDeployment-configFilePath')]
        [Parameter(Mandatory = $false, ParameterSetName = 'newDeployment-configString')]
        [Parameter(Mandatory = $false, ParameterSetName = 'updateDeployment-configFilePath')]
        [Parameter(Mandatory = $false, ParameterSetName = 'updateDeployment-configString')]
        [string]
        $alternatePSModulesURL,

        # specify a release to deploy or update to - ex: 'v1.0.9', 'prerelease-v1.0.8.1'. If not specified, the latest release will be used
        # the 'latest' release is typically the last full release, unless a critcal bug fix was applied since the last full release
        [Parameter(Mandatory = $false, ParameterSetName = 'newDeployment-configFilePath')]
        [Parameter(Mandatory = $false, ParameterSetName = 'newDeployment-configString')]
        [Parameter(Mandatory = $false, ParameterSetName = 'updateDeployment-configFilePath')]
        [Parameter(Mandatory = $false, ParameterSetName = 'updateDeployment-configString')]
        [ValidatePattern('(prerelease-)?v\d+\.\d+\.\d+(\.\d+)?')]
        [string]
        $releaseVersion,

        # # if specified, deploy the lastest pre-release version. If used with -releaseVersion, the release version will take precedence
        # [Parameter(Mandatory = $false, ParameterSetName = 'newDeployment-configFilePath')]
        # [Parameter(Mandatory = $false, ParameterSetName = 'newDeployment-configString')]
        # [Parameter(Mandatory = $false, ParameterSetName = 'updateDeployment-configFilePath')]
        # [Parameter(Mandatory = $false, ParameterSetName = 'updateDeployment-configString')]
        # [switch]
        # $prerelease,

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

        # Force enableMultiCloudProfiles = $true at runtime
        if (-not $config.ContainsKey('runtime')) { 
            $config['runtime'] = @{} 
        }

        $config['runtime']['enableMultiCloudProfiles'] = $true
        Write-Verbose "Override applied: enableMultiCloudProfiles forced to TRUE"
        # Type guard
        $val = $config['runtime']['enableMultiCloudProfiles']
        if ($val -isnot [bool]) {
            $parsed = $null
            if ([bool]::TryParse([string]$val, [ref]$parsed)) {
                $config['runtime']['enableMultiCloudProfiles'] = $parsed
            } else {
                throw "enableMultiCloudProfiles must be boolean. Got '$val' (type: $($val.GetType().FullName))."
            }
        }

        Show-GSADeploymentSummary -deployParams $PSBoundParameters -deployParamSet $PSCmdlet.ParameterSetName -yes:$yes.isPresent -Verbose:$useVerbose

        # set module install or update source URL
        $params = @{}
        If ($alternatePSModulesURL) {
            Write-Verbose "-alternatePSModulesURL specified, using alternate URL for Guardrails PowerShell modules: $alternatePSModulesURL"
            $params = @{ moduleBaseURL = $alternatePSModulesURL }
        }
        ElseIf ([string]::IsNullOrEmpty($releaseVersion) -and !$prerelease.IsPresent) {
            # getting latest release from GitHub
            $latestRelease = Invoke-RestMethod 'https://api.github.com/repos/ssc-spc-ccoe-cei/azure-guardrails-solution-accelerator/releases/latest' -Verbose:$false
            $moduleBaseURL = "https://github.com/ssc-spc-ccoe-cei/azure-guardrails-solution-accelerator/raw/{0}/psmodules" -f $latestRelease.name

            Write-Verbose "Using latest release from GitHub for Guardrails PowerShell modules: $moduleBaseURL"
            $params = @{ moduleBaseURL = $moduleBaseURL }
        }
        ElseIf ($releaseVersion) {
            # check if prerelease version was specified 
            If ($releaseVersion -like 'prerelease-*') {
                Write-Warning "-releaseVersion specified with a pre-release version, using pre-release URL for Guardrails PowerShell modules. Running pre-release code is not recommended for production deployments."
            }

            # get releases from GitHub
            $releases = Invoke-RestMethod 'https://api.github.com/repos/ssc-spc-ccoe-cei/azure-guardrails-solution-accelerator/releases' -Verbose:$false
            
            If ($releases.name -contains $releaseVersion) {
                Write-Verbose "Found a release on GitHub match for $releaseVersion"
                $moduleBaseURL = "https://github.com/ssc-spc-ccoe-cei/azure-guardrails-solution-accelerator/releases/download/{0}/" -f $releaseVersion
            }
        }
        # ElseIf ($prerelease) {
        #     Write-Warning "-Prerelease specified, using pre-release URL for Guardrails PowerShell modules. Running pre-release code is not recommended for production deployments."

        #     # getting all release from github
        #     $releases = Invoke-RestMethod 'https://api.github.com/repos/ssc-spc-ccoe-cei/azure-guardrails-solution-accelerator/releases' -Verbose:$false
        #     $latestPreRelease = $releases | Where-Object { $_.prerelease -eq 'True' } | 
        #         Sort-Object -Property published_at -Descending | 
        #         Select-Object -First 1

        #     $releaseVersion = $latestPreRelease.name
        #     $moduleBaseURL = "https://github.com/ssc-spc-ccoe-cei/azure-guardrails-solution-accelerator/releases/download/{0}/" -f $releaseVersion
        # }

        # if installing from a published release, check that the release contains zip assets
        If (-NOT($alternatePSModulesURL)) {
            # check that the release contains the 'GR-Common.zip' file as an asset. 
            Write-Verbose "Checking that the release contains the 'GR-Common.zip' file as an asset..."
            try {
                $null = Invoke-RestMethod -Method HEAD -Uri "$moduleBaseURL/GR-Common.zip" -ErrorAction Stop -Verbose:$false
            }
            catch {
                Write-Error "The release $releaseVersion does not contain the 'GR-Common.zip' file as an asset. This likely means the release was not properly published, or was published using an older process and is not recommended for new deployments. See: https://github.com/ssc-spc-ccoe-cei/azure-guardrails-solution-accelerator/releases"
                return
            }
            Write-Verbose "The release $releaseVersion contains the 'GR-Common.zip' file as an asset, continuing with `$moduleBaseURL of '$moduleBaseURL'"
        }
        
        $paramObject = New-GSACoreResourceDeploymentParamObject -config $config @params -Verbose:$useVerbose

        If (!$update.IsPresent) {
            Write-Host "Deploying Guardrails Solution Accelerator components ($($newComponents -join ','))..." -ForegroundColor Green
            Write-Verbose "Performing a new deployment of the Guardrails Solution Accelerator..."

            # confirms that prerequisites are met and that deployment can proceed
            Confirm-GSAPrerequisites -config $config -newComponents $newComponents -Verbose:$useVerbose
            
            If ($newComponents -contains 'CoreComponents') {
                # deploy core resources
                Write-Host "Deploying CoreComponents..." -ForegroundColor Green
                try{
                    Deploy-GSACoreResources -config $config -paramObject $paramObject -Verbose:$useVerbose
                }
                catch{
                    Write-Error "Error in deploying GSACoreResources. $_"
                }
                
                # add runbooks to AA
                Write-Host "Adding runbooks to automation account..." -ForegroundColor Green
                try{
                    Add-GSAAutomationRunbooks -config $config -Verbose:$useVerbose
                }
                catch{
                    Write-Error "Error adding to runbook. $_"
                }
                
            }
            
            # deploy Lighthouse components
            Write-Host "Deploying Lighthouse components..." -ForegroundColor Green
            If ($newComponents -contains 'CentralizedCustomerReportingSupport') {
                Write-Host "Deploying CentralizedReportingCustomerComponents..." -ForegroundColor Green
                try{
                    Deploy-GSACentralizedReportingCustomerComponents -config $config -Verbose:$useVerbose
                }
                catch{
                    Write-Error "Error in deploying GSA centralized reporting customer components. $_"
                }
            }
            If ($newComponents -contains 'CentralizedCustomerDefenderForCloudSupport') {
                Write-Host "Deploying GSACentralizedDefenderCustomerComponents..." -ForegroundColor Green
                try{
                    Deploy-GSACentralizedDefenderCustomerComponents -config $config -Verbose:$useVerbose
                }
                catch{
                    Write-Error "Error in deploying GSA centralized defender for cloud customer components. $_"
                }
                
            }

            Write-Host "Completed new deployment."
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
                try{
                    Update-GSACoreResources -config $config -paramObject $paramObject -Verbose:$useVerbose
                }
                catch{
                    Write-Error "Error in updating GSA core resources. $_"
                }
            }
            
            # update runbook definitions in AA
            If ($componentsToUpdate -contains 'AutomationAccountRunbooks') {
                try{
                    Update-GSAAutomationRunbooks -config $config -Verbose:$useVerbose
                }
                catch{
                    Write-Error "Error in updating Azure automation runbook. $_"
                }
                
            }

            Write-Verbose "Completed update deployment."
        }

        # after successful deployment or update
        Write-Host "Invoking manual execution of Azure Automation runbooks..."
        try{
            Invoke-GSARunbooks -config $config -Verbose:$useVerbose
        }
        catch{
            Write-Error "Error in invoking Azure automation runbook. $_"
        }

        Write-Host "Exporting configuration to GSA KeyVault "
        Write-Verbose "Exporting configuration to GSA KeyVault '$($config['runtime']['keyVaultName'])' as secret 'gsaConfigExportLatest'..."
        $configSecretName = 'gsaConfigExportLatest'
        $secretTags = @{
            'deploymentTimestamp'   = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
            'deployerLocalUsername' = $env:USERNAME
            'deployerAzureID'       = $config['runtime']['userId']
        }

        # Enhanced error handling for Key Vault secret upload with retry logic
        $maxRetries = 3
        $retryDelay = 10  # seconds
        $secretUploadSuccess = $false

        for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
            try {
                Write-Verbose "Attempt $attempt of $maxRetries : Uploading gsaConfigExportLatest secret to Key Vault..."
                
                # Add delay for role assignment propagation on first attempt
                if ($attempt -eq 1) {
                    Write-Verbose "Waiting $retryDelay seconds for Key Vault role assignments to propagate..."
                    Start-Sleep -Seconds $retryDelay
                }

                $secureConfig = (ConvertTo-SecureString -String (ConvertTo-Json $config -Depth 10) -AsPlainText -Force)
                $encryptedConfig = $secureConfig | ConvertFrom-SecureString
                $secureConfig.Dispose()
                
                $secret = Set-AzKeyVaultSecret -VaultName $config['runtime']['keyVaultName'] -Name $configSecretName -SecretValue ($encryptedConfig | ConvertTo-SecureString) -Tag $secretTags -ContentType 'application/json' -Verbose:$useVerbose -ErrorAction Stop
                
                # Verify the secret was actually created
                $verifySecret = Get-AzKeyVaultSecret -VaultName $config['runtime']['keyVaultName'] -Name $configSecretName -ErrorAction Stop
                if ($verifySecret) {
                    Write-Host "Successfully uploaded gsaConfigExportLatest secret to Key Vault '$($config['runtime']['keyVaultName'])'" -ForegroundColor Green
                    $secretUploadSuccess = $true
                    break
                } else {
                    throw "Secret verification failed - secret was not found after upload"
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                Write-Warning "Attempt $attempt of $maxRetries failed to upload gsaConfigExportLatest secret: $errorMessage"
                
                if ($attempt -lt $maxRetries) {
                    $nextDelay = $retryDelay * $attempt  # Exponential backoff
                    Write-Verbose "Retrying in $nextDelay seconds..."
                    Start-Sleep -Seconds $nextDelay
                } else {
                    Write-Error "Failed to upload gsaConfigExportLatest secret after $maxRetries attempts. This will cause compliance data collection to fail."
                    Write-Error "Last error: $errorMessage"
                    Write-Error "Please check Key Vault permissions and network access settings."
                    throw "Critical: Failed to upload gsaConfigExportLatest secret to Key Vault '$($config['runtime']['keyVaultName'])' after $maxRetries attempts. Error: $errorMessage"
                }
            }
        }

        if ($secretUploadSuccess) {
            Write-Host "Completed deployment of the Guardrails Solution Accelerator!" -ForegroundColor Green
        } else {
            Write-Error "Deployment completed with errors - gsaConfigExportLatest secret upload failed. Compliance data collection will not work."
            throw "Deployment failed - gsaConfigExportLatest secret upload unsuccessful"
        }
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
