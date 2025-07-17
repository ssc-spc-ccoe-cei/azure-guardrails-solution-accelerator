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
        [string[]] $DocumentName,
        [string] 
        $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] 
        $EnableMultiCloudProfiles # New feature flag, default to false
    )

    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    [bool] $IsCompliant = $false
    [string] $Comments = $null

    # highly privileged Role names
    $highlyPrivilegedAdminRoleNames = @("Global Administrator","Privileged Role Administrator")

    # Get the list of GA users (ACTIVE assignments)
    $urlPath = "/directoryRoles"
    try {
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
        # portal
        $data = $response.Content
        # # localExecution
        # $data = $response

        if ($null -ne $data -and $null -ne $data.value) {
            $rolesResponse  = $data.value
        }
    }
    catch {
        $errorMsg = "Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"                
        $ErrorList.Add($errorMsg)
        Write-Error "Error: $errorMsg"
    }

    $hpAdminUserAccounts = @()

    # # Filter the highly privileged Administrator role ID
    $highlyPrivilegedAdminRole = $rolesResponse | Where-Object { $_.displayName -eq $highlyPrivilegedAdminRoleNames[0] -or $_.displayName -eq $highlyPrivilegedAdminRoleNames[1] }
    foreach ($role in  $highlyPrivilegedAdminRole){
        # Get directory roles for each user with the highly privileged admin access

        $roleAssignments = @()

        $roleId = $role.id
        $roleName = $role.displayName
        # Endpoint to get members of the role
        $urlPath = "/directoryRoles/$roleId/members"
        try{
            $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
            # portal
            $data = $response.Content
            # # localExecution
            # $data = $response

            if ($null -ne $data -and $null -ne $data.value) {
                $hpAdminRoleResponse  = $data.value
            }
        }
        catch {
            $errorMsg = "Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"                
            $ErrorList.Add($errorMsg)
            Write-Error "Error: $errorMsg"
        }

        foreach ($hpAdminUser in $hpAdminRoleResponse) {
            $roleAssignments = [PSCustomObject]@{
                roleId              = $roleId
                roleName            = $roleName
                userId              = $hpAdminUser.id
                displayName         = $hpAdminUser.displayName
                mail                = $hpAdminUser.mail
                userPrincipalName   = $hpAdminUser.userPrincipalName
            }
            $hpAdminUserAccounts +=  $roleAssignments
        }
    }

    # list all users
    $urlPath = "/users"
    try {
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
        # portal
        $data = $response.Content
        # # localExecution
        # $data = $response

        if ($null -ne $data -and $null -ne $data.value) {
            $allUsers = $data.value | Select-Object userPrincipalName , displayName, givenName, surname, id, mail
        }
    }
    catch {
        $errorMsg = "Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"                
        $ErrorList.Add($errorMsg)
        Write-Error "Error: $errorMsg"
    }

    # Filter and List non-privileged users from all user list
    $nonHPAdminUserAccounts = $allUsers | Where-Object { $_.userPrincipalName -notin $hpAdminUserAccounts.userPrincipalName }


    # Read UPN files from storage with .csv extensions, add possible file extensions
    $DocumentName_new = add-documentFileExtensions -DocumentName $DocumentName -ItemName $ItemName

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

    $commentsArray = @()
    $blobFound = $false
    $baseFileNameFound = $false
    $hasBlobContent = $false
    
    # Get a list of filenames uploaded in the blob storage
    $blobs = Get-AzStorageBlob -Container $ContainerName -Context $StorageAccount.Context
    if ($null -eq $blobs) {            
        # a blob with the name $DocumentName was not located in the specified storage account
        $errorMsg = "Could not get blob from storage account '$storageAccountName' in resoruce group '$resourceGroupName' of `
        subscription '$subscriptionId'; verify that the blob exists and that you have permissions to it. Error: $_"
        $ErrorList.Add($errorMsg) 
            
        $blobFound = $false
    }
    else{
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
            else {
                $blobFound = $false
                $baseFileNameFound = $false
            }
        }
        else {
            # also covers the use case if more than 1 appropriate files are uploaded
            $blobFound = $true
        }
    }
    
    # Use case: uploaded fileName is correct but has wrong extension
    if ($baseFileNameFound){
        # a blob with the name $documentName was located in the specified storage account; however, the ext is not correct
        $commentsArray += $msgTable.procedureFileNotFoundWithCorrectExtension -f $DocumentName[0], $ContainerName, $StorageAccountName
    }
    elseif ($blobFound){
        Write-host "Retrieve UPNs from file for compliance check"
        # get UPN from the file
        $blob = Get-AzStorageBlob -Container $ContainerName -Context $StorageAccount.Context -Blob $DocumentName_new
        if ($blob) {            
            ## blob found
            try {
                $blobContent = $blob.ICloudBlob.DownloadText()| ConvertFrom-Csv
            } catch {
                $errorMsg = "Error downloading content from blob '$DocumentName_new': $_"
                $ErrorList.Add($errorMsg)
                Write-Error "Error: $errorMsg"                    
            }
    
            if ($null -eq $blobContent -or $blobContent -ieq 'N/A' -or $blobContent -ieq 'NA') {
                $commentsArray += $msgTable.invalidUserFile -f $DocumentName_new
            }
            else{
                Write-host "Blobcontent is not null or blob doesn't contain NA"
                $hasBlobContent = $true
            } 
        }    
    }
    else {
        # a blob with the name $DocumentName was not located in the specified storage account    
        $commentsArray += $msgTable.procedureFileNotFound -f $DocumentName[0], $ContainerName, $StorageAccountName
    }

    if ($hasBlobContent){
        # Blob content is present
        $headers = $blobContent[0].PSObject.Properties.Name
        # check of correct headers
        if (!($headers -contains "HP_admin_account_UPN" -and $headers -contains "regular_account_UPN") ) {
            Write-Host "Appropriate file header missing"
            $commentsArray += $msgTable.isNotCompliant + " " + $msgTable.invalidFileHeader -f $DocumentName_new
            
        } else {
            Write-Host "Appropriate file headers found!"

            $UserAccountUPNs = $blobContent 

            # if BG accounts present in the UPN list
            $BGfound = $false
            foreach ($user in $UserAccountUPNs) {
                if ($user.HP_admin_account_UPN -like $FirstBreakGlassUPN  -or $user.regular_account_UPN -like $FirstBreakGlassUPN  -or `
                    $user.HP_admin_account_UPN -like $SecondBreakGlassUPN  -or $user.regular_account_UPN -like $SecondBreakGlassUPN) {
                    $BGfound = $true
                    break
                } 
            }

            $hpGroupUPN = $UserAccountUPNs.HP_admin_account_UPN
            $regGroupUPN = $UserAccountUPNs.regular_account_UPN

            $hpUPNisNull = $false
            $regUPNisNull = $false
            

            # Check for both types of UPN exists in the list
            if ($hpGroupUPN -contains $null -or $hpGroupUPN -contains ""){
                $hpUPNisNull = $true
            }
            if ( $regGroupUPN -contains $null -or$regGroupUPN -contains ""){
                $regUPNisNull = $true
            }
            
            ## Condition: BG account in attestation file list
            if ($BGfound) { 
                $IsCompliant = $false
                $commentsArray = $msgTable.isNotCompliant + " " + $msgTable.bgAccExistInUPNlist
            }
            elseif ($hpUPNisNull){
                # Condition: HP account data is missing
                $IsCompliant = $false
                $commentsArray = $msgTable.isNotCompliant + " " + $msgTable.missingHPaccUPN
            }
            elseif ($regUPNisNull){
                # Condition: Reg account data is missing
                $IsCompliant = $false
                $commentsArray = $msgTable.isNotCompliant + " " + $msgTable.missingRegAccUPN
            }
            else {
                $hpDuplicateUPN = $false
                $regDuplicateUPN = $false 

                # Check for duplicate UPNs in the list
                $hpDuplicates = $hpGroupUPN | Group-Object | Where-Object { $_.Count -gt 1 }
                $regDuplicates = $regGroupUPN | Group-Object | Where-Object { $_.Count -gt 1 }

                if ($hpDuplicates.Count -ge 2){
                    $hpDuplicateUPN = $true
                }
                if ( $regDuplicates.Count -ge 2){
                    $regDuplicateUPN = $true
                }

                if ($hpDuplicateUPN){
                    # Condition: HP account has duplicate UPN
                    $IsCompliant = $false
                    $commentsArray = $msgTable.isNotCompliant + " " + $msgTable.dupHPAccount
                }
                elseif ($regDuplicateUPN){
                    # Condition: Reg account has duplicate UPN
                    $IsCompliant = $false
                    $commentsArray = $msgTable.isNotCompliant + " " + $msgTable.dupRegAccount
                }
                else{
                    $hpUPNinRegFound = $false
                    $regUPNinPAFound = $false
                    $hpUPNnotGA = $false
    
                    # validate: check HP users ONLY have HP admin role assignments
                    foreach ($hpAdmin in $UserAccountUPNs.HP_admin_account_UPN){
                        
                        if ( $hpAdminUserAccounts.userPrincipalName -contains $hpAdmin){
                            # each HP admin has active GA or PA role assignment
                            if ($nonHPAdminUserAccounts.userPrincipalName -contains $hpAdmin){
                                # not dedicated user UPN for admin
                                $hpUPNinRegFound = $true
                                break
                            }
                            else{
                                # validate: regular accounts are non-GA/PA role assignments
                                foreach ($regUPN in $UserAccountUPNs.regular_account_UPN){
                                    if ( $hpAdminUserAccounts.userPrincipalName -contains $regUPN){
                                        $regUPNinPAFound = $true
                                        break 
                                    }
                                }
                            }
                        }
                        else{
                            # listed admin UPN doesn't have active GA
                            $hpUPNnotGA = $true
                            break
                        }
                    }
    
                    # Compliance status
                    if($hpUPNinRegFound){
                        $IsCompliant = $false
                        $commentsArray = $msgTable.isNotCompliant + " " + $msgTable.dedicatedAdminAccNotExist
                    }
                    elseif($regUPNinPAFound){
                        $IsCompliant = $false
                        $commentsArray = $msgTable.isNotCompliant + " " + $msgTable.regAccHasHProle
                    }
                    else{
                        $IsCompliant = $true
                        $commentsArray = $msgTable.isCompliant + " " + $msgTable.dedicatedAccExist
                    }
    
                    if( $hpUPNnotGA){
                        $commentsArray += " " + $msgTable.hpAccNotGA
                    }
                } 
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

    # #Conditionally add the Profile field based on the feature flag
    if ($EnableMultiCloudProfiles) {
        $result = Add-ProfileInformation -Result $PsObject -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId
        Write-Host "$result"
    }
    
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput   
}