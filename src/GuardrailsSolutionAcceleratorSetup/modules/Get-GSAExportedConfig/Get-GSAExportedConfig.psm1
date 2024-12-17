Function Get-GSAExportedConfig {
    <#
    .SYNOPSIS
        Retrieves an exported Guardrails Solution Accelerator configuration from the specified Key Vault.
    .DESCRIPTION
        During the deployment of the Guardrails Solution Accelerator, the configuration originally specified in the JSON file referenced by
        the -configFilePath parameter is exported to the deployed Key Vault in the GSA resource group. This function retrieves the latest exported configuration from
        the Key Vault specified by the -keyVaultName parameter. 

        This function is intended to be used in a PowerShell pipeline to pass the retrieved configuration to other functions. See examples below. 
    .NOTES
        This function retrieves potentially sensitive information from the specified Key Vault. It is recommended that output is not saved to a file or logged. 

    .EXAMPLE 
        # Update an existing GSA instance (PowerShell modules, workbooks, and runbooks):
        Get-GSAExportedConfig -KeyVaultName guardrails-12345 | Deploy-GuardrailsSolutionAccelerator -update
    .EXAMPLE
        # Add the CentralizedCustomerDefenderForCloudSupport component to an existing deployment, retrieving the configuration from the existing deployment's Key Vault
        Get-GSAExportedConfig -KeyVaultName guardrails-12345 | deploy-GuardrailsSolutionAccelerator -newComponents CentralizedCustomerDefenderForCloudSupport
    .EXAMPLE
        # Remove a Guardrails Solution Acclerator deployment
        Import-Module src\GuardrailsSolutionAcceleratorSetup\modules\Remove-GSACoreResources
        Get-GSAExportedConfig -KeyVaultName guardrails-12345 | Remove-GSACoreComponents
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $KeyVaultName,

        # proceed without prompting for confirmation
        [Parameter(Mandatory = $false)]
        [Alias(
            'y'
        )]
        [switch]
        $yes
    )
    $ErrorActionPreference = 'Stop'

    If (!$yes.IsPresent) {
        Write-Host "Retrieving the latest configuration from Key Vault $KeyVaultName. To find a previous version, use the Azure Portal and browse the secret versions for secret name 'gsaConfigExportLatest'. Note that each secret version has tags with deployment details."
        Write-Warning "Executing this command will output your config value to the console, which may be a security concern. It is recommended to run this command with the syntax similar to below, where the output from Get-GSAExportedConfig is passed through the pipline. See Get-Help Get-GSAExportedConfig for more info. To surpress this warning, include the '-yes' parameter.:`n`n`tGet-GSAExportedConfig -KeyVaultName guardrails-12345 -yes | Deploy-GuardrailsSolutionAccelerator -update`n`nPress ENTER to proceed or CTRL+C to cancel."
        $null = Read-Host
    }
    
    try {
        [string]$configValue = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'gsaConfigExportLatest' -AsPlainText -ErrorAction Stop
    }
    catch {
        Write-Error -Message "Unable to retrieve the latest configuration from the Key Vault. Please ensure that the Key Vault exists and that the latest configuration has been exported. Message: $_" -ErrorAction Stop
    }

    return (New-Object -TypeName PSObject -Property @{configString = $configValue})
}
