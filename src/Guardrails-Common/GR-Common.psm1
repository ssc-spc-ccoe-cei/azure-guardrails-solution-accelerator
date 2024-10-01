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
        foreach ($tkey in $tKeys) {
            [void]$tagstring.Append("$tkey=$($tValues[$index]);")
            $index++
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
        $commentsArray += $msgTable.procedureFileNotFound -f $ItemName, $ContainerName, $StorageAccountName
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
        $result = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $SubscriptionID
        if ($result -gt 0) {
            Write-Output "Valid profile returned: $result"
            $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $result
        } else {
            Write-Output "No matching profile found or error occurred"
            $PsObject.ComplianceStatus = "Not Applicable"
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
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $CloudUsageProfiles,
        [Parameter(Mandatory = $true)]
        [string] $ModuleProfiles,
        [Parameter(Mandatory = $false)]
        [string] $SubscriptionId
    )

    try {
        # Convert input strings to integer arrays  
        $cloudUsageProfileArray = ConvertTo-IntArray $CloudUsageProfiles
        $moduleProfileArray = ConvertTo-IntArray $ModuleProfiles

        if (-not $SubscriptionId) {
            return [int](Get-HighestMatchingProfile $cloudUsageProfileArray $moduleProfileArray)
        }

        $subscriptionTags = Get-AzTag -ResourceId "subscriptions/$SubscriptionId" -ErrorAction Stop
        $profileTag = $subscriptionTags.Properties | Where-Object { $_.TagName -eq 'profile' }

        if ($null -eq $profileTag) {
            return [int](Get-HighestMatchingProfile $cloudUsageProfileArray $moduleProfileArray)
        }

        $profileTagValues = ConvertTo-IntArray $profileTag.TagValue

        $matchingProfiles = $profileTagValues | Where-Object {
            $cloudUsageProfileArray -contains $_ -and $moduleProfileArray -contains $_
        }

        if ($matchingProfiles.Count -gt 0) {
            return [int]($matchingProfiles | Measure-Object -Maximum).Maximum
        }

        Write-Error "No matching profiles found between profile tag, CloudUsageProfiles, and ModuleProfiles."
        return 0
    }
    catch {
        Write-Error "Error in Get-EvaluationProfile: $_"
        return 0
    }
}

function ConvertTo-IntArray {
    [OutputType([int[]])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$inputString
    )
    if ($inputString -match '^\[.*\]$') {
        return $inputString.Trim('[]').Split(',') | ForEach-Object { [int]$_.Trim() }
    }
    if ($inputString -match ',') {
        return $inputString.Split(',') | ForEach-Object { [int]$_.Trim() }
    }
    return @([int]$inputString)
}

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
    # $globalAdminUPNs = @()
    $userUPNs = @()

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
        # $globalAdminUPNs += $trimmedLine
        $userUPNs += $trimmedLine
    }

    $result = New-Object PSObject -Property @{
        # GlobalAdminUPNs = $globalAdminUPNs
        UserUPNs = $userUPNs
    }

    return $result
}

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

    if ($ItemName.ToLower() -eq 'network architecture diagram'){
        $fileExtensions = @(".pdf", ".png", ".jpeg", ".vsdx")
    }
    elseif ($ItemName.ToLower() -eq 'dedicated user accounts for administration') {
        $fileExtensions = @(".csv")
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



function Get-AllUserAuthInformation{
    [CmdletBinding()]
    param (      
        [Parameter(Mandatory = $true)]
        [array]$allUserList
    )
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    $userValidMFACounter = 0
    $userUPNsValidMFA = @()
    $userUPNsBadMFA = @()

    ForEach ($user in $allUserList) {
        $userAccount = $user.userPrincipalName
            
        if($userAccount -like "*#EXT#*"){
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
                
                $authFound = $false
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
            else {
                $errorMsg = "No authentication methods data found for $userAccount"                
                $ErrorList.Add($errorMsg)
                # Write-Error "Error: $errorMsg"
                
                # Create an instance of inner list object
                $userUPNtemplate = [PSCustomObject]@{
                    UPN  = $userAccount
                    MFAStatus   = $false
                }
                # Add the list to user accounts MFA list
                $userUPNsBadMFA += $userUPNtemplate
            }
        }
        else {
            $errorMsg = "Failed to get response from Graph API for $userAccount"                
            $ErrorList.Add($errorMsg)
            Write-Error "Error: $errorMsg"
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


# endregion


