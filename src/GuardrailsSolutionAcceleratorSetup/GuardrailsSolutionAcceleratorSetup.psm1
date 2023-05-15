Import-Module $PSScriptRoot\modules\Deploy-GuardrailsSolutionAccelerator\Deploy-GuardrailsSolutionAccelerator.psd1
Import-Module $PSScriptRoot\modules\Get-GSAExportedConfig\Get-GSAExportedConfig.psd1
Import-module $PSScriptRoot\modules\Remove-GSACentralizedDefenderCustomerComponents\Remove-GSACentralizedDefenderCustomerComponents.psd1
Import-module $PSScriptRoot\modules\Remove-GSACentralizedReportingCustomerComponents\Remove-GSACentralizedReportingCustomerComponents.psd1
Import-module $PSScriptRoot\modules\Remove-GSACoreResources\Remove-GSACoreResources.psd1

# list functions to export from module for public consumption; also update in Deploy-GuardrailsSolutionAccelerator.psm1 when making changes
$functionsToExport = @(
    'Deploy-GuardrailsSolutionAccelerator'
    'Get-GSAExportedConfig'
    'Remove-GSACentralizedDefenderCustomerComponents'
    'Remove-GSACentralizedReportingCustomerComponents'
    'Remove-GSACoreResources'
)

Export-ModuleMember -Function $functionsToExport
