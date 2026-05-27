Function Confirm-GSATenantSelection {
    param (
        [Parameter(Mandatory = $false)]
        [hashtable]
        $config = @{}
    )
    $ErrorActionPreference = 'Stop'

    # Ensure properly singned in before listing tenants
    try{
        $courrentContext = Get-AzContext -ErrorAction SilentlyContinue
        if(-not $courrentContext -or -not $courrentContext.Account) {
            Write-Host "Not currently signed in to Azure, initiating Connect-AzAccount..."
            Connect-AzAccount | Out-Null
            $courrentContext = Get-AzContext -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Error "Error connecting to Azure. Verify that you have access to the account and try again. $_"
        break
    }
    # Retrieve tenants and select tenant for deployment
    $tenants = @(Get-AzTenant -ErrorAction SilentlyContinue | Sort-Object -Property Name)
    if ($tenants.Count -eq 0){
        Write-Warning ("Unable to list accessible tenants. Continuing with current context " + "(Tenant: $($courrentContext.Tenant.Id)).")
        $config['tenantId'] = $courrentContext.Tenant.Id
        return
    }

    # if tenantId already in config, validate then connect
    if (-not [string]::IsNullOrEmpty($config.tenantId)) {
        Write-Host "Validating tenantId from config.json: '$($config.tenantId)'"
        $target = $tenants | Where-Object { $_.Id -eq $config.tenantId }
        if (-not $target) {
            $accessibleList = ($tenants | ForEach-Object { "$($_.Name) ($($_.Id))" }) -join "`n"
            Write-Error "tenant ID '$($config.tenantId)' from config.jsdon is not  with the current account. `nAccesible tenants: `n$accessibleList"
            break
        }
        Write-Host ("Target tenant from config.json: '$($target.Name)' with tenant Id:  $($target.Id).)")
        $null = Connect-AzAccount -Tenant $target.Id -ErrorAction Stop
        return 
    }
    # if config tenant Id is not set, or the context tenant Id does not match match with config tenant id,
    # and tenant count is either 1 or more than 1, then prompt for tenant selection. Otherwise, continue with current context tenant.
    if ($tenants.Count -eq 1) {
        $selectedTenant  = $tenants[0]
        Write-Host "Only one accessible tenant found. Selecting tenant '$($selected.Name)' with tenant Id ($($selected.Id))."
        $null = Connect-AzAccount -Tenant $selected.Id -ErrorAction Stop
        return
    }
    elseif ($tenants.Count -gt 1) {
        # Select tenant for deployment from multiple accessible tenants
        Write-Host "Multiple Azure tenants detected for this account. Current tenant context is '$((get-AzContext).Tenant.Id)'."
        Write-Host "Please select tenant for deployment or Enter to keep current one:"
        $i = 1
        foreach ($tenant in $tenants){
            Write-Host "$i - $($tenant.Name) - $($tenant.Id)"
            $i++
        }
        # # [int]$selected = Read-Host "Select Tenant number: (1 - $($i-1))"
        # selected tenant
        do {[int]$selectedIndex = Read-Host "Select tenant number: (1 - $($tenants.Count))"
        }until ($selectedIndex -ge 1 -and $selectedIndex -le $($tenants.Count))
        $selectedTenant  = $tenants[$selectedIndex - 1]
    }

    # Write-Host "Selected tenant '$($selectedTenant.Name)' with tenant Id ($($selectedTenant.Id))."
    Write-Host "Connecting to tenant '$($selectedTenant.Name)' with tenant Id '$($selectedTenant.Id)'..."
    Connect-AzAccount -Tenant $selectedTenant.Id -ErrorAction Stop | Out-Null
    $config['tenantId'] = $selectedTenant.Id
    Write-Host "Connected to tenant '$($selectedTenant.Name)' with tenant Id '$($config.tenantId)'..."

    return $config
}



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
    try{
        $testJsonResult = Test-Json -Json $configString
        if(-not $testJsonResult){
            Write-Error "Content of '$configFilePath' is not a valid JSON document; verify the file syntax and formatting."
            break
        }
    }
    catch{
        Write-Error "Content of '$configFilePath' can not be parsed as JSON; verify the file syntax and formatting."
        Write-Verbose $_.Exception.Message
        break
    }

    # import config and create a hashtable object
    Write-Verbose "Creating config hashtable object"
    $config = @{}
    $configObject = $configString | ConvertFrom-Json
    $configObject.PSObject.Properties | ForEach-Object {
        $config += @{ $_.Name = $_.Value }
    }

    # tenant selection prompt
    $config = Confirm-GSATenantSelection -config $config
    Write-Host "Config tenant Id: $($config.tenantId)"

    # verify params match expected patterns
    Write-Verbose "Validating parameters in config file/string..."
    $paramsValidationTable = @{
        keyVaultName                      = @{
            IsRequired        = $true
            ValidationPattern = '^[a-z0-9][a-z0-9-]{2,14}$'
        }
        resourcegroup                     = @{
            IsRequired        = $true
            ValidationPattern = '^(?=.*guardrails)[a-z0-9-_]{2,64}$'
        }
        region                            = @{
            IsRequired     = $false
            ValidationList = (Get-AzLocation).Location
        }
        storageaccountName                = @{
            IsRequired        = $true
            ValidationPattern = '^[a-z0-9][a-z0-9]{2,14}$'
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
        AllowedLocationInitiativeId           = @{
            IsRequired       = $true
            ValidationPattern = '(^/providers/Microsoft\.Management/managementGroups/[a-zA-Z0-9_\-]+/providers/Microsoft\.Authorization/policySetDefinitions/[a-zA-Z0-9_\-]+)|(N/A)$'
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
            ValidationPattern = '^default|\[?\d+(?:,\d+)*\]?$'
        }
        tenantId = @{
            IsRequired = $true
            ValidationByType = 'guid'
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
        #fetches current public version (from repo...maybe should download the zip...)

        # Change to Option 1 before version release; using Option 2 for this issue update

        # Option: 1
        # $latestRelease = Invoke-RestMethod 'https://api.github.com/repos/ssc-spc-ccoe-cei/azure-guardrails-solution-accelerator/releases/latest' -Verbose:$false
        # $departmentListFileURI = "https://github.com/ssc-spc-ccoe-cei/azure-guardrails-solution-accelerator/raw/{0}/setup/departmentList.csv" -f $latestRelease.name
        
        # Option: 2
        # fetch updated list from main branch
        $departmentListFileURI = "https://raw.githubusercontent.com/ssc-spc-ccoe-cei/azure-guardrails-solution-accelerator/main/setup/departmentList.csv"
        
        $response = Invoke-RestMethod -Method GET -Uri $departmentListFileURI -StatusCodeVariable statusCode -ErrorAction Stop -ResponseHeadersVariable h  
    }   
    catch {
        Write-Error "Error retrieving department list from '$departmentListFileURI'. Verify that you have access to the internet. Falling back to local department list, which may be outdated."

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

    # select tenant ID (either from config or prompt) and set context
    $tenantId = $config.tenantId
    Write-Verbose "Setting Azure context to tenant ID '$tenantId' for further validation of parameters and deployment..."
    try {
        $context = Set-AzContext -TenantId $tenantId -ErrorAction Stop
        Write-Verbose "Successfully set Azure context to tenant: $tenantId"
        
    }
    catch {
        Write-Error "Failed to set Azure context to tenant: $tenantId. Error: $_"
        break
    }

    Write-Verbose "Current Azure context tenant: $((Get-AzContext).Tenant.Id), subscription: $((Get-AzContext).Subscription.Name)"
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

    # Check the current context
    Write-Verbose "Current Azure context tenant: $((Get-AzContext).Tenant.Id), subscription: $((Get-AzContext).Subscription.Name)"
    
    ## get tenant default domain - use Graph to support SPNs
    $response = Invoke-AzRestMethod -Method get -uri 'https://graph.microsoft.com/v1.0/organization' | Select-Object -expand Content | convertfrom-json -Depth 10
    $tenantDomainUPN = $response.value.verifiedDomains | Where-Object { $_.isDefault } | Select-Object -ExpandProperty name # onmicrosoft.com is verified and default by default
    Write-Verbose "Tenant domain (UPN suffix): '$tenantDomainUPN'"

    ## get executing user identifier
    Write-Verbose "Getting executing user identifier for config..."
    If ($context.Account -match '^MSI@') {
        # running in Cloud Shell, finding delegated user ID
        $userId = (Get-AzAdUser -SignedIn).Id
        Write-Verbose "Running in Cloud Shell with MSI, using signed in user ID '$userId' for config."
    }
    ElseIf ($context.Account.Type -eq 'ServicePrincipal' -or $context.Account.Type -eq 'ClientAssertion') { # Federated Identity
        $sp = Get-AzADServicePrincipal -ApplicationId $context.Account.Id
        $userId = $sp.Id
        Write-Verbose "Running with Service Principal or Federated Identity, using service principal ID '$userId' for config."
    }
    Else {
        # running locally
        $userId = (Get-AzAdUser -SignedIn).Id
        Write-Verbose "Running locally, using signed in user ID '$userId' for config."
    }

    ## gets tags information from tags.json, including version and release date
    # Write-Verbose "Getting tags information from tags.json for config..."
    $tagsTable = get-content -path "$PSScriptRoot/../../../../setup/tags.json" | convertfrom-json -AsHashtable

    ## unique resource name suffix, default to last segment of tenant ID
    If ([string]::IsNullOrEmpty($config.uniqueNameSuffix)) {
        $uniqueNameSuffix = '-' + $tenantId.Split("-")[0]
    }
    Else {
        $uniqueNameSuffix = '-' + $config.uniqueNameSuffix
    }
    Write-Verbose "Using unique name suffix '$uniqueNameSuffix' for resource naming to avoid conflicts."

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

    # add feature flag for multi cloud profile
    if ([string]::IsNullOrEmpty($config.enableMultiCloudProfiles) -or !($config.enableMultiCloudProfiles -as [bool])) {
        Write-Error "enableMultiCloudProfiles has a value of '$config.enableMultiCloudProfiles' which is not a boolean value."
        break
    }
    $config['runtime']['enableMultiCloudProfiles'] = [bool]::Parse($config.enableMultiCloudProfiles)

    # output the configuration as an object
    Write-Host "Validation of configuration parameters completed successfully!" -ForegroundColor Green

    Write-Verbose "Returning config object: `n $($config.GetEnumerator() | Sort-Object -Property Name | Out-String)"
    Write-Verbose "Returning config object (runtime values): `n $($config.runtime.GetEnumerator() | Sort-Object -Property Name | Out-String)"

    $config

    Write-Verbose "Validation of configuration file and parameters complete"
}

