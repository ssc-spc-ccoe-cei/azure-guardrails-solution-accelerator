<#
.SYNOPSIS
    Download a Guardrails repo ref and run deployment or update from that ref.
.DESCRIPTION
    This bootstrap script lets operators run Guardrails deployment/update code from a specific GitHub branch, tag, or commit
    without cloning the full repository locally. The script performs lightweight environment checks, confirms the target
    context with the operator, downloads the requested ref, imports the downloaded Guardrails setup module, and then calls
    the existing deployment commands from that downloaded copy.

    Fresh install is supported with -configFilePath.
    Existing deployment update is supported with -configFilePath or -keyVaultName.
    Adding new components to an existing deployment is supported with -configFilePath or -keyVaultName.

    Component guide for -newComponents:
      - CoreComponents: deploys the main Guardrails resource group resources, including Log Analytics workspace,
        Automation Account, Storage Account, Key Vault, Workbook, core templates, Automation Account
        PowerShell modules, and core runbooks.
      - CentralizedCustomerReportingSupport: deploys Lighthouse reporting access for a managing tenant.
      - CentralizedCustomerDefenderForCloudSupport: deploys Defender for Cloud support resources for a managing tenant.

    Component guide for -componentsToUpdate:
      - CoreComponents: updates the core Azure resources managed by the main Guardrails template,
        including the Automation Account resource settings and variables, Log Analytics workspace
        resources, storage account resources, and data collection rule / data collection endpoint resources.
      - Workbook: updates workbook content and related saved searches.
      - GuardrailPowerShellModules: updates the Guardrails PowerShell modules in the Automation Account.
      - AutomationAccountRunbooks: updates the Automation Account runbook definitions.
.PARAMETER configFilePath
    Path to the deployment configuration JSON file. Use this for fresh installs or updates when the config file is available locally.
.PARAMETER keyVaultName
    Name of the existing Guardrails Key Vault that stores the exported deployment configuration. This is only supported for update
    or new-components flows.
.PARAMETER sourceRef
    GitHub branch, tag, or commit to download and run.
.PARAMETER update
    Update an existing deployment.
.PARAMETER newComponents
    New components to deploy. With -keyVaultName, this must be used for existing-deployment component-addition flows.
    If omitted for a file-based new deployment, the downstream deploy command uses its own default component set.
.PARAMETER componentsToUpdate
    Specific components to update. If omitted, the downstream deploy command updates its default set of components.
.PARAMETER timeoutSec
    Timeout in seconds for the bootstrap script's GitHub HTTP requests. If omitted, the default is 120 seconds.
.PARAMETER applyConfigTags
    Copy runtime.tagsTable from the provided config into the downloaded ref's setup/tags.json before deployment.
    This is the bootstrap equivalent of manually editing setup/tags.json before running Deploy-GuardrailsSolutionAccelerator directly.
    If omitted, the downloaded ref's setup/tags.json is left unchanged.
.PARAMETER yes
    Skip the bootstrap confirmation prompt. The bootstrap script always passes -yes to downstream commands to avoid duplicate
    confirmation prompts. Prompts that are not controlled by downstream -yes can still appear.
.EXAMPLE
    ./Deploy-Bootstrap.ps1 -configFilePath ./config.json -sourceRef main
    ./Deploy-Bootstrap.ps1 -configFilePath ./config.json -sourceRef v3.0.0beta -newComponents CoreComponents,CentralizedCustomerReportingSupport
.EXAMPLE
    # Fresh install all supported components: core Guardrails resources, workbook, Automation
    # Account PowerShell modules, runbooks, Lighthouse reporting support, and Defender for Cloud support.
    ./Deploy-Bootstrap.ps1 -configFilePath ./config.json -sourceRef main -newComponents CoreComponents,CentralizedCustomerReportingSupport,CentralizedCustomerDefenderForCloudSupport
.EXAMPLE
    # Copy runtime.tagsTable from config into the downloaded setup/tags.json before a fresh install.
    ./Deploy-Bootstrap.ps1 -configFilePath ./config.json -sourceRef main -applyConfigTags
.EXAMPLE
    # Update the full default update set: workbook content, Guardrails PowerShell modules,
    # Automation Account runbooks, and core template-driven resources.
    ./Deploy-Bootstrap.ps1 -configFilePath ./config.json -sourceRef main -update
.EXAMPLE
    # Copy runtime.tagsTable from the exported Key Vault config into the downloaded setup/tags.json before an update.
    ./Deploy-Bootstrap.ps1 -keyVaultName guardrails-12345 -sourceRef main -update -applyConfigTags
.EXAMPLE
    # Update only the Guardrails PowerShell modules in the Automation Account using a local config file.
    ./Deploy-Bootstrap.ps1 -configFilePath ./config.json -sourceRef main -update -componentsToUpdate GuardrailPowerShellModules
.EXAMPLE
    # Update only the Guardrails PowerShell modules in the Automation Account using config
    # saved in an existing Guardrails Key Vault.
    ./Deploy-Bootstrap.ps1 -keyVaultName guardrails-12345 -sourceRef main -update -componentsToUpdate GuardrailPowerShellModules
.EXAMPLE
    # Add Defender for Cloud support to an existing deployment using config saved in Key Vault.
    ./Deploy-Bootstrap.ps1 -keyVaultName guardrails-12345 -sourceRef main -newComponents CentralizedCustomerDefenderForCloudSupport -timeoutSec 120
.EXAMPLE
    ./Deploy-Bootstrap.ps1 -configFilePath ./config.json -sourceRef v1.0.9 -update -componentsToUpdate Workbook,CoreComponents
.EXAMPLE
    # File-based new deployment syntax:
    ./Deploy-Bootstrap.ps1 -configFilePath ./config.json -sourceRef main [-newComponents CoreComponents,CentralizedCustomerReportingSupport,CentralizedCustomerDefenderForCloudSupport] [-applyConfigTags] [-timeoutSec 120] [-yes] [-Verbose] [-Debug]
.EXAMPLE
    # File-based update syntax:
    ./Deploy-Bootstrap.ps1 -configFilePath ./config.json -sourceRef main -update [-componentsToUpdate Workbook,GuardrailPowerShellModules,AutomationAccountRunbooks,CoreComponents] [-applyConfigTags] [-timeoutSec 120] [-yes] [-Verbose] [-Debug]
.EXAMPLE
    # Key Vault-based existing deployment syntax:
    ./Deploy-Bootstrap.ps1 -keyVaultName guardrails-12345 -sourceRef main -update [-componentsToUpdate Workbook,GuardrailPowerShellModules,AutomationAccountRunbooks,CoreComponents] [-applyConfigTags] [-timeoutSec 120] [-yes] [-Verbose] [-Debug]
.EXAMPLE
    # Key Vault-based existing deployment component-addition syntax:
    ./Deploy-Bootstrap.ps1 -keyVaultName guardrails-12345 -sourceRef main -newComponents CentralizedCustomerReportingSupport,CentralizedCustomerDefenderForCloudSupport [-applyConfigTags] [-timeoutSec 120] [-yes] [-Verbose] [-Debug]
#>

[CmdletBinding(DefaultParameterSetName = 'newDeployment-configFilePath')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'newDeployment-configFilePath')]
    [Parameter(Mandatory = $true, ParameterSetName = 'updateDeployment-configFilePath')]
    [Alias('configFileName')]
    [string]
    $configFilePath,

    [Parameter(Mandatory = $true, ParameterSetName = 'updateDeployment-keyVaultName')]
    [Parameter(Mandatory = $true, ParameterSetName = 'newComponents-keyVaultName')]
    [string]
    $keyVaultName,

    [Parameter(Mandatory = $true)]
    [string]
    $sourceRef,

    [Parameter(Mandatory = $true, ParameterSetName = 'updateDeployment-configFilePath')]
    [Parameter(Mandatory = $true, ParameterSetName = 'updateDeployment-keyVaultName')]
    [switch]
    $update,

    [Parameter(Mandatory = $false, ParameterSetName = 'newDeployment-configFilePath')]
    [Parameter(Mandatory = $true, ParameterSetName = 'newComponents-keyVaultName')]
    [ValidateSet(
        'CoreComponents',
        'CentralizedCustomerReportingSupport',
        'CentralizedCustomerDefenderForCloudSupport'
    )]
    [string[]]
    $newComponents,

    [Parameter(Mandatory = $false, ParameterSetName = 'updateDeployment-configFilePath')]
    [Parameter(Mandatory = $false, ParameterSetName = 'updateDeployment-keyVaultName')]
    [ValidateSet(
        'CoreComponents',
        'Workbook',
        'GuardrailPowerShellModules',
        'AutomationAccountRunbooks'
    )]
    [string[]]
    $componentsToUpdate,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 3600)]
    [int]
    $timeoutSec = 120,

    [Parameter(Mandatory = $false)]
    [switch]
    $applyConfigTags,

    [Alias('y')]
    [switch]
    $yes
)

# Stop as soon as something fails.
$ErrorActionPreference = 'Stop'

# Values used in more than one place in this script.
$script:BootstrapPrefix = 'Ref'
$script:GitHubRepoRoot = 'https://github.com/ssc-spc-ccoe-cei/azure-guardrails-solution-accelerator'
$script:GitHubApiRoot = 'https://api.github.com/repos/ssc-spc-ccoe-cei/azure-guardrails-solution-accelerator'
$script:ExportedConfigSecretName = 'gsaConfigExportLatest'

# Download the requested branch, tag, or commit as a zip file, unpack it,
# and return the paths the rest of the script needs.
function Get-BootstrapSourceArchive {
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $SourceRef,

        [Parameter(Mandatory = $true)]
        [int]
        $TimeoutSec
    )

    # Create a unique temp folder so two runs do not use the same location.
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gsa-bootstrap-" + [guid]::NewGuid().Guid)
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

    try {
        $archivePath = Join-Path $tempRoot 'source.zip'
        # Make the ref safe to place in a web address, including branch names with "/".
        $downloadUri = "{0}/zipball/{1}" -f $script:GitHubApiRoot, [uri]::EscapeDataString($SourceRef)

        Write-Host ("Temporary files for this run: {0}" -f $tempRoot)
        Write-Host ("Downloading source ref '{0}' from '{1}'..." -f $SourceRef, $downloadUri)
        # Download the zip file from GitHub.
        try {
            Invoke-WebRequest -Uri $downloadUri -OutFile $archivePath -Headers @{ 'User-Agent' = 'Deploy-Bootstrap' } -TimeoutSec $TimeoutSec -ErrorAction Stop -Verbose:$false
        }
        catch {
            # If GitHub gives us an HTTP status, keep it so we can show a clearer message.
            $statusCode = try { [int]$_.Exception.Response.StatusCode } catch { $null }

            if ($statusCode -eq 403) {
                throw "GitHub API returned HTTP 403 for source ref '$SourceRef'. This may be caused by rate limiting, insufficient permissions, or the ref not being accessible. $_"
            }

            throw
        }

        # Unpack the downloaded zip into the temp folder.
        Write-Verbose "Extracting downloaded source archive to '$tempRoot'."
        Expand-Archive -Path $archivePath -DestinationPath $tempRoot -Force

        # GitHub zipballs should unpack into exactly one top-level repo folder.
        $repoDirectories = Get-ChildItem -Path $tempRoot -Directory
        if ($repoDirectories.Count -ne 1) {
            throw "Expected exactly one extracted repository root for source ref '$SourceRef', found $($repoDirectories.Count)."
        }
        $repoRoot = $repoDirectories[0]

        # Return both the repo path and the temp folder path.
        @{
            TempRoot = $tempRoot
            RepoRoot = $repoRoot.FullName
        }
    }
    catch {
        # Clean up here on failure because the caller may never receive the temp folder path.
        if (Test-Path -Path $tempRoot -PathType Container) {
            Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }

        throw
    }
}

# Check that GitHub can find the requested ref and that it includes the
# expected GR-Common.zip file.
function Test-BootstrapSourceRef {
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $SourceRef,

        [Parameter(Mandatory = $true)]
        [int]
        $TimeoutSec
    )

    # Build the GitHub URL for the module zip files in this ref.
    $modulesUrl = "{0}/raw/{1}/psmodules" -f $script:GitHubRepoRoot, [uri]::EscapeDataString($SourceRef)
    # Check one known file. If it is there, the ref is usable for module downloads.
    $grCommonUrl = "$modulesUrl/GR-Common.zip"

    Write-Verbose "Checking that source ref '$SourceRef' contains '$grCommonUrl'."
    try {
        # HEAD checks whether the file exists without downloading the whole file.
        Invoke-WebRequest -Method Head -Uri $grCommonUrl -Headers @{ 'User-Agent' = 'Deploy-Bootstrap' } -TimeoutSec $TimeoutSec -ErrorAction Stop -Verbose:$false | Out-Null
    }
    catch {
        # If GitHub gives us an HTTP status, use it to explain the failure more clearly.
        $statusCode = try { [int]$_.Exception.Response.StatusCode } catch { $null }

        if ($statusCode -eq 403) {
            throw "GitHub returned HTTP 403 while validating source ref '$SourceRef'. This may be caused by rate limiting, insufficient permissions, or the ref not being accessible. $_"
        }

        if ($statusCode -eq 404) {
            throw "Could not find '$grCommonUrl'. Ensure source ref '$SourceRef' exists and includes 'psmodules/GR-Common.zip'."
        }

        throw "Unable to validate source ref '$SourceRef' using '$grCommonUrl'. $_"
    }

    # Return the base URL for the module zip files.
    $modulesUrl
}

# Read the operator-provided config and return runtime.tagsTable if it exists.
# Bootstrap uses this to keep the downloaded tags file aligned with the config.
function Get-BootstrapConfigTagsTable {
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $ConfigJson
    )

    if ([string]::IsNullOrWhiteSpace($ConfigJson)) {
        return $null
    }

    try {
        $configObject = $ConfigJson | ConvertFrom-Json -AsHashtable
    }
    catch {
        Write-Verbose "Bootstrap could not parse the provided config while checking for runtime.tagsTable."
        return $null
    }

    if ($configObject.runtime -isnot [System.Collections.IDictionary]) {
        return $null
    }

    if ($configObject.runtime.tagsTable -isnot [System.Collections.IDictionary] -or $configObject.runtime.tagsTable.Count -eq 0) {
        return $null
    }

    return @{} + $configObject.runtime.tagsTable
}

# Update the downloaded setup/tags.json file so the downstream deploy command
# sees the same tag values the operator already supplied in the config.
function Update-BootstrapDownloadedTagsFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $RepoRoot,

        [Parameter(Mandatory = $true)]
        [hashtable]
        $TagsTable
    )

    $tagsFilePath = Join-Path $RepoRoot 'setup/tags.json'
    if (-not (Test-Path -Path $tagsFilePath -PathType Leaf)) {
        throw "Could not find downloaded tags file at '$tagsFilePath'."
    }

    $existingTagsJson = Get-Content -Path $tagsFilePath -Raw -ErrorAction Stop
    $existingTagsObject = $existingTagsJson | ConvertFrom-Json -AsHashtable

    if ($existingTagsObject.Count -lt 1) {
        throw "Downloaded tags file '$tagsFilePath' did not contain any tag entries."
    }

    if ($existingTagsObject -is [array]) {
        $mergedTags = @{} + $existingTagsObject[0]
    }
    else {
        $mergedTags = @{} + $existingTagsObject
    }

    foreach ($tagEntry in $TagsTable.GetEnumerator()) {
        $mergedTags[$tagEntry.Key] = $tagEntry.Value
    }

    @($mergedTags) | ConvertTo-Json -Depth 20 | Set-Content -Path $tagsFilePath -ErrorAction Stop
    Write-Host "Applied config runtime.tagsTable values to downloaded setup/tags.json."
}

# Keep track of what we need to clean up at the end.
$downloadedSource = $null
$refModule = $null
$bootstrapConfigJson = $null

try {
    # --- Pre-checks: make sure the script can run before it changes anything ---

    if ($PSVersionTable.PSVersion -lt [version]'7.0') {
        throw "Deploy-Bootstrap.ps1 requires PowerShell 7.0 or later. Current version: $($PSVersionTable.PSVersion)"
    }

    # Reject blank values like "   ".
    if ([string]::IsNullOrWhiteSpace($sourceRef)) {
        throw "-sourceRef cannot be empty or whitespace."
    }
    $sourceRef = $sourceRef.Trim()

    # Check only the Azure commands that this bootstrap script calls directly.
    $requiredCommands = @('Get-AzContext')
    $bicepSummary = 'not detected (used only for Bicep-based deployment/update flows)'

    if ($PSBoundParameters.ContainsKey('keyVaultName')) {
        if ([string]::IsNullOrWhiteSpace($keyVaultName)) {
            throw "-keyVaultName cannot be empty or whitespace."
        }

        $keyVaultName = $keyVaultName.Trim()
        $requiredCommands += 'Get-AzKeyVaultSecret'
    }

    foreach ($commandName in $requiredCommands) {
        if (-not (Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
            throw "Required command '$commandName' is not available. Install or import the required Az modules before running Deploy-Bootstrap.ps1."
        }
    }

    if (Get-Command -Name 'bicep' -ErrorAction SilentlyContinue) {
        $detectedBicepVersion = & bicep --version 2>$null
        if ([string]::IsNullOrWhiteSpace($detectedBicepVersion)) {
            $bicepSummary = 'detected'
        }
        else {
            $bicepSummary = $detectedBicepVersion.Trim()
        }
    }

    # Make sure Azure sign-in and subscription selection are already in place.
    $azureContext = Get-AzContext -ErrorAction SilentlyContinue
    if ($null -eq $azureContext -or $null -eq $azureContext.Account -or $null -eq $azureContext.Subscription) {
        throw "No Azure context is available. Sign in with Connect-AzAccount and select the correct subscription before running Deploy-Bootstrap.ps1."
    }

    # Validate whichever config source the operator chose.
    if ($PSBoundParameters.ContainsKey('configFilePath')) {
        if ([string]::IsNullOrWhiteSpace($configFilePath)) {
            throw "-configFilePath cannot be empty or whitespace."
        }

        $configFilePath = $configFilePath.Trim()
        # Turn the file path into a full path and read the config we will use later.
        $resolvedConfigPath = Resolve-Path -Path $configFilePath -ErrorAction Stop
        $bootstrapConfigJson = Get-Content -Path $resolvedConfigPath.ProviderPath -Raw -ErrorAction Stop
        $configFilePath = $resolvedConfigPath.ProviderPath
        $configSourceLabel = 'Config file'
        $configSourceValue = $configFilePath
    }
    else {
        # Read the exported config now so bootstrap can use it for both tag patching
        # and the downstream deploy command.
        try {
            $bootstrapConfigJson = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $script:ExportedConfigSecretName -AsPlainText -ErrorAction Stop
        }
        catch {
            throw "Unable to read secret '$($script:ExportedConfigSecretName)' from Key Vault '$keyVaultName'. Ensure the Key Vault exists, the exported configuration is present, and your current Azure context has access. $_"
        }

        $configSourceLabel = 'Key Vault'
        $configSourceValue = $keyVaultName
    }

    # Check the requested ref before asking the operator to continue.
    $moduleBaseUrl = Test-BootstrapSourceRef -SourceRef $sourceRef -TimeoutSec $timeoutSec

    # --- Summary: show the operator where this deployment will run ---

    Write-Host "Bootstrap pre-checks passed. Proceeding will run deployment code from the downloaded source ref below:"
    Write-Host ("  PowerShell: {0}" -f $PSVersionTable.PSVersion)
    Write-Host ("  Bicep CLI: {0}" -f $bicepSummary)
    Write-Host ("  Azure account: {0}" -f $azureContext.Account.Id)
    Write-Host ("  Tenant ID: {0}" -f $azureContext.Tenant.Id)
    Write-Host ("  {0}: {1}" -f $configSourceLabel, $configSourceValue)
    Write-Host ("  Source ref: {0}" -f $sourceRef)

    # --- Confirmation: stop here unless the operator already chose -yes ---

    if (-not $yes.IsPresent) {
        Write-Host "Press ENTER to continue or CTRL+C to cancel..."
        $null = Read-Host
    }

    # --- Download and import: get the requested code and load its module ---

    $downloadedSource = Get-BootstrapSourceArchive -SourceRef $sourceRef -TimeoutSec $timeoutSec

    # Make sure the downloaded code includes the module file we expect to import.
    $moduleManifestPath = Join-Path $downloadedSource.RepoRoot 'src/GuardrailsSolutionAcceleratorSetup/GuardrailsSolutionAcceleratorSetup.psd1'
    if (-not (Test-Path -Path $moduleManifestPath -PathType Leaf)) {
        throw "Could not find GuardrailsSolutionAcceleratorSetup module manifest in downloaded ref at '$moduleManifestPath'."
    }

    # Only patch the downloaded tags file when the operator explicitly asks for it.
    if ($applyConfigTags.IsPresent) {
        $bootstrapTagsTable = Get-BootstrapConfigTagsTable -ConfigJson $bootstrapConfigJson
        if ($bootstrapTagsTable) {
            Update-BootstrapDownloadedTagsFile -RepoRoot $downloadedSource.RepoRoot -TagsTable $bootstrapTagsTable
        }
        else {
            Write-Warning "-applyConfigTags was specified, but runtime.tagsTable was not found in the provided config. Downloaded setup/tags.json was left unchanged."
        }
    }

    # Add the prefix so these imported command names do not clash with any version
    # of the same module that might already be loaded in the session.
    Write-Warning "Importing and executing deployment code from downloaded ref at '$($downloadedSource.RepoRoot)'. Only use trusted refs."
    $refModule = Import-Module $moduleManifestPath -Force -Prefix $script:BootstrapPrefix -PassThru

    # --- Build the parameters we will pass into the downloaded commands ---

    # These settings are used by both downloaded commands.
    # -yes is always passed so bootstrap does not ask for confirmation and then
    # immediately show another confirmation prompt from the downloaded commands.
    $commonCommandParams = @{
        yes = $true
    }
    if ($PSBoundParameters.ContainsKey('Verbose')) {
        $commonCommandParams.Verbose = $true
    }
    if ($PSBoundParameters.ContainsKey('Debug')) {
        $commonCommandParams.Debug = $true
    }

    # Start building the deploy command input with the module URL, then add the rest.
    $deployParams = @{
        alternatePSModulesURL = $moduleBaseUrl
    }
    foreach ($entry in $commonCommandParams.GetEnumerator()) {
        $deployParams[$entry.Key] = $entry.Value
    }

    # Pass the config file through directly, or read the saved config from Key Vault.
    if ($PSBoundParameters.ContainsKey('configFilePath')) {
        $deployParams.configFilePath = $configFilePath
    }
    else {
        # Use the downloaded helper to keep Key Vault-to-config handling aligned
        # with the downloaded deploy code.
        $exportedConfig = Get-RefGSAExportedConfig -KeyVaultName $keyVaultName @commonCommandParams
        $deployParams.configString = $exportedConfig.configString
    }

    # Add only the mode switches the operator actually chose.
    # Anything we do not pass here falls back to the downloaded command's defaults.
    if ($update.IsPresent) {
        $deployParams.update = $true
        if ($PSBoundParameters.ContainsKey('componentsToUpdate')) {
            $deployParams.componentsToUpdate = $componentsToUpdate
        }
    }
    elseif ($PSBoundParameters.ContainsKey('newComponents')) {
        $deployParams.newComponents = $newComponents
    }

    # --- Run the deployment code from the downloaded ref ---

    Deploy-RefGuardrailsSolutionAccelerator @deployParams
}
# --- Cleanup: always run this at the end ---
finally {
    # Remove the downloaded module from the current PowerShell session.
    if ($refModule) {
        Remove-Module -ModuleInfo $refModule -Force -ErrorAction SilentlyContinue
    }

    # Delete the temp folder that held the zip file and unpacked repo.
    if ($downloadedSource -and $downloadedSource.TempRoot -and (Test-Path -Path $downloadedSource.TempRoot -PathType Container)) {
        Remove-Item -Path $downloadedSource.TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}