Import-Module "$PSScriptRoot/../Manage-GSATags/Manage-GSATags.psd1"

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
        $paramObject
    )
    $ErrorActionPreference = 'Stop'

    Write-Verbose "Initating update deployment of core GSA resources..."
    
    Write-Verbose "Updating GSA Resource Group tags because -updateComponents 'All' specified..."
    $resourceGroupId = "/subscriptions/$($config['runtime']['subscriptionId'])/resourceGroups/$($config['runtime']['resourceGroup'])"
    Invoke-GSATagPolicyOperation {
        Update-AzTag -ResourceId $resourceGroupId -Tag $config['runtime']['tagsTable'] -Operation Merge | Out-Null
    }

    # deploy primary bicep template
    Write-Verbose "Updating GSA core resource via bicep template..."
    try { 
        $mainBicepDeployment = Invoke-GSATagPolicyOperation {
            $result = New-AzResourceGroupDeployment -ResourceGroupName $config['runtime']['resourceGroup'] -Name "guardraiUpdate$(get-date -format "ddmmyyHHmmss")" `
                -TemplateParameterObject $paramObject -TemplateFile "$PSScriptRoot/../../../../setup/IaC/guardrails.bicep" -WarningAction SilentlyContinue -ErrorAction Stop
            # Confirm Azure completed the update before reporting success.
            # Otherwise the installer could finish the policy transition and
            # reject the previous tags while core resources are still incomplete.
            if ($result.ProvisioningState -ne 'Succeeded') { throw 'Core resource deployment did not succeed.' }
            $result
        }
    }
    catch {
        Write-error "Failed to deploy main Guardrails Accelerator template with error: $_" 
        Exit
    }
}
