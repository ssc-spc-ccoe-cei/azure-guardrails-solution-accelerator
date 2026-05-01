Function Add-GSAAutomationRunbooks {

    param (
        # config
        [Parameter(mandatory = $true)]
        [psobject]
        $config
    )
    $ErrorActionPreference = 'Stop'

    Write-Verbose "Starting import Azure Automation Runbook definitions..."
    $mainRunbookName = "main"
    #$RunbookPath = '.\'
    $mainRunbookDescription = "Guardrails Main Runbook"
    $backendRunbookName = "backend"
    $backendRunbookDescription = "Guardrails Backend Runbook"

    Write-Verbose "Exporting modules.json to Storage Account '$($config['runtime']['StorageAccountName'])' for runbook consumption"

    import-module "$PSScriptRoot/../../../../src/Guardrails-Common/GR-Common.psm1"
    $modulesJsonPath = "$PSScriptRoot/../../../../setup/modules.json"
    # Verify the modules.json file exists
    if (-not (Test-Path $modulesJsonPath)) {
        throw "Critical: modules.json file not found at path: $modulesJsonPath"
    }
    
    Write-Verbose "Uploading modules.json to blob storage container 'configuration'..."
    try {
        # Wait up to 10 minutes for the temporary Blob Contributor role to become usable by the deployer.
        $maxBlobAttempts = 30
        $blobRetryDelaySeconds = 20

        for ($attempt = 1; $attempt -le $maxBlobAttempts; $attempt++) {
            try {
                # Upload modules.json with the connected Entra identity instead of the storage account key.
                copy-toBlobUsingConnectedAccount -FilePath $modulesJsonPath -storageaccountName $config['runtime']['storageAccountName'] -resourceGroup $config['runtime']['resourceGroup'] -force -containerName "configuration" -ErrorAction Stop

                # Read the blob back with the same Entra-authenticated context so we only proceed after RBAC access is live.
                Write-Verbose "Verifying modules.json was successfully uploaded to blob storage..."
                $storageContext = New-ConnectedStorageContext -storageaccountName $config['runtime']['storageAccountName']
                $blob = Get-AzStorageBlob -Container "configuration" -Blob "modules.json" -Context $storageContext -ErrorAction SilentlyContinue

                if ($null -eq $blob) {
                    throw "Critical: modules.json upload verification failed - blob not found in storage account after upload"
                }

                Write-Verbose "Successfully uploaded and verified modules.json to blob storage. Blob LastModified: $($blob.LastModified)"
                Write-Host "Successfully uploaded modules.json to blob storage container 'configuration'" -ForegroundColor Green
                break
            }
            catch {
                # Keep retrying while RBAC settles, but stop immediately once we run out of attempts.
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

    Write-Verbose "Importing runbook definitions..."
    #region Import main runbook
    Write-Verbose "Importing 'main' Runbook." #main runbook, runs the modules.
    try {
        $ErrorActionPreference = 'Stop'
        Write-Verbose "`tImporting 'main' Runbook to Azure Automation Account '$($config['runtime']['AutomationAccountName'])'"
        Import-AzAutomationRunbook -Name $mainRunbookName -Path "$PSScriptRoot/../../../../setup/main.ps1" -Description $mainRunbookDescription -Type PowerShell72 -Published `
            -ResourceGroupName $config['runtime']['resourceGroup'] -AutomationAccountName $config['runtime']['autoMationAccountName'] -Tags @{version = $config['runtime']['tagsTable'].ReleaseVersion } | Out-Null
    }
    catch [System.IO.IOException] {
    Write-Log -Message "File access error: $_" -Level Error
    Write-Output "Error Code 100: Unable to access required file or resource."
    break
    }
    catch [Microsoft.Rest.Azure.CloudException] {
        Write-Log -Message "Azure cloud service error: $_" -Level Error
        Write-Output "Error Code 200: Azure API failure."
        break
    }
    catch {
        Write-Log -Message "Unexpected error occurred: $_" -Level Error
        Write-Output "Error Code 999: An unknown error occurred."
        break
    }

    $startTime = (Get-Date).Date.AddHours(7).ToUniversalTime()
    if ($startTime -lt (Get-Date).AddMinutes(5)) {
        $startTime = $startTime.AddDays(1)  # Move to the next day if the start time is too close
    }

    Write-Verbose "Creating schedule for 'main' Runbook."
    try {
        $ErrorActionPreference = 'Stop'
        Write-Verbose "`tCreating schedule for 'main' Runbook."
        New-AzAutomationSchedule -ResourceGroupName $config['runtime']['resourceGroup'] -AutomationAccountName $config['runtime']['autoMationAccountName'] -Name "GR-Daily" -StartTime $startTime -HourInterval 24 | Out-Null
    }
    catch [System.IO.IOException] {
    Write-Log -Message "File access error: $_" -Level Error
    Write-Output "Error Code 100: Unable to access required file or resource."
    break
    }
    catch [Microsoft.Rest.Azure.CloudException] {
        Write-Log -Message "Azure cloud service error: $_" -Level Error
        Write-Output "Error Code 200: Azure API failure."
        break
    }
    catch {
        Write-Log -Message "Unexpected error occurred: $_" -Level Error
        Write-Output "Error Code 999: An unknown error occurred."
        break
    }

    Write-Verbose "Registering 'main' Runbook to schedule."
    try{
        $ErrorActionPreference = 'Stop'
        Write-Verbose "`tRegistering 'main' Runbook to schedule."
        Register-AzAutomationScheduledRunbook -Name $mainRunbookName -ResourceGroupName $config['runtime']['resourceGroup'] -AutomationAccountName $config['runtime']['autoMationAccountName'] -ScheduleName "GR-Daily" | Out-Null
    }
    catch [System.IO.IOException] {
    Write-Log -Message "File access error: $_" -Level Error
    Write-Output "Error Code 100: Unable to access required file or resource."
    break
    }
    catch [Microsoft.Rest.Azure.CloudException] {
        Write-Log -Message "Azure cloud service error: $_" -Level Error
        Write-Output "Error Code 200: Azure API failure."
        break
    }
    catch {
        Write-Log -Message "Unexpected error occurred: $_" -Level Error
        Write-Output "Error Code 999: An unknown error occurred."
        break
    }
    #endregion
    #region Import main runbook
    Write-Verbose "Importing 'Backend' Runbook." #backend runbooks. gets information about tenant, version and itsgcontrols.
    try {
        $ErrorActionPreference = 'Stop'
        Write-Verbose "`tImporting 'backend' Runbook to Azure Automation Account '$($config['runtime']['AutomationAccountName'])'"
        Import-AzAutomationRunbook -Name $backendRunbookName -Path "$PSScriptRoot/../../../../setup/backend.ps1" -Description $backendRunbookDescription -Type PowerShell72 -Published `
            -ResourceGroupName $config['runtime']['resourceGroup'] -AutomationAccountName $config['runtime']['autoMationAccountName'] -Tags @{version = $config['runtime']['tagsTable'].ReleaseVersion } | Out-Null
    }
    catch [System.IO.IOException] {
    Write-Log -Message "File access error: $_" -Level Error
    Write-Output "Error Code 101: Unable to access required file or resource."
    break
    }
    catch [Microsoft.Rest.Azure.CloudException] {
        Write-Log -Message "Azure cloud service error: $_" -Level Error
        Write-Output "Error Code 200: Azure API failure."
        break
    }
    catch {
        Write-Log -Message "Unexpected error occurred: $_" -Level Error
        Write-Output "Error Code 999: An unknown error occurred."
        break
    }

    Write-Verbose "Creating schedule for 'Backend' Runbook."
    try {
        $ErrorActionPreference = 'Stop'
        Write-Verbose "`tCreating schedule for 'backend' Runbook."
        New-AzAutomationSchedule -ResourceGroupName $config['runtime']['resourceGroup'] -AutomationAccountName $config['runtime']['autoMationAccountName'] -Name "GR-Daily" -StartTime $startTime -HourInterval 24 | Out-Null
    }
    catch [System.IO.IOException] {
    Write-Log -Message "File access error: $_" -Level Error
    Write-Output "Error Code 100: Unable to access required file or resource."
    break
    }
    catch [Microsoft.Rest.Azure.CloudException] {
        Write-Log -Message "Azure cloud service error: $_" -Level Error
        Write-Output "Error Code 200: Azure API failure."
        break
    }
    catch {
        Write-Log -Message "Unexpected error occurred: $_" -Level Error
        Write-Output "Error Code 999: An unknown error occurred."
        break
    }

    Write-Verbose "Registering 'Backend' Runbook to schedule."
    try {
        $ErrorActionPreference = 'Stop'
        Write-Verbose "`tRegistering 'backend' Runbook to schedule."
        Register-AzAutomationScheduledRunbook -Name $backendRunbookName -ResourceGroupName $config['runtime']['resourceGroup'] -AutomationAccountName $config['runtime']['autoMationAccountName'] -ScheduleName "GR-Daily" | Out-Null
    }
    catch [System.IO.IOException] {
    Write-Log -Message "File access error: $_" -Level Error
    Write-Output "Error Code 100: Unable to access required file or resource."
    break
    }
    catch [Microsoft.Rest.Azure.CloudException] {
        Write-Log -Message "Azure cloud service error: $_" -Level Error
        Write-Output "Error Code 200: Azure API failure."
        break
    }
    catch {
        Write-Log -Message "Unexpected error occurred: $_" -Level Error
        Write-Output "Error Code 999: An unknown error occurred."
        break
    }

    Write-Verbose "Completed import Azure Automation Runbook definitions..."
}