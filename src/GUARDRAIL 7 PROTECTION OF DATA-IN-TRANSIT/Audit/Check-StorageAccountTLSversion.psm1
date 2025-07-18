function Check-TLSversion {
    param (
        [System.Object] $objList
    )

    Write-Verbose "Starting subscription access verification..."
    
    $storageAccountList = @()
    foreach ($obj in $objList)
    {
        Write-Verbose "Processing Subscription: $($obj.Name) ($($obj.Id))" 

        try {
            # Simplified query to match exactly what we see in Resource Graph
            $query = @"
            resources
            | where type =~ 'Microsoft.Storage/storageAccounts'
            | where subscriptionId =~ '$($obj.Id)'
            | extend minimumTlsVersion = properties.minimumTlsVersion
            | project subscriptionId,
                     resourceGroup = resourceGroup,
                     name,
                     minimumTlsVersion
"@
            
            Write-Verbose "Executing Resource Graph query for subscription: $($obj.Id)"
            $storageAccounts = Search-azgraph -Query $query -ErrorAction Stop
            Write-Verbose "Found $($storageAccounts.Count) storage accounts in subscription"
            
            foreach ($storageAcc in $storageAccounts) {
                Write-Verbose "Processing storage account: $($storageAcc.name)"
                $TLSversionNumeric = $storageAcc.minimumTlsVersion -replace "TLS", "" -replace "_", "."
                $storageAccInfo = [PSCustomObject]@{
                    SubscriptionName   = $obj.Name
                    ResourceGroupName  = $storageAcc.resourceGroup
                    StorageAccountName = $storageAcc.name
                    MinimumTlsVersion = $storageAcc.minimumTlsVersion
                    TLSversionNumeric  = $TLSversionNumeric
                }
                $storageAccountList += $storageAccInfo
            }
        }
        catch {
            Write-Warning "Failed to query storage accounts for subscription '$($obj.Name)': $_"
            continue
        }
    }

    if ($storageAccountList.Count -eq 0) {
        Write-Verbose "No storage accounts found. Current subscription context: $((Get-AzContext).Subscription.Id)"
        Write-Verbose "Number of subscriptions checked: $($objList.Count)"
        Write-Verbose "Subscription IDs checked: $($objList.Id -join ', ')"
    }

    Write-Verbose "Total storage accounts found across all subscriptions: $($storageAccountList.Count)"
    return $storageAccountList
}

function Verify-TLSForStorageAccount {
    param (
        [string] $ControlName,
        [string] $ItemName,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string] $ReportTime,
        [string] $itsgcode,
        [string] $CloudUsageProfiles = "3",
        [string] $ModuleProfiles,
        [switch] $EnableMultiCloudProfiles
    )
    
    # Initialize all arrays and objects at the start
    $IsCompliant = $false
    $PSObjectList = @()
    $ErrorList = [System.Collections.ArrayList]::new()
    $AdditionalResults = @()
    $commentsArray = @()
    
    # Initialize moduleOutput at the start
    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = $null
        Errors = $ErrorList
        AdditionalResults = $AdditionalResults
    }

    try {
        $objs = Get-AzSubscription -ErrorAction Stop | Where-Object {$_.State -eq "Enabled"} 
        if (-not $objs) {
            $errorMsg = "No enabled subscriptions found"
            $ErrorList.Add($errorMsg) | Out-Null
            Write-Warning $errorMsg
            return $moduleOutput
        }
    }
    catch {
        $errorMsg = "Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installation of the Az.Resources module; returned error message: $_"
        $ErrorList.Add($errorMsg) | Out-Null
        Write-Warning $errorMsg
        return $moduleOutput
    }

    try {
        $PSObjectList = Check-TLSversion -objList $objs 
        if ($null -eq $PSObjectList) {
            $errorMsg = "No storage accounts found to evaluate"
            $ErrorList.Add($errorMsg) | Out-Null
            Write-Warning $errorMsg
            return $moduleOutput
        }

        # Filter valid objects and check TLS compliance in one pass
        $nonCompliantAccounts = $PSObjectList | 
            Where-Object { $_.PSObject.Properties["MinimumTlsVersion"] } |
            Where-Object { 
                $_.MinimumTlsVersion -ne "TLS1_2" -and 
                $_.TLSversionNumeric -lt 1.2 
            }

        if ($nonCompliantAccounts.Count -eq 0) {
            $IsCompliant = $true
            $commentsArray = @($msgTable.isCompliant, $msgTable.storageAccValidTLS)
        }
        else {
            $IsCompliant = $false
            $nonCompliantStorageAccountNames = ($nonCompliantAccounts | 
                Select-Object -ExpandProperty StorageAccountName) -join ', '
            Write-Verbose "Storage accounts which are using TLS1.1 or less: $nonCompliantStorageAccountNames"
            $commentsArray = @($msgTable.isNotCompliant, $msgTable.storageAccNotValidTLS, $msgTable.storageAccNotValidList -f $nonCompliantStorageAccountNames)
        }
    }
    catch {
        $errorMsg = "Error creating compliance result: $_"
        $ErrorList.Add($errorMsg) | Out-Null
        Write-Warning $errorMsg
        return $moduleOutput
    }

    $Comments = $commentsArray -join " "
    
    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        ItemName         = $ItemName
        Comments         = $Comments
        ReportTime      = $ReportTime
        itsgcode        = $itsgcode
    }

    # Conditionally add the Profile field based on the feature flag
    if ($EnableMultiCloudProfiles) {
        $result = Add-ProfileInformation -Result $PsObject -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId
        Write-Host "$result"
    }

    $moduleOutput.ComplianceResults = $PsObject
    $moduleOutput.Errors = $ErrorList
    $moduleOutput.AdditionalResults = $AdditionalResults

    return $moduleOutput
}

