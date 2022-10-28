<#
.SYNOPSIS
    
.DESCRIPTION
    
.NOTES
    
.LINK
    
.EXAMPLE

#>
Function Update-GSACoreResources {
    param (
        # config
        [Parameter(mandatory = $true)]
        [psobject]
        $config,

        # parameter object
        [Parameter(mandatory = $true)]
        [psobject]
        $paramObject,

        # update components list
        [Parameter(Mandatory = $true)]
        [string[]]
        $updateComponents
    )
    $ErrorActionPreference = 'Stop'

    Write-Verbose "Initating update deployment of core GSA resources..."

    If ($updateComponents -contains "All") {
        Write-Verbose "Updating GSA Resource Group tags because -updateComponents 'All' specified..."
        $resourceGroupId = "/subscriptions/$($config['runtime']['subscriptionId'])/resourceGroups/$($config['runtime']['resourceGroup'])"
        Update-AzTag -ResourceId $resourceGroupId -Tag $config['runtime']['tagsTable'] -Operation Merge | Out-Null
    }
    Else {
        Write-Warning "Skipping GSA Resource Group tags update because -updateComponents 'All' not specified..."
    }

    # deploy primary bicep template
    Write-Verbose "Updating GSA core resource via bicep template..."
    try { 
        $mainBicepDeployment = New-AzResourceGroupDeployment -ResourceGroupName $config['runtime']['resourceGroup'] -Name "guardraiUpdate$(get-date -format "ddmmyyHHmmss")" `
            -TemplateParameterObject $paramObject -TemplateFile "$PSScriptRoot/../../../../setup/IaC/guardrails.bicep" -WarningAction SilentlyContinue -ErrorAction Stop
    }
    catch {
        Write-error "Failed to deploy main Guardrails Accelerator template with error: $_" 
        Exit
    }
}