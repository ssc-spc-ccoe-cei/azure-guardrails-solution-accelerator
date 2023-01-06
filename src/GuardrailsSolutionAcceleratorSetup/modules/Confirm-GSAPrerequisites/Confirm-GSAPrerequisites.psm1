
Function Confirm-GSAPrerequisites {

    param (
        # config
        [Parameter(mandatory = $true)]
        [psobject]
        $config,

        # optional components included in the install
        [Parameter(Mandatory = $false)]
        [string[]]
        $newComponents
    )

    $ErrorActionPreference = 'Stop'

    Write-Verbose "Starting verification of the Guardrails Solution Accelerator prerequisites."

    If ($newComponents -contains 'CoreComponents') {
        Write-Verbose "Verifying prerequisites for Core Components..."

        # confirm that executing user required permission to complete the deployment
        Write-Verbose "Checking that user '$($config['runtime']['userId'])' has role 'User Access Administrator' or 'Owner' assigned at the root management group scope (id: '$($config['runtime']['tenantRootManagementGroupId'])')"
        Write-Verbose "`t Getting role assignments with cmd: Get-AzRoleAssignment -Scope $($config['runtime']['tenantRootManagementGroupId']) -RoleDefinitionName 'User Access Administrator' -ObjectId $($config['runtime']['userId']) -ErrorAction Continue"
        Write-Verbose "`t Getting role assignments with cmd: Get-AzRoleAssignment -Scope $($config['runtime']['tenantRootManagementGroupId']) -RoleDefinitionName 'Owner' -ObjectId $($config['runtime']['userId']) -ErrorAction Continue"
        $roleAssignments = @()
        $roleAssignments += Get-AzRoleAssignment -Scope $config['runtime']['tenantRootManagementGroupId'] -RoleDefinitionName 'User Access Administrator' -ObjectId $config['runtime']['userId'] -ErrorAction Continue
        $roleAssignments += Get-AzRoleAssignment -Scope $config['runtime']['tenantRootManagementGroupId'] -RoleDefinitionName 'Owner' -ObjectId $config['runtime']['userId'] -ErrorAction Continue

        Write-Verbose "`t Count of role assignments '$($roleAssignments.Count)'"
        if ($roleAssignments.count -eq 0) {
            Write-Error "Specified user ID '$($config['runtime']['userId'])' does not have role 'User Access Administrator' or 'Owner' assigned at the root management group scope!"
            Break                                                
        }
        Else {
            Write-Verbose "`t Sufficent role assignment for current user exists..."
        }

        # confirm that target resources do not already exist

        ## storage account
        Write-Verbose "Verifying that storage account name '$($config['runtime']['storageAccountName'])' is available"
        $nameAvailability = Get-AzStorageAccountNameAvailability -Name $config['runtime']['storageaccountName']
        if (($nameAvailability).NameAvailable -eq $false) {
            Write-Error "Storage account $($config['runtime']['storageaccountName']) is not available. Message: $($nameAvailability.Message)"
            break
        }
        Else {
            Write-Verbose "Storage account name '$($config['runtime']['storageAccountName'])' is available"
        }

        ## keyvault
        Write-Verbose "Verifying the Key Vault name '$($config['runtime']['keyVaultName'])' is available"
        $kvContent = ((Invoke-AzRest -Uri "https://management.azure.com/subscriptions/$($config['runtime']['subscriptionId'])/providers/Microsoft.KeyVault/checkNameAvailability?api-version=2021-11-01-preview" `
                    -Method Post -Payload "{""name"": ""$config['runtime']['keyVaultName']"",""type"": ""Microsoft.KeyVault/vaults""}").Content | ConvertFrom-Json).NameAvailable
        if (!($kvContent) -and $deployKV) {
            write-output "Error: keyvault name '$($config['runtime']['keyVaultName'])' is not available. Specify another prefix in config.json or a different unique resource name suffix"
            break
        }
    }

    # confirm lighthouse prereqs met
    If (($newComponents -contains 'CentralizedCustomerReportingSupport') -or ($newComponents -contains 'CentralizedCustomerDefenderForCloudSupport')) {
        # verify Lighthouse config parameters
        $lighthouseServiceProviderTenantID = $config.lighthouseServiceProviderTenantID
        $lighthousePrincipalDisplayName = $config.lighthousePrincipalDisplayName
        $lighthousePrincipalId = $config.lighthousePrincipalId
        $lighthouseTargetManagementGroupID = $config.lighthouseTargetManagementGroupID

        If ($newComponents -contains 'CentralizedCustomerReportingSupport') {
            Write-Verbose "Verifying prerequisites for Centralized Customer Reporting Support..."

            Write-Verbose "Confirming that the GSA core resources exist or will be deployed..."
            If ($newComponents -notcontains 'CoreComponents') {
                If (-NOT (Get-AzResourceGroup -Name $config['runtime']['resourceGroup'] -ErrorAction SilentlyContinue)) {
                    Write-Error "Unable to locate the resource group '$($config['runtime']['resourceGroup'])'; deployment of the centralized management components require that the core components be deployed first."
                    break
                }
                Else {
                    Write-Verbose "`tFound resource group '$($config['runtime']['resourceGroup'])'"
                }

                If (-NOT (Get-AzOperationalInsightsWorkspace -ResourceGroupName $config['runtime']['resourceGroup'] -Name $config['runtime']['logAnalyticsWorkspaceName'] -ErrorAction SilentlyContinue)) {
                    Write-Error "Unable to locate the Log Analytics workspace '$($config['runtime']['logAnalyticsWorkspaceName'])'; deployment of the centralized management components require that the core components be deployed first."
                    break
                }
                Else {
                    Write-Verbose "`tFound Log Analytics workspace '$($config['runtime']['logAnalyticsWorkspaceName'])'"
                }
            }

            # get lighthouse definitions for the managing tenant
            Write-Verbose "Checking for lighthouse registration definitions for managing tenant '$lighthouseServiceProviderTenantID'..."

            $uri = 'https://management.azure.com/subscriptions/{0}/providers/Microsoft.ManagedServices/registrationdefinitions?api-version=2022-01-01-preview&$filter=managedByTenantId eq {1}' -f `
                $config['runtime']['subscriptionId'], "'$lighthouseServiceProviderTenantID'"
            $response = Invoke-AzRestMethod -Method GET -Uri $uri

            If ($response.StatusCode -notin '200', '404') {
                Write-Error "An error occurred while retrieving Lighthouse registration definitions. Error: $($response.Content)"
                break
            }

            Write-Verbose "Found $($response.Content.value.Count) registration definitions for managing tenant '$lighthouseServiceProviderTenantID', filtering for registration definitions with the name 'SSC CSPM - Read Guardrail Status'..."
            $definitionsValue = $response.Content | ConvertFrom-Json | Select-Object -ExpandProperty value
            $guardrailReaderDefinitions = $definitionsValue | Where-Object { $_.Properties.registrationDefinitionName -eq 'SSC CSPM - Read Guardrail Status' }

            If ($guardrailReaderDefinitions.count -eq 0) {
                Write-Verbose "No Lighthouse registration definitions found for the managing tenant ID '$lighthouseServiceProviderTenantID'."
            }
            ElseIf (($guardrailReaderDefinitions.count -gt 1)) {
                Write-Error "More than 1 Lighthouse registration definition found for the managing tenant ID '$lighthouseServiceProviderTenantID' with the description 'SSC CSPM - Read Guardrail Status', please remove these registrations before continuing..."
                break
            }
            Else {
                Write-Verbose "Found '$($guardrailReaderDefinitions.count)' Lighthouse registration definitions for the managing tenant ID '$lighthouseServiceProviderTenantID' with the description 'SSC CSPM - Read Guardrail Status'."
                #remove lighthouse assignments
                Write-Verbose "Checking for Lighthouse assignments for managing tenant '$lighthouseServiceProviderTenantID' and definition ID '$($guardrailReaderDefinitions.id)'..."
                $uri = 'https://management.azure.com/subscriptions/{0}/providers/Microsoft.ManagedServices/registrationAssignments?api-version=2022-01-01-preview&$filter=registrationDefinitionId eq {1}' -f `
                    $config['runtime']['subscriptionId'], "'$($guardrailReaderDefinitions.id)'"
                $response = Invoke-AzRestMethod -Method GET -Uri $uri -Verbose

                If ($response.StatusCode -notin '200', '404') {
                    Write-Error "An error occurred while retrieving Lighthouse assignments. Error: $($response.Content)"
                    break
                }

                $assignmentValue = $response.Content | ConvertFrom-Json

                If ($assignmentValue.count -gt 0) {
                    Write-Error "Found $($assignmentValue.count) Lighthouse assignments for the managing tenant ID '$lighthouseServiceProviderTenantID' and definition ID '$($guardrailReaderDefinitions.id)', please remove these assignments before continuing."
                    break
                }
            }
        }
    
        If ($newComponents -contains 'CentralizedCustomerDefenderForCloudSupport') {
            Write-Verbose "Verifying prerequisites for Centralized Customer Defender for Cloud Support..."
            # check that user has correct permissions for deploying to tenant root mgmt group
            ## this permission is required so that a Policy Definition and Assignment can be deployed at the target management group, applying to all subscriptions in the tenant
            if ($lighthouseTargetManagementGroupID -eq $config['runtime']['tenantId']) {
                Write-Verbose "lighthouseTargetManagementGroupID is the tenant root managment group, which requires explicit owner permissions for the exeucting user; verifying..."
        
                $existingAssignment = Get-AzRoleAssignment -Scope '/' -RoleDefinitionName Owner -ObjectId $config['runtime']['userId'] | Where-Object { $_.Scope -eq '/' }
                If (!$existingAssignment) {
                    Write-Error "In order to deploy resources at the Tenant Root Management Group '$lighthouseTargetManagementGroupID', the executing user must be explicitly granted Owner 
                        rights at the root level. To create this role assignment, run 'New-AzRoleAssignment -Scope '/' -RoleDefinitionName Owner -ObjectId $($config['runtime']['userId'])' 
                        then execute this script again. This role assignment only needs to exist during the Lighthouse resource deployments and can (and should) be removed after this script completes."
                    Exit
                }
            }
        
            If ($lighthouseTargetManagementGroupID -eq $config['runtime']['tenantId']) {
                $assignmentScopeMgmtmGroupId = '/'
            }
            Else {
                $assignmentScopeMgmtmGroupId = $lighthouseTargetManagementGroupID
            }

            # check if a lighthouse defender for cloud policy MSI role assignment already exists - assignment name always 2cb8e1b1-fcf1-439e-bab7-b1b8b008c294 
            Write-Verbose "Checking for role assignments at management group '$assignmentScopeMgmtmGroupId' for role 'Owner'"
            $uri = 'https://management.azure.com/providers/Microsoft.Management/managementGroups/{0}/providers/Microsoft.Authorization/roleAssignments/{1}?&api-version=2015-07-01' -f $lighthouseTargetManagementGroupID, '2cb8e1b1-fcf1-439e-bab7-b1b8b008c294'
            $roleAssignments = Invoke-AzRestMethod -Uri $uri -Method GET | Select-Object -Expand Content | ConvertFrom-Json
            If ($roleAssignments.id) {
                Write-Verbose "role assignment: $(($roleAssignments).id)"
                Write-Error "A role assignment exists with the name '2cb8e1b1-fcf1-439e-bab7-b1b8b008c294' at the Management group '$lighthouseTargetManagementGroupID'. This was likely
                created by a previous Guardrails deployment and must be removed. Navigate to the Managment Group in the Portal and delete the Owner role assignment listed as 'Identity Not Found'"
                Exit
            }
    
            # check if lighthouse Custom-RegisterLighthouseResourceProvider exists at a different scope
            Write-Verbose "Checking for existing role definitions with name 'Custom-RegisterLighthouseResourceProvider'"
            $roleDef = Get-AzRoleDefinition -Name 'Custom-RegisterLighthouseResourceProvider'
            $targetAssignableScope = "/providers/Microsoft.Management/managementGroups/$lighthouseTargetManagementGroupID"
            
            Write-Verbose "Found '$($roleDef.count)' role definitions with name 'Custom-RegisterLighthouseResourceProvider'. Verifying assignable scopes includes '$targetAssignableScope'"
            If ($roleDef -and $roleDef.AssignableScopes -notcontains $targetAssignableScope) {
                Write-Error "Role definition name 'Custom-RegisterLighthouseResourceProvider' already exists and has an assignable scope of '$($roleDef.AssignableScopes)'. Assignable scopes
                should include '$targetAssignableScope'. Delete the role definition (and any assignments) and run the script again."
                Exit
            }
    
            # check if a lighthouse Azure Automation MSI role assignment to register the Lighthouse resource provider already exists - assignment name always  5de3f84b-8866-4432-8811-24859ccf8146
            Write-Verbose "Checking for role assignments at management group '$assignmentScopeMgmtmGroupId' for role 'Custom-RegisterLighthouseResourceProvider'"
            $uri = 'https://management.azure.com/providers/Microsoft.Management/managementGroups/{0}/providers/Microsoft.Authorization/roleAssignments/{1}?&api-version=2015-07-01' -f $lighthouseTargetManagementGroupID, '5de3f84b-8866-4432-8811-24859ccf8146'
            $roleAssignments = Invoke-AzRestMethod -Uri $uri -Method GET | Select-Object -Expand Content | ConvertFrom-Json   
            If ($roleAssignments.id) {  
                Write-Verbose "role assignment: $(($roleAssignments).id)"  
                Write-Error "A role assignment exists with the name '5de3f84b-8866-4432-8811-24859ccf8146' at the Management group '$lighthouseTargetManagementGroupID'. This was likely
                created by a previous Guardrails deployment and must be removed. Navigate to the Managment Group in the Portal and delete the 'Custom-RegisterLighthouseResourceProvider' role assignment listed as 'Identity Not Found'"
                Exit
            
            }
        }
    }
    
    Write-Host "Prerequisite validation completed successfully!" -ForegroundColor Green

    Write-Verbose "Completed verification of the Guardrails Solution Accelerator prerequisites."
}
# SIG # Begin signature block
# MIInqgYJKoZIhvcNAQcCoIInmzCCJ5cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCfQr/8wNvnPfA5
# tOuYnSikTYkGzzPU+4LjuuSvuK7v2KCCDYEwggX/MIID56ADAgECAhMzAAACzI61
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
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg1EIc4rkc
# fEgU2vkm5pre1TLog0ZSOy/8JwKSnUzonEkwQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQBxgWLd6fodnOXgx3O3nHXsE3rT4Jgc+2rAOcDki9B3
# nJO/BSzcbbORIFVS6eI8x2oGSvxJyjMHR9OMLqDVdTqEom66ESbgV0eDXwmieG45
# Pdeh5O2+bMWNR+ECfP0/oxKsjmagTi0IN6Riy3QWsabu6468aMjcL27AAwublens
# zLjfvUVdivooS3q3gj5BtfHONXwBzREjPj3Ux4dj6lnnovVhK0EL2YQp9Bo1mkZE
# sTQKn84s2AISs/1gIK6K7a7DxW/EeG31Bx78hlXKGBHPR5R1jufGAVy992IMA7aU
# E2TyhQkrG0FldRlPtrRgUHPKzMmG2Ct8O2HpBmEWHp1NoYIXCTCCFwUGCisGAQQB
# gjcDAwExghb1MIIW8QYJKoZIhvcNAQcCoIIW4jCCFt4CAQMxDzANBglghkgBZQME
# AgEFADCCAVUGCyqGSIb3DQEJEAEEoIIBRASCAUAwggE8AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEII91sml20BAThmLR/rvg4lKJFp0h8KXw8fGgJXuA
# IjBBAgZjoaEn1SIYEzIwMjMwMTA2MjA0NDM2LjcwN1owBIACAfSggdSkgdEwgc4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1p
# Y3Jvc29mdCBPcGVyYXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMg
# VFNTIEVTTjpGN0E2LUUyNTEtMTUwQTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgU2VydmljZaCCEVwwggcQMIIE+KADAgECAhMzAAABpQDeCMRAB3FOAAEA
# AAGlMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# MB4XDTIyMDMwMjE4NTExOVoXDTIzMDUxMTE4NTExOVowgc4xCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVy
# YXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpGN0E2
# LUUyNTEtMTUwQTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vydmlj
# ZTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALqxhuggaki8wuoOMMd7
# rsEQnmAhtV8iU1Y0itsHq30TdCXJDmvZjaZ8yvOHYFVhTyD1b5JGJtwZjWz1fglC
# qsx5qBxP1Wx1CZnsQ1tiRsRWQc12VkETmkY8x46MgHsGyAmhPPpsgRnklGai7HqQ
# FB31x/Qjkx7rbAlr6PblB4tOmaR1nKxl4VIgstDwfneKaoEEw4iN/xTdztZjwyGi
# Y5hNp6beetkcizgJFO3/yRHYh0gtk+bREhrmIgbarrrgbz7MsnA7tlKvGcO9iHc6
# +2symrAVy3CzQ4IMNPFcTTx8wTZ+kpv6lFs1eG8xlfsu2NDWKshrMlKH2JpYzWAW
# 1fCOD5irXsE4LOvixZQvbneQE6+iGfIQwabj+fRdouAU2AiE+iaNsIDapdKab8WL
# xz6VPRbEL+M6MFkcsoiuKHHoshCp7JhmZ9iM0yrEx2XebOha/XQ342KsRGs2h02g
# pX6wByyT8eD3MJVIxSRm4MLIilvWcpd9N3rooawbLU6gdk7goKWS69+w2jtouXCE
# Yt6IPfZq8ldi0L/CwYbtv7mbHmIZ9Oc0JEJc6b9gcVDfoPiemMKcz15BLepyx7np
# Q2MiDKIscOqKhXuZI+PZerNOHhi/vsy2/Fj9lB6kJrMYSfV0F2frvBSBXMB7xjv8
# pgqX5QXUe8nTxb4UfJ0cDAvBAgMBAAGjggE2MIIBMjAdBgNVHQ4EFgQUX6aPAwCX
# rq6tcO773FkXS2ipGt8wHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIw
# XwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
# cy9jcmwvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3Js
# MGwGCCsGAQUFBwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENB
# JTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcD
# CDANBgkqhkiG9w0BAQsFAAOCAgEAlpsLF+UwMKKER2p0WJno4G6GGGnfg3qjDdaH
# c5uvXYtG6KmHrqAf/YqHkmNotSr6ZEEnlGCJYR7W3uJ+5bpvj03wFqGefvQsKIR2
# +q6TrzozvP4NsodWTT5SVp/C6TEDGuLC9mOQKA4tyL40HTW7txb0cAdfgnyHFoI/
# BsZo/FaXezQ8hO4xUjhDpyNNeJ6WYvX5NC+Hv9nmTyzjqyEg/L2cXAOmxEWvfPAQ
# 1lfxvrtUwG75jGeUaewkhwtzanCnP3l6YjwJFKB6n7/TXtrfik1xY1kgev1JwQ5a
# UdPxwSdDmGE4XTN2s6pPOi8IO199Of6AEvh41eDxRz+11VUcpuGn7tJUeSTUSHsv
# zQ8ECOj5w77Mv55/F8hWu07egnG8SrWj5+TFxNPCpx/AFNvzz+odTRTZd4LWuomc
# MHUmLFiUGOAdetF6SofHG5EcFn0DTD1apBZzCP8xsGQcZgwVqo7ov23/uIJlMCLA
# yTYZV9ITCP09ciUJbKBVCQNrGEnQ/XLFO9mysyyDRrvHhU5uGPdXz4Jt2/ZN7JQY
# RuVNSuCpNwoK0Jr1s6ciDvHEeLyiczxoIe9GH3SyfbHx6v/phI+iE3DWo1TCK75E
# L6pt6k5i36/kn2uSVXdTH44ZVkh3/ihV3vEws78uGlvsiMcrKBgpo3HdcjDHiHoW
# sUf4GIwwggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3
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
# MSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpGN0E2LUUyNTEtMTUwQTElMCMGA1UE
# AxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUA
# s8lw20WzmxDKiN1Lhh7mZWXutKiggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMDANBgkqhkiG9w0BAQUFAAIFAOdiiN0wIhgPMjAyMzAxMDYxNTQ3
# NDFaGA8yMDIzMDEwNzE1NDc0MVowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA52KI
# 3QIBADAHAgEAAgIexjAHAgEAAgIRUjAKAgUA52PaXQIBADA2BgorBgEEAYRZCgQC
# MSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqG
# SIb3DQEBBQUAA4GBAGopyR2SM0kVu4NYMl8ni+uThETA6YWTLlsVxzNfnAVITU0E
# 6TPXZcl6W5/xX/1AaBhCYYm/8kxR7dCkqKcM1O0heGbNvN2x/QXJsFwfUDeZF/Ad
# sV6nE+MskxxKbkeFixn7ObcXZEN+8nglJ63Z1kX6Q6aXJUoUdGwyxc3x0DLSMYIE
# DTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGl
# AN4IxEAHcU4AAQAAAaUwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzEN
# BgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgELj9+eszbnN25/9r5TJzVUFw
# 1cFblbygTMM+98oj42gwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCC4Cjhx
# fmYEsaCt2AU83Khh+6JHlyk3B70vfMHMlBLcXDCBmDCBgKR+MHwxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABpQDeCMRAB3FOAAEAAAGlMCIEINMDrenX
# gV6mA7hRRCuXwjiRO8D6q76RBX8pypIpqR+QMA0GCSqGSIb3DQEBCwUABIICALG/
# sQlkewgMI8BExmbrPiAOOmdO9aFfhFRYlj9+y5YbSJocZ7cxkrHFdmHifyQf0nZT
# ssmR0xhiukl6nvEK/ye53OHhkptC5L6Es2+hKsc1iH4QPbvXcWxPXE15lg/7ub18
# SeLHkRITNpzzuYPBJE+i7lZBytuLq9Ivhwe96OU9RYwdhWe8sWdVMdzDgfysDorA
# H33BD9QYdiPU5mXChEXv08YNf9gSsP5Zd97dphzG1leBkI3Y9Us6vki4n0UyDqQP
# /h78iOqDakl/aPoDPLQwPU4QQW45Jwaz3Cn7iNpkJaDsxuB+5I/epPFaBXEPAAEQ
# GLTuLRXlSJnWP2zvmmm5g+QFps4LIAVRpbIRVrBfz+e7FXaDRjajMRKfmr4RcZAo
# J5J6wvdfwbup6/4/J8L5MeAEpiA6+roL+ci2jJ8h1yINyUXsZe3WQG3CwtBdxjMt
# Qb/E/TdOWZi1hhQP0obQx0WB2X4bZqM1GjKb5r3pQkmKO+vJ34r9iXQPu8qMzeur
# ecOcLb46N5z4UWWTFtjaZIS6HJ+zUOEc2mjxiEz2UY5sal5+i1ncYwHBi5xslEiK
# O9X9CY5mhVXiiXyzeUF4EqAq2H5D2xojNAjrFAOaLO6EAJgGM3BhrDDAb5Vwei4s
# Qwewqtfrew+mRZ2ptEaAEXLaa3k23ymfScxCqnfA
# SIG # End signature block
