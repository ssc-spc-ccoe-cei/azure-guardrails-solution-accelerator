Function Remove-GSACoreResources {
    param (
        [Parameter(mandatory = $true, parameterSetName = 'string', ValueFromPipelineByPropertyName = $true)]
        [string]
        $configString,

        [Parameter(mandatory = $true, ParameterSetName = 'configFile')]
        [string]
        [Alias(
            'configFileName'
        )]
        $configFilePath,

        # resource group name
        [Parameter(Mandatory = $true, parameterSetname = 'manualParams')]
        [String]
        $resourceGroupName,

        # log analytics workspace name
        [Parameter(Mandatory = $true, parameterSetname = 'manualParams')]
        [String]
        $logAnalyticsWorkspaceName,

        # automation account name
        [Parameter(Mandatory = $true, parameterSetname = 'manualParams')]
        [String]
        $automationAccountName,

        #subcriptionID where Guardrails Solution Accelerator is deployed
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
            Write-Error -Message "The config parameter (or value from the pipeline) is not valid JSON. Please ensure that the -configString parameter is a valid JSON string or a path to a valid JSON file." -ErrorAction Stop
        }
    }
    ElseIf ($configFilePath) {
        $config = Confirm-GSAConfigurationParameters -configFilePath $configFilePath
    }
    ElseIf ($PSCmdlet.ParameterSetName -eq 'manualParams') {
        $config = @{
            resourceGroupName = $resourceGroupName
            logAnalyticsWorkspaceName = $logAnalyticsWorkspaceName
            automationAccountName = $automationAccountName
            subscriptionid = $subscriptionId
        }
    }

    Write-Warning "This function will remove the Guardrails Solution Accelerator core resources, including permenent removal of the Log Analytics Workspace data. This action cannot be undone. Use the -force parameter to confirm removal."
    If (!$force.IsPresent) {
        do { $prompt = Read-Host -Prompt 'Do you want to continue? (y/n)' }
        until ($prompt -match '[yn]')

        if ($prompt -ieq 'y') {
            Write-Verbose "Continuing with resource removal..."
        }
        elseif ($prompt -ieq 'n') {
            Write-Output "Exiting without removing Guardrails Solution Accelerator core resources..."
            break
        }
    }

    Confirm-GSASubscriptionSelection -config $config -confirmSingleSubscription:(!$force.IsPresent)

    # Azure exposes deleted workspaces through a separate REST endpoint.
    # We query that endpoint so we can tell when a "permanent" delete has
    # actually finished and the workspace is no longer recoverable.
    $deletedWorkspacePath = "/subscriptions/$($config['runtime']['subscriptionId'])/resourceGroups/$($config['runtime']['resourceGroup'])/providers/Microsoft.OperationalInsights/deletedWorkspaces?api-version=2023-09-01"

    # Small helper used by the wait loop below.
    # It fetches deleted workspaces for this resource group and filters to the
    # exact LAW name we are cleaning up.
    $getDeletedWorkspaceMatches = {
        param (
            [string]
            $workspaceName,

            [string]
            $deletedWorkspacePath,

            [string]
            $operationName
        )

        # The Azure control plane can be briefly inconsistent right after a delete.
        # Retry a couple of times before failing the cleanup.
        $attempt = 0
        do {
            try {
                $deletedWorkspaceResponse = Invoke-AzRestMethod -Method GET -Path $deletedWorkspacePath -ErrorAction Stop
                $deletedWorkspaceContent = if ($deletedWorkspaceResponse.Content) { $deletedWorkspaceResponse.Content } else { "{}" }
                $deletedWorkspacePayload = $deletedWorkspaceContent | ConvertFrom-Json -Depth 20

                return @($deletedWorkspacePayload.value) | Where-Object { $_.name -eq $workspaceName }
            }
            catch {
                $attempt++
                if ($attempt -ge 3) {
                    throw "Failed to query deleted Log Analytics workspaces while $operationName. Error: $($_.Exception.Message)"
                }

                Write-Verbose "Retrying deleted-workspaces lookup after transient error during $operationName..."
                Start-Sleep -Seconds 5
            }
        } while ($true)
    }

    $convertToHttpStatusCode = {
        param (
            $StatusCode
        )

        if ($null -eq $StatusCode) {
            return $null
        }

        try {
            return [int]$StatusCode
        }
        catch {
            try {
                return [int][System.Net.HttpStatusCode]::$StatusCode
            }
            catch {
                return $null
            }
        }
    }

    # Query ARM directly so deletion confirmation is based on HTTP status
    # codes instead of localized Azure PowerShell error text.
    $getResourceGroupArmState = {
        param (
            [string]
            $SubscriptionId,

            [string]
            $ResourceGroupName
        )

        $encodedResourceGroupName = [System.Uri]::EscapeDataString($ResourceGroupName)
        $resourceGroupUri = ('https://management.azure.com/subscriptions/{0}/resourceGroups/{1}?api-version=2021-04-01' -f $SubscriptionId, $encodedResourceGroupName) -as [uri]
        $statusCode = $null
        $message = $null

        try {
            $response = Invoke-AzRestMethod -Method GET -Uri $resourceGroupUri -ErrorAction Stop
            $statusCode = & $convertToHttpStatusCode -StatusCode $response.StatusCode
            $message = $response.Content
        }
        catch {
            $message = $_.Exception.Message
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $statusCode = & $convertToHttpStatusCode -StatusCode $_.Exception.Response.StatusCode
            }
            elseif ($_.Exception.StatusCode) {
                $statusCode = & $convertToHttpStatusCode -StatusCode $_.Exception.StatusCode
            }
        }

        if ($statusCode -eq 200 -or $statusCode -eq 204) {
            return [pscustomobject]@{ State = 'Exists'; StatusCode = $statusCode; Message = $message }
        }

        if ($statusCode -eq 404) {
            return [pscustomobject]@{ State = 'Deleted'; StatusCode = $statusCode; Message = $message }
        }

        if ($statusCode -eq 408 -or $statusCode -eq 409 -or $statusCode -eq 429 -or ($statusCode -ge 500 -and $statusCode -lt 600) -or $null -eq $statusCode) {
            return [pscustomobject]@{ State = 'Retry'; StatusCode = $statusCode; Message = $message }
        }

        throw "Resource group existence check failed for '$ResourceGroupName' with ARM status '$statusCode'. Error: $message"
    }

    Write-Verbose "Looking for Guardrails Solution Accelerator Automation Account..."
    try {
        $automationAccount = Get-AzAutomationAccount -ResourceGroupName $config['runtime']['resourceGroup'] -Name $config['runtime']['automationAccountName'] -ErrorAction Stop
    }
    catch {
        $automationAccountResource = Get-AzResource -ResourceGroupName $config['runtime']['resourceGroup'] -ResourceType 'Microsoft.Automation/automationAccounts' -Name $config['runtime']['automationAccountName'] -ErrorAction SilentlyContinue
        if ($automationAccountResource) {
            Write-Warning "Failed to read Guardrails Automation Account '$($config['runtime']['automationAccountName'])' before cleanup. Off-RG MSI role assignments may remain and can be cleaned up manually if they cause quota pressure. Error: $($_.Exception.Message)"
        }
        else {
            Write-Verbose "Guardrails Automation Account '$($config['runtime']['automationAccountName'])' was not found; no broad MSI role assignments will be removed."
        }
    }

    If ($automationAccount) {
        $guardrailsAutomationAccountMSI = $automationAccount.Identity.PrincipalId
    }

    $removeRoleAssignment = {
        param (
            [string]
            $ObjectId,

            [string]
            $RoleDefinitionName,

            [string]
            $Scope,

            [string]
            $Description
        )

        if ([string]::IsNullOrWhiteSpace($ObjectId) -or [string]::IsNullOrWhiteSpace($Scope)) {
            return
        }

        $retryDelaysInSeconds = @(5, 15, 30)
        for ($attempt = 1; $attempt -le ($retryDelaysInSeconds.Count + 1); $attempt++) {
            try {
                $existingAssignment = Get-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleDefinitionName -Scope $Scope -ErrorAction Stop
                if (-not $existingAssignment) {
                    Write-Verbose "Role assignment not found: $Description"
                    return
                }

                Write-Output "Removing role assignment: $Description"
                Remove-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleDefinitionName -Scope $Scope -ErrorAction Stop | Out-Null
                return
            }
            catch {
                $message = "Failed to remove role assignment '$Description'. This may leave stale RBAC behind. Error: $($_.Exception.Message)"
                $isLastAttempt = $attempt -gt $retryDelaysInSeconds.Count
                if (-not $isLastAttempt) {
                    $delayInSeconds = $retryDelaysInSeconds[$attempt - 1]
                    Write-Warning "$message Retrying in $delayInSeconds seconds."
                    Start-Sleep -Seconds $delayInSeconds
                    continue
                }

                Write-Warning $message
            }
        }
    }

    if ($guardrailsAutomationAccountMSI) {
        Write-Output "Removing Guardrails Automation Account MSI role assignments before deleting core resources..."

        # These assignments are outside the Guardrails resource group, so the RG
        # delete cascade will not remove them. Cleanup is best-effort because
        # stale role assignments should not block deleting the deployment.
        & $removeRoleAssignment `
            -ObjectId $guardrailsAutomationAccountMSI `
            -RoleDefinitionName Reader `
            -Scope $config['runtime']['tenantRootManagementGroupId'] `
            -Description "Reader on tenant root management group"

        & $removeRoleAssignment `
            -ObjectId $guardrailsAutomationAccountMSI `
            -RoleDefinitionName Reader `
            -Scope '/providers/Microsoft.aadiam' `
            -Description "Reader on Azure AD IAM scope"

        & $removeRoleAssignment `
            -ObjectId $guardrailsAutomationAccountMSI `
            -RoleDefinitionName Reader `
            -Scope '/providers/Microsoft.Marketplace' `
            -Description "Reader on Azure Marketplace scope"

        $storageAccount = Get-AzStorageAccount -ResourceGroupName $config['runtime']['resourceGroup'] -Name $config['runtime']['storageAccountName'] -ErrorAction SilentlyContinue
        if ($storageAccount) {
            & $removeRoleAssignment `
                -ObjectId $guardrailsAutomationAccountMSI `
                -RoleDefinitionName 'Reader and Data Access' `
                -Scope $storageAccount.Id `
                -Description "Reader and Data Access on Guardrails Storage Account '$($storageAccount.StorageAccountName)'"
        }
    }
    else {
        Write-Verbose "Guardrails Automation Account MSI was not found; no broad MSI role assignments will be removed."
    }

    $waitForArmResourceDeletion = {
        param (
            [string]
            $ResourceId,

            [string]
            $ResourceName
        )

        $resourceDeleteDeadline = (Get-Date).AddMinutes(15)
        $resourceClearChecks = 0
        do {
            try {
                $null = Get-AzResource -ResourceId $ResourceId -ErrorAction Stop
                $resourceClearChecks = 0
                Write-Verbose "Waiting for $ResourceName deletion to finish: still exists."
            }
            catch {
                if ($_.Exception.Message -match 'could not be found|ResourceNotFound|NotFound') {
                    $resourceClearChecks++
                    Write-Verbose "Waiting for $ResourceName deletion to finish: not found clearChecks=$resourceClearChecks/3."
                }
                else {
                    $resourceClearChecks = 0
                    Write-Verbose "Retrying $ResourceName deletion check after transient error: $($_.Exception.Message)"
                }
            }

            if ($resourceClearChecks -ge 3) {
                break
            }

            if ((Get-Date) -ge $resourceDeleteDeadline) {
                throw "Timed out waiting for $ResourceName to be deleted."
            }

            Start-Sleep -Seconds 15
        } while ($true)
    }

    $removeArmResource = {
        param (
            [string]
            $ResourceId,

            [string]
            $ResourceName,

            [switch]
            $RetryAzureMonitorTransientDelete,

            [switch]
            $WaitForDeletion
        )

        $resource = Get-AzResource -ResourceId $ResourceId -ErrorAction SilentlyContinue
        if (-not $resource) {
            Write-Verbose "$ResourceName not found."
            return
        }

        $retryDelaysInSeconds = if ($RetryAzureMonitorTransientDelete.IsPresent) { @(15, 30, 60, 120, 180) } else { @() }
        $removeAttempt = 0
        do {
            try {
                Write-Output "Removing $ResourceName before resource group deletion..."
                Remove-AzResource -ResourceId $ResourceId -Force -ErrorAction Stop | Out-Null
                break
            }
            catch {
                $isAzureMonitorTransientDelete = $_.Exception.Message -match 'ExistingAssociationsPreventDelete|Existing associations with Azure Monitor\s+Data Collection Rule|Data collection rule has been modified before operation completed'
                if (-not $isAzureMonitorTransientDelete -or $removeAttempt -ge $retryDelaysInSeconds.Count) {
                    throw
                }

                $retryDelayInSeconds = $retryDelaysInSeconds[$removeAttempt]
                $removeAttempt++
                Write-Warning "$ResourceName delete hit a transient Azure Monitor conflict on attempt $removeAttempt of $($retryDelaysInSeconds.Count + 1). Waiting $retryDelayInSeconds seconds before retrying."
                Start-Sleep -Seconds $retryDelayInSeconds
            }
        } while ($true)

        if ($WaitForDeletion.IsPresent) {
            & $waitForArmResourceDeletion -ResourceId $ResourceId -ResourceName $ResourceName
        }
    }

    Write-Verbose "Looking for Data Collection Rules (DCRs)..."
    $insightsResourceIdPrefix = "/subscriptions/$($config['runtime']['subscriptionId'])/resourceGroups/$($config['runtime']['resourceGroup'])/providers/Microsoft.Insights"

    # Remove DCRs before LAW and final resource-group deletion.
    & $removeArmResource -ResourceId "$insightsResourceIdPrefix/dataCollectionRules/guardrails-dcr" -ResourceName "Data Collection Rule 'guardrails-dcr'" -RetryAzureMonitorTransientDelete -WaitForDeletion:$wait.IsPresent
    & $removeArmResource -ResourceId "$insightsResourceIdPrefix/dataCollectionRules/guardrails-dcr-2" -ResourceName "Data Collection Rule 'guardrails-dcr-2'" -RetryAzureMonitorTransientDelete -WaitForDeletion:$wait.IsPresent

    Write-Output "Looking for Guardrails Log Analytics Workspace '$($config['runtime']['logAnalyticsWorkspaceName'])'..."
    $logAnalyticsWorkspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $config['runtime']['resourceGroup'] -Name $config['runtime']['logAnalyticsWorkspaceName'] -ErrorAction SilentlyContinue
    $existingDeletedWorkspaceMatches = @(& $getDeletedWorkspaceMatches -workspaceName $config['runtime']['logAnalyticsWorkspaceName'] -deletedWorkspacePath $deletedWorkspacePath -operationName 'checking for an already deleted LAW')
    if ($logAnalyticsWorkspace) {
        Write-Output "Force-deleting Guardrails Log Analytics workspace '$($config['runtime']['logAnalyticsWorkspaceName'])'."
        # Even with -ForceDelete, Azure can briefly surface the workspace in its
        # deleted view after the delete call returns. We still wait on both
        # active and deleted states so we do not redeploy while Azure is still
        # finishing the workspace delete.
        $logAnalyticsWorkspace | Remove-AzOperationalInsightsWorkspace -ForceDelete -Force
    }
    else {
        Write-Output "Guardrails Log Analytics workspace '$($config['runtime']['logAnalyticsWorkspaceName'])' not found in active resources."
    }

    # The delete command can return before Azure fully removes the workspace.
    # Wait until the active workspace is gone and the workspace no longer
    # appears in the deleted-workspaces view before deleting the resource group.
    # This avoids a race where the next deploy starts while the LAW delete is
    # still settling on Azure's side.
    $pollIntervalSeconds = 10
    $deadline = (Get-Date).AddMinutes(30)
    $clearChecks = 0

    if ($logAnalyticsWorkspace -or $existingDeletedWorkspaceMatches) {
        do {
            # Check both places Azure can still show the workspace:
            # 1. the normal active workspace view
            # 2. the deleted-workspaces view used for recoverable workspaces
            $activeWorkspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $config['runtime']['resourceGroup'] -Name $config['runtime']['logAnalyticsWorkspaceName'] -ErrorAction SilentlyContinue
            $deletedWorkspaceMatches = @(& $getDeletedWorkspaceMatches -workspaceName $config['runtime']['logAnalyticsWorkspaceName'] -deletedWorkspacePath $deletedWorkspacePath -operationName 'waiting for permanent LAW delete to settle')

            # Require multiple clean reads in a row so we do not trust a single
            # transient "gone" result from Azure.
            if (-not $activeWorkspace -and -not $deletedWorkspaceMatches) {
                $clearChecks++
            }
            else {
                $clearChecks = 0
            }

            Write-Output ("Waiting for permanent LAW delete to settle: active={0} deleted={1} clearChecks={2}/3" -f [bool]$activeWorkspace, [bool]$deletedWorkspaceMatches, $clearChecks)

            if ($clearChecks -ge 3) {
                Write-Output "Permanent LAW delete is settled for '$($config['runtime']['logAnalyticsWorkspaceName'])'."
                break
            }

            # Fail rather than silently continuing if Azure never reaches a clean state.
            if ((Get-Date) -ge $deadline) {
                throw "Timed out waiting for Log Analytics workspace '$($config['runtime']['logAnalyticsWorkspaceName'])' to disappear from both active and deleted states."
            }

            Start-Sleep -Seconds $pollIntervalSeconds
        } while ($true)
    }

    $initialResourceGroupState = & $getResourceGroupArmState -SubscriptionId $config['runtime']['subscriptionId'] -ResourceGroupName $config['runtime']['resourceGroup']
    If ($initialResourceGroupState.State -eq 'Exists') {
        Write-Output "Starting Guardrails resource group delete for '$($config['runtime']['resourceGroup'])'."
        $job = Remove-AzResourceGroup -Name $config['runtime']['resourceGroup'] -Force -AsJob 

        If ($wait.IsPresent) {
            Write-Output "Waiting for Guardrails Solution Accelerator Resource Group delete job to finish..."
            $rgDeleteJobDeadline = (Get-Date).AddMinutes(30)
            $rgDeletedBeforeJobCompleted = $false
            $rgClearChecksDuringJobWait = 0
            do {
                $job = Get-Job -Id $job.Id
                if ($job.State -in 'Completed', 'Failed', 'Stopped', 'Suspended', 'Disconnected') {
                    break
                }

                $resourceGroupState = & $getResourceGroupArmState -SubscriptionId $config['runtime']['subscriptionId'] -ResourceGroupName $config['runtime']['resourceGroup']
                if ($resourceGroupState.State -eq 'Deleted') {
                    $rgClearChecksDuringJobWait++
                    Write-Output "Resource group '$($config['runtime']['resourceGroup'])' is no longer returned by ARM while delete job is still '$($job.State)' (clearChecks=$rgClearChecksDuringJobWait/3)."
                    if ($rgClearChecksDuringJobWait -ge 3) {
                        $rgDeletedBeforeJobCompleted = $true
                        break
                    }
                    Start-Sleep -Seconds 30
                    continue
                }
                elseif ($resourceGroupState.State -eq 'Exists') {
                    $rgClearChecksDuringJobWait = 0
                    $remainingResourceCount = @(Get-AzResource -ResourceGroupName $config['runtime']['resourceGroup'] -ErrorAction SilentlyContinue).Count
                    Write-Output "ARM still returns resource group '$($config['runtime']['resourceGroup'])' while delete job is '$($job.State)'. Remaining visible child resources: $remainingResourceCount."
                }
                else {
                    $rgClearChecksDuringJobWait = 0
                    Write-Output "Retrying resource group deletion check after transient ARM status '$($resourceGroupState.StatusCode)': $($resourceGroupState.Message)"
                }

                if ($rgClearChecksDuringJobWait -ge 3) {
                    $rgDeletedBeforeJobCompleted = $true
                    break
                }

                if ((Get-Date) -ge $rgDeleteJobDeadline) {
                    throw "Timed out waiting for resource group delete job for '$($config['runtime']['resourceGroup'])' to finish."
                }

                Write-Output "Waiting for resource group delete job for '$($config['runtime']['resourceGroup'])' to finish. Current job state: $($job.State)."
                Start-Sleep -Seconds 30
            } while ($true)

            if ($rgDeletedBeforeJobCompleted) {
                # ARM removed the resource group before the local job state
                # updated, so the existence check is the authoritative signal.
                Write-Output "Resource group '$($config['runtime']['resourceGroup'])' deletion is confirmed even though the local delete job has not completed. Continuing cleanup."
                Stop-Job -Job $job -ErrorAction SilentlyContinue
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
            else {
                if ($job.State -eq 'Failed') {
                    $jobError = $job.ChildJobs | ForEach-Object { $_.JobStateInfo.Reason } | Where-Object { $_ } | Out-String
                    throw "Resource group delete job failed for '$($config['runtime']['resourceGroup'])'. Error: $jobError"
                }

                if ($job.State -ne 'Completed') {
                    throw "Resource group delete job for '$($config['runtime']['resourceGroup'])' ended with state '$($job.State)'."
                }

                # The Azure PowerShell job can finish before ARM has fully removed
                # every child resource. Confirm the RG is gone before returning so
                # callers do not start a fresh deploy while DCR/AA cleanup is
                # still settling.
                $rgDeleteDeadline = (Get-Date).AddMinutes(30)
                $rgClearChecks = 0
                do {
                    $resourceGroupState = & $getResourceGroupArmState -SubscriptionId $config['runtime']['subscriptionId'] -ResourceGroupName $config['runtime']['resourceGroup']
                    if ($resourceGroupState.State -eq 'Deleted') {
                        $rgClearChecks++
                        Write-Output "Waiting for resource group '$($config['runtime']['resourceGroup'])' deletion to finish: ARM returned 404 clearChecks=$rgClearChecks/3."
                        if ($rgClearChecks -ge 3) {
                            break
                        }
                        Start-Sleep -Seconds 30
                        continue
                    }
                    elseif ($resourceGroupState.State -eq 'Exists') {
                        $rgClearChecks = 0
                        $remainingResourceCount = @(Get-AzResource -ResourceGroupName $config['runtime']['resourceGroup'] -ErrorAction SilentlyContinue).Count
                        Write-Output "Waiting for resource group '$($config['runtime']['resourceGroup'])' deletion to finish: ARM still returns RG. Remaining visible child resources: $remainingResourceCount."
                    }
                    else {
                        $rgClearChecks = 0
                        Write-Output "Retrying resource group deletion check after transient ARM status '$($resourceGroupState.StatusCode)': $($resourceGroupState.Message)"
                    }

                    if ($rgClearChecks -ge 3) {
                        break
                    }

                    if ((Get-Date) -ge $rgDeleteDeadline) {
                        throw "Timed out waiting for resource group '$($config['runtime']['resourceGroup'])' to be deleted."
                    }

                    Start-Sleep -Seconds 30
                } while ($true)
            }
        }
    }
    elseif ($initialResourceGroupState.State -eq 'Deleted') {
        Write-Output "Guardrails Solution Accelerator Resource Group '$($config['runtime']['resourceGroup'])' not found."
    }
    else {
        throw "Could not confirm whether Guardrails Solution Accelerator Resource Group '$($config['runtime']['resourceGroup'])' exists before deletion. ARM status '$($initialResourceGroupState.StatusCode)': $($initialResourceGroupState.Message)"
    }

    Write-Host "Completed cleanup of Guardrails Solution Accelerator core resources. If -wait parameter was not specified, the core Resource Group deletion may still be in progress." -ForegroundColor Green
}