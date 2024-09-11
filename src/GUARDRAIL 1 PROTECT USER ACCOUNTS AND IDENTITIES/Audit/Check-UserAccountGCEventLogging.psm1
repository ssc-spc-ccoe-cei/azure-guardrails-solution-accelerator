function Check-UserAccountGCEventLogging {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$LAWResourceId,
        [Parameter(Mandatory=$true)]
        [int]$RequiredRetentionDays,
        [Parameter(Mandatory=$true)]
        [string]$ControlName,
        [Parameter(Mandatory=$true)]
        [string]$ItemName,
        [Parameter(Mandatory=$true)]
        [string]$itsgcode,
        [Parameter(Mandatory=$true)]
        [hashtable]$msgTable,
        [Parameter(Mandatory=$true)]
        [string]$ReportTime
    )

    $IsCompliant = $true
    $Comments = ""
    $ErrorList = @()

    # Parse LAW Resource ID
    $lawParts = $LAWResourceId -split '/'
    $subscriptionId = $lawParts[2]
    $resourceGroupName = $lawParts[4]
    $lawName = $lawParts[-1]

    try {
        # Get the Log Analytics Workspace
        $law = Get-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -Name $lawName -ErrorAction Stop

        # Check retention period
        if ($law.RetentionInDays -lt $RequiredRetentionDays) {
            $IsCompliant = $false
            $Comments += $msgTable.retentionNotMet
            $ErrorList += "Retention period is set to $($law.RetentionInDays) days, required: $RequiredRetentionDays days"
        }

        # Check if required logs are enabled
        $requiredLogs = @('AuditLogs', 'SignInLogs', 'MicrosoftGraphActivityLogs')
        $diagnosticSettings = Get-AzDiagnosticSetting -ResourceId $LAWResourceId

        foreach ($log in $requiredLogs) {
            $logEnabled = $diagnosticSettings.Logs | Where-Object {$_.Category -eq $log -and $_.Enabled -eq $true}
            if (-not $logEnabled) {
                $IsCompliant = $false
                $Comments += $msgTable.logsNotCollected
                $ErrorList += "Required log '$log' is not enabled"
            }
        }

        # Check if Read-only lock is in place
        $lock = Get-AzResourceLock -ResourceGroupName $resourceGroupName -ResourceName $lawName -ResourceType "Microsoft.OperationalInsights/workspaces"
        if (-not $lock -or $lock.Properties.level -ne "ReadOnly") {
            $IsCompliant = $false
            $Comments += $msgTable.noReadOnlyLock
            $ErrorList += "No Read-only lock found on the Log Analytics Workspace"
        }

    }
    catch {
        $IsCompliant = $false
        $Comments += $msgTable.lawNotFound
        $ErrorList += "Error accessing Log Analytics Workspace: $_"
    }

    if ($IsCompliant) {
        $Comments = $msgTable.compliantComment
    }

    $result = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName = $ControlName
        Comments = $Comments
        ItemName = $ItemName
        ReportTime = $ReportTime
        itsgcode = $itsgcode
    }

    $moduleOutput = [PSCustomObject]@{
        ComplianceResults = $result
        Errors = $ErrorList
    }

    return $moduleOutput
}

Export-ModuleMember -Function Check-UserAccountGCEventLogging