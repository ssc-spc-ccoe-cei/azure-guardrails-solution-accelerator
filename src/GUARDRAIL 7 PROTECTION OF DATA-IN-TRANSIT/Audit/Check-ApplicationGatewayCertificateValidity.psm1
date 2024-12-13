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
        [Parameter(Mandatory = $true)]
        [string] $StorageAccountName,
        [Parameter(Mandatory = $true)]
        [string] $ContainerName, 
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroupName,
        [Parameter(Mandatory = $true)]
        [string] $SubscriptionID, 
        [Parameter(Mandatory = $true)]
        [string[]] $DocumentName, 
        [string] $CloudUsageProfiles = "3",
        [string] $ModuleProfiles,
        [switch] $EnableMultiCloudProfiles
    )

    $IsCompliant = $false
    $Comments = ""
    $ErrorList = [System.Collections.ArrayList]@()
    $ApprovedCAList = @()

    # Add possible file extensions
    $DocumentName_new = add-documentFileExtensions -DocumentName $DocumentName -ItemName $ItemName

    try {
        Select-AzSubscription -Subscription $SubscriptionID | out-null
    }
    catch {
        $ErrorList.Add("Failed to run 'Select-Azsubscription' with error: $_")
        throw "Error: Failed to run 'Select-Azsubscription' with error: $_"
    }
    try {
        $StorageAccount = Get-Azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction Stop
    }
    catch {
        $ErrorList.Add("Could not find storage account '$storageAccountName' in resoruce group '$resourceGroupName' of `
        subscription '$subscriptionId'; verify that the storage account exists and that you have permissions to it. Error: $_")
        Write-Error "Could not find storage account '$storageAccountName' in resoruce group '$resourceGroupName' of `
            subscription '$subscriptionId'; verify that the storage account exists and that you have permissions to it. Error: $_"
    }

    $baseFileNameFound = $false
    $blobFound = $false

    # Get a list of filenames uploaded in the blob storage
    $blobs = Get-AzStorageBlob -Container $ContainerName -Context $StorageAccount.Context
    
    $fileNamesList = @()
    $blobs | ForEach-Object {
        $fileNamesList += $_.Name
    }
    $matchingFiles = $fileNamesList | Where-Object { $_ -in $DocumentName_new }
    if ( $matchingFiles.count -lt 1 ){
        # check if any fileName matches without the extension
        $baseFileNames = $fileNamesList | ForEach-Object { ($_.Split('.')[0]) }
        
        $BaseFileNamesMatch = $baseFileNames | Where-Object { $_ -in $DocumentName  }
        if ($BaseFileNamesMatch.Count -gt 0){
            $baseFileNameFound = $true
        }
    }
    else {
        # also covers the use case if more than 1 appropriate files are uploaded
        
        # check for procedure doc in blob storage account
        $blobs = Get-AzStorageBlob -Container $ContainerName -Context $StorageAccount.Context -Blob $DocumentName_new

        If ($blobs) {
            $blobFound = $true
            # Read the content of the blob and save CA names into array
            $blobContent = Get-AzStorageBlobContent -Container $ContainerName -Blob $docName -Context $StorageAccount.Context -Force
            $ApprovedCAList = Get-Content $blobContent.Name | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim() }
            Remove-Item $blobContent.Name -Force
            break
        }
    }

    # Use case: uploaded fileName is correct but has wrong extension
    if ($baseFileNameFound){
        # a blob with the name $documentName was located in the specified storage account; however, the ext is not correct
        $Comments += $msgTable.procedureFileNotFoundWithCorrectExtension -f $DocumentName[0], $ContainerName, $StorageAccountName
        $IsCompliant = $false

        $PsObject = [PSCustomObject]@{
            ComplianceStatus = $IsCompliant
            ControlName      = $ControlName
            Comments         = $Comments
            ItemName         = $ItemName
            ReportTime       = $ReportTime
            itsgcode         = $itsgcode
        }

        if ($EnableMultiCloudProfiles) {
            Set-ProfileEvaluation -PsObject $PsObject -ErrorList $ErrorList -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        }
    
        $moduleOutput = [PSCustomObject]@{ 
            ComplianceResults = $PsObject
            Errors            = $ErrorList
        }
        return $moduleOutput

    }
    elseif ($blobFound){
        $Comments += $msgTable.approvedCAFileFound -f $DocumentName
    }
    else {
        $Comments += $msgTable.approvedCAFileNotFound -f $DocumentName[0], $ContainerName, $StorageAccountName
        $IsCompliant = $false
        
        $PsObject = [PSCustomObject]@{
            ComplianceStatus = $IsCompliant
            ControlName      = $ControlName
            Comments         = $Comments
            ItemName         = $ItemName
            ReportTime       = $ReportTime
            itsgcode         = $itsgcode
        }

        if ($EnableMultiCloudProfiles) {
            Set-ProfileEvaluation -PsObject $PsObject -ErrorList $ErrorList -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        }
    
        $moduleOutput = [PSCustomObject]@{ 
            ComplianceResults = $PsObject
            Errors            = $ErrorList
        }
        return $moduleOutput
    }

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
                        
                            if ($x509cert.NotAfter -le (Get-Date)) {
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
                            else {
                                # Check if the certificate issuer is in or matches part of the ApprovedCAList
                                # or if ApprovedCA is part of the Issuer (bidirectional check)
                                $isApprovedCA = $false
                                foreach ($approvedCA in $ApprovedCAList) {
                                    if ($x509cert.Issuer -like "*$approvedCA*" -or $approvedCA -like "*$($x509cert.Issuer)*") {
                                        $isApprovedCA = $true
                                        break
                                    }
                                }
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
        $IsCompliant = $true
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
        Set-ProfileEvaluation -PsObject $PsObject -ErrorList $ErrorList -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
    }

    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors            = $ErrorList
    }
    return $moduleOutput
}

function Set-ProfileEvaluation {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$PsObject,
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [System.Collections.ArrayList]$ErrorList,
        [Parameter(Mandatory=$true)]
        [string]$CloudUsageProfiles,
        [Parameter(Mandatory=$true)]
        [string]$ModuleProfiles
    )

    $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
    if (!$evalResult.ShouldEvaluate) {
        if ($evalResult.Profile -gt 0) {
            $PsObject.ComplianceStatus = "Not Applicable"
            $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile -Force
            $PsObject.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
        } else {
            # Add error to ErrorList instead of throwing
            [void]$ErrorList.Add("Error occurred while evaluating profile configuration")
        }
    } else {
        $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile -Force
    }
}
