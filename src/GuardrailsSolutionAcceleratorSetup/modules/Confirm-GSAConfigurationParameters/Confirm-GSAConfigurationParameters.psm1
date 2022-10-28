Function Confirm-GSASubscriptionSelection {
    param (
        # config object
        [Parameter(Mandatory = $false)]
        [hashtable]
        $config = @{},

        # confirm the subscription selection, even if there is only one subscription
        [Parameter(Mandatory = $false)]
        [switch]
        $confirmSingleSubscription
    )
    $ErrorActionPreference = 'Stop'

    $subs = Get-AzSubscription -ErrorAction SilentlyContinue
    if (-not($subs)) {
        Connect-AzAccount
    }
    if ([string]::IsNullOrEmpty($config.subscriptionId)) {
        $subs = Get-AzSubscription -ErrorAction SilentlyContinue
        if ($subs.count -gt 1) {
            Write-output "More than one subscription detected. Current subscription $((get-azcontext).Name)"
            Write-output "Please select subscription for deployment or Enter to keep current one:"
            $i = 1
            $subs | ForEach-Object { Write-output "$i - $($_.Name) - $($_.SubscriptionId)"; $i++ }
            [int]$selection = Read-Host "Select Subscription number: (1 - $($i-1))"
        }
        else { $selection = 0 }
        if ($selection -ne 0) {
            if ($selection -gt 0 -and $selection -le ($i - 1)) { 
                $null = Select-AzSubscription -SubscriptionObject $subs[$selection - 1]
                
                $config['subscriptionId'] = $subs[$selection - 1].Id
            }
            else {
                Write-output "Invalid selection. ($selection)"
                break
            }
        }
        else {
            If ($confirmSingleSubscription.IsPresent) {
                do { $prompt = Read-Host -Prompt "Do you want to continue with the current subscription ($($subs[0].Name))? (y/n)" }
                until ($prompt -match '[yn]')

                if ($prompt -eq 'y') {
                    Write-Verbose "Using current subscription '$($subs[0].Name)'"

                    $config['runtime']['subscriptionId'] = $subs[0].Id
                }
                elseif ($prompt -eq 'n') {
                    Write-Output "Exiting without modifying Guardrails Solution Accelerator..."
                    break
                }
            }
            Else {
                $config['runtime']['subscriptionId'] = $subs[0].Id
            }
        }
    }
    else {
        Write-Host "Selecting subscription: '$($config.subscriptionId)'"
        try {
            $null = Select-AzSubscription -Subscription $config.subscriptionId
        }
        catch {
            Write-error "Error selecting provided subscription."
            break
        }
    }
}
Function Confirm-GSAConfigurationParameters {
    <#
.SYNOPSIS
    Verifies that the configuration parameters in the config file specified with -configFilePath are valid.
.DESCRIPTION
    
.NOTES
    
.LINK

.INPUTS
    A configuration JSON file at the path specified with configFilePath.

.OUTPUTS
    Outputs a verified object containing the configuration values.
    
.EXAMPLE
    Confirm-GSAConfigurationParameters -configFilePath
#>
    param (
        [Parameter(mandatory = $true, parameterSetName = 'configFile')]
        [string]
        $configFilePath,

        [Parameter(mandatory = $true, parameterSetName = 'configString')]
        [string]
        $configString
    )

    $ErrorActionPreference = 'Stop'

    Write-Verbose "Starting validation of configuration file/string and parameters..."

    If ($configFilePath) {
        # verify path is valid
        Write-Verbose "Verifying that the file specified by -configFilePath exists at '$configFilePath'"
        If (-NOT (Test-Path -Path $configFilePath -PathType Leaf)) {
            Write-Error "File specified with -configFilePath does not exist, you do not have access, or it is not a file."
            break
        }

        Write-Verbose "Reading contents of '$configFilePath'"
        $configString = Get-Content -Path $configFilePath -Raw
    }

    # verify file is a valid JSON file
    Write-Verbose "Verifying that the contents of '$configFilePath'/-configString is a valid JSON document"
    If (-NOT(Test-Json -Json $configString)) {
        Write-Error "Content of '$configFilePath' is not a valid JSON document; verify the file syntax and formatting."
        break
    }

    # import config and create a hashtable object
    Write-Verbose "Creating config hashtable object"
    $config = @{}
    $configObject = $configString | ConvertFrom-Json
    $configObject.PSObject.Properties | ForEach-Object {
        $config += @{ $_.Name = $_.Value }
    }

    # verify standard config parameters
    if ($config.SecurityLAWResourceId.split("/").Count -ne 9) {
        Write-Output "Error in SecurityLAWResourceId ID ('$($config.SecurityLAWResourceId)'). Parameter needs to be a full resource Id. (/subscriptions/<subid>/...)"
        Break
    }
    if ( $config.HealthLAWResourceId.Split("/").Count -ne 9) {
        Write-Output "Error in HealthLAWResourceId ID ('$($config.HealthLAWResourceId)'). Parameter needs to be a full resource Id. (/subscriptions/<subid>/...)"
        Break
    }

    # get tenant id from curent context
    $context = Get-AzContext
    $tenantId = $context.Tenant.Id

    # verify Lighthouse config parameters
    $lighthouseServiceProviderTenantID = $config.lighthouseServiceProviderTenantID
    $lighthousePrincipalDisplayName = $config.lighthousePrincipalDisplayName
    $lighthousePrincipalId = $config.lighthousePrincipalId
    $lighthouseTargetManagementGroupID = $config.lighthouseTargetManagementGroupID
    If ($configureLighthouseAccessDelegation.isPresent) {
        # verify input from config.json
        if ([string]::IsNullOrEmpty($lighthouseServiceProviderTenantID) -or !($lighthouseServiceProviderTenantID -as [guid])) {
            Write-Error "Lighthouse delegation cannot be configured when config.json parameter 'lighthouseServiceProviderTenantID' has a value of '$lighthouseServiceProviderTenantID'"
            break
        }
        if ([string]::IsNullOrEmpty($lighthousePrincipalDisplayName)) {
            Write-Error "Lighthouse delegation cannot be configured when config.json parameter 'lighthousePrincipalDisplayName' has a value of '$lighthousePrincipalDisplayName'"
            break
        }
        if ([string]::IsNullOrEmpty($lighthousePrincipalId) -or !($lighthousePrincipalId -as [guid])) {
            Write-Error "Lighthouse delegation cannot be configured when config.json parameter 'lighthousePrincipalId' has a value of '$lighthousePrincipalId'"
            break
        }
        if ([string]::IsNullOrEmpty($lighthouseTargetManagementGroupID)) {
            Write-Error "Lighthouse delegation cannot be configured when config.json parameter 'lighthouseTargetManagementGroupID' has a value of '$lighthouseTargetManagementGroupID'"
            break
        }
    }

    # generate run-time config parameters
    $config['runtime'] = @{}

    ## confirm subscription selection
    Confirm-GSASubscriptionSelection -config $config
    
    ## get tenant default domain - use Graph to support SPNs
    $response = Invoke-AzRestMethod -Method get -uri 'https://graph.microsoft.com/v1.0/organization' | Select-Object -expand Content | convertfrom-json -Depth 10
    $tenantDomainUPN = $response.value.verifiedDomains | Where-Object { $_.isDefault } | Select-Object -ExpandProperty name # onmicrosoft.com is verified and default by default

    ## get executing user identifier
    If ($context.Account -match '^MSI@') {
        # running in Cloud Shell, finding delegated user ID
        $userId = (Get-AzAdUser -SignedIn).Id
    }
    ElseIf ($context.Account.Type -eq 'ServicePrincipal') {
        $sp = Get-AzADServicePrincipal -ApplicationId $context.Account.Id
        $userId = $sp.Id
    }
    Else {
        # running locally
        $userId = (Get-AzAdUser -SignedIn).Id
    }

    ## gets tags information from tags.json, including version and release date.
    $tagsTable = get-content -path "$PSScriptRoot/../../../../setup/tags.json" | convertfrom-json -AsHashtable

    ## unique resource name suffix, default to last segment of tenant ID
    If ([string]::IsNullOrEmpty($config.uniqueNameSuffix)) {
        $uniqueNameSuffix = "-" + $tenantId.Split("-")[0]
    }

    ## generate resource names
    #TO-DO: switch to keyVaulNamePrefix, etc and existingKeyVauleName in config.json
    $config['runtime']['keyVaultName'] = $config.KeyVaultName + $uniqueNameSuffix
    $config['runtime']['logAnalyticsWorkspaceName'] = $config.logAnalyticsWorkspaceName + $uniqueNameSuffix
    $config['runtime']['resourceGroup'] = $config.resourceGroup + $uniqueNameSuffix
    $config['runtime']['automationAccountName'] = $config.automationAccountName + $uniqueNameSuffix
    $config['runtime']['storageAccountName'] = $config.storageAccountName + $uniqueNameSuffix.replace('-', '') # remove hyphen, which is not supported in storage account name

    # add values to config object
    $config['runtime']['tenantId'] = $tenantId
    $config['runtime']['tenantDomainUPN'] = $tenantDomainUPN
    $config['runtime']['tenantRootManagementGroupId'] = '/providers/Microsoft.Management/managementGroups/{0}' -f $tenantId
    $config['runtime']['userId'] = $userId
    $config['runtime']['tagsTable'] = $tagsTable
    $config['runtime']['deployLAW'] = $true
    $config['runtime']['deployKV'] = $true
    
    # output the configuration as an object
    Write-Host "Validation of configuration parameters completed successfully!" -ForegroundColor Green

    Write-Verbose "Returning config object: `n $($config.GetEnumerator() | Sort-Object -Property Name | Out-String)"
    Write-Verbose "Returning config object (runtime values): `n $($config.runtime.GetEnumerator() | Sort-Object -Property Name | Out-String)"

    $config

    Write-Verbose "Validation of configuration file and parameters complete"
}
