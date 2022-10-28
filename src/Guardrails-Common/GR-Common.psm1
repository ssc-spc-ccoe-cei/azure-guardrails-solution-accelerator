function get-tagValue {
    param (
        [string] $tagKey,
        [System.Object] $object
    )
    $tagString = get-tagstring($object)
    $tagslist = $tagString.split(";")
    foreach ($tag in $tagslist) {
        if ($tag.split("=")[0] -eq $tagKey) {
            return $tag.split("=")[1]
        }
    }
    return ""
}
function get-tagstring ($object) {
    if ($object.Tag.Count -eq 0) {
        $tagstring = "None"
    }
    else {
        $tagstring = ""
        $tKeys = $object.tag | Select-Object -ExpandProperty keys
        $tValues = $object.Tag | Select-Object -ExpandProperty values
        $index = 0
        if ($object.Tag.Count -eq 1) {
            $tagstring = "$tKeys=$tValues"
        }
        else {
            foreach ($tkey in $tkeys) {
                $tagstring += "$tkey=$($tValues[$index]);"
                $index++
            }
        }
    }
    return $tagstring.Trim(";")
}
function get-rgtagstring ($object) {
    if ($object.Tags.Count -eq 0) {
        $tagstring = "None"
    }
    else {
        $tagstring = ""
        $tKeys = $object.tags | Select-Object -ExpandProperty keys
        $tValues = $object.Tags | Select-Object -ExpandProperty values
        $index = 0
        if ($object.Tags.Count -eq 1) {
            $tagstring = "$tKeys=$tValues"
        }
        else {
            foreach ($tkey in $tkeys) {
                $tagstring += "$tkey=$($tValues[$index]);"
                $index++
            }
        }
    }
    return $tagstring.Trim(";")
}
function get-rgtagValue {
    param (
        [string] $tagKey,
        [System.Object] $object
    )
    $tagString = get-rgtagstring($object)
    $tagslist = $tagString.split(";")
    foreach ($tag in $tagslist) {
        if ($tag.split("=")[0] -eq $tagKey) {
            return $tag.split("=")[1]
        }
    }
    return ""
}
function copy-toBlob {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $FilePath,
        [Parameter(Mandatory = $true)]
        [string]
        $storageaccountName,
        [Parameter(Mandatory = $true)]
        [string]
        $resourcegroup,
        [Parameter(Mandatory = $true)]
        [string]
        $containerName,
        [Parameter(Mandatory = $false)]
        [switch]
        $force
    )
    try {
        $saParams = @{
            ResourceGroupName = $resourcegroup
            Name              = $storageaccountName
        }
        $scParams = @{
            Container = $containerName
        }
        $bcParams = @{
            File = $FilePath
            Blob = ($FilePath | Split-Path -Leaf)
        }
        if ($force)
        { Get-AzStorageAccount @saParams | Get-AzStorageContainer @scParams | Set-AzStorageBlobContent @bcParams -Force | Out-Null}
        else { Get-AzStorageAccount @saParams | Get-AzStorageContainer @scParams | Set-AzStorageBlobContent @bcParams | Out-Null }
    }
    catch {
        Write-Error $_.Exception.Message
    }
}
function get-blobs {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $storageaccountName,
        [Parameter(Mandatory = $true)]
        [string]
        $resourcegroup
    )
    $psModulesContainerName = "psmodules"
    try {
        $saParams = @{
            ResourceGroupName = $resourcegroup
            Name              = $storageaccountName
        }

        $scParams = @{
            Container = $psModulesContainerName
        }
        return (Get-AzStorageAccount @saParams | Get-AzStorageContainer @scParams | Get-AzStorageBlob)
    }
    catch {
        Write-Error $_.Exception.Message
    }
}

function read-blob {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $FilePath,
        [Parameter(Mandatory = $true)]
        [string]
        $storageaccountName,
        [Parameter(Mandatory = $true)]
        [string]
        $resourcegroup,
        [Parameter(Mandatory = $true)]
        [string]
        $containerName,
        [Parameter(Mandatory = $false)]
        [switch]
        $force
    )
    $Context = (Get-AzStorageAccount -ResourceGroupName $resourcegroup -Name $storageaccountName).Context
    $blobParams = @{
        Blob        = 'modules.json'
        Container   = $containerName
        Destination = $FilePath
        Context     = $Context
    }
    Get-AzStorageBlobContent @blobParams
    
}

Function Add-LogEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True, Position = 0)]
        [ValidateSet("Critical", "Error", "Warning", "Information", "Debug")]
        [string]
        $severity,

        # message details (string)
        [Parameter(Mandatory = $true, Position = 1)]
        [string]
        $message,

        # module name
        [Parameter(Mandatory = $false)]
        [string]
        $moduleName = (Split-Path -Path $MyInvocation.ScriptName -Leaf),

        # additional values in hashtable
        [Parameter(Mandatory = $false)]
        [hashtable]
        $additionalValues = @{},

        # exception log type - this is the Log Analytics table name
        [Parameter(Mandatory = $false)]
        [string]
        $exceptionLogTable = "GuardrailsComplianceException",

        # guardrails exception workspace GUID
        [Parameter(Mandatory = $true)]
        [string]
        $workspaceGuid,

        # guardrails exception workspace shared key
        [Parameter(Mandatory = $true)]
        [string]
        $workspaceKey
    )

    # build log entry object, convert to json
    $entryHash = @{
        "message" = $message
        "moduleName" = $moduleName
        "severity" = $severity
    } + $additionalValues
    
    $entryJson = ConvertTo-Json -inputObject $entryHash -Depth 20

    # log event to Log Analytics workspace by REST API via the OMSIngestionAPI community PS module
    Send-OMSAPIIngestionFile  -customerId $workspaceGuid `
        -sharedkey $workspaceKey `
        -body $entryJson `
        -logType $exceptionLogTable `
        -TimeStampField Get-Date 

}
Function Add-TenantInfo {
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $WorkSpaceID,
        [Parameter(Mandatory=$true)]
        [string]
        $workspaceKey,
        [Parameter(Mandatory=$false)]
        [string]
        $LogType="GR_TenantInfo",
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime,
        [Parameter(Mandatory=$true)]
        [string]
        $TenantId
        )
    $tenantInfo=Get-AutomationVariable("tenantDomainUPN")
    $object = [PSCustomObject]@{ 
        TenantDomain = $tenantInfo
        DepartmentTenantID = $TenantId
        ReportTime = $ReportTime
    }
    Write-Output $tenantInfo
    $JSON= ConvertTo-Json -inputObject $object

    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
    -sharedkey $workspaceKey `
    -body $JSON `
    -logType $LogType `
    -TimeStampField Get-Date 
}

function Check-DocumentExistsInStorage {
    param (
        [string] $StorageAccountName,
        [string] $ContainerName, 
        [string] $ResourceGroupName,
        [string] $SubscriptionID, 
        [string] $DocumentName, 
        [string] $ControlName, 
        [string]$ItemName,
        [hashtable] $msgTable, 
        [string] $WorkSpaceID, 
        [string] $workspaceKey, 
        [string] $LogType,
        [string]$itsgcode,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime
    )

    [bool] $IsCompliant = $false
    [string] $Comments = $null

    try {
        Connect-AzAccount -Identity -Subscription  $SubscriptionID -ErrorAction Stop
    }
    catch {
        Add-LogEntry 'Error' "Failed to run 'Connect-AzAccount' with error: $_" -workspaceKey $workspaceKey -workspaceGuid $WorkSpaceID
        throw "Error: Failed to run 'Connect-AzAccount' with error: $_"
    }

    try {
        $StorageAccount = Get-Azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction Stop
    }
    catch {
        Add-LogEntry 'Error' "Could not find storage account '$storageAccountName' in resoruce group '$resourceGroupName' of `
            subscription '$subscriptionId'; verify that the storage account exists and that you have permissions to it. Error: $_" `
            -workspaceKey $workspaceKey -workspaceGuid $WorkSpaceID
        Write-Error "Could not find storage account '$storageAccountName' in resoruce group '$resourceGroupName' of `
            subscription '$subscriptionId'; verify that the storage account exists and that you have permissions to it. Error: $_"
    }

    # check for procedure doc in blob storage account
    $blobs = Get-AzStorageBlob -Container $ContainerName -Context $StorageAccount.Context -Blob $DocumentName -ErrorAction SilentlyContinue

    If ($blobs) {
        # a blob with the name $DocumentName was located in the specified storage account
        $IsCompliant = $True
        $Comments = $msgTable.procedureFileFound -f $DocumentName
    }
    else {
        # no blob with the name $DocumentName was found in the specified storage account
        $Comments = $msgTable.procedureFileNotFound -f $ItemName, $DocumentName, $ContainerName, $StorageAccountName
    }

    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        ItemName         = $ItemName
        DocumentName     = $DocumentName
        Comments         = $Comments
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }
    $JsonObject = convertTo-Json -inputObject $PsObject 
    Send-OMSAPIIngestionFile -customerId $WorkSpaceID  -sharedkey $workspaceKey -body $JsonObject -logType $LogType -TimeStampField Get-Date 
}

function Check-UpdateAvailable {
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $WorkSpaceID,
        [Parameter(Mandatory=$true)]
        [string]
        $workspaceKey,
        [Parameter(Mandatory=$false)]
        [string]
        $LogType="GR_VersionInfo",
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime,
        [Parameter(Mandatory=$false)]
        [string]
        $ResourceGroupName
    )
    #fetches current public version (from repo...maybe should download the zip...)
    $ReleaseVersion=((Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/Azure/GuardrailsSolutionAccelerator/main/setup/tags.json).content | ConvertFrom-Json).ReleaseVersion
    if ([string]::IsNullOrEmpty($ResourceGroupName)) {
        $ResourceGroupName=Get-AutomationVariable -Name "ResourceGroupName"
    }
    $rg=Get-AzResourceGroup -Name $ResourceGroupName 
    $currentVersion=get-rgtagValue -tagkey releaseversion -object $rg
    Write-Output "RG Tag: $currentVersion"
    Write-Output "Avail. Release: $ReleaseVersion"
    
    if ($currentVersion -ne $ReleaseVersion)
    {
        $updateNeeded=$true
    }
    else {
        $updateNeeded=$false
    }
    $object = [PSCustomObject]@{ 
        CurrentVersion = $currentVersion
        AvailableVersion = $ReleaseVersion
        UpdateNeeded= $updateNeeded
        ReportTime = $ReportTime
    }
    $JSON= ConvertTo-Json -inputObject $object

    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
    -sharedkey $workspaceKey `
    -body $JSON `
    -logType $LogType `
    -TimeStampField Get-Date 
}
function get-itsgdata {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $URL,
        [string] $WorkSpaceID,
        [string] $workspaceKey,
        [string] $LogType="GRITSGControls",
        [switch] $DebugCode
    )
    (Invoke-WebRequest -UseBasicParsing $URL).Content | out-file tempitsg.csv
    $Header="Family","Control ID","Enhancement","Name","Class","Definition","Supplemental Guidance,References"
    $itsgtempinfo=Import-Csv ./tempitsg.csv -Header $Header
    $itsginfo=$itsgtempinfo | Select-Object Name,Definition, @{Name="itsgcode";Expression={ ($_.Family + $_."Control ID" + $_.Enhancement).replace("`t","") }}
    $JSONcontrols = ConvertTo-Json -inputObject $itsginfo
    
    if ($DebugCode) {
        $JSONcontrols
    }

    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
   -sharedkey $workspaceKey `
   -body $JSONcontrols `
   -logType $LogType `
   -TimeStampField Get-Date
}
# endregion

# SIG # Begin signature block
# MIInngYJKoZIhvcNAQcCoIInjzCCJ4sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBGe8wUHfwvaU5H
# 7LJQ/Z6C3bqjHUai21Fj5+mXaLrqvqCCDYEwggX/MIID56ADAgECAhMzAAACzI61
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
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZczCCGW8CAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAsyOtZamvdHJTgAAAAACzDAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg4CrTVaT8
# v/f0WgpzS1Eofz99p5rG4JdLFXr10oJJE4YwQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQAN1j4Z4hD5HgxDD0MQ3NAFoqurzMIPUrZmLUQUeE5K
# T+3mbhrAngcEM5EBcGDZYRrC2hwk80kBLQkoRxiaLz4pAynKpsEnR2P2hQg9Y2xZ
# aB9LinBvWYw0G+Z0Sq228tsdpL5cAuhsw2VU205g5JSokd8cDT6aPp4Wn5KuYheX
# u3ZN2X64QcDTGx8077cqrbHeDTN0/JMRusGYaAtOKkxow4VpTrexykpZSJ89+6ny
# NSW82hoYIIP3+FZyo29B6nt2/O9niCzJkTIZIKMNUB0+dtiYq4wJVULMGM6qi/B9
# 8vDYI7XyamWgPrf6jRczOlU+yjX53sMVXhmD2LkQcqrgoYIW/TCCFvkGCisGAQQB
# gjcDAwExghbpMIIW5QYJKoZIhvcNAQcCoIIW1jCCFtICAQMxDzANBglghkgBZQME
# AgEFADCCAVEGCyqGSIb3DQEJEAEEoIIBQASCATwwggE4AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIJJ4NGJ+P/CsSUO2hHIfMmftBehNlnjpjUH68PZU
# ajKHAgZjI12tJdIYEzIwMjIxMDA0MTQzOTEzLjEyM1owBIACAfSggdCkgc0wgcox
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1p
# Y3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJjAkBgNVBAsTHVRoYWxlcyBUU1Mg
# RVNOOjQ5QkMtRTM3QS0yMzNDMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNloIIRVDCCBwwwggT0oAMCAQICEzMAAAGXA89ZnGuJeD8AAQAAAZcw
# DQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcN
# MjExMjAyMTkwNTE0WhcNMjMwMjI4MTkwNTE0WjCByjELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2Eg
# T3BlcmF0aW9uczEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046NDlCQy1FMzdBLTIz
# M0MxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDtAErqSkFN8/Ce/csrHVWcv1iSjNTA
# rPKEMqKPUTpYJX8TBZl88LNrpw4bEpPimO+Etcli5RBoZEieo+SzYUnb0+nKEWaE
# Ygubgp+HTFZiD85Lld7mk2Xg91KMDE2yMeOIH2DHpTsn5p0Lf0CDlfPE5HOwpP5/
# vsUxNeDWMW6zsSuKU69aL7Ocyk36VMyCKjHNML67VmZMJBO7bX1vYVShOvQqZUkx
# CpCR3szmxHT09s6nhwLeNCz7nMnU7PEiNGVxSYu+V0ETppFpK7THcGYAMa3SYZjQ
# xGyDOc7J20kEud6tz5ArSRzG47qscDfPYqv1+akex81w395E+1kc4uukfn0CeKtA
# Dum7PqRrbRMD7wyFnX2FvyaytGj0uaKuMXFJsZ+wfdk0RsuPeWHtVz4MRCEwfYr1
# c+JTkmS3n/pvHr/b853do28LoPHezk3dSxbniQojW3BTYJLmrUei/n4BHK5mTT8N
# uxG6zoP3t8HVmhCW//i2sFwxVHPsyQ6sdrxs/hapsPR5sti2ITG/Hge4SeH7Sne9
# 42OHeA/T7sOSJXAhhx9VyUiEUUax+dKIV7Gu67rjq5SVr5VNS4bduOpLsWEjeGHp
# Mei//3xd8dxZ42G/EDkr5+L7UFxIuBAq+r8diP/D8yR/du7vc4RGKw1ppxpo4JH9
# MnYfd+zUDuUgcQIDAQABo4IBNjCCATIwHQYDVR0OBBYEFG3PAc8o6zBullUL0bG+
# 3X69FQBgMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRY
# MFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01p
# Y3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEF
# BQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
# a2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAo
# MSkuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZI
# hvcNAQELBQADggIBAARI2GHSJO0zHnshct+Hgu4dsPU0b0yUsDXBhAdAGdH1T+uD
# eq3c3Hp7v5C4QowSEqp0t/eDlFHhH+hkvm8QlVZR8hIf+hJZ3OqtKGpyZPg7HNzY
# IGzRS2fKilUObhbYK6ajeq7KRg+kGgZ16Ku8N13XncDCwmQgyCb/yzEkpsgF5Pza
# 2etSeA2Y2jy7uXW4TSGwwCrVuK9Drd9Aiev5Wpgm9hPRb/Q9bukDeqHihw2OJfpn
# x32SPHwvu4E8j8ezGJ8KP/yYVG+lUFg7Ko/tjl2LlkCeNMNIcxk1QU8e36eEVdRw
# eNc9FEcIyqomDgPrdfpvRXRHztD3eKnAYhcEzM4xA0i0k5F6Qe0eUuLduDouemOz
# RoKjn9GUcKM2RIOD7FXuph5rfsv84pM2OqYfek0BrcG8/+sNCIYRi+ABtUcQhDPt
# YxZJixZ5Q8VkjfqYKOBRjpXnfwKRC0PAzwEOIBzL6q47x6nKSI/QffbKrAOHznYF
# 5abV60X4+TD+3xc7dD52IW7saCKqN16aPhV+lGyba1M30ecB7CutvRfBjxATa2nS
# FF03ZvRSJLEyYHiE3IopdVoMs4UJ2Iuex+kPSuM4fyNsQJk5tpZYuf14S8Ov5A1A
# +9Livjsv0BrwuvUevjtXAnkTaAISe9jAhEPOkmExGLQqKNg3jfJPpdIZHg32MIIH
# cTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAAAAAAFTANBgkqhkiG9w0BAQsFADCB
# iDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMp
# TWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMjEw
# OTMwMTgyMjI1WhcNMzAwOTMwMTgzMjI1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAOThpkzntHIh
# C3miy9ckeb0O1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDivbk+F2Az/1xPx2b3lVNx
# WuJ+Slr+uDZnhUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU88V29YZQ3MFEyHFc
# UTE3oAo4bo3t1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqYO7oaezOtgFt+jBAc
# nVL+tuhiJdxqD89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzpcGkNyjYtcI4xyDUo
# veO0hyTD4MmPfrVUj9z6BVWYbWg7mka97aSueik3rMvrg0XnRm7KMtXAhjBcTyzi
# YrLNueKNiOSWrAFKu75xqRdbZ2De+JKRHh09/SDPc31BmkZ1zcRfNN0Sidb9pSB9
# fvzZnkXftnIv231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZNN3SUHDSCD/AQ8rdH
# GO2n6Jl8P0zbr17C89XYcz1DTsEzOUyOArxCaC4Q6oRRRuLRvWoYWmEBc8pnol7X
# KHYC4jMYctenIPDC+hIK12NvDMk2ZItboKaDIV1fMHSRlJTYuVD5C4lh8zYGNRiE
# R9vcG9H9stQcxWv2XFJRXRLbJbqvUAV6bMURHXLvjflSxIUXk8A8FdsaN8cIFRg/
# eKtFtvUeh17aj54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB2TASBgkrBgEEAYI3
# FQEEBQIDAQABMCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSavoKRPEY1Kc8Q/y8E7jAd
# BgNVHQ4EFgQUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0gBFUwUzBRBgwrBgEE
# AYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUFBwMI
# MBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMB
# Af8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1Ud
# HwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3By
# b2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQRO
# MEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2Vy
# dHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MA0GCSqGSIb3DQEBCwUAA4IC
# AQCdVX38Kq3hLB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOXPTEztTnXwnE2P9pk
# bHzQdTltuw8x5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjYNi6cqYJWAAOwBb6J6Gng
# ugnue99qb74py27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/zjj3G82jfZfakVqr3
# lbYoVSfQJL1AoL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz/AyeixmJ5/ALaoHC
# gRlCGVJ1ijbCHcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyRgNI95ko+ZjtPu4b6
# MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdUbZ1jdEgssU5HLcEU
# BHG/ZPkkvnNtyo4JvbMBV0lUZNlz138eW0QBjloZkWsNn6Qo3GcZKCS6OEuabvsh
# VGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4Ku+xBZj1p/cvBQUl+
# fpO+y/g75LcVv7TOPqUxUYS8vwLBgqJ7Fx0ViY1w/ue10CgaiQuPNtq6TPmb/wrp
# NPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9vMvpe784cETRkPHI
# qzqKOghif9lwY1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGCAsswggI0AgEBMIH4
# oYHQpIHNMIHKMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUw
# IwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMSYwJAYDVQQLEx1U
# aGFsZXMgVFNTIEVTTjo0OUJDLUUzN0EtMjMzQzElMCMGA1UEAxMcTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAYUDSsI2YSTTNTXYN
# g0YxTcHWY9GggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAN
# BgkqhkiG9w0BAQUFAAIFAObmP4QwIhgPMjAyMjEwMDQxMzEzNDBaGA8yMDIyMTAw
# NTEzMTM0MFowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA5uY/hAIBADAHAgEAAgIF
# PDAHAgEAAgISUTAKAgUA5ueRBAIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEE
# AYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBBQUAA4GB
# ACIBDbclNZFY/LNvOvPaYdIIh/iPXXDbY8IxOXAG4h92IS/sPtoCErAPKTXwFsQD
# KmehP3fm6UEf6BaI/PQE170P14zRbLij/JZxfAdufCbfweUHvLiMDYMit0TW+mnx
# QfCPr8qQifNKngT5plQ6Nqq3ArAeT65gVZMVZjIruICUMYIEDTCCBAkCAQEwgZMw
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGXA89ZnGuJeD8AAQAA
# AZcwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRAB
# BDAvBgkqhkiG9w0BCQQxIgQgBN5yNvtMmQRmrVWo/d1ger5OD7oaifs2d7H6rHQe
# smQwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCBbe9obEJV6OP4EDMVJ8zF8
# dD5vHGSoLDwuQxj9BnimvzCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAABlwPPWZxriXg/AAEAAAGXMCIEIIYlnC1Z2Wr0P+w+KHHwH+Fc
# I8jDxtFpVa7lI0RlP659MA0GCSqGSIb3DQEBCwUABIICANUt2ftLlZcYpJiypEsQ
# GRsfmQKOHfvxP87HdtYnLDDcW4uTThkisPIwRIamzmHG6i/IiE6ZWs8N7AVjU4kV
# AHZv0SBnfM9UcXQ0WJv4xPzP6JwufnFeYjb6ZngsCKUYAIBAQPKLIoVCKH3CsYYQ
# 3Lnz97Bz+z7uwqs4C6Xx5CfvxVHSmAAX6d1xWwtq+bPzjTqWHnu/784WLIK2CBFk
# zizGz6rvQuMqs64rDixxD6xcx0PwanaHx9z7+XVXCyiPWZWYUcTf+7iDys8Hi7Gn
# mOaZtq/0sHBjfxCQsQ5lmR9wjyo3fDrfrt8RdfaMPOW1VjF/7gR6IQ3p3pUqEAeT
# 7C9kxpdiA02fgn3XXWDL42fa6yTy2XD8V9qi/FrkSxeiMpVMR8y/z3xp8x0lS7oc
# XCEPM9UgMCPZTGvVGB4exucQ5xT8wnur8nFgRlju3vijSE2hpXXDZTpVapBy+umi
# lmA3MN/Z+AS0bZ9RJ7lyY8wdU/pAKDXWu6Yznf7IjDpL4uxWc1SnSuqr3taNjrX0
# taGjVCdVmyWjOkum9ZK4w6QZQnlUNtkMniV44fo81KKNaFQlRHWj8iJ5YpGkk23w
# VukPCYWA/+i3J5JnXXRbtBMJUoyNSqTIgYEMTjfDkP8ekbqLY6S2NNl8q9Pw7R5E
# +tP23A75kXNb8RJY3zq74Srz
# SIG # End signature block
