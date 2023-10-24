param (
    [switch]$localExecution,
    [string]$keyVaultName
)

Disable-AzContextAutosave -Scope Process | Out-Null

function Get-GSAAutomationVariable {
    param ([parameter(Mandatory = $true)]$name)

    Write-Debug "Getting automation variable '$name'"
    # when running in an Azure Automation Account
    If ($ENV:AZUREPS_HOST_ENVIRONMENT -eq 'AzureAutomation/') {
        $value = Get-AutomationVariable -Name $name
        return $value
    }
    # when running outside an automation account
    Else {
        If ($value = [System.Environment]::GetEnvironmentVariable($name)) {
            Write-Debug "Found variable '$name' in environment variables"
            return $value
        }
        Else {
            Write-Debug "Variable '$name' not found in environment variables, trying keyvault"
            $secretValue = Get-AzKeyVaultSecret -VaultName $ENV:KeyvaultName -Name $name -AsPlainText
            return $secretValue.trim('"')
        }
    }
}

# Connects to Azure using the Automation Account's managed identity
If (!$localExecution.IsPresent) {
    try {
        Connect-AzAccount -Identity -ErrorAction Stop
    }
    catch {
        throw "Critical: Failed to connect to Azure with the 'Connect-AzAccount' command and '-identity' (MSI) parameter; verify that Azure Automation identity is configured. Error message: $_"
    }
}
Else {
    Write-Output "Running locally, skipping Azure connection."

    Update-AzConfig -Scope Process -DisplayBreakingChangeWarning:$false
    
    Write-Output "Removing previously imported Guardrail modules..."
    Get-Module | where-object {$_.Path -like '*GUARDRAIL*'} | Remove-Module

    Write-Output "Importing all modules manually..."
    Get-ChildItem -path ../src -Filter *.psd1 -Recurse -File -Exclude 'GR-ComplianceCheck*' | Import-Module -Force 

    # manually import localization module due to directory structure
    Import-Module ../src/Guardrails-Localization/GR-ComplianceChecks.psd1

    # install marketplace module
    Install-Module -Name Az.Marketplace -Scope CurrentUser 

    # setting local environment variables
    $config = Get-GSAExportedConfig -KeyVaultName $keyVaultName -yes | Select-Object -Expand configString | ConvertFrom-Json | Select-Object -ExcludeProperty runtime
    $config.psobject.properties | ForEach-Object {
        Write-Host "Setting environment variable: $($_.Name) = $($_.Value.ToString())"
        [System.Environment]::SetEnvironmentVariable($_.Name, $_.Value.ToString(), [System.EnvironmentVariableTarget]::Process)
    }
    ## overwrite config vars with runtime full values
    $config = Get-GSAExportedConfig -KeyVaultName $keyVaultName -yes | Select-Object -Expand configString | ConvertFrom-Json | Select-Object -Expand runtime
    $config.psobject.properties | ForEach-Object {
        Write-Host "Setting environment variable: $($_.Name) = $($_.Value.ToString())"
        [System.Environment]::SetEnvironmentVariable($_.Name, $_.Value.ToString(), [System.EnvironmentVariableTarget]::Process)
    }

    # manually set additional variables
    #[System.Environment]::SetEnvironmentVariable('GuardRailsLocale', '', [System.EnvironmentVariableTarget]::Process)
    [System.Environment]::SetEnvironmentVariable('ResourceGroupName', $env:ResourceGroup, [System.EnvironmentVariableTarget]::Process)
    [System.Environment]::SetEnvironmentVariable('GuardrailWorkspaceIDKeyName', 'WorkSpaceKey', [System.EnvironmentVariableTarget]::Process)
    [System.Environment]::SetEnvironmentVariable('LogType', 'GuardrailsCompliance', [System.EnvironmentVariableTarget]::Process)
    [System.Environment]::SetEnvironmentVariable('WorkSpaceID', (Get-AzOperationalInsightsWorkspace -ResourceGroupName $env:ResourceGroup -Name $env:logAnalyticsworkspaceName).CustomerId, [System.EnvironmentVariableTarget]::Process)
    [System.Environment]::SetEnvironmentVariable('ContainerName', 'guardrailsstorage', [System.EnvironmentVariableTarget]::Process)
    [System.Environment]::SetEnvironmentVariable('ReservedSubnetList', "GatewaySubnet,AzureFirewallSubnet,AzureBastionSubnet,AzureFirewallManagementSubnet,RouteServerSubnet", [System.EnvironmentVariableTarget]::Process)
}

#Standard variables
$WorkSpaceID = Get-GSAAutomationVariable -Name "WorkSpaceID" 
$LogType = Get-GSAAutomationVariable -Name "LogType" 
$KeyVaultName = Get-GSAAutomationVariable -Name "KeyvaultName" 
$GuardrailWorkspaceIDKeyName = Get-GSAAutomationVariable -Name "GuardrailWorkspaceIDKeyName" 
$ResourceGroupName = Get-GSAAutomationVariable -Name "ResourceGroupName"
# This is one of the valid date format (ISO-8601) that can be sorted properly in KQL
$ReportTime = (get-date).tostring("yyyy-MM-dd HH:mm:ss")
$StorageAccountName = Get-GSAAutomationVariable -Name "StorageAccountName" 
$Locale = Get-GSAAutomationVariable -Name "GuardRailsLocale"

If ($Locale -eq $null) {
    $Locale = "en-CA"
}

try {
    $RuntimeConfig = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'gsaConfigExportLatest' -AsPlainText -ErrorAction Stop | ConvertFrom-Json | Select-Object -Expand runtime
    Set-AzContext -SubscriptionId $RuntimeConfig.subscriptionId
}
catch {
    throw "Failed to retrieve config json with secret name gsaConfigExportLatest from KeyVault '$KeyVaultName'. Error message: $_"
}

$SubID = (Get-AzContext).Subscription.Id
$tenantID = (Get-AzContext).Tenant.Id
Write-Output "Starting main runbooks."
Write-Output "Reading configuration file."
read-blob -FilePath ".\modules.json" -resourcegroup $ResourceGroupName -storageaccountName $StorageAccountName -containerName "configuration" | Out-Null
try {
    $modulesList = Get-Content .\modules.json
}
catch {
    Write-Error "Couldn't find module configuration file."    
    break
}
$modules = $modulesList | convertfrom-json

Write-Output "Found $($modules.Count) modules."

If ($localExecution.IsPresent -and $modulesToExecute.IsPresent) {
    Write-Output "Running locally and filtering modules to those specified in the -modulesToExecute parameter."
    
    $modules = $modules | Where-Object { $modulesToExecute.Value -icontains $_.ModuleName }
    Write-Output "Running only $($modules.Count) modules: $($modules.name -join ', ')"
}

Write-Output "Reading required secrets."
try {
    [String] $WorkspaceKey = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $GuardrailWorkspaceIDKeyName -AsPlainText -ErrorAction Stop
}
catch {
    throw "Failed to retrieve workspace key with secret name '$GuardrailWorkspaceIDKeyName' from KeyVault '$KeyVaultName'. Error message: $_"
}

Add-LogEntry 'Information' "Starting execution of main runbook" -workspaceGuid $WorkSpaceID -workspaceKey $WorkspaceKey -moduleName main `
    -additionalValues @{reportTime = $ReportTime; locale = $locale }

# This loads the file containing all of the messages in the culture specified in the automation account variable "GuardRailsLocale"
$messagesFileName = "GR-ComplianceChecks-Msgs"
if (Get-Module -Name GR-ComplianceChecks) {
    $messagesBaseDirectory = (Get-Module -Name GR-ComplianceChecks).path | Get-Item | Select-Object -Expand Directory | Select-Object -Expand FullName
}
else {
    # module is not imported preemptively in Automation Account
    $messagesBaseDirectory = (Get-Module -Name GR-ComplianceChecks -ListAvailable).path | Get-Item | Select-Object -Expand Directory | Select-Object -Expand FullName
}
$messagesBindingVariableName = "msgTable"
Write-Output "Loading messages in '$($Locale)'"
#dir 'C:\Modules\User\GR-ComplianceChecks'
try {
    Import-LocalizedData -BindingVariable $messagesBindingVariableName -UICulture $Locale -FileName $messagesFileName -BaseDirectory $messagesBaseDirectory #-ErrorAction SilentlyContinue
}
catch {
    $sanitizedScriptblock = $($ExecutionContext.InvokeCommand.ExpandString(($module.script -ireplace '\$workspaceKey', '***')))
            
    Add-LogEntry 'Error' "Failed to load message table for main module. script: '$sanitizedScriptblock' `
        with error: $_" -workspaceGuid $WorkSpaceID -workspaceKey $WorkspaceKey -moduleName main
    Write-Error "Failed to load messages table for main module."
    Write-Output "Content of messages specified directory: $messagesBaseDirectory."
    Get-ChildItem $messagesBaseDirectory
    break
}
Write-Output "Loaded $($msgTable.Count) messages." 
Write-Output "Starting modules loop."
foreach ($module in $modules) {
    if ($module.Status -eq "Enabled") {
        $NewScriptBlock = [scriptblock]::Create($module.Script)
        Write-Output "Processing Module $($module.modulename)" 
        $variables = $module.variables
        $secrets = $module.secrets
        $localVariables = $module.localVariables
        $vars = [PSCustomObject]@{}          
        if ($null -ne $variables) {
            foreach ($v in $variables) {
                $tempvarvalue = Get-GSAAutomationVariable -Name $v.value
                $vars | Add-Member -MemberType Noteproperty -Name $($v.Name) -Value $tempvarvalue
            }      
        }
        if ($null -ne $secrets) {
            foreach ($v in $secrets) {
                $tempvarvalue = Get-AzKeyVaultSecret -VaultName $KeyVaultName -AsPlainText -Name $v.value
                $vars | Add-Member -MemberType Noteproperty -Name $($v.Name) -Value $tempvarvalue
            }
        }
        if ($null -ne $localVariables) {
            foreach ($v in $localVariables) {
                $vars | Add-Member -MemberType Noteproperty -Name $($v.Name) -Value $v.value
            }
        }
        #$vars
        #Write-host $module.Script

        try {
            $results = $NewScriptBlock.Invoke()
            #$results.ComplianceResults
            #$results.Add("Required", $module.Required)
            #Write-Output "required: $($module.Required)."
            $results.ComplianceResults | Add-Member -MemberType Noteproperty -Name "Required" -Value $module.Required
            #"Results Required: $($results.ComplianceResults.Required)"
            New-LogAnalyticsData -Data $results.ComplianceResults -WorkSpaceID $WorkSpaceID -WorkSpaceKey $WorkspaceKey -LogType $LogType | Out-Null
            if ($null -ne $results.Errors) {
                "Module $($module.modulename) failed with $($results.Errors.count) errors."
                New-LogAnalyticsData -Data $results.errors -WorkSpaceID $WorkSpaceID -WorkSpaceKey $WorkspaceKey -LogType "GuardrailsComplianceException" | Out-Null
            }
            if ($null -ne $results.AdditionalResults) {
                # There is more data!
                "Module $($module.modulename) returned $($results.AdditionalResults.count) additional results."
                New-LogAnalyticsData -Data $results.AdditionalResults.records -WorkSpaceID $WorkSpaceID `
                    -WorkSpaceKey $WorkspaceKey -LogType $results.AdditionalResults.logType | Out-Null
            }
        }
        catch {
            $sanitizedScriptblock = $($ExecutionContext.InvokeCommand.ExpandString(($module.script -ireplace '\$workspaceKey', '***')))
            
            Add-LogEntry 'Error' "Failed invoke the module execution script for module '$($module.moduleName)', script '$sanitizedScriptblock' `
                with error: $_" -workspaceGuid $WorkSpaceID -workspaceKey $WorkspaceKey -moduleName main
            Write-Error "Failed invoke the module execution script for module '$($module.moduleName)', script '$sanitizedScriptblock' with error: $_"
        }
    }
    else {
        Write-Output "Skipping module $($module.ModuleName). Disabled in the configuration file (modules.json)."
    }
}

Add-LogEntry 'Information' "Completed execution of main runbook" -workspaceGuid $WorkSpaceID -workspaceKey $WorkspaceKey -moduleName main `
    -additionalValues @{reportTime = $ReportTime; locale = $locale }

# SIG # Begin signature block
# MIInqgYJKoZIhvcNAQcCoIInmzCCJ5cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB6t1/OQitxFVvc
# CKBF68qwUugg09+EP8bpHV67gpo1wqCCDYEwggX/MIID56ADAgECAhMzAAACzI61
# lqa90clOAAAAAALMMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjIwNTEyMjA0NjAxWhcNMjMwNTExMjA0NjAxWjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQCiTbHs68bADvNud97NzcdP0zh0mRr4VpDv68KobjQFybVAuVgiINf9aG2zQtWK
# No6+2X2Ix65KGcBXuZyEi0oBUAAGnIe5O5q/Y0Ij0WwDyMWaVad2Te4r1Eic3HWH
# UfiiNjF0ETHKg3qa7DCyUqwsR9q5SaXuHlYCwM+m59Nl3jKnYnKLLfzhl13wImV9
# DF8N76ANkRyK6BYoc9I6hHF2MCTQYWbQ4fXgzKhgzj4zeabWgfu+ZJCiFLkogvc0
# RVb0x3DtyxMbl/3e45Eu+sn/x6EVwbJZVvtQYcmdGF1yAYht+JnNmWwAxL8MgHMz
# xEcoY1Q1JtstiY3+u3ulGMvhAgMBAAGjggF+MIIBejAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUiLhHjTKWzIqVIp+sM2rOHH11rfQw
# UAYDVR0RBEkwR6RFMEMxKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMRYwFAYDVQQFEw0yMzAwMTIrNDcwNTI5MB8GA1UdIwQYMBaAFEhu
# ZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNpZ1BDQTIwMTFfMjAxMS0w
# Ny0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUFBzAChkVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0NvZFNpZ1BDQTIwMTFfMjAx
# MS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAeA8D
# sOAHS53MTIHYu8bbXrO6yQtRD6JfyMWeXaLu3Nc8PDnFc1efYq/F3MGx/aiwNbcs
# J2MU7BKNWTP5JQVBA2GNIeR3mScXqnOsv1XqXPvZeISDVWLaBQzceItdIwgo6B13
# vxlkkSYMvB0Dr3Yw7/W9U4Wk5K/RDOnIGvmKqKi3AwyxlV1mpefy729FKaWT7edB
# d3I4+hldMY8sdfDPjWRtJzjMjXZs41OUOwtHccPazjjC7KndzvZHx/0VWL8n0NT/
# 404vftnXKifMZkS4p2sB3oK+6kCcsyWsgS/3eYGw1Fe4MOnin1RhgrW1rHPODJTG
# AUOmW4wc3Q6KKr2zve7sMDZe9tfylonPwhk971rX8qGw6LkrGFv31IJeJSe/aUbG
# dUDPkbrABbVvPElgoj5eP3REqx5jdfkQw7tOdWkhn0jDUh2uQen9Atj3RkJyHuR0
# GUsJVMWFJdkIO/gFwzoOGlHNsmxvpANV86/1qgb1oZXdrURpzJp53MsDaBY/pxOc
# J0Cvg6uWs3kQWgKk5aBzvsX95BzdItHTpVMtVPW4q41XEvbFmUP1n6oL5rdNdrTM
# j/HXMRk1KCksax1Vxo3qv+13cCsZAaQNaIAvt5LvkshZkDZIP//0Hnq7NnWeYR3z
# 4oFiw9N2n3bb9baQWuWPswG0Dq9YT9kb+Cs4qIIwggd6MIIFYqADAgECAgphDpDS
# AAAAAAADMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMTAeFw0xMTA3MDgyMDU5MDlaFw0yNjA3MDgyMTA5MDla
# MH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMT
# H01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQCr8PpyEBwurdhuqoIQTTS68rZYIZ9CGypr6VpQqrgG
# OBoESbp/wwwe3TdrxhLYC/A4wpkGsMg51QEUMULTiQ15ZId+lGAkbK+eSZzpaF7S
# 35tTsgosw6/ZqSuuegmv15ZZymAaBelmdugyUiYSL+erCFDPs0S3XdjELgN1q2jz
# y23zOlyhFvRGuuA4ZKxuZDV4pqBjDy3TQJP4494HDdVceaVJKecNvqATd76UPe/7
# 4ytaEB9NViiienLgEjq3SV7Y7e1DkYPZe7J7hhvZPrGMXeiJT4Qa8qEvWeSQOy2u
# M1jFtz7+MtOzAz2xsq+SOH7SnYAs9U5WkSE1JcM5bmR/U7qcD60ZI4TL9LoDho33
# X/DQUr+MlIe8wCF0JV8YKLbMJyg4JZg5SjbPfLGSrhwjp6lm7GEfauEoSZ1fiOIl
# XdMhSz5SxLVXPyQD8NF6Wy/VI+NwXQ9RRnez+ADhvKwCgl/bwBWzvRvUVUvnOaEP
# 6SNJvBi4RHxF5MHDcnrgcuck379GmcXvwhxX24ON7E1JMKerjt/sW5+v/N2wZuLB
# l4F77dbtS+dJKacTKKanfWeA5opieF+yL4TXV5xcv3coKPHtbcMojyyPQDdPweGF
# RInECUzF1KVDL3SV9274eCBYLBNdYJWaPk8zhNqwiBfenk70lrC8RqBsmNLg1oiM
# CwIDAQABo4IB7TCCAekwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFEhuZOVQ
# BdOCqhc3NyK1bajKdQKVMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1Ud
# DwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO
# 4eqnxzHRI4k0MFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwubWljcm9zb2Z0
# LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcmwwXgYIKwYBBQUHAQEEUjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcnQwgZ8GA1UdIASBlzCBlDCBkQYJKwYBBAGCNy4DMIGDMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2RvY3MvcHJpbWFyeWNw
# cy5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AcABvAGwAaQBjAHkA
# XwBzAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAGfyhqWY
# 4FR5Gi7T2HRnIpsLlhHhY5KZQpZ90nkMkMFlXy4sPvjDctFtg/6+P+gKyju/R6mj
# 82nbY78iNaWXXWWEkH2LRlBV2AySfNIaSxzzPEKLUtCw/WvjPgcuKZvmPRul1LUd
# d5Q54ulkyUQ9eHoj8xN9ppB0g430yyYCRirCihC7pKkFDJvtaPpoLpWgKj8qa1hJ
# Yx8JaW5amJbkg/TAj/NGK978O9C9Ne9uJa7lryft0N3zDq+ZKJeYTQ49C/IIidYf
# wzIY4vDFLc5bnrRJOQrGCsLGra7lstnbFYhRRVg4MnEnGn+x9Cf43iw6IGmYslmJ
# aG5vp7d0w0AFBqYBKig+gj8TTWYLwLNN9eGPfxxvFX1Fp3blQCplo8NdUmKGwx1j
# NpeG39rz+PIWoZon4c2ll9DuXWNB41sHnIc+BncG0QaxdR8UvmFhtfDcxhsEvt9B
# xw4o7t5lL+yX9qFcltgA1qFGvVnzl6UJS0gQmYAf0AApxbGbpT9Fdx41xtKiop96
# eiL6SJUfq/tHI4D1nvi/a7dLl+LrdXga7Oo3mXkYS//WsyNodeav+vyL6wuA6mk7
# r/ww7QRMjt/fdW1jkT3RnVZOT7+AVyKheBEyIXrvQQqxP/uozKRdwaGIm1dxVk5I
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZfzCCGXsCAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAsyOtZamvdHJTgAAAAACzDAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgLWOVvIRV
# Au3+TBhhiHEcugWKMPPGR8Au/9aknVgyWuQwQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQCAHhdj7emh9pdExT9ghRXwVF0xYek/xOoWA2n7qo3f
# GD8u3pX+rmaYx7lHOY8UoLWtNjCPdTM908ix3oCDIplWNM8evQnfAT06HMidETqb
# jyPUch0UAzsFhTp/qDPKCl5uURJkwHwRr+CKmQIXskngsoZQ2HrkSY5TjlxbjAvV
# UoMjB/CzT6/E/jB0Rx2b3yVOQg7xhXsclfeDIfXaFCT653q3aCPcmF5BKILfplQK
# U7rVsEpAnpsTyTkAxE9+mHrhvXEy+ljcyW6FHOazqPdozQaRx/Yps886WZrQvLgj
# DcFZ2g0hvpyFEf78YfQkOCe4BvcslKQF+ZNJ5GRktGtloYIXCTCCFwUGCisGAQQB
# gjcDAwExghb1MIIW8QYJKoZIhvcNAQcCoIIW4jCCFt4CAQMxDzANBglghkgBZQME
# AgEFADCCAVUGCyqGSIb3DQEJEAEEoIIBRASCAUAwggE8AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIITeD+DZYreZoeVC5FM8u9mvz8nCP9ztLSG3Canb
# QonWAgZjxoxkCtwYEzIwMjMwMjA2MTUwOTIyLjI0NlowBIACAfSggdSkgdEwgc4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1p
# Y3Jvc29mdCBPcGVyYXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMg
# VFNTIEVTTjpDNEJELUUzN0YtNUZGQzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgU2VydmljZaCCEVwwggcQMIIE+KADAgECAhMzAAABo/uas457hkNPAAEA
# AAGjMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# MB4XDTIyMDMwMjE4NTExNloXDTIzMDUxMTE4NTExNlowgc4xCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVy
# YXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpDNEJE
# LUUzN0YtNUZGQzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vydmlj
# ZTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAO+9TcrLeyoKcCqLbNtz
# 7Nt2JbP1TEzzMhi84gS6YLI7CF6dVSA5I1bFCHcw6ZF2eF8Qiaf0o2XSXf/jp5sg
# mUYtMbGi4neAtWSNK5yht4iyQhBxn0TIQqF+NisiBxW+ehMYWEbFI+7cSdX/dWw+
# /Y8/Mu9uq3XCK5P2G+ZibVwOVH95+IiTGnmocxWgds0qlBpa1rYg3bl8XVe5L2qT
# UmJBvnQpx2bUru70lt2/HoU5bBbLKAhCPpxy4nmsrdOR3Gv4UbfAmtpQntP758NR
# Phg1bACH06FlvbIyP8/uRs3x2323daaGpJQYQoZpABg62rFDTJ4+e06tt+xbfvp8
# M9lo8a1agfxZQ1pIT1VnJdaO98gWMiMW65deFUiUR+WngQVfv2gLsv6o7+Ocpzy6
# RHZIm6WEGZ9LBt571NfCsx5z0Ilvr6SzN0QbaWJTLIWbXwbUVKYebrXEVFMyhuVG
# QHesZB+VwV386hYonMxs0jvM8GpOcx0xLyym42XA99VSpsuivTJg4o8a1ACJbTBV
# FoEA3VrFSYzOdQ6vzXxrxw6i/T138m+XF+yKtAEnhp+UeAMhlw7jP99EAlgGUl0K
# kcBjTYTz+jEyPgKadrU1of5oFi/q9YDlrVv9H4JsVe8GHMOkPTNoB4028j88OEe4
# 26BsfcXLki0phPp7irW0AbRdAgMBAAGjggE2MIIBMjAdBgNVHQ4EFgQUUFH7szwm
# CLHPTS9Bo2irLnJji6owHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIw
# XwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
# cy9jcmwvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3Js
# MGwGCCsGAQUFBwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENB
# JTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcD
# CDANBgkqhkiG9w0BAQsFAAOCAgEAWvLep2mXw6iuBxGu0PsstmXI5gLmgPkTKQnj
# gZlsoeipsta9oku0MTVxlHVdcdBbFcVHMLRRkUFIkfKnaclyl5eyj03weD6b/pUf
# FyDZB8AZpGUXhTYLNR8PepM6yD6g+0E1nH0MhOGoE6XFufkbn6eIdNTGuWwBeEr2
# DNiGhDGlwaUH5ELz3htuyMyWKAgYF28C4iyyhYdvlG9VN6JnC4mc/EIt50BCHp8Z
# QAk7HC3ROltg1gu5NjGaSVdisai5OJWf6e5sYQdDBNYKXJdiHei1N7K+L5s1vV+C
# 6d3TsF9+ANpioBDAOGnFSYt4P+utW11i37iLLLb926pCL4Ly++GU0wlzYfn7n22R
# yQmvD11oyiZHhmRssDBqsA+nvCVtfnH183Df5oBBVskzZcJTUjCxaagDK7AqB6QA
# 3H7l/2SFeeqfX/Dtdle4B+vPV4lq1CCs0A1LB9lmzS0vxoRDusY80DQi10K3SfZK
# 1hyyaj9a8pbZG0BsBp2Nwc4xtODEeBTWoAzF9ko4V6d09uFFpJrLoV+e8cJU/hT3
# +SlW7dnr5dtYvziHTpZuuRv4KU6F3OQzNpHf7cBLpWKRXRjGYdVnAGb8NzW6wWTj
# ZjMCNdCFG7pkKLMOGdqPDFdfk+EYE5RSG9yxS76cPfXqRKVtJZScIF64ejnXbFIs
# 5bh8KwEwggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3
# DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIw
# MAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAx
# MDAeFw0yMTA5MzAxODIyMjVaFw0zMDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
# 5OGmTOe0ciELeaLL1yR5vQ7VgtP97pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/
# XE/HZveVU3Fa4n5KWv64NmeFRiMMtY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1
# hlDcwUTIcVxRMTegCjhuje3XD9gmU3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7
# M62AW36MEBydUv626GIl3GoPz130/o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3K
# Ni1wjjHINSi947SHJMPgyY9+tVSP3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy
# 1cCGMFxPLOJiss254o2I5JasAUq7vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF80
# 3RKJ1v2lIH1+/NmeRd+2ci/bfV+AutuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQc
# NIIP8BDyt0cY7afomXw/TNuvXsLz1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahha
# YQFzymeiXtcodgLiMxhy16cg8ML6EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkL
# iWHzNgY1GIRH29wb0f2y1BzFa/ZcUlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV
# 2xo3xwgVGD94q0W29R6HXtqPnhZyacaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIG
# CSsGAQQBgjcVAQQFAgMBAAEwIwYJKwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUp
# zxD/LwTuMB0GA1UdDgQWBBSfpxVdAF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBT
# MFEGDCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYI
# KwYBBQUHAwgwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGG
# MA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186a
# GMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3Br
# aS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsG
# AQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcN
# AQELBQADggIBAJ1VffwqreEsH2cBMSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1
# OdfCcTY/2mRsfNB1OW27DzHkwo/7bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYA
# A7AFvonoaeC6Ce5732pvvinLbtg/SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbz
# aN9l9qRWqveVtihVJ9AkvUCgvxm2EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6L
# GYnn8AtqgcKBGUIZUnWKNsIdw2FzLixre24/LAl4FOmRsqlb30mjdAy87JGA0j3m
# Sj5mO0+7hvoyGtmW9I/2kQH2zsZ0/fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0
# SCyxTkctwRQEcb9k+SS+c23Kjgm9swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxko
# JLo4S5pu+yFUa2pFEUep8beuyOiJXk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFm
# PWn9y8FBSX5+k77L+DvktxW/tM4+pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC482
# 2rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7
# vzhwRNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYICzzCC
# AjgCAQEwgfyhgdSkgdEwgc4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1ZXJ0byBSaWNv
# MSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpDNEJELUUzN0YtNUZGQzElMCMGA1UE
# AxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUA
# Hl/pXkLMAbPapCwa+GXc3SlDDROggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMDANBgkqhkiG9w0BAQUFAAIFAOeLZ7kwIhgPMjAyMzAyMDYxNTQ5
# MTNaGA8yMDIzMDIwNzE1NDkxM1owdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA54tn
# uQIBADAHAgEAAgIafzAHAgEAAgISSTAKAgUA54y5OQIBADA2BgorBgEEAYRZCgQC
# MSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqG
# SIb3DQEBBQUAA4GBAA760/O0SGBvPwULkFPxPjQd7Kcko6aEG9OZg8wBFEmj1n7b
# /7vLw7Y2PS6iPIVsk4so8pyaVKMwoc8jmIEAsl6DWrNm+eXHIx5KYqVla25Wmsqp
# jX9A/jYfeUEtTGI85Z6AhiUMXVfiAbjSJxT+mtZEj2vU9U5U8Kl4KkAPUqwCMYIE
# DTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGj
# +5qzjnuGQ08AAQAAAaMwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzEN
# BgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgEpY02XAd88iKoyeevBsm2yEp
# nMrlobeOthLq0QcrP94wgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCCM+Liw
# BnHMMoOd/sgbaYxpwvEJlREZl/pTPklz6euN/jCBmDCBgKR+MHwxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABo/uas457hkNPAAEAAAGjMCIEIKHaSnbq
# CCANYijEilJ1AoZz0Vmx1INIVR3wMzxkkXHxMA0GCSqGSIb3DQEBCwUABIICAOAg
# pMwGWivBSuHwCwGYrKNss1ZxGHvVanPupdJUcMdkMTNxZWuUUda7KvyXSQtsv4+9
# t0Fc05MBCMT2QOs4Nd+DyUe5YprxqgS8vsMTphUsRE7QjBt4qkqfC3HZaM7nENO/
# f/5KGHgFFCkSKrHKDHbay4mqbmGZlGwDnaGvK5JNXG/5OoxK1pZXxYeZ8SkmIymR
# 8cMtwiAIMGBpbZuSkdt7wna5y3W1/WaFoNY5I56CFubnMnhEzoyOqjZ64gmQL6r0
# l0wyek4DS6rmFaqBix7M40/qOjlO/a8QBF1oIqfFC8W7XmU1OstjMbVhIkdlxYnN
# vduHbe/rUCbpQefqNRPCsYhO6dp/k6CH5XGin8lPPIDdRl+LaSY13QYD9rWEeAFo
# A6om4dcNwSng2HswnGtUaDxiDTtAqPv1F5RTFD0ILoHWkDjD4NwHiodDPKn7pbFV
# yOVynr1zu8cGneK2fBidzculEjzOfaASvM/aH/oDSpTrM8ZKKURcEsU+PqxeByn2
# yMExxoMHREyWswmY3LtDgo36H0D1SGJ8OcVHhzGFFV5Q9/u8jodCy2JNH83BuKGh
# 1euy9uKef3TlcDqKCnG2Oaxd6OzqfCTWgWazjQ0M2OZOurZWbXBMVTJuD6GUxNSm
# z8oLhvJYXybSsUZJ6zHql7KukNVheG7WXTrb6Pe0
# SIG # End signature block
