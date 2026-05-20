[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]
    $configFilePath,

    # Optional. If omitted, the currently signed-in Az account is used (works in Azure Cloud Shell).
    [Parameter(Mandatory = $false)]
    [string]
    $userId = '',

    [Parameter(Mandatory = $false)]
    [string]
    $subscriptionId
)

$ErrorActionPreference = 'Stop'

# Run from the script's own folder so all relative paths (./tags.json, ./IaC/grfunc.bicep, ../*) resolve correctly,
# regardless of where the user invoked it from (Cloud Shell tends to launch from the home directory).
$scriptRoot = Split-Path -Parent $PSCommandPath
Push-Location $scriptRoot

try {
    $begin  = Get-Date
    $update = $false   # explicit; the deploy block runs only when this is false

    function Resolve-CentralViewIngestionServicePrincipalObjectId {
        param([string]$ApplicationId)
        if ([string]::IsNullOrWhiteSpace($ApplicationId)) { return '' }
        try {
            $sp = Get-AzADServicePrincipal -ApplicationId $ApplicationId -ErrorAction Stop
            return [string]$sp.Id
        }
        catch {
            Write-Warning "Could not resolve service principal object id for ApplicationId '$ApplicationId': $($_.Exception.Message)"
            return ''
        }
    }

    function Test-RoleAssignmentConflictIsBenign {
        param([System.Management.Automation.ErrorRecord]$ErrRecord)
        $parts = @(
            $ErrRecord.Exception.Message
            $ErrRecord.Exception.InnerException.Message
            "$($ErrRecord.Exception)"
        ) | Where-Object { $_ }
        $text = ($parts -join ' ')
        if ($text -match '(?i)(already exists|RoleAssignmentExists|Conflict|\b409\b|duplicate)') {
            return $true
        }
        try {
            $resp = $ErrRecord.Exception.Response
            if ($null -ne $resp -and [int]$resp.StatusCode -eq 409) { return $true }
        }
        catch {}
        return $false
    }

    function Convert-PlainTextToSecureString {
        param([string]$Value)

        # Required because Set-AzKeyVaultSecret expects SecureString.
        # Some values written here are operational identifiers, not credentials.
        return ConvertTo-SecureString $Value -AsPlainText -Force
    }

    function Test-BicepAvailable {
        if (Get-Command bicep -ErrorAction SilentlyContinue) { return $true }
        # Az PowerShell looks here on Windows when 'bicep' isn't on PATH
        $userBicep = Join-Path $env:USERPROFILE '.bicep\bicep.exe'
        if ($IsWindows -and (Test-Path $userBicep)) { return $true }
        # Cloud Shell PowerShell ships with bicep on PATH, so 'Get-Command' covers it.
        return $false
    }

    if (-not (Test-BicepAvailable)) {
        Write-Error @"
Bicep CLI is required by New-AzResourceGroupDeployment but was not found on PATH.

Quick installs:
  Windows (winget):   winget install -e --id Microsoft.Bicep
  Linux/WSL:          curl -Lo bicep https://github.com/Azure/bicep/releases/latest/download/bicep-linux-x64; chmod +x bicep; sudo mv bicep /usr/local/bin/bicep
  Azure Cloud Shell:  bicep is already preinstalled - if missing, run 'az bicep install' and re-open the shell.

After installing, close and re-open this shell so PATH is refreshed.
"@
        return
    }

    Write-Output "Reading config file '$configFilePath'."
    try {
        $config = Get-Content -Raw -Path $configFilePath | ConvertFrom-Json
    }
    catch {
        Write-Error "Error reading config file '$configFilePath'. $_"
        return
    }

    Write-Output "Loading tags from tags.json."
    try {
        $tagsRaw = Get-Content -Raw -Path './tags.json' | ConvertFrom-Json
        # tags.json may be a single object {} (preferred) or a legacy array [{}] - support both.
        $tags = if ($tagsRaw -is [System.Array]) { $tagsRaw[0] } else { $tagsRaw }
        $tagstable = @{}
        $tags.PSObject.Properties | ForEach-Object { $tagstable[$_.Name] = $_.Value }
        if ($tagstable.Count -eq 0) {
            Write-Error "tags.json contains no tag values. Populate the policy-required tags (e.g. CostCenter, DataSensitivity, ProjectContact, ProjectName, TechnicalContact) before rerunning."
            return
        }
    }
    catch {
        Write-Error "Error parsing tags.json. $_"
        return
    }

    # Sign in if there's no current Az context.
    $azContext = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $azContext) {
        Write-Output "No Az context detected, signing in..."
        Connect-AzAccount | Out-Null
        $azContext = Get-AzContext
    }

    # Resolve the running user (mandatory for KV admin assignment).
    if ([string]::IsNullOrWhiteSpace($userId)) {
        try { $currentUserId = (Get-AzADUser -SignedIn -ErrorAction Stop).Id } catch { $currentUserId = $null }
    }
    else {
        try { $currentUserId = (Get-AzADUser -UserPrincipalName $userId -ErrorAction Stop).Id } catch { $currentUserId = $null }
    }
    if (-not $currentUserId) {
        Write-Error "Could not resolve current user. Pass -userId 'name@tenant.onmicrosoft.com' or run 'Connect-AzAccount' first."
        return
    }

    # Subscription selection
    if (-not [string]::IsNullOrWhiteSpace($subscriptionId)) {
        Write-Output "Selecting subscription '$subscriptionId'."
        try { Select-AzSubscription -SubscriptionId $subscriptionId | Out-Null } catch { Write-Error "Could not select subscription. $_"; return }
    }
    else {
        $subs = Get-AzSubscription -ErrorAction SilentlyContinue
        if ($null -eq $subs) {
            Write-Error "No subscriptions visible to the current account."
            return
        }
        if ($subs.Count -gt 1) {
            Write-Output "Current subscription: $((Get-AzContext).Name)"
            $i = 1
            $subs | ForEach-Object { Write-Output "$i - $($_.Name) - $($_.SubscriptionId)"; $i++ }
            $selection = Read-Host "Select subscription number (Enter to keep current)"
            if (-not [string]::IsNullOrWhiteSpace($selection)) {
                if ([int]::TryParse($selection, [ref]$null) -and [int]$selection -ge 1 -and [int]$selection -le $subs.Count) {
                    Select-AzSubscription -SubscriptionObject $subs[[int]$selection - 1] | Out-Null
                }
                else {
                    Write-Error "Invalid selection '$selection'."
                    return
                }
            }
        }
    }

    $tenantIDtoAppend = '-' + ($((Get-AzContext).Tenant.Id).Split('-')[0])

    $keyVaultName              = $config.keyVaultName + $tenantIDtoAppend
    $resourcegroup             = $config.resourcegroup + $tenantIDtoAppend
    $region                    = $config.region
    $logAnalyticsworkspaceName = $config.logAnalyticsworkspaceName + $tenantIDtoAppend
    $functionname              = $config.functionName + $tenantIDtoAppend

    if (-not $update) {
        # Deterministic-but-unique storage account name suffix (4 lowercase chars).
        $randomstoragechars = -join ((97..122) | Get-Random -Count 4 | ForEach-Object { [char]$_ })
        $storageaccountName = ("$($config.storageaccountName)$randomstoragechars").ToLower()

        if ($storageaccountName -notmatch '^[a-z0-9]{3,24}$') {
            Write-Error "Storage account name '$storageaccountName' must be 3-24 lowercase letters/digits. Update config.storageaccountName."
            return
        }
        try {
            $storageNameAvailable = (Get-AzStorageAccountNameAvailability -Name $storageaccountName).NameAvailable
        }
        catch {
            Write-Error "Storage account name availability check failed. $_"
            return
        }
        if (-not $storageNameAvailable) {
            Write-Error "Storage account name '$storageaccountName' is not available. Try a different config.storageaccountName."
            return
        }

        $deferTenantsComplianceTable = $false
        if ($null -ne $config.PSObject.Properties['deferGuardrailsTenantsComplianceTableProvisioning'] -and $config.deferGuardrailsTenantsComplianceTableProvisioning -eq $true) {
            $deferTenantsComplianceTable = $true
        }

        $templateParameterObject = @{
            kvName                                              = $keyVaultName
            location                                            = $region
            storageAccountName                                  = $storageaccountName
            logAnalyticsWorkspaceName                           = $logAnalyticsworkspaceName
            version                                             = $tags.ReleaseVersion
            releasedate                                         = $tags.ReleaseDate
            functionname                                        = $functionname
            deferGuardrailsTenantsComplianceTableProvisioning   = $deferTenantsComplianceTable
            ingestionServicePrincipalObjectId                   = (Resolve-CentralViewIngestionServicePrincipalObjectId -ApplicationId $config.ApplicationId)
        }
        if (-not [string]::IsNullOrWhiteSpace($alternatePSModulesURL)) {
            $templateParameterObject['CustomModulesBaseURL'] = $alternatePSModulesURL
        }

        # Key Vault name availability (separate from RG ARM check).
        try {
            $kvAvailability = ((Invoke-AzRest -Method Post `
                -Uri "https://management.azure.com/subscriptions/$((Get-AzContext).Subscription.Id)/providers/Microsoft.KeyVault/checkNameAvailability?api-version=2021-11-01-preview" `
                -Payload "{""name"":""$keyVaultName"",""type"":""Microsoft.KeyVault/vaults""}").Content | ConvertFrom-Json).NameAvailable
        }
        catch {
            $kvAvailability = $true # If the API check fails, let the deploy attempt and surface the real error.
        }
        if (-not $kvAvailability) {
            Write-Warning "Key Vault name '$keyVaultName' is not available globally. If the vault already exists in this RG and you are re-running setup, this is fine; otherwise change config.keyVaultName."
        }

        Write-Output "Creating resource group '$resourcegroup' in '$region'."
        try {
            New-AzResourceGroup -Name $resourcegroup -Location $region -Tag $tagstable -Force -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Error "Error creating resource group '$resourcegroup' (often a tagging policy). $_"
            return
        }

        Write-Output "Deploying solution through Bicep."
        $templateParameterObject | Format-Table -AutoSize | Out-String | Write-Verbose
        try {
            New-AzResourceGroupDeployment -ResourceGroupName $resourcegroup `
                -Name "guardraildeployment$(Get-Date -Format 'ddMMyyHHmmss')" `
                -TemplateParameterObject $templateParameterObject `
                -TemplateFile (Join-Path $scriptRoot 'IaC/grfunc.bicep') `
                -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Error "Bicep deployment failed: $_"
            return
        }

        # Self-grant Key Vault Administrator (idempotent).
        try { $kv = Get-AzKeyVault -ResourceGroupName $resourcegroup -VaultName $keyVaultName -ErrorAction Stop } catch { Write-Error "Cannot fetch deployed Key Vault '$keyVaultName'. $_"; return }
        try {
            New-AzRoleAssignment -ObjectId $currentUserId -RoleDefinitionName "Key Vault Administrator" -Scope $kv.ResourceId -ErrorAction Stop | Out-Null
        }
        catch {
            if (-not (Test-RoleAssignmentConflictIsBenign $_)) {
                Write-Warning "Could not assign Key Vault Administrator to current user (may already be present). $_"
            }
        }
        Write-Output "Sleeping 30 seconds for KV permissions to propagate..."
        Start-Sleep -Seconds 30

        # Function App's MSI may need a moment to surface; retry getting it.
        $funcMsi = $null
        for ($i = 0; $i -lt 6 -and -not $funcMsi; $i++) {
            try {
                $webapp  = Get-AzWebApp -Name $functionname -ResourceGroupName $resourcegroup -ErrorAction Stop
                $funcMsi = $webapp.Identity.PrincipalId
            }
            catch { Start-Sleep -Seconds 10 }
            if (-not $funcMsi) { Start-Sleep -Seconds 10 }
        }
        if ($funcMsi) {
            foreach ($role in @('Key Vault Secrets User', 'Key Vault Reader')) {
                try { New-AzRoleAssignment -ObjectId $funcMsi -RoleDefinitionName $role -Scope $kv.ResourceId -ErrorAction Stop | Out-Null }
                catch {
                    if (-not (Test-RoleAssignmentConflictIsBenign $_)) {
                        Write-Warning "Could not assign '$role' to Function App MSI. $_"
                    }
                }
            }
        }
        else {
            Write-Warning "Function App MSI did not appear in time; assign 'Key Vault Secrets User' / 'Key Vault Reader' on the KV manually."
        }

        # Aggregation tenant info from Microsoft Graph.
        try {
            $org = Invoke-AzRestMethod -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization' -ErrorAction Stop |
                Select-Object -ExpandProperty Content | ConvertFrom-Json
            $aggTenantId      = $org.value.id
            $aggTenantName    = $org.value.displayName
            $aggDomainUPN     = ($org.value.verifiedDomains | Where-Object { $_.isDefault }).name

            Set-AzKeyVaultSecret -VaultName $keyVaultName -Name 'TenantId'        -SecretValue (Convert-PlainTextToSecureString $aggTenantId) | Out-Null
            Set-AzKeyVaultSecret -VaultName $keyVaultName -Name 'TenantName'      -SecretValue (Convert-PlainTextToSecureString $aggTenantName) | Out-Null
            if (-not [string]::IsNullOrWhiteSpace($aggDomainUPN)) {
                Set-AzKeyVaultSecret -VaultName $keyVaultName -Name 'tenantDomainUPN' -SecretValue (Convert-PlainTextToSecureString $aggDomainUPN) | Out-Null
            }
        }
        catch {
            Write-Warning "Could not seed tenant info secrets (TenantId/TenantName/tenantDomainUPN): $_"
        }

        # Workspace key + id (used by some legacy flows; ingestion now uses DCR but secrets stay for compatibility).
        try {
            $ws         = Get-AzOperationalInsightsWorkspace -ResourceGroupName $resourcegroup -Name $logAnalyticsworkspaceName -ErrorAction Stop
            $wsShared   = (Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $resourcegroup -Name $logAnalyticsworkspaceName -ErrorAction Stop).PrimarySharedKey
            Set-AzKeyVaultSecret -VaultName $keyVaultName -Name 'WorkspaceKey' -SecretValue (Convert-PlainTextToSecureString $wsShared) | Out-Null
            Set-AzKeyVaultSecret -VaultName $keyVaultName -Name 'WorkspaceId'  -SecretValue (Convert-PlainTextToSecureString $ws.CustomerId) | Out-Null
        }
        catch {
            Write-Warning "Could not seed Workspace secrets: $_"
        }

        # ApplicationId / SecurePassword from config (or placeholder).
        try {
            if (-not [string]::IsNullOrWhiteSpace($config.ApplicationId)) {
                Set-AzKeyVaultSecret -VaultName $keyVaultName -Name 'ApplicationId'  -SecretValue (Convert-PlainTextToSecureString $config.ApplicationId) | Out-Null
                Set-AzKeyVaultSecret -VaultName $keyVaultName -Name 'SecurePassword' -SecretValue (Convert-PlainTextToSecureString $config.SecurePassword) | Out-Null
                Write-Output "ApplicationId and SecurePassword stored in Key Vault."
            }
            else {
                # Seed empty placeholders so Function code's Get-AzKeyVaultSecret calls don't fail with NotFound.
                $placeholder = Convert-PlainTextToSecureString ' '
                foreach ($name in 'ApplicationId','SecurePassword') {
                    if (-not (Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $name -ErrorAction SilentlyContinue)) {
                        Set-AzKeyVaultSecret -VaultName $keyVaultName -Name $name -SecretValue $placeholder | Out-Null
                    }
                }
                Write-Warning "config.ApplicationId / SecurePassword are empty - placeholders seeded. Add real values to Key Vault and rerun setup for DCR RBAC."
            }
        }
        catch {
            Write-Warning "Could not write ApplicationId/SecurePassword secrets: $_"
        }

        # Make absolutely sure the DCR RBAC happens once we know the SP exists.
        try {
            $spObjectId = Resolve-CentralViewIngestionServicePrincipalObjectId -ApplicationId $config.ApplicationId
            if (-not [string]::IsNullOrWhiteSpace($spObjectId)) {
                $dcr = Get-AzResource -ResourceGroupName $resourcegroup -ResourceType 'Microsoft.Insights/dataCollectionRules' -Name 'guardrails-cv-dcr' -ErrorAction SilentlyContinue
                if ($dcr) {
                    try {
                        New-AzRoleAssignment -ObjectId $spObjectId -RoleDefinitionName 'Monitoring Metrics Publisher' -Scope $dcr.ResourceId -ErrorAction Stop | Out-Null
                        Write-Output "Granted Monitoring Metrics Publisher to ingestion SP on DCR."
                    }
                    catch {
                        if (-not (Test-RoleAssignmentConflictIsBenign $_)) {
                            Write-Warning "Could not grant Monitoring Metrics Publisher on DCR. $_"
                        }
                    }
                }
                else {
                    Write-Warning "DCR 'guardrails-cv-dcr' not found in '$resourcegroup' - manually assign Monitoring Metrics Publisher once it appears."
                }
            }
        }
        catch {
            Write-Warning "DCR RBAC step failed: $_"
        }

        # Publish Function App code (cross-platform temp path).
        Write-Output "Packaging and publishing Function App code."
        try {
            [System.Net.ServicePointManager]::SecurityProtocol = 'TLS12'
            $sscViewZipPath = Join-Path ([System.IO.Path]::GetTempPath()) 'sscview.zip'
            if (Test-Path $sscViewZipPath) { Remove-Item $sscViewZipPath -Force -ErrorAction SilentlyContinue }

            # ../* relative to the setup folder packages all the function code (host.json, runbooks, profile.ps1, etc.)
            $sourceGlob = Join-Path (Split-Path -Parent $scriptRoot) '*'
            Compress-Archive -Path $sourceGlob -DestinationPath $sscViewZipPath -Force
            Publish-AzWebApp -ResourceGroupName $resourcegroup -Name $functionname -ArchivePath $sscViewZipPath -Force | Out-Null
        }
        catch {
            Write-Error "Function code publish failed: $_"
            return
        }

        $timetaken = (Get-Date) - $begin
        Write-Output ("Setup complete in {0} minutes." -f [Math]::Round($timetaken.TotalMinutes, 0))
    }
}
finally {
    Pop-Location
}