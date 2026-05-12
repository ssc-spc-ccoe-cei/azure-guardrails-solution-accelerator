[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]
    $SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]
    $ResourceGroupPrefix,

    [Parameter(Mandatory = $false)]
    [string]
    $BaseUniqueNameSuffix = '',

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
    $DcrDeleteTimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'

function ConvertTo-ArmHttpStatusCode {
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
function Get-ResourceGroupArmState {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $SubscriptionId,

        [Parameter(Mandatory = $true)]
        [string]
        $ResourceGroupName
    )

    $encodedResourceGroupName = [System.Uri]::EscapeDataString($ResourceGroupName)
    $resourceGroupUri = ('https://management.azure.com/subscriptions/{0}/resourceGroups/{1}?api-version=2021-04-01' -f $SubscriptionId, $encodedResourceGroupName) -as [uri]
    $statusCode = $null
    $message = $null

    try {
        $response = Invoke-AzRestMethod -Method GET -Uri $resourceGroupUri -ErrorAction Stop
        $statusCode = ConvertTo-ArmHttpStatusCode -StatusCode $response.StatusCode
        $message = $response.Content
    }
    catch {
        $message = $_.Exception.Message
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $statusCode = ConvertTo-ArmHttpStatusCode -StatusCode $_.Exception.Response.StatusCode
        }
        elseif ($_.Exception.StatusCode) {
            $statusCode = ConvertTo-ArmHttpStatusCode -StatusCode $_.Exception.StatusCode
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

function Start-StaleArmResourceDelete {
    # DCR deletes are best-effort for stale CI resource groups. Any failure
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

    if (-not (Wait-Job -Job $job -Timeout $DcrDeleteTimeoutSeconds)) {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        Write-Warning "$ResourceName delete did not finish within $DcrDeleteTimeoutSeconds seconds and may still be pending in Azure. Continuing stale CI cleanup; the resource group drain check will decide whether this can be left behind."
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

function Remove-StaleAutomationMsiRoleAssignment {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $ObjectId,

        [Parameter(Mandatory = $true)]
        [string]
        $RoleDefinitionName,

        [Parameter(Mandatory = $true)]
        [string]
        $Scope,

        [Parameter(Mandatory = $true)]
        [string]
        $Description
    )

    $retryDelaysInSeconds = @(5, 15, 30)
    for ($attempt = 1; $attempt -le ($retryDelaysInSeconds.Count + 1); $attempt++) {
        try {
            $existingAssignment = Get-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleDefinitionName -Scope $Scope -ErrorAction Stop
            if (-not $existingAssignment) {
                Write-Output "Role assignment not found for stale CI cleanup: $Description"
                return
            }

            Write-Output "Removing stale CI role assignment: $Description"
            Remove-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleDefinitionName -Scope $Scope -ErrorAction Stop | Out-Null
            return
        }
        catch {
            $message = "Failed to remove stale CI role assignment '$Description'. The stale resource group cleanup will continue, but RBAC may need manual cleanup if role-assignment quotas become a problem. Error: $($_.Exception.Message)"
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

Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
$tenantRootManagementGroupScope = "/providers/Microsoft.Management/managementGroups/$((Get-AzContext).Tenant.Id)"

$currentResourceGroupName = "$ResourceGroupPrefix$CurrentUniqueNameSuffix"
# The dev/test CI prefixes are disposable cleanup scopes. This intentionally
# also cleans manually-created RGs that use those prefixes.
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
        $automationAccounts = @(Get-AzAutomationAccount -ResourceGroupName $staleResourceGroup.ResourceGroupName -ErrorAction Stop)
    }
    catch {
        $automationAccountResources = @(Get-AzResource -ResourceGroupName $staleResourceGroup.ResourceGroupName -ResourceType 'Microsoft.Automation/automationAccounts' -ErrorAction SilentlyContinue)
        if ($automationAccountResources.Count -gt 0) {
            Write-Warning "Failed to read Automation Account resources in stale CI resource group '$($staleResourceGroup.ResourceGroupName)'. Off-RG MSI role assignments may remain and can be cleaned up manually if they cause quota pressure. Error: $($_.Exception.Message)"
        }
        else {
            Write-Output "No Automation Account resources found in stale CI resource group '$($staleResourceGroup.ResourceGroupName)'."
        }
        $automationAccounts = @()
    }

    $storageAccounts = @(Get-AzStorageAccount -ResourceGroupName $staleResourceGroup.ResourceGroupName -ErrorAction SilentlyContinue)
    foreach ($automationAccount in $automationAccounts) {
        $automationAccountMsi = $automationAccount.Identity.PrincipalId
        if ([string]::IsNullOrWhiteSpace($automationAccountMsi)) {
            continue
        }

        # Tenant/provider-scope assignments are outside the stale resource group.
        # Remove them when possible, but do not block CI cleanup if RBAC cleanup
        # fails; the deployment resources are the higher-priority cleanup target.
        Remove-StaleAutomationMsiRoleAssignment -ObjectId $automationAccountMsi -RoleDefinitionName Reader -Scope $tenantRootManagementGroupScope -Description "Reader on tenant root management group for '$($automationAccount.AutomationAccountName)'"
        Remove-StaleAutomationMsiRoleAssignment -ObjectId $automationAccountMsi -RoleDefinitionName Reader -Scope '/providers/Microsoft.aadiam' -Description "Reader on Azure AD IAM scope for '$($automationAccount.AutomationAccountName)'"
        Remove-StaleAutomationMsiRoleAssignment -ObjectId $automationAccountMsi -RoleDefinitionName Reader -Scope '/providers/Microsoft.Marketplace' -Description "Reader on Azure Marketplace scope for '$($automationAccount.AutomationAccountName)'"

        foreach ($storageAccount in $storageAccounts) {
            Remove-StaleAutomationMsiRoleAssignment -ObjectId $automationAccountMsi -RoleDefinitionName 'Reader and Data Access' -Scope $storageAccount.Id -Description "Reader and Data Access on Storage Account '$($storageAccount.StorageAccountName)' for '$($automationAccount.AutomationAccountName)'"
        }
    }

    Start-StaleArmResourceDelete -ResourceId "$insightsResourceIdPrefix/dataCollectionRules/guardrails-dcr" -ResourceName "Data Collection Rule 'guardrails-dcr'"
    Start-StaleArmResourceDelete -ResourceId "$insightsResourceIdPrefix/dataCollectionRules/guardrails-dcr-2" -ResourceName "Data Collection Rule 'guardrails-dcr-2'"

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
    # cleanup has reached a state that is safe for the current deployment suffix.
    Remove-AzResourceGroup -Name $staleResourceGroup.ResourceGroupName -Force -AsJob -ErrorAction SilentlyContinue | Out-Null

    $staleCleanupDeadline = (Get-Date).AddMinutes($TimeoutMinutes)
    do {
        try {
            $remainingResources = @(Get-AzResource -ResourceGroupName $staleResourceGroup.ResourceGroupName -ErrorAction Stop)
        }
        catch {
            $resourceGroupState = Get-ResourceGroupArmState -SubscriptionId $SubscriptionId -ResourceGroupName $staleResourceGroup.ResourceGroupName
            if ($resourceGroupState.State -eq 'Deleted') {
                Write-Output "Stale CI resource group '$($staleResourceGroup.ResourceGroupName)' no longer exists. Continuing with the current deployment suffix."
                break
            }

            if ($resourceGroupState.State -eq 'Retry') {
                Write-Warning "Retrying stale CI resource group deletion check after transient ARM status '$($resourceGroupState.StatusCode)': $($resourceGroupState.Message)"
                Start-Sleep -Seconds $PollIntervalSeconds
                continue
            }

            throw "Failed to enumerate remaining resources in stale CI resource group '$($staleResourceGroup.ResourceGroupName)'. Cleanup cannot safely determine whether only DCR resources remain. Error: $($_.Exception.Message)"
        }

        # Azure reports this exact resource type for DCRs today.
        # Keep the fallback narrow so unrelated cleanup problems still fail CI.
        $nonDcrResources = @($remainingResources | Where-Object {
            $_.ResourceType -ne 'Microsoft.Insights/dataCollectionRules'
        })

        if ($remainingResources.Count -eq 0) {
            Write-Output "Stale CI resource group '$($staleResourceGroup.ResourceGroupName)' has no remaining resources. Continuing with the current deployment suffix."
            break
        }

        if ($nonDcrResources.Count -eq 0) {
            Write-Warning "Stale CI resource group '$($staleResourceGroup.ResourceGroupName)' still has only DCR resources. Continuing because the current deployment suffix does not depend on those old resources."
            break
        }

        if ((Get-Date) -ge $staleCleanupDeadline) {
            $remainingResourceSummary = $nonDcrResources | Select-Object ResourceType, Name | Format-Table -AutoSize | Out-String
            throw "Timed out waiting for stale CI resource group '$($staleResourceGroup.ResourceGroupName)' to remove quota-sensitive resources. Remaining non-DCR resources: $remainingResourceSummary"
        }

        Write-Output "Waiting for stale CI resource group '$($staleResourceGroup.ResourceGroupName)' cleanup. Remaining non-DCR resources: $($nonDcrResources.Count)."
        Start-Sleep -Seconds $PollIntervalSeconds
    } while ($true)
}