function Verify-AllowedLocationPolicy {
    param (
        [switch] $DebugData,
        [string] $ControlName,
        [string] $ItemName,
        [string] $PolicyID, 
        [string] $WorkSpaceID,
        [string] $workspaceKey,
        [string] $LogType,
        [string] $itsgcode,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime,
        [Parameter(Mandatory=$true)]
        [string]
        $CBSSubscriptionName
    )

    #$PolicyID = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"

    [System.Object] $RootMG = $null
    [string] $PolicyID = $policyID
    [PSCustomObject] $MGList = New-Object System.Collections.ArrayList
    [PSCustomObject] $MGItems = New-Object System.Collections.ArrayList
    [PSCustomObject] $SubscriptionList = New-Object System.Collections.ArrayList
    [PSCustomObject] $CompliantList = New-Object System.Collections.ArrayList
    [PSCustomObject] $NonCompliantList = New-Object System.Collections.ArrayList

    $AllowedLocations = @("canada" , "canadaeast" , "canadacentral")

    try {
        $managementGroups = Get-AzManagementGroup -ErrorAction Stop
    }
    catch {
        Add-LogEntry 'Error' "Failed to execute the 'Get-AzManagementGroup' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_" -workspaceGuid $WorkSpaceID -workspaceKey $WorkSpaceKey
        throw "Error: Failed to execute the 'Get-AzManagementGroup' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_"
    }
    
    foreach ($mg in $managementGroups) {
        $MG = Get-AzManagementGroup -GroupName $mg.Name -Expand -Recurse
        $MGItems.Add($MG)
        if ($null -eq $MG.ParentId) {
            $RootMG = $MG
        }
    }
    foreach ($items in $MGItems) {
        foreach ($Children in $items.Children ) {
            foreach ($c in $Children) {
                if ($c.Type -eq "/subscriptions" -and (-not $SubscriptionList.Contains($c) -and $c.DisplayName -ne $CBSSubscriptionName)) {
                    [string]$type = "subscription"
                    $SubscriptionList.Add($c)

                    try {
                        $AssignedPolicyList = Get-AzPolicyAssignment -scope $c.Id -PolicyDefinitionId $PolicyID -ErrorAction Stop
                    }
                    catch {
                        Add-LogEntry 'Error' "Failed to execute the 'Get-AzPolicyAssignment' command for scope '$($c.id)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_" -workspaceGuid $WorkSpaceID -workspaceKey $WorkSpaceKey
                        Write-Error "Error: Failed to execute the 'Get-AzPolicyAssignment' command for scope '$($c.id)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_"                
                    }
                    $AssignedPolicyLocation = $AssignedPolicyList.Properties.Parameters.listOfAllowedLocations.value

                    If ($null -eq $AssignedPolicyList) {
                        $c | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
                        $c | Add-Member -MemberType NoteProperty -Name Comments -Value $($msgTable.policyNotAssigned -f $type)
                        $c | Add-Member -MemberType NoteProperty -Name ComplianceStatus -Value $false
                        $c | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName
                        $c | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName
                        $c | Add-Member -MemberType NoteProperty -Name itsgcode -Value $itsgcode
                        $NonCompliantList.add($c)
                    }
                    elseif (-not ([string]::IsNullOrEmpty(($AssignedPolicyList.Properties.NotScopesScope)))   ) {
                        $c | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
                        $c | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName
                        $c | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName
                        $c | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $false
                        $c | Add-Member -MemberType NoteProperty -Name itsgcode -Value $itsgcode
                        if (-not (Test-AllowedLocation -AssignedLocations $AssignedPolicyLocation -AllowedLocations $AllowedLocations)  ) {
                            $c | Add-Member -MemberType NoteProperty -Name Comments -Value $($msgTable.excludedFromScope -f $type + $msgTable.notAllowedLocation)
                        }
                        else {
                            $c | Add-Member -MemberType NoteProperty -Name Comments -Value $($msgTable.excludedFromScope -f $type)
                        }
                        $NonCompliantList.add($c)  
                    }
                    else {
                        $c | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
                        $c | Add-Member -MemberType NoteProperty -Name Comments -Value $msgTable.isCompliant
                        $c | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $true
                        $c | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName
                        $c | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName
                        $c | Add-Member -MemberType NoteProperty -Name itsgcode -Value $itsgcode
                        $CompliantList.add($c) 
                    }
                }
                elseif ($c.Type -like "*managementGroups*" -and (-not $MGList.Contains($c)) ) {
                    [string]$type = "Management Groups"
                    $MGList.Add($c)

                    try {
                        $AssignedPolicyList = Get-AzPolicyAssignment -scope $c.Id -PolicyDefinitionId $PolicyID -ErrorAction Stop
                    }
                    catch {
                        Add-LogEntry 'Error' "Failed to execute the 'Get-AzPolicyAssignment' command for scope '$($c.id)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_" -workspaceGuid $WorkSpaceID -workspaceKey $WorkSpaceKey
                        Write-Error "Error: Failed to execute the 'Get-AzPolicyAssignment' command for scope '$($c.id)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_"                
                    }

                    If ($null -eq $AssignedPolicyList) {
                        $c | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
                        $c | Add-Member -MemberType NoteProperty -Name Comments -Value $($msgTable.policyNotAssigned -f $type)
                        $c | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $false
                        $c | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName
                        $c | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName
                        $c | Add-Member -MemberType NoteProperty -Name itsgcode -Value $itsgcode
                        $NonCompliantList.add($c)
                    }
                    elseif (-not ([string]::IsNullOrEmpty(($AssignedPolicyList.Properties.NotScopesScope)))) {
                        $c | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
                        $c | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName
                        $c | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName
                        $c | Add-Member -MemberType NoteProperty -Name itsgcode -Value $itsgcode
                        $c | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $false
                        if (-not (Test-AllowedLocation -AssignedLocations $AssignedPolicyLocation -AllowedLocations $AllowedLocations)  ) {
                            $c | Add-Member -MemberType NoteProperty -Name Comments -Value $($msgTable.excludedFromScope -f $type + $msgTable.notAllowedLocation)
                        }
                        else {
                            $c | Add-Member -MemberType NoteProperty -Name Comments -Value $($msgTable.excludedFromScope -f $type)
                        }
                        $NonCompliantList.add($c)  
                    }
                    else {       
                        $c | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
                        $c | Add-Member -MemberType NoteProperty -Name Comments -Value $msgTable.isCompliant
                        $c | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $true
                        $c | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName
                        $c | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName
                        $c | Add-Member -MemberType NoteProperty -Name itsgcode -Value $itsgcode
                        $CompliantList.add($c) 
                    }
                }
            }                
        }
    }


    try {
        $AssignedPolicyList = Get-AzPolicyAssignment -scope $RootMG.Id -PolicyDefinitionId $PolicyID -ErrorAction Stop
    }
    catch {
        Add-LogEntry 'Error' "Failed to execute the 'Get-AzPolicyAssignment' command for scope '$($RootMG.Id)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_" -workspaceGuid $WorkSpaceID -workspaceKey $WorkSpaceKey
        Write-Error "Error: Failed to execute the 'Get-AzPolicyAssignment' command for scope '$($RootMG.Id)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_"                
    }
    If ($null -eq $AssignedPolicyList) {
        $RootMG | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
        $RootMG | Add-Member -MemberType NoteProperty -Name Comments -Value $msgTable.policyNotAssignedRootMG
        $RootMG | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $false
        $RootMG | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName
        $RootMG | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName
        $RootMG | Add-Member -MemberType NoteProperty -Name itsgcode -Value $itsgcode
        $NonCompliantList.add($RootMG)
    }
    elseif (-not ([string]::IsNullOrEmpty(($AssignedPolicyList.Properties.NotScopesScope)))) {
        $RootMG | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
        $RootMG | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName
        $RootMG | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName
        $RootMG | Add-Member -MemberType NoteProperty -Name itsgcode -Value $itsgcode
        $RootMG | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $false
        if (-not (Test-AllowedLocation -AssignedLocations $AssignedPolicyLocation -AllowedLocations $AllowedLocations)  ) {
            $RootMG | Add-Member -MemberType NoteProperty -Name Comments -Value $($msgTable.rootMGExcluded + $msgTable.notAllowedLocation)
        }
        else {
            $RootMG | Add-Member -MemberType NoteProperty -Name Comments -Value $msgTable.rootMGExcluded
        }
        $NonCompliantList.add($RootMG)  
    }
    else {       
        $RootMG | Add-Member -MemberType NoteProperty -Name Comments -Value $msgTable.isCompliant
        $RootMG | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $true
        $RootMG | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName -Force
        $RootMG | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName -Force
        $RootMG | Add-Member -MemberType NoteProperty -Name itsgcode -Value $itsgcode
        $RootMG | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
        $CompliantList.add($RootMG) 
    }
    if ($CompliantList.Count -gt 0) {
        $JsonObject = $CompliantList | convertTo-Json
        if ($DebugData) {
            "Sending Compliant data."
            "Id: $WorkSpaceID"
            "Key: $workspaceKey"
            "Body: $JsonObject"
        }
        Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
            -sharedkey $workspaceKey `
            -body $JsonObject `
            -logType $LogType `
            -TimeStampField Get-Date
    }
    if ($NonCompliantList.Count -gt 0) {
        $JsonObject = $NonCompliantList | convertTo-Json  
        if ($DebugData) {
            "Sending Non-Compliant data."
            "Id: $WorkSpaceID"
            "Key: $workspaceKey"
            "Body: $JsonObject"
        }
        Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
            -sharedkey $workspaceKey `
            -body $JsonObject `
            -logType $LogType `
            -TimeStampField Get-Date
    }
}


function Test-AllowedLocation {
    param (
        [array] $AssignedLocations,
        [array] $AllowedLocations
    )
    $IsCompliant = $true
    foreach ($AssignedLocation in $AssignedLocations) {
        if ( $AssignedLocation -notin $AllowedLocations) {
            $IsCompliant = $false
        }
    }
    return $IsCompliant 
}


# SIG # Begin signature block
# MIInqgYJKoZIhvcNAQcCoIInmzCCJ5cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDv3X/bZ1cgpXsC
# KijtnHO8iDUbBDGkcWMhqPgOd5TJZKCCDYEwggX/MIID56ADAgECAhMzAAACzI61
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
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgYrdYob4+
# Pa5jbyW+4AYa4pWMHjsedHa9rpKUUxAuFBQwQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQBOhN1f7yd1Mg0Ghl3kSS75SSOu6/c0WWpOvSO96FJH
# rXj8oSagiBQaLZrEM700+++Dr8IaJOt13mYOfXHx5wE5W1wqgRa7hutpeM9k3rHk
# tVA/4n/QQvhSARoxFlk6n4rlKlzWmNsgo5Az3VgVew30xXJaUUsMxDgvWI6GBsXt
# 95l9wGg1ANiFnB7/O9AIF04bHNpiXBLzitxKnXZSwQ703rS2EhcdvjlcpkN3I0rT
# uDNBJu+r6wYk/cD1q4jljls7Nku7q3SvQyv+tcyQV0Yx6aCfG7Vaty/NBwAz7bph
# a+xZApQISQ8dpnruW+Vbb4upCLJ3D3w8rDm/pea6JoceoYIXCTCCFwUGCisGAQQB
# gjcDAwExghb1MIIW8QYJKoZIhvcNAQcCoIIW4jCCFt4CAQMxDzANBglghkgBZQME
# AgEFADCCAVUGCyqGSIb3DQEJEAEEoIIBRASCAUAwggE8AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIAsQteoCa9bMLcpNM+dr0V9Hc7BV+0ImgZ/W6m6C
# 1Cr7AgZjKeH1KGYYEzIwMjIxMDAzMjE0MzQyLjk5NFowBIACAfSggdSkgdEwgc4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1p
# Y3Jvc29mdCBPcGVyYXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMg
# VFNTIEVTTjpGNzdGLUUzNTYtNUJBRTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgU2VydmljZaCCEVwwggcQMIIE+KADAgECAhMzAAABqqUxmwvLsggOAAEA
# AAGqMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# MB4XDTIyMDMwMjE4NTEyNloXDTIzMDUxMTE4NTEyNlowgc4xCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVy
# YXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpGNzdG
# LUUzNTYtNUJBRTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vydmlj
# ZTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAKBP7HK51bWHf+FDSh9O
# 7YyrQtkNMvdHzHiazvOdI9POGjyJIYrs1WOMmSCp3o/mvsuPnFSP5c0dCeBuUq6u
# 6J30M81ZaNOP/abZrTwYrYN+N5nStrOGdCtRBum76hy7Tr3AZDUArLwvhsGlXhLl
# DU1wioaxM+BVwCNI7LmTaYKqjm58hEgsYtKIHk59LzOnI4aenbPLBP/VYYjI6a4K
# Icun0EZErAukt5PC/mKUaOphUMGYm0PxfpY9BkG5sPfczFyIfA13LLRS4sGhbUrc
# M54EvE2FlWBQaJo7frKW7CVjITLEX4E2lxwQG/MuZ+1wDYg9OOErT5h+6zecj67e
# enwxeUoaOEbKtiUxaJUYnyQKxCWTkNdWRXTKSmIxx0tbsP5irWjqXvT6t/zeJKw0
# 5NY8hPT56vW20q0DYK2NteOCDD0UD6ZNAFLV87GOkl0eBqXcToFVdeJwwOTE6aA4
# RqYoNr2QUPBIU6JEiUGBs9c4qC5mBHTY46VaR/odaFDLcxQI4OPkn5al/IPsd8/r
# aDmMfKik66xcNh2qN4yytYM3uiDenX5qeFdx3pdi43pYAFN/S1/3VRNk+/GRVUUY
# WYBjDZSqxslidE8hsxC7K8qLfmNoaQ2aAsu13h1faTMSZIEVxosz1b9yIeXmtM6N
# lrjV3etwS7JXYwGhHMdVYEL1AgMBAAGjggE2MIIBMjAdBgNVHQ4EFgQUP5oUvFOH
# Lthfd0Wz3hGtnQVGpJ4wHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIw
# XwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
# cy9jcmwvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3Js
# MGwGCCsGAQUFBwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENB
# JTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcD
# CDANBgkqhkiG9w0BAQsFAAOCAgEA3wyATZBFEBogrcwHs4zI7qX2y0jbKCI6ZieG
# AIR96RiMrjZvWG39YPA/FL2vhGSCtO7ea3iBlwhhTyJEPexLugT4jB4W0rldOLP5
# bEc0zwxs9NtTFS8Ul2zbJ7jz5WxSnhSHsfaVFUp7S6B2a1bjKmWIo/Svd3W1V3mc
# IYzhbpLIUVlP3CbTJEE+cC3hX+JggnSYRETyo+mI7Hz/KMWFaRWBUYI4g0BrwiV2
# lYqKyekjNp6rj7b8l6OhbgX/JP0bzNxv6io0Y4iNlIzz/PdIh/E2pj3pXPiQJPRl
# EkMksRecE8VnFyqhR4fb/F6c5ywY4+mEpshIAg2YUXswFqqbK9Fv+U8YYclYPvhK
# /wRZs+/5auK4FM+QTjywj0C5rmr8MziqmUGgAuwZQYyHRCopnVdlaO/xxSZCfaZR
# 7w7B3OBEl8j+Voofs1Kfq9AmmQAWZOjt4DnNk5NnxThPvjQVuOU/y+HTErwqD/wK
# RCl0AJ3UPTJ8PPYp+jbEXkKmoFhU4JGer5eaj22nX19pujNZKqqart4yLjNUOkqW
# jVk4KHpdYRGcJMVXkKkQAiljUn9cHRwNuPz/Tu7YmfgRXWN4HvCcT2m1QADinOZP
# sO5v5j/bExw0WmFrW2CtDEApnClmiAKchFr0xSKE5ET+AyubLapejENr9vt7QXNq
# 6aP1XWcwggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3
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
# MSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpGNzdGLUUzNTYtNUJBRTElMCMGA1UE
# AxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUA
# 4G0m0J4eAlljcP/jvOv9/pm/68aggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMDANBgkqhkiG9w0BAQUFAAIFAOblg30wIhgPMjAyMjEwMDMxOTUx
# MjVaGA8yMDIyMTAwNDE5NTEyNVowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA5uWD
# fQIBADAHAgEAAgISAzAHAgEAAgIRTjAKAgUA5ubU/QIBADA2BgorBgEEAYRZCgQC
# MSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqG
# SIb3DQEBBQUAA4GBAKzvmo+TW9rPtMXUhrwNnKRro6AlLJ0f7hiMrrYhyPRvx36d
# cl94RpWK19gZSZ3VCqsoGLnmGQOrvuQpCJkrUAyH4nJqkU/vk7DiUXjM/ZthFHpd
# t+PTGKV0KihUaj5DSOTSx+yns9wwCBwTu7PoyY9kqExRXxqlT5HdtPwU/YYXMYIE
# DTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGq
# pTGbC8uyCA4AAQAAAaowDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzEN
# BgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgIYu6jtF85uH/pEGrue4WRbWO
# ybzce4Lkl68Tg8hMzEcwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCBWtQJD
# HFq8EeBz3TXugCqRhSI/JCZbATYEIwTG8bMewDCBmDCBgKR+MHwxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABqqUxmwvLsggOAAEAAAGqMCIEIICrxeRQ
# dFEl0pOWCIUAwrZaZuVi3qRMO3Kc8I8iE1mFMA0GCSqGSIb3DQEBCwUABIICAB6m
# BO2JH6q30DhKt6CJIoFIKm/Se9NBzLcC9jLlnre4zEnx3k7CtlMWj3SYCtyi4idx
# s+BXKv1uQH2JUEgzOHinlA94mQRYcDoehM293bTYJeMam0gf5B3INUsAVzSHKfkR
# gCZb5ydeYcGElOGPhoaTUhboxTd9WQ9UB7bPtNk1z+rCkEMLBQbKlIuj9+wspIbr
# 9sLMz0lDBnnt9t44HNxLg0cKMujL6d0JxIEfiNwjxN5gDl2sroi7m4fKIwbyVnmZ
# g8bSsLPoAPoop84xMwWXXTNuuZL7yNsQi+vca5Am50Rzne8v0rYxMv+R9AJt7ylT
# ukskWJaEUMLpHP+pLn4dXFoX73eUhvDZkKYlns4bywpDyOFiyLn63LgAswtd6rfd
# rwI71WWvDAACGfFKnGNR7Y740PKwzKu+J3QPzMFj93CboL7LqAvTsHEmtytvk8M9
# 5IcRcZdgocsOaj2UmrKbj6GSjN46wNBevufmNV5fxY0EO5dZw1hwQcrZHT0WAAT5
# CEWynEG/MUCihRUb3T65V8cM+49SLFjmGRUVFmLy86+l9ATQMEF1VjSVBNZGFk1c
# nYvqeubG9uRH7+TMre7rMFH5wQPfNrTHcAnKz5Iwu264kgxRO57cS9qlfDF3ZbMv
# Im2G3AzLqpAj7XbfJZ75ELJEXPxuUaIt0lc+ZbbH
# SIG # End signature block
