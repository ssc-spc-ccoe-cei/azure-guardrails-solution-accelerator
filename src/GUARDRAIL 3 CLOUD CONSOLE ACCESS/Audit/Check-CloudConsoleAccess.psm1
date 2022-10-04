
function Get-CloudConsoleAccess {
    param (      
        #[Parameter(Mandatory=$true)]
        [string] $ControlName,
        #[Parameter(Mandatory=$true)]
        [string] $ItemName,
        #[Parameter(Mandatory=$true)]
        [string] $WorkSpaceID,
        #[Parameter(Mandatory=$true)]
        [string] $workspaceKey,
        #[Parameter(Mandatory=$true)]
        [string] $LogType,
        #[Parameter(Mandatory=$true)]
        [string] $itsgcode,
        #[Parameter(Mandatory=$true)]
        [hashtable] $msgTable,
        #[Parameter(Mandatory=$true)]
        [string] $ReportTime
    )
    #[PSCustomObject] $FinalObjectList = New-Object System.Collections.ArrayList
    [String] $GraphAccessToken = (Get-AzAccessToken -ResourceTypeName MSGraph).Token
    $IsCompliant = $false
    Write-Debug "Token: $GraphAccessToken"
    $locationsBaseAPIUrl = "https://graph.microsoft.com/v1.0/identity/conditionalAccess/namedLocations"
    $CABaseAPIUrl = "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies"
    try {
        $locations = (Invoke-RestMethod -Headers @{Authorization = "Bearer $($GraphAccessToken)" } -Uri $locationsBaseAPIUrl -Method Get -ErrorAction Stop).value
    }
    catch {
        Add-LogEntry 'Error' "Failed to call Microsoft Graph REST API at URL '$locationsBaseAPIUrl'; returned error message: $_" -workspaceGuid $WorkSpaceID -workspaceKey $WorkSpaceKey
        Write-Error "Error: Failed to call Microsoft Graph REST API at URL '$locationsBaseAPIUrl'; returned error message: $_"
    }
    # $locations
    $validLocations = @()
    foreach ($location in $locations) {
        #Determine location conditions
        #get all valid locations: needs to have Canada Only
        if ($location.countriesAndRegions.Count -eq 1 -and $location.countriesAndRegions -eq "CA") {
            $validLocations += $location
        }
    }
    if ($validLocations.count -ne 0) {
        #if there is at least one location with Canada only, we are good. If no Canada Only policy, not compliant.
        # Conditional access Policies
        # Need a location based policy, for admins (owners, contributors) that uses one of the valid locations above.
        # If there is no policy or the policy doesn't use one of the locations above, not compliant.

        try {
            $caps = (Invoke-RestMethod -Headers @{Authorization = "Bearer $($GraphAccessToken)" } -Uri $CABaseAPIUrl -Method Get -ErrorAction Stop).value

            $validPolicies = $caps | Where-Object { $_.conditions.locations.includeLocations -in $validLocations.ID -and $cap.state -eq 'enabled' }
        }
        catch {
            Add-LogEntry 'Error' "Failed to call Microsoft Graph REST API at URL '$CABaseAPIUrl'; returned error message: $_" -workspaceGuid $WorkSpaceID -workspaceKey $WorkSpaceKey
            Write-Error "Error: Failed to call Microsoft Graph REST API at URL '$CABaseAPIUrl'; returned error message: $_"
        }
        if (!$validPolicies) {
            #failed. No policies have valid locations.
            $Comments = $msgTable.noCompliantPoliciesfound
            $IsCompliant = $false
        }
        else {
            "Compliant Policies."
            $IsCompliant = $true
            $Comments = $msgTable.allPoliciesAreCompliant
        }      
    }
    else {
        # Failed. Reason: No locations have only Canada.
        $Comments = $msgTable.noLocationsCompliant
        $IsCompliant = $false
    }
    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        Comments         = $Comments
        ItemName         = $ItemName
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }
    $JsonObject = convertTo-Json -inputObject $PsObject 

    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
        -sharedkey $workspaceKey `
        -body $JsonObject `
        -logType $LogType `
        -TimeStampField Get-Date 
}

# SIG # Begin signature block
# MIInoQYJKoZIhvcNAQcCoIInkjCCJ44CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCbbZFiAtB3lkrR
# DX1jd8YDQk0MX3gSrMFMW7HfrgmdzKCCDYEwggX/MIID56ADAgECAhMzAAACzI61
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
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZdjCCGXICAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAsyOtZamvdHJTgAAAAACzDAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg2Pyus7nb
# WIdM9hAoyLGpzDa/kvz9Pe5FoKCKAGo23J4wQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQBzPiXabyOuYJdHyiNz3T92El2efoHSmwglns0X+Rfq
# tWSwKXlUm6ucan4RHeOJTLu/Ym1mZ0mg7/XXr7zxSYiaVzM9faVB/rxODrfy5tEn
# KBxc91Raz4XYUFXboM4EIlwarehTZUqQYpTd0n+mE/k0mM4RAm6xK4N4zmbr5Mji
# 0zvmKEIt2oxbsFM7DHXLyAJq26KsWnLuAjPfOT40ogvv97z1JBd5zYGp9tEEyQOq
# kR8h+GdyNli+j+P0c+hZ5+c93wLl9q7WyFSRgsXXHclFFEkWawJdo4rJgF/M9ygU
# 1AOdTbwJHGp7trap2FSyTjqtzSk17/7bbv8V/JPj2hMvoYIXADCCFvwGCisGAQQB
# gjcDAwExghbsMIIW6AYJKoZIhvcNAQcCoIIW2TCCFtUCAQMxDzANBglghkgBZQME
# AgEFADCCAVEGCyqGSIb3DQEJEAEEoIIBQASCATwwggE4AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIErEJPPv5L9+gu/Id7NjIrX38tpeSLE8qiVG19ZT
# d2+TAgZjIxYn8SIYEzIwMjIxMDA0MTQzOTE1LjMzOFowBIACAfSggdCkgc0wgcox
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1p
# Y3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJjAkBgNVBAsTHVRoYWxlcyBUU1Mg
# RVNOOkQ2QkQtRTNFNy0xNjg1MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNloIIRVzCCBwwwggT0oAMCAQICEzMAAAGe/cIt2DFatrEAAQAAAZ4w
# DQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcN
# MjExMjAyMTkwNTIwWhcNMjMwMjI4MTkwNTIwWjCByjELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2Eg
# T3BlcmF0aW9uczEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046RDZCRC1FM0U3LTE2
# ODUxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDu6VylSHXD8Da8XkVNIqDgwWpTrhL5
# XXBaw2Zzerm2srxV+NpL/Zv7pVASO/TDGhAEMcwZTxyajt8I4vZ4DnnF9TD4tP6E
# E5Qx1LQQoZAjq55UH9qqpc1nwRJNBlQi+WdAV7IiGjQBe8J+WYV3yvDqlEYFC5VM
# e8OsB7yOMpFrAIZq3DhPpTLJM1LRdNEVAtGFlLT5BbBw3FG6EgfQt6DifBYtsZqu
# hPAaER9PIALFQxA138+ihNRZJMJUMhXYaAS6oLRN6pYZDDoXy4qqcGGeINsRBRZ9
# 1TN6lQgad8Cna+qH0tDQsQSJQfv74nJdgzkIpvz/DnvUFNZ9vqmh2OxNn82pX4nL
# uzAZCP4+zmFGYPAlo6ycnTc9Y8XNu8XVJYvno8uYYigRdRm2AYIfw04DYFhURE9h
# kckKIhxjqERNRxA0ZeHTUHA5t6ZS3xTOJOWgeB5W3PRhuAQyhITjGaUQUAgSyXzD
# zrOakNTVbjj7+X8OGsFtR8OYPzBe7l31SLvudNOq8Sxh2VA+WoGmdzhf+W7JmIEG
# Ato//9u8HUtnoNzJK/dwS2MYucnimlOrxKVrnq9jv1hpgmHPobWHnnLhAgXnH4Sj
# abyPkF1CZd8I2DLC56I4weWpcrtp+TdhpvwBFvWi6onTs1uSFg4UBAotOVJjdXNK
# +01JVZF7nxs1cQIDAQABo4IBNjCCATIwHQYDVR0OBBYEFGjTPoPRdY6XPtQkSTro
# h9lkZbutMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRY
# MFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01p
# Y3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEF
# BQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
# a2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAo
# MSkuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZI
# hvcNAQELBQADggIBAFS5VY6hmc8GH2D18v+STQA+A+gT1duE3yuNn1mH41TLquzV
# NLW03AzAvuucYea1VaitRE5UYbIzxUsV9G8sTrXbdiczeVG66IpLullh4Ixqfn+x
# zGbPOZWUT6wAtgXq3FfMGY9k73qo/IQ5shoToeMhBmHLWeg53+tBcu8SzocSHJTi
# eWcv5KmnAtoJra5SmDdZdFBCz0cP3IUq4kedN0Q2KhKrMDRAeD/CCza2DX8Bj9tR
# ePycTnvfsScCc5VsxDNCannq8tVJ+HQazRVK8ANW2UMDgV63i7SKGb3+slKI/Y92
# ouMrTFhai6h4rCojzSsQtJQTCcnI0QTDoextzmaLsmtKu3jF2Ayh8gFed+KRDiDh
# tNcyZoJm+fmqaKhTIi9guPoed7wvn5zde93Zr6RXBTtXL0dlR0FMw/wPQVJjLVEa
# EnYWnKZH9lU8XZJV+xOmWFBFZkd+RnVOW3ZW5eBGsLeuzDCAamruyotw4PD36T6e
# YGJv5YvrX1iRYADrxXCUYidrZJY2s0IVZFicqGgp5FtYYnAMpE7tyuIj2o4y+ol1
# by3lQV6Ob0P4RnK6gnuECWBfmWSjevOfr+02mkseW8oREHAm9y9XfcdUcQ57vbba
# u8+AQia8wGQcNXpxAnoLDwJ+RAycDlpe3e2Yha9nXuYzcVMk92r/bKI0fyGOMIIH
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
# qzqKOghif9lwY1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGCAs4wggI3AgEBMIH4
# oYHQpIHNMIHKMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUw
# IwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMSYwJAYDVQQLEx1U
# aGFsZXMgVFNTIEVTTjpENkJELUUzRTctMTY4NTElMCMGA1UEAxMcTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAAhXCOZBbDxA/B5Te
# i6Rf80L9GheggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAN
# BgkqhkiG9w0BAQUFAAIFAObmoG0wIhgPMjAyMjEwMDQyMDA3MDlaGA8yMDIyMTAw
# NTIwMDcwOVowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA5uagbQIBADAKAgEAAgIM
# kwIB/zAHAgEAAgISkzAKAgUA5ufx7QIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgor
# BgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBBQUA
# A4GBAET/tgZLTkZFMYiCyN4i0X6GCUaohrSnnyZF8RS77PhUY8v4dy9JjYQCUNKi
# +AK7TldFAXLYPrGjQSjwAyIZQkHArDBdmPelHcjz5OmKmHQeOtljwSI6N/lHXQhn
# WqlcyvgxD2ci6J15+XyMQ937IjkUQD/71zcVXR3yyUV+OmWaMYIEDTCCBAkCAQEw
# gZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGe/cIt2DFatrEA
# AQAAAZ4wDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0B
# CRABBDAvBgkqhkiG9w0BCQQxIgQgBOMJy/ecJx9inePHIouImMtP1G01QNRiQ9Dl
# NGUJxN4wgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAOxVYyIv5cj0+pZkJu
# rJ+yCrq0Re5XgrkfStUO/W88GTCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwAhMzAAABnv3CLdgxWraxAAEAAAGeMCIEIPCNylWAKRCx6xWNYL21
# ILW7oHHRcB/bkw0iN+bZXkN3MA0GCSqGSIb3DQEBCwUABIICACH8lCo2iStT+cuJ
# aBavlG23geU8iL2fKiYn5O008uuBpzbTcq/V8c4AIMK2pI6dWFMyBNtqEaFBnDpG
# obfgNXm/wlEO/06yoNDnT8sL6q9VpPSJFOpX2pj/OyOMn2EBSxF4wLSsBrRDQ94Q
# ptpczeXZPz1EreaS+FNSqD0zp7bbn4sv/+wBsyuq6qsb4HENbWzbfvqO525+1ao7
# B0RKjwnGzeIFcq1uDLV+zFXHZi1vS19TWQg7xbsDv3pECmznhmH5z6OApx8cr1jo
# 2BoEw/8FlDT02YBPEr6AqldEU/gpU+3rwSnEFAEENgmgZltQx5AkIv06Fj1z/5on
# snMv1M99JmXILcAURhtaCbm2s0ZG8eU7hSYNbygdLofhWDBqu2UX4+Pd4+Uz/oD8
# 1XDUOY6mp2pDGs5++TRA+11xSXHUrl8IEcHy/R8ZD8gm7AgR7FfomA4kA6JicUJp
# ZRHH/88bc0u6YJPi/YF7pBTESp+BeTNqfBCKQ2L+5BsI0UBI9LHASgoHzVIa3epj
# nZEwWvHCmjwqcBMbommND5PdTOPCJMv8LmfGMVTywpA10hTkZQVG608v4Fj07KrL
# 0U+6Avs84UFklZma50xusekr9JAHwU2cvGGN0som87558F+oFQaZEZf0oWfcrXDh
# RkHBYOsLolo+HJe1uvaSMXv3KLkJ
# SIG # End signature block
