@{
    RootModule = 'Manage-GSAAutomationRuntime.psm1'
    ModuleVersion = '1.0.0'
    GUID = '97b2327c-b52a-44b5-b982-9d95d09101df'
    Author = 'Cloud Security Compliance'
    CompanyName = 'Shared Services Canada'
    Description = 'Manages the Guardrails Azure Automation Runtime Environment and linked runbooks.'
    # This is the deployment helper's minimum local shell version, not the runbook runtime version.
    # The deployment configuration and Bicep template explicitly select PowerShell 7.6 for the runbooks.
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Format-GSAElapsedTime'
        'Assert-GSAAutomationRuntimeEnvironment'
        'Wait-GSAAutomationRuntimeModules'
        'Set-GSAAutomationRunbook'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}