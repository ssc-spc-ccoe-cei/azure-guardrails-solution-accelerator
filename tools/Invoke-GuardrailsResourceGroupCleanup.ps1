[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]
    $SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]
    $ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]
    $ConfirmResourceGroupName,

    [Parameter(Mandatory = $false)]
    [bool]
    $ForceDeleteLogAnalyticsWorkspace = $true,

    [Parameter(Mandatory = $false)]
    [bool]
    $DryRun = $false,

    [Parameter(Mandatory = $false)]
    [int]
    $TimeoutMinutes = 30,

    [Parameter(Mandatory = $false)]
    [int]
    $PollIntervalSeconds = 30,

    [Parameter(Mandatory = $false)]
    [int]
    $DcrDceDeleteTimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'

function Start-GuardrailsArmResourceDelete {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $ResourceId,

        [Parameter(Mandatory = $true)]
        [string]
        $ResourceType,

        [Parameter(Mandatory = $true)]
        [string]
        $ResourceName
    )

    Write-Output "Starting delete for $ResourceType '$ResourceName'."
    try {
        $job = Remove-AzResource -ResourceId $ResourceId -Force -AsJob -ErrorAction Stop
    }
    catch {
        Write-Warning "Delete could not be started for $ResourceType '$ResourceName'. Continuing to resource group delete. Error: $($_.Exception.Message)"
        return
    }

    if (-not (Wait-Job -Job $job -Timeout $DcrDceDeleteTimeoutSeconds)) {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        Write-Warning "Delete for $ResourceType '$ResourceName' did not finish within $DcrDceDeleteTimeoutSeconds seconds and may still be pending in Azure. Continuing to resource group delete."
        return
    }

    try {
        Receive-Job -Job $job -ErrorAction Stop | Out-Null
        Write-Output "Delete request completed for $ResourceType '$ResourceName'."
    }
    catch {
        Write-Warning "Delete failed for $ResourceType '$ResourceName'. Continuing to resource group delete. Error: $($_.Exception.Message)"
    }
    finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}

if ($ResourceGroupName -ne $ConfirmResourceGroupName) {
    throw "Confirmation mismatch. ResourceGroupName '$ResourceGroupName' does not match ConfirmResourceGroupName '$ConfirmResourceGroupName'."
}

Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

$resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $resourceGroup) {
    Write-Output "Resource group '$ResourceGroupName' was not found in subscription '$SubscriptionId'. Nothing to delete."
    return
}

Write-Output "Preparing to delete resource group '$ResourceGroupName' in subscription '$SubscriptionId'."
$initialResources = @(Get-AzResource -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Sort-Object ResourceType, Name)
if ($initialResources.Count -eq 0) {
    Write-Output "Resource group '$ResourceGroupName' has no active child resources."
}
else {
    Write-Output "Resources found before cleanup:"
    $initialResources | Select-Object ResourceType, Name | Format-Table -AutoSize | Out-String | Write-Output
}

$guardrailsMarkerResources = @($initialResources | Where-Object {
    $_.ResourceType -in @(
        'Microsoft.Insights/dataCollectionRules',
        'Microsoft.Insights/dataCollectionEndpoints',
        'Microsoft.OperationalInsights/workspaces',
        'Microsoft.Automation/automationAccounts'
    )
})
if ($guardrailsMarkerResources.Count -eq 0 -and $initialResources.Count -gt 0) {
    Write-Warning "Resource group '$ResourceGroupName' does not contain common Guardrails resource types such as DCR, DCE, Log Analytics workspace, or Automation Account. Continuing because the resource group name was explicitly confirmed."
}

if ($DryRun) {
    Write-Output "Dry run requested. No resources were deleted."
    return
}

$dcrResources = @($initialResources | Where-Object { $_.ResourceType -eq 'Microsoft.Insights/dataCollectionRules' })
foreach ($resource in $dcrResources) {
    Start-GuardrailsArmResourceDelete -ResourceId $resource.ResourceId -ResourceType $resource.ResourceType -ResourceName $resource.Name
}

$dceResources = @($initialResources | Where-Object { $_.ResourceType -eq 'Microsoft.Insights/dataCollectionEndpoints' })
foreach ($resource in $dceResources) {
    Start-GuardrailsArmResourceDelete -ResourceId $resource.ResourceId -ResourceType $resource.ResourceType -ResourceName $resource.Name
}

if ($ForceDeleteLogAnalyticsWorkspace) {
    $logAnalyticsWorkspaces = @(Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue)
    foreach ($workspace in $logAnalyticsWorkspaces) {
        Write-Output "Force-deleting Log Analytics workspace '$($workspace.Name)'."
        $workspace | Remove-AzOperationalInsightsWorkspace -ForceDelete -Force -ErrorAction Stop | Out-Null
    }
}
else {
    Write-Output "Skipping explicit Log Analytics workspace force-delete because ForceDeleteLogAnalyticsWorkspace is false."
}

Write-Output "Starting resource group delete for '$ResourceGroupName'."
Remove-AzResourceGroup -Name $ResourceGroupName -Force -AsJob -ErrorAction SilentlyContinue | Out-Null

$deleteDeadline = (Get-Date).AddMinutes($TimeoutMinutes)
$clearChecks = 0
do {
    try {
        $null = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
        $clearChecks = 0
    }
    catch {
        if ($_.Exception.Message -match 'could not be found|ResourceGroupNotFound|Resource group .* could not be found') {
            $clearChecks++
            Write-Output "Resource group '$ResourceGroupName' is no longer found (clearChecks=$clearChecks/3)."
        }
        else {
            $clearChecks = 0
            Write-Warning "Retrying resource group deletion check after transient error: $($_.Exception.Message)"
        }
    }

    if ($clearChecks -ge 3) {
        Write-Output "Resource group '$ResourceGroupName' deletion confirmed."
        return
    }

    if ((Get-Date) -ge $deleteDeadline) {
        $remainingResources = @(Get-AzResource -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Sort-Object ResourceType, Name)
        if ($remainingResources.Count -eq 0) {
            throw "Timed out waiting for resource group '$ResourceGroupName' deletion to be confirmed, but no child resources are visible. Retry the cleanup workflow or check Azure Activity Log."
        }

        $remainingResourceSummary = $remainingResources | Select-Object ResourceType, Name | Format-Table -AutoSize | Out-String
        throw "Timed out waiting for resource group '$ResourceGroupName' to be deleted. Remaining resources: $remainingResourceSummary"
    }

    $remainingCount = @(Get-AzResource -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue).Count
    Write-Output "Waiting for resource group '$ResourceGroupName' deletion. Remaining resources: $remainingCount."
    Start-Sleep -Seconds $PollIntervalSeconds
} while ($true)