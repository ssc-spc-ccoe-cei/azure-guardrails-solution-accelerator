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

# Returns true when the GCCloudGuardrails custom security attribute marks the user as excluded from MFA.
function Test-GuardrailsMfaExclusion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [psobject] $User,
        [string] $AttributeNamespace = 'GCCloudGuardrails',
        [string] $AttributeName = 'ExcludeFromMFA'
    )

    if ($null -eq $User) { return $false }

    $customAttributes = $User.customSecurityAttributes
    if ($null -eq $customAttributes) { return $false }

    $namespaceProperty = $customAttributes.PSObject.Properties[$AttributeNamespace]
    if ($null -eq $namespaceProperty) { return $false }

    $namespaceValue = $namespaceProperty.Value
    if ($null -eq $namespaceValue) { return $false }

    $attributeProperty = $namespaceValue.PSObject.Properties[$AttributeName]
    if ($null -eq $attributeProperty) { return $false }

    return ($attributeProperty.Value -eq $true)
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
        $errorMessage = "Failed to upload blob '$($FilePath | Split-Path -Leaf)' to storage account '$storageaccountName' container '$containerName'. Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        throw $errorMessage
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

function Get-GuardrailIdentityPermissions {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantRootManagementGroupId
    )

    if ([string]::IsNullOrWhiteSpace($TenantRootManagementGroupId)) {
        throw "TenantRootManagementGroupId is required."
    }

    $context = Get-AzContext
    if (-not $context -or -not $context.Account -or [string]::IsNullOrWhiteSpace($context.Account.Id)) {
        throw "Azure context is not initialized; unable to resolve automation account identity."
    }

    $principal = $null
    $principalLookupErrors = [System.Collections.Generic.List[string]]::new()

    $automationAccountObjectId = $env:AUTOMATION_ACCOUNT_ID
    if (-not [string]::IsNullOrWhiteSpace($automationAccountObjectId)) {
        $objectGuid = [Guid]::Empty
        if ([Guid]::TryParse($automationAccountObjectId, [ref]$objectGuid)) {
            try {
                $principal = Get-AzADServicePrincipal -ObjectId $objectGuid -ErrorAction Stop
            }
            catch {
                $principalLookupErrors.Add("AUTOMATION_ACCOUNT_ID lookup failed: $($_.Exception.Message)") | Out-Null
            }
        }
        else {
            $principalLookupErrors.Add("AUTOMATION_ACCOUNT_ID value '$automationAccountObjectId' is not a GUID.") | Out-Null
        }
    }
    else {
        $principalLookupErrors.Add('AUTOMATION_ACCOUNT_ID environment variable not set.') | Out-Null
    }

    if (-not $principal) {
        $applicationGuid = [Guid]::Empty
        if ([Guid]::TryParse($context.Account.Id, [ref]$applicationGuid)) {
            try {
                $principal = Get-AzADServicePrincipal -ApplicationId $applicationGuid -ErrorAction Stop
            }
            catch {
                $principalLookupErrors.Add("ApplicationId lookup failed: $($_.Exception.Message)") | Out-Null
            }
        }
        else {
            $principalLookupErrors.Add("Context.Account.Id '$($context.Account.Id)' is not a GUID.") | Out-Null
        }
    }

    if (-not $principal) {
        $details = if ($principalLookupErrors.Count -gt 0) { ' Details: ' + ($principalLookupErrors -join ' | ') } else { '' }
        throw "Failed to resolve automation account service principal.$details"
    }

    $principalDisplayName = $principal.DisplayName
    if ([string]::IsNullOrWhiteSpace($principalDisplayName)) {
        $principalDisplayName = $principal.AppId
    }

    $assignments = [System.Collections.Generic.List[psobject]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()

    try {
        $rbacAssignments = Get-AzRoleAssignment -ObjectId $principal.Id -ExpandPrincipalGroups:$false -ErrorAction Stop
    }
    catch {
        $errors.Add("RBAC enumeration failed: $($_.Exception.Message)") | Out-Null
        $rbacAssignments = @()
    }

    foreach ($assignment in $rbacAssignments) {
        $assignments.Add([pscustomobject]@{
                PrincipalType        = 'AutomationAccountMSI'
                PermissionType       = 'RBAC'
                PrincipalName        = $principalDisplayName
                PrincipalId          = $principal.Id
                Role                 = $assignment.RoleDefinitionName
                RoleDefinitionId     = $assignment.RoleDefinitionId
                Scope                = $assignment.Scope
                # Some Az versions expose the GUID as RoleAssignmentId instead of Id (PS5.1 compatible)
                AssignmentId         = if ($assignment.RoleAssignmentId) { $assignment.RoleAssignmentId } else { $assignment.Id }
                TenantRootManagementGroupId        = $TenantRootManagementGroupId
                TenantRootManagementGroupResourceId = "/providers/Microsoft.Management/managementGroups/$TenantRootManagementGroupId"
            }) | Out-Null
    }

    # AAD app-role assignments (GUIDs only)
    $resourceAppRoleAssignments = @()
    $graphPath = "/servicePrincipals/$($principal.Id)/appRoleAssignments?`$select=appRoleId,createdDateTime,principalDisplayName,principalId,resourceDisplayName,resourceId"
    $graphResponse = $null
    try {
        $graphResponse = Invoke-GraphQueryEX -urlPath $graphPath -ErrorAction Stop
    }
    catch {
        $errors.Add("AAD app-role enumeration failed: $($_.Exception.Message)") | Out-Null
    }

    if ($graphResponse -and $graphResponse.Content -and $graphResponse.Content.value) {
        $resourceAppRoleAssignments = $graphResponse.Content.value
    }
    elseif ($null -eq $graphResponse) {
        # distinguish API failure from truly empty assignments
        $errors.Add('AAD app-role enumeration did not return a response.') | Out-Null
    }

    # cache appRoles per resourceId to keep calls to 1 per resource
    $appRoleMetadataCache = @{}
    $uniqueResourceIds = @($resourceAppRoleAssignments | Select-Object -ExpandProperty resourceId -Unique | Where-Object { $_ })

    foreach ($resourceId in $uniqueResourceIds) {
        if ($appRoleMetadataCache.ContainsKey($resourceId)) { continue }

        # Use direct Graph call (not Invoke-GraphQueryEX) so appRoles aren't hidden under Content.value and AppRoleValue stays populated.
        $resourceUri = "https://graph.microsoft.com/v1.0/servicePrincipals/$resourceId"
        try {
            # Use a Graph-scoped token and Invoke-RestMethod (PS 5.1 friendly)
            $graphToken = Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com" -ErrorAction Stop
            $authHeader = @{ 'Authorization' = "Bearer $($graphToken.Token)"; 'Content-Type' = 'application/json' }

            $appRoles = $null

            $resourcePayload = Invoke-RestMethod -Method Get -Uri $resourceUri -Headers $authHeader -ErrorAction Stop
            $appRoles = if ($resourcePayload.appRoles) { $resourcePayload.appRoles }
                       elseif ($resourcePayload.value) {
                           $valueObj = $resourcePayload.value
                           if ($valueObj -is [System.Array] -and $valueObj.Count -gt 0 -and $valueObj[0].appRoles) { $valueObj[0].appRoles }
                           elseif ($valueObj.appRoles) { $valueObj.appRoles }
                       }

            if ($null -eq $appRoles) {
                $errors.Add("AAD app-role metadata lookup for resource $($resourceId): appRoles property not found or empty.") | Out-Null
            }

            $appRoleMetadataCache[$resourceId] = $appRoles
        }
        catch {
            $statusCode = if ($_.Exception.Response -and $_.Exception.Response.StatusCode) { [int]$_.Exception.Response.StatusCode.value__ } else { 500 }
            $errors.Add("AAD app-role metadata lookup for resource $($resourceId) returned status $statusCode : $($_.Exception.Message)") | Out-Null
            $appRoleMetadataCache[$resourceId] = $null
            continue
        }
    }

    foreach ($assignment in $resourceAppRoleAssignments) {
        $appRoleValue = $null

        if ($assignment.resourceId -and $assignment.appRoleId -and $appRoleMetadataCache.ContainsKey($assignment.resourceId) -and $appRoleMetadataCache[$assignment.resourceId]) {
            $matchingRole = $appRoleMetadataCache[$assignment.resourceId] | Where-Object { [string]$_.id -eq [string]$assignment.appRoleId } | Select-Object -First 1
            if ($matchingRole) {
                $appRoleValue = $matchingRole.value
            }
        }

        $assignments.Add([pscustomobject]@{
                PrincipalType        = 'AutomationAccountMSI'
                PermissionType       = 'AADAppRole'
                PrincipalName        = $principalDisplayName
                PrincipalId          = $principal.Id
                ResourceDisplayName  = $assignment.resourceDisplayName
                ResourceId           = $assignment.resourceId
                AppRoleId            = $assignment.appRoleId
                CreatedDateTime      = $assignment.createdDateTime
                AppRoleValue         = $appRoleValue
                TenantRootManagementGroupId        = $TenantRootManagementGroupId
                TenantRootManagementGroupResourceId = "/providers/Microsoft.Management/managementGroups/$TenantRootManagementGroupId"
            }) | Out-Null
    }

    return [pscustomobject]@{
        PrincipalType                     = 'AutomationAccountMSI'
        PrincipalId                       = $principal.Id
        PrincipalAppId                    = $principal.AppId
        PrincipalName                     = $principalDisplayName
        TenantRootManagementGroupId       = $TenantRootManagementGroupId
        TenantRootManagementGroupResourceId = "/providers/Microsoft.Management/managementGroups/$TenantRootManagementGroupId"
        Assignments                       = $assignments
        Errors                            = $errors
    }
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
    elseif(($deployedVersionVersion -eq $currentVersionVersion) -and 
        ($deployedVersion -match 'beta') -and 
        ($currentVersion -notmatch 'beta')) {
        $updateNeeded = $true
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

#region Guardrail Telemetry Helpers

function Initialize-GuardrailTelemetry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$GuardrailId,
        [Parameter(Mandatory = $true)]
        [string]$RunbookName,
        [Parameter(Mandatory = $true)]
        [string]$WorkSpaceID,
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceKey,
        [Parameter(Mandatory = $false)]
        [string]$SubscriptionId,
        [Parameter(Mandatory = $false)]
        [string]$TenantId,
        [Parameter(Mandatory = $false)]
        [string]$JobId,
        [Parameter(Mandatory = $false)]
        [string]$CorrelationId
    )

    $telemetryEnabled = $false
    if ($env:ENABLE_DEBUG_METRICS) {
        $telemetryEnabled = [string]::Equals($env:ENABLE_DEBUG_METRICS, 'true', [System.StringComparison]::InvariantCultureIgnoreCase)
    }

    if (-not $telemetryEnabled) {
        return [pscustomobject]@{ Enabled = $false }
    }

    if ([string]::IsNullOrWhiteSpace($WorkSpaceID) -or [string]::IsNullOrWhiteSpace($WorkspaceKey)) {
        Write-Verbose "Guardrail telemetry disabled due to missing workspace configuration."
        return [pscustomobject]@{ Enabled = $false }
    }

    if (-not $CorrelationId) {
        $CorrelationId = [guid]::NewGuid().ToString()
    }

    return [pscustomobject]@{
        Enabled        = $true
        GuardrailId    = $GuardrailId
        RunbookName    = $RunbookName
        WorkspaceId    = $WorkSpaceID
        WorkspaceKey   = $WorkspaceKey
        SubscriptionId = $SubscriptionId
        TenantId       = $TenantId
        JobId          = $JobId
        CorrelationId  = $CorrelationId
        DurationColumnInitialized = $false
    }
}

# Returns the current PowerShell worker memory usage in MB (rounded to two decimals).
function Get-GuardrailProcessMemory {
    [CmdletBinding()]
    param ()

    $process = [System.Diagnostics.Process]::GetCurrentProcess()
    try {
        $workingSetMb = [Math]::Round(($process.WorkingSet64 / 1MB), 2)
        $peakWorkingSetMb = [Math]::Round(($process.PeakWorkingSet64 / 1MB), 2)

        return [pscustomobject]@{
            WorkingSetMb     = $workingSetMb
            PeakWorkingSetMb = $peakWorkingSetMb
        }
    }
    finally {
        $process.Dispose()
    }
}

function Update-RunStateMemoryStats {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [psobject]$RunState,
        [Parameter(Mandatory = $true)]
        [psobject]$CurrentSnapshot
    )

    $RunState.Stats.MemoryEndMb = $CurrentSnapshot.WorkingSetMb
    if ($CurrentSnapshot.PeakWorkingSetMb -gt $RunState.Stats.MemoryPeakMb) {
        $RunState.Stats.MemoryPeakMb = $CurrentSnapshot.PeakWorkingSetMb
    }
    $RunState.Stats.MemoryDeltaMb = [Math]::Round(($RunState.Stats.MemoryEndMb - $RunState.Stats.MemoryStartMb), 2)
}

function Write-GuardrailTelemetry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [psobject]$Context,
        [Parameter(Mandatory = $true)]
        [string]$ExecutionScope,
        [Parameter(Mandatory = $true)]
        [string]$EventType,
        [Parameter(Mandatory = $false)]
        [string]$ModuleName,
        [Parameter(Mandatory = $false)]
        [Nullable[double]]$DurationMs,
        [Parameter(Mandatory = $false)]
        [double]$ErrorCount,
        [Parameter(Mandatory = $false)]
        [double]$ItemCount,
        [Parameter(Mandatory = $false)]
        [double]$CompliantCount,
        [Parameter(Mandatory = $false)]
        [double]$NonCompliantCount,
        [Parameter(Mandatory = $false)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [string]$ReportTime,
        [Parameter(Mandatory = $false)]
        [string]$GuardrailIdOverride,
        [Parameter(Mandatory = $false)]
        [Nullable[double]]$MemoryStartMb,
        [Parameter(Mandatory = $false)]
        [Nullable[double]]$MemoryEndMb,
        [Parameter(Mandatory = $false)]
        [Nullable[double]]$MemoryPeakMb,
        [Parameter(Mandatory = $false)]
        [Nullable[double]]$MemoryDeltaMb
    )

    if (-not $Context -or -not $Context.Enabled) {
        return
    }

    try {
        $record = [ordered]@{
            GuardrailId        = if (-not [string]::IsNullOrWhiteSpace($GuardrailIdOverride)) { $GuardrailIdOverride } else { $Context.GuardrailId }
            RunbookName        = $Context.RunbookName
            ModuleName         = $ModuleName
            ExecutionScope     = $ExecutionScope
            EventType          = $EventType
            CorrelationId      = [string]$Context.CorrelationId
            JobId              = [string]$Context.JobId
            RunSubscriptionId  = [string]$Context.SubscriptionId
            RunTenantId        = [string]$Context.TenantId
            ErrorCount         = if ($null -ne $ErrorCount) { [double]$ErrorCount } else { 0d }
            ItemCount          = if ($null -ne $ItemCount) { [double]$ItemCount } else { 0d }
            CompliantCount     = if ($null -ne $CompliantCount) { [double]$CompliantCount } else { 0d }
            NonCompliantCount  = if ($null -ne $NonCompliantCount) { [double]$NonCompliantCount } else { 0d }
            ReportTime         = if ($ReportTime) { $ReportTime } else { $null }
            Message            = if (-not [string]::IsNullOrWhiteSpace($Message)) { $Message } else { $null }
        }

        $hasDurationValue = $PSBoundParameters.ContainsKey('DurationMs') -and $null -ne $DurationMs

        if ($hasDurationValue) {
            $durationRounded = [double][Math]::Round($DurationMs, 2)
            $record['DurationMsReal'] = $durationRounded
            $Context.DurationColumnInitialized = $true
        }
        elseif (-not $Context.DurationColumnInitialized) {
            # LAW infers DurationMsReal as string when the first ingested
            # record omits duration. Seed with a tiny double to force the column type once.
            $record['DurationMsReal'] = [double]0.01
            $Context.DurationColumnInitialized = $true
        }

        if ($PSBoundParameters.ContainsKey('MemoryStartMb') -and $null -ne $MemoryStartMb) {
            $record['MemoryStartMb'] = [double][Math]::Round($MemoryStartMb, 2)
        }
        if ($PSBoundParameters.ContainsKey('MemoryEndMb') -and $null -ne $MemoryEndMb) {
            $record['MemoryEndMb'] = [double][Math]::Round($MemoryEndMb, 2)
        }
        if ($PSBoundParameters.ContainsKey('MemoryPeakMb') -and $null -ne $MemoryPeakMb) {
            $record['MemoryPeakMb'] = [double][Math]::Round($MemoryPeakMb, 2)
        }
        if ($PSBoundParameters.ContainsKey('MemoryDeltaMb') -and $null -ne $MemoryDeltaMb) {
            $record['MemoryDeltaMb'] = [double][Math]::Round($MemoryDeltaMb, 2)
        }

        $data = @([pscustomobject]$record)
        New-LogAnalyticsData -Data $data -WorkSpaceID $Context.WorkspaceId -WorkSpaceKey $Context.WorkspaceKey -LogType 'CaCDebugMetrics' | Out-Null
    }
    catch {
        Write-Verbose "Failed to write guardrail telemetry: $_"
    }
}

function New-GuardrailRunState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$GuardrailId,
        [Parameter(Mandatory = $true)]
        [string]$RunbookName,
        [Parameter(Mandatory = $true)]
        [string]$WorkSpaceID,
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceKey,
        [Parameter(Mandatory = $false)]
        [string]$SubscriptionId,
        [Parameter(Mandatory = $false)]
        [string]$TenantId,
        [Parameter(Mandatory = $false)]
        [string]$JobId,
        [Parameter(Mandatory = $false)]
        [string]$ReportTime
    )

    $telemetryContext = Initialize-GuardrailTelemetry -GuardrailId $GuardrailId -RunbookName $RunbookName -WorkSpaceID $WorkSpaceID -WorkspaceKey $WorkspaceKey -SubscriptionId $SubscriptionId -TenantId $TenantId -JobId $JobId -CorrelationId $null

    $runState = [pscustomobject]@{
        TelemetryContext = $telemetryContext
        ReportTime       = $ReportTime
        RunStopwatch     = [System.Diagnostics.Stopwatch]::StartNew()
        Stats            = [ordered]@{
            ModulesEnabled    = 0
            ModulesDisabled   = 0
            TotalItems        = 0
            CompliantItems    = 0
            NonCompliantItems = 0
            Errors            = 0
            MemoryStartMb     = 0
            MemoryEndMb       = 0
            MemoryPeakMb      = 0
            MemoryDeltaMb     = 0
        }
        Summaries        = [System.Collections.Generic.List[psobject]]::new()
    }

    $initialMemory = Get-GuardrailProcessMemory
    $runState.Stats.MemoryStartMb = $initialMemory.WorkingSetMb
    Update-RunStateMemoryStats -RunState $runState -CurrentSnapshot $initialMemory

    Write-GuardrailTelemetry -Context $telemetryContext -ExecutionScope 'Runbook' -ModuleName 'RUNBOOK' -EventType 'Start' -ReportTime $ReportTime -MemoryStartMb $initialMemory.WorkingSetMb -MemoryPeakMb $initialMemory.PeakWorkingSetMb

    return $runState
}

function Start-GuardrailModuleState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [psobject]$RunState,
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,
        [Parameter(Mandatory = $false)]
        [string]$GuardrailId
    )

    $RunState.Stats.ModulesEnabled++

    $memorySnapshot = Get-GuardrailProcessMemory
    Update-RunStateMemoryStats -RunState $RunState -CurrentSnapshot $memorySnapshot

    $moduleState = [pscustomobject]@{
        ModuleName        = $ModuleName
        Stopwatch         = [System.Diagnostics.Stopwatch]::StartNew()
        GuardrailId       = $GuardrailId
        MemoryStartMb     = $memorySnapshot.WorkingSetMb
        MemoryStartPeakMb = $memorySnapshot.PeakWorkingSetMb
    }

    Write-GuardrailTelemetry -Context $RunState.TelemetryContext -ExecutionScope 'Module' -ModuleName $ModuleName -EventType 'Start' -ReportTime $RunState.ReportTime -GuardrailIdOverride $GuardrailId -MemoryStartMb $memorySnapshot.WorkingSetMb -MemoryPeakMb $memorySnapshot.PeakWorkingSetMb

    return $moduleState
}

function Complete-GuardrailModuleState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [psobject]$RunState,
        [Parameter(Mandatory = $true)]
        [psobject]$ModuleState,
        [Parameter(Mandatory = $false)]
        [int]$ErrorCount = 0,
        [Parameter(Mandatory = $false)]
        [int]$ItemCount = 0,
        [Parameter(Mandatory = $false)]
        [int]$CompliantCount = 0,
        [Parameter(Mandatory = $false)]
        [int]$NonCompliantCount = 0,
        [Parameter(Mandatory = $false)]
        [string]$Message
    )

    if ($ModuleState.Stopwatch -and $ModuleState.Stopwatch.IsRunning) {
        $ModuleState.Stopwatch.Stop()
    }

    $durationMs = $null
    if ($ModuleState.Stopwatch) {
        $durationMs = $ModuleState.Stopwatch.Elapsed.TotalMilliseconds
    }

    $RunState.Stats.Errors += $ErrorCount
    $RunState.Stats.TotalItems += $ItemCount
    $RunState.Stats.CompliantItems += $CompliantCount
    $RunState.Stats.NonCompliantItems += $NonCompliantCount

    if (-not $Message) {
        $parts = @("Items=$ItemCount")
        if ($ErrorCount -gt 0) { $parts += "Errors=$ErrorCount" }
        $Message = $parts -join '; '
    }

    $memoryEnd = Get-GuardrailProcessMemory
    $memoryStartMb = if ($ModuleState.PSObject.Properties.Match('MemoryStartMb').Count -gt 0) { $ModuleState.MemoryStartMb } else { $memoryEnd.WorkingSetMb }
    $memoryStartPeakMb = if ($ModuleState.PSObject.Properties.Match('MemoryStartPeakMb').Count -gt 0) { $ModuleState.MemoryStartPeakMb } else { $memoryEnd.PeakWorkingSetMb }
    $modulePeakMb = [Math]::Round(([Math]::Max($memoryEnd.PeakWorkingSetMb, $memoryStartPeakMb)), 2)
    $memoryDeltaMb = [Math]::Round(($memoryEnd.WorkingSetMb - $memoryStartMb), 2)

    Update-RunStateMemoryStats -RunState $RunState -CurrentSnapshot $memoryEnd

    Write-GuardrailTelemetry -Context $RunState.TelemetryContext -ExecutionScope 'Module' -ModuleName $ModuleState.ModuleName -EventType 'End' -DurationMs $durationMs -ErrorCount $ErrorCount -ItemCount $ItemCount -CompliantCount $CompliantCount -NonCompliantCount $NonCompliantCount -ReportTime $RunState.ReportTime -Message $Message -GuardrailIdOverride $ModuleState.GuardrailId -MemoryStartMb $memoryStartMb -MemoryEndMb $memoryEnd.WorkingSetMb -MemoryPeakMb $modulePeakMb -MemoryDeltaMb $memoryDeltaMb

    $summary = [pscustomobject]@{
        ModuleName      = $ModuleState.ModuleName
        IsSkipped       = $false
        DurationSeconds = if ($null -ne $durationMs) { [Math]::Round($durationMs / 1000, 2) } else { 0 }
        Items           = $ItemCount
        Errors          = $ErrorCount
        GuardrailId     = $ModuleState.GuardrailId
        MemoryStartMb   = $memoryStartMb
        MemoryEndMb     = $memoryEnd.WorkingSetMb
        MemoryDeltaMb   = $memoryDeltaMb
        MemoryPeakMb    = $modulePeakMb
    }
    $null = $RunState.Summaries.Add($summary)

    return $summary
}

function Skip-GuardrailModuleState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [psobject]$RunState,
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,
        [Parameter(Mandatory = $false)]
        [string]$GuardrailId
    )

    $RunState.Stats.ModulesDisabled++

    $memorySnapshot = Get-GuardrailProcessMemory
    Update-RunStateMemoryStats -RunState $RunState -CurrentSnapshot $memorySnapshot

    Write-GuardrailTelemetry -Context $RunState.TelemetryContext -ExecutionScope 'Module' -ModuleName $ModuleName -EventType 'Skipped' -ReportTime $RunState.ReportTime -GuardrailIdOverride $GuardrailId -MemoryStartMb $memorySnapshot.WorkingSetMb -MemoryEndMb $memorySnapshot.WorkingSetMb -MemoryPeakMb $memorySnapshot.PeakWorkingSetMb -MemoryDeltaMb 0

    $summary = [pscustomobject]@{
        ModuleName      = $ModuleName
        IsSkipped       = $true
        DurationSeconds = 0
        Items           = 0
        Errors          = 0
        GuardrailId     = $GuardrailId
        MemoryStartMb   = $memorySnapshot.WorkingSetMb
        MemoryEndMb     = $memorySnapshot.WorkingSetMb
        MemoryDeltaMb   = 0
        MemoryPeakMb    = $memorySnapshot.PeakWorkingSetMb
    }
    $null = $RunState.Summaries.Add($summary)

    return $summary
}

function Complete-GuardrailRunState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [psobject]$RunState
    )

    if ($RunState.RunStopwatch -and $RunState.RunStopwatch.IsRunning) {
        $RunState.RunStopwatch.Stop()
    }

    $duration = if ($RunState.RunStopwatch) { $RunState.RunStopwatch.Elapsed } else { [TimeSpan]::Zero }

    $messageParts = @(
        "ModulesEnabled=$($RunState.Stats.ModulesEnabled)",
        "ModulesDisabled=$($RunState.Stats.ModulesDisabled)",
        "TotalItems=$($RunState.Stats.TotalItems)"
    )
    $runMessage = $messageParts -join '; '

    Update-RunStateMemoryStats -RunState $RunState -CurrentSnapshot ([pscustomobject]@{
            WorkingSetMb     = $RunState.Stats.MemoryEndMb
            PeakWorkingSetMb = $RunState.Stats.MemoryPeakMb
        })

    Write-GuardrailTelemetry -Context $RunState.TelemetryContext -ExecutionScope 'Runbook' -ModuleName 'RUNBOOK' -EventType 'End' -DurationMs $duration.TotalMilliseconds -ErrorCount $RunState.Stats.Errors -ItemCount $RunState.Stats.TotalItems -CompliantCount $RunState.Stats.CompliantItems -NonCompliantCount $RunState.Stats.NonCompliantItems -ReportTime $RunState.ReportTime -Message $runMessage -MemoryStartMb $RunState.Stats.MemoryStartMb -MemoryEndMb $RunState.Stats.MemoryEndMb -MemoryPeakMb $RunState.Stats.MemoryPeakMb -MemoryDeltaMb $RunState.Stats.MemoryDeltaMb

    return [pscustomobject]@{
        Duration  = $duration
        Stats     = $RunState.Stats
        Summaries = $RunState.Summaries
    }
}

#endregion Guardrail Telemetry Helpers

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

# Function for true streaming Graph API queries with callback processing
function Invoke-GraphQueryStreamWithCallback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^(?!https://graph.microsoft.com/(v1|beta)/)')]
        [string] $urlPath,
        
        [Parameter(Mandatory = $true)]
        [scriptblock] $ProcessPageCallback,
        
        [Parameter(Mandatory = $false)]
        [hashtable] $CallbackContext = @{},
        
        [Parameter(Mandatory = $false)]
        [int] $PageSize = 999,
        
        [Parameter(Mandatory = $false)]
        [int] $MaxRetries = 3,
        
        [Parameter(Mandatory = $false)]
        [int] $RetryDelaySeconds = 5,
        
        [Parameter(Mandatory = $false)]
        [hashtable] $PerformanceMetrics = $null
    )

    [string] $baseUri = "https://graph.microsoft.com/v1.0"
    
    # Add $top parameter if not already present
    if ($urlPath -notmatch '\$top=') {
        $separator = if ($urlPath -match '\?') { '&' } else { '?' }
        $urlPath = "$urlPath$separator`$top=$PageSize"
    }

    
    $fullUri = "$baseUri$urlPath"
    $pageCount = 0
    $totalProcessed = 0
    $totalUploaded = 0
        
    do {
        $pageCount++
        $retryCount = 0
        $success = $false
        
        Write-Verbose "  -> Fetching page $pageCount from Graph API..."        
        do {
            try {
                $uri = $fullUri -as [uri]
                $response = Invoke-AzRestMethod -Uri $uri -Method GET -ErrorAction Stop
                $statusCode = $response.StatusCode
                                
                # Check for successful status codes (200-299)
                if ($statusCode -ge 200 -and $statusCode -lt 300) {
                    $data = $response.Content | ConvertFrom-Json
                    $success = $true
                                        
                    # Update performance metrics if provided
                    if ($PerformanceMetrics) {
                        $PerformanceMetrics.GraphApiCalls++
                    }
                } else {
                    # Handle non-success status codes
                    $errorContent = $response.Content

                    # Determine if this is a retryable error
                    $isRetryable = switch ($statusCode) {
                        429 { $true }   # Too Many Requests - always retry
                        500 { $true }   # Internal Server Error - retry
                        502 { $true }   # Bad Gateway - retry  
                        503 { $true }   # Service Unavailable - retry
                        504 { $true }   # Gateway Timeout - retry
                        400 { $false }  # Bad Request - don't retry (client error)
                        401 { $false }  # Unauthorized - don't retry (auth error)
                        403 { $false }  # Forbidden - don't retry (permission error)
                        404 { $false }  # Not Found - don't retry (resource error)
                        default { $statusCode -ge 500 }  # Retry on 5xx errors, not 4xx
                    }
                    
                    if (-not $isRetryable) {
                        throw [System.Exception]::new("Graph API returned non-retryable error $statusCode at page $pageCount. Content: $errorContent")
                    } else {
                        throw [System.Exception]::new("Graph API returned retryable error $statusCode at page $pageCount. Content: $errorContent")
                    }
                }
                
            }
            catch {
                $retryCount++
                $errorMessage = $_.Exception.Message
                                
                if ($retryCount -ge $MaxRetries) {
                    Write-Error "Failed to call Microsoft Graph REST API at URL '$fullUri' after $MaxRetries attempts; error: $errorMessage at page $pageCount"
                    throw [System.Exception]::new("Failed to call Microsoft Graph REST API at URL '$fullUri' after $MaxRetries attempts; error: $errorMessage at page $pageCount")
                } elseif ($isRetryable) {
                    Write-Warning "Retryable error calling Graph API (attempt $retryCount/$MaxRetries): $errorMessage. Retrying in $RetryDelaySeconds seconds..."
                    Start-Sleep -Seconds $RetryDelaySeconds
                } else {
                    Write-Error "Non-retryable error calling Graph API: $errorMessage"
                    throw [System.Exception]::new("Non-retryable error calling Graph API: $errorMessage")
                }
            }
        } while (-not $success -and $retryCount -lt $MaxRetries)

        # Process current page immediately via callback
        $pageData = @{
            Data = if ($null -ne $data.value) { $data.value } else { $data }
            PageNumber = $pageCount
            HasMore = $null -ne $data.'@odata.nextLink'
            StatusCode = $statusCode
        }
        
        # Execute callback to process this page immediately with error handling
        try {
            $callbackResult = & $ProcessPageCallback $pageData $CallbackContext
            if ($callbackResult) {
                $totalProcessed += $callbackResult.ProcessedCount
                $totalUploaded += $callbackResult.UploadedCount
            }
        }
        catch {
            Write-Error "Failed to process page $pageCount via callback: $($_.Exception.Message)"
            throw $_  # Re-throw to stop processing if callback fails
        }
        
        # Update URI for next page
        if ($data.'@odata.nextLink') {
            $fullUri = $data.'@odata.nextLink'
        } else {
            $fullUri = $null
        }
        
        # Rate limiting between pages
        if ($fullUri) {
            Write-Verbose "  -> Waiting 2 seconds before fetching next page..."
            Start-Sleep -Seconds 2
        }
        
    } while ($fullUri)
    
    return @{
        TotalPages = $pageCount
        TotalProcessed = $totalProcessed
        TotalUploaded = $totalUploaded
    }
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

# Utility function for centralized error handling
function Add-FunctionError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        
        [Parameter(Mandatory = $false)]
        [System.Exception] $Exception = $null,
        
        [Parameter(Mandatory = $false)]
        [string] $Category = "General",
        
        [Parameter(Mandatory = $false)]
        [System.Collections.Generic.List[string]] $ErrorList = $null
    )
    
    if ($Exception) {
        $errorMsg = "$Category - $Message : $($Exception.Message)"
    } else {
        $errorMsg = "$Category - $Message"
    }
    
    Write-Warning $errorMsg
    
    if ($ErrorList) {
        $ErrorList.Add($errorMsg)
    }
}

# Utility function for exponential backoff delay calculation
function Get-BackoffDelay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int] $Attempt,
        
        [Parameter(Mandatory = $true)]
        [hashtable] $Config
    )
    
    $delay = [Math]::Min(
        $Config.BaseDelay * [Math]::Pow($Config.BackoffMultiplier, $Attempt - 1),
        $Config.MaxDelay
    )
    return [int]$delay
}

# Utility function for Graph API calls with metrics and error handling
function Invoke-GraphQueryWithMetrics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $UrlPath,
        
        [Parameter(Mandatory = $false)]
        [string] $Operation = "Graph API Call",
        
        [Parameter(Mandatory = $false)]
        [hashtable] $PerformanceMetrics = $null,
        
        [Parameter(Mandatory = $false)]
        [int] $MaxRetries = 5,
        
        [Parameter(Mandatory = $false)]
        [int] $RetryDelaySeconds = 10
    )
    
    Write-Verbose "  -> $Operation : $UrlPath"
    
    try {
        # Use the existing retry logic in Invoke-GraphQueryEX
        $response = Invoke-GraphQueryEX -urlPath $UrlPath -MaxRetries $MaxRetries -RetryDelaySeconds $RetryDelaySeconds -ErrorAction Stop
        
        # Update performance metrics if provided
        if ($PerformanceMetrics) {
            $PerformanceMetrics.GraphApiCalls++
        }
        
        # Handle array responses consistently
        if ($response -is [System.Array]) {
            $response = $response | Where-Object { 
                $null -ne $_.Content -or $null -ne $_.StatusCode 
            } | Select-Object -Last 1
        }
        
        # Check for successful response
        if ($response.Error) {
            throw [System.Exception]::new("Graph API error: $($response.Error)")
        }
        
        if (-not $response.StatusCode -or $response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
            throw [System.Exception]::new("Graph API returned status code: $($response.StatusCode)")
        }
        
        Write-Verbose "  Success: $Operation completed"
        return $response
    }
    catch {
        Write-Error "$Operation failed: $($_.Exception.Message)"
        throw $_
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
            # Use WebUtility for PS5/PS7 compatibility
            $encodedUserEmail = [System.Net.WebUtility]::UrlEncode($userEmail)
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
                    Write-Host "$userAccount - System preferred authentication method is $systemPreferredMethod"
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
        [AllowEmptyCollection()]
        # Callers pass an ArrayList so this function can append errors in-place
        # and return the same mutable collection in the output envelope.
        [System.Collections.ArrayList] $ErrorList,
        [bool] $IsCompliant
    )

    # Find named locations
    $locationsBaseAPIUrl = '/identity/conditionalAccess/namedLocations'
    try {
        $response = Invoke-GraphQueryEX -urlPath $locationsBaseAPIUrl -ErrorAction Stop
        $data = $response.Content
        $locationData = if ($data -and $data.value) { $data.value } else { @() }
        # Filter for country NamedLocation only
        $locations = $locationData | Where-Object { $_.'@odata.type' -and $_.'@odata.type' -eq '#microsoft.graph.countryNamedLocation'}
    }
    catch {
        # Suppress Add() return index so the function output remains a compliance object, not an array.
        [void]$Errorlist.Add("Failed to call Microsoft Graph REST API at URL '$locationsBaseAPIUrl'; returned error message: $_") 
        Write-Warning "Error: Failed to call Microsoft Graph REST API at URL '$locationsBaseAPIUrl'; returned error message: $_"
        $locations = @()
    }

    # Find conditional access policies
    $CABaseAPIUrl = '/identity/conditionalAccess/policies'
    try {
        $response = Invoke-GraphQueryEX -urlPath $CABaseAPIUrl -ErrorAction Stop

        $caps = if ($response.Content -and $response.Content.value) { $response.Content.value } else { @() }
    }
    catch {
        [void]$Errorlist.Add("Failed to call Microsoft Graph REST API at URL '$CABaseAPIUrl'; returned error message: $_")
        Write-Warning "Error: Failed to call Microsoft Graph REST API at URL '$CABaseAPIUrl'; returned error message: $_"
        $caps = @()
    }

    # Group named locations and find location Ids
    $validLocations = @()               # Canada-only named locations
    $validLocationIds = @()             
    $nonCAnamedLocations = @()          # named locations that represent 'all countries except Canada-only
    $nonCAnamedLocationsIds = @()
    $someNonCAnamedLocations = @()      # named locations that represent 'some countries except Canada-only'
    $someNonCAnamedLocationsIds = @()       
    $notValidCAnamedLocations = @()     # named locations that includes Canada + other countries
    $notValidCAnamedLocationsIds = @()  

    foreach ($location in $locations) {
        try {
            $countries = @()
            if ($null -ne $location.countriesAndRegions) { 
                $countries = @($location.countriesAndRegions) 
            }
            # Find all valid locations: Canada-Only; a valid location requirement i.e. Canada
            if ($countries.Count -eq 1 -and $countries[0] -eq 'CA') {
                Write-Host "Named Location Found: $($location.displayName) with Country/Region: $($location.countriesAndRegions -join ', ')"
                $validLocations += $location
                if ($location.PSObject.Properties.Match('id').Count -gt 0) { 
                    $validLocationIds += $location.id.ToString().ToLower()
                }
                continue
            }
            # Find named location contains ALL countries except Canada; a valid location requirement i.e. 'RestOfTheWorld'
            if ($countries.Count -eq 249 -and -not ($countries -contains 'CA')) {
                Write-Host "Named Location Found: $($location.displayName) with Country/Region: $($location.countriesAndRegions -join ', ')"
                $nonCAnamedLocations += $location
                if ($location.PSObject.Properties.Match('id').Count -gt 0){
                    $nonCAnamedLocationsIds += $location.id.ToString().ToLower()
                }
                continue
            }
            # Find named location contains multiple countries; includes Canada; not a valid location requirement i.e. 'TestLocation'
            if ($countries.Count -ge 1 -and ($countries -contains 'CA')) {
                Write-Host "Named Location Found: $($location.displayName) with Country/Region: $($location.countriesAndRegions -join ', ')"
                $notValidCAnamedLocations += $location
                if ($location.PSObject.Properties.Match('id').Count -gt 0){
                    $notValidCAnamedLocationsIds += $location.id.ToString().ToLower()
                }
                continue
            }
            # Find named location contains countries (may or may not multiple but not 'ALL') except Canada; not a valid location requirement i.e. 'SelectedCountriesExclCanada'
            if ($countries.Count -lt 249 -and -not ($countries -contains 'CA')) {
                Write-Host "Named Location Found: $($location.displayName) with Country/Region: $($location.countriesAndRegions -join ', ')"
                $someNonCAnamedLocations += $location
                if ($location.PSObject.Properties.Match('id').Count -gt 0){
                    $someNonCAnamedLocationsIds += $location.id.ToString().ToLower()
                }
                continue
            }
        }
        catch {
            $ErrorList.Add("Error processing named location object: $_") | Out-Null
            continue
        }
    }
    # If no Canada-only named locations or no non-Canada all-country named locations found, return non-compliant
    if ($validLocations.Count -eq 0 -or $nonCAnamedLocations.Count -eq 0) {
        Write-Warning "Warning: No Canada-only named locations found or no non-Canada all-country named locations found. Cannot evaluate Conditional Access Policies for compliance."
        $ErrorList.Add("No Canada-only named locations found. Cannot evaluate Conditional Access Policies for compliance.") | Out-Null
        $IsCompliant = $false
        $Comments = $msgTable.noCanadaNamedLocationFound + " " + $msgTable.noLocationsnonCACompliant

        $PsObject = [PSCustomObject]@{
            ComplianceStatus = $IsCompliant
            ControlName      = $ControlName
            Comments         = $Comments
            ItemName         = $ItemName
            ReportTime       = $ReportTime
            itsgcode         = $itsgcode
            Errors           = $ErrorList
        }
        # Explicit return avoids null/implicit output in early-exit non-compliance paths.
        return $PsObject
    }
    

    # Filter enabled CAPs
    $enabledCAPs = $caps | Where-Object { $_.state -eq 'enabled' }
    # If no enabled CAPs found, return non-compliant
    if ($null -eq $enabledCAPs -or $enabledCAPs.Count -eq 0) {
        Write-Host "No enabled Conditional Access Policies found."
        $ErrorList.Add("No enabled Conditional Access Policies found. Cannot evaluate Conditional Access Policies for compliance.") | Out-Null
        $Comments = $msgTable.noEnabledPoliciesFound
        $IsCompliant = $false

        $PsObject = [PSCustomObject]@{
            ComplianceStatus = $IsCompliant
            ControlName      = $ControlName
            Comments         = $Comments
            ItemName         = $ItemName
            ReportTime       = $ReportTime
            itsgcode         = $itsgcode
            Errors           = $ErrorList
        }
        return $PsObject
    }
    
    Write-Host "Found $($enabledCAPs.Count) enabled Conditional Access Policies."

    #  ---------Evaluate CAPs for patterns that effectively restrict access to Canada ---------------#
    # Compliant Patterns: Compliant if CAPs found that match the patterns below:
    #  A) Pattern A: Policy explicitly includes a named location that represents 'all countries except Canada' (make sure all countries are included) AND action is Block
    #  B) Pattern B: Policy includes 'all' locations and explicitely excludes the Canada-only named-location id AND action is Block (i.e. block all except Canada)
    #  C) Pattern C: Policy has no includeLocations but EXCLUDES the Canada-only named-location id (conservative treat as location-based)
    
    # Non-Compliant Patterns: Non-Compliant if CAPs found that match the patterns below:
    #  D) Pattern D: Policy explicitly includes the Canada-only named-location id AND action is Grant, but none in exclusion (i.e. allow only Canada)
    #  E) Pattern E: Policy explicitly includes a named location that represents some countries except Canada AND action is Block

    # Common synonyms for "all" locations in various CAP outputs
    $allLocationsSym = @('all','any','alltrusted','alltrustedlocations','alllocations')

    # $locationBasedPolicies =  $enabledCAPs | Where-Object {($null -ne $_.conditions.locations) -and ($validLocations.id -in $_.conditions.locations.includeLocations) -or ($validLocations.id -in $_.conditions.locations.excludeLocations ) }
    # Find CAPs with Location conditions
    $locationBasedPolicies =  $enabledCAPs | Where-Object {($null -ne $_.conditions) -and ($null -ne $_.conditions.locations) }

    $validlocationBasedPolicies = @()
    foreach ($cap in $locationBasedPolicies) {
        try {
            $locationCondition = $cap.conditions.locations
            # include/exclude lists
            $includes = @()
            $excludes = @()
            if ($locationCondition.includeLocations -and $locationCondition.PSObject.Properties.Match('includeLocations').Count -gt 0 ) {
                $inccludeVals = @( $locationCondition.includeLocations )
                $includes = $inccludeVals | ForEach-Object { $_.ToString().ToLower() }
            }  
            if ($locationCondition.excludeLocations -and $locationCondition.PSObject.Properties.Match('excludeLocations').Count -gt 0) {
                $excludeVals = @( $locationCondition.excludeLocations )
                $excludes = $excludeVals | ForEach-Object { $_.ToString().ToLower() }
            }
            # Determine the CAP's grant controls
            $grantControls = @()
            $grantBuiltIns = @()    
            if ($cap.grantControls -and $cap.PSObject.Properties.Match('grantControls').Count -gt 0) {
                $grantControls = @($cap.grantControls.buildInControls )
                try {
                    if ($cap.grantControls.PSObject.Properties.Match('builtInControls').Count -gt 0 -and $cap.grantControls.builtInControls) {
                        $grantBuiltIns = @($cap.grantControls.builtInControls) | ForEach-Object { $_.ToString().ToLower() }
                    }
                } catch { 
                    Write-Warning "Warning: Unable to process grantControls builtInControls for CAP '$($cap.id)': $_"
                }
            }
            # Check for Grant/Block action in grant controls
            $isBlockAction = $false
            $isGrantAction = $false
            if ($grantControls -contains 'block' -or $grantBuiltIns -contains 'block') {
                $isBlockAction = $true
            }
            else{
                $isGrantAction = $true
            }
            # Evaluate patterns
            $matched = $false

            # Pattern A: explicitly includes a named location of 'All' countries but does not have Canada in it  -> can represent "block all except Canada"
            # PASS
            if ($includes | Where-Object { $nonCAnamedLocationsIds -contains $_ }) {
                if ($isBlockAction) {
                    $matched = $true
                }
            }

            # Pattern B: includes 'all' (or equivalent) but explicitely excludes Canada-only named location -> can represent "block all except Canada"
            # PASS
            if (($includes | Where-Object { $allLocationsSym -contains $_ }) -and ($excludes | Where-Object { $validLocationIds -contains $_ })) {
                if ($isBlockAction) {
                    $matched = $true
                }
            }
            # Pattern C: no includes but explicitely exclude Canada-only named locations(conservative detection)
            # PASS
            if ($includes.Count -eq 0 -and ($excludes | Where-Object { $validLocationIds -contains $_ })) {
                if ($isBlockAction) {
                    $matched = $true
                }
            }
            # Pattern D: explicit inclusion of Canada-only named location, no exclusion -> can represent "allow only Canada but other countries not excluded
            # FAIL
            if ($includes | Where-Object { $validLocationIds -contains $_ }) {
                if ($isGrantAction) {
                    $matched = $false
                }
            }
            # Pattern E: explicit inclusion of some countries except Canada -> can represent "block some countries except Canada"
            # FAIL
            if ($someNonCAnamedLocationsIds | Where-Object { $includes -contains $_ }) {
                if ($isBlockAction) {
                    $matched = $false
                }
            }

            Write-Host "CAP Found $($cap.displayName) with include and/or exclude location condition that has a match '$($matched)' with '$($grantBuiltIns)' access control"
            if ($matched) {
                $validlocationBasedPolicies += $cap
                Write-Host "Valid Canada-only location CAP Found: $($cap.displayName)"
            }

        }
        catch {
            $ErrorList.Add("Error evaluating CAP '$($cap.id)' : $_") | Out-Null
            continue
        }
        
        # Determine compliance based on presence of named-location and matching policies
        if ($null -eq $validlocationBasedPolicies -or ($validlocationBasedPolicies.Count -eq 0) ){
            # Non-complient; No policies have valid locations
            $Comments = $msgTable.noCompliantPoliciesfound
            $IsCompliant = $false
        }
        elseif ($validlocationBasedPolicies.count -ne 0) {
            # Compliant; valid policies found
            $validCAPnames = ($validlocationBasedPolicies | Select-Object -ExpandProperty displayName) -join ', '
            $IsCompliant = $true
            # display all names of compliant CAPs in Comments
            $Comments = $msgTable.allPoliciesAreCompliant -f $validCAPnames
        }
        else{
            # Do nothing; all use cases are covered
        }
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
    $complianceDetails = @()
    $policySetDefinitionName = $PolicyID
    $policyFilters = @()
    $subscriptionFilter = "SubscriptionId eq '$($subscription.SubscriptionID)'"
    foreach ($policyRef in $requiredPolicyExemptionIds) {
        if (-not [string]::IsNullOrWhiteSpace($policyRef)) {
            $policyFilters += "PolicyDefinitionReferenceId eq '$policyRef'"
        }
    }
    if ($policyFilters.Count -gt 0) {
        $filterExpression = "$subscriptionFilter and PolicySetDefinitionName eq '$policySetDefinitionName' and (" + ($policyFilters -join " or ") + ")"
    }
    else {
        $filterExpression = "$subscriptionFilter and PolicySetDefinitionName eq '$policySetDefinitionName'"
    }

    $filteredQueryFailed = $true
    if ($filterExpression) {
        $filteredQueryFailed = $false
        try {
            Write-Verbose "Querying policy state with filter: $filterExpression"
            $complianceDetails = @(Get-AzPolicyState -Filter $filterExpression | Where-Object{ $_.SubscriptionId -eq $($subscription.SubscriptionID) })
        }
        catch {
            Write-Verbose "Filtered Get-AzPolicyState call failed, falling back to unfiltered query. Error: $_"
            $filteredQueryFailed = $true
        }
    }

    if ($filteredQueryFailed) {
        $complianceDetails = @(Get-AzPolicyState | Where-Object{ $_.SubscriptionId -eq $($subscription.SubscriptionID) } | Where-Object{ $_.PolicySetDefinitionName -eq $PolicyID})
    }

    if ($complianceDetails.Count -eq 0) {
        $complianceDetails = $null
    }
    
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
    [System.Collections.ArrayList] $tempObjectList = New-Object System.Collections.ArrayList
    $policyAssignmentCache = @{}
    $policySetDefinitionCache = @{}

    foreach ($obj in $objList)
    {
        Write-Verbose "Checking $objType : $($obj.Name)"
        Write-Verbose "PBMM policy PolicyID is $PolicyID"

        if ([string]::IsNullOrWhiteSpace($PolicyID)) {
            Write-Error "PolicyID is null or empty. Skipping PBMM evaluation for scope '$($obj.Id)'."
            continue
        }

        # Find scope
        if ($objType -eq "subscription"){
            $tempId="/subscriptions/$($obj.Id)"
        }
        else {
            $tempId=$obj.Id                              
        }
        Write-Host "Scope is $tempId"

        # Find assigned policy list from PBMM policy for the scope
        # Accept tenant, management group, or subscription scoped IDs that end with /policySetDefinitions/{id}
        if ($PolicyID.StartsWith("/") -and $PolicyID -match "/policySetDefinitions/[^/]+$") {
            $policyDefinitionIdFilter = $PolicyID
        }
        else {
            $policyDefinitionIdFilter = "/providers/Microsoft.Authorization/policySetDefinitions/$PolicyID"
        }

        $assignmentCacheKey = "$tempId|$policyDefinitionIdFilter"
        if ($policyAssignmentCache.ContainsKey($assignmentCacheKey)) {
            $AssignedPolicyList = $policyAssignmentCache[$assignmentCacheKey]
        }
        else {
            $AssignedPolicyList = Get-AzPolicyAssignment -Scope $tempId -PolicyDefinitionId $policyDefinitionIdFilter | `
                Select-Object -ExpandProperty properties
            $policyAssignmentCache[$assignmentCacheKey] = $AssignedPolicyList
        }

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
            if ($PolicyID.StartsWith("/") -and $PolicyID -match "/policySetDefinitions/[^/]+$") {
                $policySetCacheKey = $PolicyID
            }
            else {
                $policySetCacheKey = "/providers/Microsoft.Authorization/policySetDefinitions/$PolicyID"
            }

            if ($policySetDefinitionCache.ContainsKey($policySetCacheKey)) {
                $policySetDefinition = $policySetDefinitionCache[$policySetCacheKey]
            }
            else {
                try {
                    $policySetDefinition = Get-AzPolicySetDefinition -Id $policySetCacheKey
                    $policySetDefinitionCache[$policySetCacheKey] = $policySetDefinition
                }
                catch {
                    Write-Verbose "Direct lookup for policy set '$policySetCacheKey' failed. Falling back to tenant scan. Error: $_"
                    $policySetDefinition = Get-AzPolicySetDefinition | `
                        Where-Object { $_.PolicySetDefinitionId -like "*$PolicyID*" }
                }
            }

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
                            # Set Az context to this subscription
                            Set-AzContext -SubscriptionId $subscription.SubscriptionID | Out-Null
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
        [ValidateNotNullOrEmpty()]
        [string] $ReportTime,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $FirstBreakGlassUPN,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $SecondBreakGlassUPN,
        
        [Parameter(Mandatory=$true)]
        [ValidateScript({
            try { [System.Guid]::Parse($_); $true }
            catch { throw "WorkSpaceID must be a valid GUID" }
        })]
        [string] $WorkSpaceID,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $WorkspaceKey,
        
        [Parameter()]
        [int] $BatchSize = 999,
        
        [Parameter()]
        [hashtable] $RetryConfig = @{
            MaxRetries = 12
            BaseDelay = 5
            MaxDelay = 60
            BackoffMultiplier = 2
        }
    )
    
    # Initialize error tracking and performance monitoring
    $ErrorList = [System.Collections.Generic.List[string]]::new()
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $performanceMetrics = @{
        StartTime = Get-Date
        GraphApiCalls = 0
        UsersProcessed = 0
        DataIngestionAttempts = 0
    }
    
    $startTimeFormatted = $performanceMetrics.StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    Write-Verbose "=== Starting FetchAllUserRawData with ReportTime: $ReportTime  at $startTimeFormatted ==="
    Write-Verbose "Step 1: Fetching authentication method registration details..."
    $regById = @{}
    
    try {
        $regPath = "/reports/authenticationMethods/userRegistrationDetails"
        $regResponse = Invoke-GraphQueryWithMetrics -UrlPath $regPath -Operation "Fetch Registration Details" -PerformanceMetrics $performanceMetrics
        $registrationDetails = @($regResponse.Content.value)
        
        Write-Verbose "  Success: Retrieved $($registrationDetails.Count) registration records"
        
        # Build efficient lookup for registration data
        $registrationDetails | ForEach-Object {
            if ($_.id -and -not $regById.ContainsKey($_.id)) {
                $regById[$_.id] = $_
            }
        }
        Write-Verbose "  Success: Built lookup table for $($regById.Count) registration records"        
    } catch {
        Add-FunctionError -Message "Failed to fetch registration details from Microsoft Graph" -Exception $_.Exception -Category "GraphAPI" -ErrorList $ErrorList
    }
    
    # Step 2: Prepare break-glass account filtering
    Write-Verbose "Step 2: Preparing break-glass account filtering..."
        $bgUpns = @($FirstBreakGlassUPN, $SecondBreakGlassUPN) | 
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.ToLower() }
            
            # Use hashtable for O(1) lookup performance
            $bgUpnLookup = @{}
            $bgUpns | ForEach-Object { $bgUpnLookup[$_] = $true }
            
    if ($bgUpns.Count -gt 0) {
        $bgUpnList = $bgUpns -join ', '
        Write-Verbose "  -> Will filter out break-glass accounts: $bgUpnList"
    }
    
    # Step 3: Setup streaming user processing
    Write-Verbose "Step 3: Starting streaming user processing..."
    $selectFields = "displayName,id,userPrincipalName,mail,createdDateTime,userType,accountEnabled,signInActivity,customSecurityAttributes"
    $filterQuery = "accountEnabled eq true"
    $usersPath = "/users?$" + "select=$selectFields&$" + "filter=$filterQuery"

    # Step 4: True streaming - process and upload users page by page as they're fetched
    Write-Verbose "Step 4: True streaming user processing with page size $BatchSize..."
    
    # Create a context object with all variables needed by the callback
    $callbackContext = @{
        WorkSpaceID = $WorkSpaceID
        WorkspaceKey = $WorkspaceKey
        ReportTime = $ReportTime
        bgUpnLookup = $bgUpnLookup
        regById = $regById
        RetryConfig = $RetryConfig
        ErrorList = $ErrorList
        domainTenantCache = @{}  # Cache for guest domain → tenant ID mapping
    }
    
    # Define the callback function that processes each page immediately
    $processPageCallback = {
        param($pageData, $context)
        
        $pageNumber = $pageData.PageNumber
        $pageUsers = $pageData.Data
        $hasMore = $pageData.HasMore
        
        if (-not $pageUsers -or $pageUsers.Count -eq 0) {
            Write-Verbose "  -> Page $pageNumber : No users returned, skipping..."
            return @{ ProcessedCount = 0; UploadedCount = 0 }
        }
        
        Write-Verbose "  -> Page $pageNumber : Processing $($pageUsers.Count) users from Graph API..."
                
        # Filter out break-glass accounts from this page
        $filteredPageUsers = $pageUsers | Where-Object { 
            $upn = $_.userPrincipalName
            if ([string]::IsNullOrWhiteSpace($upn)) { 
                return $false 
            }
            
            $isNotBreakGlass = -not $context.bgUpnLookup.ContainsKey($upn.ToLower())
            if (-not $isNotBreakGlass) { 
                Write-Verbose "    Filtered out break-glass account: $upn" 
            }
            return $isNotBreakGlass
        }
        
        $filteredCount = $filteredPageUsers.Count
        $removedCount = $pageUsers.Count - $filteredCount
        if ($removedCount -gt 0) {
            Write-Verbose "  -> Page $pageNumber : Filtered $($pageUsers.Count) -> $filteredCount users (removed $removedCount break-glass accounts)"
        }
        
        if ($filteredCount -eq 0) {
            Write-Verbose "  -> Page $pageNumber : No users remaining after filtering, skipping upload..."
            return @{ ProcessedCount = $pageUsers.Count; UploadedCount = 0 }
        }
        
        # Process current page users
        $batchResults = $filteredPageUsers | ForEach-Object {
            $user = $_
            $registration = $context.regById[$user.id]
            $methods = @()
            $guardrailsExcluded = Test-GuardrailsMfaExclusion -User $user

            # Get home tenant ID for guest users using cache
            $homeTenantId = $null
            $homeTenantResolved = $false
            if ($user.userType -eq "Guest") {
                $domain = Get-GuestUserHomeDomain -UserPrincipalName $user.userPrincipalName -Mail $user.mail
                
                if ($domain) {
                    # Get from cache or resolve (with automatic caching)
                    $resolutionResult = Get-TenantIdWithCache -Domain $domain -Cache $context.domainTenantCache
                    $homeTenantId = $resolutionResult.TenantId
                    $homeTenantResolved = $resolutionResult.ResolutionSucceeded
                    Write-Verbose "    Guest user $($user.displayName) → domain: $domain → tenant: $homeTenantId → resolved: $homeTenantResolved"
                }
                else {
                    Write-Verbose "    Guest user $($user.displayName) → could not extract domain from UPN/mail"
                }
            }            
            
            if ($registration -and $registration.methodsRegistered) {
                $methods = @($registration.methodsRegistered)
            }
            
            [PSCustomObject]@{
                id                = $user.id
                userPrincipalName = $user.userPrincipalName
                displayName       = $user.displayName
                mail              = $user.mail
                createdDateTime   = $user.createdDateTime
                userType          = $user.userType
                homeTenantId      = $homeTenantId
                homeTenantResolved = $homeTenantResolved
                accountEnabled    = $user.accountEnabled
                signInActivity    = $user.signInActivity
                customSecurityAttributes = $user.customSecurityAttributes
                guardrailsExcludedMfa    = $guardrailsExcluded
                isMfaRegistered       = if ($registration) { $registration.isMfaRegistered } else { $null }
                isMfaCapable          = if ($registration) { $registration.isMfaCapable } else { $null }
                isSsprEnabled         = if ($registration) { $registration.isSsprEnabled } else { $null }
                isSsprRegistered      = if ($registration) { $registration.isSsprRegistered } else { $null }
                isSsprCapable         = if ($registration) { $registration.isSsprCapable } else { $null }
                isPasswordlessCapable = if ($registration) { $registration.isPasswordlessCapable } else { $null }
                defaultMethod         = if ($registration) { $registration.defaultMethod } else { $null }
                methodsRegistered     = $methods
                isSystemPreferredAuthenticationMethodEnabled = if ($registration) { $registration.isSystemPreferredAuthenticationMethodEnabled } else { $null }
                systemPreferredAuthenticationMethods = if ($registration) { $registration.systemPreferredAuthenticationMethods } else { $null }
                userPreferredMethodForSecondaryAuthentication = if ($registration) { $registration.userPreferredMethodForSecondaryAuthentication } else { $null }
                ReportTime        = $context.ReportTime
            }
        }
        
        Write-Verbose "  -> Page $pageNumber : Processing complete. $filteredCount records prepared for upload"        
        # Upload current page to Log Analytics
        Write-Verbose "  -> Page $pageNumber : Uploading $($batchResults.Count) records to Log Analytics..."
        
        $pageUploadSuccessful = $false
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                New-LogAnalyticsData -Data $batchResults -WorkSpaceID $context.WorkSpaceID -WorkSpaceKey $context.WorkspaceKey -LogType "GuardrailsUserRaw" | Out-Null
                $pageUploadSuccessful = $true
                Write-Verbose "  Success: Page $pageNumber upload successful on attempt $attempt"
                break
            }
            catch {
                if ($attempt -eq 3) {
                    $errorMsg = "Failed to upload page $pageNumber after 3 attempts: $($_.Exception.Message)"
                    Add-FunctionError -Message $errorMsg -Exception $_.Exception -Category "LogAnalytics" -ErrorList $context.ErrorList
                    throw [System.Exception]::new($errorMsg)
                } else {
                    $delay = Get-BackoffDelay -Attempt $attempt -Config $context.RetryConfig
                    Start-Sleep -Seconds $delay
                }
            }
        }
        
        if (-not $pageUploadSuccessful) {
            $errorMsg = "Failed to upload page $pageNumber after 3 attempts"
            Add-FunctionError -Message $errorMsg -Category "LogAnalytics" -ErrorList $context.ErrorList
            throw [System.Exception]::new($errorMsg)
        }
        
        # Progress reporting
        $statusMsg = if ($hasMore) { "more pages remaining..." } else { "final page" }
        Write-Verbose "  -> Page $pageNumber : Upload complete ($statusMsg)"
        
        return @{ 
            ProcessedCount = $pageUsers.Count
            UploadedCount = $batchResults.Count 
        }
    }
    
    try {
        # Use true streaming approach with callback processing        
        $streamResult = Invoke-GraphQueryStreamWithCallback -urlPath $usersPath -PageSize $BatchSize -ProcessPageCallback $processPageCallback -CallbackContext $callbackContext -PerformanceMetrics $performanceMetrics        
        $pageNumber = $streamResult.TotalPages
        $processedUsers = $streamResult.TotalProcessed
        $totalUploadedRecords = $streamResult.TotalUploaded
                
        $performanceMetrics.UsersProcessed = $processedUsers
        Write-Verbose "  Success: All pages processed and uploaded - $totalUploadedRecords total records uploaded from $pageNumber pages"
        
    } catch {
        Add-FunctionError -Message "Failed during streaming user processing" -Exception $_.Exception -Category "GraphAPI" -ErrorList $ErrorList
        return $ErrorList
    }
    
    # Step 5: Wait before verification to allow data ingestion and table creation
    Write-Verbose "Step 5: Waiting for data ingestion and table creation..."
    Write-Verbose "  -> Waiting 60 seconds to allow Log Analytics to create table and index data..."
    Write-Verbose "  -> Note: First-time table creation can take several minutes in Log Analytics"
    Start-Sleep -Seconds 60
    
    # Step 6: Verify data ingestion with robust error handling
    Write-Verbose "Step 6: Verifying data ingestion..."
    
    $dataIngested = $false
    $recordCount = 0
    $permissionError = $false
    $verificationSkipped = $false
    
    # First, check if we can access Log Analytics at all
    Write-Verbose "  -> Testing Log Analytics connectivity..."
    try {
        # Simple test query to check permissions and connectivity
        $testQuery = "Heartbeat | limit 1"
        $testResult = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkSpaceID -Query $testQuery -ErrorAction Stop
        Write-Verbose "  -> Log Analytics connectivity test successful"
    }
    catch {
        $errorMessage = $_.Exception.Message
        if ($errorMessage -like "*Forbidden*" -or $errorMessage -like "*403*" -or $errorMessage -like "*unauthorized*") {
            Write-Verbose "  -> Automation Account may need 'Log Analytics Reader' role on workspace $WorkSpaceID"
            $permissionError = $true
            $verificationSkipped = $true
        }
        elseif ($errorMessage -like "*BadRequest*" -or $errorMessage -like "*400*" -or $errorMessage -like "*Failed to resolve table*") {
            Write-Verbose "  -> The GuardrailsUserRaw_CL table may still be initializing after first data upload"
            Write-Verbose "  -> This typically resolves within 5-15 minutes of first deployment"
            $verificationSkipped = $true
        }
        else {
            Write-Verbose "  -> Will attempt data verification with reduced retry count"
        }
    }
    
    # Only attempt verification if connectivity test passed
    if (-not $verificationSkipped) {
        $maxVerificationAttempts = [Math]::Min($RetryConfig.MaxRetries, 6)  # Limit to 6 attempts max
        
        for ($attempt = 1; $attempt -le $maxVerificationAttempts; $attempt++) {
        $performanceMetrics.DataIngestionAttempts = $attempt
            
            # Use more robust query with error handling
            $query = @"
GuardrailsUserRaw_CL 
| where ReportTime_s == '$ReportTime'
| count
"@
            
            try {
                Write-Verbose "  -> Verification attempt $attempt/$maxVerificationAttempts : Querying Log Analytics..."
                
                # Use shorter timeout and explicit error handling
                $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkSpaceID -Query $query -ErrorAction Stop
                $recordCount = 0
            
                if ($result -and $result.Results) {
                    try {
                        # Direct access - if Count property exists, this will work
                        $recordCount = [int]$result.Results[0].Count
                    } catch {
                        # If direct access fails, the Count property doesn't exist as expected
                        $recordCount = 0
                    }
                }
            
                if ($recordCount -gt 0) {
                    Write-Verbose "  Success: Data ingestion verified - $recordCount records found for ReportTime '$ReportTime'"
                    $dataIngested = $true
                    break
                } else {
                    $delay = Get-BackoffDelay -Attempt $attempt -Config $RetryConfig
                        Write-Verbose "  -> Data not yet available (attempt $attempt/$maxVerificationAttempts). Waiting $delay seconds..."
                    
                        if ($attempt -lt $maxVerificationAttempts) {
                        Start-Sleep -Seconds $delay
                    }
                }
            
            } catch {
                $errorMessage = $_.Exception.Message
                $delay = Get-BackoffDelay -Attempt $attempt -Config $RetryConfig
                
                if ($errorMessage -like "*Forbidden*" -or $errorMessage -like "*403*" -or $errorMessage -like "*unauthorized*") {
                    Write-Warning "  Warning: Permission error on attempt $attempt : $errorMessage"
                    $permissionError = $true
                    break  # Don't retry permission errors
                } 
                elseif ($errorMessage -like "*BadRequest*" -or $errorMessage -like "*400*" -or $errorMessage -like "*Failed to resolve table*") {
                    if ($errorMessage -like "*Failed to resolve table*GuardrailsUserRaw_CL*") {
                        Write-Warning "  Warning: Table GuardrailsUserRaw_CL not yet available in Log Analytics."
                        Write-Verbose "  -> This is normal for first-time deployments - table creation can take 5-15 minutes"
                        Write-Verbose "  -> Data was uploaded successfully and will be available once indexing completes"
                        $verificationSkipped = $true
                    } else {
                        Write-Warning "  Warning: Query error on attempt $attempt : $errorMessage"
                        if ($attempt -eq $maxVerificationAttempts) {
                            Write-Verbose "  -> Query verification not available in this environment"
                            $verificationSkipped = $true
                        }
                    }
                    break  # Don't retry bad request errors
                }
                else {
                    Write-Warning "  Warning: Query attempt $attempt failed: $errorMessage"                    
                    if ($attempt -eq $maxVerificationAttempts) {
                        Write-Verbose "  -> Maximum verification attempts reached"
                    } elseif ($attempt -lt $maxVerificationAttempts) {
                        Write-Verbose "  -> Retrying in $delay seconds..."
                        Start-Sleep -Seconds $delay
                    }
                }
            }
        }
    }
    
    # Step 7: Final validation and reporting with graceful error handling
    Write-Verbose "Step 7: Final validation and reporting..."
    
    if ($verificationSkipped) {
        if ($permissionError) {
                Write-Warning "  Warning: Data verification skipped due to insufficient Log Analytics permissions."
                Write-Verbose "  -> Data upload completed successfully: $totalUploadedRecords records uploaded"
                Write-Verbose "  -> Consider granting 'Log Analytics Reader' role to the Automation Account for verification"
            } else {
                Write-Warning "  Warning: Data verification skipped - GuardrailsUserRaw_CL table not yet available."
                Write-Verbose "  -> Data upload completed successfully: $totalUploadedRecords records uploaded"
                Write-Verbose "  -> This is normal for first-time deployments - table creation can take 5-15 minutes"
                Write-Verbose "  -> Subsequent runs will be able to verify data once the table is established"
            }
            
        # Don't treat verification skip as a failure - data was uploaded successfully
        Write-Verbose "  Success: Data upload completed - $totalUploadedRecords records uploaded to Log Analytics"        
    } elseif ($permissionError) {
        # Permission error occurred during verification attempts
        Write-Warning "  Warning: Cannot verify data ingestion due to permission error."
        Write-Verbose "  -> Data upload completed: $totalUploadedRecords records uploaded"
        Write-Verbose "  -> Verification failed, but upload was successful"
            
        # Add a non-fatal warning rather than an error
        Add-FunctionError -Message "Data verification unavailable due to permissions. Upload completed successfully with $totalUploadedRecords records." -Category "Permissions" -ErrorList $ErrorList
        
    } elseif (-not $dataIngested) {
        # Verification was attempted but no data found
        Write-Warning "  Warning: Data ingestion verification failed - no records found in Log Analytics."
        Write-Verbose "  -> Uploaded $totalUploadedRecords records but verification query returned 0 results"
        Write-Verbose "  -> This may indicate data ingestion delay or indexing issues"
            
        Add-FunctionError -Message "Data ingestion verification failed. Uploaded $totalUploadedRecords records but verification query found 0 results. Data may still be processing." -Category "DataVerification" -ErrorList $ErrorList        
    } elseif ($recordCount -ne $totalUploadedRecords) {
            # Data found but count mismatch
        $expectedCount = $totalUploadedRecords
        Write-Warning "  Warning: Data count mismatch detected."
        Write-Verbose "  -> Expected: $expectedCount records, Found: $recordCount records"
            
        if ($recordCount > 0) {
            Write-Verbose "  -> Partial data ingestion detected - some records may still be processing"
            Add-FunctionError -Message "Data count mismatch: expected $expectedCount, found $recordCount records. Some data may still be processing." -Category "DataIntegrity" -ErrorList $ErrorList
        } else {
            Add-FunctionError -Message "Data count mismatch: expected $expectedCount, found $recordCount records. Data may be missing or still processing." -Category "DataIntegrity" -ErrorList $ErrorList
        }    
    } else {
        # Perfect success case
        Write-Verbose "  Success: Data ingestion verification successful - $recordCount records ingested and verified"
        Write-Verbose "  -> Upload and verification both completed successfully"
    }
    
    # Performance summary
    $stopwatch.Stop()
    $performanceMetrics.EndTime = Get-Date
    $performanceMetrics.TotalDurationMs = $stopwatch.ElapsedMilliseconds
    $performanceMetrics.TotalDurationMin = [Math]::Round($stopwatch.ElapsedMilliseconds / 60000, 2)
    
    Write-Verbose "=== Performance Summary ==="
    $durationMin = $performanceMetrics.TotalDurationMin
    $durationMs = $performanceMetrics.TotalDurationMs
    Write-Verbose "  Total Duration: $durationMin minutes ($durationMs ms)"
    Write-Verbose "  Users Processed: $($performanceMetrics.UsersProcessed)"
    Write-Verbose "  Records Uploaded: $totalUploadedRecords"
    Write-Verbose "  Page Size: $BatchSize"
    Write-Verbose "  Total Pages: $pageNumber"
    Write-Verbose "  Graph API Calls: $($performanceMetrics.GraphApiCalls)"
    Write-Verbose "  Data Ingestion Attempts: $($performanceMetrics.DataIngestionAttempts)"
    Write-Verbose "  Errors: $($ErrorList.Count)"
    
    if ($ErrorList.Count -eq 0) {
        Write-Verbose "  Success: Function completed successfully with no errors!"
    } else {
        $errorCount = $ErrorList.Count
        Write-Verbose "  Warning: Function completed with $errorCount errors/warnings"
    }
    
    Write-Verbose "=== FetchAllUserRawData Complete ==="
    
    return $ErrorList
}

# ============================================================================
# Guest User Cross-Tenant MFA Trust Functions
# ============================================================================

# Function to extract domain from guest user UPN or email
function Get-GuestUserHomeDomain {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string] $UserPrincipalName,
        
        [Parameter(Mandatory=$false)]
        [string] $Mail
    )
    
    # Extract domain from UPN (format: user_domain.com#EXT#@hosttenant.com)
    # Use greedy match (.*_) to capture from the LAST underscore before #EXT#
    if ($UserPrincipalName -match '.*_([^_#]+)#EXT#') {
        return $Matches[1]
    }
    # Or extract from mail
    elseif ($Mail -and $Mail -match '@(.+)$') {
        return $Matches[1]
    }
    
    return $null
}

# Function to resolve tenant ID from domain (single domain)
# Returns a PSCustomObject with TenantId and ResolutionSucceeded properties
# Includes retry logic for transient failures (DNS timeout, throttling, 5xx errors)
function Resolve-TenantIdFromDomain {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string] $Domain,
        
        [Parameter(Mandatory=$false)]
        [int] $MaxRetries = 3,
        
        [Parameter(Mandatory=$false)]
        [int] $InitialDelayMs = 500
    )
    
    $attempt = 0
    $delay = $InitialDelayMs
    
    while ($attempt -lt $MaxRetries) {
        $attempt++
        
        try {
            # Use OpenID Connect discovery endpoint (public, no auth required)
            $tenantUrl = "https://login.microsoftonline.com/$Domain/.well-known/openid-configuration"
            
            if ($attempt -eq 1) {
                Write-Verbose "  Resolving tenant ID for domain: $Domain"
            } else {
                Write-Verbose "  Retry attempt $attempt/$MaxRetries for domain: $Domain"
            }
            
            $response = Invoke-RestMethod -Uri $tenantUrl -Method Get -ErrorAction Stop -TimeoutSec 10
            
            if ($response.token_endpoint -match 'https://login\.microsoftonline\.com/([a-f0-9-]+)/') {
                $tenantId = $Matches[1]
                Write-Verbose "Resolved $Domain → $tenantId (attempt $attempt)"
                return [PSCustomObject]@{
                    TenantId = $tenantId
                    ResolutionSucceeded = $true
                }
            }
            
            # Regex didn't match - this is a permanent failure (bad response format)
            Write-Verbose "Invalid response format for domain: $Domain"
            return [PSCustomObject]@{
                TenantId = $null
                ResolutionSucceeded = $false
            }
            
        }
        catch {
            # NOTE: Invoke-RestMethod throws exceptions for HTTP error codes (4xx, 5xx) by default
            # This catch block handles: 404, 429, 500, 503, timeouts, network errors, etc.
            
            $errorMessage = $_.Exception.Message
            $statusCode = $null
            $isTransient = $false
            
            # Extract HTTP status code if available (works for both PS 5.1 and PS 7+)
            if ($_.Exception.Response) {
                # Try direct property first (PS 7+)
                if ($_.Exception.Response.StatusCode.Value__) {
                    $statusCode = [int]$_.Exception.Response.StatusCode.Value__
                }
                # Fallback to casting (PS 5.1)
                else {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }
            }
            elseif ($_.Exception.InnerException.Response) {
                # Check inner exception (some network stacks wrap the exception)
                if ($_.Exception.InnerException.Response.StatusCode.Value__) {
                    $statusCode = [int]$_.Exception.InnerException.Response.StatusCode.Value__
                }
                else {
                    $statusCode = [int]$_.Exception.InnerException.Response.StatusCode
                }
            }
            
            # Classify error based on status code (most reliable)
            if ($statusCode) {
                Write-Verbose "HTTP $statusCode for domain: $Domain (attempt $attempt/$MaxRetries)"
                
                switch ($statusCode) {
                    # 2xx - Success (shouldn't reach here, but handle gracefully)
                    { $_ -ge 200 -and $_ -lt 300 } {
                        Write-Verbose "Unexpected: Got HTTP $statusCode but entered catch block"
                        $isTransient = $false
                    }
                    # 4xx - Client errors (permanent, except 429)
                    429 {
                        # Too Many Requests - transient, should retry
                        $isTransient = $true
                        Write-Verbose "Rate limited (429) for domain: $Domain"
                    }
                    404 {
                        # Not Found - domain/tenant doesn't exist (permanent)
                        Write-Verbose "Domain not found (404): $Domain"
                        return [PSCustomObject]@{
                            TenantId = $null
                            ResolutionSucceeded = $false
                        }
                    }
                    { $_ -ge 400 -and $_ -lt 500 } {
                        # Other 4xx - permanent errors (bad request, unauthorized, forbidden, etc.)
                        Write-Verbose "Client error ($statusCode) for domain: $Domain"
                        return [PSCustomObject]@{
                            TenantId = $null
                            ResolutionSucceeded = $false
                        }
                    }
                    # 5xx - Server errors (transient, should retry)
                    { $_ -ge 500 -and $_ -lt 600 } {
                        $isTransient = $true
                        Write-Verbose "Server error ($statusCode) for domain: $Domain"
                    }
                    # Unexpected status code
                    default {
                        $isTransient = $true
                        Write-Verbose "Unexpected status code ($statusCode) for domain: $Domain"
                    }
                }
            }
            # No status code - likely network/DNS/timeout issue (transient)
            else {
                $isTransient = $true
                Write-Verbose "Network/timeout error for domain $Domain (attempt $attempt/$MaxRetries): $errorMessage"
            }
            
            # If this is the last attempt, fail
            if (!$isTransient -or $attempt -ge $MaxRetries) {
                Write-Verbose "Failed to resolve tenant ID for domain: $Domain after $attempt attempt(s)"
                return [PSCustomObject]@{
                    TenantId = $null
                    ResolutionSucceeded = $false
                }
            }
            
            # Wait before retry with exponential backoff
            Write-Verbose "Waiting ${delay}ms before retry..."
            Start-Sleep -Milliseconds $delay
            $delay = $delay * 2  # Exponential backoff
        }
    }
    
    # Shouldn't reach here, but handle edge case
    Write-Verbose "Failed to resolve tenant ID for domain: $Domain (max retries exceeded)"
    return [PSCustomObject]@{
        TenantId = $null
        ResolutionSucceeded = $false
    }
}

# Function to get or resolve tenant ID with lazy caching
# Returns a PSCustomObject with TenantId and ResolutionSucceeded properties
function Get-TenantIdWithCache {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string] $Domain,
        
        [Parameter(Mandatory=$true)]
        [hashtable] $Cache
    )
    
    # Check cache first
    if ($Cache.ContainsKey($Domain)) {
        return $Cache[$Domain]
    }
    
    # Not in cache, resolve it
    Write-Verbose "  Cache miss for domain: $Domain, resolving..."
    $result = Resolve-TenantIdFromDomain -Domain $Domain
    
    # Store in cache (even if resolution failed, to avoid retrying failed lookups)
    $Cache[$Domain] = $result
    
    return $result
}

# Function to get cross-tenant access settings for B2B collaboration
function Get-CrossTenantAccessSettings {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [hashtable] $PerformanceMetrics = $null
    )
    
    $ErrorList = [System.Collections.Generic.List[string]]::new()
    $crossTenantSettings = @()
    
    try {
        Write-Verbose "Fetching cross-tenant access settings..."
        
        # Get default cross-tenant access settings
        $defaultSettingsPath = "/policies/crossTenantAccessPolicy/default"
        try {
            $defaultResponse = Invoke-GraphQueryWithMetrics -UrlPath $defaultSettingsPath -Operation "Fetch Default Cross-Tenant Access Settings" -PerformanceMetrics $PerformanceMetrics
            $defaultSettings = $defaultResponse.Content
            
            if ($defaultSettings) {
                Write-Verbose "  Retrieved default cross-tenant access settings"
                $crossTenantSettings += [PSCustomObject]@{
                    PartnerTenantId = "default"
                    InboundTrustMfa = $defaultSettings.inboundTrust.isMfaAccepted
                    InboundTrustCompliantDevice = $defaultSettings.inboundTrust.isCompliantDeviceAccepted
                    InboundTrustHybridAzureADJoined = $defaultSettings.inboundTrust.isHybridAzureADJoinedDeviceAccepted
                    IsDefault = $true
                }
            }
        } catch {
            Add-FunctionError -Message "Failed to fetch default cross-tenant access settings: $($_.Exception.Message)" -Exception $_.Exception -Category "GraphAPI" -ErrorList $ErrorList
        }
        
        # Get partner-specific cross-tenant access settings
        $partnerSettingsPath = "/policies/crossTenantAccessPolicy/partners"
        try {
            $partnerResponse = Invoke-GraphQueryWithMetrics -UrlPath $partnerSettingsPath -Operation "Fetch Partner Cross-Tenant Access Settings" -PerformanceMetrics $PerformanceMetrics
            $partnerSettings = @($partnerResponse.Content.value)
            
            Write-Verbose "  Retrieved $($partnerSettings.Count) partner-specific cross-tenant access settings"
            
            foreach ($partner in $partnerSettings) {
                $crossTenantSettings += [PSCustomObject]@{
                    PartnerTenantId = $partner.tenantId
                    InboundTrustMfa = $partner.inboundTrust.isMfaAccepted
                    InboundTrustCompliantDevice = $partner.inboundTrust.isCompliantDeviceAccepted
                    InboundTrustHybridAzureADJoined = $partner.inboundTrust.isHybridAzureADJoinedDeviceAccepted
                    IsDefault = $false
                }
            }
        } catch {
            Add-FunctionError -Message "Failed to fetch partner cross-tenant access settings: $($_.Exception.Message)" -Exception $_.Exception -Category "GraphAPI" -ErrorList $ErrorList
        }
        
    } catch {
        Add-FunctionError -Message "Unexpected error fetching cross-tenant access settings: $($_.Exception.Message)" -Exception $_.Exception -Category "GraphAPI" -ErrorList $ErrorList
    }
    
    return [PSCustomObject]@{
        Settings = $crossTenantSettings
        ErrorList = $ErrorList
    }
}

# Function to check if conditional access policies require MFA for guest users
function Test-GuestMfaConditionalAccessPolicy {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [hashtable] $PerformanceMetrics = $null
    )
    
    $ErrorList = [System.Collections.Generic.List[string]]::new()
    $hasGuestMfaPolicy = $false
    $matchingPolicies = @()
    
    try {
        Write-Verbose "Checking conditional access policies for guest MFA requirements..."
        
        $capPath = "/identity/conditionalAccess/policies"
        $capResponse = Invoke-GraphQueryWithMetrics -UrlPath $capPath -Operation "Fetch Conditional Access Policies" -PerformanceMetrics $PerformanceMetrics
        $policies = @($capResponse.Content.value)
        
        Write-Verbose "  Analyzing $($policies.Count) conditional access policies..."
        
        # Check for policies that meet these criteria:
        # 1. State = 'enabled'
        # 2. Includes guest/external users OR includes all users
        # 3. Does NOT explicitly exclude guest/external users
        # 4. Requires MFA
        $matchingPolicies = $policies | Where-Object {
            $_.state -eq 'enabled' -and
            $_.grantControls.builtInControls -contains 'mfa' -and
            (
                # Either targets all users (which includes guests)
                ($_.conditions.users.includeUsers -contains 'All') -or
                # Or specifically targets guest/external users
                ($null -ne $_.conditions.users.includeGuestsOrExternalUsers -and
                 $_.conditions.users.includeGuestsOrExternalUsers.guestOrExternalUserTypes -match 'b2bCollaborationGuest|b2bCollaborationMember|internalGuest')
            ) -and
            # Ensure guests are NOT explicitly excluded
            ($null -eq $_.conditions.users.excludeGuestsOrExternalUsers -or
             $_.conditions.users.excludeGuestsOrExternalUsers.guestOrExternalUserTypes -notmatch 'b2bCollaborationGuest|b2bCollaborationMember|internalGuest')
        }
        
        if ($matchingPolicies.Count -gt 0) {
            $hasGuestMfaPolicy = $true
            Write-Verbose "  Found $($matchingPolicies.Count) conditional access policies requiring MFA for guest users"
            foreach ($policy in $matchingPolicies) {
                Write-Verbose "    - Policy: $($policy.displayName)"
            }
        } else {
            Write-Verbose "  No conditional access policies found requiring MFA for guest users"
        }
        
    } catch {
        Add-FunctionError -Message "Failed to check conditional access policies for guest MFA: $($_.Exception.Message)" -Exception $_.Exception -Category "GraphAPI" -ErrorList $ErrorList
    }
    
    return [PSCustomObject]@{
        HasGuestMfaPolicy = $hasGuestMfaPolicy
        MatchingPolicies = $matchingPolicies
        ErrorList = $ErrorList
    }
}

# Function to collect and upload cross-tenant access and guest MFA policy data to Log Analytics
function Upload-CrossTenantAccessData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string] $ReportTime,
        
        [Parameter(Mandatory=$true)]
        [string] $WorkSpaceID,
        
        [Parameter(Mandatory=$true)]
        [string] $WorkspaceKey,
        
        [Parameter(Mandatory=$false)]
        [hashtable] $PerformanceMetrics = $null
    )
    
    $ErrorList = [System.Collections.Generic.List[string]]::new()
    
    try {
        Write-Verbose "=== Starting Cross-Tenant Access Data Collection ==="
        
        # Get cross-tenant access settings
        $crossTenantResult = Get-CrossTenantAccessSettings -PerformanceMetrics $PerformanceMetrics
        if ($crossTenantResult.ErrorList.Count -gt 0) {
            $crossTenantResult.ErrorList | ForEach-Object { $ErrorList.Add($_) }
        }
        
        # Check guest MFA conditional access policies
        $guestMfaPolicyResult = Test-GuestMfaConditionalAccessPolicy -PerformanceMetrics $PerformanceMetrics
        if ($guestMfaPolicyResult.ErrorList.Count -gt 0) {
            $guestMfaPolicyResult.ErrorList | ForEach-Object { $ErrorList.Add($_) }
        }
        
        # Prepare data for upload
        $crossTenantData = @()
        
        # Upload cross-tenant access settings
        foreach ($setting in $crossTenantResult.Settings) {
            $crossTenantData += [PSCustomObject]@{
                ReportTime = $ReportTime
                PartnerTenantId = $setting.PartnerTenantId
                InboundTrustMfa = $setting.InboundTrustMfa
                InboundTrustCompliantDevice = $setting.InboundTrustCompliantDevice
                InboundTrustHybridAzureADJoined = $setting.InboundTrustHybridAzureADJoined
                IsDefault = $setting.IsDefault
                HasGuestMfaPolicy = $guestMfaPolicyResult.HasGuestMfaPolicy
            }
        }
        
        # If no settings found, upload a single record indicating the state
        if ($crossTenantData.Count -eq 0) {
            $crossTenantData += [PSCustomObject]@{
                ReportTime = $ReportTime
                PartnerTenantId = "none"
                InboundTrustMfa = $false
                InboundTrustCompliantDevice = $false
                InboundTrustHybridAzureADJoined = $false
                IsDefault = $true
                HasGuestMfaPolicy = $guestMfaPolicyResult.HasGuestMfaPolicy
            }
        }
        
        # Upload to Log Analytics
        Write-Verbose "Uploading cross-tenant access data to Log Analytics..."
        try {
            New-LogAnalyticsData -Data $crossTenantData -WorkSpaceID $WorkSpaceID -WorkSpaceKey $WorkspaceKey -LogType "GuardrailsCrossTenantAccess" | Out-Null
            Write-Verbose "  Success: Cross-tenant access data uploaded successfully"
        } catch {
            Add-FunctionError -Message "Failed to upload cross-tenant access data: $($_.Exception.Message)" -Exception $_.Exception -Category "LogAnalytics" -ErrorList $ErrorList
        }
        
        Write-Verbose "=== Cross-Tenant Access Data Collection Complete ==="
        
    } catch {
        Add-FunctionError -Message "Unexpected error during cross-tenant access data collection: $($_.Exception.Message)" -Exception $_.Exception -Category "General" -ErrorList $ErrorList
    }
    
    return $ErrorList
}