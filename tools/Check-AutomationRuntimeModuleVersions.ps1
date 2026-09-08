[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]
    $RepositoryRoot = (Split-Path $PSScriptRoot -Parent)
)

$runtimeManifestPath = Join-Path $RepositoryRoot 'setup/automation-runtime-modules.json'
$sourceRoot = Join-Path $RepositoryRoot 'src'
$zipRoot = Join-Path $RepositoryRoot 'psmodules'

try {
    $runtimeModules = @(Get-Content -LiteralPath $runtimeManifestPath -Raw -ErrorAction Stop |
        ConvertFrom-Json -Depth 20 -ErrorAction Stop)
}
catch {
    throw "Could not read Runtime Environment module manifest '$runtimeManifestPath'. $($_.Exception.Message)"
}

# Index source manifests by module name. A duplicate name is ambiguous and must be fixed before deployment.
$sourceManifestsByName = @{}
foreach ($sourceManifest in Get-ChildItem -LiteralPath $sourceRoot -Filter '*.psd1' -Recurse -File) {
    $moduleName = $sourceManifest.BaseName
    if (-not $sourceManifestsByName.ContainsKey($moduleName)) {
        $sourceManifestsByName[$moduleName] = [System.Collections.Generic.List[object]]::new()
    }
    $sourceManifestsByName[$moduleName].Add($sourceManifest)
}

$errors = [System.Collections.Generic.List[string]]::new()
$duplicateRuntimeNames = @($runtimeModules | Group-Object -Property name | Where-Object Count -gt 1)
foreach ($duplicate in $duplicateRuntimeNames) {
    $errors.Add("Runtime module '$($duplicate.Name)' is listed more than once.")
}

$checkedModuleCount = 0
foreach ($runtimeModule in $runtimeModules) {
    $moduleName = [string]$runtimeModule.name
    $expectedVersion = [string]$runtimeModule.version

    if ([string]::IsNullOrWhiteSpace($moduleName) -or [string]::IsNullOrWhiteSpace($expectedVersion)) {
        $errors.Add('Every Runtime Environment module needs a non-empty name and version.')
        continue
    }

    # An explicit URI identifies an external module, such as Az.Marketplace, which has no Guardrails source manifest.
    if ($runtimeModule.PSObject.Properties.Name -contains 'uri') {
        continue
    }

    if (-not $sourceManifestsByName.ContainsKey($moduleName)) {
        $errors.Add("Runtime module '$moduleName' has no matching source manifest under src.")
        continue
    }

    $matchingManifests = @($sourceManifestsByName[$moduleName])
    if ($matchingManifests.Count -ne 1) {
        $paths = $matchingManifests.FullName -join ', '
        $errors.Add("Runtime module '$moduleName' matches more than one source manifest: $paths")
        continue
    }

    try {
        $sourceModule = Import-PowerShellDataFile -LiteralPath $matchingManifests[0].FullName -ErrorAction Stop
    }
    catch {
        $errors.Add("Could not read source manifest for '$moduleName'. $($_.Exception.Message)")
        continue
    }

    $sourceVersion = [string]$sourceModule.ModuleVersion
    if ($sourceVersion -ne $expectedVersion) {
        $errors.Add("Runtime module '$moduleName' expects version $expectedVersion, but its source manifest uses $sourceVersion.")
    }

    $zipPath = Join-Path $zipRoot "$moduleName.zip"
    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
        $errors.Add("Runtime module '$moduleName' is missing its deployment ZIP at '$zipPath'.")
    }

    $checkedModuleCount++
}

if ($errors.Count -gt 0) {
    throw "Runtime Environment module validation failed:`n - $($errors -join "`n - ")"
}

Write-Host "Validated $checkedModuleCount Guardrails Runtime Environment modules against their source manifests and deployment ZIPs."