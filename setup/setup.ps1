param (
    [Parameter(Mandatory = $true)]
    [string]
    $configFilePath,
    [Parameter(Mandatory = $false)]
    [string]
    $userId = '',
    [Parameter(Mandatory = $false)]
    [string]
    $existingKeyVaultName,
    # Configure lighthouse delegation - requires lighthousePrincipalDisplayName, lighthousePrincipalDisplayName, and lighthouseServiceProviderTenantID in config.json
    [Parameter(Mandatory = $false)]
    [switch]
    $configureLighthouseAccessDelegation,
    [Parameter(Mandatory = $false)]
    [string]
    $existingKeyVaultRG,
    [Parameter(Mandatory = $false)]
    [string]
    $existingWorkspaceName,
    [Parameter(Mandatory = $false)]
    [string]
    $existingWorkSpaceRG,
    [Parameter(Mandatory = $false)]
    [switch]
    $skipDeployment,
    # alternate custom powershell modules URL -- use for module development/testing
    [Parameter(mandatory = $false)]
    [uri]
    $alternatePSModulesURL,
    [Parameter(Mandatory = $false)]
    [switch]
    $update,
    [string] $subscriptionId,

    # proceed through imput prompts
    [Parameter(Mandatory = $false)]
    [Alias('y')]
    [switch]
    $yes
)

#ensures verbose preference is passed through to sub-modules
If ($PSBoundParameters.ContainsKey('verbose')) {
    $useVerbose = $true
}
Else {
    $useVerbose = $false
}


$legacyParameters = @(
    "existingKeyVaultName",
    "existingKeyVaultRG",
    "existingWorkspaceName",
    "existingWorkSpaceRG",
    "skipDeployment",
    "subscriptionId"
)
ForEach ($legacyParameter in $legacyParameters) {
    If ($PSBoundParameters.ContainsKey($legacyParameter)) {
        Write-Warning "Parameter '$legacyParameter' is deprecated; to use this parameter, execute the setup_legacy.ps1 script instead."
        break
    }
}

Import-Module $PSScriptRoot\..\src\GuardrailsSolutionAcceleratorSetup

If (!$update.IsPresent) {
    If (!$configureLighthouseAccessDelegation.IsPresent) {
        Deploy-GuardrailsSolutionAccelerator -configFilePath $configFilePath -verbose:$useVerbose -Yes:$yes.isPresent
    }
    Else {
        Deploy-GuardrailsSolutionAccelerator -configFilePath $configFilePath -newComponents CoreComponents, CentralizedCustomerDefenderForCloudSupport, CentralizedCustomerReportingSupport -Yes:$yes.isPresent -verbose:$useVerbose
    }
}
Else {
    Deploy-GuardrailsSolutionAccelerator -configFilePath $configFilePath -updateComponents All -Yes:$yes.isPresent -verbose:$useVerbose
}
