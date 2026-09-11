[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]
    $RepositoryRoot = (Split-Path $PSScriptRoot -Parent)
)

# Use the installer's reader so CI checks exactly the same source versions and ZIPs.
$helperPath = Join-Path $RepositoryRoot 'src/GuardrailsSolutionAcceleratorSetup/modules/Manage-GSAAutomationRuntime/Manage-GSAAutomationRuntime.psd1'
# Reload this checkout's reader when a developer has an older copy loaded in the same session.
Import-Module $helperPath -Force -ErrorAction Stop
$runtimeModules = @(Get-GSAExpectedAutomationRuntimeModules -RepositoryRoot $RepositoryRoot)
$guardrailsModules = @($runtimeModules | Where-Object { -not $_.ContainsKey('uri') })

Write-Host "Validated $($guardrailsModules.Count) Guardrails Runtime Environment modules against their source manifests and deployment ZIPs."