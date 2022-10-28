Function Get-GSAExportedConfig {
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
        Write-Warning "Executing this command will output your config value to the console, which may be a security concern. It is recommended to run this command with the syntax below:`n`n`tGet-GSAExportedConfig -KeyVaultName guardrails-12345 | Remove-GSACoreComponents`n`nPress ENTER to proceed or CTRL+C to cancel."
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