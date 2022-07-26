param (
    [Parameter(Mandatory = $true)]
    [string]
    $configFilePath,
    [Parameter(Mandatory = $true)]
    [string]
    $userId,
    [Parameter(Mandatory = $false)]
    [string]
    $existingKeyVaultName,
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
    $alternatePSModulesURL
)
#region Configuration and initialization
# test
#Configuration Variables
$version = '1.0'
$releaseDate = '2022-07-01' #yyyy-mm-dd
$randomstoragechars = -join ((97..122) | Get-Random -Count 4 | ForEach-Object { [char]$_ })
Write-Output "Reading Config file:"
try {
    $config = get-content $configFilePath | convertfrom-json
}
catch {
    "Error reading config file."
    break
}
#$tenantIDtoAppend="-"+$($env:ACC_TID).Split("-")[0]
$tenantIDtoAppend = "-" + $((Get-AzContext).Tenant.Id).Split("-")[0]
$keyVaultName = $config.keyVaultName + $tenantIDtoAppend
$resourcegroup = $config.resourcegroup + $tenantIDtoAppend
$region = $config.region
$storageaccountName = "$($config.storageaccountName)$randomstoragechars"
$logAnalyticsworkspaceName = $config.logAnalyticsworkspaceName + $tenantIDtoAppend
$autoMationAccountName = $config.autoMationAccountName + $tenantIDtoAppend
$keyVaultRG = $resourcegroup #initially, same RG.
$logAnalyticsWorkspaceRG = $resourcegroup #initially, same RG.
$deployKV = 'true'
$deployLAW = 'true'
$bga1 = $config.FirstBreakGlassAccountUPN #Break glass account 1
$bga2 = $config.SecondBreakGlassAccountUPN #Break glass account 2
$PBMMPolicyID = $config.PBMMPolicyID
$AllowedLocationPolicyId = $config.AllowedLocationPolicyId
$DepartmentNumber = $config.DepartmentNumber
if ($config.SecurityLAWResourceId.split("/").Count -ne 9 -or $config.HealthLAWResourceId.Split("/").Count -ne 9) {
    Write-Output "Error in SecurityLAWResourceId or HealthLAWResourceId ID. Parameter needs to be a full resource Id. (/subscriptions/<subid>/...)"
    Break
}

#Other Variables
$mainRunbookName = "main"
$mainRunbookPath = '.\'
$mainRunbookDescription = "Guardrails Main Runbook"

#Tests if logged in:
$subs = Get-AzSubscription -ErrorAction SilentlyContinue
if (-not($subs)) {
    Connect-AzAccount
    $subs = Get-AzSubscription -ErrorAction SilentlyContinue
}
if ($subs.count -gt 1) {
    Write-output "More than one subscription detected. Current subscription $((get-azcontext).Name)"
    Write-output "Please select subscription for deployment or Enter to keep current one:"
    $i = 1
    $subs | ForEach-Object { Write-output "$i - $($_.Name) - $($_.SubscriptionId)"; $i++ }
    [int]$selection = Read-Host "Select Subscription number: (1 - $($i-1))"
}
else { $selection = 0 }
if ($selection -ne 0) {
    if ($selection -gt 0 -and $selection -le ($i - 1)) { 
        Select-AzSubscription -SubscriptionObject $subs[$selection - 1]
    }
    else {
        Write-output "Invalid selection. ($selection)"
        break
    }
}
else {
    Write-host "Keeping current subscription."
}
#region Let's deal with existing stuff...
# Keyvault first
if (!([string]::IsNullOrEmpty($existingKeyVaultName))) {
    Write-Output "Will try to use an existing Keyvault."
    $keyVaultName = $existingKeyVaultName
    $keyVaultRG = $existingKeyVaultRG
    $deployKV = 'false'
}
#log analytics now...
if (!([string]::IsNullOrEmpty($existingWorkspaceName))) {
    Write-Output "Will try to use an existing Log Analytics workspace."
    $logAnalyticsworkspaceName = $existingWorkspaceName
    $logAnalyticsWorkspaceRG = $existingWorkSpaceRG
    $deployLAW = 'false' #it will be passed to bicep.
}
#endregion
#Storage verification
if ((Get-AzStorageAccountNameAvailability -Name $storageaccountName).NameAvailable -eq $false) {
    Write-Error "Storage account $storageaccountName not available."
    break
}
if ($storageaccountName.Length -gt 24 -or $storageaccountName.Length -lt 3) {
    Write-Error "Storage account name must be between 3 and 24 lowercase characters."
    break
}
#endregion
#region keyvault verification
$kvContent = ((Invoke-AzRest -Uri "https://management.azure.com/subscriptions/$((Get-AzContext).Subscription.Id)/providers/Microsoft.KeyVault/checkNameAvailability?api-version=2021-11-01-preview" `
            -Method Post -Payload "{""name"": ""$keyVaultName"",""type"": ""Microsoft.KeyVault/vaults""}").Content | ConvertFrom-Json).NameAvailable
if (!($kvContent)) {
    write-output "Error: keyvault name $keyVaultName is not available."
    break
}
#endregion
#before deploying anything, check if current user can be found.
$begin = get-date
Write-Verbose "Adding current user as a Keyvault administrator (for setup)."
if ($userId -eq "") {
    $currentUserId = (get-azaduser -UserPrincipalName (Get-AzAccessToken).UserId).Id 
}
else {
    $currentUserId = (get-azaduser -UserPrincipalName $userId).Id
}
if ($null -eq $currentUserId) {
    Write-Error "Error: no current user could be found in current Tenant. Context: $((Get-AzAccessToken).UserId). Override specified: $userId."
    break;
}
#region  Template Deployment
Write-Output "Creating bicep parameters file for this deployment."
$parameterTemplate = get-content .\parameters_template.json
$parameterTemplate = $parameterTemplate.Replace("%kvName%", $keyVaultName)
$parameterTemplate = $parameterTemplate.Replace("%location%", $region)
$parameterTemplate = $parameterTemplate.Replace("%storageAccountName%", $storageaccountName)
$parameterTemplate = $parameterTemplate.Replace("%logAnalyticsWorkspaceName%", $logAnalyticsworkspaceName)
$parameterTemplate = $parameterTemplate.Replace("%automationAccountName%", $autoMationAccountName)
$parameterTemplate = $parameterTemplate.Replace("%subscriptionId%", (Get-AzContext).Subscription.Id)
$parameterTemplate = $parameterTemplate.Replace("%PBMMPolicyID%", $PBMMPolicyID)
$parameterTemplate = $parameterTemplate.Replace("%deployKV%", $deployKV)
$parameterTemplate = $parameterTemplate.Replace("%deployLAW%", $deployLAW)
$parameterTemplate = $parameterTemplate.Replace("%AllowedLocationPolicyId%", $AllowedLocationPolicyId)
$parameterTemplate = $parameterTemplate.Replace("%DepartmentNumber%", $DepartmentNumber)
$parameterTemplate = $parameterTemplate.Replace("%CBSSubscriptionName%", $config.CBSSubscriptionName)
$parameterTemplate = $parameterTemplate.Replace("%SecurityLAWResourceId%", $config.SecurityLAWResourceId)
$parameterTemplate = $parameterTemplate.Replace("%HealthLAWResourceId%", $config.HealthLAWResourceId)
$parameterTemplate = $parameterTemplate.Replace("%version%", $version)
$parameterTemplate = $parameterTemplate.Replace("%releasedate%", $releaseDate)
$parameterTemplate = $parameterTemplate.Replace("%Locale%", $config.Locale)
#writes the file
$parameterTemplate | out-file .\parameters.json -Force
#endregion

#region bicep deployment

# create a parameter object for dynamically passing a CustomModulesBaseURL value to bicep
$templateParameterObject = @{}
$paramFileContent = Get-Content .\parameters.json | ConvertFrom-Json -Depth 20
$paramFileContent.parameters | Get-Member -MemberType Properties | ForEach-Object {
    $templateParameterObject += @{ $_.name = $paramFileContent.parameters.$($_.name).value }
}

If (![string]::IsNullOrEmpty($alternatePSModulesURL)) {
    $templateParameterObject += @{CustomModulesBaseURL = $alternatePSModulesURL }
}

Write-Verbose "Creating $resourceGroup in $region location."
$tags = get-content ./tags.json | convertfrom-json
$tagstable = @{}
$tags.psobject.properties | Foreach { $tagstable[$_.Name] = $_.Value }
try {
    New-AzResourceGroup -Name $resourceGroup -Location $region -Tags $tagstable
}
catch { 
    throw "Error creating resource group. $_" 
}

Write-Output "Deploying solution through bicep."
try { 
    New-AzResourceGroupDeployment -ResourceGroupName $resourcegroup -Name "guardraildeployment$(get-date -format "ddmmyyHHmmss")" `
        -TemplateParameterObject $templateParameterObject -TemplateFile .\guardrails.bicep -WarningAction SilentlyContinue
}
catch {
    Write-error "Error deploying solution to Azure. $_"
}
#endregion
#Add current user as a Keyvault administrator (for setup)
try { $kv = Get-AzKeyVault -ResourceGroupName $keyVaultRG -VaultName $keyVaultName } catch { "Error fetching KV object. $_"; break }
try { New-AzRoleAssignment -ObjectId $currentUserId -RoleDefinitionName "Key Vault Administrator" -Scope $kv.ResourceId }catch { "Error assigning permissions to KV. $_"; break }
Write-Output "Sleeping 30 seconds to allow for permissions to be propagated."
Start-Sleep -Seconds 30
#region Secret Setup
# Adds keyvault secret user permissions to the Automation account
Write-Verbose "Adding automation account Keyvault Secret User."
try {
    New-AzRoleAssignment -ObjectId (Get-AzAutomationAccount -AutomationAccountName $autoMationAccountName -ResourceGroupName $resourceGroup).Identity.PrincipalId -RoleDefinitionName "Key Vault Secrets User" -Scope $kv.ResourceId
}
catch {
    "Error assigning permissions to Automation account (for keyvault). $_"
    break
}

Write-Verbose "Adding workspacekey secret to keyvault."
try {
    $workspaceKey = (Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $logAnalyticsWorkspaceRG -Name $logAnalyticsworkspaceName).PrimarySharedKey
    $secretvalue = ConvertTo-SecureString $workspaceKey -AsPlainText -Force 
    $secret = Set-AzKeyVaultSecret -VaultName $keyVaultName -Name "WorkSpaceKey" -SecretValue $secretvalue
}
catch { "Error adding WS secret to KV. $_"; break }
#endregion
#region Copy modules definition to recently created Storage account
Import-Module ./blob-functions.psm1
copy-toBlob -FilePath ./modules.json -storageaccountName $storageaccountName -resourcegroup $resourceGroup -force -containerName "configuration"
#endregion

#region Import main runbook
Write-Verbose "Importing Runbook." #only one for now, as a template.
try {
    Import-AzAutomationRunbook -Name $mainRunbookName -Path "$mainRunbookpath\main.ps1" -Description $mainRunbookDescription -Type PowerShell -Published `
        -ResourceGroupName $resourcegroup -AutomationAccountName $autoMationAccountName -Tags @{version = $version }
    #Create schedule
    New-AzAutomationSchedule -ResourceGroupName $resourcegroup -AutomationAccountName $autoMationAccountName -Name "GR-Hourly" -StartTime (get-date).AddHours(1) -HourInterval 1
    #Register
    Register-AzAutomationScheduledRunbook -Name $mainRunbookName -ResourceGroupName $resourcegroup -AutomationAccountName $autoMationAccountName -ScheduleName "GR-Hourly"
}
catch {
    "Error importing Runbook. $_"
    break
}
#endregion

#region Other secrects
#Breakglass accounts and UPNs
try {
    $secretvalue = ConvertTo-SecureString $bga1 -AsPlainText -Force 
    $secret = Set-AzKeyVaultSecret -VaultName $keyVaultName -Name "BGA1" -SecretValue $secretvalue
    $secretvalue = ConvertTo-SecureString $bga2 -AsPlainText -Force 
    $secret = Set-AzKeyVaultSecret -VaultName $keyVaultName -Name "BGA2" -SecretValue $secretvalue
    #endregion

    #region Assign permissions
    $GraphAppId = "00000003-0000-0000-c000-000000000000"
    Write-Output "Adding Permissions to Automation Account - Managed Identity"
    import-module AzureAD.Standard.Preview
    AzureAD.Standard.Preview\Connect-AzureAD -Identity -TenantID $env:ACC_TID
    $MSI = (Get-AzureADServicePrincipal -Filter "displayName eq '$autoMationAccountName'")
    #Start-Sleep -Seconds 10
    $graph = Get-AzureADServicePrincipal -Filter "appId eq '$GraphAppId'"
    $appRoleIds = @("Organization.Read.All", "User.Read.All", "UserAuthenticationMethod.Read.All", "Policy.Read.All")
    foreach ($approleidName in $appRoleIds) {
        Write-Output "Adding permission to $approleidName"
        $approleid = ($graph.AppRoles | Where-Object { $_.Value -eq $approleidName }).Id
        if ($null -ne $approleid) {
            try {
                New-AzureAdServiceAppRoleAssignment -ObjectId $MSI.ObjectId -PrincipalId $MSI.ObjectId -ResourceId $graph.ObjectId -Id $approleid
            }
            catch {
                "Error assigning permissions $approleid to $approleidName. $_"
            }
        }
        else {
            Write-Output "App Role Id $approleid Not found... :("
        }
    }
}
catch {
    "Error assigning permissions to graph API. $_"
    break 
}
#endregion
try {
    Write-Output "Assigning reader access to the Automation Account Managed Identity for MG: $($rootmg.DisplayName)"
    $rootmg = get-azmanagementgroup | ? { $_.Id.Split("/")[4] -eq (Get-AzContext).Tenant.Id }
    $AAId = (Get-AzAutomationAccount -ResourceGroupName $resourcegroup -Name $autoMationAccountName).Identity.PrincipalId
    New-AzRoleAssignment -ObjectId $AAId -RoleDefinitionName Reader -Scope $rootmg.Id
    New-AzRoleAssignment -ObjectId $AAId -RoleDefinitionName "Reader and Data Access" -Scope (Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageaccountName).Id
    New-AzRoleAssignment -ObjectId $AAID -RoleDefinitionName Reader -Scope /providers/Microsoft.aadiam
}
catch {
    "Error assigning root management group permissions. $_"
    break
}
Write-Output "Waiting 60 seconds to allow for management group permissions to be applied."
Start-Sleep -Seconds 60
try {
    Start-AzAutomationRunbook -Name "main" -AutomationAccountName $autoMationAccountName -ResourceGroupName $resourcegroup
}
catch { 
    "Error starting runbook. $_"
}
$timetaken = ((get-date) - $begin) 
"Time to deploy: $([Math]::Round($timetaken.TotalMinutes,0)) Minutes."
# SIG # Begin signature block
# MIInmAYJKoZIhvcNAQcCoIIniTCCJ4UCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD/nobQmBPaMrVp
# WRpVzUzs/uyqXGuMocDS7bvwI72kQaCCDXYwggX0MIID3KADAgECAhMzAAACURR2
# zMWFg24LAAAAAAJRMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjEwOTAyMTgzMjU5WhcNMjIwOTAxMTgzMjU5WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDBIpXR3b1IYAMunV9ZYBVYsaA7S64mqacKy/OJUf0Lr/LW/tWlJDzJH9nFAhs0
# zzSdQQcLhShOSTUxtlwZD9dnfIcx4pZgu0VHkqQw2dVc8Ob21GBo5sVrXgEAQxZo
# rlEuAl20KpSIFLUBwoZFGFSQNSMcqPudXOw+Mhvn6rXYv/pjXIjgBntn6p1f+0+C
# 2NXuFrIwjJIJd0erGefwMg//VqUTcRaj6SiCXSY6kjO1J9P8oaRQBHIOFEfLlXQ3
# a1ATlM7evCUvg3iBprpL+j1JMAUVv+87NRApprPyV75U/FKLlO2ioDbb69e3S725
# XQLW+/nJM4ihVQ0BHadh74/lAgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUMLgM7NX5EnpPfK5uU6FPvn2g/Ekw
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzQ2NzU5NjAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAIVJlff+Fp0ylEJhmvap
# NVv1bYLSWf58OqRRIDnXbHQ+FobsOwL83/ncPC3xl8ySR5uK/af4ZDy7DcDw0yEd
# mKbRLzHIfcztZVSrlsg0GKwZuaB2MEI1VizNCoZlN+HlFZa4DNm3J0LhTWrZjVR0
# M6V57cFW0GsV4NlqmtelT9JFEae7PomwgAV9xOScz8HzvbZeERcoSRp9eRsQwOw7
# 8XeCLeglqjUnz9gFM7RliCYP58Fgphtkht9LNEcErLOVW17m6/Dj75zg/IS+//6G
# FEK2oXnw5EIIWZraFHqSaee+NMgOw/R6bwB8qLv5ClOJEpGKA3XPJvS9YgOpF920
# Vu4Afqa5Rv5UJKrsxA7HOiuH4TwpkP3XQ801YLMp4LavXnvqNkX5lhFcITvb01GQ
# lcC5h+XfCv0L4hUum/QrFLavQXJ/vtirCnte5Bediqmjx3lswaTRbr/j+KX833A1
# l9NIJmdGFcVLXp1en3IWG/fjLIuP7BqPPaN7A1tzhWxL+xx9yw5vQiT1Yn14YGmw
# OzBYYLX0H9dKRLWMxMXGvo0PWEuXzYyrdDQExPf66Fq/EiRpZv2EYl2gbl9fxc3s
# qoIkyNlL1BCrvmzunkwt4cwvqWremUtqTJ2B53MbBHlf4RfvKz9NVuh5KHdr82AS
# MMjU4C8KNTqzgisqQdCy8unTMIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
# hkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
# IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQg
# Q29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03
# a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akr
# rnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0Rrrg
# OGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy
# 4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9
# sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAh
# dCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8k
# A/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTB
# w3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmn
# Eyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90
# lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0w
# ggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2o
# ynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBa
# BgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsG
# AQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNV
# HSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsG
# AQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABl
# AG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKb
# C5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11l
# hJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6
# I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0
# wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560
# STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQam
# ASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGa
# J+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ah
# XJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA
# 9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33Vt
# Y5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr
# /Xmfwb1tbWrJUnMTDXpQzTGCGXgwghl0AgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAAJRFHbMxYWDbgsAAAAAAlEwDQYJYIZIAWUDBAIB
# BQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIMFSMDGocxfLMaBcNMIDgQDI
# RGnTAzeZ1kE5X6IJ6XCUMEQGCisGAQQBgjcCAQwxNjA0oBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEcgBpodHRwczovL3d3dy5taWNyb3NvZnQuY29tIDANBgkqhkiG9w0B
# AQEFAASCAQCos5no89RTnRWuuXCLpPtFRxBnDw/8dUMAPJB+EHAwv5YA90Ig5lqy
# xhQXgBhztRw77jXYw5g62h/k6CKQUWQr6QVF9YQX7diGrdqHpPGTrNPD0cTyftoU
# jRpumIEsNBuz6DoSWL7fO8BXIkPfnb97goYGTsJIlrDZlLQOmSwCvglcafHMtDI3
# vBoZjAppy+7kp7ffIriPdab3WF6TqDKsf0xIO5mfM9BvMfHrcgud32h7eFAFiZ/X
# iWC7Vj0vcAOF5YyqCFhaGwxrlMxzohyrg0eGJ0QIKYiayfNWkSgoYC8VprSVymJp
# jkcBm29aJ6/nanQV1NJL0vujE1ox61B8oYIXADCCFvwGCisGAQQBgjcDAwExghbs
# MIIW6AYJKoZIhvcNAQcCoIIW2TCCFtUCAQMxDzANBglghkgBZQMEAgEFADCCAVEG
# CyqGSIb3DQEJEAEEoIIBQASCATwwggE4AgEBBgorBgEEAYRZCgMBMDEwDQYJYIZI
# AWUDBAIBBQAEIBbRWfc/6HREijlEW1Y2t2jgabUU3OyNCN2u5tTwQRSeAgZi1XrZ
# CJcYEzIwMjIwNzI2MTg0MDE3Ljk4NVowBIACAfSggdCkgc0wgcoxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBB
# bWVyaWNhIE9wZXJhdGlvbnMxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOjEyQkMt
# RTNBRS03NEVCMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# oIIRVzCCBwwwggT0oAMCAQICEzMAAAGhAYVVmblUXYoAAQAAAaEwDQYJKoZIhvcN
# AQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMjExMjAyMTkw
# NTI0WhcNMjMwMjI4MTkwNTI0WjCByjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9u
# czEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046MTJCQy1FM0FFLTc0RUIxJTAjBgNV
# BAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQDayTxe5WukkrYxxVuHLYW9BEWCD9kkjnnHsOKwGddI
# PbZlLY+l5ovLDNf+BEMQKAZQI3DX91l1yCDuP9X7tOPC48ZRGXA/bf9ql0FK5438
# gIl7cV528XeEOFwc/A+UbIUfW296Omg8Z62xaQv3jrG4U/priArF/er1UA1HNuIG
# UyqjlygiSPwK2NnFApi1JD+Uef5c47kh7pW1Kj7RnchpFeY9MekPQRia7cEaUYU4
# sqCiJVdDJpefLvPT9EdthlQx75ldx+AwZf2a9T7uQRSBh8tpxPdIDDkKiWMwjKTr
# AY09A3I/jidqPuc8PvX+sqxqyZEN2h4GA0Edjmk64nkIukAK18K5nALDLO9SMTxp
# AwQIHRDtZeTClvAPCEoy1vtPD7f+eqHqStuu+XCkfRjXEpX9+h9frsB0/BgD5CBf
# 3ELLAa8TefMfHZWEJRTPNrbXMKizSrUSkVv/3HP/ZsJpwaz5My2Rbyc3Ah9bT76e
# BJkyfT5FN9v/KQ0HnxhRMs6HHhTmNx+LztYci+vHf0D3QH1eCjZWZRjp1mOyxpPU
# 2mDMG6gelvJse1JzRADo7YIok/J3Ccbm8MbBbm85iogFltFHecHFEFwrsDGBFnNY
# HMhcbarQNA+gY2e2l9fAkX3MjI7Uklkoz74/P6KIqe5jcd9FPCbbSbYH9OLsteeY
# OQIDAQABo4IBNjCCATIwHQYDVR0OBBYEFBa/IDLbY475VQyKiZSw47l0/cypMB8G
# A1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCG
# Tmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUy
# MFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4w
# XAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2Vy
# dHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwG
# A1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQELBQAD
# ggIBACDDIxElfXlG5YKcKrLPSS+f3JWZprwKEiASvivaHTBRlXtAs+TkadcsEei+
# 9w5vmF5tCUzTH4c0nCI7bZxnsL+S6XsiOs3Z1V4WX+IwoXUJ4zLvs0+mT4vjGDtY
# fKQ/bsmJKar2c99m/fHv1Wm2CTcyaePvi86Jh3UyLjdRILWbtzs4oImFMwwKbzHd
# PopxrBhgi+C1YZshosWLlgzyuxjUl+qNg1m52MJmf11loI7D9HJoaQzd+rf928Y8
# rvULmg2h/G50o+D0UJ1Fa/cJJaHfB3sfKw9X6GrtXYGjmM3+g+AhaVsfupKXNtOF
# u5tnLKvAH5OIjEDYV1YKmlXuBuhbYassygPFMmNgG2Ank3drEcDcZhCXXqpRszNo
# 1F6Gu5JCpQZXbOJM9Ue5PlJKtmImAYIGsw+pnHy/r5ggSYOp4g5Z1oU9GhVCM3V0
# T9adee6OUXBk1rE4dZc/UsPlj0qoiljL+lN1A5gkmmz7k5tIObVGB7dJdz8J0FwX
# RE5qYu1AdvauVbZwGQkL1x8aK/svjEQW0NUyJ29znDHiXl5vLoRTjjFpshUBi2+I
# Y+mNqbLmj24j5eT+bjDlE3HmNtLPpLcMDYqZ1H+6U6YmaiNmac2jRXDAaeEE/uoD
# Mt2dArfJP7M+MDv3zzNNTINeuNEtDVgm9zwfgIUCXnDZuVtiMIIHcTCCBVmgAwIB
# AgITMwAAABXF52ueAptJmQAAAAAAFTANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0
# IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMjEwOTMwMTgyMjI1
# WhcNMzAwOTMwMTgzMjI1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCC
# AiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAOThpkzntHIhC3miy9ckeb0O
# 1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDivbk+F2Az/1xPx2b3lVNxWuJ+Slr+uDZn
# hUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU88V29YZQ3MFEyHFcUTE3oAo4bo3t
# 1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqYO7oaezOtgFt+jBAcnVL+tuhiJdxq
# D89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzpcGkNyjYtcI4xyDUoveO0hyTD4MmP
# frVUj9z6BVWYbWg7mka97aSueik3rMvrg0XnRm7KMtXAhjBcTyziYrLNueKNiOSW
# rAFKu75xqRdbZ2De+JKRHh09/SDPc31BmkZ1zcRfNN0Sidb9pSB9fvzZnkXftnIv
# 231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZNN3SUHDSCD/AQ8rdHGO2n6Jl8P0zb
# r17C89XYcz1DTsEzOUyOArxCaC4Q6oRRRuLRvWoYWmEBc8pnol7XKHYC4jMYcten
# IPDC+hIK12NvDMk2ZItboKaDIV1fMHSRlJTYuVD5C4lh8zYGNRiER9vcG9H9stQc
# xWv2XFJRXRLbJbqvUAV6bMURHXLvjflSxIUXk8A8FdsaN8cIFRg/eKtFtvUeh17a
# j54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB2TASBgkrBgEEAYI3FQEEBQIDAQAB
# MCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSavoKRPEY1Kc8Q/y8E7jAdBgNVHQ4EFgQU
# n6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0gBFUwUzBRBgwrBgEEAYI3TIN9AQEw
# QTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9E
# b2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUFBwMIMBkGCSsGAQQB
# gjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/
# MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1UdHwRPME0wS6BJ
# oEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01p
# Y1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYB
# BQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9v
# Q2VyQXV0XzIwMTAtMDYtMjMuY3J0MA0GCSqGSIb3DQEBCwUAA4ICAQCdVX38Kq3h
# LB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOXPTEztTnXwnE2P9pkbHzQdTltuw8x
# 5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjYNi6cqYJWAAOwBb6J6Gngugnue99qb74p
# y27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/zjj3G82jfZfakVqr3lbYoVSfQJL1A
# oL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz/AyeixmJ5/ALaoHCgRlCGVJ1ijbC
# HcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyRgNI95ko+ZjtPu4b6MhrZlvSP9pEB
# 9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdUbZ1jdEgssU5HLcEUBHG/ZPkkvnNt
# yo4JvbMBV0lUZNlz138eW0QBjloZkWsNn6Qo3GcZKCS6OEuabvshVGtqRRFHqfG3
# rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4Ku+xBZj1p/cvBQUl+fpO+y/g75LcV
# v7TOPqUxUYS8vwLBgqJ7Fx0ViY1w/ue10CgaiQuPNtq6TPmb/wrpNPgkNWcr4A24
# 5oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9vMvpe784cETRkPHIqzqKOghif9lw
# Y1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGCAs4wggI3AgEBMIH4oYHQpIHNMIHK
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMSYwJAYDVQQLEx1UaGFsZXMgVFNT
# IEVTTjoxMkJDLUUzQUUtNzRFQjElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAG3F2jO4LEMVLwgKGXdYMN4FBgOCg
# gYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYw
# JAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0B
# AQUFAAIFAOaKhMgwIhgPMjAyMjA3MjYyMzIwNDBaGA8yMDIyMDcyNzIzMjA0MFow
# dzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA5oqEyAIBADAKAgEAAgIbUwIB/zAHAgEA
# AgISEzAKAgUA5ovWSAIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMC
# oAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBBQUAA4GBALndA2vr
# /hyMv23m86WZQHMZCUQPGDJx8qXfHKt5dlvmNZav0dzUskpe8ZnHH+FvaYLwP+J8
# ILaioR0D18R7H3+BzXSXyUac/l1pc1I5wxeMJ6DFPwS7oID6HVW9PHMfzpKJT1mO
# CZc2tkQ2uySYs/QourzqjGjL+XZF80+VYQbiMYIEDTCCBAkCAQEwgZMwfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGhAYVVmblUXYoAAQAAAaEwDQYJ
# YIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkq
# hkiG9w0BCQQxIgQgAiK5jF2WfVsekiaRGQ+jEB1KooF69tek47rKiad8CUwwgfoG
# CyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCDrCFTxOoGCaCCCjoRyBe1JSQrMJeCC
# TyErziiJ347QhDCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# AhMzAAABoQGFVZm5VF2KAAEAAAGhMCIEIAj6bh2jmnFkGM9l5iVU+Sl1Xiy6jsjy
# DKCE9reeqJSuMA0GCSqGSIb3DQEBCwUABIICADS/k/ueDhheA92bvqvhbixtruVC
# MbO0GKWCxgXwPC8AWSQc2+uzUvvZPakvYEeWhOmsADCJQzexw42l/CFwK7SPcThf
# jbY7bXkR14wV3z7a9bOAKixzGdlqcSZ561+/EVy8QXmt/yDngW+NZ4Pg7ujJ0Bct
# TsC6D/0yFZLwmPBSzA2vEnB8mSuu6WGsFYw1hO+jGmCu1/ESUm+fS1AV7w24oIXp
# zlpHSc8oKjrxjCJ3bV7Bk+oEPZ/0Z9L+f+0/SoS8kMGcKGlbhYkIreBKl2tJbpMj
# aPV4XvX/zcwGE30EsOluf9JCwXBjST4JNuQezd9FKoyCQj7HxT4nwYyVhsoP+Txm
# HV+vSJU9Ll3bdsnznsb5uX9w22d0TQ8SuW+C94MPSlO67Ufe9axJgeEcz1+IcUpw
# yzlUUZ6/VySjLZ06OZAlLFyy2XiGTkLz4NMr76R/myQok+tIvkWDHZQtvPc9NFWc
# gpGojsvp7BM7GpJuvQ8X088zQPA/tThepOyaNcLYk6dk+RAmlCbR4yuU4MtDi/Np
# 1ZqoX7V/n+XHtVMEPJPxtwIxhl/cvn5YDNugUsv4hM6dyLdnHk86671r9mYBGH+9
# 85Jmv3cnXHGgfXDP2psa5j71NqArh0AviDhGNecFO3NE6ENFiZsuNKK7coGIlHVj
# R78De+m1TwcVT+Qv
# SIG # End signature block
