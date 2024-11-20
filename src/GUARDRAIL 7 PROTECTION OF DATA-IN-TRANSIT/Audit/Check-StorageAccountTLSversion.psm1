function Check-TLSversion {
    param (
        [System.Object] $objList,
        [string] $ControlName,
        [string] $ItemName,
        [string] $LogType,
        [string] $itsgcode,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string] $ReportTime 
    )

    $storageAccountList = @()
    foreach ($subscription in $objList)
    {
        Set-AzContext -SubscriptionId $subscription.Id
        $resourceGroups = Get-AzResourceGroup

        # Loop through each resource group
        foreach ($resourceGroup in $resourceGroups) {
            $storageAccounts = Get-AzStorageAccount -ResourceGroupName $resourceGroup.ResourceGroupName
            if ($storageAccounts.Count -ne 0){
                foreach ($storageAccount in $storageAccounts) {
                    $TLSversionNumeric = $storageAccount.MinimumTlsVersion -replace "TLS", "" -replace "_", "." 
                    $storageAccInfo = [PSCustomObject]@{
                        SubscriptionName   = $subscription.Name
                        ResourceGroupName  = $resourceGroup.ResourceGroupName
                        StorageAccountName = $storageAccount.StorageAccountName
                        MinimumTlsVersion  = $storageAccount.MinimumTlsVersion
                        TLSversionNumeric  = $TLSversionNumeric
                    }
                    $storageAccountList +=  $storageAccInfo
                }
            }
        }
    }

    return $storageAccountList | Format-Table
}

function Verify-TLSForStorageAccount {
    param (
            [string] $ControlName,
            [string] $ItemName,
            [string] $PolicyID, 
            [string] $itsgcode,
            [hashtable] $msgTable,
            [Parameter(Mandatory=$true)]
            [string] $ReportTime,
            [Parameter(Mandatory=$false)]
            [string] $CBSSubscriptionName,
            [string] $CloudUsageProfiles = "3",  # Passed as a string
            [string] $ModuleProfiles,  # Passed as a string
            [switch] $EnableMultiCloudProfiles # New feature flag, default to false    
    )
    $IsCompliant = $false
    [PSCustomObject] $PSObjectList = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList

    #Check Subscriptions
    try {
        $objs = Get-AzSubscription -ErrorAction Stop | Where-Object {$_.State -eq "Enabled"} 
    }
    catch {
        $Errorlist.Add("Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_")
        throw "Error: Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_"
    }

    $PSObjectList = Check-TLSversion -objList $objs -ControlName $ControlName -ItemName $ItemName -LogType $LogType -itsgcode $itsgcode -msgTable $msgTable -ReportTime $ReportTime 

    # Filter to keep only objects that have the 'subscriptionName' property
    $PSObjectListCleaned = $PSObjectList | Where-Object { $_.PSObject.Properties["SubscriptionName"] }

    # find TLS version not equal to TLS1.2
    $filteredPSObjectList = $PSObjectListCleaned | Where-Object { $_.MinimumTlsVersion -ne "TLS1_2" }

    # Condition: all storage accounts are using TLS1.2
    if ($filteredPSObjectList.Count -eq 0){
        $IsCompliant = $true
        $Comments = $msgTable.isCompliant + " " + $msgTable.storageAccValidTLS
    }
    else{
        # Condition: isTLSLessThan1_2 = true if the TLSversionNumeric < 1.2
        $filteredPSObjectList | Add-Member -MemberType NoteProperty -Name isTLSLessThan1_2 -Value (
            $filteredPSObjectList.TLSversionNumeric -lt 1.2
        )
        $filteredPSObjectList | ForEach-Object {
            $_ | Add-Member -MemberType NoteProperty -Name isTLSLessThan1_2 -Value ($_.TLSversionNumeric -lt 1.2)
            $_  
        }
        $storageAccWithTLSLessThan1_2 = $filteredPSObjectList | Where-Object { $_.IsTLSLessThan1_2 -eq $true }

        # condition: storage accounts are all using TLS version 1.2 or higher
        if ($storageAccWithTLSLessThan1_2.Count = 0){
            $IsCompliant = $true
            $Comments = $msgTable.isCompliant + " " + $msgTable.storageAccValidTLS
        }
        else{
            ## keep a record for non-compliant storage acc names for reference
            $nonCompliantstorageAccountNames = ($storageAccWithTLSLessThan1_2 | Select-Object -ExpandProperty StorageAccountName | ForEach-Object { $_ } ) -join ', '
            Write-Host "Storage accounts which are using TLS1.1 or less: $nonCompliantstorageAccountNames"
            $IsCompliant = $false
            $Comments = $msgTable.isNotCompliant + " " + $msgTable.storageAccNotValidTLS
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

    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }

    return $moduleOutput  
}

