#New-ModuleManifest -Path .\Check-BreakGlassAccountOwnersInformation.psd1 -Author "FastTrack for Azure Team" -CompanyName Microsoft -ModuleVersion 1.0.0 -Tags "GOC 30 days Guardrails"
function Generate-Manifest {
    [CmdletBinding()]
    param (
    
        [String] $DirectoryPath, 
        [String] $ModuleVersion,
        [Parameter(Mandatory=$true)]
        [string][string] $ModulesFolder,
        [switch] $interactive
    )
    if ([string]::IsNullOrEmpty($DirectoryPath))
    {
        $DirectoryPath="."
    }
    if ($interactive)
    {
        $PSM1Files = Get-ChildItem -Path $($DirectoryPath + "\*")-include *.psm1 -File -Recurse | Select-Object LastWriteTime, Name,FullName, BaseName, Directory | Out-GridView -PassThru
    }
    else {
        $PSM1Files = Get-ChildItem -Path $($DirectoryPath + "\")-include *.psm1 -File -Recurse
    }
    $overriteAll=$false

    Write-Output "Found '$($PSM1Files.count)' PSm1 Files"

    $currentFolder=(pwd).Path
    foreach ($file in $PSM1Files) {
        #change to folder containing the file
        "Working on $($file.FullName)"
        Set-Location -Path $file.Directory
        pwd
        #look for manifest. If exists, skip creation
        $manifestFileName=$($file.BaseName+".psd1")
        if (Get-ChildItem -Path $manifestFileName -ErrorAction SilentlyContinue)
        {
            "Using existing manifest."
        }
        else {
            "File $manifestFileName not found."
            "Creating new manifest."
            New-ModuleManifest -Path $manifestFileName -Author "FastTrack for Azure Team" -CompanyName Microsoft -ModuleVersion $ModuleVersion -Tags "GOC 30 days Guardrails" `
                               -RootModule $(".\"+$file.Name) -FunctionsToExport '*' -VariablesToExport '*'  -Confirm                                    
        }
        #create zip file from both files in the Modules Target folder.
        
        if ($PSVersionTable.Platform -ne 'Unix')
        {
            $targetFileName="$($ModulesFolder)\$($file.BaseName).zip"
            "Creating $targetFileName file."
            if ((get-item $targetFileName -ErrorAction SilentlyContinue) -and !$overriteAll)
            {
                Write-Output "File $targetFileName already exists. Overwrite? (Y/N/A)"
                $answer=(Read-Host).ToUpper()
                if ($answer -eq 'Y')
                {
                    Compress-Archive -Path ".\$($file.BaseName).*" -DestinationPath $targetFileName -Force
                }
                else {
                    if ($answer -eq 'A') {
                        $overriteAll = $true
                    }
                    else {
                        "Skipping..."
                    }
                }
            }
            else {
                Compress-Archive -Path ".\$($file.BaseName).*" -DestinationPath $targetFileName -Force
            }
        }
        else {
            $targetFileName="$($ModulesFolder)/$($file.BaseName).zip"
            "Creating $targetFileName file."
            if ((get-item $targetFileName -ErrorAction SilentlyContinue) -and !$overriteAll)
            {
                Write-Output "File $targetFileName already exists. Overwrite? (Y/N/A)"
                $answer=(Read-Host).ToUpper()
                if ($answer -eq 'Y')
                {
                    Compress-Archive -Path ".\$($file.BaseName).*" -DestinationPath $targetFileName -Force
                }
                else {
                    if ($answer -eq 'A') {
                        $overriteAll = $true
                    }
                    else {
                        "Skipping..."
                    }
                }
            }
            else {
                Compress-Archive -Path "./$($file.BaseName).*" -DestinationPath $targetFileName -Force
            }
        }
    }
    Set-Location -Path $currentFolder
}
# SIG # Begin signature block
# MIInzAYJKoZIhvcNAQcCoIInvTCCJ7kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBCTHazpWKdVlD/
# YWTnoIMWRyAqummXIQJGpf7dXhI7CKCCDYEwggX/MIID56ADAgECAhMzAAACzI61
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
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZoTCCGZ0CAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAsyOtZamvdHJTgAAAAACzDAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgTQVA9lBJ
# U8dDoV7+zNXT8NkGx5tqbKLQzA8c3yvAqd0wQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQAoicXDA/sTwB+ruyF8j7NPlN53PowJl7Z+KB0cuyjg
# XrZXBASD/Gs/kpncdDTI9vRzffE7T4dGy4w64/6OCijK+KlEcNcN4C/LJQ12OvHO
# ZXMVx2gi3oZ3e5/XDCgff2aaQoT/Rdd27XiAP6U9FPWwhxjc3s5d7ZXq9C+Zedf6
# jsJF9m0j7IESWi5KrhOiK2CD02rzIYsYMxVHiC6cASAypejgIjecYw89FV5twqdR
# Q5JbqkFoBf0k4o7hxADbJ2PNekBVDDJNaXoMBjZwHITvUnhc0kdtngJhk1IEfiPP
# Eif236kQ0uXw8nRyAF1rUDnJPvumgn4xr2tVjRoie04boYIXKzCCFycGCisGAQQB
# gjcDAwExghcXMIIXEwYJKoZIhvcNAQcCoIIXBDCCFwACAQMxDzANBglghkgBZQME
# AgEFADCCAVgGCyqGSIb3DQEJEAEEoIIBRwSCAUMwggE/AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIBExpBLQaxvl0UJzcaUIwggR527iWQgxrz3mXvc1
# 9SoDAgZjx9zmbBcYEjIwMjMwMTI1MjIyNTQ0LjY3WjAEgAIB9KCB2KSB1TCB0jEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWlj
# cm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVkMSYwJAYDVQQLEx1UaGFs
# ZXMgVFNTIEVTTjpGQzQxLTRCRDQtRDIyMDElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaCCEXswggcnMIIFD6ADAgECAhMzAAABufYADWVUT7wD
# AAEAAAG5MA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMB4XDTIyMDkyMDIwMjIxN1oXDTIzMTIxNDIwMjIxN1owgdIxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJ
# cmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhhbGVzIFRTUyBF
# U046RkM0MS00QkQ0LUQyMjAxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDjST7JYfUW
# x8kBAm1CCDcTBebkJMjdO1SEoSE17my6VpwDYAQi7wnCZe6P9hxzkZ7EXJkiDSf6
# nJQJiyKzo52J626HAJ4sYjBFwvmtbGfOKsWFrRFWO1WMNCwnM2PvOlP/LIYMarGn
# syqVq4jznKVdUofErDsX99Mju475XfyAQN0+pRzNqU/x0Y1pP6/bssdEOGrcdJpC
# 1WEvcuef6E5SixNNIe/dkvpmmnQHct1YE8HosKBDlw+/OcL94fn8B/8E0LQvZYQM
# YTDuKfjj/fPPFsZG5egakVl7neeEU86qdla/snp9UNQOrpsjAe16tLJyGBuQdQHH
# OFICZT0P2YjJKoMUDRQlkL89BvaC4Ejw/CstAJF9tj3Azm6D7jU+EXHlj19FFWVL
# F/SFILO0BeNR4kEsBHjjhxsq30HZkrJQE625h/9fDOUK7EzOSSDY3LfRuNsajfFR
# fWfFjohjIzW75aXBJpsrGJeUMoaxA6BZ0E1O2xaw9yV9HyH7tbGy1ngal8G6eGfM
# gAk7aYStlW8zr4uL3NEQpkTc72EENj42ezWk1xOBrt74IACfq7c1EwHyaLbzkqnD
# IDcC2WtWPhE/5W9Fco62MBbh7YNEFskIz+d+dC06b9POqclVIeAN8PzrOYUxhWYB
# XuWwsjJ6WNPTNMj3R2kP+eqGFLEiHMislQIDAQABo4IBSTCCAUUwHQYDVR0OBBYE
# FLewOHHbWEOaCYxNWaq0qJ6eNURSMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWn
# G1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEw
# KDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFt
# cCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAww
# CgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQDN
# 3GezRVB0TLCys45e6yTyJL+6CfrPZJLrdIWYn/VkretEs2BlC6dc5nT6nPsPHh05
# Ial9Bigqdk06kswVwYcBzpvPqeoVMTZQ3sBjGVKLPedmk125QE9zigZ31QS0MlGr
# 60o7iRmQFt9HDWN641Q1JRg/lcoEB8kmg2r4iUGyuv+n0L1FBaKiJN5XRn45wLZ3
# m7FZaoellmplXOQGXaVkdY0szf6MSmKnNQRuEscZT7XH6wHQc/3FOG8VV6gAH9Nj
# WbHLyTaUZzgC3+ZFaNh7qSVwrJPU8z+TzVtrE0t05sISEJj8a9BNFKjqI1KwSVDo
# WyEwMXJ0mvyDJbi9R10bS0GSPsbNnkbbjzlLClFu9f9WHqrGAixy77vNnHg1UELz
# +xhxBJKdpBI4qH242BKwaNoghGscXl+GfR7wIAODLEJG5+nuBBUH9d7D/ip914DC
# LyW6iyXhXEI2vklHjl7uXH5MXtBs0zaI3ciMM2h5YTn5VUWTa8XntwfsmcHdyRwy
# L7+9bkiP0iM87fXFNhsh0FasQUq0bSlulvFcO86Vb6FbCL95Y8YPuzYhkpV19bO8
# 2wTQzFI/Tp8zpRyv95qzlPGBLkX+kcGpFuVAnhmpsuTIirtmLsiohgQr+DhoT7LT
# XuwC5BDofAV9dreJ7bmLvoMPS+sgj2NI1mGkLcwD/TCCB3EwggVZoAMCAQICEzMA
# AAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290
# IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMw
# MDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3u
# nAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1
# jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP2CZT
# fDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/PXfT+
# jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361VI/c
# +gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwBSru+
# cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9X4C6
# 26p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV
# 2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoS
# CtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxS
# UV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJp
# xq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkr
# BgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0A
# XmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYI
# KwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9S
# ZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIE
# DB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNV
# HSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVo
# dHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29D
# ZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAC
# hj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1
# dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwEx
# JFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts
# 0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9I
# dQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/GbYS
# EhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3DYXMu
# LGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT9
# 9kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqOCb2z
# AVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I6Ile
# T53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6l
# MVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbh
# IurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3u
# gm2lBRDBcQZqELQdVTNYs6FwZvKhggLXMIICQAIBATCCAQChgdikgdUwgdIxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jv
# c29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhhbGVz
# IFRTUyBFU046RkM0MS00QkQ0LUQyMjAxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMVAMdiHhh4ZOfDEJM80lpJxnC4
# 34E6oIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZI
# hvcNAQEFBQACBQDne5W1MCIYDzIwMjMwMTI1MTk0OTA5WhgPMjAyMzAxMjYxOTQ5
# MDlaMHcwPQYKKwYBBAGEWQoEATEvMC0wCgIFAOd7lbUCAQAwCgIBAAICC9cCAf8w
# BwIBAAICEVQwCgIFAOd85zUCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGE
# WQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOBgQCF
# +S1d+BoAiOJAiidW0eduFEkqQrEqIGR485+j2wRw1bK3N64zECwP/SsKT7IGGCvR
# KltPdDBng02ea4GU7sxG2HN4r4L9gpwBUW687pVSL9TKUTrnFtIowDttmZXUVmHd
# 2sR+vHnHerfAumPF/Cdm5HsIWFPPOes71WKjs0gFEzGCBA0wggQJAgEBMIGTMHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABufYADWVUT7wDAAEAAAG5
# MA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQw
# LwYJKoZIhvcNAQkEMSIEIL+GGujzu5UkBt382p3Rm6W3MYj0xmoP+4FycXW8x8sE
# MIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgZOtGzvFvObkwHyVRDt719mi2
# kBXIHBqXcLDqIvn6D/QwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMAITMwAAAbn2AA1lVE+8AwABAAABuTAiBCBZr+DXH/6svUvSoTNldjeHdK+b
# o9WiYN9UrHIBiz5wxzANBgkqhkiG9w0BAQsFAASCAgCx1tzq3gCass5PEKBX5A84
# yk9fsn+/tRxBXN6hdWE+6tCN7+ua1XZNngl20YRb1qtKTUGQCYpH6/+JiXe84Bdv
# /Nu5q45C88QajrLh+NxZAfZk/p8LrkhDPNBwu2lf7AhfQVqLEIhU2OP2FJZcQCm2
# b7qXhuyGbLYmOkbCDf2uNdt3Cmb2/CfjDtCqByUzwpt0Z6P34pg5jK3SHiUaddi+
# M8l614xxMFxgX6B8GC6UKgPAXYBL+Orq67259qBZASyJldgHUrUZQVt1pFvhhN5h
# tWVJ8pFqVCiBXxLntP0EfpsbR/l8fK+MLKEJZz9OXYLPh+heTV2kPstEhPpjBztX
# GwP78JZj+2SO35lBiOHKTMY/6RESKxvk2q8t/F8W8S/mfmSIX7iEgydE2dzo3m2N
# SkaxNgIS+1knyE4EekwFUjjrkh6Rncd7IFFOfAuQisPkHUeyYpjXxSWQv6T/wu8B
# LtoqPigeFmvcs2GAeTMUwvQTmEAu2o+cSxdfGdXiYJdiipmEGpYAkCr1TtDU0j6c
# 0mjLuLD3wUKADh7sEm4QSdBfRKlUhoxNvFIMr86w7EabBBbr40twgzyrStE4xtpe
# c9f8D/qTI+JgcxkR+6lcL3IOy0xzJ5nnpYZke/t+hBq4aGucFwf2X2FqF4HQoHtu
# vS5xKQgniHD6swzUSF5GDg==
# SIG # End signature block
