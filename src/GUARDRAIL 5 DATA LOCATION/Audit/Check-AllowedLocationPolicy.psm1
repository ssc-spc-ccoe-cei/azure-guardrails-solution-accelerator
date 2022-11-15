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
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    $AllowedLocations = @("canada" , "canadaeast" , "canadacentral")

    try {
        $managementGroups = Get-AzManagementGroup -ErrorAction Stop
    }
    catch {
        $Errorlist.Add("Failed to execute the 'Get-AzManagementGroup' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_")
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
                        $Errorlist.Add("Failed to execute the 'Get-AzPolicyAssignment' command for scope '$($c.id)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_" )
                        Write-Error "Error: Failed to execute the 'Get-AzPolicyAssignment' command for scope '$($c.id)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_"                
                    }
                    $AssignedPolicyLocation = $AssignedPolicyList.Properties.Parameters.listOfAllowedLocations.value

                    If ($null -eq $AssignedPolicyList) {
                        $c | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force | out-null
                        $c | Add-Member -MemberType NoteProperty -Name Comments -Value $($msgTable.policyNotAssigned -f $type) | out-null
                        $c | Add-Member -MemberType NoteProperty -Name ComplianceStatus -Value $false | out-null
                        $c | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName | out-null
                        $c | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName | out-null
                        $c | Add-Member -MemberType NoteProperty -Name itsgcode -Value $itsgcode | out-null
                        $NonCompliantList.add($c)
                    }
                    elseif (-not ([string]::IsNullOrEmpty(($AssignedPolicyList.Properties.NotScopesScope)))   ) {
                        $c | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force | out-null
                        $c | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName | out-null
                        $c | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName | out-null
                        $c | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $false | out-null
                        $c | Add-Member -MemberType NoteProperty -Name itsgcode -Value $itsgcode | out-null
                        if (-not (Test-AllowedLocation -AssignedLocations $AssignedPolicyLocation -AllowedLocations $AllowedLocations)  ) {
                            $c | Add-Member -MemberType NoteProperty -Name Comments -Value $($msgTable.excludedFromScope -f $type + $msgTable.notAllowedLocation) | out-null
                        }
                        else {
                            $c | Add-Member -MemberType NoteProperty -Name Comments -Value $($msgTable.excludedFromScope -f $type) | out-null
                        }
                        $NonCompliantList.add($c)  
                    }
                    else {
                        $c | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force | out-null
                        $c | Add-Member -MemberType NoteProperty -Name Comments -Value $msgTable.isCompliant | out-null
                        $c | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $true | out-null
                        $c | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName | out-null
                        $c | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName | out-null
                        $c | Add-Member -MemberType NoteProperty -Name itsgcode -Value $itsgcode | out-null
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
                        $Errorlist.Add("Failed to execute the 'Get-AzPolicyAssignment' command for scope '$($c.id)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_")
                        Write-Error "Error: Failed to execute the 'Get-AzPolicyAssignment' command for scope '$($c.id)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_"                
                    }

                    If ($null -eq $AssignedPolicyList) {
                        $c | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force | out-null
                        $c | Add-Member -MemberType NoteProperty -Name Comments -Value $($msgTable.policyNotAssigned -f $type) | out-null
                        $c | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $false | out-null
                        $c | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName | out-null
                        $c | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName | out-null
                        $c | Add-Member -MemberType NoteProperty -Name itsgcode -Value $itsgcode | out-null
                        $NonCompliantList.add($c)
                    }
                    elseif (-not ([string]::IsNullOrEmpty(($AssignedPolicyList.Properties.NotScopesScope)))) {
                        $c | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force | out-null
                        $c | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName | out-null
                        $c | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName | out-null
                        $c | Add-Member -MemberType NoteProperty -Name itsgcode -Value $itsgcode | out-null
                        $c | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $false | out-null
                        if (-not (Test-AllowedLocation -AssignedLocations $AssignedPolicyLocation -AllowedLocations $AllowedLocations)  ) {
                            $c | Add-Member -MemberType NoteProperty -Name Comments -Value $($msgTable.excludedFromScope -f $type + $msgTable.notAllowedLocation) | out-null
                        }
                        else {
                            $c | Add-Member -MemberType NoteProperty -Name Comments -Value $($msgTable.excludedFromScope -f $type) | out-null
                        }
                        $NonCompliantList.add($c)  
                    }
                    else {       
                        $c | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force | out-null
                        $c | Add-Member -MemberType NoteProperty -Name Comments -Value $msgTable.isCompliant | out-null
                        $c | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $true | out-null
                        $c | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName | out-null
                        $c | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName | out-null
                        $c | Add-Member -MemberType NoteProperty -Name itsgcode -Value $itsgcode | out-null
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
        $Errorlist.Add("Failed to execute the 'Get-AzPolicyAssignment' command for scope '$($RootMG.Id)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_")
        Write-Error "Error: Failed to execute the 'Get-AzPolicyAssignment' command for scope '$($RootMG.Id)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_"                
    }
    If ($null -eq $AssignedPolicyList) {
        $RootMG | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force | out-null
        $RootMG | Add-Member -MemberType NoteProperty -Name Comments -Value $msgTable.policyNotAssignedRootMG | out-null
        $RootMG | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $false | out-null
        $RootMG | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName | out-null
        $RootMG | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName | out-null
        $RootMG | Add-Member -MemberType NoteProperty -Name itsgcode -Value $itsgcode | out-null
        $NonCompliantList.add($RootMG)
    }
    elseif (-not ([string]::IsNullOrEmpty(($AssignedPolicyList.Properties.NotScopesScope)))) {
        $RootMG | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force | out-null
        $RootMG | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName | out-null
        $RootMG | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName | out-null
        $RootMG | Add-Member -MemberType NoteProperty -Name itsgcode -Value $itsgcode | out-null
        $RootMG | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $false | out-null
        if (-not (Test-AllowedLocation -AssignedLocations $AssignedPolicyLocation -AllowedLocations $AllowedLocations)  ) {
            $RootMG | Add-Member -MemberType NoteProperty -Name Comments -Value $($msgTable.rootMGExcluded + $msgTable.notAllowedLocation) | out-null
        }
        else {
            $RootMG | Add-Member -MemberType NoteProperty -Name Comments -Value $msgTable.rootMGExcluded | out-null
        }
        $NonCompliantList.add($RootMG)  
    }
    else {       
        $RootMG | Add-Member -MemberType NoteProperty -Name Comments -Value $msgTable.isCompliant | out-null
        $RootMG | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $true | out-null
        $RootMG | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName -Force | out-null
        $RootMG | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName -Force | out-null
        $RootMG | Add-Member -MemberType NoteProperty -Name itsgcode -Value $itsgcode | out-null
        $RootMG | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force | out-null
        $CompliantList.add($RootMG) 
    }
    $finalList = $CompliantList + $NonCompliantList
    <#
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
    #>
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $finalList 
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput  
}

# SIG # Begin signature block
# MIInoQYJKoZIhvcNAQcCoIInkjCCJ44CAQExDzANBglghkgBZQMEAgEFADB5Bgor
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
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZdjCCGXICAQEwgZUwfjELMAkG
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
# a+xZApQISQ8dpnruW+Vbb4upCLJ3D3w8rDm/pea6JoceoYIXADCCFvwGCisGAQQB
# gjcDAwExghbsMIIW6AYJKoZIhvcNAQcCoIIW2TCCFtUCAQMxDzANBglghkgBZQME
# AgEFADCCAVEGCyqGSIb3DQEJEAEEoIIBQASCATwwggE4AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIAsQteoCa9bMLcpNM+dr0V9Hc7BV+0ImgZ/W6m6C
# 1Cr7AgZjSDbMYZEYEzIwMjIxMTAyMTQyNDU3LjU0NlowBIACAfSggdCkgc0wgcox
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1p
# Y3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJjAkBgNVBAsTHVRoYWxlcyBUU1Mg
# RVNOOkU1QTYtRTI3Qy01OTJFMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNloIIRVzCCBwwwggT0oAMCAQICEzMAAAGVt/wN1uM3MSUAAQAAAZUw
# DQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcN
# MjExMjAyMTkwNTEyWhcNMjMwMjI4MTkwNTEyWjCByjELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2Eg
# T3BlcmF0aW9uczEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046RTVBNi1FMjdDLTU5
# MkUxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCfbUEMZ7ZLOz9aoRCeJL4hhT9Q8JZB
# 2xaVlMNCt3bwhcTI5GLPrt2e93DAsmlqOzw1cFiPPg6S5sLCXz7LbbUQpLha8S4v
# 2qccMtTokEaDQS+QJErnAsl6VSmRvAy0nlj+C/PaZuLb3OzY0ARw7UeCZLpyWPPH
# +k5MdYj6NUDTNoXqbzQHCuPs+fgIoro5y3DHoO077g6Ir2THIx1yfVFEt5zDcFPO
# YMg4yBi4A6Xc3hm9tZ6w849nBvVKwm5YALfH3y/f3n4LnN61b1wzAx3ZCZjf13UK
# bpE7p6DYJrHRB/+pwFjG99TwHH6uXzDeZT6/r6qH7AABwn8fpYc1TmleFY8YRuVz
# zjp9VkPHV8VzvzLL7QK2kteeXLL/Y4lvjL6hzyOmE+1LVD3lEbYho1zCt+F7bU+F
# pjyBfTC4i/wHsptb218YlbkQt1i1B6llmJwVFwCLX7gxQ48QIGUacMy8kp1+zczY
# +SxlpaEgNmQkfc1raPh9y5sMa6X48+x0K7B8OqDoXcTiECIjJetxwtuBlQseJ05H
# RfisfgFm09kG7vdHEo3NbUuMMBFikc4boN9Ufm0iUhq/JtqV0Kwrv9Cv3ayDgdNw
# EWiL2a65InEWSpRTYfsCQ03eqEh5A3rwV/KfUFcit+DrP+9VcDpjWRsCokZv4tgn
# 5qAXNMtHa8NiqQIDAQABo4IBNjCCATIwHQYDVR0OBBYEFKuX02ICFFdXgrcCBmDJ
# fH5v/KkXMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRY
# MFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01p
# Y3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEF
# BQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
# a2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAo
# MSkuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZI
# hvcNAQELBQADggIBAOCzNt4fJ+jOvQuq0Itn37IZrYNBGswAi+IAFM3YGK/wGQlE
# ncgjmNBuac95W2fAL6xtFVfMfkeqSLMLqoidVsU9Bm4DEBjaWNOT9uX/tcYiJSfF
# QM0rDbrl8V4nM88RZF56G/qJW9g5dIqOSoimzKUt/Q7WH6VByW0sar5wGvgovK3q
# FadwKShzRYcEqTkHH2zip5e73jezPHx2+taYqJG5xJzdDErZ1nMixRjaHs3Kpcsm
# ZYuxsIRfBYOJvAFGymTGRv5PuwsNps9Ech1Aasq84H/Y/8xN3GQj4P3MiDn8izUB
# DCuXIfHYk39bqnaAmFbUiCby+WWpuzdk4oDKz/sWwrnsoQ72uEGVEN7+kyw9+HSo
# 5i8l8Zg1Ymj9tUgDpVUGjAduoLyHQ7XqknKmS9kJSBKk4okEDg0Id6LeKLQwH1e4
# aVeTyUYwcBX3wg7pLJQWvR7na2SGrtl/23YGQTudmWOryhx9lnU7KBGV/aNvz0tT
# pcsucsK+cZFKDEkWB/oUFVrtyun6ND5pYZNj0CgRup5grVACq/Agb+EOGLCD+zEt
# GNop4tfKvsYb64257NJ9XrMHgpCib76WT34RPmCBByxLUkHxHq5zCyYNu0IFXAt1
# AVicw14M+czLYIVM7NOyVpFdcB1B9MiJik7peSii0XTRdl5/V/KscTaCBFz3MIIH
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
# aGFsZXMgVFNTIEVTTjpFNUE2LUUyN0MtNTkyRTElMCMGA1UEAxMcTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUA0Y+CyLezGgVHWFNm
# KI1LuE/hY6uggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAN
# BgkqhkiG9w0BAQUFAAIFAOcMabgwIhgPMjAyMjExMDIxMTU5NTJaGA8yMDIyMTEw
# MzExNTk1MlowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA5wxpuAIBADAKAgEAAgIZ
# AgIB/zAHAgEAAgISmTAKAgUA5w27OAIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgor
# BgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBBQUA
# A4GBADBzRFCgbhDlLxMKQWulDZQp8LLZPXbO6HVo4E36SaOacV+HTfhByDnI+MPH
# fcHQZ3IlJn8SQiP6u6jPi2km87L+lwmR7W9U69QEbmXpiMYavajHZ3V4F8SF/h0h
# KACUrfOVHb0qLuTZFNZGZgGzFD4Akkk/2atLy8oeMaLla84fMYIEDTCCBAkCAQEw
# gZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGVt/wN1uM3MSUA
# AQAAAZUwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0B
# CRABBDAvBgkqhkiG9w0BCQQxIgQg8XwR8GXg2paTtKCltMyMeK+w+GjPfx35gOm8
# l7gl5skwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCBc5kvhjZALe2mhIz/Q
# d7keVOmA/cC1dzKZT4ybLEkCxzCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwAhMzAAABlbf8DdbjNzElAAEAAAGVMCIEINUqkhouZcBE7EyWuqop
# lWQ49HcuAXM1MVtlexQkK5OQMA0GCSqGSIb3DQEBCwUABIICAHpjyMWXiXgOsSId
# r9ur6Nc4dTeUdbTBQ4MOfWbyIHNQiHbBdK6RQZAGHR0DNDoHutHE3EnvbiZ22Al8
# NacjmlnwSgDci4zOD1pKlG96lD8M5mX6qHfOhSZx7QpSsNnrR9HkTNG6Ph3Ky7rp
# wnGAVpZO5HoKmLfAfZhAOl5IO62lsIjHo2l7Kj2zg7qyw5wyiMgH+V7aSPV3u0Mc
# PXQNcXKVCjAzcHOGNuWZbZiUK9M2lUCoCrozjOpQSeGF2RkFoM7zRAvh4FgATcQ4
# GnkmxeKx9PzuWFwNVWu2JEKyDkbAKUl+Pzy+kGz4HZ/fVpXMRuVysJHSKX5xLQU7
# KWq0b7yLBAz15pJbUjWDAB9XK9+Tw8UyJ/wVPOXaGfGt+piEsV+D0XmASrjqDp4R
# nhb5Pr8FP3ict2GOczMaaKsPIikmcoEhkfjU+vg8VGoXfEMagDEY7Z5UySZajZTO
# mZRZUm2rfZlB11NPCnQ77hbFJ6xFNoXs3rLKxnrfO/6GYYT4xrcn+Dk3m4PM1jhW
# 2OZ71BJ1bvNj2MGENhs4dI6paqLkpbBndm67DKG9Ana2wRhz6A0ZoIgcVOwNBC/D
# oaLtr/UmaQE65tEI0iq6nT+6hw+jU1Xn5YEZgJzV6tpDtVfvGNpt6XtbXbfGwV7q
# 6LPnw5CR09lZG3ifCjxhGQgDXuEm
# SIG # End signature block
