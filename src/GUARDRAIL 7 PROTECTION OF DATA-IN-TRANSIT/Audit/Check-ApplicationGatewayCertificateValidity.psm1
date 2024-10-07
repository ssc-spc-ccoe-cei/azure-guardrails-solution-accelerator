function Check-ApplicationGatewayCertificateValidity {
    param (
        [Parameter(Mandatory=$true)]
        [string] $ControlName,
        [Parameter(Mandatory=$true)]
        [string] $ItemName,
        [Parameter(Mandatory=$true)]
        [string] $itsgcode,
        [Parameter(Mandatory=$true)]
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string] $ReportTime,
        [string] $CloudUsageProfiles = "3",
        [string] $ModuleProfiles,
        [switch] $EnableMultiCloudProfiles
    )

    $IsCompliant = $false
    $Comments = ""
    $ErrorList = New-Object System.Collections.ArrayList

    # Get all subscriptions
    $subscriptions = Get-AzSubscription

    $allCompliant = $true
    $appGatewaysFound = $false

    foreach ($subscription in $subscriptions) {
        # Set the context to the current subscription
        Set-AzContext -Subscription $subscription.Id | Out-Null

        # Get Application Gateways in the current subscription
        $appGateways = Get-AzApplicationGateway

        if ($appGateways.Count -gt 0) {
            $appGatewaysFound = $true
            foreach ($appGateway in $appGateways) {
                # 2. Check for SSL Certificates in listeners
                $listeners = Get-AzApplicationGatewayHttpListener -ApplicationGateway $appGateway
                $sslListeners = $listeners | Where-Object { $_.SslCertificate -ne $null }
                
                if ($sslListeners.Count -eq 0) {
                    $Comments += $msgTable.noSslListenersFound -f $appGateway.Name
                    $allCompliant = $false
                    continue
                }

                foreach ($listener in $sslListeners) {
                    # Extract the certificate name from the Id
                    $certName = $listener.SslCertificate.Id.Split('/')[-1]

                    # 3. Check certificate validity
                    $cert = Get-AzApplicationGatewaySslCertificate -ApplicationGateway $appGateway -Name $certName
                    if ($cert.PublicCertData) {
                        try {
                            $certBytes = [System.Convert]::FromBase64String($cert.PublicCertData)
                            $certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
                            $certCollection.Import($certBytes)
                            $x509cert = $certCollection[0]
                        
                            if ($.NotAfter -le (Get-Date)) {
                                $Comments += $msgTable.expiredCertificateFound -f $listener.Name, $appGateway.Name
                                $allCompliant = $false
                            }

                            # 4. Check if certificate is from an approved CA
                            $isApprovedCA = $false
                            
                            # Get the Key Vault name from the Application Gateway configuration
                            $keyVaultName = $appGateway.SslCertificates | Where-Object { $_.Name -eq $certName } | Select-Object -ExpandProperty KeyVaultSecretId -ErrorAction SilentlyContinue
                            if ($keyVaultName) {
                                $keyVaultName = ($keyVaultName -split '/')[8]
                                $isApprovedCA = $true
                            }

                            if (-not $isApprovedCA) {
                                $Comments += $msgTable.unapprovedCAFound -f $listener.Name, $appGateway.Name, $x509cert.Issuer
                                $allCompliant = $false
                            }
                        }
                        catch {
                            $Comments += $msgTable.unableToProcessCertData -f $listener.Name, $appGateway.Name, $_.Exception.Message
                            $allCompliant = $false
                        }
                    }
                    else {
                        $Comments += $msgTable.unableToRetrieveCertData -f $listener.Name, $appGateway.Name
                        $allCompliant = $false
                    }
                }

                # 3. Check HTTPS backend settings for well-known CA certificates
                $httpsBackendSettings = $appGateway.BackendHttpSettingsCollection | 
                    Where-Object { $_.Protocol -eq 'Https' }

                if ($httpsBackendSettings.Count -eq 0) {
                    $Comments += $msgTable.noHttpsBackendSettingsFound -f $appGateway.Name
                } else {
                    $allWellKnownCA = $true
                    foreach ($backendSetting in $httpsBackendSettings) {
                        if ($backendSetting.TrustedRootCertificates.Count -gt 0) {
                            $Comments += $msgTable.manualTrustedRootCertsFound -f $appGateway.Name, $backendSetting.Name
                            $allWellKnownCA = $false
                        }
                    }

                    if ($allWellKnownCA) {
                        $Comments += $msgTable.allBackendSettingsUseWellKnownCA -f $appGateway.Name
                    } else {
                        $allCompliant = $false
                    }
                }
            }
        }
    }

    if (-not $appGatewaysFound) {
        $Comments = $msgTable.noAppGatewayFound
        $IsCompliant = $false
    } else {
        $IsCompliant = $allCompliant
        if ($IsCompliant) {
            $Comments = $msgTable.allCertificatesValid
        }
    }

    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        Comments         = $Comments
        ItemName         = $ItemName
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }

    if ($EnableMultiCloudProfiles) {
        $result = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        if ($result -eq 0) {
            Write-Output "No matching profile found or error occurred"
            $PsObject.ComplianceStatus = "Not Applicable"
        } elseif ($result -gt 0) {
            Write-Output "Valid profile returned: $result"
            $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $result
        } else {
            Write-Error "Unexpected result: $result"
        }
    }

    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors            = $ErrorList
    }
    return $moduleOutput
}