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
            # Resource Graph query for this specific subscription
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
            
            $storageAccounts = Search-AzGraph -Query $query
            
            foreach ($storageAcc in $storageAccounts) {
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
            [string] $CloudUsageProfiles = "3",  # Passed as a string
            [string] $ModuleProfiles,  # Passed as a string
            [switch] $EnableMultiCloudProfiles # New feature flag, default to false    
    )
    $IsCompliant = $false
    [PSCustomObject] $PSObjectList = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList

    $commentsArray = @()

    #Check Subscriptions
    try {
        $objs = Get-AzSubscription -ErrorAction Stop | Where-Object {$_.State -eq "Enabled"} 
    }
    catch {
        $Errorlist.Add("Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_")
        throw "Error: Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_"
    }

    $PSObjectList = @()
    try{
        $PSObjectList = Check-TLSversion -objList $objs 

        # Filter to keep only objects that have the 'subscriptionName' property
        $PSObjectListCleaned = $PSObjectList | Where-Object { $_.PSObject.Properties["MinimumTlsVersion"] }

        # find TLS version not equal to TLS1.2
        $filteredPSObjectList = $PSObjectListCleaned | Where-Object { $_.MinimumTlsVersion -ne "TLS1_2" }

        # Condition: all storage accounts are using TLS1.2
        if ($filteredPSObjectList.Count -eq 0){
            $IsCompliant = $true
            $commentsArray = $msgTable.isCompliant + " " + $msgTable.storageAccValidTLS
        }
        else{
            # Condition: isTLSLessThan1_2 = true if the TLSversionNumeric < 1.2
            $filteredPSObjectList | ForEach-Object {
                $_ | Add-Member -MemberType NoteProperty -Name isTLSLessThan1_2 -Value ($_.TLSversionNumeric -lt 1.2)
            }

            $storageAccWithTLSLessThan1_2 = $filteredPSObjectList | Where-Object { $_.IsTLSLessThan1_2 -eq $true }

            # condition: storage accounts are all using TLS version 1.2 or higher
            if ($storageAccWithTLSLessThan1_2.Count -eq 0){
                $IsCompliant = $true
                $commentsArray = $msgTable.isCompliant + " " + $msgTable.storageAccValidTLS
            }
            else{
                ## keep a record for non-compliant storage acc names for reference
                $nonCompliantstorageAccountNames = ($storageAccWithTLSLessThan1_2 | Select-Object -ExpandProperty StorageAccountName | ForEach-Object { $_ } ) -join ', '
                Write-Verbose "Storage accounts which are using TLS1.1 or less: $nonCompliantstorageAccountNames"
                $IsCompliant = $false
                $commentsArray = $msgTable.isNotCompliant + " " + $msgTable.storageAccNotValidTLS
            }
        }
    }
    catch{
        $Errorlist.Add("Error creating compliance result: $_")
        throw "Error: $_"
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
        $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        if (!$evalResult.ShouldEvaluate) {
            if ($evalResult.Profile -gt 0) {
                $PsObject.ComplianceStatus = "Not Applicable"
                $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                $PsObject.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
            } else {
                $ErrorList.Add("Error occurred while evaluating profile configuration")
            }
        } else {
            
            $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
        }
    }

    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors = $ErrorList
        AdditionalResults = $AdditionalResults
    }

    return $moduleOutput
}

