function get-tagValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $tagKey,
        [Parameter(Mandatory = $true)]
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
function get-tagstring {
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [System.Object] $object
    )
    if ($object.Tag.Count -eq 0) {
        $tagstring = "None"
    }
    else {
        $tagstring = [System.Text.StringBuilder]::new()
        $tKeys = $object.tag | Select-Object -ExpandProperty keys
        $tValues = $object.Tag | Select-Object -ExpandProperty values
        $index = 0

        if ($object.Tag.Count -eq 1) {
            $tagstring = "$tKeys=$tValues"
        }
        else {
            foreach ($tkey in $tKeys) {
                [void]$tagstring.Append("$tkey=$($tValues[$index]);")
                $index++
            }
        }
        $tagstring = $tagstring.ToString().TrimEnd(';')
    }
    return $tagstring
}
function get-rgtagstring {
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [System.Object] $object
    )
    if ($object.Tags.Count -eq 0) {
        $tagstring = "None"
    }
    else {
        $tagstring = [System.Text.StringBuilder]::new()
        $tKeys = $object.tags | Select-Object -ExpandProperty keys
        $tValues = $object.Tags | Select-Object -ExpandProperty values
        $index = 0
        foreach ($tkey in $tKeys) {
            [void]$tagstring.Append("$tkey=$($tValues[$index]);")
            $index++
        }
        $tagstring = $tagstring.ToString().TrimEnd(';')
    }
    return $tagstring
}
function get-rgtagValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $tagKey,
        [Parameter(Mandatory = $true)]
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
    [CmdletBinding()]
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
    [CmdletBinding()]
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
    [CmdletBinding()]
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
    [CmdletBinding()]
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
        $tenantName,
        [Parameter(Mandatory = $true)]
        [string]
        $locale
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
        Locale             = $locale
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
    [CmdletBinding()]
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

function Check-DocumentExistsInStorage {
    [Alias('Check-DocumentsExistInStorage')]
    [CmdletBinding()]
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
        [string[]] $DocumentName, 
        [Parameter(Mandatory = $true)]
        [string] $ControlName, 
        [Parameter(Mandatory = $true)]
        [string]$ItemName,
        [Parameter(Mandatory = $true)]
        [hashtable] $msgTable, 
        [Parameter(Mandatory = $true)]
        [string]$itsgcode,
        [Parameter(Mandatory = $true)]
        [string]
        $ReportTime,
        [Parameter(Mandatory = $false)]
        [string] 
        $CloudUsageProfiles = "3",  # Passed as a string
        [Parameter(Mandatory = $false)]
        [string] $ModuleProfiles,  # Passed as a string
        [Parameter(Mandatory = $false)]
        [switch] $EnableMultiCloudProfiles # New feature flag, default to false    
    )
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    [bool] $IsCompliant = $false
    [string] $Comments = $null

    # Add possible file extensions
    $DocumentName_new = add-documentFileExtensions -DocumentName $DocumentName -ItemName $ItemName

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
    $baseFileNameFound = $false
   
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
        $blobFound = $true
    }

    # Use case: uploaded fileName is correct but has wrong extension
    if ($baseFileNameFound){
        # a blob with the name $documentName was located in the specified storage account; however, the ext is not correct
        $docMissing = $true
        $commentsArray += $msgTable.procedureFileNotFoundWithCorrectExtension -f $DocumentName[0], $ContainerName, $StorageAccountName
    }
    else{
        if ($blobFound){
            # Use case: a blob with the name $documentName was located in the specified storage account
            $commentsArray += $msgTable.procedureFileFound -f  $DocumentName
        }
        else {
            # Use case: no blob with the name $documentName was found in the specified storage account
            $docMissing = $true
            $commentsArray += $msgTable.procedureFileNotFound -f $DocumentName[0], $ContainerName, $StorageAccountName
        }
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

    if ($EnableMultiCloudProfiles) {        
        $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $SubscriptionID
        if (!$evalResult.ShouldEvaluate) {
            if ($evalResult.Profile -gt 0) {
                $PsObject.ComplianceStatus = "Not Applicable"
                $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                $PsObject.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
                
                $moduleOutput = [PSCustomObject]@{ 
                    ComplianceResults = $PsObject
                    Errors            = $ErrorList
                    AdditionalResults = $AdditionalResults
                }
                return $moduleOutput
            } else {
                $ErrorList.Add("Error occurred while evaluating profile configuration")
            }
        } else {
            
            $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
        }
    }

    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors            = $ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput

}

function Check-UpdateAvailable {
    [CmdletBinding()]
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
    elseif(($deployedVersionVersion -eq $currentVersionVersion) -and ($deployedVersion -match 'beta')){
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
        [Parameter(Mandatory = $true)]
        [string]
        $URL,
        [Parameter(Mandatory = $true)]
        [string] $WorkSpaceID,
        [Parameter(Mandatory = $true)]
        [string] $workspaceKey,
        [Parameter(Mandatory = $false)]
        [string] $LogType = "GRITSGControls",
        [Parameter(Mandatory = $false)]
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
        [Parameter(Mandatory = $true)]
        [string]
        $WorkSpaceID,
        [Parameter(Mandatory = $true)]
        [string]
        $WorkSpaceKey,
        [Parameter(Mandatory = $true)]
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
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
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

function Get-EvaluationProfile {
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $CloudUsageProfiles,
        [Parameter(Mandatory = $true)]
        [string] $ModuleProfiles,
        [Parameter(Mandatory = $false)]
        [string] $SubscriptionId
    )
    Write-Host "Config CloudUsageProfiles $CloudUsageProfiles"
    Write-Host "MCP GR ModuleProfiles $ModuleProfiles"
    Write-Host "SubscriptionId $SubscriptionId"

    $returnProfile = ""
    $returnShouldEvaluate = $false
    $returnShouldAvailable = $false

    try {
        # Convert input strings to integer arrays  
        $cloudUsageProfileArray = ConvertTo-IntArray $CloudUsageProfiles
        $moduleProfileArray = ConvertTo-IntArray $ModuleProfiles

        if (-not $SubscriptionId) {
            $matchedProfile = Get-HighestMatchingProfile $cloudUsageProfileArray $moduleProfileArray
            return [PSCustomObject]@{
                Profile = $matchedProfile
                ShouldEvaluate = ($matchedProfile -in $cloudUsageProfileArray)
            }
        }

        $subscriptionTags = Get-AzTag -ResourceId "subscriptions/$SubscriptionId" -ErrorAction Stop
        $profileTagValues = if ($subscriptionTags.Properties -and 
                              $subscriptionTags.Properties.TagsProperty -and 
                              $subscriptionTags.Properties.TagsProperty['profile']) {
            $subscriptionTags.Properties.TagsProperty['profile']
        } else {
            $null
        }

        if ($null -eq $profileTagValues) {
            $matchedProfile = Get-HighestMatchingProfile $cloudUsageProfileArray $moduleProfileArray
            return [PSCustomObject]@{
                Profile = $matchedProfile
                ShouldEvaluate = ($matchedProfile -in $cloudUsageProfileArray)
                ShouldAvailable = ($matchedProfile -in $moduleProfileArray)
            }
        }

        $profileTagValuesArray = ConvertTo-IntArray $profileTagValues

        # Get the highest profile from all sources
        #cloudUsageProfile from config json
        $highestCloudUsageProfile = ($cloudUsageProfileArray | Measure-Object -Maximum).Maximum
        #module profiles for the guardrail
        $highestModuleProfile = ($moduleProfileArray | Measure-Object -Maximum).Maximum
        #subscription tag
        $highestTagProfile = ($profileTagValuesArray | Measure-Object -Maximum).Maximum


        $returnProfile = $highestTagProfile
        $returnShouldAvailable = ($highestTagProfile -in $moduleProfileArray)
        # Use the highest profile if it's present in the module profiles
        if ($highestTagProfile -in $moduleProfileArray) {
            # CONDITION: hightest sub tag is in module profile
            $returnShouldEvaluate = ($highestTagProfile -in $cloudUsageProfileArray)   
        }
        else{
            # CONDITION: hightest sub tag is not in module profile
            $returnShouldEvaluate = ($highestTagProfile -in $moduleProfileArray)
        }
        
        return [PSCustomObject]@{
            Profile =  $returnProfile
            ShouldEvaluate = $returnShouldEvaluate
            ShouldAvailable = $returnShouldAvailable
        }
    }
    catch {
        Write-Error "Error in Get-EvaluationProfile: $_"
        return [PSCustomObject]@{
            Profile = 0
            ShouldEvaluate = $false
            ShouldAvailable = $false
        }
    }
}

# Helper function to get the highest matching profile
function Get-HighestMatchingProfile {
    [OutputType([int])]
    param (
        [Parameter(Mandatory = $true)]
        [int[]]$profile1,
        [Parameter(Mandatory = $true)]
        [int[]]$profile2
    )
    $matchingProfiles = $profile1 | Where-Object { $profile2 -contains $_ }
    if ($matchingProfiles.Count -eq 0) {
        return 0
    }
    return ($matchingProfiles | Measure-Object -Maximum).Maximum
}

function ConvertTo-IntArray {
    [OutputType([int[]])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$inputString
    )
    # Remove any brackets and split on comma, then convert each element to int
    return $inputString.Trim('[]').Split(',') | ForEach-Object { [int]$_.Trim() }
}

function Parse-BlobContent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
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
# New improves version of Invoke-GraphQuery function that handles paging and retries
# This function is designed to be used with the Microsoft Graph API and will automatically handle pagination

function Invoke-GraphQueryEX {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^(?!https://graph.microsoft.com/(v1|beta)/)')]
        [string]
        $urlPath,
        [int]$MaxRetries = 3,
        [int]$RetryDelaySeconds = 5
    )

    [string]$baseUri = "https://graph.microsoft.com/v1.0"
    $fullUri = "$baseUri$urlPath" 
    $fullUri
    $allResults = @()
    $statusCode = $null
    $pageCount = 0
   # Write-Host $fullUri
    do {
        $retryCount = 0
        $success = $false
        $pageCount++
        Write-Progress -Activity "Invoke-GraphQueryEX" -Status "Retrieving page $pageCount..."
        
        do {
            try {
                $uri = $fullUri -as [uri]
                $uri 
                $response = Invoke-AZRestMethod  -Uri $uri  -Method GET -ErrorAction Stop 
                $data = $response.Content | ConvertFrom-Json
                $parsedcontent = $data.value
                $statusCode = $response.StatusCode
                $success = $true
            }
            catch {
                $retryCount++
                if ($retryCount -ge $MaxRetries) {
                    Write-Error "Failed to call Microsoft Graph REST API at URL '$fullUri' after $MaxRetries attempts; error: $($_.Exception.Message) at page $pageCount"
                    Write-Progress -Activity "Invoke-GraphQueryEX" -Status "Failed" -Completed
                    return @{
                        Content    = $null
                        StatusCode = $null
                        Error      = $_.Exception.Message
                    }
                } else {
                    Write-Warning "Transient error calling Graph API: $($_.Exception.Message). Retrying in $RetryDelaySeconds seconds... (Attempt $retryCount of $MaxRetries)"
                    Start-Sleep -Seconds $RetryDelaySeconds
                }
            }
        } while (-not $success -and $retryCount -lt $MaxRetries)

        if ($null -ne $data.value) {
            $allResults += $data.value
        } else {
            # For endpoints that don't return .value (single object)
            $allResults = $data
            break
        }
        # Handle paging
        if ($data.'@odata.nextLink') {
            $fullUri = $data.'@odata.nextLink'
        } else {
            $fullUri = $null
        }
    } while ($fullUri)
    
    Write-Progress -Activity "Invoke-GraphQueryEX" -Status "Completed" -Completed

    return @{
        Content    = @{ value = $allResults }
        StatusCode = $statusCode
    }
}
# end of Invoke-GraphQueryEX function
function Invoke-GraphQuery {
    [CmdletBinding()]
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
function add-documentFileExtensions {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]] $DocumentName,
        [Parameter(Mandatory = $true)]
        [string]$ItemName

    )

    if ($ItemName.ToLower() -eq 'network architecture diagram' -or 
        $ItemName.ToLower() -eq 'high level design documentation' -or
        $ItemName.ToLower() -eq "diagramme d'architecture réseau" -or 
        $ItemName.ToLower() -eq 'documentation de Conception de haut niveau'){

            $fileExtensions = @(".pdf", ".png", ".jpeg", ".vsdx",".txt",".docx", ".doc")
    }
    elseif ($ItemName.ToLower() -eq 'dedicated user accounts for administration' -or 
            $ItemName.ToLower() -eq "Comptes d'utilisateurs dédiés pour l'administration") {
                
            $fileExtensions = @(".csv")
    }
    elseif ($ItemName.ToLower() -eq 'application gateway certificate validity' -or 
            $ItemName.ToLower() -eq "validité du certificat : passerelle d'application") {
        
            $fileExtensions = @(".txt")
    }
    else {
        $fileExtensions = @(".txt",".docx", ".doc", ".pdf")
    }
    
    $DocumentName_new = New-Object System.Collections.Generic.List[System.Object]
    ForEach ($fileExt in $fileExtensions) {
        $DocumentName_new.Add($DocumentName[0] + $fileExt)
    }

    return $DocumentName_new
}

function Get-UserSignInPreferences {
    [CmdletBinding()]
    param (      
        [Parameter(Mandatory = $true)]
        [string]$UserUPN
    )
    
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    $signInPreferences = $null
    
    # Handle guest accounts (external users)
    $pattern = "*#EXT#*"
    if($UserUPN -like $pattern){
        # for guest accounts
        $userEmail = $UserUPN
        if(!$null -eq $userEmail){
            $encodedUserEmail = [System.Web.HttpUtility]::UrlEncode($userEmail)
            $urlPath = '/users/' + $encodedUserEmail + '/authentication/signInPreferences'            
        }else{
            Write-Warning "userEmail is null for $UserUPN"
            $extractedEmail = (($UserUPN -split '#')[0]) -replace '_', '@'
            $urlPath = '/users/' + $extractedEmail + '/authentication/signInPreferences'
        }
    }else{
        # for member accounts
        $urlPath = '/users/' + $UserUPN + '/authentication/signInPreferences'
    }
    
    try {
        # Use beta endpoint for signInPreferences
        $uri = "https://graph.microsoft.com/beta$urlPath" -as [uri]
        
        $response = Invoke-AzRestMethod -Uri $uri -Method GET -ErrorAction Stop
        
        if ($response.StatusCode -eq 200) {
            $signInPreferences = $response.Content | ConvertFrom-Json
            Write-Host "Successfully retrieved sign-in preferences for $UserUPN"
        } else {
            $errorMsg = "Failed to retrieve sign-in preferences for $UserUPN. Status code: $($response.StatusCode)"
            $ErrorList.Add($errorMsg)
            Write-Error $errorMsg
        }
    }
    catch {
        $errorMsg = "Failed to call Microsoft Graph Beta API at URL '$urlPath'; returned error message: $_"
        $ErrorList.Add($errorMsg)
        Write-Error "Error: $errorMsg"
    }
    
    $PsObject = [PSCustomObject]@{
        SignInPreferences = $signInPreferences
        ErrorList = $ErrorList
    }
    
    return $PsObject
}



function Get-AllUserAuthInformation {
    [CmdletBinding()]
    param (      
        [Parameter(Mandatory = $true)]
        [array]$allUserList
    )
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    $userValidMFACounter = 0
    $userUPNsValidMFA = @()
    $userUPNsBadMFA = @()
    $pattern = "*#EXT#*"

    ForEach ($user in $allUserList) {
        $userAccount = $user.userPrincipalName
        $authFound = $false

        # First, check if user has FIDO2 or HardwareOTP as system preferred authentication method
        try {
            $signInPrefsResult = Get-UserSignInPreferences -UserUPN $userAccount
            if ($signInPrefsResult.ErrorList.Count -eq 0 -and $null -ne $signInPrefsResult.SignInPreferences) {
                $preferences = $signInPrefsResult.SignInPreferences
                $isSystemPreferredEnabled = $preferences.isSystemPreferredAuthenticationMethodEnabled
                $systemPreferredMethod = $preferences.systemPreferredAuthenticationMethod
                
                # Check if system preferred is enabled and set to FIDO2 or HardwareOTP
                if ($isSystemPreferredEnabled -eq $true -and 
                    ($systemPreferredMethod -eq "Fido2" -or $systemPreferredMethod -eq "HardwareOTP")) {
                    $authFound = $true
                    Write-Host "✅ $userAccount - System preferred authentication method is $systemPreferredMethod"
                }
            }
        }
        catch {
            $errorMsg = "Failed to check sign-in preferences for $userAccount : $_"
            $ErrorList.Add($errorMsg)
            Write-Error "Warning: $errorMsg"
        }
        
        # If system preferred authentication is not FIDO2 or HardwareOTP, check authentication methods
        if (-not $authFound) {
            if($userAccount -like $pattern){
                # for guest accounts
                $userEmail = $user.mail
                if(!$null -eq  $userEmail){
                    $urlPath = '/users/' + $userEmail + '/authentication/methods'
                }else{
                    Write-Host "userEmail is null for $userAccount"
                    $extractedEmail = (($userAccount -split '#')[0]) -replace '_', '@'
                    $urlPath = '/users/' + $extractedEmail + '/authentication/methods'
                }
                
            }else{
                # for member accounts
                $urlPath = '/users/' + $userAccount + '/authentication/methods'
            }
            
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
            # # 7. #microsoft.graph.temporaryAccessPassAuthenticationMethod
            # # 8. #microsoft.graph.windowsHelloForBusinessAuthenticationMethod

            if ($null -ne $response) {
                # portal
                $data = $response.Content
                # # localExecution
                # $data = $response
                if ($null -ne $data -and $null -ne $data.value) {
                    $authenticationmethods = $data.value
                    
                    foreach ($authmeth in $authenticationmethods) {    
                    
                        switch ($authmeth.'@odata.type') {
                            "#microsoft.graph.phoneAuthenticationMethod" { $authFound = $true; break }
                            "#microsoft.graph.microsoftAuthenticatorAuthenticationMethod" { $authFound = $true; break }
                            "#microsoft.graph.fido2AuthenticationMethod" { $authFound = $true; break }
                            "#microsoft.graph.temporaryAccessPassAuthenticationMethod" { $authFound = $true; break }
                            "#microsoft.graph.windowsHelloForBusinessAuthenticationMethod" { $authFound = $true; break }
                            "#microsoft.graph.softwareOathAuthenticationMethod" { $authFound = $true; break }
                        }
                    }
                }
                else {
                    $errorMsg = "No authentication methods data found for $userAccount"                
                    $ErrorList.Add($errorMsg)
                    # Write-Error "Error: $errorMsg"
                }
            }
            else {
                $errorMsg = "Failed to get response from Graph API for $userAccount"                
                $ErrorList.Add($errorMsg)
                Write-Error "Error: $errorMsg"
            }
        }
        
        # Process the authentication result
        if($authFound){
            #need to keep track of user account mfa in a counter and compare it with the total user count   
            $userValidMFACounter += 1
            Write-Host "Auth method found for $userAccount"

            # Create an instance of valid MFA inner list object
            $userValidUPNtemplate = [PSCustomObject]@{
                UPN  = $userAccount
                MFAStatus   = $true
            }
            $userUPNsValidMFA +=  $userValidUPNtemplate
        }
        else{
            # This message is being used for debugging
            Write-Host "$userAccount does not have MFA enabled"

            # Create an instance of inner list object
            $userUPNtemplate = [PSCustomObject]@{
                UPN  = $userAccount
                MFAStatus   = $false
            }
            # Add the list to user accounts MFA list
            $userUPNsBadMFA += $userUPNtemplate

        }    
    }

    $PsObject = [PSCustomObject]@{
        userUPNsBadMFA = $userUPNsBadMFA
        ErrorList      = $ErrorList
        userValidMFACounter = $userValidMFACounter
        userUPNsValidMFA = $userUPNsValidMFA
    }

    return $PsObject

}
function Get-AllUserAuthInformationEX {
    <#
    .SYNOPSIS
    Optimized version of Get-AllUserAuthInformation using Microsoft Graph Batch API for improved performance.
    Compatible with PowerShell 5.1. Signature and output format are unchanged.

    .PARAMETER allUserList
    Array of user objects to check for MFA status.

    .OUTPUTS
    PSCustomObject with userUPNsBadMFA, ErrorList, userValidMFACounter, userUPNsValidMFA.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array]$allUserList
    )

    # Initialize output containers
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    $userValidMFACounter = 0
    $userUPNsValidMFA = @()
    $userUPNsBadMFA = @()
    $batchSize = 20
    $pattern = "*#EXT#*"

    # Process users in batches of 20 (Graph Batch API limit)
    for ($i = 0; $i -lt $allUserList.Count; $i += $batchSize) {
        $batchUsers = $allUserList[$i..([Math]::Min($i+$batchSize-1, $allUserList.Count-1))]
        $batchRequests = @()
        $userMap = @{}

        # Build batch request payload for each user in the batch
        $reqId = 1
        foreach ($user in $batchUsers) {
            $userAccount = $user.userPrincipalName
            if ($userAccount -like $pattern) {
                # Guest accounts
                $userEmail = $user.mail
                if ($null -ne $userEmail) {
                    $urlPath = "/users/$userEmail/authentication/methods"
                } else {
                    $extractedEmail = (($userAccount -split '#')[0]) -replace '_', '@'
                    $urlPath = "/users/$extractedEmail/authentication/methods"
                }
            } else {
                # Member accounts
                $urlPath = "/users/$userAccount/authentication/methods"
            }
            $batchRequests += @{
                id     = "$reqId"
                method = "GET"
                url    = $urlPath
            }
            $userMap["$reqId"] = $userAccount
            $reqId++
        }

        # Convert batch request to JSON
        $batchPayload = @{ requests = $batchRequests } | ConvertTo-Json -Depth 4

        # Send batch request to Graph API
        try {
            $response = Invoke-AzRestMethod -Uri "https://graph.microsoft.com/v1.0/\$batch" -Method POST -Body $batchPayload -ErrorAction Stop
            $batchResults = ($response.Content | ConvertFrom-Json).responses
        }
        catch {
            $ErrorList.Add("Batch request failed: $_")
            continue
        }

        # Process each response in the batch
        foreach ($result in $batchResults) {
            $userAccount = $userMap[$result.id]
            if ($result.status -eq 200 -and $null -ne $result.body.value) {
                $authFound = $false
                foreach ($authmeth in $result.body.value) {
                    switch ($authmeth.'@odata.type') {
                        "#microsoft.graph.phoneAuthenticationMethod" { $authFound = $true; break }
                        "#microsoft.graph.microsoftAuthenticatorAuthenticationMethod" { $authFound = $true; break }
                        "#microsoft.graph.fido2AuthenticationMethod" { $authFound = $true; break }
                        "#microsoft.graph.temporaryAccessPassAuthenticationMethod" { $authFound = $true; break }
                        "#microsoft.graph.windowsHelloForBusinessAuthenticationMethod" { $authFound = $true; break }
                        "#microsoft.graph.softwareOathAuthenticationMethod" { $authFound = $true; break }
                    }
                }
                if ($authFound) {
                    $userValidMFACounter += 1
                    $userValidUPNtemplate = [PSCustomObject]@{ UPN = $userAccount; MFAStatus = $true }
                    $userUPNsValidMFA += $userValidUPNtemplate
                } else {
                    $userUPNtemplate = [PSCustomObject]@{ UPN = $userAccount; MFAStatus = $false }
                    $userUPNsBadMFA += $userUPNtemplate
                }
            } else {
                $ErrorList.Add("No authentication methods data for $userAccount or error status: $($result.status)")
                $userUPNtemplate = [PSCustomObject]@{ UPN = $userAccount; MFAStatus = $false }
                $userUPNsBadMFA += $userUPNtemplate
            }
        }
    }

    # Return results in the same format as the original function
    $PsObject = [PSCustomObject]@{
        userUPNsBadMFA      = $userUPNsBadMFA
        ErrorList           = $ErrorList
        userValidMFACounter = $userValidMFACounter
        userUPNsValidMFA    = $userUPNsValidMFA
    }
}
function CompareKQLQueries{
    param (
        [string] $query,
        [string] $targetQuery
        )

    #Fix the formatting of KQL query
    $normalizedTargetQuery = $targetQuery -replace '\s+', ' ' -replace '\|', ' | ' 
    $removeSpacesQuery = $query -replace '\s', ''
    $removeSpacesTargetQuery = $normalizedTargetQuery -replace '\s', ''

    return $removeSpacesQuery -eq $removeSpacesTargetQuery
}

# Function used for V2.0 GR2V7(M) andV1.0  GR3(R) cloud console access
function Get-allowedLocationCAPCompliance {
    param (
        [array]$ErrorList,
        [string] $IsCompliant
    )

    # get named locations
    $locationsBaseAPIUrl = '/identity/conditionalAccess/namedLocations'
    try {
        $response = Invoke-GraphQuery -urlPath $locationsBaseAPIUrl -ErrorAction Stop
        $data = $response.Content
        $locations = $data.value
    }
    catch {
        $Errorlist.Add("Failed to call Microsoft Graph REST API at URL '$locationsBaseAPIUrl'; returned error message: $_") 
        Write-Warning "Error: Failed to call Microsoft Graph REST API at URL '$locationsBaseAPIUrl'; returned error message: $_"
    }

    # get conditional access policies
    $CABaseAPIUrl = '/identity/conditionalAccess/policies'
    try {
        $response = Invoke-GraphQuery -urlPath $CABaseAPIUrl -ErrorAction Stop

        $caps = $response.Content.value
    }
    catch {
        $Errorlist.Add("Failed to call Microsoft Graph REST API at URL '$CABaseAPIUrl'; returned error message: $_")
        Write-Warning "Error: Failed to call Microsoft Graph REST API at URL '$CABaseAPIUrl'; returned error message: $_"
    }
    
    # check that a named location for Canada exists and that a policy exists that uses it
    $validLocations = @()

    foreach ($location in $locations) {
        #Determine location conditions
        #get all valid locations: needs to have Canada Only
        if ($location.countriesAndRegions.Count -eq 1 -and $location.countriesAndRegions[0] -eq "CA") {
            $validLocations += $location
        }
    }

    $locationBasedPolicies = $caps | Where-Object { $_.conditions.locations.includeLocations -in $validLocations.ID -and $_.state -eq 'enabled' }

    if ($validLocations.count -ne 0) {
        #if there is at least one location with Canada only, we are good. If no Canada Only policy, not compliant.
        # Conditional access Policies
        # Need a location based policy, for admins (owners, contributors) that uses one of the valid locations above.
        # If there is no policy or the policy doesn't use one of the locations above, not compliant.

        if (!$locationBasedPolicies) {
            #failed. No policies have valid locations.
            $Comments = $msgTable.noCompliantPoliciesfound
            $IsCompliant = $false
        }
        else {
            #"Compliant Policies."
            $IsCompliant = $true
            $Comments = $msgTable.allPoliciesAreCompliant
        }      
    }
    else {
        # Failed. Reason: No locations have only Canada.
        $Comments = $msgTable.noLocationsCompliant
        $IsCompliant = $false
    }
    
    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        Comments         = $Comments
        ItemName         = $ItemName
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
        Errors           = $ErrorList
    }
    return  $PsObject

}


function Test-PolicyExemptionExists {
    param (
        [string] $ScopeId,
        [array]  $requiredPolicyExemptionIds
    )
    [PSCustomObject] $policyExemptionList = New-Object System.Collections.ArrayList     
    # $exemptionsIds = Get-AzPolicyExemption -Scope $ScopeId | Select-Object -ExpandProperty Properties| Select-Object PolicyDefinitionReferenceIds
    $exemptionsIds=(Get-AzPolicyExemption -Scope $ScopeId).Properties.PolicyDefinitionReferenceIds
    $isExempt =  $false

    if ($null -ne $exemptionsIds)
    {
        foreach ($exemptionId in $exemptionsIds)
        {
            if ($exemptionId -in $requiredPolicyExemptionIds){
                $isExempt = $true

                # if exempted, add to the list
                $result = [PSCustomObject] @{
                    isExempt = $isExempt 
                    exemptionId = $exemptionId
                }
                $policyExemptionList.add($result)
            }

        }
    }
    return $policyExemptionList
    
}

function Test-ComplianceForSubscription {
    param (
        [System.Object] $obj,
        [System.Object] $subscription,
        [string] $PolicyID,
        [array]  $requiredPolicyExemptionIds,
        [string] $objType
    )
    $strPattern = "/providers/microsoft.authorization/policysetdefinitions/(.*)"
    if ($PolicyID -match $strPattern){
        $PolicyID = $matches[1]
    }
    Write-Host "Get compliance details for Subscription : $($subscription.DisplayName)"
    $complianceDetails = Get-AzPolicyState | Where-Object{ $_.SubscriptionId -eq $($subscription.SubscriptionID) } | Where-Object{ $_.PolicySetDefinitionName -eq $PolicyID}  
    
    If ($null -eq $complianceDetails) {
        Write-Host "No compliance details found for Management Group : $($obj.DisplayName) and subscription: $($subscription.DisplayName)"
    }
    else{   
        $complianceDetails = $complianceDetails | Where-Object{$_.PolicyAssignmentScope -like "*$($obj.TenantId)*" }
        $requiredPolicyExemptionIds_smallCaps = @()
        foreach ($str in $requiredPolicyExemptionIds) {
            $requiredPolicyExemptionIds_smallCaps += $str.ToLower()
        }
        # Filter for required policies
        $complianceDetails = $complianceDetails | Where-Object{ $_.PolicyDefinitionReferenceId -in $requiredPolicyExemptionIds_smallCaps}
        if ($objType -eq "subscription"){
            Write-Host "$($complianceDetails.count) Compliance details found for subscription: $($subscription.DisplayName)"
        }
        else {
            Write-Host "$($complianceDetails.count) Compliance details found for Management Group : $($obj.DisplayName) and subscription: $($subscription.DisplayName)"                            
        }
        
    }

    return $complianceDetails
}


function Check-PBMMPolicies {
    param (
        [System.Object] $objList,
        [string] $objType, #subscription or management Group
        [array]  $requiredPolicyExemptionIds,
        [string] $PolicyID,
        [string] $ControlName,
        [string] $ItemName,
        [string] $LogType,
        [string] $itsgcode,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string] $ReportTime,
        [string] $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] $EnableMultiCloudProfiles # New feature flag, default to false    
    )   
    [PSCustomObject] $tempObjectList = New-Object System.Collections.ArrayList

    foreach ($obj in $objList)
    {
        Write-Verbose "Checking $objType : $($obj.Name)"
        Write-Verbose "PBMM policy PolicyID is $PolicyID"

        # Find scope
        if ($objType -eq "subscription"){
            $tempId="/subscriptions/$($obj.Id)"
        }
        else {
            $tempId=$obj.Id                              
        }
        Write-Host "Scope is $tempId"

        # Find assigned policy list from PBMM policy for the scope
        $AssignedPolicyList = Get-AzPolicyAssignment -scope $tempId | `
            Select-Object -ExpandProperty properties | `
            Where-Object { $_.PolicyDefinitionID -like "*$PolicyID*" } 

        If ($null -eq $AssignedPolicyList -or (-not ([string]::IsNullOrEmpty(($AssignedPolicyList.Properties.NotScopesScope)))))
        {
            # PBMM initiative not applied
            $ComplianceStatus=$false
            $Comment = $msgTable.isNotCompliant + ' ' + $msgTable.pbmmNotApplied 
        }
        else {
            # PBMM initiative applied
            $Comment = $msgTable.pbmmApplied

            # List the policies within the PBMM initiative (policy set definition)
            $policySetDefinition = Get-AzPolicySetDefinition | `
                Where-Object { $_.PolicySetDefinitionId -like "*$PolicyID*" } 

            $listPolicies = $policySetDefinition.Properties.policyDefinitions
            # Check all 3 policies are applied for this scope
            $appliedPolicies = $listPolicies.policyDefinitionReferenceId | Where-Object { $requiredPolicyExemptionIds -contains $_ }
            if($appliedPolicies.Count -ne  $requiredPolicyExemptionIds.Count){
                # some required policies are not applied
                $ComplianceStatus=$false
                $Comment = $msgTable.isNotCompliant + ' ' + $Comment + ' ' + $msgTable.reqPolicyNotApplied
            }
            else{
                # All 3 required policies are applied
                $Comment += ' ' + $msgTable.reqPolicyApplied

                # PBMM is applied and not excluded. Testing if specific policies haven't been exempted.
                $policyExemptionList = Test-PolicyExemptionExists -ScopeId $tempId -requiredPolicyExemptionIds $requiredPolicyExemptionIds

                $exemptList = $policyExemptionList.exemptionId
                # $nonExemptList = $policyExemptionList | Where-Object { $_.isExempt -eq $false }
                if ($ExemptList.Count -gt 0){   
                    
                    # join all exempt policies to a string
                    if(-not($null -eq $exemptList)){
                        $exemptListAllPolicies = $exemptList -join ", "
                    }
                    # boolean, exemption for GR, required policies exists.
                    $ComplianceStatus=$false
                    $Comment += ' '+ $msgTable.grExemptionFound -f $exemptListAllPolicies

                }
                else {
                     # Required Policy Definitions are not exempt. Find compliance details for the assigned PBMM policy
                    $Comment += ' ' + $msgTable.grExemptionNotFound

                    # Check the number of resources and compliance for the required policies in applied PBMM initiative
                    # ----------------#
                    # Subscription
                    # ----------------#
                    if ($objType -eq "subscription"){
                        Write-Host "Find compliance details for Subscription : $($obj.Name)"
                        $subscription = @()
                        $subscription += New-Object -TypeName psobject -Property ([ordered]@{'DisplayName'=$obj.Name;'SubscriptionID'=$obj.Id})
                        
                        $currentSubscription = Get-AzContext
                        if($currentSubscription.Subscription.Id -ne $subscription.SubscriptionId){
                            # Set Az context to the this subscription
                            Set-AzContext -SubscriptionId $subscription.SubscriptionID
                            Write-Host "AzContext set to $($subscription.DisplayName)"
                        }
    
                        $complianceDetailsSubscription = Test-ComplianceForSubscription -obj $obj -subscription $subscription -PolicyID $PolicyID -requiredPolicyExemptionIds $requiredPolicyExemptionIds -objType $objType

                        if ($null -eq $complianceDetailsSubscription) {
                            Write-Host "Compliance details for $($subscription.DisplayName) outputs as NULL"
                            $complianceDetailsList = $null
                        }
                        else{
                            if($complianceDetailsSubscription.Count -lt 2){
                                $complianceDetailsList = $complianceDetailsSubscription[0] | Select-Object `
                                    Timestamp, ResourceId, ResourceLocation, ResourceType, SubscriptionId, `
                                    ResourceGroup, PolicyDefinitionName, ManagementGroupIds, PolicyAssignmentScope, IsCompliant, `
                                    ComplianceState, PolicyDefinitionAction, PolicyDefinitionReferenceId, ResourceTags, ResourceName
                            }
                            else{
                                $complianceDetailsList = $complianceDetailsSubscription | Select-Object `
                                    Timestamp, ResourceId, ResourceLocation, ResourceType, SubscriptionId, `
                                    ResourceGroup, PolicyDefinitionName, ManagementGroupIds, PolicyAssignmentScope, IsCompliant, `
                                    ComplianceState, PolicyDefinitionAction, PolicyDefinitionReferenceId, ResourceTags, ResourceName
                            }
                            
                            if (-not ($complianceDetailsList -is [System.Array])) {
                                $complianceDetailsList = @($complianceDetailsList)
                            }
                        }

                    }

                    if ($null -eq $complianceDetailsList) {
                        # PBMM applied but complianceDetailsList is null i.e. no resources in this subcription to apply the required policies
                        Write-Host "Check for compliance details; outputs as NULL"
                        $resourceCompliant = 0 
                        $resourceNonCompliant = 0
                        $totalResource = 0
                        $countResourceCompliant = 0 
                        $countResourceNonCompliant = 0          
                    }
                    else{
                        # # check the compliant & non-compliant resources only for $requiredPolicyExemptionIds policies
                        $totalResource = $complianceDetailsList.Count

                        # #-------------# #
                        # # Compliant
                        # #-------------# #
                        # List compliant resource
                        if ( $complianceDetailsList.Count -eq 1){
                            $resourceCompliant = $complianceDetailsList[0] | Where-Object {$_.ComplianceState -eq "Compliant"}
                        }
                        else{
                            $resourceCompliant = $complianceDetailsList | Where-Object {$_.ComplianceState -eq "Compliant"}
                        }
                        if (-not ($resourceCompliant -is [System.Array])) {
                            $resourceCompliant = @($resourceCompliant)
                        }
                        if ($null -eq $resourceCompliant){
                            Write-Host "resourceCompliant is null"
                            $countResourceCompliant = 0
                        }
                        else{
                            Write-Host "resourceCompliant is not null"
                            $countResourceCompliant = $resourceCompliant.Count
                        }
                        
                        # #-------------##
                        # # Non-compliant
                        # #-------------##
                        # List non-compliant resources
                        $resourceNonCompliant = $complianceDetailsList | Where-Object {$_.ComplianceState -eq "NonCompliant"}
                        if (-not ($resourceNonCompliant -is [System.Array])) {
                            $resourceNonCompliant = @($resourceNonCompliant)
                        }
                        $countResourceNonCompliant = $resourceNonCompliant.Count
                    }
                    
                    # # ---------------------------------------------------------------------------------
                    # At this point PBMM initiative is applied. All 3 policies are applied. No exemption.
                    # # ---------------------------------------------------------------------------------

                    # Count Compliant & non-compliant resources and Total resources
                    if($totalResource -eq 0){
                        # complianceDetailsList is null i.e no resources to apply the required policies in this subscription
                        $ComplianceStatus=$true
                        $Comment = $msgTable.isCompliant + ' ' + $Comment + ' '+ $msgTable.noResource
                    }
                    elseif($totalResource -gt 0 -and ($countResourceCompliant -eq $totalResource)){
                        # All resources are compliant
                        $ComplianceStatus=$true
                        $Comment = $msgTable.isCompliant + ' ' + $Comment + ' '+ $msgTable.allCompliantResources
                    }
                    elseif($totalResource -gt 0 -and ($countResourceNonCompliant -eq $totalResource)){
                        # All resources are non-compliant
                        $ComplianceStatus=$false
                        $Comment = $msgTable.isNotCompliant + ' ' + $Comment + ' '+ $msgTable.allNonCompliantResources
                    }
                    elseif($totalResource -gt 0 -and $countResourceNonCompliant -gt 0 -and ($countResourceNonCompliant -lt $totalResource)){
                        # There are some resources that are non-compliant
                        $ComplianceStatus=$false
                        $Comment = $msgTable.isNotCompliant + ' ' + $Comment + ' '+ $msgTable.hasNonComplianceResource -f $countResourceNonCompliant, $totalResource
                    }
                    else{
                        Write-host "All use cases are addressed."
                        # Do nothing 
                    }                   
                }

            }
        }

        # Add to the Object List 
        if ($null -eq $obj.DisplayName){
            $DisplayName=$obj.Name
        }
        else {
            $DisplayName=$obj.DisplayName
        }

        $c = New-Object -TypeName PSCustomObject -Property @{ 
            Type = [string]$objType
            Id = [string]$obj.Id
            Name = [string]$obj.Name
            DisplayName = [string]$DisplayName
            ComplianceStatus = [boolean]$ComplianceStatus
            Comments = [string]$Comment
            ItemName = [string]$ItemName
            itsgcode = [string]$itsgcode
            ControlName = [string]$ControlName
            ReportTime = [string]$ReportTime
        }

        if ($EnableMultiCloudProfiles) {
            if ($objType -eq "subscription") {
                $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $obj.Id
            } else {
                $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
            }
            
            if (!$evalResult.ShouldEvaluate) {
                if(!$evalResult.ShouldAvailable ){
                    if ($evalResult.Profile -gt 0) {
                        $c.ComplianceStatus = "Not Applicable"
                        $c | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                        $c.Comments = "Not available - Profile $($evalResult.Profile) not applicable for this guardrail"
                    } else {
                        $ErrorList.Add("Error occurred while evaluating profile configuration availability")
                    }
                } else {
                    if ($evalResult.Profile -gt 0) {
                        $c.ComplianceStatus = "Not Applicable"
                        $c | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                        $c.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
                    } else {
                        $ErrorList.Add("Error occurred while evaluating profile configuration")
                    }
                }
            } else {
                
                $c | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
            }
        }        

        $tempObjectList.add($c)| Out-Null
    }
    return $tempObjectList
}


# Used in AlersMonitor and UserAccountGCEventLogging
function get-AADDiagnosticSettings {
    $apiUrl = "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01-preview"
    $response = Invoke-AzRestMethod -Uri $apiUrl -Method Get -ErrorAction Stop
    if ($response.StatusCode -eq 200) {
        return ($response.Content | ConvertFrom-Json).value
    }
    throw "Failed to retrieve diagnostic settings. Status code: $($response.StatusCode)"
}


# USE OF THIS FUNCITON: GR2 V10 and V3 automated role reviews
function Expand-ListColumns {
    param (
        [Parameter(Mandatory = $true)]
        [Array]$accessReviewList  # The input list of access review objects
    )

    $expandedList = @()

    # Iterate through each item in the $accessReviewList
    foreach ($reviewInfo in $accessReviewList) {
        # Determine the maximum number of elements in the lists you want to expand
        $maxCount = @(
            $reviewInfo.AccessReviewScopeList.Count,
            $reviewInfo.AccessReviewResourceScopeList.Count,
            $reviewInfo.AccessReviewReviewerList.Count
        ) | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

        # Expand the lists by iterating through each element
        for ($i = 0; $i -lt $maxCount; $i++) {
            $expandedReviewInfo = [PSCustomObject]@{
                AccessReviewName                            = $reviewInfo.AccessReviewName
                AccessReviewInstanceId                      = $reviewInfo.AccessReviewInstanceId
                DescriptionForAdmins                        = $reviewInfo.DescriptionForAdmins
                DescriptionForReviewers                     = $reviewInfo.DescriptionForReviewers
                AccessReviewCreatedBy                       = $reviewInfo.AccessReviewCreatedBy
                AccessReviewStartDate                       = $reviewInfo.AccessReviewStartDate
                AccessReviewEndDate                         = $reviewInfo.AccessReviewEndDate
                AccessReviewStatus                          = $reviewInfo.AccessReviewStatus
                AccesReviewRecurrenceType                   = $reviewInfo.AccesReviewRecurrenceType
                AccesReviewRecurrencePattern                = $reviewInfo.AccesReviewRecurrencePattern
                AccessReviewScope                           = if ($reviewInfo.AccessReviewScopeList.Count -eq 1) { $reviewInfo.AccessReviewScopeList} else { if ($reviewInfo.AccessReviewScopeList.Count -gt $i) { $reviewInfo.AccessReviewScopeList[$i] } else {$null}}
                AccessReviewReviewer                        = if ($reviewInfo.AccessReviewReviewerList.Count -eq 1) { $reviewInfo.AccessReviewReviewerList} else { if ($reviewInfo.AccessReviewReviewerList.Count -gt $i) { $reviewInfo.AccessReviewReviewerList[$i] } else { $null }}
                AccessReviewResourceScope                   = if ($reviewInfo.AccessReviewResourceScopeList.Count -eq 1) { $reviewInfo.AccessReviewResourceScopeList} else { if ($reviewInfo.AccessReviewResourceScopeList.Count -gt $i) { $reviewInfo.AccessReviewResourceScopeList[$i] } else { $null }}
            }

            # Add the expanded row to the new list
            $expandedList += $expandedReviewInfo
        }
    }

    # Return the expanded list
    return $expandedList
}

function Add-ProfileInformation {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Result,
        [string]$CloudUsageProfiles,
        [string]$ModuleProfiles,
        [string]$SubscriptionId,
        [AllowEmptyCollection()]
        [System.Collections.ArrayList]$ErrorList
    )
    
    if($null -eq $SubscriptionId){
        $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
    }else{
        $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $SubscriptionID
    }

    if (!$evalResult.ShouldEvaluate) {
        if(!$evalResult.ShouldAvailable ){
            if ($evalResult.Profile -gt 0) {
                $Result.ComplianceStatus = "Not Applicable"
                $Result | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                $Result.Comments = "Not available - Profile $($evalResult.Profile) not applicable for this guardrail"
            } else {
                $ErrorList.Add("Error occurred while evaluating profile configuration availability")
            }
        } else {
            if ($evalResult.Profile -gt 0) {
                $Result.ComplianceStatus = "Not Applicable"
                $Result | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                $Result.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
            } else {
                $ErrorList.Add("Error occurred while evaluating profile configuration")
            }
        }
    } else {
        $Result | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
    }
    return $Result
}

function Check-BuiltInPoliciesPerSubscription {
    param (
        [Parameter(Mandatory = $true)]
        [array]$requiredPolicyIds,
        [Parameter(Mandatory = $true)]
        [string]$ReportTime,
        [Parameter(Mandatory = $true)]
        [string]$ItemName,
        [Parameter(Mandatory = $true)]
        [hashtable]$msgTable,
        [Parameter(Mandatory = $true)]
        [string]$ControlName,
        [string]$itsgcode,
        [string]$CloudUsageProfiles = "3",
        [string]$ModuleProfiles,
        [switch]$EnableMultiCloudProfiles,
        [System.Collections.ArrayList]$ErrorList
    )


    $subscriptions = Get-AzSubscription
    $results = New-Object System.Collections.ArrayList

    foreach ($subscription in $subscriptions) {
        try {
            Set-AzContext -SubscriptionId $subscription.Id -ErrorAction Stop
            $scope = "/subscriptions/$($subscription.Id)"
            Write-Host "Checking policies for subscription: $($subscription.Name) [$($subscription.Id)]"
        } catch {
            $ErrorList.Add("Error setting context for subscription $($subscription.Id): $_")
            continue
        }
        $result = Check-BuiltInPolicies -requiredPolicyIds $requiredPolicyIds -ReportTime $ReportTime -ItemName $ItemName -msgTable $msgTable -ControlName $ControlName -subScope $scope -subscription $subscription -itsgcode $itsgcode -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -EnableMultiCloudProfiles -ErrorList $ErrorList
        $results.Add($result)
    }
    Write-Host "Completed policy compliance check. Found $($results.Count) results"
    return $results
}


function Check-BuiltInPolicies {
    param (
        [Parameter(Mandatory=$true)]
        [array]$requiredPolicyIds,
        [Parameter(Mandatory=$true)]
        [string]$ReportTime,
        [Parameter(Mandatory=$true)]
        [string]$ItemName,
        [Parameter(Mandatory=$true)]
        [hashtable]$msgTable,
        [Parameter(Mandatory=$true)]
        [string]$ControlName,
        [string]$subScope, #optional param to check a specific subscription
        $subscription,
        [string]$itsgcode,
        [string]$CloudUsageProfiles = "3",
        [string]$ModuleProfiles,
                             [switch]$EnableMultiCloudProfiles,
        [System.Collections.ArrayList]$ErrorList
    )
    
    $results = New-Object System.Collections.ArrayList
    
    if($subScope){$rootScope = $subScope}
    else{
        # Get tenant root management group
        try {
            $tenantId = (Get-AzContext).Tenant.Id
            $rootScope = "/providers/Microsoft.Management/managementGroups/$tenantId"
        } catch {
            $ErrorList.Add("Error getting tenant context: $_")
            return $results
        }
    }

    Write-Host "Starting policy compliance check for tenant: $tenantId"
    
    foreach ($policyId in $requiredPolicyIds) {
        Write-Host "Checking policy assignment for policy ID: $policyId"
        
        # Get policy definition details
        try {
            $policyDefinition = Get-AzPolicyDefinition -Id $policyId -ErrorAction Stop
            $policyDisplayName = $policyDefinition.Properties.DisplayName
        } catch {
            $ErrorList.Add("Error getting policy definition: $_")
            $policyDisplayName = "Unknown Policy"
            return $results
        }
        
        # Check for policy assignments at tenant level
        try {
            $assignments = Get-AzPolicyAssignment -Scope $rootScope -PolicyDefinitionId $policyId -ErrorAction Stop
            $tenantPolicyAssignments = @()
            if ($assignments -is [array]) {
                $tenantPolicyAssignments = $assignments | Where-Object { $null -ne $_ }
            } else {
                if ($null -ne $assignments) {
                    $tenantPolicyAssignments += $assignments
                }
            }            
        } catch {
            $ErrorList.Add("Error getting policy assignments for policy $policyId : $_")
            $tenantPolicyAssignments = @()
        }
        
        # Check if we have any policy assignments (not null and not empty)
        if ($null -ne $tenantPolicyAssignments -and $tenantPolicyAssignments.Count -gt 0) {
            Write-Host "Found $($tenantPolicyAssignments.Count) assignments matching this policy ID"
            
            $hasExemptions = $false
            
            # Check for policy exemptions
            foreach ($assignment in $tenantPolicyAssignments) {
                try {
                    if ($null -ne $assignment -and $null -ne $assignment.PolicyAssignmentId ) {
                        Write-Host "Checking exemptions for assignment: $($assignment.PolicyAssignmentId)"
                        $policyExemptions = Get-AzPolicyExemption -Scope $rootScope -PolicyAssignmentId $assignment.PolicyAssignmentId  -ErrorAction Stop
                        if ($policyExemptions) {
                            $hasExemptions = $true
                            break
                        }
                    } else {
                        Write-Host "Skipping exemption check for invalid assignment"
                        continue
                    }
                } catch {
                    $ErrorList.Add("Error checking policy exemptions: $_")
                }
                continue
            }
            
            if ($hasExemptions) {
                if($subScope){
                    $result = [PSCustomObject]@{
                        Type = "subscription"
                        Id = $subscription.Id
                        SubscriptionName = $subscription.Name
                        DisplayName = $subscription.Name
                        ComplianceStatus = $false
                        Comments = $msgTable.policyHasExemptions
                        ItemName = "$ItemName - $policyDisplayName"
                        ControlName = $ControlName
                        ReportTime = $ReportTime
                        itsgcode = $itsgcode
                    }
                }
                else{
                    $result = [PSCustomObject]@{
                        Type = "tenant"
                        Id = $tenantId
                        Name = "Tenant ($tenantId)"
                        DisplayName = "Tenant ($tenantId)"
                        ComplianceStatus = $false
                        Comments = $msgTable.policyHasExemptions
                        ItemName = "$ItemName - $policyDisplayName"
                        ControlName = $ControlName
                        ReportTime = $ReportTime
                        itsgcode = $itsgcode
                    }
                }
                if ($EnableMultiCloudProfiles) {
                    $result = Add-ProfileInformation -Result $result -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -ErrorList $ErrorList
                }
                $results.Add($result) | Out-Null
                continue
            }

            Write-Host "Policy is assigned at tenant level. Checking compliance states..."
            
            # Get all policy states for this policy
            $policyStates = Get-AzPolicyState | Where-Object { $_.PolicyDefinitionId -eq $policyId }

            # If no resources are found that the policy applies to
            if ($null -eq $policyStates -or $policyStates.Count -eq 0) {

                if($subScope){
                    $result = [PSCustomObject]@{
                        Type = "subscription"
                        Id = $subscription.Id
                        SubscriptionName = $subscription.Name
                        DisplayName = $subscription.Name
                        ComplianceStatus = $true
                        Comments = $msgTable.policyNoApplicableResourcesSub
                        ItemName = "$ItemName - $policyDisplayName"
                        ControlName = $ControlName
                        ReportTime = $ReportTime
                        itsgcode = $itsgcode
                    }
                }
                else{
                    $result = [PSCustomObject]@{
                        Type = "tenant"
                        Id = $tenantId
                        Name = "Tenant ($tenantId)"
                        DisplayName = "Tenant ($tenantId)"
                        ComplianceStatus = $true
                        Comments = $msgTable.policyNoApplicableResources
                        ItemName = "$ItemName - $policyDisplayName"
                        ControlName = $ControlName
                        ReportTime = $ReportTime
                        itsgcode = $itsgcode
                    }
                }
                if ($EnableMultiCloudProfiles) {
                    $result = Add-ProfileInformation -Result $result -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -ErrorList $ErrorList
                }
                
                $results.Add($result) | Out-Null
                continue
            }

            # Check if any resources are non-compliant
            $nonCompliantResources = $policyStates | 
                Where-Object { $_.ComplianceState -eq "NonCompliant" -or $_.IsCompliant -eq $false }
            
            if ($nonCompliantResources) {
                Write-Host "Found $($nonCompliantResources.Count) non-compliant resources"
                foreach ($resource in $nonCompliantResources) {
                    $result = [PSCustomObject]@{
                        Type = $resource.ResourceType
                        Id = $resource.ResourceId
                        Name = $resource.ResourceGroup + "/" + ($resource.ResourceId -split '/')[-1]
                        DisplayName = $resource.ResourceGroup + "/" + ($resource.ResourceId -split '/')[-1]
                        ComplianceStatus = $false
                        Comments = $msgTable.policyNotCompliant
                        ItemName = "$ItemName - $policyDisplayName"
                        ControlName = $ControlName
                        ReportTime = $ReportTime
                        itsgcode = $itsgcode
                    }
                    
                    if ($EnableMultiCloudProfiles) {
                        $result = Add-ProfileInformation -Result $result -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -ErrorList $ErrorList
                    }
                    
                    $results.Add($result) | Out-Null
                }
            } else {
                Write-Host "All resources are compliant with the policy"

                if($subScope){
                    $result = [PSCustomObject]@{
                        Type = "subscription"
                        Id = $subscription.Id
                        Name = "All Resources"
                        DisplayName = $subscription.Name
                        ComplianceStatus = $true
                        Comments = $msgTable.policyCompliant
                        ItemName = "$ItemName - $policyDisplayName"
                        ControlName = $ControlName
                        ReportTime = $ReportTime
                        itsgcode = $itsgcode
                    }
                }
                else{
                    $result = [PSCustomObject]@{
                        Type = "tenant"
                        Id = $tenantId
                        Name = "All Resources"
                        DisplayName = "All Resources"
                        ComplianceStatus = $true
                        Comments = $msgTable.policyCompliant
                        ItemName = "$ItemName - $policyDisplayName"
                        ControlName = $ControlName
                        ReportTime = $ReportTime
                        itsgcode = $itsgcode
                    }
                }
                if ($EnableMultiCloudProfiles) {
                    $result = Add-ProfileInformation -Result $result -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -ErrorList $ErrorList
                }
                $results.Add($result) | Out-Null
            }
        } else {
            
            if($subScope){
                $result = [PSCustomObject]@{
                    Type = "subscription"
                    Id = $subscription.Id
                    SubscriptionName = $subscription.Name
                    DisplayName = $subscription.Name
                    ComplianceStatus = $false
                    Comments = $msgTable.policyNotConfiguredSub -f $subScope
                    ItemName = "$ItemName - $policyDisplayName"
                    ControlName = $ControlName
                    ReportTime = $ReportTime
                    itsgcode = $itsgcode
                }
            }
            else{
                $result = [PSCustomObject]@{
                    Type = "tenant"
                    Id = $tenantId
                    Name = "Tenant ($tenantId)"
                    DisplayName = "Tenant ($tenantId)"
                    ComplianceStatus = $false
                    Comments = $msgTable.policyNotConfigured
                    ItemName = "$ItemName - $policyDisplayName"
                    ControlName = $ControlName
                    ReportTime = $ReportTime
                    itsgcode = $itsgcode
                }
            }
            if ($EnableMultiCloudProfiles) {
                $result = Add-ProfileInformation -Result $result -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -ErrorList $ErrorList
            }
            $results.Add($result) | Out-Null
        }
    }

    Write-Host "Completed policy compliance check. Found $($results.Count) results"
    return $results
}

function FetchAllUserRawData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string] $ReportTime,
        [Parameter(Mandatory=$true)]
        [string] $FirstBreakGlassUPN,
        [Parameter(Mandatory=$true)]
        [string] $SecondBreakGlassUPN,
        [Parameter(Mandatory=$true)]
        [string] $WorkSpaceID,
        [Parameter(Mandatory=$true)]
        [string] $WorkspaceKey
    )
    $ErrorList = [System.Collections.Generic.List[string]]::new()
    $usersPath = "/users?`$select=displayName,id,userPrincipalName,mail,createdDateTime,userType,accountEnabled,signInActivity"


    try {
        $response = Invoke-GraphQueryEX -urlPath $usersPath -ErrorAction Stop
        if ($response -is [System.Array]) {
            $response = $response | Where-Object { $_.Content -ne $null -or $_.StatusCode -ne $null } | Select-Object -Last 1
        }
        $allUsers = @($response.Content.value)
        $bgUpns = @($FirstBreakGlassUPN, $SecondBreakGlassUPN) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        if ($bgUpns.Count -gt 0) {
            $allUsers = @($allUsers | Where-Object {
                $upn = $_.userPrincipalName
                -not [string]::IsNullOrWhiteSpace($upn) -and ($bgUpns -notcontains $upn)
            })
        }
    } catch {
        Write-Warning "Failed to call Microsoft Graph REST API at URL '$usersPath'; error: $_"
        $ErrorList += "Graph call failed for users list: $_"
        $allUsers = @()
    }
    $regPath = "/reports/authenticationMethods/userRegistrationDetails"
    $registrationDetails = @()
    try {
        $regResp = Invoke-GraphQueryEX -urlPath $regPath -ErrorAction Stop
        if ($regResp -is [System.Array]) {
            $regResp = $regResp | Where-Object { $_.Content -ne $null -or $_.StatusCode -ne $null } | Select-Object -Last 1
        }
        $registrationDetails = @($regResp.Content.value)
    } catch {
        Write-Warning "Failed to call Microsoft Graph REST API at URL '$regPath'; error: $_"
        $ErrorList += "Graph call failed for registration details: $_"
        $registrationDetails = @()
    }
    $regById = @{
    }
    foreach ($r in $registrationDetails) {
        if ($null -ne $r.id -and -not $regById.ContainsKey($r.id)) { $regById[$r.id] = $r }
    }
    $augmentedUsers = New-Object 'System.Collections.Generic.List[PSObject]'
    foreach ($u in $allUsers) {
        $r = $null
        if ($null -ne $u.id -and $regById.ContainsKey($u.id)) { $r = $regById[$u.id] }
        $methods = @()
        if ($null -ne $r -and $null -ne $r.methodsRegistered) { $methods = @($r.methodsRegistered) }
        $userObject = [PSCustomObject]@{
            id                = $u.id
            userPrincipalName = $u.userPrincipalName
            displayName       = $u.displayName
            mail              = $u.mail
            createdDateTime   = $u.createdDateTime
            userType          = $u.userType
            accountEnabled    = $u.accountEnabled
            signInActivity    = $u.signInActivity
            isMfaRegistered       = $r.isMfaRegistered
            isMfaCapable          = $r.isMfaCapable
            isSsprEnabled         = $r.isSsprEnabled
            isSsprRegistered      = $r.isSsprRegistered
            isSsprCapable         = $r.isSsprCapable
            isPasswordlessCapable = $r.isPasswordlessCapable
            defaultMethod         = $r.defaultMethod
            methodsRegistered     = $methods
            isSystemPreferredAuthenticationMethodEnabled = $r.isSystemPreferredAuthenticationMethodEnabled
            systemPreferredAuthenticationMethods = $r.systemPreferredAuthenticationMethods
            userPreferredMethodForSecondaryAuthentication = $r.userPreferredMethodForSecondaryAuthentication
            ReportTime        = $ReportTime
        }
        $augmentedUsers.Add($userObject) | Out-Null
    }
    # Send data once before loop
    try {
        Write-Verbose "Sending $($augmentedUsers.Count) user records to GuardrailsUserRaw_CL table"
        New-LogAnalyticsData -Data $augmentedUsers -WorkSpaceID $WorkSpaceID -WorkSpaceKey $WorkspaceKey -LogType "GuardrailsUserRaw" | Out-Null
        Write-Verbose "Successfully sent raw data to Log Analytics"
    } catch {
        Write-Error "Failed to send raw data to Log Analytics: $_"
        $ErrorList.Add("Failed to send raw data to GuardrailsUserRaw_CL: $_")
    }
    # Retry loop only queries for records
    $maxRetries = 10
    $retryDelay = 30
    $attempt = 0
    $recordCount = 0
    do {
        $query = "GuardrailsUserRaw_CL | where ReportTime_s == '$ReportTime' | count"
        try {
            $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkSpaceID -Query $query -ErrorAction Stop
            $recordCount = 0
            if ($result.Results.Count -gt 0 -and $result.Results[0].Count) {
                $recordCount = [int]$result.Results[0].Count
            }
            if ($recordCount -gt 0) {
                break
            } else {
                Write-Warning "No records found for ReportTime $ReportTime in GuardrailsUserRaw_CL. Retrying..."
                Start-Sleep -Seconds $retryDelay
            }
        } catch {
            Write-Error "Failed to query Log Analytics for GuardrailsUserRaw_CL: $_"
            $ErrorList.Add("Failed to query Log Analytics for GuardrailsUserRaw_CL: $_")
            Start-Sleep -Seconds $retryDelay
        }
        $attempt++
    } while ($attempt -lt $maxRetries)
    if ($attempt -ge $maxRetries) {
        $ErrorList.Add("No records found in GuardrailsUserRaw_CL for ReportTime $ReportTime after $maxRetries attempts.")
    }
    # Compare ingested record count to augmentedUsers.Count
    if ($recordCount -ne $augmentedUsers.Count) {
        $ErrorList.Add("Mismatch in ingested user records: expected $($augmentedUsers.Count), found $recordCount in GuardrailsUserRaw_CL for ReportTime $ReportTime.")
    }
    return $ErrorList
}

