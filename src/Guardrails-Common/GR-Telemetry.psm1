# Guardrail telemetry helper functions shared across runbooks.

function Initialize-GuardrailTelemetry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$GuardrailId,
        [Parameter(Mandatory = $true)]
        [string]$RunbookName,
        [Parameter(Mandatory = $true)]
        [string]$WorkSpaceID,
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceKey,
        [Parameter(Mandatory = $false)]
        [string]$SubscriptionId,
        [Parameter(Mandatory = $false)]
        [string]$TenantId,
        [Parameter(Mandatory = $false)]
        [string]$JobId,
        [Parameter(Mandatory = $false)]
        [string]$CorrelationId
    )

    $telemetryEnabled = $false
    if ($env:ENABLE_DEBUG_METRICS) {
        $telemetryEnabled = [string]::Equals($env:ENABLE_DEBUG_METRICS, 'true', [System.StringComparison]::InvariantCultureIgnoreCase)
    }

    if (-not $telemetryEnabled) {
        return [pscustomobject]@{ Enabled = $false }
    }

    if ([string]::IsNullOrWhiteSpace($WorkSpaceID) -or [string]::IsNullOrWhiteSpace($WorkspaceKey)) {
        Write-Verbose "Guardrail telemetry disabled due to missing workspace configuration."
        return [pscustomobject]@{ Enabled = $false }
    }

    if (-not $CorrelationId) {
        $CorrelationId = [guid]::NewGuid().ToString()
    }

    return [pscustomobject]@{
        Enabled        = $true
        GuardrailId    = $GuardrailId
        RunbookName    = $RunbookName
        WorkspaceId    = $WorkSpaceID
        WorkspaceKey   = $WorkspaceKey
        SubscriptionId = $SubscriptionId
        TenantId       = $TenantId
        JobId          = $JobId
        CorrelationId  = $CorrelationId
    }
}

function Write-GuardrailTelemetry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [psobject]$Context,
        [Parameter(Mandatory = $true)]
        [string]$ExecutionScope,
        [Parameter(Mandatory = $true)]
        [string]$EventType,
        [Parameter(Mandatory = $false)]
        [string]$ModuleName,
        [Parameter(Mandatory = $false)]
        [string]$Status,
        [Parameter(Mandatory = $false)]
        [double]$DurationMs,
        [Parameter(Mandatory = $false)]
        [double]$ErrorCount,
        [Parameter(Mandatory = $false)]
        [double]$WarningCount,
        [Parameter(Mandatory = $false)]
        [double]$ItemCount,
        [Parameter(Mandatory = $false)]
        [double]$CompliantCount,
        [Parameter(Mandatory = $false)]
        [double]$NonCompliantCount,
        [Parameter(Mandatory = $false)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [string]$ReportTime
    )

    if (-not $Context -or -not $Context.Enabled) {
        return
    }

    try {
        $record = [ordered]@{
            GuardrailId_s    = $Context.GuardrailId
            RunbookName_s    = $Context.RunbookName
            ModuleName_s     = $ModuleName
            ExecutionScope_s = $ExecutionScope
            EventType_s      = $EventType
            Status_s         = $Status
            CorrelationId_s  = $Context.CorrelationId
            JobId_g          = $Context.JobId
            SubscriptionId_s = $Context.SubscriptionId
            TenantId_s       = $Context.TenantId
        }

        if ($null -ne $DurationMs) {
            $record['DurationMs_d'] = [Math]::Round($DurationMs, 2)
        }
        if ($null -ne $ErrorCount) {
            $record['ErrorCount_d'] = [double]$ErrorCount
        }
        if ($null -ne $WarningCount) {
            $record['WarningCount_d'] = [double]$WarningCount
        }
        if ($null -ne $ItemCount) {
            $record['ItemCount_d'] = [double]$ItemCount
        }
        if ($null -ne $CompliantCount) {
            $record['CompliantCount_d'] = [double]$CompliantCount
        }
        if ($null -ne $NonCompliantCount) {
            $record['NonCompliantCount_d'] = [double]$NonCompliantCount
        }
        if ($ReportTime) {
            $record['ReportTime_s'] = $ReportTime
        }
        if (-not [string]::IsNullOrWhiteSpace($Message)) {
            $record['Message_s'] = $Message
        }

        $data = @([pscustomobject]$record)
        New-LogAnalyticsData -Data $data -WorkSpaceID $Context.WorkspaceId -WorkSpaceKey $Context.WorkspaceKey -LogType "CaCDebugMetrics" | Out-Null
    }
    catch {
        Write-Verbose "Failed to write guardrail telemetry: $_"
    }
}

function New-GuardrailRunState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$GuardrailId,
        [Parameter(Mandatory = $true)]
        [string]$RunbookName,
        [Parameter(Mandatory = $true)]
        [string]$WorkSpaceID,
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceKey,
        [Parameter(Mandatory = $false)]
        [string]$SubscriptionId,
        [Parameter(Mandatory = $false)]
        [string]$TenantId,
        [Parameter(Mandatory = $false)]
        [string]$JobId,
        [Parameter(Mandatory = $false)]
        [string]$ReportTime
    )

    $telemetryContext = Initialize-GuardrailTelemetry -GuardrailId $GuardrailId -RunbookName $RunbookName -WorkSpaceID $WorkSpaceID -WorkspaceKey $WorkspaceKey -SubscriptionId $SubscriptionId -TenantId $TenantId -JobId $JobId

    $runState = [pscustomobject]@{
        TelemetryContext = $telemetryContext
        ReportTime       = $ReportTime
        RunStopwatch     = [System.Diagnostics.Stopwatch]::StartNew()
        Stats            = [ordered]@{
            ModulesEnabled    = 0
            ModulesDisabled   = 0
            ModulesSucceeded  = 0
            ModulesFailed     = 0
            TotalItems        = 0
            CompliantItems    = 0
            NonCompliantItems = 0
            Errors            = 0
            Warnings          = 0
        }
        Summaries        = [System.Collections.Generic.List[psobject]]::new()
    }

    Write-GuardrailTelemetry -Context $telemetryContext -ExecutionScope 'Runbook' -ModuleName 'RUNBOOK' -EventType 'Start' -Status 'Running' -ReportTime $ReportTime

    return $runState
}

function Start-GuardrailModuleState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [psobject]$RunState,
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )

    $RunState.Stats.ModulesEnabled++

    $moduleState = [pscustomobject]@{
        ModuleName = $ModuleName
        Stopwatch  = [System.Diagnostics.Stopwatch]::StartNew()
    }

    Write-GuardrailTelemetry -Context $RunState.TelemetryContext -ExecutionScope 'Module' -ModuleName $ModuleName -EventType 'Start' -Status 'Running' -ReportTime $RunState.ReportTime

    return $moduleState
}

function Complete-GuardrailModuleState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [psobject]$RunState,
        [Parameter(Mandatory = $true)]
        [psobject]$ModuleState,
        [Parameter(Mandatory = $true)]
        [string]$Status,
        [Parameter(Mandatory = $false)]
        [int]$ErrorCount = 0,
        [Parameter(Mandatory = $false)]
        [int]$WarningCount = 0,
        [Parameter(Mandatory = $false)]
        [int]$ItemCount = 0,
        [Parameter(Mandatory = $false)]
        [int]$CompliantCount = 0,
        [Parameter(Mandatory = $false)]
        [int]$NonCompliantCount = 0,
        [Parameter(Mandatory = $false)]
        [string]$Message
    )

    if ($ModuleState.Stopwatch -and $ModuleState.Stopwatch.IsRunning) {
        $ModuleState.Stopwatch.Stop()
    }

    $durationMs = $null
    if ($ModuleState.Stopwatch) {
        $durationMs = $ModuleState.Stopwatch.Elapsed.TotalMilliseconds
    }

    if ($Status -eq 'Failed') {
        $RunState.Stats.ModulesFailed++
    }
    elseif ($Status -eq 'Skipped') {
        # handled in Skip helper
    }
    else {
        $RunState.Stats.ModulesSucceeded++
    }

    $RunState.Stats.Errors += $ErrorCount
    $RunState.Stats.Warnings += $WarningCount
    $RunState.Stats.TotalItems += $ItemCount
    $RunState.Stats.CompliantItems += $CompliantCount
    $RunState.Stats.NonCompliantItems += $NonCompliantCount

    if (-not $Message) {
        $parts = @("Items=$ItemCount")
        if ($ErrorCount -gt 0) { $parts += "Errors=$ErrorCount" }
        if ($WarningCount -gt 0) { $parts += "Warnings=$WarningCount" }
        $Message = $parts -join '; '
    }

    Write-GuardrailTelemetry -Context $RunState.TelemetryContext -ExecutionScope 'Module' -ModuleName $ModuleState.ModuleName -EventType 'End' -Status $Status -DurationMs $durationMs -ErrorCount $ErrorCount -WarningCount $WarningCount -ItemCount $ItemCount -CompliantCount $CompliantCount -NonCompliantCount $NonCompliantCount -ReportTime $RunState.ReportTime -Message $Message

    $summary = [pscustomobject]@{
        ModuleName      = $ModuleState.ModuleName
        Status          = $Status
        DurationSeconds = if ($null -ne $durationMs) { [Math]::Round($durationMs / 1000, 2) } else { 0 }
        Items           = $ItemCount
        Errors          = $ErrorCount
        Warnings        = $WarningCount
    }
    $null = $RunState.Summaries.Add($summary)

    return $summary
}

function Skip-GuardrailModuleState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [psobject]$RunState,
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )

    $RunState.Stats.ModulesDisabled++

    Write-GuardrailTelemetry -Context $RunState.TelemetryContext -ExecutionScope 'Module' -ModuleName $ModuleName -EventType 'Skipped' -Status 'Skipped' -ReportTime $RunState.ReportTime

    $summary = [pscustomobject]@{
        ModuleName      = $ModuleName
        Status          = 'Skipped'
        DurationSeconds = 0
        Items           = 0
        Errors          = 0
        Warnings        = 0
    }
    $null = $RunState.Summaries.Add($summary)

    return $summary
}

function Complete-GuardrailRunState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [psobject]$RunState
    )

    if ($RunState.RunStopwatch -and $RunState.RunStopwatch.IsRunning) {
        $RunState.RunStopwatch.Stop()
    }

    $duration = if ($RunState.RunStopwatch) { $RunState.RunStopwatch.Elapsed } else { [TimeSpan]::Zero }

    $status = 'Succeeded'
    if ($RunState.Stats.ModulesFailed -gt 0) {
        $status = 'Failed'
    }
    elseif ($RunState.Stats.Errors -gt 0) {
        $status = 'CompletedWithErrors'
    }
    elseif ($RunState.Stats.Warnings -gt 0) {
        $status = 'CompletedWithWarnings'
    }

    $messageParts = @(
        "ModulesEnabled=$($RunState.Stats.ModulesEnabled)",
        "ModulesSucceeded=$($RunState.Stats.ModulesSucceeded)",
        "ModulesFailed=$($RunState.Stats.ModulesFailed)",
        "ModulesDisabled=$($RunState.Stats.ModulesDisabled)",
        "TotalItems=$($RunState.Stats.TotalItems)"
    )
    $runMessage = $messageParts -join '; '

    Write-GuardrailTelemetry -Context $RunState.TelemetryContext -ExecutionScope 'Runbook' -ModuleName 'RUNBOOK' -EventType 'End' -Status $status -DurationMs $duration.TotalMilliseconds -ErrorCount $RunState.Stats.Errors -WarningCount $RunState.Stats.Warnings -ItemCount $RunState.Stats.TotalItems -CompliantCount $RunState.Stats.CompliantItems -NonCompliantCount $RunState.Stats.NonCompliantItems -ReportTime $RunState.ReportTime -Message $runMessage

    return [pscustomobject]@{
        Status    = $status
        Duration  = $duration
        Stats     = $RunState.Stats
        Summaries = $RunState.Summaries
    }
}