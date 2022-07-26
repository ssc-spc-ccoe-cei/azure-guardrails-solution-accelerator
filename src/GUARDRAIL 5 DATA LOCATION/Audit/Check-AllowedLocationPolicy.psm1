function Verify-AllowedLocationPolicy {
    param (
        [switch] $DebugData,
        [string] $ControlName,
        [string] $ItemName,
        [string] $PolicyID, 
        [string] $WorkSpaceID,
        [string] $workspaceKey,
        [string] $LogType,
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
                        $NonCompliantList.add($c)
                    }
                    elseif (-not ([string]::IsNullOrEmpty(($AssignedPolicyList.Properties.NotScopesScope)))   ) {
                        $c | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
                        $c | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName
                        $c | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName
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
                        $NonCompliantList.add($c)
                    }
                    elseif (-not ([string]::IsNullOrEmpty(($AssignedPolicyList.Properties.NotScopesScope)))) {
                        $c | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
                        $c | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName
                        $c | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName
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
        $NonCompliantList.add($RootMG)
    }
    elseif (-not ([string]::IsNullOrEmpty(($AssignedPolicyList.Properties.NotScopesScope)))) {
        $RootMG | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
        $RootMG | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName
        $RootMG | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName
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
# MIInlQYJKoZIhvcNAQcCoIInhjCCJ4ICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD8nnpVNrwc1Iu/
# 2RlAKJYsRbsAGweTuqPfxJNc5oAyEqCCDXYwggX0MIID3KADAgECAhMzAAACURR2
# zMWFg24LAAAAAAJRMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjEwOTAyMTgzMjU5WhcNMjIwOTAxMTgzMjU5WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDBIpXR3b1IYAMunV9ZYBVYsaA7S64mqacKy/OJUf0Lr/LW/tWlJDzJH9nFAhs0
# zzSdQQcLhShOSTUxtlwZD9dnfIcx4pZgu0VHkqQw2dVc8Ob21GBo5sVrXgEAQxZo
# rlEuAl20KpSIFLUBwoZFGFSQNSMcqPudXOw+Mhvn6rXYv/pjXIjgBntn6p1f+0+C
# 2NXuFrIwjJIJd0erGefwMg//VqUTcRaj6SiCXSY6kjO1J9P8oaRQBHIOFEfLlXQ3
# a1ATlM7evCUvg3iBprpL+j1JMAUVv+87NRApprPyV75U/FKLlO2ioDbb69e3S725
# XQLW+/nJM4ihVQ0BHadh74/lAgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUMLgM7NX5EnpPfK5uU6FPvn2g/Ekw
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzQ2NzU5NjAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAIVJlff+Fp0ylEJhmvap
# NVv1bYLSWf58OqRRIDnXbHQ+FobsOwL83/ncPC3xl8ySR5uK/af4ZDy7DcDw0yEd
# mKbRLzHIfcztZVSrlsg0GKwZuaB2MEI1VizNCoZlN+HlFZa4DNm3J0LhTWrZjVR0
# M6V57cFW0GsV4NlqmtelT9JFEae7PomwgAV9xOScz8HzvbZeERcoSRp9eRsQwOw7
# 8XeCLeglqjUnz9gFM7RliCYP58Fgphtkht9LNEcErLOVW17m6/Dj75zg/IS+//6G
# FEK2oXnw5EIIWZraFHqSaee+NMgOw/R6bwB8qLv5ClOJEpGKA3XPJvS9YgOpF920
# Vu4Afqa5Rv5UJKrsxA7HOiuH4TwpkP3XQ801YLMp4LavXnvqNkX5lhFcITvb01GQ
# lcC5h+XfCv0L4hUum/QrFLavQXJ/vtirCnte5Bediqmjx3lswaTRbr/j+KX833A1
# l9NIJmdGFcVLXp1en3IWG/fjLIuP7BqPPaN7A1tzhWxL+xx9yw5vQiT1Yn14YGmw
# OzBYYLX0H9dKRLWMxMXGvo0PWEuXzYyrdDQExPf66Fq/EiRpZv2EYl2gbl9fxc3s
# qoIkyNlL1BCrvmzunkwt4cwvqWremUtqTJ2B53MbBHlf4RfvKz9NVuh5KHdr82AS
# MMjU4C8KNTqzgisqQdCy8unTMIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
# hkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
# IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQg
# Q29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03
# a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akr
# rnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0Rrrg
# OGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy
# 4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9
# sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAh
# dCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8k
# A/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTB
# w3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmn
# Eyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90
# lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0w
# ggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2o
# ynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBa
# BgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsG
# AQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNV
# HSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsG
# AQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABl
# AG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKb
# C5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11l
# hJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6
# I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0
# wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560
# STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQam
# ASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGa
# J+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ah
# XJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA
# 9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33Vt
# Y5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr
# /Xmfwb1tbWrJUnMTDXpQzTGCGXUwghlxAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAAJRFHbMxYWDbgsAAAAAAlEwDQYJYIZIAWUDBAIB
# BQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIB14Ow/eToMWD6jGI4TNWUbz
# QOriM867eBNfh9jo+lVsMEQGCisGAQQBgjcCAQwxNjA0oBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEcgBpodHRwczovL3d3dy5taWNyb3NvZnQuY29tIDANBgkqhkiG9w0B
# AQEFAASCAQCtZK0T6SGs4mnLjBxs4/wO5h+uabVZLxygXtyAINN8YiIGurugQy/Y
# vRv2djxIiPnwV1ugwdEqLIvcRe0EMThu2QeEClR1PAGxJDh7Ijv6+fMpefQqIUwB
# 10rFlvNmZe/oEdXe2jll94D1i6qlFgXryZbFbCmizYNodHfY9GkkmH+HdJrCkVKd
# eq+WtCoOU9AFLaIqN44buIRZXISDO6xIJMh4myPJpBCcVNxtFqus7x5UOLHbkAZK
# Ab858uSIHff1knyely5tnM59d8nd3PATwpc6mlAvQV8GTDlIf5CW299x+z87TqiX
# 1JQpHaJwUewAyn5Jhm9mKyW+sh6//jFqoYIW/TCCFvkGCisGAQQBgjcDAwExghbp
# MIIW5QYJKoZIhvcNAQcCoIIW1jCCFtICAQMxDzANBglghkgBZQMEAgEFADCCAVEG
# CyqGSIb3DQEJEAEEoIIBQASCATwwggE4AgEBBgorBgEEAYRZCgMBMDEwDQYJYIZI
# AWUDBAIBBQAEIIHpoT8lX/ApjN9nZ3DI8EWp3xbgExkbFou5odSasdtFAgZi1VvS
# fgkYEzIwMjIwNzI2MTgzNjU3LjMzMlowBIACAfSggdCkgc0wgcoxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBB
# bWVyaWNhIE9wZXJhdGlvbnMxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOjNFN0Et
# RTM1OS1BMjVEMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# oIIRVDCCBwwwggT0oAMCAQICEzMAAAGg6buMuw6i0XoAAQAAAaAwDQYJKoZIhvcN
# AQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMjExMjAyMTkw
# NTIzWhcNMjMwMjI4MTkwNTIzWjCByjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9u
# czEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046M0U3QS1FMzU5LUEyNUQxJTAjBgNV
# BAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQC/2uIOaHGdAOj2YvhhI6C8iFAq7wrl/5WpPjj0fEHC
# i6Ivx/I02Jss/HVhkfGTMGttR5jRhhrJXydWDnOmzRU3B4G525T7pwkFNFBXumM/
# 98l5k0U2XiaZ+bulXHe54x6uj/6v5VGFv+0Hh1dyjGUTPaREwS7x98Te5tFHEimP
# a+AsG2mM+n9NwfQRjd1LiECbcCZFkgwbliQ/akiMr1tZmjkDbxtu2aQcXjEfDna8
# JH+wZmfdu0X7k6dJ5WGRFwzZiLOJW4QhAEpeh2c1mmbtAfBnhSPN+E5yULfpfTT2
# wX8RbH6XfAg6sZx8896xq0+gUD9mHy8ZtpdEeE1ZA0HgByDW2rJCbTAJAht71B7R
# z2pPQmg5R3+vSCri8BecSB+Z8mwYL3uOS3R6beUBJ7iE4rPS9WC1w1fZR7K44ZSm
# e2dI+O9/nhgb3MLYgm6zx3HhtLoGhGVPL+WoDkMnt93IGoO6kNBCM2X+Cs22ql2t
# PjkIRyxwxF6RsXh/QHnhKJgBzfO+e84I3TYbI0i29zATL6yHOv5sEs1zaNMih27I
# wfWg4Q7+40L7e68uC6yD8EUEpaD2s2T59NhSauTzCEnAp5YrSscc9MQVIi7g+5GA
# dC8pCv+0iRa7QIvalU+9lWgkyABU/niFHWPjyGoB4x3Kzo3tXB6aC3yZ/dTRXpJn
# aQIDAQABo4IBNjCCATIwHQYDVR0OBBYEFHK5LlDYKU6RuJFsFC9EzwthjNDoMB8G
# A1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCG
# Tmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUy
# MFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4w
# XAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2Vy
# dHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwG
# A1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQELBQAD
# ggIBADF9xgKr+N+slAmlbcEqQBlpL5PfBMqcLkS6ySeGJjG+LKX3Wov5pygrhKft
# XZ90NYWUftIZpzdYs4ehR5RlaE3eYubWlcNlwsKkcrGSDJKawbbDGfvO4h/1L13s
# g66hPib67mG96CAqRVF0c5MA1wiKjjl/5gfrbdNLHgtREQ8zCpbK4+66l1Fd0up9
# mxcOEEphhJr8U3whwFwoK+QJ/kxWogGtfDiaq6RyoFWhP8uKSLVDV+MTETHZb3p2
# OwnBWE1W6071XDKdxRkN/pAEZ15E1LJNv9iYo1l1P/RdF+IzpMLGDAf/PlVvTUw3
# VrH9uaqbYr+rRxti+bM3ab1wv9v3xRLc+wPoniSxW2p69DN4Wo96IDFZIkLR+HcW
# CiqHVwFXngkCUfdMe3xmvOIXYRkTK0P6wPLfC+Os7oeVReMj2TA1QMMkgZ+rhPO0
# 7iW7N57zABvMiHJQdHRMeK3FBgR4faEvTjUAdKRQkKFV82uE7w0UMnseJfX7ELDY
# 9T4aWx2qwEqam9l7GHX4A2Zm0nn1oaa/YxczJ7gIVERSGSOWLwEMxcFqBGPm9QSQ
# 7ogMBn5WHwkdTTkmanBb/Z2cDpxBxd1vOjyIm4BOFlLjB4pivClO2ZksWKH7qBYl
# oYa07U1O3C8jtbzGUdHyLCaVGBV8DfD5h8eOnyjraBG7PNNZMIIHcTCCBVmgAwIB
# AgITMwAAABXF52ueAptJmQAAAAAAFTANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0
# IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMjEwOTMwMTgyMjI1
# WhcNMzAwOTMwMTgzMjI1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCC
# AiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAOThpkzntHIhC3miy9ckeb0O
# 1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDivbk+F2Az/1xPx2b3lVNxWuJ+Slr+uDZn
# hUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU88V29YZQ3MFEyHFcUTE3oAo4bo3t
# 1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqYO7oaezOtgFt+jBAcnVL+tuhiJdxq
# D89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzpcGkNyjYtcI4xyDUoveO0hyTD4MmP
# frVUj9z6BVWYbWg7mka97aSueik3rMvrg0XnRm7KMtXAhjBcTyziYrLNueKNiOSW
# rAFKu75xqRdbZ2De+JKRHh09/SDPc31BmkZ1zcRfNN0Sidb9pSB9fvzZnkXftnIv
# 231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZNN3SUHDSCD/AQ8rdHGO2n6Jl8P0zb
# r17C89XYcz1DTsEzOUyOArxCaC4Q6oRRRuLRvWoYWmEBc8pnol7XKHYC4jMYcten
# IPDC+hIK12NvDMk2ZItboKaDIV1fMHSRlJTYuVD5C4lh8zYGNRiER9vcG9H9stQc
# xWv2XFJRXRLbJbqvUAV6bMURHXLvjflSxIUXk8A8FdsaN8cIFRg/eKtFtvUeh17a
# j54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB2TASBgkrBgEEAYI3FQEEBQIDAQAB
# MCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSavoKRPEY1Kc8Q/y8E7jAdBgNVHQ4EFgQU
# n6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0gBFUwUzBRBgwrBgEEAYI3TIN9AQEw
# QTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9E
# b2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUFBwMIMBkGCSsGAQQB
# gjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/
# MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1UdHwRPME0wS6BJ
# oEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01p
# Y1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYB
# BQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9v
# Q2VyQXV0XzIwMTAtMDYtMjMuY3J0MA0GCSqGSIb3DQEBCwUAA4ICAQCdVX38Kq3h
# LB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOXPTEztTnXwnE2P9pkbHzQdTltuw8x
# 5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjYNi6cqYJWAAOwBb6J6Gngugnue99qb74p
# y27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/zjj3G82jfZfakVqr3lbYoVSfQJL1A
# oL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz/AyeixmJ5/ALaoHCgRlCGVJ1ijbC
# HcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyRgNI95ko+ZjtPu4b6MhrZlvSP9pEB
# 9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdUbZ1jdEgssU5HLcEUBHG/ZPkkvnNt
# yo4JvbMBV0lUZNlz138eW0QBjloZkWsNn6Qo3GcZKCS6OEuabvshVGtqRRFHqfG3
# rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4Ku+xBZj1p/cvBQUl+fpO+y/g75LcV
# v7TOPqUxUYS8vwLBgqJ7Fx0ViY1w/ue10CgaiQuPNtq6TPmb/wrpNPgkNWcr4A24
# 5oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9vMvpe784cETRkPHIqzqKOghif9lw
# Y1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGCAsswggI0AgEBMIH4oYHQpIHNMIHK
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMSYwJAYDVQQLEx1UaGFsZXMgVFNT
# IEVTTjozRTdBLUUzNTktQTI1RDElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAEwa4jWjacbOYU++95ydJ7hSCi5ig
# gYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYw
# JAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0B
# AQUFAAIFAOaKZeswIhgPMjAyMjA3MjYyMTA4NTlaGA8yMDIyMDcyNzIxMDg1OVow
# dDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA5opl6wIBADAHAgEAAgIBsjAHAgEAAgI+
# BTAKAgUA5ou3awIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMCoAow
# CAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBBQUAA4GBAFtLPWBxpxCw
# nfZrhc4YZGMzI+tGVTHFqAWsdzbTJbu4iMo10aUwFMW5+30ofnCnhURG+erEfNok
# pS6hT18ILBgBaCQ1Crnd5+ZuiQmfRdJytUhiXisxCfItWPrLSVfwIbbaNHpD1h2K
# Ix1ofV9l6yMG4O6dFn51LTq7BVYZslm8MYIEDTCCBAkCAQEwgZMwfDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGg6buMuw6i0XoAAQAAAaAwDQYJYIZI
# AWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG
# 9w0BCQQxIgQgF0HdjKuXgnWus1F4KGS9/jwZQ7h5HGURCdVQ7ocUpwIwgfoGCyqG
# SIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAvR4o8aGUEIhIt3REvsx0+svnM6Wiaga5S
# PaK4g6+00zCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMz
# AAABoOm7jLsOotF6AAEAAAGgMCIEIIkbQg7pgefYYvAhLW9B1sSM1OkhBv0+LsVH
# kcQAxWwMMA0GCSqGSIb3DQEBCwUABIICAJHyMR/BU89PtKHC38e7UsGF51J2oY7f
# SNYsAibyeJnD/dpsq5wok4hhUNFSmKGFZZprCDrYcUrzfSJwe9WIOtADiVEn/H+Y
# XivXBBUaV+QbLCoN6NnezgxxHX0kRzocUB74FzLRwJ31+VTW8QPw/WorY3qzC5XH
# f1XYb9LjR6GAq+6QoYSM6VrTc0vwCXja3BqtAhuTcdrQiNr8yPQyHChE1ch69Vr1
# PNO+0EpMUVoRMzQm6gLyAZxtxsytCk4HP/75QVLzPK0DiJnr866S736joBZFBXaG
# irI2dhPABRM/ZQ5PScOvGER+iTfBDd95YfPPPfHIV//DzFqzr5aoJGkHJk+o7OdT
# Rq1ROr58/5KFcUYfxBA/fow4wtu+hxZJrZT+OCxSYOzzrmP/t7CrWvr7h+Ax6WW8
# 55G/Z7J6jpidyPgGqjNvHzIzrW07fcnXCX7WR2GH+6c0Quej4UDIQh9l8IbpgaYG
# /o6bZDlhcy1tM1U8cjhFAGxW5PbykrNyHvPZSVxPnAXyPWmx9K8NYekDjr4TT8bj
# SLBqORS1xq45WD5N/JhExnRW6GVqCSKpX2rmBIM8RAnBz8IDBax/HfsIlMaN0MKE
# VDN/YzFPWjQA3yAA4iHNRilGFUFs7ZEKEeCFMFZ63Tl1YVZCA12Nm7Y63vrt3rWl
# anGSkAgd8UxC
# SIG # End signature block
