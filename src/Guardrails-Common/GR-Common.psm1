function get-tagValue {
    param (
        [string] $tagKey,
        [System.Object] $object
    )
    $tagString = get-tagstring($object)
    $tagslist = $tagString.split(";")
    foreach ($tag in $tagslist) {
        if ($tag.split("=")[0] -eq $tagKey) {
            return $tag.split("=")[1]
        }
    }
    return ""
}
function get-tagstring ($object) {
    if ($object.Tag.Count -eq 0) {
        $tagstring = "None"
    }
    else {
        $tagstring = ""
        $tKeys = $object.tag | Select-Object -ExpandProperty keys
        $tValues = $object.Tag | Select-Object -ExpandProperty values
        $index = 0
        if ($object.Tag.Count -eq 1) {
            $tagstring = "$tKeys=$tValues"
        }
        else {
            foreach ($tkey in $tkeys) {
                $tagstring += "$tkey=$($tValues[$index]);"
                $index++
            }
        }
    }
    return $tagstring.Trim(";")
}
function get-rgtagstring ($object) {
    if ($object.Tags.Count -eq 0) {
        $tagstring = "None"
    }
    else {
        $tagstring = ""
        $tKeys = $object.tags | Select-Object -ExpandProperty keys
        $tValues = $object.Tags | Select-Object -ExpandProperty values
        $index = 0
        if ($object.Tags.Count -eq 1) {
            $tagstring = "$tKeys=$tValues"
        }
        else {
            foreach ($tkey in $tkeys) {
                $tagstring += "$tkey=$($tValues[$index]);"
                $index++
            }
        }
    }
    return $tagstring.Trim(";")
}
function get-rgtagValue {
    param (
        [string] $tagKey,
        [System.Object] $object
    )
    $tagString = get-rgtagstring($object)
    $tagslist = $tagString.split(";")
    foreach ($tag in $tagslist) {
        if ($tag.split("=")[0] -eq $tagKey) {
            return $tag.split("=")[1]
        }
    }
    return ""
}
function copy-toBlob {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $FilePath,
        [Parameter(Mandatory = $true)]
        [string]
        $storageaccountName,
        [Parameter(Mandatory = $true)]
        [string]
        $resourcegroup,
        [Parameter(Mandatory = $true)]
        [string]
        $containerName,
        [Parameter(Mandatory = $false)]
        [switch]
        $force
    )
    try {
        $saParams = @{
            ResourceGroupName = $resourcegroup
            Name              = $storageaccountName
        }
        $scParams = @{
            Container = $containerName
        }
        $bcParams = @{
            File = $FilePath
            Blob = ($FilePath | Split-Path -Leaf)
        }
        if ($force)
        { Get-AzStorageAccount @saParams | Get-AzStorageContainer @scParams | Set-AzStorageBlobContent @bcParams -Force | Out-Null }
        else { Get-AzStorageAccount @saParams | Get-AzStorageContainer @scParams | Set-AzStorageBlobContent @bcParams | Out-Null }
    }
    catch {
        Write-Error $_.Exception.Message
    }
}
function get-blobs {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $storageaccountName,
        [Parameter(Mandatory = $true)]
        [string]
        $resourcegroup
    )
    $psModulesContainerName = "psmodules"
    try {
        $saParams = @{
            ResourceGroupName = $resourcegroup
            Name              = $storageaccountName
        }
        $scParams = @{
            Container = $psModulesContainerName
        }
        return (Get-AzStorageAccount @saParams | Get-AzStorageContainer @scParams | Get-AzStorageBlob)
    }
    catch {
        Write-Error $_.Exception.Message
    }
}

function read-blob {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $FilePath,
        [Parameter(Mandatory = $true)]
        [string]
        $storageaccountName,
        [Parameter(Mandatory = $true)]
        [string]
        $resourcegroup,
        [Parameter(Mandatory = $true)]
        [string]
        $containerName,
        [Parameter(Mandatory = $false)]
        [switch]
        $force
    )
    $Context = (Get-AzStorageAccount -ResourceGroupName $resourcegroup -Name $storageaccountName).Context
    $blobParams = @{
        Blob        = 'modules.json'
        Container   = $containerName
        Destination = $FilePath
        Context     = $Context
        Force       = $true
    }
    Get-AzStorageBlobContent @blobParams
}

Function Add-LogEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True, Position = 0)]
        [ValidateSet("Critical", "Error", "Warning", "Information", "Debug")]
        [string]
        $severity,

        # message details (string)
        [Parameter(Mandatory = $true, Position = 1)]
        [string]
        $message,

        # module name
        [Parameter(Mandatory = $false)]
        [string]
        $moduleName = (Split-Path -Path $MyInvocation.ScriptName -Leaf),

        # additional values in hashtable
        [Parameter(Mandatory = $false)]
        [hashtable]
        $additionalValues = @{},

        # exception log type - this is the Log Analytics table name
        [Parameter(Mandatory = $false)]
        [string]
        $exceptionLogTable = "GuardrailsComplianceException",

        # guardrails exception workspace GUID
        [Parameter(Mandatory = $true)]
        [string]
        $workspaceGuid,

        # guardrails exception workspace shared key
        [Parameter(Mandatory = $true)]
        [string]
        $workspaceKey
    )

    # build log entry object, convert to json
    $entryHash = @{
        "message"    = $message
        "moduleName" = $moduleName
        "severity"   = $severity
    } + $additionalValues
    
    $entryJson = ConvertTo-Json -inputObject $entryHash -Depth 20

    # log event to Log Analytics workspace by REST API via the OMSIngestionAPI community PS module
    Send-OMSAPIIngestionFile  -customerId $workspaceGuid `
        -sharedkey $workspaceKey `
        -body $entryJson `
        -logType $exceptionLogTable `
        -TimeStampField Get-Date 

}

Function Add-TenantInfo {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $WorkSpaceID,
        [Parameter(Mandatory = $true)]
        [string]
        $workspaceKey,
        [Parameter(Mandatory = $false)]
        [string]
        $LogType = "GR_TenantInfo",
        [Parameter(Mandatory = $true)]
        [string]
        $ReportTime,
        [Parameter(Mandatory = $true)]
        [string]
        $TenantId,
        [Parameter(Mandatory = $true)]
        [string]
        $DepartmentName,
        [Parameter(Mandatory = $true)]
        [string]
        $DepartmentNumber,
        [Parameter(Mandatory = $true)]
        [string]
        $cloudUsageProfiles,
        [Parameter(Mandatory = $true)]
        [string]
        $tenantName
    )
    $tenantInfo = Get-GSAAutomationVariable("tenantDomainUPN")

    $object = [PSCustomObject]@{ 
        TenantDomain       = $tenantInfo
        DepartmentTenantID = $TenantId
        DepartmentTenantName= $tenantName
        ReportTime         = $ReportTime
        DepartmentName     = $DepartmentName
        DepartmentNumber   = $DepartmentNumber
        cloudUsageProfiles = $cloudUsageProfiles
    }
    if ($debug) { Write-Output $tenantInfo }
    $JSON = ConvertTo-Json -inputObject $object

    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
        -sharedkey $workspaceKey `
        -body $JSON `
        -logType $LogType `
        -TimeStampField Get-Date 
}

function Add-LogAnalyticsResults {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $WorkSpaceID,
        [Parameter(Mandatory = $true)]
        [string]
        $workspaceKey,
        [Parameter(Mandatory = $false)]
        [string]
        $LogType = "GR_Results",
        [Parameter(Mandatory = $false)]
        [array]
        $Results
    )

    $JSON = ConvertTo-Json -inputObject $Results

    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
        -sharedkey $workspaceKey `
        -body $JSON `
        -logType $LogType `
        -TimeStampField Get-Date 
}

function Check-GAAuthenticationMethods {
    param (
        [string] $StorageAccountName,
        [string] $ContainerName, 
        [string] $ResourceGroupName,
        [string] $SubscriptionID, 
        [string[]] $DocumentName, 
        [string] $ControlName, 
        [string]$ItemName,
        [hashtable] $msgTable, 
        [string]$itsgcode,
        [Parameter(Mandatory = $true)]
        [string]
        $ReportTime
    )
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    [bool] $IsCompliant = $false
    [string] $Comments = $null

    # Add possible file extensions
    $DocumentName_new = add-documentFileExtention -DocumentName $DocumentName -ItemName $ItemName
    
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

    $mfaCounter = 0
    $commentsArray = @()
    $globalAdminUPNs = @()

    $GAUPNsMFA = @()

    ForEach ($docName in $DocumentName_new) {
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
                $globalAdminUPNs = $result.GlobalAdminUPNs
            }
        }   
    }

    
    if ($globalAdminUPNs.Count -ge 2) {
        
        ForEach ($globalAdminAccount in $globalAdminUPNs) {
            $urlPath = '/users/' + $globalAdminAccount + '/authentication/methods'
            
            # create hidden format UPN
            $hiddenUPN = Hide-Email -email $globalAdminAccount
            
            
            try {
                $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop

            }
            catch {
                $errorMsg = "Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"                
                $ErrorList.Add($errorMsg)
                Write-Error "Error: $errorMsg"
            }

            # # To check if MFA is setup for a user, we're checking various authentication methods:
            # # 1. #microsoft.graph.microsoftAuthenticatorAuthenticationMethod
            # # 2. #microsoft.graph.phoneAuthenticationMethod
            # # 3. #microsoft.graph.passwordAuthenticationMethod - not considered for MFA
            # # 4. #microsoft.graph.emailAuthenticationMethod - not considered for MFA
            # # 5. #microsoft.graph.fido2AuthenticationMethod
            # # 6. #microsoft.graph.softwareOathAuthenticationMethod

            if ($null -ne $response) {
                $data = $response.Content
                if ($null -ne $data -and $null -ne $data.value) {
                    $authenticationmethods = $data.value
                    
                    $authFound = $false
                    foreach ($authmeth in $authenticationmethods) {                        
                        if (($($authmeth.'@odata.type') -eq "#microsoft.graph.phoneAuthenticationMethod") -or `
                            ($($authmeth.'@odata.type') -eq "#microsoft.graph.microsoftAuthenticatorAuthenticationMethod") -or`
                            ($($authmeth.'@odata.type') -eq "#microsoft.graph.fido2AuthenticationMethod" ) -or`
                            ($($authmeth.'@odata.type') -eq "#microsoft.graph.softwareOathAuthenticationMethod" ) ) {
                                
                                # need to keep track of each GA mfa in counter and compare it to count
                                $mfaCounter += 1
                                $authFound = $true
                                # atleast one auth method is true - so we move to the next UPN 
                                break
                        }
                    }
                    if($authFound){
                        # This message is being used for debugging
                        Write-Host "Auth method found for $globalAdminAccount"
                    }
                    else{
                        # This message is being used for debugging
                        Write-Host "$globalAdminAccount does not have MFA enabled"

                        # Create an instance of inner list object
                        $GAUPNtemplate = [PSCustomObject]@{
                            UPN  = $globalAdminAccount
                            MFAStatus   = $false
                            MFAComments = $hiddenUPN 
                        }
                        # Add the list to GA MFA list
                        $GAUPNsMFA += $GAUPNtemplate
                    }
                }
                else {
                    $errorMsg = "No authentication methods data found for $globalAdminAccount"                
                    $ErrorList.Add($errorMsg)
                    Write-Error "Error: $errorMsg"    
                }
            }
            else {
                $errorMsg = "Failed to get response from Graph API for $globalAdminAccount"                
                $ErrorList.Add($errorMsg)
                Write-Error "Error: $errorMsg"    
            }    
        }
    }

    # Condition: GA UPN list has less than 2 UPN
    if ($globalAdminUPNs.Count -lt 2) {
        $commentsArray += $msgTable.globalAdminMinAccnts
    }
    # Condition: GA UPN list has > 2 UPNs and all are MFA enabled
    elseif($globalAdminUPNs.Count -ge 2 -and $mfaCounter -eq $globalAdminUPNs.Count) {
        $commentsArray += $msgTable.globalAdminMFAPassAndMin2Accnts
        $IsCompliant = $true
    }
    # Condition: GA UPN list has > 2 UPNs and not all UPNs are MFA enabled
    else{
        # This will be used for debugging
        if($GAUPNsMFA.Count -eq 0){
            Write-Host "Something is wrong as GAUPNsMFA Count equals 0. This output should only execute if there is an error populating GAUPNsMFA"
        }
        else{
            # only one UPN is not MFA enable
            if ( $GAUPNsMFA.Count -eq 1 ) {
                $commentsArray += $msgTable.globalAdminAccntsMFADisabled1 -f $GAUPNsMFA[0].MFAComments
            }
            # None are MFA enabled
            elseif ( $GAUPNsMFA.Count -eq $globalAdminUPNs.Count) {
                $commentsArray += $msgTable.globalAdminAccntsMFADisabled3
            }
            # 2 or more UPNs in the list are not MFA enabled
            else {
                $hiddenUPNsString = ""
                for ($i =0; $i -lt $GAUPNsMFA.Count; $i++) {
                    $hiddenUPNsString += $GAUPNsMFA[$i].MFAComments + ", "
                }
                $hiddenUPNsString = $hiddenUPNsString.TrimEnd(', ')
                $commentsArray += $msgTable.globalAdminAccntsMFADisabled2 -f $hiddenUPNsString
            }
        }
    }
    
    $Comments = $commentsArray -join ";"

    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        ItemName         = $ItemName
        DocumentName     = $DocumentName
        Comments         = $Comments
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }
    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors            = $ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput

}

function Check-DocumentExistsInStorage {
    [Alias('Check-DocumentsExistInStorage')]
    param (
        [string] $StorageAccountName,
        [string] $ContainerName, 
        [string] $ResourceGroupName,
        [string] $SubscriptionID, 
        [string[]] $DocumentName, 
        [string] $ControlName, 
        [string]$ItemName,
        [hashtable] $msgTable, 
        [string]$itsgcode,
        [Parameter(Mandatory = $true)]
        [string]
        $ReportTime
    )
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    [bool] $IsCompliant = $false
    [string] $Comments = $null

    # Add possible file extensions
    $DocumentName_new = add-documentFileExtention -DocumentName $DocumentName -ItemName $ItemName

    try {
        Select-AzSubscription -Subscription $SubscriptionID | out-null
    }
    catch {
        $ErrorList.Add("Failed to run 'Select-Azsubscription' with error: $_")
        #Add-LogEntry 'Error' 
        throw "Error: Failed to run 'Select-Azsubscription' with error: $_"
    }
    try {
        $StorageAccount = Get-Azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction Stop
    }
    catch {
        $ErrorList.Add("Could not find storage account '$storageAccountName' in resoruce group '$resourceGroupName' of `
        subscription '$subscriptionId'; verify that the storage account exists and that you have permissions to it. Error: $_")
        #Add-LogEntry 'Error' "Could not find storage account '$storageAccountName' in resoruce group '$resourceGroupName' of `
        #    subscription '$subscriptionId'; verify that the storage account exists and that you have permissions to it. Error: $_" `
        #    -workspaceKey $workspaceKey -workspaceGuid $WorkSpaceID
        Write-Error "Could not find storage account '$storageAccountName' in resoruce group '$resourceGroupName' of `
            subscription '$subscriptionId'; verify that the storage account exists and that you have permissions to it. Error: $_"
    }

    $docMissing = $false
    $commentsArray = @()
    $blobFound = $false
   
    ForEach ($docName in $DocumentName_new) {
        # check for procedure doc in blob storage account
        $blobs = Get-AzStorageBlob -Container $ContainerName -Context $StorageAccount.Context -Blob $docName -ErrorAction SilentlyContinue

        If ($blobs) {
            $blobFound = $true
            break
        }
    }

    if ($blobFound){
        # a blob with the name $attestationFileName was located in the specified storage account
        $commentsArray += $msgTable.procedureFileFound -f $docName
    }
    else {
        # no blob with the name $attestationFileName was found in the specified storage account
        $docMissing = $true
        $commentsArray += $msgTable.procedureFileNotFound -f $ItemName, $DocumentName[0], $ContainerName, $StorageAccountName
    }

    $Comments = $commentsArray -join ";"

    If ($docMissing) {
        $IsCompliant = $false
    }
    Else {
        $IsCompliant = $true
    }

    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        ItemName         = $ItemName
        DocumentName     = $DocumentName
        Comments         = $Comments
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }
    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors            = $ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput

}

function Check-UpdateAvailable {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $WorkSpaceID,
        [Parameter(Mandatory = $true)]
        [string]
        $workspaceKey,
        [Parameter(Mandatory = $false)]
        [string]
        $LogType = "GR_VersionInfo",
        [Parameter(Mandatory = $true)]
        [string]
        $ReportTime,
        [Parameter(Mandatory = $false)]
        [string]
        $ResourceGroupName
    )
    #fetches current public version (from repo...maybe should download the zip...)
    $latestRelease = Invoke-RestMethod 'https://api.github.com/repos/ssc-spc-ccoe-cei/azure-guardrails-solution-accelerator/releases/latest' -Verbose:$false
    $tagsFileURI = "https://github.com/ssc-spc-ccoe-cei/azure-guardrails-solution-accelerator/raw/{0}/setup/tags.json" -f $latestRelease.name
    $tags = Invoke-RestMethod $tagsFileURI -Verbose:$false

    if ([string]::IsNullOrEmpty($ResourceGroupName)) {
        $ResourceGroupName = Get-AutomationVariable -Name "ResourceGroupName"
    }
    $rg=Get-AzResourceGroup -Name $ResourceGroupName 

    $deployedVersion=$rg.Tags["ReleaseVersion"]
    $currentVersion = $tags.ReleaseVersion

    try {
        # script version numbers of surrounding characters and then converted to a version object
        $deployedVersionVersion = [version]::Parse(($deployedVersion -replace '[\w-]+?(\d+?\.\d+?\.\d+?(\.\d+?)?)[\w-]*$','$1'))
        $currentVersionVersion = [version]::Parse(($currentVersion -replace '[\w-]+?(\d+?\.\d+?\.\d+?(\.\d+?)?)[\w-]*$','$1'))
    }
    catch {
        Write-Error "Error: Failed to convert version numbers to version objects. Error: $_"
    }

    if ($debug) { Write-Output "Resource Group Tag (deployed version): $deployedVersion; $deployedVersionVersion"}
    if ($debug) { Write-Output "Latest available version from GitHub: $currentVersion; $currentVersionVersion"}
    
    if ($deployedVersionVersion -lt $currentVersionVersion)
    {
        $updateNeeded=$true
    }
    else {
        $updateNeeded = $false
    }
    $object = [PSCustomObject]@{ 
        DeployedVersion = $deployedVersion
        AvailableVersion = $currentVersion
        UpdateNeeded= $updateNeeded
        ReportTime = $ReportTime
    }
    $JSON = ConvertTo-Json -inputObject $object

    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
        -sharedkey $workspaceKey `
        -body $JSON `
        -logType $LogType `
        -TimeStampField Get-Date 
}
function get-itsgdata {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $URL,
        [string] $WorkSpaceID,
        [string] $workspaceKey,
        [string] $LogType = "GRITSGControls",
        [switch] $DebugCode
    )
    (Invoke-WebRequest -UseBasicParsing $URL).Content | out-file tempitsg.csv
    $Header = "Family", "Control ID", "Enhancement", "Name", "Class", "Definition", "Supplemental Guidance,References"
    $itsgtempinfo = Import-Csv ./tempitsg.csv -Header $Header
    $itsginfo = $itsgtempinfo | Select-Object Name, Definition, @{Name = "itsgcode"; Expression = { ($_.Family + $_."Control ID" + $_.Enhancement).replace("`t", "") } }
    $JSONcontrols = ConvertTo-Json -inputObject $itsginfo
    
    if ($DebugCode) {
        $JSONcontrols
    }

    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
        -sharedkey $workspaceKey `
        -body $JSONcontrols `
        -logType $LogType `
        -TimeStampField Get-Date
}
function New-LogAnalyticsData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array] 
        $Data,
        [Parameter()]
        [string]
        $WorkSpaceID,
        [Parameter()]
        [string]
        $WorkSpaceKey,
        [Parameter()]
        [string]
        $LogType
    )
    $JsonObject = convertTo-Json -inputObject $Data -Depth 3

    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
        -sharedkey $workspaceKey `
        -body $JsonObject `
        -logType $LogType `
        -TimeStampField Get-Date  
}

function Hide-Email {
    param (
        [string]$email
    )

    $parts = $email -split '@'
    if ($parts.Length -eq 2) {
        $username = $parts[0]
        $domain = $parts[1]

        $hiddenUsername = $username[0] + ($username.Substring(1, $username.Length - 2) -replace '.', '#') + $username[-1]
        $hiddenDomain = $domain[0] + ($domain.Substring(1, $domain.Length - 5) -replace '.', '#') + $domain[-4] + $domain[-3] + $domain[-2] + $domain[-1]

        $hiddenEmail = "$hiddenUsername@$hiddenDomain"
        return $hiddenEmail
    } else {
        return "Invalid email format"
    }
}

function Parse-BlobContent {
    param (
        [string]$blobContent
    )

    # Check if blob content is retrieved
    if (-not $blobContent) {
        throw "Failed to retrieve blob content or blob is empty."
    }

    # Split content into lines
    $lines = $blobContent -split "`r`n|`n|,|;|,\s|;\s"

    $filteredLines = $lines | Where-Object { $_ -match '\S' -and $_ -like "*@*" } | ForEach-Object { $_ -replace '\s' }

    # Initialize an empty array
    $globalAdminUPNs = @()

    # Check each line, remove the hyphen (if any), and add to array
    foreach ($line in $filteredLines) {
        if ($line.StartsWith("-")) {
            # Remove the leading hyphen and any potential whitespace after it
            $trimmedLine = $line.Substring(1)
        } 
        else{
            $trimmedLine = $line
        }
        $trimmedLine = $trimmedLine.Trim()
        $globalAdminUPNs += $trimmedLine
    }

    $result = New-Object PSObject -Property @{
        GlobalAdminUPNs = $globalAdminUPNs
    }

    return $result
}

function Invoke-GraphQuery {
    param(
        # URL path (ex: /users)
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^(?!https://graph.microsoft.com/(v1|beta)/)')]
        [string]
        $urlPath
    )

    try {
        $uri = "https://graph.microsoft.com/v1.0$urlPath" -as [uri]
        
        $response = Invoke-AzRestMethod -Uri $uri -Method GET -ErrorAction Stop

    }
    catch {
        Write-Error "An error occured constructing the URI or while calling Graph query for URI GET '$uri': $($_.Exception.Message)"
    }
    
    @{
        Content    = $response.Content | ConvertFrom-Json
        StatusCode = $response.StatusCode

    }

}

# Function to add other possible file extension(s) to the module file names
function add-documentFileExtention {
    param (
        [string[]] $DocumentName,
        [string]$ItemName

    )

    if ($ItemName.ToLower() -eq 'network architecture diagram'){
        $fileExtensions = @(".pdf", ".png", ".jpeg", ".vsdx")
    }
    elseif ($ItemName.ToLower() -eq 'global administrators accounts mfa check') {
        $fileExtensions = @(".txt")
    }
    else {
        $fileExtensions = @(".txt",".docx", ".doc")
    }
    
    $DocumentName_new = New-Object System.Collections.Generic.List[System.Object]
    ForEach ($fileExt in $fileExtensions) {
        $DocumentName_new.Add($DocumentName[0] + $fileExt)
    }

    return $DocumentName_new
}

# endregion

