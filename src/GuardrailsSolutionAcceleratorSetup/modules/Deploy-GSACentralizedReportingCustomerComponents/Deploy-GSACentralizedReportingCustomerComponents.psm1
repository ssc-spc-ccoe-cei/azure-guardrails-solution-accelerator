Function Deploy-GSACentralizedReportingCustomerComponents {

    param (
        # config
        [Parameter(mandatory = $true)]
        [psobject]
        $config
    )
    $ErrorActionPreference = 'Stop'

    Write-Verbose "Starting deployment of Lighthouse delegation of access to the GSA resource group"
    $lighthouseBicepPath = "$PSScriptRoot/../../../../setup/lighthouse/"

    #build lighthouse parameter object for resource group delegation
    $bicepParams = @{
        'rgName'               = $config['runtime']['resourceGroup']
        'managedByTenantId'    = $config.lighthouseServiceProviderTenantID
        'managedByName'        = 'SSC CSPM - Read Guardrail Status'
        'managedByDescription' = 'SSC CSPM - Read Guardrail Status'
        'authorizations'       = @(
            @{
                'principalIdDisplayName' = $config.lighthousePrincipalDisplayName
                'principalId'            = $config.lighthousePrincipalId
                'roleDefinitionId'       = 'acdd72a7-3385-48ef-bd42-f606fba81ae7' # Reader
            }
            @{
                "principalId"            = $config.lighthousePrincipalId
                "roleDefinitionId"       = "43d0d8ad-25c7-4714-9337-8ba259a9fe05" # monitoring reader
                "principalIdDisplayName" = $config.lighthousePrincipalDisplayName
            }
            @{
                'principalIdDisplayName' = $config.lighthousePrincipalDisplayName
                'principalId'            = $config.lighthousePrincipalId
                'roleDefinitionId'       = '91c1777a-f3dc-4fae-b103-61d183457e46' # Managed Services Registration assignment Delete Role
            }
        )
    }

    #deploy Guardrails resource group permission delegation
    try {
        $null = New-AzDeployment -Location $config.region `
            -TemplateFile $lighthouseBicepPath/lighthouse_rg.bicep `
            -TemplateParameterObject $bicepParams `
            -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to deploy lighthouse delegation template with error: $_"
        break
    }

    Write-Verbose "Completing deployment of Lighthouse delegation of access to the GSA resource group"

}
