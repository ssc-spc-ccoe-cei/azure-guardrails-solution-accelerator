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

    Write-Verbose "Looking for Guardrails Log Analytics Workspace..."
    $logAnalyticsWorkspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $config['runtime']['resourceGroup'] -Name $config['runtime']['logAnalyticsWorkspaceName'] -ErrorAction SilentlyContinue
    $existingDeletedWorkspaceMatches = @(& $getDeletedWorkspaceMatches -workspaceName $config['runtime']['logAnalyticsWorkspaceName'] -deletedWorkspacePath $deletedWorkspacePath -operationName 'checking for an already deleted LAW')
    if ($logAnalyticsWorkspace) {
        Write-Verbose "Removing Guardrails Solution Accelerator Log Analytics Workspace..."
        # Even with -ForceDelete, Azure can briefly surface the workspace in its
        # deleted view after the delete call returns. We still wait on both
        # active and deleted states so we do not start deleting the resource group
        # or redeploying while Azure is still finishing the workspace delete.
        $logAnalyticsWorkspace | Remove-AzOperationalInsightsWorkspace -ForceDelete -Force
    }
    else {
        Write-Verbose "Guardrails Solution Accelerator Log Analytics workspace not found."
    }

    # The delete command can return before Azure fully removes the workspace.
    # Wait until the active workspace is gone and the workspace no longer
    # appears in the deleted-workspaces view before deleting the resource group.
    # This avoids a race where the resource group delete or the next deploy
    # starts while the LAW delete is still settling on Azure's side.
    $pollIntervalSeconds = 10
    $deadline = (Get-Date).AddMinutes(10)
    $clearChecks = 0

    if ($logAnalyticsWorkspace -or $existingDeletedWorkspaceMatches) {
        do {
            # Check both places Azure can still show the workspace:
            # 1. the normal active workspace view
            # 2. the deleted-workspaces view used for recoverable workspaces
            $activeWorkspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $config['runtime']['resourceGroup'] -Name $config['runtime']['logAnalyticsWorkspaceName'] -ErrorAction SilentlyContinue
            $deletedWorkspaceMatches = @(& $getDeletedWorkspaceMatches -workspaceName $config['runtime']['logAnalyticsWorkspaceName'] -deletedWorkspacePath $deletedWorkspacePath -operationName 'waiting for permanent LAW delete to settle')
            $deletedWorkspace = $deletedWorkspaceMatches | Select-Object -First 1

            # Require multiple clean reads in a row so we do not trust a single
            # transient "gone" result from Azure.
            if (-not $activeWorkspace -and -not $deletedWorkspace) {
                $clearChecks++
            }
            else {
                $clearChecks = 0
            }

            Write-Verbose ("Waiting for permanent LAW delete to settle: active={0} deleted={1} clearChecks={2}/3" -f [bool]$activeWorkspace, [bool]$deletedWorkspace, $clearChecks)

            if ($clearChecks -ge 3) {
                break
            }

            # Fail rather than silently continuing if Azure never reaches a clean state.
            if ((Get-Date) -ge $deadline) {
                throw "Timed out waiting for Log Analytics workspace '$($config['runtime']['logAnalyticsWorkspaceName'])' to disappear from both active and deleted states."
            }

            Start-Sleep -Seconds $pollIntervalSeconds
        } while ($true)
    }

    Write-Verbose "Looking for Guardrails Solution Accelerator Automation Account..."
    $automationAccount = Get-AzAutomationAccount -ResourceGroupName $config['runtime']['resourceGroup'] -Name $config['runtime']['automationAccountName'] -ErrorAction SilentlyContinue
    If ($automationAccount) {
        $guardrailsAutomationAccountMSI = $automationAccount.Identity.PrincipalId
    }

    Write-Verbose "Looking for Data Collection Endpoint (DCE) and Data Collection Rule (DCR)..."
    $dce = Get-AzDataCollectionEndpoint -ResourceGroupName $config['runtime']['resourceGroup'] -Name "guardrails-dce" -ErrorAction SilentlyContinue
    if ($dce) {
        Write-Verbose "Found Data Collection Endpoint 'guardrails-dce' (will be removed with resource group)."
    }
    $dcr = Get-AzDataCollectionRule -ResourceGroupName $config['runtime']['resourceGroup'] -Name "guardrails-dcr" -ErrorAction SilentlyContinue
    if ($dcr) {
        Write-Verbose "Found Data Collection Rule 'guardrails-dcr' (will be removed with resource group)."
    }

    If (Get-AzResourceGroup -Name $config['runtime']['resourceGroup'] -ErrorAction SilentlyContinue) {
        Write-Verbose "Removing Guardrails Solution Accelerator Resource Group (including DCE, DCR, and all other resources)..."
        $job = Remove-AzResourceGroup -Name $config['runtime']['resourceGroup'] -Force -AsJob 

        If ($wait.IsPresent) {
            Write-Verbose "Waiting for Guardrails Solution Accelerator Resource Group to be removed..."
            $job | Wait-Job | Out-Null
        }
    }
    else {
        Write-Verbose "Guardrails Solution Accelerator Resource Group not found."
    }

    Write-Host "Completed cleanup of Guardrails Solution Accelerator core resources. If -wait parameter was not specified, the core Resource Group deletion may still be in progress." -ForegroundColor Green
    Write-Warning "Role assignments for the Guardrails Solution Accelerator service principal will not be removed. To remove these role assignments, remove them from the root management group manually."
}