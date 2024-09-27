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

    # 1. Check if Application Gateway is used
    $appGateways = Get-AzApplicationGateway
    if ($appGateways.Count -eq 0) {
        $Comments = $msgTable.noAppGatewayFound
        $IsCompliant = $false
    }
    else {
        $allCompliant = $true
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
                # 3. Check certificate validity
                $cert = Get-AzApplicationGatewaySslCertificate -ApplicationGateway $appGateway -Name $listener.SslCertificate.Id
                if ($cert.PublicCertData) {
                    $x509cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
                    $x509cert.Import([System.Convert]::FromBase64String($cert.PublicCertData))
                    
                    if ($x509cert.NotAfter -le (Get-Date)) {
                        $Comments += $msgTable.expiredCertificateFound -f $listener.Name, $appGateway.Name
                        $allCompliant = $false
                    }

                    # 4. Check if certificate is from an approved CA
                    $isApprovedCA = $false
                    
                    # Get the Key Vault and HSM names from the Application Gateway configuration
                    $keyVaultName = $appGateway.SslCertificates | Where-Object { $_.Id -eq $listener.SslCertificate.Id } | Select-Object -ExpandProperty KeyVaultSecretId -ErrorAction SilentlyContinue
                    if ($keyVaultName) {
                        $keyVaultName = ($keyVaultName -split '/')[8]
                        $hsmName = Get-AzKeyVault -VaultName $keyVaultName | Select-Object -ExpandProperty HsmName -ErrorAction SilentlyContinue
                    }

                    if ($keyVaultName -and $hsmName) {
                        # Check if "well-known" toggle is on
                        $wellKnownToggle = Get-AzKeyVaultManagedHsm -Name $hsmName -ResourceGroupName (Get-AzKeyVault -VaultName $keyVaultName).ResourceGroupName | 
                            Select-Object -ExpandProperty Properties | 
                            Select-Object -ExpandProperty EnableSoftDelete
                        
                        # Check if Certificate Allow-List exists
                        $allowList = Get-AzKeyVaultCertificate -VaultName $keyVaultName -Name "CertificateAllowList" -ErrorAction SilentlyContinue
                        
                        # Check if Certificate management in key vault is enabled
                        $certManagementEnabled = Get-AzKeyVault -VaultName $keyVaultName | Select-Object -ExpandProperty EnabledForCertificateManagement

                        if ($wellKnownToggle -and $allowList -and $certManagementEnabled) {
                            $isApprovedCA = $true
                        }
                    }

                    if (-not $isApprovedCA) {
                        $Comments += $msgTable.unapprovedCAFound -f $listener.Name, $appGateway.Name, $x509cert.Issuer
                        $allCompliant = $false
                    }
                }
                else {
                    $Comments += $msgTable.unableToRetrieveCertData -f $listener.Name, $appGateway.Name
                    $allCompliant = $false
                }
            }
        }
        
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