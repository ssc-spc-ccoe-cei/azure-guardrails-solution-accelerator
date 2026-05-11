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
    $DcrDeleteTimeoutSeconds = 300
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

    if (-not (Wait-Job -Job $job -Timeout $DcrDeleteTimeoutSeconds)) {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        Write-Warning "Delete for $ResourceType '$ResourceName' did not finish within $DcrDeleteTimeoutSeconds seconds and may still be pending in Azure. Continuing to resource group delete."
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

function Remove-GuardrailsAutomationMsiRoleAssignment {
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
                Write-Output "Role assignment not found: $Description"
                return
            }

            Write-Output "Removing role assignment: $Description"
            Remove-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleDefinitionName -Scope $Scope -ErrorAction Stop | Out-Null
            return
        }
        catch {
            $message = "Failed to remove role assignment '$Description'. Resource group cleanup will continue, but RBAC may need manual cleanup if role-assignment quotas become a problem. Error: $($_.Exception.Message)"
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

if ($ResourceGroupName -ne $ConfirmResourceGroupName) {
    throw "Confirmation mismatch. ResourceGroupName '$ResourceGroupName' does not match ConfirmResourceGroupName '$ConfirmResourceGroupName'."
}

Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
$tenantRootManagementGroupScope = "/providers/Microsoft.Management/managementGroups/$((Get-AzContext).Tenant.Id)"

$resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $resourceGroup) {
    Write-Output "Resource group '$ResourceGroupName' was not found in subscription '$SubscriptionId'. Nothing to delete."
    return
}

Write-Output "Preparing to delete resource group '$ResourceGroupName' in subscription '$SubscriptionId'."
try {
    $initialResources = @(Get-AzResource -ResourceGroupName $ResourceGroupName -ErrorAction Stop | Sort-Object ResourceType, Name)
}
catch {
    throw "Failed to enumerate resources in '$ResourceGroupName'. Cleanup cannot safely continue because ordered DCR cleanup depends on a complete resource list. Error: $($_.Exception.Message)"
}

if ($initialResources.Count -eq 0) {
    Write-Output "Resource group '$ResourceGroupName' has no active child resources."
}
else {
    Write-Output "Resources found before cleanup:"
    $initialResources | Select-Object ResourceType, Name | Format-Table -AutoSize | Out-String | Write-Output
}

if ($DryRun) {
    Write-Output "Dry run requested. No resources were deleted."
    return
}

try {
    $automationAccounts = @(Get-AzAutomationAccount -ResourceGroupName $ResourceGroupName -ErrorAction Stop)
}
catch {
    $automationAccountResources = @($initialResources | Where-Object { $_.ResourceType -eq 'Microsoft.Automation/automationAccounts' })
    if ($automationAccountResources.Count -gt 0) {
        Write-Warning "Failed to read Automation Account resources in '$ResourceGroupName'. Off-RG MSI role assignments may remain and can be cleaned up manually if they cause quota pressure. Error: $($_.Exception.Message)"
    }
    else {
        Write-Output "No Automation Account resources found in '$ResourceGroupName'."
    }
    $automationAccounts = @()
}

$storageAccounts = @(Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue)
foreach ($automationAccount in $automationAccounts) {
    $automationAccountMsi = $automationAccount.Identity.PrincipalId
    if ([string]::IsNullOrWhiteSpace($automationAccountMsi)) {
        continue
    }

    # Tenant/provider-scope assignments are outside the target resource group.
    # Remove them when possible, but keep the operator-requested RG deletion
    # moving if RBAC cleanup fails.
    Remove-GuardrailsAutomationMsiRoleAssignment -ObjectId $automationAccountMsi -RoleDefinitionName Reader -Scope $tenantRootManagementGroupScope -Description "Reader on tenant root management group for '$($automationAccount.AutomationAccountName)'"
    Remove-GuardrailsAutomationMsiRoleAssignment -ObjectId $automationAccountMsi -RoleDefinitionName Reader -Scope '/providers/Microsoft.aadiam' -Description "Reader on Azure AD IAM scope for '$($automationAccount.AutomationAccountName)'"
    Remove-GuardrailsAutomationMsiRoleAssignment -ObjectId $automationAccountMsi -RoleDefinitionName Reader -Scope '/providers/Microsoft.Marketplace' -Description "Reader on Azure Marketplace scope for '$($automationAccount.AutomationAccountName)'"

    foreach ($storageAccount in $storageAccounts) {
        Remove-GuardrailsAutomationMsiRoleAssignment -ObjectId $automationAccountMsi -RoleDefinitionName 'Reader and Data Access' -Scope $storageAccount.Id -Description "Reader and Data Access on Storage Account '$($storageAccount.StorageAccountName)' for '$($automationAccount.AutomationAccountName)'"
    }
}

$dcrResources = @($initialResources | Where-Object { $_.ResourceType -eq 'Microsoft.Insights/dataCollectionRules' })
foreach ($resource in $dcrResources) {
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
        $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
        if ($null -eq $resourceGroup) {
            $clearChecks++
            Write-Output "Resource group '$ResourceGroupName' is no longer returned (clearChecks=$clearChecks/3)."
            if ($clearChecks -ge 3) {
                Write-Output "Resource group '$ResourceGroupName' deletion confirmed."
                return
            }
            Start-Sleep -Seconds $PollIntervalSeconds
            continue
        }

        $clearChecks = 0
    }
    catch {
        if ($_.Exception.Message -match 'could not be found|ResourceGroupNotFound|ResourceNotFound|NotFound|Resource group .* could not be found|does not exist|not found') {
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