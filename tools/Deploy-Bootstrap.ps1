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
.PARAMETER yes
    Skip the bootstrap confirmation prompt. The bootstrap script always passes -yes to downstream commands to avoid duplicate
    confirmation prompts. Prompts that are not controlled by downstream -yes can still appear.
.EXAMPLE
    # New deployment with file-based config and source from the main branch:
    ./Deploy-Bootstrap.ps1 -configFilePath ./config.json -sourceRef main
.EXAMPLE
    # New deployment with file-based config and source from a specific tag, deploying only a subset of components:
    ./Deploy-Bootstrap.ps1 -configFilePath ./config.json -sourceRef v3.0.0beta -newComponents CoreComponents,CentralizedCustomerReportingSupport
.EXAMPLE
    # Update with file-based config, source from tag, and updating only a subset of components:
    ./Deploy-Bootstrap.ps1 -configFilePath ./config.json -sourceRef v2.3.3 -update -componentsToUpdate Workbook,CoreComponents
.EXAMPLE
    # New deployment with Key Vault-based config, source from main, deploying only one new component:
    ./Deploy-Bootstrap.ps1 -keyVaultName guardrails-12345 -sourceRef main -newComponents CentralizedCustomerDefenderForCloudSupport -timeoutSec 120
.EXAMPLE
    # File-based new deployment syntax:
    ./Deploy-Bootstrap.ps1 -configFilePath ./config.json -sourceRef v3.0.0beta [-newComponents CoreComponents,CentralizedCustomerReportingSupport,CentralizedCustomerDefenderForCloudSupport] [-timeoutSec 120] [-yes] [-Verbose] [-Debug]
.EXAMPLE
    # File-based update syntax:
    ./Deploy-Bootstrap.ps1 -configFilePath ./config.json -sourceRef main -update [-componentsToUpdate Workbook,GuardrailPowerShellModules,AutomationAccountRunbooks,CoreComponents] [-timeoutSec 120] [-yes] [-Verbose] [-Debug]
.EXAMPLE
    # Key Vault-based existing deployment syntax:
    ./Deploy-Bootstrap.ps1 -keyVaultName guardrails-12345 -sourceRef fa/some-branch -update [-componentsToUpdate Workbook,GuardrailPowerShellModules,AutomationAccountRunbooks,CoreComponents] [-timeoutSec 120] [-yes] [-Verbose] [-Debug]
.EXAMPLE
    # Key Vault-based existing deployment component-addition syntax:
    ./Deploy-Bootstrap.ps1 -keyVaultName guardrails-12345 -sourceRef main -newComponents CentralizedCustomerReportingSupport,CentralizedCustomerDefenderForCloudSupport [-timeoutSec 120] [-yes] [-Verbose] [-Debug]
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
        $SourceRef
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
            Invoke-WebRequest -Uri $downloadUri -OutFile $archivePath -Headers @{ 'User-Agent' = 'Deploy-Bootstrap' } -TimeoutSec $timeoutSec -ErrorAction Stop -Verbose:$false
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

        # GitHub zipballs unpack into one top-level repo folder. Use that as the repo root.
        $repoRoot = Get-ChildItem -Path $tempRoot -Directory | Select-Object -First 1

        if ($null -eq $repoRoot) {
            throw "Could not determine extracted repository root for source ref '$SourceRef'."
        }

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
        $SourceRef
    )

    # Build the GitHub URL for the module zip files in this ref.
    $modulesUrl = "{0}/raw/{1}/psmodules" -f $script:GitHubRepoRoot, [uri]::EscapeDataString($SourceRef)
    # Check one known file. If it is there, the ref is usable for module downloads.
    $grCommonUrl = "$modulesUrl/GR-Common.zip"

    Write-Verbose "Checking that source ref '$SourceRef' contains '$grCommonUrl'."
    try {
        # HEAD checks whether the file exists without downloading the whole file.
        Invoke-WebRequest -Method Head -Uri $grCommonUrl -Headers @{ 'User-Agent' = 'Deploy-Bootstrap' } -TimeoutSec $timeoutSec -ErrorAction Stop -Verbose:$false | Out-Null
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

# Keep track of what we need to clean up at the end.
$downloadedSource = $null
$refModule = $null

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

    # Make sure Azure sign-in and subscription selection are already in place.
    $azureContext = Get-AzContext -ErrorAction SilentlyContinue
    if ($null -eq $azureContext -or $null -eq $azureContext.Account -or $null -eq $azureContext.Subscription) {
        throw "No Azure context is available. Sign in with Connect-AzAccount and select the correct subscription before running Deploy-Bootstrap.ps1."
    }

    # Validate whichever config source the operator chose.
    if ($PSBoundParameters.ContainsKey('configFilePath')) {
        # Turn the file path into a full path and make sure we can read it.
        $resolvedConfigPath = Resolve-Path -Path $configFilePath -ErrorAction Stop
        $null = Get-Content -Path $resolvedConfigPath.ProviderPath -TotalCount 1 -ErrorAction Stop
        $configFilePath = $resolvedConfigPath.ProviderPath
        $configSourceLabel = 'Config file'
        $configSourceValue = $configFilePath
    }
    else {
        # Make sure the exported config secret exists and we can read it.
        try {
            Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $script:ExportedConfigSecretName -ErrorAction Stop | Out-Null
        }
        catch {
            throw "Unable to read secret '$($script:ExportedConfigSecretName)' from Key Vault '$keyVaultName'. Ensure the Key Vault exists, the exported configuration is present, and your current Azure context has access. $_"
        }

        $configSourceLabel = 'Key Vault'
        $configSourceValue = $keyVaultName
    }

    # Check the requested ref before asking the operator to continue.
    $moduleBaseUrl = Test-BootstrapSourceRef -SourceRef $sourceRef

    # --- Summary: show the operator where this deployment will run ---

    Write-Host "Bootstrap pre-checks passed. Proceeding will run deployment code from the downloaded source ref below:"
    Write-Host ("  PowerShell: {0}" -f $PSVersionTable.PSVersion)
    Write-Host ("  Azure account: {0}" -f $azureContext.Account.Id)
    Write-Host ("  Tenant ID: {0}" -f $azureContext.Tenant.Id)
    Write-Host ("  Subscription ID: {0}" -f $azureContext.Subscription.Id)
    $subscriptionName = if ([string]::IsNullOrWhiteSpace($azureContext.Subscription.Name)) { '(unavailable)' } else { $azureContext.Subscription.Name }
    Write-Host ("  Subscription name: {0}" -f $subscriptionName)
    Write-Host ("  {0}: {1}" -f $configSourceLabel, $configSourceValue)
    Write-Host ("  Source ref: {0}" -f $sourceRef)

    # --- Confirmation: stop here unless the operator already chose -yes ---

    if (-not $yes.IsPresent) {
        Write-Host "Press ENTER to continue or CTRL+C to cancel..."
        $null = Read-Host
    }

    # --- Download and import: get the requested code and load its module ---

    $downloadedSource = Get-BootstrapSourceArchive -SourceRef $sourceRef

    # Make sure the downloaded code includes the module file we expect to import.
    $moduleManifestPath = Join-Path $downloadedSource.RepoRoot 'src/GuardrailsSolutionAcceleratorSetup/GuardrailsSolutionAcceleratorSetup.psd1'
    if (-not (Test-Path -Path $moduleManifestPath -PathType Leaf)) {
        throw "Could not find GuardrailsSolutionAcceleratorSetup module manifest in downloaded ref at '$moduleManifestPath'."
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
        # The downloaded helper returns the saved config as a string for the deploy command.
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
