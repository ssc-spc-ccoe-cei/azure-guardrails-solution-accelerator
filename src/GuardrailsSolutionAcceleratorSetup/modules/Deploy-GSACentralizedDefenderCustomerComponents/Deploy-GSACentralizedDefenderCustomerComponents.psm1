
Function Deploy-GSACentralizedDefenderCustomerComponents {
    param (
        # config
        [Parameter(mandatory = $true)]
        [psobject]
        $config
    )
    $ErrorActionPreference = 'Stop'

    Write-Verbose "Initiating deployment of components Lighthouse delegation of access to Defender for Cloud"
    $lighthouseBicepPath = "$PSScriptRoot/../../../../setup/lighthouse/"

    #build parameter object for subscription Defender for Cloud access delegation
    $bicepParams = @{
        'managedByTenantId'       = $config.lighthouseServiceProviderTenantID
        'location'                = $config.region
        'managedByName'           = 'SSC CSPM - Defender for Cloud Access'
        'managedByDescription'    = 'SSC CSPM - Defender for Cloud Access'
        'managedByAuthorizations' = @(
            @{
                'principalIdDisplayName' = $config.lighthousePrincipalDisplayName
                'principalId'            = $config.lighthousePrincipalId
                'roleDefinitionId'       = '91c1777a-f3dc-4fae-b103-61d183457e46' # Managed Services Registration assignment Delete Role
            }
            @{
                'principalIdDisplayName' = $config.lighthousePrincipalDisplayName
                'principalId'            = $config.lighthousePrincipalId
                'roleDefinitionId'       = '39bc4728-0917-49c7-9d2c-d95423bc2eb4' # Security Reader
            }
        )
    }

    #deploy a custom role definition at the lighthouseTargetManagementGroupID, which will later be used to grant the Automation Account MSI permissions to register the Lighthouse Resource Provider
    try {
        $roleDefinitionDeployment = New-AzManagementGroupDeployment -ManagementGroupId $config.lighthouseTargetManagementGroupID `
            -Location $config.region `
            -TemplateFile $lighthouseBicepPath/lighthouse_registerRPRole.bicep `
            -Confirm:$false `
            -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to deploy lighthouse resource provider registration custom role template with error: $_"
        break
    }
    $lighthouseRegisterRPRoleDefinitionID = $roleDefinitionDeployment.Outputs.roleDefinitionId.value

    #deploy Guardrails Defender for Cloud permission delegation - this delegation adds a role assignment to every subscription under the target management group
    try {
        $policyDeployment = New-AzManagementGroupDeployment -ManagementGroupId $config.lighthouseTargetManagementGroupID `
            -Location $config.region `
            -TemplateFile $lighthouseBicepPath/lighthouseDfCPolicy.bicep `
            -TemplateParameterObject $bicepParams `
            -Confirm:$false `
            -ErrorAction Stop
    }
    catch {
        If ($_.Exception.message -like "*Status Message: Principal * does not exist in the directory *. Check that you have the correct principal ID.*") {
            Write-Warning "Deployment role assignment failed due to AAD replication delay, attempting to proceed with role assignment anyway..."
        }
        Else {
            Write-Error "Failed to deploy Lighthouse Defender for Cloud delegation by Azure Policy template with error: $_"
            break
        }
    }

    ### wait up to 5 minutes to ensure AAD has time to propagate MSI identities before assigning a roles ###
    $i = 0
    do {
        Write-Verbose "Waiting for Policy assignment MSI to be available..."
        Start-Sleep 5

        $i++
        If ($i -gt '60') {
            Write-Error "[$i/60]Timeout while waiting for MSI '$($policyDeployment.Outputs.policyAssignmentMSIRoleAssignmentID.value)' to exist in Azure AD"
            break
        }
    }
    until ((Get-AzADServicePrincipal -id $policyDeployment.Outputs.policyAssignmentMSIRoleAssignmentID.value -ErrorAction SilentlyContinue))

    # deploy an 'Owner' role assignment for the MSI associated with the Policy Assignment created in the previous step
    # Owner rights are required so that the MSI can then assign the requested 'Security Reader' role on each subscription under the target management group
    try {
        $null = New-AzManagementGroupDeployment -ManagementGroupId $config.lighthouseTargetManagementGroupID `
            -Location $config.region `
            -TemplateFile $lighthouseBicepPath/lighthouseDfCPolicyRoleAssignment.bicep `
            -TemplateParameterObject @{policyAssignmentMSIPrincipalID = $policyDeployment.Outputs.policyAssignmentMSIRoleAssignmentID.value } `
            -Confirm:$false `
            -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to deploy template granting the Defender for Cloud delegation policy rights to configure role assignments with error: $_"
        break   
    } 

    # deploy a custom role assignment, granting the Automation Account MSI permissions to register the Lighthouse resource provider on each subscription under the target management group
    try {
        $null = New-AzManagementGroupDeployment -ManagementGroupId $config.lighthouseTargetManagementGroupID `
            -Location $config.region `
            -TemplateFile $lighthouseBicepPath/lighthouse_assignRPRole.bicep `
            -TemplateParameterObject @{lighthouseRegisterRPRoleDefinitionID = $lighthouseRegisterRPRoleDefinitionID; guardrailsAutomationAccountMSI = $config.guardrailsAutomationAccountMSI } `
            -Confirm:$false `
            -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to deploy template granting the Azure Automation account rights to register the Lighthouse resource provider with error: $_"
        break   
    } 

    ### TO DO ### The remediation task created by the Bicep template should be all that is required, but does not seem to execute
    try {
        $ErrorActionPreference = 'Stop'
        $null = Start-AzPolicyRemediation -Name Redemdiation -ManagementGroupName $config.lighthouseTargetManagementGroupID -PolicyAssignmentId $policyDeployment.Outputs.policyAssignmentId.value
    }
    catch {
        Write-Error "Failed to create Remediation Task for policy assignment '$($policyDeployment.Outputs.policyAssignmentId.value)' with the following error: $_"
    }

    Write-Verbose "Completing deployment of components Lighthouse delegation of access to Defender for Cloud"
}
# SIG # Begin signature block
# MIInnwYJKoZIhvcNAQcCoIInkDCCJ4wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCC5wF2HDNGKh7K
# qVcPnSCh++wq3ogVuOU/QMBFo3zNyqCCDYEwggX/MIID56ADAgECAhMzAAACzI61
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
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZdDCCGXACAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAsyOtZamvdHJTgAAAAACzDAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgvxgzbWvW
# ZiFxL5CQdko4l7ILYtuMzWP19pDl96zeKN4wQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQAlgNRW69KVqc//ZBZsW/URPsW7BiU10XgK/HKb/NaB
# Z2LIe2h+CXR8HBNM4wAU17J3BQEASlR6ArGGScGDlUmeGj2KJBWSfUcEVwNEV/Qz
# qL2m6JMw9ZFsZn3cqTdAWf7nRY+XyOEnAlmLRVfLn1u+WR3oUwtDTy1GPRmPFidY
# HX3hwQGu7ucYfkvhSVBUsUu+JqFjI0wxnLp3UiFzHbntEZnCunX9zbB+8e7UwIEV
# dSQrW2fhFagw1itPJpg/Iq4qjnXyQxbSN1Yi715eoCM5hyH5EPKUgBzezJcE484o
# Y0G5icJQIb0DWeQbDMCSwDgrgRrttxY3oTkTPSJzAD4ToYIW/jCCFvoGCisGAQQB
# gjcDAwExghbqMIIW5gYJKoZIhvcNAQcCoIIW1zCCFtMCAQMxDzANBglghkgBZQME
# AgEFADCCAU8GCyqGSIb3DQEJEAEEoIIBPgSCATowggE2AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIDuN0F3h9WYrVcdiq6znMO5qEhYjA+5Oah4rcJ0k
# cwFsAgZjbRKY6vkYETIwMjIxMTMwMTgxMTMyLjZaMASAAgH0oIHQpIHNMIHKMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNy
# b3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVT
# TjoxMkJDLUUzQUUtNzRFQjElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAg
# U2VydmljZaCCEVcwggcMMIIE9KADAgECAhMzAAAByk/Cs+0DDRhsAAEAAAHKMA0G
# CSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTIy
# MTEwNDE5MDE0MFoXDTI0MDIwMjE5MDE0MFowgcoxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9w
# ZXJhdGlvbnMxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOjEyQkMtRTNBRS03NEVC
# MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkq
# hkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAwwGcq9j50rWEkcLSlGZLweUVfxXRaUji
# PsyaNVxPdMRs3CVe58siu/EkaVt7t7PNTPko/s8lNtusAeLEnzki44yxk2c9ekm8
# E1SQ2YV9b8/LOxfKapZ8tVlPyxw6DmFzNFQjifVm8EiZ7lFRoY448vpcbBD18qjY
# NF/2Z3SQchcsdV1N9Y6V2WGl55VmLqFRX5+dptdjreBXzi3WW9TsoCEWcYCBK5wY
# gS9tT2SSSTzae3jmdw40g+LOIyrVPF2DozkStv6JBDPvwahXWpKGpO7rHrKF+o7E
# CN/ViQFMZyp/vxePiUABDNqzEUI8s7klYmeHXvjeQOq/CM3C/Y8bj3fJObnZH7eA
# XvRDnxT8R6W/uD1mGUJvv9M9BMu3nhKpKmSxzzO5LtcMEh2tMXxhMGGNMUP3DOEK
# 3X+2/LD1Z03usJTk5pHNoH/gDIvbp787Cw40tsApiAvtrHYwub0TqIv8Zy62l8n8
# s/Mv/P764CTqrxcXzalBHh+Xy4XPjmadnPkZJycp3Kczbkg9QbvJp0H/0FswHS+e
# fFofpDNJwLh1hs/aMi1K/ozEv7/WLIPsDgK16fU/axybqMKk0NOxgelUjAYKl4wU
# 0Y6Q4q9N/9PwAS0csifQhY1ooQfAI0iDCCSEATslD8bTO0tRtqdcIdavOReqzoPd
# vAv3Dr1XXQ8CAwEAAaOCATYwggEyMB0GA1UdDgQWBBT6x/6lS4ESQ8KZhd0RgU7R
# YXM8fzAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBW
# MFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNy
# b3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUH
# AQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtp
# b3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEp
# LmNydDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsGAQUFBwMIMA0GCSqGSIb3
# DQEBCwUAA4ICAQDY0HkqCS3KuKefFX8/rm/dtD9066dKEleNqriwZqsM4Ym8Ew4Q
# iqOqO7mWoYYY4K5y8eXSOHKNXOfpO6RbaYj8jCOcJAB5tqLl5hiMgaMbAVLrl1hl
# ix9sloO45LON0JphKva3D6AVKA7P78mA9iRHZYUVrRiyfvQjWxmUnxhis8fom92+
# /RHcEZ1Dh5+p4gzeeL84Yl00Wyq9EcgBKKfgq0lCjWNSq1AUG1sELlgXOSvKZ4/l
# XXH+MfhcHe91WLIaZkS/Hu9wdTT6I14BC97yhDsZWXAl0IJ801I6UtEFpCsTeOyZ
# BJ7CF0rf5lxJ8tE9ojNsyqXJKuwVn0ewCMkZqz/cEwv9FEx8QmsZ0ZNodTtsl+V9
# dZm+eUrMKZk6PKsKArtQ+jHkfVsHgKODloelpOmHqgX7UbO0NVnIlpP55gQTqV76
# vU7wRXpUfz7KhE3BZXNgwG05dRnCXDwrhhYz+Itbzs1K1R8I4YMDJjW90ASCg9Jf
# +xygRKZGKHjo2Bs2XyaKuN1P6FFCIVXN7KgHl/bZiakGq7k5TQ4OXK5xkhCHhjdg
# Huxj3hK5AaOy+GXxO/jbyqGRqeSxf+TTPuWhDWurIo33RMDGe5DbImjcbcj6dVhQ
# evqHClR1OHSfr+8m1hWRJGlC1atcOWKajArwOURqJSVlThwVgIyzGNmjzjCCB3Ew
# ggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQELBQAwgYgx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1p
# Y3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTIxMDkz
# MDE4MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENB
# IDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM57RyIQt5
# osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9cT8dm95VTcVri
# fkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWGUNzBRMhxXFEx
# N6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6GnszrYBbfowQHJ1S
# /rboYiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2LXCOMcg1KL3j
# tIckw+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLVwIYwXE8s4mKy
# zbnijYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW/aUgfX78
# 2Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjt
# p+iZfD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2
# AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb
# 3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXbGjfHCBUYP3ir
# Rbb1Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJKwYBBAGCNxUB
# BAUCAwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYD
# VR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMwUQYMKwYBBAGC
# N0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
# a2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZ
# BgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/
# BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8E
# TzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9k
# dWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBM
# MEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRz
# L01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0BAQsFAAOCAgEA
# nVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U518JxNj/aZGx8
# 0HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgADsAW+iehp4LoJ
# 7nvfam++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo32X2pFaq95W2
# KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZiefwC2qBwoEZ
# QhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa
# 2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RILLFORy3BFARx
# v2T5JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgkujhLmm77IVRr
# akURR6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3LwUFJfn6T
# vsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzbaukz5m/8K6TT4
# JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6
# ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggLOMIICNwIBATCB+KGB
# 0KSBzTCByjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMG
# A1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEmMCQGA1UECxMdVGhh
# bGVzIFRTUyBFU046MTJCQy1FM0FFLTc0RUIxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMVAKOO55cMT4syPP6nClg2
# IWfajMqkoIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJ
# KoZIhvcNAQEFBQACBQDnMe6FMCIYDzIwMjIxMTMwMjMwMDIxWhgPMjAyMjEyMDEy
# MzAwMjFaMHcwPQYKKwYBBAGEWQoEATEvMC0wCgIFAOcx7oUCAQAwCgIBAAICJmEC
# Af8wBwIBAAICEccwCgIFAOczQAUCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYB
# BAGEWQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOB
# gQCgRvDNtBJY/jiVg5f+ONQG2WiL80/5GQQJbvFFO3GJLfCGbLcHsuBENsSjPWvC
# XqLUW0dvWvDIRGVtF8vEzEDyn0O9G5CP8ygEFDBFuHyw9cA0jD1xI7DJYKFyH5BT
# bto2aXYvGEiXpUQcrHw0Lxp9OH7rkjm6Kjcuza2a4QjuKTGCBA0wggQJAgEBMIGT
# MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
# HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAByk/Cs+0DDRhsAAEA
# AAHKMA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQ
# AQQwLwYJKoZIhvcNAQkEMSIEIJFBQDTZ+yVJvqzFDC0H8oXUPL31Do6dkMN6ox59
# 9T2lMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgEz0b85vrVU2slZAk4jt1
# SDEk6IzZAwVCoWwF3KzcGuAwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMAITMwAAAcpPwrPtAw0YbAABAAAByjAiBCCsztGlJmVV5l4GpPQsAMsA
# 6Zgq0DmiDm1ogKAIFSoJgzANBgkqhkiG9w0BAQsFAASCAgBT2TA4GdRtUpOFMv1R
# 2GJv54kuOxer94Eg7BiMtzOVGsMC6cwBTaFfIfGBq+sDkhk2VtzCSiZFEEAPSxwg
# S4d9l8VNojb9pp7xBRd0M52y/8luHA0CROIdIGLYDRHkrxkt38HsPfbQotTfIbpp
# EvTpTwBTjshI5BnUV7cZ3gTyGAwvu3DGxfMrMHiXBHHlpmuUTlMPwDrVfCWFnQmX
# QVsSMh623wrSMiL94QG0IL/2n4BsS10ANbISyMhGTgMRRo3O1zt3FU8hCICBcapH
# 4cqFyb+uB2N15WyoxVxwfqYk4a9khzw2awypJ94FEbTRUBm8s2OIf8dzxZLdsDWM
# 9S85YpbonxCZwGap39Oc/JiNgHG2Lr0GfRljNn3YeYJYB9CHq2o2KkFKHEiUvQoC
# rI4hpXt+tvlLkbW3/T48uqeXgPBqtGryLW/35LZdKh+wTUknEB1IpvziEt17O/g2
# psbZGeOoZ2SkyBLiTZrKAphN3E+0piGVbMzDExXWMAs2B9rs/W95uLW4eSJuVMED
# J0qnbK1FBPY57leKDYhXuPZ/xml4v2ZBK/OGJ8sNB+pdgrhe2jqO215sHRkMxA36
# cin6JDOKeCsUOnmSoUiM6es63+vsQwUNElNcJfrsa+mfKx+vCHVX+TTsmuI4jtIi
# pyP7q8vJMx2XYmujt5R4HdEn1A==
# SIG # End signature block
