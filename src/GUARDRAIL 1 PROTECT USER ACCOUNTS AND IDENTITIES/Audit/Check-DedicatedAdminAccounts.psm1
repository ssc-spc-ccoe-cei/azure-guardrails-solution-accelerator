function Check-DedicatedAdminAccounts {
    param (
        [Parameter(Mandatory = $true)]
        [string] $StorageAccountName,
        [Parameter(Mandatory = $true)]
        [string] $ContainerName, 
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroupName,
        [Parameter(Mandatory = $true)]
        [string] $SubscriptionID, 
        [Parameter(Mandatory = $true)]
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
        [Parameter(Mandatory=$true)]
        [string] $FirstBreakGlassUPN,
        [Parameter(Mandatory=$true)] 
        [string] $SecondBreakGlassUPN,
        [Parameter(Mandatory = $true)]
        [string[]] $DocumentName1, 
        [Parameter(Mandatory = $true)]
        [string[]] $DocumentName2, 
        [string] 
        $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] 
        $EnableMultiCloudProfiles # New feature flag, default to false
    )

    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    [bool] $IsCompliant = $false
    [string] $Comments = $null

    # list all users
    $urlPath = "/users"
    try {
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
        # portal
        $data = $response.Content
        # # localExecution
        # $data = $response

        if ($null -ne $data -and $null -ne $data.value) {
            $users = $data.value | Select-Object userPrincipalName , displayName, givenName, surname, id, mail
        }
    }
    catch {
        $errorMsg = "Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"                
        $ErrorList.Add($errorMsg)
        Write-Error "Error: $errorMsg"
    }

    # Read from the blob
    # Add possible file extensions
    $DocumentName_privilegedUserAdminAccountUPN = add-documentFileExtensions -DocumentName1 $DocumentName1 -ItemName $ItemName
    $DocumentName_PrivilegedUserRegularAccountUPN = add-documentFileExtensions -DocumentName2 $DocumentName2 -ItemName $ItemName

    try {
        Set-AzContext -Subscription $SubscriptionID | out-null
    }
    catch{
        $ErrorList.Add("Failed to run 'Select-Azsubscription' with error: $_")
        throw "Error: Failed to run 'Select-Azsubscription' with error: $_"
    }
    try {
        $StorageAccount = Get-Azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction Stop
    }
    catch {
        $ErrorList.Add("Could not find storage account '$storageAccountName' in resoruce group '$resourceGroupName' of `
        subscription '$subscriptionId'; verify that the storage account exists and that you have permissions to it. Error: $_")

        throw "Could not find storage account '$storageAccountName' in resoruce group '$resourceGroupName' of `
            subscription '$subscriptionId'; verify that the storage account exists and that you have permissions to it. Error: $_"
    }

    ForEach ($docName in $DocumentName_privilegedUserAdminAccountUPN) {
        $blob = Get-AzStorageBlob -Container $ContainerName -Context $StorageAccount.Context -Blob $docName -ErrorAction SilentlyContinue

        If ($null -eq $blob) {            
            # a blob with the name $DocumentName was not located in the specified storage account
            $errorMsg = "Could not get blob from storage account '$storageAccountName' in resoruce group '$resourceGroupName' of `
            subscription '$subscriptionId'; verify that the blob exists and that you have permissions to it. Error: $_"
            $ErrorList.Add($errorMsg) 
            #Write-Error "Error: $errorMsg"                 
            $commentsArray += $msgTable.procedureFileNotFound -f $ItemName, $docName, $ContainerName, $StorageAccountName
        }
        else {
            try {
                $blobContent = $blob.ICloudBlob.DownloadText()
                # Further processing of $blobContent...
            } catch {
                $errorMsg = "Error downloading content from blob '$docName': $_"
                $ErrorList.Add($errorMsg)
                Write-Error "Error: $errorMsg"                    
            }
            if ([string]::IsNullOrWhiteSpace($blobContent)) {
                $commentsArray += $msgTable.globalAdminFileEmpty -f $docName
            }
            elseif ($blobContent -ieq 'N/A' -or`
                    $blobContent -ieq 'NA') {
                $commentsArray += $msgTable.globalAdminNotExist -f $docName
            }
            else {
                # Blob content is present and needs to be parsed
                # Parses the UPNs and sanitizes them
                $result = Parse-BlobContent -blobContent $blobContent
                $privilegedUserAdminAccountUPN = $result.UserUPNs
            }
        }   
    }



    $Comments = $commentsArray -join ";"
    
    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        ItemName         = $ItemName
        Comments         = $Comments
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }

    # Conditionally add the Profile field based on the feature flag
    if ($EnableMultiCloudProfiles) {
        $result = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        if ($result -eq 0) {
            Write-Output "No matching profile found"
            $PsObject.ComplianceStatus = "Not Applicable"
        } else {
            Write-Output "Valid profile returned: $result"
            $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $result
        }
    }
    
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput   
}

