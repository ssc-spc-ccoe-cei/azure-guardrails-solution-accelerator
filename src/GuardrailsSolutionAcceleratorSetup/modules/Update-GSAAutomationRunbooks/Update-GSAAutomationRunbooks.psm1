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
    # Verify the modules.json file exists
    if (-not (Test-Path $modulesJsonPath)) {
        throw "Critical: modules.json file not found at path: $modulesJsonPath"
    }
    
    Write-Verbose "Uploading modules.json to blob storage container 'configuration'..."
    try {
        copy-toBlob -FilePath $modulesJsonPath -storageaccountName $config['runtime']['storageAccountName'] -resourceGroup $config['runtime']['resourceGroup'] -force -containerName "configuration" -ErrorAction Stop
        
        # Verify the upload succeeded by checking the blob exists
        Write-Verbose "Verifying modules.json was successfully uploaded to blob storage..."
        $storageAccount = Get-AzStorageAccount -ResourceGroupName $config['runtime']['resourceGroup'] -Name $config['runtime']['storageAccountName'] -ErrorAction Stop
        $blob = Get-AzStorageBlob -Container "configuration" -Blob "modules.json" -Context $storageAccount.Context -ErrorAction SilentlyContinue
        
        if ($null -eq $blob) {
            throw "Critical: modules.json upload verification failed - blob not found in storage account after upload"
        }

        # Verify the blob was updated today (for upgrade scenario)
        $today = (Get-Date).Date
        $blobLastModifiedDate = $blob.LastModified.UtcDateTime.Date
        
        if ($blobLastModifiedDate -lt $today) {
            throw "Critical: modules.json blob verification failed - LastModified date ($blobLastModifiedDate) is not today ($today). This indicates the blob was not updated during the upgrade. The blob may be stale from a previous deployment."
        }
        
        Write-Verbose "Successfully uploaded and verified modules.json to blob storage. Blob LastModified: $($blob.LastModified.UtcDateTime) (UTC)"
        Write-Host "Successfully updated modules.json in blob storage container 'configuration' (LastModified: $($blob.LastModified.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss')) UTC)" -ForegroundColor Green        
    }
    catch {
        $errorMessage = "Critical: Failed to upload modules.json to blob storage. This will cause runbook execution to fail. Error: $_"
        Write-Error $errorMessage
        throw $errorMessage
    }
}
