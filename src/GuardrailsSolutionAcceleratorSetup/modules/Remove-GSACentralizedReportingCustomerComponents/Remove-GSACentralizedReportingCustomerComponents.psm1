Function Remove-GSACentralizedReportingCustomerComponents {
    param (
        [Parameter(mandatory = $true, parameterSetName = 'hashtable', ValueFromPipelineByPropertyName = $true)]
        [string]
        $configString,

        [Parameter(mandatory = $true, ParameterSetName = 'configFile')]
        [string]
        [Alias(
            'configFileName'
        )]
        $configFilePath,

        # lighthouseServiceProviderTenantID
        [Parameter(Mandatory = $true, parameterSetname = 'manualParams')]
        [String]
        $lighthouseServiceProviderTenantID,

        # subscriptionID where Guardrails Solution Accelerator is deployed
        [Parameter(Mandatory = $true, parameterSetname = 'manualParams')]
        [String]
        $subscriptionId,

        # force removal of resources
        [Parameter(Mandatory = $false)]
        [switch]
        $force,

        # wait for removal of resources
        [Parameter(Mandatory = $false)]
        [switch]
        $wait
    )
    $ErrorActionPreference = 'Stop'
    
    Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Deploy-GuardrailsSolutionAccelerator\Deploy-GuardrailsSolutionAccelerator.psd1") -Function 'Confirm-GSASubscriptionSelection','Confirm-GSAConfigurationParameters'

    If ($configString) {
        If (Test-Json -Json $configString) {
            $config = ConvertFrom-Json -InputObject $configString -AsHashtable
        }
        Else {
            Write-Error -Message "The config parameter (or value from the pipeline) is not valid JSON. Please ensure that the config parameter is a valid JSON string or a path to a valid JSON file." -ErrorAction Stop
        }
    }
    ElseIf ($configFilePath) {
        $config = Confirm-GSAConfigurationParameters -configFilePath $configFilePath
    }
    ElseIf ($PSCmdlet.ParameterSetName -eq 'manualParams') {
        $config = @{
            lighthouseServiceProviderTenantID = $lighthouseServiceProviderTenantID
            subscriptionId = $subscriptionId
        }
    }

    If (!$lighthouseServiceProviderTenantID) {
        $lighthouseServiceProviderTenantID = $config.lighthouseServiceProviderTenantID
    }

    Confirm-GSASubscriptionSelection -confirmSingleSubscription:(!$force.IsPresent) -config $config
    $config.subscriptionId = (Get-AzContext).Subscription.id

    If (!$force.IsPresent) {
        Write-Warning "This action will delete Lighthouse definitions and assignments associated with the managing tenant ID '$lighthouseServiceProviderTenantID' in subscription '$($config.subscriptionId)'. `n`nIf you are not certain you want to perform this action, press CTRL+C to cancel; otherwise, press ENTER to continue."
        Read-Host
    }

    # get lighthouse definitions for the managing tenant
    Write-Verbose "Checking for lighthouse registration definitions for managing tenant '$lighthouseServiceProviderTenantID'..."

    $uri = 'https://management.azure.com/subscriptions/{0}/providers/Microsoft.ManagedServices/registrationdefinitions?api-version=2022-01-01-preview&$filter=managedByTenantId eq {1}' -f `
        $config.subscriptionId, "'$lighthouseServiceProviderTenantID'"
    $response = Invoke-AzRestMethod -Method GET -Uri $uri

    If ($response.StatusCode -notin 200,404) {
        Write-Error "An error occurred while retrieving Lighthouse registration definitions. Error: $($response.Content)"
        break
    }

    Write-Verbose "Found $($response.Content.value.Count) registration definitions for managing tenant '$lighthouseServiceProviderTenantID', filtering for registration definitions with the name 'SSC CSPM - Read Guardrail Status'..."
    $definitionsValue = $response.Content | ConvertFrom-Json | Select-Object -ExpandProperty value
    $guardrailReaderDefinitions = $definitionsValue | Where-Object { $_.Properties.registrationDefinitionName -eq 'SSC CSPM - Read Guardrail Status' }

    If ($guardrailReaderDefinitions.count -eq 0) {
        Write-Verbose "No Lighthouse registration definitions found for the managing tenant ID '$lighthouseServiceProviderTenantID'."
    }
    ElseIf (($guardrailReaderDefinitions.count -gt 1)) {
        Write-Error "More than 1 Lighthouse registration definition found for the managing tenant ID '$lighthouseServiceProviderTenantID' with the description 'SSC CSPM - Read Guardrail Status', unable to determine which to remove."
        break
    }
    Else {
        Write-Verbose "Found '$($guardrailReaderDefinitions.count)' Lighthouse registration definitions for the managing tenant ID '$lighthouseServiceProviderTenantID' with the description 'SSC CSPM - Read Guardrail Status'."
        #remove lighthouse assignments
        Write-Verbose "Checking for Lighthouse assignments for managing tenant '$lighthouseServiceProviderTenantID' and definition ID '$($guardrailReaderDefinitions.id)'..."
        $uri = 'https://management.azure.com/subscriptions/{0}/providers/Microsoft.ManagedServices/registrationAssignments?api-version=2022-01-01-preview&$filter=registrationDefinitionId eq {1}' -f `
            $config.subscriptionId, "'$($guardrailReaderDefinitions.id)'"
        $response = Invoke-AzRestMethod -Method GET -Uri $uri -Verbose

        If ($response.StatusCode -notin 200,404) {
            Write-Error "An error occurred while retrieving Lighthouse assignments. Error: $($response.Content)"
            break
        }

        $assignmentValue = $response.Content | ConvertFrom-Json
    
        ForEach ($assignment in $assignmentValue) {
            If ($assignment.Value.name) {
                Write-Verbose "Deleting lighthouse assignment '$($assignment.Value.id)'"
                $uri = 'https://management.azure.com{0}?api-version=2022-01-01-preview' -f $assignment.value.id
    
                $response = Invoke-AzRestMethod -Method DELETE -Uri $uri -Verbose

                If ($response.statusCode -notin 200,202,204) {
                    Write-Error "An error occurred while deleting Lighthouse assignment $($assignment.name). Error: Status Code: $($response.statusCode); message: $($response.Content)"
                    break
                }
            }
        }
    
        ForEach ($definition in $guardrailReaderDefinitions) {
            if ($definition.name) {
                Write-Verbose "Deleteing lighthouse registration definition '$($definition.Name)'"
                $uri = 'https://management.azure.com/subscriptions/{0}/providers/Microsoft.ManagedServices/registrationdefinitions/{1}?api-version=2022-01-01-preview' -f $config.subscriptionId, $definition.Name
    
                $response = Invoke-AzRestMethod -Method DELETE -Uri $uri -Verbose

                if ($response.StatusCode -eq 409) {
                    Write-Warning "The lighthouse assignment(s) associated with the registration definition '$($definition.Name)' have not finished deleting. The script will try again after 60 seconds..."
                    Start-Sleep -Seconds 60
                    
                    $response = Invoke-AzRestMethod -Method DELETE -Uri $uri -Verbose
                }
                if ($response.statusCode -notin 200,202,204) {
                    Write-Error "An error occurred while deleting Lighthouse registration definition $($definition.Name). Status code: '$($response.statusCode)' Error: $($response.Content)"
                    break
                }
            }
        }
    }
    
    Write-Host "Completed Removing Lighthouse definitions and assignments for the managing tenant ID '$lighthouseServiceProviderTenantID' in subscription '$($config.subscriptionId)'." -ForegroundColor Green
}
