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
        type                  = 'PowerShell72'
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
    $temporaryBlobContributorCreated = $false
    $storageAccountId = $null
    try {
        # Resolve the storage-account scope first so the deployer can get temporary blob upload access for this update.
        $storageAccount = Get-AzStorageAccount -ResourceGroupName $config['runtime']['resourceGroup'] -Name $config['runtime']['storageAccountName'] -ErrorAction Stop
        $storageAccountId = $storageAccount.Id

        # Reuse an existing effective assignment at this scope when present, otherwise create the temporary one this update needs.
        $existingBlobContributor = Get-AzRoleAssignment -ObjectId $config['runtime']['userId'] -Scope $storageAccountId -ErrorAction SilentlyContinue |
            Where-Object { $_.RoleDefinitionName -eq "Storage Blob Data Contributor" } |
            Select-Object -First 1

        if (-not $existingBlobContributor) {
            New-AzRoleAssignment -ObjectId $config['runtime']['userId'] -RoleDefinitionName "Storage Blob Data Contributor" -Scope $storageAccountId -ErrorAction Stop | Out-Null
            $temporaryBlobContributorCreated = $true
        }

        # Give RBAC enough time to propagate before the update gives up on uploading modules.json.
        $maxBlobAttempts = 18
        $blobRetryDelaySeconds = 20

        for ($attempt = 1; $attempt -le $maxBlobAttempts; $attempt++) {
            try {
                # Upload modules.json with the connected Entra identity instead of the storage account key.
                copy-toBlobUsingConnectedAccount -FilePath $modulesJsonPath -storageaccountName $config['runtime']['storageAccountName'] -resourceGroup $config['runtime']['resourceGroup'] -force -containerName "configuration" -ErrorAction Stop

                # Verify the blob with the same Entra-authenticated context so update follows the same auth model as runtime.
                Write-Verbose "Verifying modules.json was successfully uploaded to blob storage..."
                $storageContext = New-ConnectedStorageContext -storageaccountName $config['runtime']['storageAccountName']
                $blob = Get-AzStorageBlob -Container "configuration" -Blob "modules.json" -Context $storageContext -ErrorAction SilentlyContinue

                if ($null -eq $blob) {
                    throw "Critical: modules.json upload verification failed - blob not found in storage account after upload"
                }

                # Keep the existing update check that confirms the blob was actually refreshed during this run.
                $today = (Get-Date).ToUniversalTime().Date
                $blobLastModifiedDate = $blob.LastModified.UtcDateTime.Date

                if ($blobLastModifiedDate -lt $today) {
                    throw "Critical: modules.json blob verification failed - LastModified date ($blobLastModifiedDate) is not today ($today). This indicates the blob was not updated during the upgrade. The blob may be stale from a previous deployment."
                }

                Write-Verbose "Successfully uploaded and verified modules.json to blob storage. Blob LastModified: $($blob.LastModified.UtcDateTime) (UTC)"
                Write-Host "Successfully updated modules.json in blob storage container 'configuration' (LastModified: $($blob.LastModified.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss')) UTC)" -ForegroundColor Green
                break
            }
            catch {
                # Keep retrying while RBAC settles, but stop immediately once the final attempt is exhausted.
                if ($attempt -eq $maxBlobAttempts -or -not (Test-GSARetryableBlobError -ErrorRecord $_)) {
                    throw
                }

                Write-Verbose "Attempt $attempt of $maxBlobAttempts could not upload or verify modules.json yet. Waiting $blobRetryDelaySeconds seconds before retrying. Error: $($_.Exception.Message)"
                Start-Sleep -Seconds $blobRetryDelaySeconds
            }
        }
    }
    catch {
        $errorMessage = "Critical: Failed to upload modules.json to blob storage. This will cause runbook execution to fail. Error: $_"
        Write-Error $errorMessage
        throw $errorMessage
    }
    finally {
        # Remove the temporary blob role when this update created it and no longer needs blob write access.
        if ($temporaryBlobContributorCreated -and -not [string]::IsNullOrWhiteSpace($storageAccountId)) {
            try {
                Remove-AzRoleAssignment -ObjectId $config['runtime']['userId'] -RoleDefinitionName "Storage Blob Data Contributor" -Scope $storageAccountId -ErrorAction Stop
            }
            catch {
                Write-Warning "Failed to remove temporary deployer blob access on storage account '$($config['runtime']['storageAccountName'])'. $_"
            }
        }
    }
}