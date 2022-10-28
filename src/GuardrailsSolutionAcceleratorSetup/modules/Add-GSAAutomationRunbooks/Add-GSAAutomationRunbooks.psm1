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
    copy-toBlob -FilePath $modulesJsonPath -storageaccountName $config['runtime']['storageAccountName'] -resourceGroup $config['runtime']['resourceGroup'] -force -containerName "configuration"

    Write-Verbose "Importing runbook definitions..."
    #region Import main runbook
    Write-Verbose "Importing 'main' Runbook." #main runbook, runs the modules.
    try {
        $ErrorActionPreference = 'Stop'

        Write-Verbose "`tImporting 'main' Runbook to Azure Automation Account '$($config['runtime']['AutomationAccountName'])'"
        Import-AzAutomationRunbook -Name $mainRunbookName -Path "$PSScriptRoot/../../../../setup/main.ps1" -Description $mainRunbookDescription -Type PowerShell -Published `
            -ResourceGroupName $config['runtime']['resourceGroup'] -AutomationAccountName $config['runtime']['autoMationAccountName'] -Tags @{version = $config['runtime']['tagsTable'].ReleaseVersion } | Out-Null

        Write-Verbose "`tCreating schedule for 'main' Runbook."
        New-AzAutomationSchedule -ResourceGroupName $config['runtime']['resourceGroup'] -AutomationAccountName $config['runtime']['autoMationAccountName'] -Name "GR-Every6hours" -StartTime (get-date).AddHours(1) -HourInterval 6 | Out-Null

        Write-Verbose "`tRegistering 'main' Runbook to schedule."
        Register-AzAutomationScheduledRunbook -Name $mainRunbookName -ResourceGroupName $config['runtime']['resourceGroup'] -AutomationAccountName $config['runtime']['autoMationAccountName'] -ScheduleName "GR-Every6hours" | Out-Null
    }
    catch {
        Write-Error "Error importing 'main' Runbook. $_"
        break
    }
    #endregion
    #region Import main runbook
    Write-Verbose "Importing 'Backend' Runbook." #backend runbooks. gets information about tenant, version and itsgcontrols.
    try {
        $ErrorActionPreference = 'Stop'

        Write-Verbose "`tImporting 'backend' Runbook to Azure Automation Account '$($config['runtime']['AutomationAccountName'])'"
        Import-AzAutomationRunbook -Name $backendRunbookName -Path "$PSScriptRoot/../../../../setup/backend.ps1" -Description $backendRunbookDescription -Type PowerShell -Published `
            -ResourceGroupName $config['runtime']['resourceGroup'] -AutomationAccountName $config['runtime']['autoMationAccountName'] -Tags @{version = $config['runtime']['tagsTable'].ReleaseVersion } | Out-Null
        
        Write-Verbose "`tCreating schedule for 'backend' Runbook."
        New-AzAutomationSchedule -ResourceGroupName $config['runtime']['resourceGroup'] -AutomationAccountName $config['runtime']['autoMationAccountName'] -Name "GR-Daily" -StartTime (get-date).AddHours(1) -HourInterval 24 | Out-Null
        
        Write-Verbose "`tRegistering 'backend' Runbook to schedule."
        Register-AzAutomationScheduledRunbook -Name $backendRunbookName -ResourceGroupName $config['runtime']['resourceGroup'] -AutomationAccountName $config['runtime']['autoMationAccountName'] -ScheduleName "GR-Daily" | Out-Null
    }
    catch {
        Write-Error "Error importing 'backend' Runbook. $_"
        break
    }

    Write-Verbose "Completed import Azure Automation Runbook definitions..."
}