# Runtime flow:
# 1. Bicep creates the named PowerShell 7.6 environment and imports its modules into the Automation Account.
# 2. This module confirms the environment and modules are ready before publishing runbooks.
# 3. Each runbook is linked to that environment, so its jobs use PowerShell 7.6 and the same module set.
# 4. Later releases reuse this environment when updating modules or runbooks.
# The legacy runbook import cmdlet cannot attach this named environment, so use the Runtime Environment API
# for environment, module, and runbook requests throughout the migration flow. Version 2024-10-23 provides
# the Runtime Environment and runbook-link properties used by this module.
$script:AutomationApiVersion = '2024-10-23'

# Build the Azure Resource Manager path for the named Runtime Environment used by Guardrails.
# Other functions use this path directly or add Azure's `/packages` endpoint for PowerShell modules.
function Get-GSAAutomationRuntimeBasePath {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]
        $Config
    )

    # Read the identifiers prepared during configuration validation. A missing value would create an invalid Azure path.
    $subscriptionId = $Config['runtime']['subscriptionId']
    $resourceGroupName = $Config['runtime']['resourceGroup']
    $automationAccountName = $Config['runtime']['automationAccountName']
    $runtimeEnvironmentName = $Config['runtime']['automationRuntimeEnvironmentName']

    foreach ($requiredValue in @($subscriptionId, $resourceGroupName, $automationAccountName, $runtimeEnvironmentName)) {
        if ([string]::IsNullOrWhiteSpace($requiredValue)) {
            throw 'The Guardrails Automation Runtime Environment settings are incomplete.'
        }
    }

    "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runtimeEnvironments/$runtimeEnvironmentName"
}

# Read the Runtime Environment currently attached to the Automation Account.
# Return null only when it does not exist; permission, network, and other Azure failures must stop deployment.
function Get-GSAAutomationRuntimeEnvironment {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]
        $Config
    )

    $runtimePath = Get-GSAAutomationRuntimeBasePath -Config $Config
    try {
        $response = Invoke-AzRestMethod -Method GET -Path "${runtimePath}?api-version=$script:AutomationApiVersion" -ErrorAction Stop
    }
    catch {
        # Az modules can expose a missing resource as an exception rather than a normal 404 response.
        $statusCode = $null
        if ($null -ne $_.Exception.Response -and $null -ne $_.Exception.Response.StatusCode) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }

        if ($statusCode -eq 404) {
            return $null
        }

        throw "Could not read the Guardrails Automation Runtime Environment. $($_.Exception.Message)"
    }

    # Validate responses returned normally as well as exceptions handled above.
    if ([int]$response.StatusCode -eq 404) {
        return $null
    }
    if ([int]$response.StatusCode -lt 200 -or [int]$response.StatusCode -ge 300) {
        throw "Could not read the Guardrails Automation Runtime Environment. Azure returned HTTP $($response.StatusCode)."
    }
    if ([string]::IsNullOrWhiteSpace($response.Content)) {
        throw 'Azure returned an empty response while reading the Guardrails Automation Runtime Environment.'
    }

    # Return a PowerShell object so callers can inspect the runtime language, version, and default Az module.
    $response.Content | ConvertFrom-Json -Depth 20
}

# Stop deployment unless the expected named environment exists and uses the configured PowerShell version.
function Assert-GSAAutomationRuntimeEnvironment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]
        $Config
    )

    $runtimeEnvironment = Get-GSAAutomationRuntimeEnvironment -Config $Config
    $runtimeEnvironmentName = $Config['runtime']['automationRuntimeEnvironmentName']
    $expectedVersion = $Config['runtime']['automationRuntimeVersion']
    $automationAccountName = $Config['runtime']['automationAccountName']

    if ($null -eq $runtimeEnvironment) {
        throw "Required PowerShell $expectedVersion Runtime Environment '$runtimeEnvironmentName' was not found in Automation Account '$automationAccountName'."
    }

    # A same-named environment is not sufficient; its language and version must match what Guardrails will run.
    $actualLanguage = $runtimeEnvironment.properties.runtime.language
    $actualVersion = $runtimeEnvironment.properties.runtime.version
    if ($actualLanguage -ne 'PowerShell' -or $actualVersion -ne $expectedVersion) {
        throw "Automation Runtime Environment '$runtimeEnvironmentName' uses '$actualLanguage $actualVersion'; Guardrails requires PowerShell $expectedVersion."
    }
}

# JSON selects the modules to install; each Guardrails source manifest owns its version.
# The installer resolves and validates this list before Azure resources change.
function Get-GSAExpectedAutomationRuntimeModules {
    [CmdletBinding()]
    param (
        [string]
        $RepositoryRoot = (Join-Path $PSScriptRoot '../../../..')
    )

    # ZIP APIs use the process directory, which can differ from PowerShell's current location.
    $RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot -ErrorAction Stop).ProviderPath
    $manifestPath = Join-Path $RepositoryRoot 'setup/automation-runtime-modules.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "The Guardrails Runtime Environment module manifest was not found at '$manifestPath'."
    }

    # Parse the complete file as JSON so formatting and line breaks do not affect the result.
    try {
        $modules = @(Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -Depth 20 -ErrorAction Stop)
    }
    catch {
        throw "Could not read the Guardrails Runtime Environment module manifest. $($_.Exception.Message)"
    }

    $invalidModules = @($modules | Where-Object { $_.name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' })
    $duplicateNames = @($modules | Group-Object -Property name | Where-Object { $_.Count -gt 1 })
    if ($modules.Count -eq 0 -or $invalidModules.Count -gt 0 -or $duplicateNames.Count -gt 0) {
        throw 'The Guardrails Runtime Environment module manifest must contain a non-empty list of unique, valid module names.'
    }

    # Index source manifests once, but resolve only names explicitly listed in JSON.
    # Duplicate source names are ambiguous even when they appear in different folders.
    $sourceManifests = @(Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'src') -Filter '*.psd1' -Recurse -File -ErrorAction Stop)
    $manifestsByName = $sourceManifests | Group-Object -Property BaseName -AsHashTable -AsString
    if ($null -eq $manifestsByName) { $manifestsByName = @{} }
    $resolvedModules = [System.Collections.Generic.List[object]]::new()
    foreach ($module in $modules) {
        $name = [string]$module.name
        if ($module.PSObject.Properties.Name -contains 'uri') {
            # External modules have no source manifest here, so their version and HTTPS URL stay in JSON.
            $uri = $null
            if (-not [Uri]::TryCreate([string]$module.uri, [UriKind]::Absolute, [ref]$uri) -or
                $uri.Scheme -ne 'https' -or -not ([string]$module.version -as [version])) {
                throw "External module '$name' requires a valid version and an HTTPS download URL."
            }
            $resolvedModules.Add(@{ name = $name; version = [string]$module.version; uri = [string]$module.uri })
            continue
        }

        if ($module.PSObject.Properties.Name -contains 'version') {
            throw "Guardrails module '$name' must declare its version only in its source .psd1, not in automation-runtime-modules.json."
        }
        $matchingManifests = @($manifestsByName[$name] | Where-Object { $null -ne $_ })
        if ($matchingManifests.Count -ne 1) {
            throw "Runtime module '$name' must have exactly one matching source manifest under src; found $($matchingManifests.Count)."
        }
        $sourceManifest = Import-PowerShellDataFile -LiteralPath $matchingManifests[0].FullName -ErrorAction Stop
        $version = [string]$sourceManifest.ModuleVersion
        if (-not ($version -as [version])) {
            throw "Runtime module '$name' has an invalid ModuleVersion in its source manifest."
        }

        # A source version is deployable only when its ZIP has been rebuilt with the same version.
        # Read the manifest as data, without importing or executing code from the archive.
        $zipPath = Join-Path $RepositoryRoot "psmodules/$name.zip"
        $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $entries = @($archive.Entries | Where-Object { $_.Name -eq "$name.psd1" })
            if ($entries.Count -ne 1) {
                throw "Runtime module '$name' must have exactly one matching manifest in its deployment ZIP."
            }
            $reader = [System.IO.StreamReader]::new($entries[0].Open())
            try { $content = $reader.ReadToEnd() }
            finally { $reader.Dispose() }
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$null, [ref]$parseErrors)
            $dataAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $false)
            if ($parseErrors.Count -gt 0 -or $null -eq $dataAst) {
                throw "Runtime module '$name' has an invalid manifest in its deployment ZIP."
            }
            $zipManifest = $dataAst.SafeGetValue()
            if ([string]$zipManifest.ModuleVersion -ne $version) {
                throw "Runtime module '$name' source is version $version, but its ZIP contains version $($zipManifest.ModuleVersion). Rebuild the ZIP before deployment."
            }
        }
        finally { $archive.Dispose() }
        $resolvedModules.Add(@{ name = $name; version = $version })
    }

    # Return only after every entry passes validation, so callers cannot deploy a partial list.
    $resolvedModules.ToArray()
}

# Read every PowerShell module Azure currently reports for the Guardrails Runtime Environment.
function Get-GSAAutomationRuntimeModules {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]
        $Config
    )

    $runtimePath = Get-GSAAutomationRuntimeBasePath -Config $Config
    # Azure names this REST collection "packages", although each entry is a PowerShell module.
    $nextPage = "${runtimePath}/packages?api-version=$script:AutomationApiVersion"
    $modules = [System.Collections.Generic.List[object]]::new()

    # Azure may split the module list across several responses. Read every page before deciding it is ready.
    while (-not [string]::IsNullOrWhiteSpace($nextPage)) {
        # The first request uses a resource path; Azure may return later page links as complete URLs.
        if ([Uri]::IsWellFormedUriString($nextPage, [UriKind]::Absolute)) {
            $response = Invoke-AzRestMethod -Method GET -Uri $nextPage -ErrorAction Stop
        }
        else {
            $response = Invoke-AzRestMethod -Method GET -Path $nextPage -ErrorAction Stop
        }

        # Do not treat an error or empty page as an empty module list; that could publish unusable runbooks.
        if ([int]$response.StatusCode -lt 200 -or [int]$response.StatusCode -ge 300) {
            throw "Could not read modules from the Guardrails Automation Runtime Environment. Azure returned HTTP $($response.StatusCode)."
        }
        if ([string]::IsNullOrWhiteSpace($response.Content)) {
            throw 'Azure returned an empty response while reading modules from the Guardrails Automation Runtime Environment.'
        }

        # Add this page to one complete list, then follow Azure's next-page link when present.
        $page = $response.Content | ConvertFrom-Json -Depth 20 -ErrorAction Stop
        foreach ($module in @($page.value)) {
            $modules.Add($module)
        }
        $nextPage = $page.nextLink
    }

    $modules.ToArray()
}

# Wait until Azure has imported the exact module set required by Guardrails.
# This checks the default Az version plus every custom module's presence, state, and version.
function Wait-GSAAutomationRuntimeModules {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]
        $Config,

        # Use the same resolved list that was supplied to Bicep; do not read source versions again mid-deployment.
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object[]]
        $ExpectedModules,

        [Parameter(Mandatory = $false)]
        [int]
        $TimeoutMinutes = 30,

        [Parameter(Mandatory = $false)]
        [int]
        $PollIntervalSeconds = 15
    )

    # Confirm the PowerShell environment itself before waiting for modules that belong to it.
    Assert-GSAAutomationRuntimeEnvironment -Config $Config

    # The installer supplies custom module versions; configuration defines the Azure-managed default Az module.
    $expectedModuleNames = @($expectedModules.name)
    $expectedAzVersion = [string]$Config['runtime']['automationRuntimeAzVersion']
    if ([string]::IsNullOrWhiteSpace($expectedAzVersion)) {
        throw 'The required Az version is missing from the Guardrails Automation Runtime Environment settings.'
    }

    # Preserve the most recent state so a timeout can name every item that is still not ready.
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $missingModuleNames = @()
    $pendingModules = @()
    $moduleVersionMismatches = @()
    $actualAzVersion = $null
    $azVersionReady = $false
    Write-Host "Waiting for $($expectedModules.Count) Guardrails PowerShell modules and Az $expectedAzVersion to become ready (up to $TimeoutMinutes minutes)..."

    # Module imports are asynchronous. Read fresh Azure state on every pass until all checks agree.
    while ($true) {
        $runtimeEnvironment = Get-GSAAutomationRuntimeEnvironment -Config $Config
        if ($null -eq $runtimeEnvironment) {
            throw 'The Guardrails Automation Runtime Environment disappeared while its modules were being checked.'
        }
        # Azure stores the default Az module in defaultPackages rather than in the custom module list.
        $actualAzVersion = [string]$runtimeEnvironment.properties.defaultPackages.Az
        $azVersionReady = $actualAzVersion -eq $expectedAzVersion

        # Index modules by name so each expected entry can be compared with Azure's current entry.
        $modules = @(Get-GSAAutomationRuntimeModules -Config $Config)
        $modulesByName = @{}
        foreach ($module in $modules) {
            $modulesByName[[string]$module.name] = $module
        }

        # Ignore unrelated/default packages. Az is checked separately, and this deployment owns only manifest modules.
        $missingModuleNames = @($expectedModuleNames | Where-Object { -not $modulesByName.ContainsKey($_) })
        $managedModules = @(
            foreach ($moduleName in $expectedModuleNames) {
                if ($modulesByName.ContainsKey($moduleName)) {
                    $modulesByName[$moduleName]
                }
            }
        )

        # A failed Guardrails module import cannot recover by waiting, so stop with Azure's error details.
        $failedModules = @($managedModules | Where-Object { $_.properties.provisioningState -in @('Failed', 'Canceled', 'Cancelled') })
        if ($failedModules.Count -gt 0) {
            $failureDetails = $failedModules | ForEach-Object {
                $message = $_.properties.error.message
                if ([string]::IsNullOrWhiteSpace($message)) {
                    $message = $_.properties.provisioningState
                }
                "$($_.name): $message"
            }
            throw "One or more Guardrails Runtime Environment modules failed to import: $($failureDetails -join '; ')"
        }

        $pendingModules = @($managedModules | Where-Object { $_.properties.provisioningState -ne 'Succeeded' })
        # An update can briefly report the old successful module while the replacement becomes visible.
        # Keep polling until each successful module reports the exact version supplied to Bicep.
        $moduleVersionMismatches = @(
            foreach ($expectedModule in $expectedModules) {
                $moduleName = [string]$expectedModule.name
                if (-not $modulesByName.ContainsKey($moduleName)) {
                    continue
                }

                $actualModule = $modulesByName[$moduleName]
                if ($actualModule.properties.provisioningState -eq 'Succeeded') {
                    $actualVersion = [string]$actualModule.properties.version
                    $expectedVersion = [string]$expectedModule.version
                    if ($actualVersion -ne $expectedVersion) {
                        $reportedVersion = if ([string]::IsNullOrWhiteSpace($actualVersion)) { 'not reported' } else { $actualVersion }
                        "$moduleName (expected $expectedVersion, found $reportedVersion)"
                    }
                }
            }
        )

        # Runbooks are safe to publish only when nothing is missing, importing, stale, or on the wrong Az version.
        if ($missingModuleNames.Count -eq 0 -and $pendingModules.Count -eq 0 -and
            $moduleVersionMismatches.Count -eq 0 -and $azVersionReady) {
            Write-Verbose "All $($expectedModules.Count) Guardrails Runtime Environment modules and Az $expectedAzVersion are ready."
            Write-Host "All Guardrails PowerShell modules and Az $expectedAzVersion are ready." -ForegroundColor Green
            return
        }

        # Report progress without treating normal Azure provisioning time as an error.
        $azVersionStatus = if ($azVersionReady) { 'ready' } else { "waiting for $expectedAzVersion (currently '$actualAzVersion')" }
        Write-Verbose "Waiting for $($pendingModules.Count) module import(s), $($missingModuleNames.Count) module registration(s), and $($moduleVersionMismatches.Count) module version update(s). Az is $azVersionStatus."

        $currentTime = Get-Date
        if ($currentTime -ge $deadline) {
            break
        }

        # Do not sleep past the deadline by a full poll interval. The loop performs one final read after this delay.
        $remainingSeconds = [int][Math]::Ceiling(($deadline - $currentTime).TotalSeconds)
        $sleepSeconds = [Math]::Min($PollIntervalSeconds, $remainingSeconds)
        Start-Sleep -Seconds $sleepSeconds
    }

    # If time runs out, build one actionable list of missing, pending, and wrong-version modules.
    $details = @(
        foreach ($moduleName in $missingModuleNames) {
            "$moduleName (missing)"
        }
        foreach ($module in $pendingModules) {
            "$($module.name) ($($module.properties.provisioningState))"
        }
        $moduleVersionMismatches
        if (-not $azVersionReady) {
            $reportedAzVersion = if ([string]::IsNullOrWhiteSpace($actualAzVersion)) { 'not reported' } else { $actualAzVersion }
            "Az (expected $expectedAzVersion, found $reportedAzVersion)"
        }
    ) | Sort-Object -Unique
    throw "Timed out after $TimeoutMinutes minutes waiting for Guardrails Runtime Environment modules to finish importing. Not ready: $($details -join ', ')."
}

# Get the secure Azure Resource Manager token needed for direct runbook-content and operation-status requests.
function Get-GSAResourceManagerAccessToken {
    $context = Get-AzContext -ErrorAction Stop
    $resourceManagerUrl = $context.Environment.ResourceManagerUrl
    if ([string]::IsNullOrWhiteSpace($resourceManagerUrl)) {
        throw 'The current Azure context does not provide a Resource Manager endpoint.'
    }

    # Linking runbooks to PowerShell 7.6 requires the direct ARM requests used later in this module.
    # Keep their ARM token as a SecureString; ErrorAction Stop prevents uploads from continuing without valid authentication.
    $token = (Get-AzAccessToken -ResourceUrl $resourceManagerUrl -AsSecureString -ErrorAction Stop).Token
    if ($token -isnot [securestring]) {
        throw 'Az.Accounts did not return a secure Resource Manager access token. Update Az.Accounts and try again.'
    }

    # Return the endpoint with the token so callers use the correct URL for public or sovereign Azure clouds.
    @{
        ResourceManagerUrl = $resourceManagerUrl.TrimEnd('/')
        Token = $token
    }
}

# The direct runbook API required for the 7.6 link can complete asynchronously and return operation details in headers.
# Read a header across the different object types that PowerShell HTTP commands can return.
function Get-GSAResponseHeaderValue {
    param (
        [Parameter(Mandatory = $false)]
        [object]
        $Headers,

        [Parameter(Mandatory = $true)]
        [string]
        $Name
    )

    if ($null -eq $Headers) {
        return $null
    }

    # Invoke-RestMethod commonly returns a dictionary when ResponseHeadersVariable is used.
    if ($Headers -is [System.Collections.IDictionary] -and $Headers.ContainsKey($Name)) {
        return [string]@($Headers[$Name])[0]
    }

    # .NET HttpResponseHeaders exposes values through GetValues instead of dictionary indexing.
    $value = $null
    try {
        $value = @($Headers.GetValues($Name))[0]
    }
    catch {
        # HttpResponseHeaders throws when a header is absent. The caller can try another header.
        $value = $null
    }
    if (-not [string]::IsNullOrWhiteSpace($value)) {
        return [string]$value
    }

    # Some PowerShell callers provide a normal object whose properties are the header names.
    $property = $Headers.PSObject.Properties[$Name]
    if ($null -ne $property) {
        return [string]@($property.Value)[0]
    }

    $null
}

# The direct runbook API used to attach PowerShell 7.6 can return HTTP 202, which means accepted but not yet finished.
# Requests completed synchronously need no polling and return immediately.
function Wait-GSAAzureOperation {
    param (
        [Parameter(Mandatory = $true)]
        [int]
        $StatusCode,

        [Parameter(Mandatory = $false)]
        [object]
        $Headers,

        [Parameter(Mandatory = $true)]
        [hashtable]
        $ArmAccess,

        [Parameter(Mandatory = $true)]
        [string]
        $Description,

        [Parameter(Mandatory = $false)]
        [int]
        $TimeoutMinutes = 5
    )

    if ($StatusCode -ne 202) {
        return
    }

    # Azure may accept a draft upload or publish request before it finishes. Follow its operation URL
    # so the installer cannot publish or start a runbook while Azure still has the previous content.
    $operationUri = Get-GSAResponseHeaderValue -Headers $Headers -Name 'Azure-AsyncOperation'
    if ([string]::IsNullOrWhiteSpace($operationUri)) {
        $operationUri = Get-GSAResponseHeaderValue -Headers $Headers -Name 'Location'
    }
    if ([string]::IsNullOrWhiteSpace($operationUri)) {
        throw "Azure accepted $Description but did not return an operation URL to confirm completion."
    }
    if ($operationUri -notmatch '^https://') {
        $operationUri = "$($ArmAccess.ResourceManagerUrl)/$($operationUri.TrimStart('/'))"
    }

    # Respect Azure's requested delay where possible, while keeping each pause between one and thirty seconds.
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $retryAfter = Get-GSAResponseHeaderValue -Headers $Headers -Name 'Retry-After'
    Write-Host "Waiting for Azure to finish $Description (up to $TimeoutMinutes minutes)..."
    do {
        $delaySeconds = 2
        if ($retryAfter -match '^\d+$') {
            $delaySeconds = [Math]::Min([Math]::Max([int]$retryAfter, 1), 30)
        }
        Start-Sleep -Seconds $delaySeconds

        $pollHeaders = $null
        $pollStatusCode = $null
        # Keep the 7.6 runbook-linking request on the secure token path while checking Azure's operation status.
        # PowerShell builds the bearer authorization header without exposing the token as plain text.
        $operation = Invoke-RestMethod -Method GET -Uri $operationUri -Authentication Bearer -Token $ArmAccess.Token `
            -ResponseHeadersVariable pollHeaders -StatusCodeVariable pollStatusCode -ErrorAction Stop

        # Azure can report a terminal failure in the response body even when the status request itself succeeded.
        $operationStatus = $operation.status
        if ($operationStatus -in @('Failed', 'Canceled', 'Cancelled')) {
            $errorMessage = $operation.error.message
            if ([string]::IsNullOrWhiteSpace($errorMessage)) {
                $errorMessage = $operationStatus
            }
            throw "Azure could not complete ${Description}: $errorMessage"
        }

        # Azure operation endpoints are not fully uniform: success may be in the body or implied by a non-202 response.
        if ([int]$pollStatusCode -ne 202 -and ([string]::IsNullOrWhiteSpace($operationStatus) -or $operationStatus -eq 'Succeeded')) {
            Write-Host "Azure finished $Description." -ForegroundColor Green
            return
        }


        $retryAfter = Get-GSAResponseHeaderValue -Headers $pollHeaders -Name 'Retry-After'
    } while ((Get-Date) -lt $deadline)

    throw "Timed out after $TimeoutMinutes minutes waiting for Azure to complete $Description."
}

# Create or update one runbook, link it to the named Runtime Environment, upload its script, and publish it.
# Do not return until Azure confirms both the Published state and the expected Runtime Environment link.
function Set-GSAAutomationRunbook {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]
        $Config,

        [Parameter(Mandatory = $true)]
        [string]
        $Name,

        [Parameter(Mandatory = $true)]
        [string]
        $Path,

        [Parameter(Mandatory = $true)]
        [string]
        $Description,

        [Parameter(Mandatory = $true)]
        [hashtable]
        $Tags
    )

    # Check locally before changing Azure so a missing script cannot leave behind an empty runbook.
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Runbook file '$Path' was not found."
    }

    # Build the exact Azure path for this runbook from the validated deployment configuration.
    $runtimeEnvironmentName = $Config['runtime']['automationRuntimeEnvironmentName']
    $automationAccountName = $Config['runtime']['automationAccountName']
    $resourceGroupName = $Config['runtime']['resourceGroup']
    $subscriptionId = $Config['runtime']['subscriptionId']
    $runbookPath = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runbooks/$Name"

    # The current Az.Automation import cmdlet cannot attach a named Runtime Environment, so use the supported REST contract.
    # runtimeEnvironment is the link that makes this runbook and each of its jobs use Guardrails PowerShell 7.6 modules.
    $runbookPayload = @{
        name = $Name
        location = $Config.region
        properties = @{
            description = $Description
            draft = @{}
            logProgress = $false
            logVerbose = $false
            runbookType = 'PowerShell'
            runtimeEnvironment = $runtimeEnvironmentName
        }
        tags = $Tags
    } | ConvertTo-Json -Depth 10 -Compress

    # Create or update the runbook metadata and its Runtime Environment link before uploading script content.
    $createResponse = Invoke-AzRestMethod -Method PUT -Path "${runbookPath}?api-version=$script:AutomationApiVersion" -Payload $runbookPayload -ErrorAction Stop
    if ([int]$createResponse.StatusCode -lt 200 -or [int]$createResponse.StatusCode -ge 300) {
        throw "Azure returned HTTP $($createResponse.StatusCode) while creating or updating runbook '$Name'."
    }

    # Draft content is plain text, so send it directly instead of allowing a JSON REST helper to alter it.
    $armAccess = Get-GSAResourceManagerAccessToken
    $runbookContent = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path)
    $draftContentUri = "$($armAccess.ResourceManagerUrl)${runbookPath}/draft/content?api-version=$script:AutomationApiVersion"
    $draftResponseHeaders = $null
    $draftStatusCode = $null
    # This direct upload is part of publishing the runbook with its PowerShell 7.6 environment link.
    # Send the script as plain text while PowerShell safely adds the bearer header from the secure ARM token.
    Write-Host "Uploading content for runbook '$Name'..."
    Invoke-RestMethod -Method PUT -Uri $draftContentUri -Authentication Bearer -Token $armAccess.Token -ContentType 'text/plain; charset=utf-8' `
        -Body $runbookContent -ResponseHeadersVariable draftResponseHeaders -StatusCodeVariable draftStatusCode -ErrorAction Stop | Out-Null
    Wait-GSAAzureOperation -StatusCode $draftStatusCode -Headers $draftResponseHeaders -ArmAccess $armAccess -Description "uploading runbook '$Name' content"

    # Publishing promotes the uploaded draft so schedules and manual starts run the new script.
    Write-Host "Publishing runbook '$Name'..."
    $publishResponse = Invoke-AzRestMethod -Method POST -Path "${runbookPath}/publish?api-version=$script:AutomationApiVersion" -ErrorAction Stop
    if ([int]$publishResponse.StatusCode -lt 200 -or [int]$publishResponse.StatusCode -ge 300) {
        throw "Azure returned HTTP $($publishResponse.StatusCode) while publishing runbook '$Name'."
    }
    Wait-GSAAzureOperation -StatusCode $publishResponse.StatusCode -Headers $publishResponse.Headers -ArmAccess $armAccess -Description "publishing runbook '$Name'"

    # Operation completion alone is not enough. Re-read the runbook until Azure exposes the final state and link.
    $publishDeadline = (Get-Date).AddMinutes(5)
    Write-Host "Confirming runbook '$Name' is published and linked to Runtime Environment '$runtimeEnvironmentName' (up to 5 minutes)..."
    while ($true) {
        $runbookResponse = Invoke-AzRestMethod -Method GET -Path "${runbookPath}?api-version=$script:AutomationApiVersion" -ErrorAction Stop
        if ([int]$runbookResponse.StatusCode -lt 200 -or [int]$runbookResponse.StatusCode -ge 300) {
            throw "Azure returned HTTP $($runbookResponse.StatusCode) while confirming runbook '$Name'."
        }
        $runbook = $runbookResponse.Content | ConvertFrom-Json -Depth 20
        if ($runbook.properties.state -eq 'Published' -and $runbook.properties.runtimeEnvironment -eq $runtimeEnvironmentName) {
            Write-Verbose "Runbook '$Name' is published and linked to Runtime Environment '$runtimeEnvironmentName'."
            Write-Host "Runbook '$Name' is published and linked to Runtime Environment '$runtimeEnvironmentName'." -ForegroundColor Green
            return
        }


        $currentTime = Get-Date
        if ($currentTime -ge $publishDeadline) {
            break
        }

        # Sleep only for the time still available, then perform one final Azure read before timing out.
        $remainingSeconds = [int][Math]::Ceiling(($publishDeadline - $currentTime).TotalSeconds)
        Start-Sleep -Seconds ([Math]::Min(5, $remainingSeconds))
    }

    throw "Runbook '$Name' was not published with Runtime Environment '$runtimeEnvironmentName' within 5 minutes."
}

# Export the deployment functions; keep REST helpers private.
Export-ModuleMember -Function @(
    'Get-GSAExpectedAutomationRuntimeModules'
    'Assert-GSAAutomationRuntimeEnvironment'
    'Wait-GSAAutomationRuntimeModules'
    'Set-GSAAutomationRunbook'
)
