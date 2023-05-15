<#
.SYNOPSIS
    
.DESCRIPTION
    
.NOTES
    
.LINK
    
.EXAMPLE

#>

Function Update-GSAAutomationRunbooks {
    param (
        # config
        [Parameter(mandatory = $true)]
        [psobject]
        $config
    )
    $ErrorActionPreference = 'Stop'
    
    # define runbook variables
    $mainRunbookName = "main"
    $mainRunbookDescription = "Guardrails Main Runbook"
    $backendRunbookName = "backend"
    $backendRunbookDescription = "Guardrails Backend Runbook"

    $currentMainRunbook = Get-AzAutomationRunbook -ResourceGroupName $config['runtime']['resourceGroup'] -AutomationAccountName $config['runtime']['automationAccountName'] -Name $mainRunbookName
    $currentBackendRunbook = Get-AzAutomationRunbook -ResourceGroupName $config['runtime']['resourceGroup'] -AutomationAccountName $config['runtime']['automationAccountName'] -Name $backendRunbookName

    # define runbook import parameters
    $updateRunbookParams = @{
        automationAccountName = $config['runtime']['automationAccountName']
        resourceGroupName     = $config['runtime']['resourceGroup']
        type                  = 'PowerShell'
        tags                  = @{version = $config['runtime']['tagsTable'].ReleaseVersion; releaseDate = $config['runtime']['tagsTable'].ReleaseDate } 
        force                 = $true
        published             = $true
    }
    Write-Verbose "Importing updated Runbooks..."

    Write-Verbose "Importing 'main' runbook version '$($config['runtime']['tagsTable'].ReleaseVersion)', replacing version '$($currentMainRunbook.Tags['version'])'..."
    $null = Import-AzAutomationRunbook -Name $mainRunbookName -Path "$PSScriptRoot/../../../../setup/main.ps1" -Description "$mainRunbookDescription V.$($config['runtime']['tagsTable'].ReleaseVersion)" @updateRunbookParams

    Write-Verbose "Importing 'backend' runbook version '$($config['runtime']['tagsTable'].ReleaseVersion)', replacing version '$($currentBackendRunbook.Tags['version'])'..."
    $null = Import-AzAutomationRunbook -Name $backendRunbookName -Path "$PSScriptRoot/../../../../setup/backend.ps1" -Description "$backendRunbookDescription V.$($config['runtime']['tagsTable'].ReleaseVersion)" @updateRunbookParams

    Write-Verbose "Exporting modules.json to Storage Account '$($config['runtime']['StorageAccountName'])' for runbook consumption"

    import-module "$PSScriptRoot/../../../../src/Guardrails-Common/GR-Common.psm1"
    $modulesJsonPath = "$PSScriptRoot/../../../../setup/modules.json"
    copy-toBlob -FilePath $modulesJsonPath -storageaccountName $config['runtime']['storageAccountName'] -resourceGroup $config['runtime']['resourceGroup'] -force -containerName "configuration"
}
