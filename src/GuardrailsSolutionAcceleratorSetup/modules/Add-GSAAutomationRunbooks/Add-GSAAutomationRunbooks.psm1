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
    $scheduleName = "GR-Daily"

    function Invoke-GSARunbookSetupStep {
        param (
            [Parameter(Mandatory = $true)]
            [string]
            $Description,

            [Parameter(Mandatory = $true)]
            [scriptblock]
            $ScriptBlock
        )

        try {
            & $ScriptBlock
        }
        catch {
            $errorDetails = $_ | Out-String
            if ([string]::IsNullOrWhiteSpace($errorDetails)) {
                $errorDetails = $_.Exception.Message
            }
            throw "$Description failed. $errorDetails"
        }
    }

    function Set-GSAAutomationSchedule {
        param (
            [Parameter(Mandatory = $true)]
            [psobject]
            $Config,

            [Parameter(Mandatory = $true)]
            [string]
            $Name,

            [Parameter(Mandatory = $true)]
            [datetime]
            $StartTime
        )

        $existingSchedule = Get-AzAutomationSchedule -ResourceGroupName $Config['runtime']['resourceGroup'] -AutomationAccountName $Config['runtime']['autoMationAccountName'] -Name $Name -ErrorAction SilentlyContinue
        if ($existingSchedule) {
            Write-Verbose "`tAutomation schedule '$Name' already exists. Reusing it."
            return
        }

        New-AzAutomationSchedule -ResourceGroupName $Config['runtime']['resourceGroup'] -AutomationAccountName $Config['runtime']['autoMationAccountName'] -Name $Name -StartTime $StartTime -HourInterval 24 | Out-Null
    }

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
    Invoke-GSARunbookSetupStep -Description "Importing 'main' Runbook to Azure Automation Account '$($config['runtime']['AutomationAccountName'])'" -ScriptBlock {
        Write-Verbose "`tImporting 'main' Runbook to Azure Automation Account '$($config['runtime']['AutomationAccountName'])'"
        Import-AzAutomationRunbook -Name $mainRunbookName -Path "$PSScriptRoot/../../../../setup/main.ps1" -Description $mainRunbookDescription -Type PowerShell72 -Published `
            -ResourceGroupName $config['runtime']['resourceGroup'] -AutomationAccountName $config['runtime']['autoMationAccountName'] -Tags @{version = $config['runtime']['tagsTable'].ReleaseVersion } | Out-Null
    }

    $startTime = (Get-Date).Date.AddHours(7).ToUniversalTime()
    if ($startTime -lt (Get-Date).AddMinutes(5)) {
        $startTime = $startTime.AddDays(1)  # Move to the next day if the start time is too close
    }

    Write-Verbose "Ensuring '$scheduleName' schedule exists."
    Invoke-GSARunbookSetupStep -Description "Ensuring Automation schedule '$scheduleName'" -ScriptBlock {
        Set-GSAAutomationSchedule -Config $config -Name $scheduleName -StartTime $startTime
    }

    Write-Verbose "Registering 'main' Runbook to schedule."
    Invoke-GSARunbookSetupStep -Description "Registering 'main' Runbook to schedule '$scheduleName'" -ScriptBlock {
        Write-Verbose "`tRegistering 'main' Runbook to schedule '$scheduleName'."
        Register-AzAutomationScheduledRunbook -Name $mainRunbookName -ResourceGroupName $config['runtime']['resourceGroup'] -AutomationAccountName $config['runtime']['autoMationAccountName'] -ScheduleName $scheduleName | Out-Null
    }
    #endregion
    #region Import backend runbook
    Write-Verbose "Importing 'Backend' Runbook." #backend runbooks. gets information about tenant, version and itsgcontrols.
    Invoke-GSARunbookSetupStep -Description "Importing 'backend' Runbook to Azure Automation Account '$($config['runtime']['AutomationAccountName'])'" -ScriptBlock {
        Write-Verbose "`tImporting 'backend' Runbook to Azure Automation Account '$($config['runtime']['AutomationAccountName'])'"
        Import-AzAutomationRunbook -Name $backendRunbookName -Path "$PSScriptRoot/../../../../setup/backend.ps1" -Description $backendRunbookDescription -Type PowerShell72 -Published `
            -ResourceGroupName $config['runtime']['resourceGroup'] -AutomationAccountName $config['runtime']['autoMationAccountName'] -Tags @{version = $config['runtime']['tagsTable'].ReleaseVersion } | Out-Null
    }

    Write-Verbose "Registering 'Backend' Runbook to schedule."
    Invoke-GSARunbookSetupStep -Description "Registering 'backend' Runbook to schedule '$scheduleName'" -ScriptBlock {
        Write-Verbose "`tRegistering 'backend' Runbook to schedule '$scheduleName'."
        Register-AzAutomationScheduledRunbook -Name $backendRunbookName -ResourceGroupName $config['runtime']['resourceGroup'] -AutomationAccountName $config['runtime']['autoMationAccountName'] -ScheduleName $scheduleName | Out-Null
    }
    #endregion

    Write-Verbose "Completed import Azure Automation Runbook definitions..."
}