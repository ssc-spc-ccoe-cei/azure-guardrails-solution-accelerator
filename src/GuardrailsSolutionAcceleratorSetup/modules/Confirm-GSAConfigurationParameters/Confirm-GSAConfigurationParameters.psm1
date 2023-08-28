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
        Connect-AzAccount | Out-Null
    }
    if ([string]::IsNullOrEmpty($config.subscriptionId)) {
        $subs = Get-AzSubscription -ErrorAction SilentlyContinue  | Where-Object { $_.State -eq "Enabled" } | Sort-Object -Property Name
        if ($subs.count -gt 1) {
            Write-Host "More than one subscription detected. Current subscription $((get-azcontext).Name)"
            Write-Host "Please select subscription for deployment or Enter to keep current one:"
            $i = 1
            $subs | ForEach-Object { Write-Host "$i - $($_.Name) - $($_.SubscriptionId)"; $i++ }
            [int]$selection = Read-Host "Select Subscription number: (1 - $($i-1))"
        }
        else { $selection = 0 }
        if ($selection -ne 0) {
            if ($selection -gt 0 -and $selection -le ($i - 1)) { 
                $null = Select-AzSubscription -SubscriptionObject $subs[$selection - 1]
                
                $config['runtime']['subscriptionId'] = $subs[$selection - 1].Id
            }
            else {
                Write-Host "Invalid selection. ($selection)"
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
                    Write-Host "Exiting without modifying Guardrails Solution Accelerator..."
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
            $context = Select-AzSubscription -Subscription $config.subscriptionId
            $config['runtime']['subscriptionId'] = $context.Subscription.Id
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

    # verify params match expected patterns
    Write-Verbose "Validating parameters in config file/string..."
    $paramsValidationTable = @{
        keyVaultName                      = @{
            IsRequired        = $true
            ValidationPattern = '^[a-z0-9][a-z0-9-]{3,12}$'
        }
        resourcegroup                     = @{
            IsRequired        = $true
            ValidationPattern = '^[a-z0-9][a-z0-9-_]{2,64}$'
        }
        region                            = @{
            IsRequired     = $false
            ValidationList = (Get-AzLocation).Location
        }
        storageaccountName                = @{
            IsRequired        = $true
            ValidationPattern = '^[a-z0-9][a-z0-9]{2,11}$'
        }
        logAnalyticsworkspaceName         = @{
            IsRequired        = $true
            ValidationPattern = '^[a-z0-9][a-z0-9-_]{2,51}[a-z0-9]$'
        }
        autoMationAccountName             = @{
            IsRequired        = $true
            ValidationPattern = '^[a-z0-9][a-z0-9-_]{2,40}[a-z0-9]$'
        }
        PBMMPolicyID                      = @{
            IsRequired       = $true
            ValidationByType = 'guid'
        }
        AllowedLocationPolicyId           = @{
            IsRequired       = $true
            ValidationByType = 'guid'
        }
        FirstBreakGlassAccountUPN         = @{
            IsRequired        = $true
            ValidationPattern = '^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$'
        }
        SecondBreakGlassAccountUPN        = @{
            IsRequired        = $true
            ValidationPattern = '^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$'
        }
        DepartmentNumber                  = @{
            IsRequired       = $true
            ValidationByType = 'int'
        }
        CBSSubscriptionName               = @{
            IsRequired        = $false
            ValidationPattern = '^([a-zA-Z0-9][a-zA-Z0-9-_]{2,128})|(N/A)$'
        }
        SSCReadOnlyServicePrincipalNameAPPID = @{
            IsRequired        = $true
            ValidationByType = 'guid'
        }
        SecurityLAWResourceId             = @{
            IsRequired        = $true
            ValidationPattern = '^\/subscriptions\/[a-fA-F0-9]{8}-([a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}\/resourceGroups\/[^\/]+\/providers\/[^\/]+(\/[^\/]+)*$'
        }
        HealthLAWResourceId               = @{
            IsRequired        = $true
            ValidationPattern = '^\/subscriptions\/[a-fA-F0-9]{8}-([a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}\/resourceGroups\/[^\/]+\/providers\/[^\/]+(\/[^\/]+)*$'
        }
        Locale                            = @{
            IsRequired     = $true
            ValidationList = @('en-ca', 'fr-ca')
        }
        lighthouseServiceProviderTenantID = @{
            IsRequired       = $false
            ParameterSetName = 'lighthouse'
            ValidationByType = 'guid'
        }
        lighthousePrincipalDisplayName    = @{
            IsRequired        = $false
            ParameterSetName  = 'lighthouse'
            ValidationPattern = '^[a-zA-Z0-9][a-zA-Z0-9-_\s]{2,128}$'
        }
        lighthousePrincipalId             = @{
            IsRequired       = $false
            ParameterSetName = 'lighthouse'
            ValidationByType = 'guid'
        }
        lighthouseTargetManagementGroupID = @{
            IsRequired        = $false
            ParameterSetName  = 'lighthouse'
            ValidationPattern = '^[a-zA-Z0-9][a-zA-Z0-9-_\s]{2,128}$'
        }
        securityRetentionDays             = @{
            IsRequired       = $false
            ValidationByType = 'int'
        }
        cloudUsageProfiles                = @{
            IsRequired        = $false
            ValidationPattern = '^default|([0-9](,[0-9]){0,9})$'
        }
    }

    ForEach ($configParam in $config.GetEnumerator()) {
        $paramName = $configParam.Key
        $paramValue = $configParam.Value
        $paramValidation = $paramsValidationTable[$paramName]

        Write-Verbose "Validating config file parameter '$paramName' with value '$paramValue'..."
        if ($paramValidation -eq $null) {
            Write-Warning "`tParameter '$paramName' is not a valid configuration parameter or has not been added to the `$paramsValidationTable above yet."
            continue
        }
        if ($paramValidation.IsRequired -and [string]::IsNUllOrEmpty($paramValue)) {
            Write-Error "Parameter '$paramName' is required but not specified."
            break
        }
        elseif (!$paramValidation.IsRequired -and [string]::IsNUllOrEmpty($paramValue)) {
            Write-Verbose "Parameter '$paramName' is not required and is empty, skipping."
            continue
        }
        if ($paramValidation.IsRequired -and [string]::IsNUllOrEmpty($paramValue)) {
            Write-Error "Parameter '$paramName' is required but not specified."
            break
        }
        if (![string]::IsNUllOrEmpty($paramValue) -and $null -ne $paramValidation.ValidationList -and $paramValue -notin $paramValidation.ValidationList) {
            Write-Error "Parameter '$paramName' value '$paramValue' is not in the expected list of values '$($paramValidation.ValidationList -join ', ')."
            break
        }
        if (![string]::IsNUllOrEmpty($paramValue) -and $null -ne $paramValidation.ValidationByType -and -NOT ($paramValue -as $paramValidation.ValidationByType)) {
            Write-Error "Parameter '$paramName' value '$paramValue' is not a valid type '$($paramValidation.ValidationByType)'."
            break
        }
        if (![string]::IsNUllOrEmpty($paramValue) -and $null -ne $paramValidation.ValidationPattern -and $paramValue -inotmatch $paramValidation.ValidationPattern) {
            Write-Error "Parameter '$paramName' value '$paramValue' does not match the expected pattern '$($paramValidation.ValidationPattern)'."
            break
        }
    }

    
    # verify that Department Number has an associated Department Name, get name value for AA variable
    try {
        $uri = 'https://donnees-data.tpsgc-pwgsc.gc.ca/ba1/min-dept/min-dept.csv'
        $response = Invoke-RestMethod -Method GET -Uri $uri -StatusCodeVariable statusCode -ErrorAction Stop -ResponseHeadersVariable h
    }
    catch {
        Write-Error "Error retrieving department list from '$uri'. Verify that you have access to the internet. Falling back to local department list, which may be outdated."
        
        $departmentList = Import-Csv -Path "$PSScriptRoot/../../../../setup/departmentList.csv"
    }
    If ($statusCode -eq 200) {
        try {
            $departmentList = $response | ConvertFrom-CSV -ErrorAction Stop
        }
        catch {
            Write-Error "Error converting department list from CSV to hashtable. Verify that the CSV format and response is valid!"
            break
        }
        
        If ($departmentList.'Department_number-Ministère_numéro' -notcontains $config.DepartmentNumber) {
            Write-Error "Department Number '$($config.DepartmentNumber)' is not a valid department number or is not found in this GOC-published list: $uri. Verify that the department number is correct and that the published list is accurate."
            $departmentName = 'Department_Name_Unknown'
        }
        Else {
            $departmentName = $departmentList | Where-Object { $_.'Department_number-Ministère_numéro' -eq $config.DepartmentNumber } | 
            Select-Object -ExpandProperty 'Department-name_English-Ministère_nom_anglais'
        }
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

    ## add department name
    $config['runtime']['DepartmentName'] = $departmentName

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
        $uniqueNameSuffix = '-' + $tenantId.Split("-")[0]
    }
    Else {
        $uniqueNameSuffix = '-' + $config.uniqueNameSuffix
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

