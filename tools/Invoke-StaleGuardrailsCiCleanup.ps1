[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]
    $SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]
    $ResourceGroupPrefix,

    [Parameter(Mandatory = $true)]
    [string]
    $BaseUniqueNameSuffix,

    [Parameter(Mandatory = $true)]
    [string]
    $CurrentUniqueNameSuffix,

    [Parameter(Mandatory = $true)]
    [string]
    $LogAnalyticsWorkspacePrefix,

    [Parameter(Mandatory = $false)]
    [int]
    $TimeoutMinutes = 10,

    [Parameter(Mandatory = $false)]
    [int]
    $PollIntervalSeconds = 30,

    [Parameter(Mandatory = $false)]
    [int]
    $DcrDceDeleteTimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'

function Start-StaleArmResourceDelete {
    # DCR/DCE deletes are best-effort for stale CI resource groups. Any failure
    # is logged and execution continues. The active-resource drain check at the
    # end of this script is the gate that fails CI if quota-sensitive resources
    # remain. Strict customer-facing cleanup stays in Remove-GSACoreResources.
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $ResourceId,

        [Parameter(Mandatory = $true)]
        [string]
        $ResourceName
    )

    if (-not (Get-AzResource -ResourceId $ResourceId -ErrorAction SilentlyContinue)) {
        Write-Output "$ResourceName not found in stale CI resource group."
        return
    }

    Write-Output "Starting best-effort delete for $ResourceName from stale CI resource group."
    try {
        $job = Remove-AzResource -ResourceId $ResourceId -Force -AsJob -ErrorAction Stop
    }
    catch {
        Write-Warning "$ResourceName delete could not be started. Continuing stale CI cleanup; the resource group drain check will decide whether this can be left behind. Error: $($_.Exception.Message)"
        return
    }

    if (-not (Wait-Job -Job $job -Timeout $DcrDceDeleteTimeoutSeconds)) {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        Write-Warning "$ResourceName delete did not finish within $DcrDceDeleteTimeoutSeconds seconds and may still be pending in Azure. Continuing stale CI cleanup; the resource group drain check will decide whether this can be left behind."
        return
    }

    try {
        Receive-Job -Job $job -ErrorAction Stop | Out-Null
        Write-Output "$ResourceName delete request completed."
    }
    catch {
        Write-Warning "$ResourceName delete failed. Continuing stale CI cleanup; the resource group drain check will decide whether this can be left behind. Error: $($_.Exception.Message)"
    }
    finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}

Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

$currentResourceGroupName = "$ResourceGroupPrefix$CurrentUniqueNameSuffix"
$staleResourceGroups = @(Get-AzResourceGroup -ErrorAction Stop | Where-Object {
    $_.ResourceGroupName -like "$ResourceGroupPrefix$BaseUniqueNameSuffix*" -and
    $_.ResourceGroupName -ne $currentResourceGroupName
} | Sort-Object -Property ResourceGroupName)

foreach ($staleResourceGroup in $staleResourceGroups) {
    Write-Output "Removing stale CI resource group '$($staleResourceGroup.ResourceGroupName)' before deployment."

    $staleSuffix = $staleResourceGroup.ResourceGroupName.Substring($ResourceGroupPrefix.Length)
    $staleLogAnalyticsWorkspaceName = "$LogAnalyticsWorkspacePrefix$staleSuffix"
    $insightsResourceIdPrefix = "/subscriptions/$SubscriptionId/resourceGroups/$($staleResourceGroup.ResourceGroupName)/providers/Microsoft.Insights"

    Start-StaleArmResourceDelete -ResourceId "$insightsResourceIdPrefix/dataCollectionRules/guardrails-dcr" -ResourceName "Data Collection Rule 'guardrails-dcr'"
    Start-StaleArmResourceDelete -ResourceId "$insightsResourceIdPrefix/dataCollectionRules/guardrails-dcr-2" -ResourceName "Data Collection Rule 'guardrails-dcr-2'"
    Start-StaleArmResourceDelete -ResourceId "$insightsResourceIdPrefix/dataCollectionEndpoints/guardrails-dce" -ResourceName "Data Collection Endpoint 'guardrails-dce'"

    $logAnalyticsWorkspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $staleResourceGroup.ResourceGroupName -Name $staleLogAnalyticsWorkspaceName -ErrorAction SilentlyContinue
    if ($logAnalyticsWorkspace) {
        Write-Output "Force-deleting stale CI Log Analytics workspace '$staleLogAnalyticsWorkspaceName'."
        $logAnalyticsWorkspace | Remove-AzOperationalInsightsWorkspace -ForceDelete -Force
    }
    else {
        Write-Output "Stale CI Log Analytics workspace '$staleLogAnalyticsWorkspaceName' not found."
    }

    Write-Output "Starting resource group delete for stale CI resource group '$($staleResourceGroup.ResourceGroupName)'."
    # Job kickoff is fire-and-forget; the polling loop below decides whether
    # cleanup has reached a state that is safe for the new generated suffix.
    Remove-AzResourceGroup -Name $staleResourceGroup.ResourceGroupName -Force -AsJob -ErrorAction SilentlyContinue | Out-Null

    $staleCleanupDeadline = (Get-Date).AddMinutes($TimeoutMinutes)
    do {
        $remainingResources = @(Get-AzResource -ResourceGroupName $staleResourceGroup.ResourceGroupName -ErrorAction SilentlyContinue)

        # Azure reports these exact resource types for DCRs and DCEs today.
        # Keep the fallback narrow so unrelated cleanup problems still fail CI.
        $nonDcrDceResources = @($remainingResources | Where-Object {
            $_.ResourceType -notin @('Microsoft.Insights/dataCollectionRules', 'Microsoft.Insights/dataCollectionEndpoints')
        })

        if ($remainingResources.Count -eq 0) {
            Write-Output "Stale CI resource group '$($staleResourceGroup.ResourceGroupName)' has no remaining resources. Continuing with the new generated suffix."
            break
        }

        if ($nonDcrDceResources.Count -eq 0) {
            Write-Warning "Stale CI resource group '$($staleResourceGroup.ResourceGroupName)' still has only DCR/DCE resources. Continuing because the new generated suffix does not depend on those old resources."
            break
        }

        if ((Get-Date) -ge $staleCleanupDeadline) {
            $remainingResourceSummary = $nonDcrDceResources | Select-Object ResourceType, Name | Format-Table -AutoSize | Out-String
            throw "Timed out waiting for stale CI resource group '$($staleResourceGroup.ResourceGroupName)' to remove quota-sensitive resources. Remaining non-DCR/DCE resources: $remainingResourceSummary"
        }

        Write-Output "Waiting for stale CI resource group '$($staleResourceGroup.ResourceGroupName)' cleanup. Remaining non-DCR/DCE resources: $($nonDcrDceResources.Count)."
        Start-Sleep -Seconds $PollIntervalSeconds
    } while ($true)
}