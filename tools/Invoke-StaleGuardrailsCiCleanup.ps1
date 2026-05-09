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
    $PollIntervalSeconds = 30
)

$ErrorActionPreference = 'Stop'

$azureMonitorTransientDeletePattern = 'ExistingAssociationsPreventDelete|Existing associations with Azure Monitor\s+Data Collection Rule|Data collection rule has been modified before operation completed'

function Remove-StaleArmResource {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $ResourceId,

        [Parameter(Mandatory = $true)]
        [string]
        $ResourceName
    )

    $resource = Get-AzResource -ResourceId $ResourceId -ErrorAction SilentlyContinue
    if (-not $resource) {
        Write-Output "$ResourceName not found."
        return
    }

    $retryDelaysInSeconds = @(15, 30, 60, 120, 180)
    $removeAttempt = 0
    do {
        try {
            Write-Output "Removing $ResourceName from stale CI resource group..."
            Remove-AzResource -ResourceId $ResourceId -Force -ErrorAction Stop | Out-Null
            return
        }
        catch {
            $isAzureMonitorTransientDelete = $_.Exception.Message -match $azureMonitorTransientDeletePattern
            if (-not $isAzureMonitorTransientDelete -or $removeAttempt -ge $retryDelaysInSeconds.Count) {
                throw
            }

            $retryDelayInSeconds = $retryDelaysInSeconds[$removeAttempt]
            $removeAttempt++
            Write-Warning "$ResourceName delete hit a transient Azure Monitor conflict on attempt $removeAttempt of $($retryDelaysInSeconds.Count + 1). Waiting $retryDelayInSeconds seconds before retrying."
            Start-Sleep -Seconds $retryDelayInSeconds
        }
    } while ($true)
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

    try {
        Remove-StaleArmResource -ResourceId "$insightsResourceIdPrefix/dataCollectionRules/guardrails-dcr" -ResourceName "Data Collection Rule 'guardrails-dcr'"
        Remove-StaleArmResource -ResourceId "$insightsResourceIdPrefix/dataCollectionRules/guardrails-dcr-2" -ResourceName "Data Collection Rule 'guardrails-dcr-2'"
        Remove-StaleArmResource -ResourceId "$insightsResourceIdPrefix/dataCollectionEndpoints/guardrails-dce" -ResourceName "Data Collection Endpoint 'guardrails-dce'"
    }
    catch {
        if ($_.Exception.Message -notmatch $azureMonitorTransientDeletePattern) {
            throw
        }

        Write-Warning "Stale CI Azure Monitor DCR/DCE cleanup hit a known transient conflict. Continuing to force-delete LAW and drain the resource group."
    }

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