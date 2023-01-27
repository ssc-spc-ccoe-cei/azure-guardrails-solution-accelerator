    # PART 2 - Checking for GUEST accounts  
    # Note that this URL only reads from the All-Users (not the deleted accounts) in the directory, 
    # This querly looks for accounts marked as GUEST
    # It does not list GUEST accounts from the list of deleted accounts.
    
    function Check-ExternalUsers  {
        Param ( 
            [string] $ControlName, 
            [string] $ItemName, 
            [string] $itsgcode,
            [hashtable] $msgTable,
            [Parameter(Mandatory=$true)]
            [string]
            $ReportTime
            )
    
    [psCustomObject] $guestUsersArray = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    [bool] $IsCompliant= $false
    
    $stopWatch = New-Object -TypeName System.Diagnostics.Stopwatch 
    $stopWatch.Start()

    # Only get the Guests accounts
    if ($debug) {Write-Output "Getting guest users in the tenant"}
    $guestUsers = Get-AzADUser -Filter "usertype eq 'guest'" 

    if ($null -eq $guestUsers) {
        # There are no Guest users in the tenant
        Write-Output "No Guest Users found in the tenant"
        $IsCompliant= $true
        $comment = $msgTable.noGuestAccounts
        $MitigationCommands = "N/A"
    }
    else {
        if ($debug) {Write-Output "Found $($guestUsers.Count) Guest Users in the tenant"}

        $subs=Get-AzSubscription -ErrorAction SilentlyContinue| Where-Object {$_.State -eq 'Enabled'}
        if ($debug) {Write-Output "Found $($subs.Count) subscriptions"}

        foreach ($sub in $subs) {
            $scope="/subscriptions/$($sub.Id)"
            if ($debug) {Write-Output "Looking in subscription $($sub.Name)"}

            # Get the role assignments for this subscription
            $subRoleAssignments = Get-AzRoleAssignment -Scope $scope

            if (!$null -eq $subRoleAssignments) {
                if ($debug) {Write-Output "Found $($subRoleAssignments.Count) Role Assignments in that subscription"}

                # Find each guest users having a role assignment
                $matchedUser = $guestUsers | Where-Object {$subRoleAssignments.ObjectId -contains $_.Id}  

                if (!$null -eq $matchedUser) {
                    if ($debug) {Write-Output "Found $($matchedUser.Count) Guest users with role assignment"}

                    foreach ($user in $matchedUser) {
                        # What should we do if the same user may has multiple role assignments ?

                        $Customuser = [PSCustomObject] @{
                            DisplayName = $user.DisplayName
                            Subscription = $sub.Name
                            Mail = $user.mail
                            Type = $user.userType
                            CreatedDate = $user.createdDateTime
                            Enabled = $user.accountEnabled
                            Comments = $msgTable.guestMustbeRemoved
                            ItemName= $ItemName 
                            ReportTime = $ReportTime
                            itsgcode = $itsgcode                            
                        }
                        $guestUsersArray.add($Customuser)
                    }
                }
                else {
                    Write-Output "Found no Guest users with role assignment"
                }
            }
        }
    }

    # If there are no Guest accounts or Guest accounts don't have any permissions on the Azure subscriptions, it's fine
    # we still create the Log Analytics table
    if ($guestUsersArray.Count -eq 0) {
        $IsCompliant= $true
        $MitigationCommands = "N/A"             
        # Don't overwrite the comment if there are no guest users
        if (!$null -eq $guestUsers) {
            $comment = $msgTable.guestAccountsNoPermission
        }
        
        $Customuser = [PSCustomObject] @{
            DisplayName = "N/A"
            Subscription = "N/A"
            Mail = "N/A"
            Type = "N/A"
            CreatedDate = "N/A"
            Enabled = "N/A"
            Comments = $comment
            ItemName= $ItemName 
            ReportTime = $ReportTime
            itsgcode = $itsgcode
        }
        $guestUsersArray.add($Customuser)
    }
    else {
        $IsCompliant= $false
        $comment = $msgTable.removeGuestAccountsComment
        $MitigationCommands = $msgTable.removeGuestAccounts
    }

    # Convert data to JSON format for input in Azure Log Analytics
    #$JSONGuestUsers = ConvertTo-Json -inputObject $guestUsersArray
    #Write-Output "Creating or updating Log Analytics table 'GR2ExternalUsers' and adding '$($guestUsers.Count)' guest user entries"

    # Add the list of non-compliant users to Log Analytics (in a different table)
    <#Send-OMSAPIIngestionFile  -customerId $WorkSpaceID -sharedkey $workspaceKey `
    -body $JSONGuestUsers -logType "GR2ExternalUsers" -TimeStampField Get-Date#>

    $GuestUserStatus = [PSCustomObject]@{
        ComplianceStatus= $IsCompliant
        ControlName = $ControlName
        Comments= $comment
        ItemName= $ItemName
        itsgcode = $itsgcode        
        ReportTime = $ReportTime
        MitigationCommands = $MitigationCommands
    }
    $AdditionalResults = [PSCustomObject]@{
        records = $guestUsersArray
        logType = "GR2ExternalUsers"
    }

    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $GuestUserStatus
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput 
    <#
    $logAnalyticsEntry = ConvertTo-Json -inputObject $GuestUserStatus
        
    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID -sharedkey $workspaceKey -body $logAnalyticsEntry `
                                -logType $LogType -TimeStampField Get-Date                 
    #>
    
    $stopWatch.Stop()
    if ($debug) {Write-Output "CheckExternalAccounts ran for: $($StopWatch.Elapsed.ToString()) "}
}
# SIG # Begin signature block
# MIInzQYJKoZIhvcNAQcCoIInvjCCJ7oCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD7Eh5P9EKkNngv
# oWV4DhK4C0F7/8gpiGDO0KtwboS3haCCDYEwggX/MIID56ADAgECAhMzAAACzI61
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
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgoyv6r3Xk
# LlyD4jul/5MNlRCjAItGmasscU4YFAyErJgwQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQCNyHtwjmFX5kAIYIhEQU7sWbsLbn/w+RDuJ2lNmI3f
# L9Qrl95GOTfM7zA3dCV/f6VC2XPJKOpevsal3SdNKkkVW/+C4kxz2Zk5DUhGNWYY
# nRHAGVvqV5VNEfehFTME5M7MWa7q2zdPWIwlQllIqVFdC10Q+NOB8FyYkeG5KweU
# lHpy4bODYa4nLGhfv2aFcUgc9njFqLm/i9/Z8LDZNyNO5rMrdYPggY6RYdg9X+2+
# uVkCRhJtjbNjzv2XPTsSBvZAVJbjF9xGJp/IRBLTFrFWmqEAwPphstoj1ErKhEVt
# uAiofjk/oJRD7B8+8GOnGJoSXM38A4L0dEdYeimMwve8oYIXLDCCFygGCisGAQQB
# gjcDAwExghcYMIIXFAYJKoZIhvcNAQcCoIIXBTCCFwECAQMxDzANBglghkgBZQME
# AgEFADCCAVkGCyqGSIb3DQEJEAEEoIIBSASCAUQwggFAAgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIPlJrxEp5wbneERp1WmR1Fmko6OZoFZ1TudwtN4q
# RcreAgZjx9zmbAUYEzIwMjMwMTI1MjIyNTQ0LjA2MVowBIACAfSggdikgdUwgdIx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1p
# Y3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhh
# bGVzIFRTUyBFU046RkM0MS00QkQ0LUQyMjAxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WgghF7MIIHJzCCBQ+gAwIBAgITMwAAAbn2AA1lVE+8
# AwABAAABuTANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDAeFw0yMjA5MjAyMDIyMTdaFw0yMzEyMTQyMDIyMTdaMIHSMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQg
# SXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1Mg
# RVNOOkZDNDEtNEJENC1EMjIwMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA40k+yWH1
# FsfJAQJtQgg3EwXm5CTI3TtUhKEhNe5sulacA2AEIu8JwmXuj/Ycc5GexFyZIg0n
# +pyUCYsis6OdietuhwCeLGIwRcL5rWxnzirFha0RVjtVjDQsJzNj7zpT/yyGDGqx
# p7MqlauI85ylXVKHxKw7F/fTI7uO+V38gEDdPqUczalP8dGNaT+v27LHRDhq3HSa
# QtVhL3Lnn+hOUosTTSHv3ZL6Zpp0B3LdWBPB6LCgQ5cPvznC/eH5/Af/BNC0L2WE
# DGEw7in44/3zzxbGRuXoGpFZe53nhFPOqnZWv7J6fVDUDq6bIwHterSychgbkHUB
# xzhSAmU9D9mIySqDFA0UJZC/PQb2guBI8PwrLQCRfbY9wM5ug+41PhFx5Y9fRRVl
# Sxf0hSCztAXjUeJBLAR444cbKt9B2ZKyUBOtuYf/XwzlCuxMzkkg2Ny30bjbGo3x
# UX1nxY6IYyM1u+WlwSabKxiXlDKGsQOgWdBNTtsWsPclfR8h+7WxstZ4GpfBunhn
# zIAJO2mErZVvM6+Li9zREKZE3O9hBDY+Nns1pNcTga7e+CAAn6u3NRMB8mi285Kp
# wyA3AtlrVj4RP+VvRXKOtjAW4e2DRBbJCM/nfnQtOm/TzqnJVSHgDfD86zmFMYVm
# AV7lsLIyeljT0zTI90dpD/nqhhSxIhzIrJUCAwEAAaOCAUkwggFFMB0GA1UdDgQW
# BBS3sDhx21hDmgmMTVmqtKienjVEUjAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQM
# MAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEA
# zdxns0VQdEywsrOOXusk8iS/ugn6z2SS63SFmJ/1ZK3rRLNgZQunXOZ0+pz7Dx4d
# OSGpfQYoKnZNOpLMFcGHAc6bz6nqFTE2UN7AYxlSiz3nZpNduUBPc4oGd9UEtDJR
# q+tKO4kZkBbfRw1jeuNUNSUYP5XKBAfJJoNq+IlBsrr/p9C9RQWioiTeV0Z+OcC2
# d5uxWWqHpZZqZVzkBl2lZHWNLM3+jEpipzUEbhLHGU+1x+sB0HP9xThvFVeoAB/T
# Y1mxy8k2lGc4At/mRWjYe6klcKyT1PM/k81baxNLdObCEhCY/GvQTRSo6iNSsElQ
# 6FshMDFydJr8gyW4vUddG0tBkj7GzZ5G2485SwpRbvX/Vh6qxgIscu+7zZx4NVBC
# 8/sYcQSSnaQSOKh9uNgSsGjaIIRrHF5fhn0e8CADgyxCRufp7gQVB/Xew/4qfdeA
# wi8luosl4VxCNr5JR45e7lx+TF7QbNM2iN3IjDNoeWE5+VVFk2vF57cH7JnB3ckc
# Mi+/vW5Ij9IjPO31xTYbIdBWrEFKtG0pbpbxXDvOlW+hWwi/eWPGD7s2IZKVdfWz
# vNsE0MxSP06fM6Ucr/eas5TxgS5F/pHBqRblQJ4ZqbLkyIq7Zi7IqIYEK/g4aE+y
# 017sAuQQ6HwFfXa3ie25i76DD0vrII9jSNZhpC3MA/0wggdxMIIFWaADAgECAhMz
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
# cyBUU1MgRVNOOkZDNDEtNEJENC1EMjIwMSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQDHYh4YeGTnwxCTPNJaScZw
# uN+BOqCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
# SIb3DQEBBQUAAgUA53uVtTAiGA8yMDIzMDEyNTE5NDkwOVoYDzIwMjMwMTI2MTk0
# OTA5WjB3MD0GCisGAQQBhFkKBAExLzAtMAoCBQDne5W1AgEAMAoCAQACAgvXAgH/
# MAcCAQACAhFUMAoCBQDnfOc1AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQB
# hFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQEFBQADgYEA
# hfktXfgaAIjiQIonVtHnbhRJKkKxKiBkePOfo9sEcNWytzeuMxAsD/0rCk+yBhgr
# 0SpbT3QwZ4NNnmuBlO7MRthzeK+C/YKcAVFuvO6VUi/UylE65xbSKMA7bZmV1FZh
# 3drEfrx5x3q3wLpjxfwnZuR7CFhTzznrO9Vio7NIBRMxggQNMIIECQIBATCBkzB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAbn2AA1lVE+8AwABAAAB
# uTANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEE
# MC8GCSqGSIb3DQEJBDEiBCBboaLJ1jQgMfN/LbZVpAa10pDHodmMgAEIrTya8ZWm
# eTCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIGTrRs7xbzm5MB8lUQ7e9fZo
# tpAVyBwal3Cw6iL5+g/0MIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENB
# IDIwMTACEzMAAAG59gANZVRPvAMAAQAAAbkwIgQgWa/g1x/+rL1L0qEzZXY3h3Sv
# m6PVomDfVKxyAYs+cMcwDQYJKoZIhvcNAQELBQAEggIArx+bHz0dCIDqoi3SvX1k
# hbH09V+MYTMF+KVzTS5sMDmN22DjfFXaMqWniADTWdfCj1g2qMiWTAFu1QCR38fD
# 1xJKYt+j/cfH7ASxNx8FZbDl7C1uxU6KwLZ3Tc7eQrw+MdXoQguoFG4lLlttEqMs
# EIpPzOyfy6qPbMtPaYIMOp2ET4PiR+SAd0a8wy0FGAKOt1Ee5fhTEu9LQd0DgXuN
# EdwG1zHHSsE+xpyR53fBzCb2tbZz0gvj/dgFzmnVzgreswOHM1XTp27x0SiJZ7eZ
# biRGkWGsrvUtcG4gzER8BqEA18aaffTgxkkPTMPB4m9TZEs+59gnhuKuCstRUzmI
# ivOUP0TJI8AIzrbcTxksXzzWKpWWmPC9ojnsqAkZg/sNAsgOTGHz11HMtrVvT8yE
# F2s3UmKIITeCfhNceAcp56wWiRhLYjM5iPc0WMQhaxsZRyAcskq1MAqWY1NW4ajB
# WDdLL+xoK0qrveqNaEaqYNM1XqYtbiKwfwqLuvCJn9Ewqfrf0UyLpQ7A3ohm9ZIt
# KeiXTUUQLyBaUSLVD6eA/igen4NStKzW+80LSzQACWIE64bUfhrjw/gynx7gzmvh
# 4H4oE/CmP/vJE/M7ldQs+e6R+oxj/8ewJITLnvxlqmePPb5hUzNeHlGKMaRYCyzb
# okMOcukEVD2EeP0RS2ii42E=
# SIG # End signature block
