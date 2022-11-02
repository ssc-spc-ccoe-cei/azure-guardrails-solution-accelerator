
Function Show-GSADeploymentSummary {
    param (
        # parameters from deploy function call
        [Parameter(Mandatory=$true)]
        [psobject]
        $deployParams,
        
        # deploy function parameter set name
        [Parameter(Mandatory = $true)]
        [string]
        $deployParamSet,

        # proceed through imput prompts
        [Parameter(Mandatory = $false)]
        [Alias('y')]
        [switch]
        $yes
    )
    $ErrorActionPreference = 'Stop'
    Write-Verbose "Starting Show-GSADeploymentSummary..."

    # determine the resources and configurations to be deployed
    switch -regex ($deployParamSet) {
        'newDeployment' {
            $deployType = 'New component'
            $components = $deployParams.newComponents

            $messages = ""
            If ($components -contains 'CoreComponents' -or [string]::IsNullOrEmpty($components)) {
                $messages += @"
Core components deployments will make the following changes to your environment:
    - Create a new resource group
    - Create a Log Analyics workspace, Automation Account, Storage Account, Key Vault, and Workbook resources in the new resource group
    - Grant the Automation Account Managed Service Identity (MSI) permissions to the Key Vault, Storage Account, and Log Analytics workspace in the new resource group
    - Grant the Automation Account Managed Service Identity (MSI) reader rights to your Azure tenant at the root Management Group scope
    - Grant the Automation Account MSI the following roles in Azure AD: "Organization.Read.All", "User.Read.All", "UserAuthenticationMethod.Read.All", "Policy.Read.All"`n
"@
            }
            If ($components -contains 'CentralizedCustomerReportingSupport') {
                $messages += @"
Centralized Customer Reporting Support will make the following changes to your environment:
    - Add a Lighthouse delegation definition, allowing Reader, Monitoring Reader, and Managed Services Registration assignment Delete Role
    - Assign the Lighthouse delegation at the Guardrails resource group scope, allowing access to the managing tenant principal specified in the configuration file`n
"@
            }
            If ($components -contains 'CentralizedCustomerDefenderForCloudSupport') {
                $messages += @"
Centralized Customer Defender for Cloud Support will make the following changes to your environment:
    - Creates a new Policy definition and assignment at the Management Group specified in the configuration file (lighthouseTargetManagementGroupID)
    - The Policy deploys a Lighthouse definition and assignment at each Subscription under the Management Group specified in the configuration file (lighthouseTargetManagementGroupID) which grants the Security Reader to the managing tenant service principal specified in the configuration file.
    - Creates a new custom RBAC definition allowing the registration of the Lighthouse Resource Provider
    - Assigns the custom RBAC definition to the Automation Account MSI at the Management Group specified in the configuration file (lighthouseTargetManagementGroupID)
    - Enables a step in the Automation Account 'backend' runbook to register the Lighthouse Resource Provider`n
"@
            }
        }
        'updateDeployment' {
            $deployType = 'Update component'
            $components = $deployParams.updateComponents
        }
    }

    # display the resources and configurations to be deployed
    $actionString = ""
    ForEach ($component in $components) {
        $actionString += "`n`t-  {0}: {1}" -f $deployType, $component
    }

    # verify the user's acceptance
    Write-Host "Executing this command will perform the following actions: $actionString"
    Write-Host $messages -ForegroundColor Yellow

    If (!$yes.IsPresent) {
        do { $prompt = Read-Host -Prompt 'Do you want to continue? (y/n)' }
        until ($prompt -match '[yn]')

        if ($prompt -ieq 'y') {
            Write-Verbose "Continuing with resource removal..."
        }
        elseif ($prompt -ieq 'n') {
            Write-Output "Exiting without removing Guardrails Solution Accelerator core resources..."
            break
        }
    }

    Write-Verbose "Show-GSADeploymentSummary completed."
}
# SIG # Begin signature block
# MIInzQYJKoZIhvcNAQcCoIInvjCCJ7oCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDB4y+84Da76IKk
# 1+shEMlYHQ4vgSUKV6gVybKBDoeVaqCCDYEwggX/MIID56ADAgECAhMzAAACzI61
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
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZojCCGZ4CAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAsyOtZamvdHJTgAAAAACzDAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgniK8XNce
# UIlvnrJLhpgCrjwOf6sLfvMGROxkom1kiN8wQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQBXpJF9gVSBzdJO4SwxuTimq9XknTMiXXHGK0jUQqLQ
# YEI69FT1+rlAfaUqW8hduDeJ2jNlTOz78pvW6DaYz8MKIkBeUVE2lSRyRJR9Ei+U
# 6Z+6yXMT8sJuZMMYQlVLC93jXuszXv3bb5zZLdHvx8DlN0Lt0Qs+D1KHbksmH8Po
# 8sCCtyo1tUot8Cof6bDeeSxnV8xgRnus2iJoHL6AFZQp8mwfy35nESqqYuOsXtVD
# r4ReY6S61PQhhon+DvwZUDfsjX8MFbv9ZNAnpmu5L1AgYyVQLm87q/qEVMffzTyk
# GBYPQNKNEkF8hpuZ94HdrghN4VxP1mT9ILNAFsHI2EkBoYIXLDCCFygGCisGAQQB
# gjcDAwExghcYMIIXFAYJKoZIhvcNAQcCoIIXBTCCFwECAQMxDzANBglghkgBZQME
# AgEFADCCAVkGCyqGSIb3DQEJEAEEoIIBSASCAUQwggFAAgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIGamOYA2gRCmQqJHBk3ZKV9WMTL7kPoVboQF1BeP
# ygSMAgZjUBvdXrkYEzIwMjIxMTAyMTQyNDU3LjkxMlowBIACAfSggdikgdUwgdIx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1p
# Y3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhh
# bGVzIFRTUyBFU046ODZERi00QkJDLTkzMzUxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WgghF7MIIHJzCCBQ+gAwIBAgITMwAAAbchJxoHoiqG
# RgABAAABtzANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDAeFw0yMjA5MjAyMDIyMTRaFw0yMzEyMTQyMDIyMTRaMIHSMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQg
# SXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1Mg
# RVNOOjg2REYtNEJCQy05MzM1MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAx/3PV1A0
# E2RMGrcclyXKmNBwkiUMCCm+zDi8cl7TqfnfZEoaRyfRXunrk54DXA6g77w2yime
# M+lVnz7iz9GF0wIw09AlehZ2RY6n/em4gSzV/M8GBMmt2bN3JRjOsCWggJjHvbaC
# Z2ls1/c/TLlnaBE7jyxYhjJh40lhyH5l8nNeqq+6+rsbw2bwgxCLxlrK/H7l1IYE
# zlVgcHEISNcX0Q3pDDsDrRJpeMqOiNKlSalozgWZV5z3zk811KHyE54/a0vvzVIF
# qf3YNPX2180e/0fQUCYTYcZHCLMeQn/+YBl1LSzpuL9TA8ySwCJrlumcgME6hph1
# aRXSVUbms3T6W1HP3OOVof26F0ZMn5aI0o6vuZGeXNhADnd+1JIkGqwSlPMK/tzr
# vd92+W3HfLjw96vq9zpRHl7iRJmwfXjUiHGGZFHZKYRpu5go5N07tD++W8B9DG4S
# cn3c0vgthXUhbDw77E07qCWOsGkI5845NCBYkX4zr8g/K5ity/v0u7uVzrtL5T0w
# S7Z2iDQy4kihgIyK5VpdLn4WY4mLJ+IJmbRUmwnnvTL2T+0RB7ppBH0zENbWnYXc
# dZ5uiVeP2y7vOusSU2UcAS+kWFyCgyeLKU1OJNnMvBSPtMfzeCe6DDUUIRVWHlT2
# XA0w8vUga7P/dT5FP3BkIElgisUk93qTxS0CAwEAAaOCAUkwggFFMB0GA1UdDgQW
# BBSz8jk+DDQkBWEN1gHbI8gjyXi07DAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQM
# MAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEA
# DZ1kzJuFXFJdNsnMWC82IwJXn8DKflS7MlTj3lgO1x5+iV3R6FH1AEYGEeYAy3XR
# ZgIfPZZBTIzeZAPgiwd8QvUkTCAb20arvW5yf12ScsEcPfQm9tBGEgpy8VKe9EIK
# lWmKUzwX9hpZcL1WJtJ5/89TYZYD7XOzrhUXEmod67LwqqtDJ8XbRIKd3zNFmXhh
# gFyOH0bQaOEkdQ8BgTHSvyNJaPKLajZYAcPoKmkG2TCdlJ/sDrwMvg7DAGmYUHf6
# +5uOA3BogJL5+QZW9Gc/ZmCaV+doBqzwzHuKAmpyKqrRDoCf7SsePWTGKw10iJPM
# WW7kbDZ6FekuuXn2S+yY41UAkeGd2nHef/SvvpMf7dY1L1RP2NvFCQT63a2GJ/ow
# rmSsUyeQEgIJH8NVxXWrD2yDqwwSjTBZJeVBhe9xBYDrl5XNKSizKWEiUhlksvcY
# dkPUtC0COnYDkXsLcjDg23sLtoMJ+kXGibdm6VGcUmiWU8dve6eP2ED3G9GIqdYw
# AylLgxkCiJXg7b3NYpl1TPKCnuAPhaMorXXkoInSi8Rx/3YCfAwBcyc2zWjQsKzO
# D64OaJBmzl5HuPN0rNV8XXPtt8Ng08Am+bmlJB1vLfAg6w3+y1iMz4SRo+1TOvw7
# IzCsb6OkUxuwHhx83q28h4a2u2SUwkW2cXrwJxlnkgAwggdxMIIFWaADAgECAhMz
# AAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9v
# dCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAeFw0yMTA5MzAxODIyMjVaFw0z
# MDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIICIjAN
# BgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA5OGmTOe0ciELeaLL1yR5vQ7VgtP9
# 7pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/XE/HZveVU3Fa4n5KWv64NmeFRiMM
# tY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1hlDcwUTIcVxRMTegCjhuje3XD9gm
# U3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7M62AW36MEBydUv626GIl3GoPz130
# /o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3KNi1wjjHINSi947SHJMPgyY9+tVSP
# 3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy1cCGMFxPLOJiss254o2I5JasAUq7
# vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF803RKJ1v2lIH1+/NmeRd+2ci/bfV+A
# utuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQcNIIP8BDyt0cY7afomXw/TNuvXsLz
# 1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahhaYQFzymeiXtcodgLiMxhy16cg8ML6
# EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkLiWHzNgY1GIRH29wb0f2y1BzFa/Zc
# UlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV2xo3xwgVGD94q0W29R6HXtqPnhZy
# acaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIGCSsGAQQBgjcVAQQFAgMBAAEwIwYJ
# KwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUpzxD/LwTuMB0GA1UdDgQWBBSfpxVd
# AF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBTMFEGDCsGAQQBgjdMg30BATBBMD8G
# CCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3Mv
# UmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYBBAGCNxQC
# BAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYD
# VR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZF
# aHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9v
# Q2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcw
# AoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJB
# dXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcNAQELBQADggIBAJ1VffwqreEsH2cB
# MSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1OdfCcTY/2mRsfNB1OW27DzHkwo/7
# bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYAA7AFvonoaeC6Ce5732pvvinLbtg/
# SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbzaN9l9qRWqveVtihVJ9AkvUCgvxm2
# EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6LGYnn8AtqgcKBGUIZUnWKNsIdw2Fz
# Lixre24/LAl4FOmRsqlb30mjdAy87JGA0j3mSj5mO0+7hvoyGtmW9I/2kQH2zsZ0
# /fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0SCyxTkctwRQEcb9k+SS+c23Kjgm9
# swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxkoJLo4S5pu+yFUa2pFEUep8beuyOiJ
# Xk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFmPWn9y8FBSX5+k77L+DvktxW/tM4+
# pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC4822rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW
# 4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7vzhwRNGQ8cirOoo6CGJ/2XBjU02N
# 7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIC1zCCAkACAQEwggEAoYHYpIHVMIHSMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxl
# cyBUU1MgRVNOOjg2REYtNEJCQy05MzM1MSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQDIZ0EYw5s4OWwYFmZJRfah
# aB+pxqCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
# SIb3DQEBBQUAAgUA5wxlzDAiGA8yMDIyMTEwMjExNDMwOFoYDzIwMjIxMTAzMTE0
# MzA4WjB3MD0GCisGAQQBhFkKBAExLzAtMAoCBQDnDGXMAgEAMAoCAQACAhJyAgH/
# MAcCAQACAiDhMAoCBQDnDbdMAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQB
# hFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQEFBQADgYEA
# miFPF131oqRYKbo5lfMRZuSw+lTJNd7JmuDUZsya26/2rX/aSIpcXCBv2n/rQvbx
# 2N8h50H5hY+NUrfWD0OPBVJmxnXp8IVBvZjuQP/9NL7O+ZRIIH3FsYUXT7gTz414
# w1JdsPGONvmUxDe/b8iDmut+TQh1GajA0U4MfaLor8MxggQNMIIECQIBATCBkzB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAbchJxoHoiqGRgABAAAB
# tzANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEE
# MC8GCSqGSIb3DQEJBDEiBCBP5G6WxKVtyI5Gwko0aNxH18S+h/zn/APpqTz25hIB
# 1TCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIGwneNOyHtovyE16JgYvn/wg
# GfzNR+vv9DuuQzyJzXBBMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENB
# IDIwMTACEzMAAAG3IScaB6IqhkYAAQAAAbcwIgQgp8w+bN28MyhyCqyGLdjPMaY8
# Ip+t0R3UQxns7Lk8jewwDQYJKoZIhvcNAQELBQAEggIAvY9Ejf9mIHcajhPuUl/E
# Z+YPTpU5jZagCXfKvX/a6K/XB+upZNvMg53TRMzH2vIe8uifXOca9aPPrwoEnDdw
# wPyEqeRiscONP06Mg8q2uOno9UDySpy/OzcX8kihlsz/wKkHQlkkEzpHODPo4zbT
# +Cye4N7lbDpzNEYpn1CJmgu8JeX5uU4FuBKRVpLAtp40UamLNaSaAYpWH9UOhBi+
# imkarYGGpFfcZYsX/Obe4UFg2uaIj8ivi+P336qXDZPlWVGgZbZK9R95uYQu0P22
# Q71mIMlZ6l5QSkSoOK2CbqJAoHT8nSDFcVToJncvQs9XW52H8xvkZpvFgopM3ayH
# gTGaN6USLv6vsv71lNmNPHleHgUxPcUoW17487tijLj8Zuupvyc6lkK/4R2VrAxs
# 7WwLjhTIH0UscqsBYAhkfHZBpgSHBqjYB6iy/RNpcT9QRApldSYy5bKeV3XsyJB2
# LO7QXaZ9vcjDEAxPpSS+iNSX206lkthLBtDY2+Ggh1jtC//hEV+NXiGc9kr06hSm
# 0Qt9kSVQzTZ7mfHdKzOHsGYDLaL7DgYS3rkbbFzzwB6YhM5B9e4LgWp7Yn8EKFsY
# AbVhgpOe8Sk3R/B8zIL0HROP3socw57qIqIKzXpDKzQATJmHkqI+HVWwvZwfb8ad
# pzCPrhDY6mahzyl1iZA8Vew=
# SIG # End signature block
