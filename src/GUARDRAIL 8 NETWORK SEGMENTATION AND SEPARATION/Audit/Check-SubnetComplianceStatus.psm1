
function Get-SubnetComplianceInformation {
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $ControlName,
        [string] $itsgcodesegmentation,
        [string] $itsgcodeseparation,
        [Parameter(Mandatory=$false)]
        [string]
        $ExcludedSubnetsList,#Separated by command, simple string
        [Parameter(Mandatory=$false)]
        [string]$ReservedSubnetList, #Separated by command, simple string
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime,
        [Parameter(Mandatory=$true)]
        [string]
        $CBSSubscriptionName,
        [Parameter(Mandatory=$false)]
        [switch]
        $debuginfo
    )
    #module for Tags handling
    #import-module '..\..\GUARDRAIL COMMON\Get-Tags.psm1'
    [PSCustomObject] $SubnetList = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    $AdditionalResults= $null
    
    $reservedSubnetNames=$ReservedSubnetList.Split(",")
    $ExcludedSubnets=$ExcludedSubnetsList.Split(",")
    $allexcluded=$ExcludedSubnets+$reservedSubnetNames

    try {
        $subs=Get-AzSubscription -ErrorAction Stop  | Where-Object {$_.State -eq 'Enabled' -and $_.Name -ne $CBSSubscriptionName}  
    }
    catch {
        $ErrorList.Add("Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Accounts module; returned error message: $_")
        throw "Error: Failed to execute the 'Get-AzSubscription'--verify your permissions and the installion of the Az.Accounts module; returned error message: $_"                
    }

    # if ($ExcludedSubnets -ne $null)
    # {
    #     $ExcludedSubnetsList=$ExcludedSubnets.Split(",")
    # }
    foreach ($sub in $subs)
    {
        Write-Verbose "Selecting subscription: $($sub.Name)"
        Select-AzSubscription -SubscriptionObject $sub | Out-Null
        
        $VNets=Get-AzVirtualNetwork
        Write-Debug "Found $($VNets.count) VNets."
        if ($VNets)
        {
            foreach ($VNet in $VNets)
            {
                Write-Debug "Working on $($VNet.Name) VNet..."
                $ev=get-tagValue -tagKey "GR-ExcludeFromCompliance" -object $VNet # this will exclude the VNet from the compliance check, altogether.
                $ExcludeSubnetsTag=get-tagValue -tagKey "GR-ExcludedSubnets" -object $VNet
                if (!([string]::IsNullOrEmpty($ExcludeSubnetsTag)))
                {
                    $ExcludedSubnetListFromTag=$ExcludeSubnetsTag.Split(",")
                }
                else {
                    $ExcludedSubnetListFromTag=@()
                }

                if ($ev -ne "true")
                {
                    #Handles the subnets
                    foreach ($subnet in Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $VNet)
                    {
                        Write-Debug "Working on $($subnet.Name) Subnet..."
                        if ($subnet.Name -notin $allexcluded -and $subnet.Name -notin $ExcludedSubnetListFromTag)
                        {
                            #checks NSGs
                            $ComplianceStatus=$false
                            $Comments = $msgTable.noNSG
                            if ($null -ne $subnet.NetworkSecurityGroup)
                            {
                                Write-Debug "Found $($subnet.NetworkSecurityGroup.Id.Split("/")[8]) NSG"
                                #Add routine to analyze NSG regarding standard rules.
                                $nsg=Get-AzNetworkSecurityGroup -Name $subnet.NetworkSecurityGroup.Id.Split("/")[8] -ResourceGroupName $subnet.NetworkSecurityGroup.Id.Split("/")[4]
                                if ($nsg.SecurityRules.count -ne 0) #NSG has other rules on top of standard rules.
                                {
                                    $LastSecurityRule=($nsg.SecurityRules | Sort-Object Priority -Descending)[0]
                                    if ($LastSecurityRule.DestinationAddressPrefix -eq '*' -and $LastSecurityRule.Access -eq "Deny") # Determine all criteria for good or bad here...
                                    {
                                        $ComplianceStatus=$true
                                        $Comments = $msgTable.subnetCompliant
                                    }
                                    else {
                                        $ComplianceStatus=$false
                                        $Comments = $msgTable.nsgConfigDenyAll
                                    }
                                }
                                else {
                                    #NSG is present but has no custom rules at all.
                                    $ComplianceStatus=$false
                                    $Comments = $msgTable.nsgCustomRule
    
                                }
                            }
                            $SubnetObject = [PSCustomObject]@{ 
                                SubscriptionName  = $sub.Name 
                                SubnetName="$($VNet.Name)\$($subnet.Name)"
                                ComplianceStatus = $ComplianceStatus
                                Comments = $Comments
                                ItemName = $msgTable.networkSegmentation
                                ControlName = $ControlName
                                itsgcode = $itsgcodesegmentation
                                ReportTime = $ReportTime
                            }
                            $SubnetList.add($SubnetObject) | Out-Null
                            #Checks Routes
                            if ($subnet.RouteTable)
                            {
                                $UDR=$subnet.RouteTable.Id.Split("/")[8]
                                Write-Debug "Found $UDR UDR"
                                $routeTable=Get-AzRouteTable -ResourceGroupName $subnet.RouteTable.Id.Split("/")[4] -name $UDR
                                $ComplianceStatus=$false # I still don´t know if it has a UDR with 0.0.0.0 being sent to a Virtual Appliance.
                                $Comments = $msgTable.routeNVA
                                foreach ($route in $routeTable.Routes)
                                {
                                    if ($route.NextHopType -eq "VirtualAppliance" -and $route.AddressPrefix -eq "0.0.0.0/0") # Found the required UDR
                                    {
                                        $ComplianceStatus=$true
                                        $Comments= $msgTable.subnetCompliant
                                    }
                                }
                            }
                        }
                        else { #subnet excluded
                            $ComplianceStatus=$true
                            $Comments=$msgTable.subnetExcluded
                        }
                        $SubnetObject = [PSCustomObject]@{ 
                            SubscriptionName  = $sub.Name 
                            SubnetName="$($VNet.Name)\$($subnet.Name)"
                            ComplianceStatus = $ComplianceStatus
                            Comments = $Comments
                            ItemName = $msgTable.networkSeparation
                            itsgcode = $itsgcodeseparation
                            ControlName = $ControlName
                            ReportTime = $ReportTime
                        }
                        $SubnetList.add($SubnetObject) | Out-Null
                    }
                }
                else {
                    Write-Verbose "Excluding $($VNet.Name) based on tagging."
                }    
            }
        }
        else {
            #No subnets found
            $ComplianceStatus=$true
            $Comments="$($msgTable.noSubnets) - $($sub.Name)"
            $SubnetObject = [PSCustomObject]@{ 
                SubscriptionName  = $sub.Name 
                SubnetName=$msgTable.noSubnets
                ComplianceStatus = $ComplianceStatus
                Comments = $Comments
                ItemName = $msgTable.networkSegmentation
                ControlName = $ControlName
                itsgcode = $itsgcodesegmentation
                ReportTime = $ReportTime
            }
            $SubnetList.add($SubnetObject) | Out-Null
        }
    }
    if ($debug) {
        Write-Output "Listing $($SubnetList.Count) List members."
        $SubnetList |  select-object SubnetName, ComplianceStatus, Comments
    }
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $SubnetList
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput
}
<<<<<<< HEAD
=======

# SIG # Begin signature block
# MIInygYJKoZIhvcNAQcCoIInuzCCJ7cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBHXTK8ToxMq2SX
# D9jxdK81u6H84O+1hZqh/ItTnCOWdKCCDYEwggX/MIID56ADAgECAhMzAAACzI61
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
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZnzCCGZsCAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAsyOtZamvdHJTgAAAAACzDAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgWszF1K3l
# 1vvFN/GJ+N8Bhgh1Bsieko/tQnyOiElARn8wQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQAD4ZwLowncDYsal7lh5wmEbTwyWYHDbsOuxjqUq1a8
# KUyhpkopr/lKFoA9KGAKkvo7r/DypBIFGTz8tB3rWI4qri7E8/SVovfrvvvus5wp
# Llkc6m0O41VbYlwvPEuzeDf4zBVinS4Qa1+nFMEA/jxX9peCDGB7F+74EgZEJhlI
# 9SGX8X2QVVuqWTWHKzz8de1qFqc+Wa/BlgF4fT/GdtFM6HjVyNDBXfLbafci7oNq
# zuP34dsUTRD38CMD0PRh9WrrrKt8Lr0x+AwSvcnhXcrBpMGKt9qm3oOz72KZQ00A
# GkfRRgM1yFkPgnbZLbr06HpFW4rtN78G7rKJJtt4xuV5oYIXKTCCFyUGCisGAQQB
# gjcDAwExghcVMIIXEQYJKoZIhvcNAQcCoIIXAjCCFv4CAQMxDzANBglghkgBZQME
# AgEFADCCAVkGCyqGSIb3DQEJEAEEoIIBSASCAUQwggFAAgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIIyNeVUuGpHlRzj2w/8JeWaVxAHzf92wLCe68nDV
# qRkEAgZjx90lcdwYEzIwMjMwMTI1MjIyNTQzLjMyN1owBIACAfSggdikgdUwgdIx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1p
# Y3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhh
# bGVzIFRTUyBFU046MDg0Mi00QkU2LUMyOUExJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WgghF4MIIHJzCCBQ+gAwIBAgITMwAAAbJuQAN/bqmU
# kgABAAABsjANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDAeFw0yMjA5MjAyMDIyMDFaFw0yMzEyMTQyMDIyMDFaMIHSMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQg
# SXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1Mg
# RVNOOjA4NDItNEJFNi1DMjlBMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAyqJlMh17
# +VDisL4GaXl/9a6r/EpPGt9sbbceh+ZD6pkA3gbI7vc8XfL04B+m3tB/aNyV1Y4Z
# QH4fMG7CWVjI/d/HgxjzO+4C4HfsW+jK2c0LYMqdWtWUc5VwZQv0KeaEM0wDb+ey
# SMh/YiiIb0nSotivx268d1An0uLY+r2C7JJv2a9QvrSiCyUI72CSHoWIQPAyvBSv
# xaNrqMWlROfLy2DQ3RycI3bDh8qSnmplxtRgViJwtJv/oDukcK1frGeOrCGYmiJv
# e+QonJXFu4UtGFVfEf3lvQsd42GJ+feO+jaP7/hBXXSMSldVb6IL0GxO1Hr3G9ON
# TnVmA/sFHhgMRarsmzKVI6/kHlMdMNdF/XzhRHMWFPJvw5lApjuaoyHtzwnzDWwQ
# zhcNQXZRk3Lzb01ULMba190RdlofEXxGbGlBgHHKFnBjWui24hL6B83Z6r6GQBPe
# Kkafz8qYPAO3MBud+5eMCmB5mrCBxgnykMn7L/FTqi7MnPUG97lNOKGSIDvBCxB7
# pHrRmT10903PDQwrmeJHO5BkC3gYj3oWGOGVRZxRk4KS/8lcz84a7+uBKmVjB2Y8
# vPN8O1fK7L8YJTkjiXTyDqKJ9fKkyChiSRx44ADPi/HXHQE6dlZ8jd9LCo1S+g3u
# dxNP4wHhWm9/VAGmmMEBBS6+6Lp4IbQwJU0CAwEAAaOCAUkwggFFMB0GA1UdDgQW
# BBSZ8ieAXNkRmU+SMM5WW4FIMNpqcTAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQM
# MAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEA
# 3Ee27cXMhptoNtaqzB0oGUCEpdEI37kJIyK/ZNhriLZC5Yib732mLACEOEAN9uqi
# vXPIuL3ljoZCe8hZSB14LugvVm1nJ73bNgr4Qh/BhmaFL4IfiKd8DNS+xwdkXfCW
# slR89QgMZU/SUJhWx72aC68bR2qRjhrJA8Qc68m5uBllo52D83x0id3p8Z45z7QO
# gbMH4uJ45snZDQC0S3dc3eJfwKnr51lNfzHAT8u+FHA+lv/6cqyE7tNW696fB1PC
# oH8tPoI09oSXAV4rEqupFM8xsd6D6L4qcEt/CaERewyDazVBfskjF+9P3qZ3R6Iy
# OIwQ7bYts7OYsw13csg2jACdEEAm1f7f97f3QH2wwYwen5rVX6GCzrYCikGXSn/T
# SWLfQM3nARDkh/flmTtv9PqkTHqslQNgK2LvMJuKSMpNqcGc5z33MYyV6Plf58L+
# TkTFQKs6zf9XMZEJm3ku9VBJ1aqr9AzNMSaKbixvMBIr2KYSSM21lnK8LUKxRwPW
# +gWS2V3iYoyMT64MRXch10P4OtGT3idXM09K5ld7B9U6dcdJ6obvEzdXt+XZovi/
# U6Evb4nA7VPHcHSKs7U72ps10mTfnlue13VFJUqAzbYoUEeegvsmzulGEGJoqZVN
# Aag5v6PVBrur5yLEajjxWH2TfkEOwlL8MuhcVI8OXiYwggdxMIIFWaADAgECAhMz
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
# 7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIC1DCCAj0CAQEwggEAoYHYpIHVMIHSMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxl
# cyBUU1MgRVNOOjA4NDItNEJFNi1DMjlBMSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQCOEn4R7JJF+fYoI2yOf1wX
# 0BRJOqCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
# SIb3DQEBBQUAAgUA53uV9jAiGA8yMDIzMDEyNTE5NTAxNFoYDzIwMjMwMTI2MTk1
# MDE0WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDne5X2AgEAMAcCAQACAiBkMAcC
# AQACAhFLMAoCBQDnfOd2AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkK
# AwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQEFBQADgYEAYSv5
# 9tSKtXDhfP4F2UK/1jXDBq3G1zMhvcegtiJfjdDhZIrjng434G3dsOVdFuFlMYvD
# vPvFGEn1u5F5g/VRVYH+n09SMtnJBC9ctYZ7o/wS/rpn+iTj/dGsaE/4Zgb5ariI
# jrD6CgfWTFMYCUz/WdK0TPAQFQoBXRc3EJl7x3MxggQNMIIECQIBATCBkzB8MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNy
# b3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAbJuQAN/bqmUkgABAAABsjAN
# BglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8G
# CSqGSIb3DQEJBDEiBCBqrvVaDSeJJwqyw8aPLTyMUySShUExbTEM2W2eGr0llTCB
# +gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIFN4zjzn4T63g8RWJ5SgUpfs9XIu
# j+fO76G0k8IbTj41MIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIw
# MTACEzMAAAGybkADf26plJIAAQAAAbIwIgQgK0Lv0IEUbEQIdXpkzRZMiVCMbxEY
# ogAuheEu3cPoF/UwDQYJKoZIhvcNAQELBQAEggIArlzf0UDqKdowZ3zbGhHe9883
# ZI5KL5xvUuOaR6YpBTVtA3CGYgmTMOy66uycT1cUDbegSJ0s/Kn7Us8eH3tRvSNC
# Epmb0qtNacN+bdhR9CTv+Z7lAuc8mZaudPkhqaG+RbrAN9GAtfw2JZCWYlgOiOnw
# RlkbXYi6d056IhYuL1tFvq0jyTiuebFLyUMjJKW40pquPHOvh/hWNOUfsl1auTPF
# zTmkYj2tpjZ9AG1lAFngGqTO2q5//CClekUR6ZBDtrYp7sWHtivBmq5ANW1ZiVQn
# ZJAjnLWbx9n6vzJoks8z8CKHh/XRVNkbFoJLKcN4GWrUb3G8xQ5mc1zjvLApBQS+
# 7iD5aACdXXCbNLZnpxDhT4QXgxAobJuT6CBqUaQjVT9lNS81TPNL7PJAVei1Nzx/
# WkR/Y7pTQg2oaz5yd8z0SDl+WdJPijHV09JYiKAa+293mzzuKnF0VzAZW/Y8NH6H
# Jvt+kjeTIvkcAVIlukLMoHpO/XkySTi8DX/eHrE0r8Uoe4fg2wCYzhFyIoSmZJUT
# xpg4TJQsA51o45yJ0t1P+cVuYqwfw63cm8GrzBr+EPbaq9uN4sGJDifl4O/uZLsX
# psdIgRZkUyXiiFAiIUq6JTq7Tr6AeqWutEZ6NOWdKp+TkFA3nUYo95fJa+A/scqY
# +PnATHqQNGcflXaba1w=
# SIG # End signature block
>>>>>>> 24cb13053eff742cede0d4016b0032695e8fa7f9
