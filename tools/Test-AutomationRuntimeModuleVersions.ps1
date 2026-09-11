[CmdletBinding()]
param ([string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent))

# Run without Azure credentials or a separate test framework. Fixtures stay in a temporary directory.
$ErrorActionPreference = 'Stop'
$helperPath = Join-Path $RepositoryRoot 'src/GuardrailsSolutionAcceleratorSetup/modules/Manage-GSAAutomationRuntime/Manage-GSAAutomationRuntime.psd1'
$runtimeHelper = Import-Module $helperPath -Force -PassThru
$fixture = Join-Path ([IO.Path]::GetTempPath()) "guardrails-module-tests-$([Guid]::NewGuid())"
$script:assertions = 0

function Assert-Condition ([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:assertions++
}

function Assert-Failure ([scriptblock]$Action, [string]$Pattern) {
    try { & $Action | Out-Null }
    catch {
        Assert-Condition ($_.Exception.Message -like $Pattern) "Unexpected failure: $($_.Exception.Message)"
        return
    }
    throw "Expected failure matching '$Pattern'."
}

function New-Fixture (
    [string]$SourceVersion = '1.2.3',
    [string]$ZipVersion = '1.2.3',
    [AllowEmptyCollection()][object[]]$Inventory = @(
        @{ name = 'Test.Module' },
        @{ name = 'Az.Marketplace'; version = '0.3.0'; uri = 'https://example.com/az.marketplace.nupkg' }
    )
) {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
    foreach ($directory in @('setup', 'src/Test.Module', 'psmodules')) {
        New-Item -ItemType Directory -Path (Join-Path $fixture $directory) -Force | Out-Null
    }
    ConvertTo-Json -InputObject $Inventory -Depth 10 | Set-Content (Join-Path $fixture 'setup/automation-runtime-modules.json')
    "@{ RootModule = 'Test.Module.psm1'; ModuleVersion = '$SourceVersion' }" |
        Set-Content (Join-Path $fixture 'src/Test.Module/Test.Module.psd1')
    '# Test fixture' | Set-Content (Join-Path $fixture 'src/Test.Module/Test.Module.psm1')
    $zip = [IO.Compression.ZipFile]::Open((Join-Path $fixture 'psmodules/Test.Module.zip'), [IO.Compression.ZipArchiveMode]::Create)
    try {
        $writer = [IO.StreamWriter]::new($zip.CreateEntry('Test.Module.psd1').Open())
        try { $writer.Write("@{ RootModule = 'Test.Module.psm1'; ModuleVersion = '$ZipVersion' }") }
        finally { $writer.Dispose() }
    }
    finally { $zip.Dispose() }
}

try {
    # The real repository must still resolve the explicit inventory and every released ZIP.
    $actual = @(Get-GSAExpectedAutomationRuntimeModules -RepositoryRoot $RepositoryRoot)
    $inventory = @(Get-Content (Join-Path $RepositoryRoot 'setup/automation-runtime-modules.json') -Raw | ConvertFrom-Json)
    Assert-Condition ($actual.Count -eq $inventory.Count) 'The resolved list lost an installation entry.'
    Assert-Condition (($actual.name -join ',') -eq ($inventory.name -join ',')) 'The reader changed module selection or order.'

    New-Fixture
    $resolved = @(Get-GSAExpectedAutomationRuntimeModules -RepositoryRoot $fixture)
    Assert-Condition ($resolved[0].version -eq '1.2.3') 'Source version was not resolved.'
    Assert-Condition ($resolved[1].version -eq '0.3.0' -and $resolved[1].uri -eq 'https://example.com/az.marketplace.nupkg') 'External metadata was not preserved.'
    Push-Location $fixture
    try {
        $relative = @(Get-GSAExpectedAutomationRuntimeModules -RepositoryRoot '.')
        Assert-Condition ($relative[0].version -eq '1.2.3') 'Relative repository paths did not resolve correctly.'
    }
    finally { Pop-Location }

    New-Fixture -SourceVersion '1.2.4'
    Assert-Failure { Get-GSAExpectedAutomationRuntimeModules -RepositoryRoot $fixture } '*Rebuild the ZIP*'
    Assert-Condition ($resolved[0].version -eq '1.2.3') 'An already resolved deployment list changed.'
    New-Fixture -SourceVersion '1.2.4' -ZipVersion '1.2.4'
    $updated = @(Get-GSAExpectedAutomationRuntimeModules -RepositoryRoot $fixture)
    Assert-Condition ($updated[0].version -eq '1.2.4') 'A source-only version change and rebuilt ZIP were not picked up.'

    # Invalid configuration must fail before the reader returns any deployable entries.
    $badInventories = @(
        @{ Entries = @(); Pattern = '*non-empty list*' },
        @{ Entries = @(@{ name = '' }); Pattern = '*valid module names*' },
        @{ Entries = @(@{ name = '../Test.Module' }); Pattern = '*valid module names*' },
        @{ Entries = @(@{ name = 'Test.Module' }, @{ name = 'test.module' }); Pattern = '*unique*' },
        @{ Entries = @(@{ name = 'Missing.Module' }); Pattern = '*exactly one matching source*' },
        @{ Entries = @(@{ name = 'Test.Module'; version = '1.2.3' }); Pattern = '*only in its source .psd1*' },
        @{ Entries = @(@{ name = 'External'; version = '1.0.0'; uri = 'http://example.com/module.zip' }); Pattern = '*HTTPS*' },
        @{ Entries = @(@{ name = 'External'; uri = 'https://example.com/module.zip' }); Pattern = '*valid version*' }
    )
    foreach ($case in $badInventories) {
        New-Fixture -Inventory $case.Entries
        Assert-Failure { Get-GSAExpectedAutomationRuntimeModules -RepositoryRoot $fixture } $case.Pattern
    }
    New-Fixture -SourceVersion 'invalid'
    Assert-Failure { Get-GSAExpectedAutomationRuntimeModules -RepositoryRoot $fixture } '*invalid ModuleVersion*'
    New-Fixture
    Copy-Item (Join-Path $fixture 'src/Test.Module/Test.Module.psd1') (Join-Path $fixture 'src/Test.Module.psd1')
    Assert-Failure { Get-GSAExpectedAutomationRuntimeModules -RepositoryRoot $fixture } '*found 2*'
    New-Fixture
    Remove-Item (Join-Path $fixture 'src/Test.Module/Test.Module.psd1')
    Assert-Failure { Get-GSAExpectedAutomationRuntimeModules -RepositoryRoot $fixture } '*source manifest*'
    New-Fixture
    Remove-Item (Join-Path $fixture 'psmodules/Test.Module.zip')
    Assert-Failure { Get-GSAExpectedAutomationRuntimeModules -RepositoryRoot $fixture } '*Test.Module.zip*'
    New-Fixture
    'not a zip' | Set-Content (Join-Path $fixture 'psmodules/Test.Module.zip')
    Assert-Failure { Get-GSAExpectedAutomationRuntimeModules -RepositoryRoot $fixture } '*'
    New-Fixture
    '{' | Set-Content (Join-Path $fixture 'setup/automation-runtime-modules.json')
    Assert-Failure { Get-GSAExpectedAutomationRuntimeModules -RepositoryRoot $fixture } '*Could not read*'

    # Execute the real installer and parameter-builder functions with Azure operations replaced by local stubs.
    # Loading only these function declarations avoids importing Azure-dependent setup modules in CI.
    $deployPath = Join-Path $RepositoryRoot 'src/GuardrailsSolutionAcceleratorSetup/modules/Deploy-GuardrailsSolutionAccelerator/Deploy-GuardrailsSolutionAccelerator.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($deployPath, [ref]$null, [ref]$null)
    $definitions = $ast.FindAll({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -in @('Deploy-GuardrailsSolutionAccelerator', 'New-GSACoreResourceDeploymentParamObject')
    }, $false)
    $testModule = New-Module -ArgumentList $definitions, $runtimeHelper, $fixture -ScriptBlock {
        param ($Definitions, $Helper, $FixtureRoot)
        foreach ($definition in $Definitions) { . ([scriptblock]::Create($definition.Extent.Text)) }
        $script:helper = $Helper
        $script:fixtureRoot = $FixtureRoot
        function Get-GSAExpectedAutomationRuntimeModules {
            $script:state.Reads++
            & $script:helper { param($root) Get-GSAExpectedAutomationRuntimeModules -RepositoryRoot $root } $script:fixtureRoot
        }
        function Confirm-GSAConfigurationParameters { @{ runtime = @{ tagsTable = @{} } } }
        function Get-AzContext { @{ Subscription = @{ Id = 'test-subscription' } } }
        function Show-GSADeploymentSummary {}
        function Confirm-GSAPrerequisites {}
        function Assert-GSAAutomationRuntimeEnvironment {}
        function Export-GSAConfigToKeyVault {}
        function Invoke-GSARunbooks {}
        function Remove-GSATemporaryDeployerBlobAccess {}
        function Update-GSAAutomationRunbooks {}
        function Get-AzOperationalInsightsSavedSearch { @{ Value = @() } }
        function Write-Host {}
        function Write-Warning {}
        function Read-Host {}
        function Invoke-RestMethod { @(@{ name = 'v9.8.7' }) }
        function Deploy-GSACoreResources { param($config, $paramObject) $script:state.Deployed = $paramObject }
        function Update-GSACoreResources { param($config, $paramObject) $script:state.Deployed = $paramObject }
        function Add-GSAAutomationRunbooks { param($config, $RuntimeModules) $script:state.Waited = $RuntimeModules }
        function Wait-GSAAutomationRuntimeModules { param($Config, $ExpectedModules) $script:state.Waited = $ExpectedModules }
        Export-ModuleMember -Function @()
    }

    foreach ($mode in @('Fresh', 'Modules', 'Core', 'Workbook', 'Runbooks', 'All', 'Release')) {
        New-Fixture
        $state = & $testModule {
            param ($Mode)
            $script:state = @{ Reads = 0; Deployed = $null; Waited = @() }
            $arguments = @{ configString = '{}'; alternatePSModulesURL = 'https://test.blob.core.windows.net/psmodules'; yes = $true }
            switch ($Mode) {
                'Modules' { $arguments.update = $true; $arguments.componentsToUpdate = @('GuardrailPowerShellModules') }
                'Core' { $arguments.update = $true; $arguments.componentsToUpdate = @('CoreComponents') }
                'Workbook' { $arguments.update = $true; $arguments.componentsToUpdate = @('Workbook') }
                'Runbooks' { $arguments.update = $true; $arguments.componentsToUpdate = @('AutomationAccountRunbooks') }
                'All' { $arguments.update = $true }
                'Release' { $arguments.Remove('alternatePSModulesURL'); $arguments.releaseVersion = 'v9.8.7' }
            }
            Deploy-GuardrailsSolutionAccelerator @arguments | Out-Null
            $script:state
        } $mode
        $changesModules = $mode -in @('Fresh', 'Modules', 'All', 'Release')
        Assert-Condition ($state.Reads -eq [int]$changesModules) "$mode resolved versions an unexpected number of times."
        Assert-Condition ($state.Waited.Count -eq $(if ($changesModules) { 2 } else { 0 })) "$mode waited for the wrong module set."
        if ($changesModules) {
            Assert-Condition ([object]::ReferenceEquals($state.Deployed.guardrailsRuntimeModules, $state.Waited)) "$mode did not pass the same list to Bicep and readiness checks."
            Assert-Condition ($state.Deployed.guardrailsRuntimeModules[0].version -eq '1.2.3') "$mode deployed the wrong source version."
            $expectedUrl = if ($mode -eq 'Release') { 'https://github.com/ssc-spc-ccoe-cei/azure-guardrails-solution-accelerator/raw/v9.8.7/psmodules' } else { 'https://test.blob.core.windows.net/psmodules' }
            Assert-Condition ($state.Deployed.ModuleBaseURL -eq $expectedUrl) "$mode changed the selected module download source."
        }
        elseif ($null -ne $state.Deployed) {
            Assert-Condition ($state.Deployed.guardrailsRuntimeModules.Count -eq 0) "$mode unexpectedly selected modules for installation."
        }
    }

    New-Fixture -SourceVersion '1.2.4'
    Assert-Failure {
        & $testModule {
            $script:state = @{ Reads = 0; Deployed = $null; Waited = @() }
            Deploy-GuardrailsSolutionAccelerator -configString '{}' -alternatePSModulesURL 'https://test.blob.core.windows.net/psmodules' -yes
        }
    } '*Rebuild the ZIP*'
    Assert-Condition (& $testModule { $null -eq $script:state.Deployed }) 'Invalid modules reached the resource deployment step.'

    # Exercise the actual readiness loop against a local Azure-shaped response. A stale ZIP on disk
    # must not change the already resolved list, and unrelated installed hotfix modules stay outside it.
    & $runtimeHelper {
        function script:Get-GSAAutomationRuntimeEnvironment {
            @{ properties = @{ runtime = @{ language = 'PowerShell'; version = '7.6' }; defaultPackages = @{ Az = '15.1.0' } } }
        }
        function script:Get-GSAAutomationRuntimeModules {
            @(
                @{ name = 'Test.Module'; properties = @{ version = '1.2.3'; provisioningState = 'Succeeded' } },
                @{ name = 'Client.Hotfix'; properties = @{ version = '9.0.0'; provisioningState = 'Succeeded' } }
            )
        }
        $config = @{ runtime = @{ automationRuntimeVersion = '7.6'; automationRuntimeAzVersion = '15.1.0' } }
        Wait-GSAAutomationRuntimeModules -Config $config -ExpectedModules @(@{ name = 'Test.Module'; version = '1.2.3' }) -TimeoutMinutes 0
    }
    $script:assertions++
    Assert-Failure {
        & $runtimeHelper {
            $config = @{ runtime = @{ automationRuntimeVersion = '7.6'; automationRuntimeAzVersion = '15.1.0' } }
            Wait-GSAAutomationRuntimeModules -Config $config -ExpectedModules @(@{ name = 'Test.Module'; version = '1.2.4' }) -TimeoutMinutes 0
        }
    } '*expected 1.2.4, found 1.2.3*'

    Microsoft.PowerShell.Utility\Write-Host "Passed $script:assertions runtime module regression assertions. No Azure resources were accessed."
}
finally {
    if ($null -ne $testModule) { Remove-Module $testModule }
    # Unload the helper so the fake Azure readers cannot leak into a later deployment in this session.
    if ($null -ne $runtimeHelper) { Remove-Module $runtimeHelper }
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}