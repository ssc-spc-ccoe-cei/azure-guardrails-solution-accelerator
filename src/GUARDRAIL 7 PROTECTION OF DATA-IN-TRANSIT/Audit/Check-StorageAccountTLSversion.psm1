function Check-TLSversion {
    param (
        [System.Object] $objList
    )

    Write-Verbose "Starting subscription access verification..."
    
    $storageAccountList = [System.Collections.Generic.List[PSCustomObject]]::new()
    $subscriptionIds = [string[]]@($objList.Id)

    # O(1) lookup for subscription name by ID
    $subscriptionNameMap = @{}
    foreach ($obj in $objList) {
        $subscriptionNameMap[$obj.Id] = $obj.Name
    }

    try {
        # Single batched query across all subscriptions instead of N separate calls
        $query = @"
        resources
        | where type =~ 'Microsoft.Storage/storageAccounts'
        | extend minimumTlsVersion = properties.minimumTlsVersion
        | project subscriptionId,
                 resourceGroup = resourceGroup,
                 name,
                 minimumTlsVersion
"@
        
        Write-Verbose "Executing Resource Graph query across $($subscriptionIds.Count) subscriptions"
        
        $skipToken = $null
        do {
            $graphParams = @{
                Query        = $query
                Subscription = $subscriptionIds
                First        = 1000
                ErrorAction  = 'Stop'
            }
            if ($skipToken) { $graphParams['SkipToken'] = $skipToken }
            
            $storageAccounts = Search-AzGraph @graphParams
            
            foreach ($storageAcc in $storageAccounts) {
                Write-Verbose "Processing storage account: $($storageAcc.name)"
                $storageAccountList.Add([PSCustomObject]@{
                    SubscriptionName   = $subscriptionNameMap[$storageAcc.subscriptionId]
                    ResourceGroupName  = $storageAcc.resourceGroup
                    StorageAccountName = $storageAcc.name
                    MinimumTlsVersion  = $storageAcc.minimumTlsVersion
                    TLSversionNumeric  = ($storageAcc.minimumTlsVersion -replace "TLS", "" -replace "_", ".")
                })
            }
            
            $skipToken = $storageAccounts.SkipToken
            Write-Verbose "Page returned $($storageAccounts.Count) storage accounts, SkipToken: $($null -ne $skipToken)"
        } while ($skipToken)
    }
    catch {
        Write-Warning "Failed to query storage accounts: $_"
    }

    if ($storageAccountList.Count -eq 0) {
        Write-Verbose "No storage accounts found. Current subscription context: $((Get-AzContext).Subscription.Id)"
        Write-Verbose "Number of subscriptions checked: $($objList.Count)"
        Write-Verbose "Subscription IDs checked: $($subscriptionIds -join ', ')"
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
    
    $ObjectList = [System.Collections.Generic.List[PSCustomObject]]::new()
    $ErrorList = [System.Collections.Generic.List[string]]::new()
    $AdditionalResults = @()
    
    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = $null
        Errors = $ErrorList
        AdditionalResults = $AdditionalResults
    }

    try {
        $objs = Get-AzSubscription -ErrorAction Stop | Where-Object {$_.State -eq "Enabled"} 
        if (-not $objs) {
            $errorMsg = "No enabled subscriptions found"
            $ErrorList.Add($errorMsg)
            Write-Warning $errorMsg
            return $moduleOutput
        }
    }
    catch {
        $errorMsg = "Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installation of the Az.Resources module; returned error message: $_"
        $ErrorList.Add($errorMsg)
        Write-Warning $errorMsg
        return $moduleOutput
    }

    try {
        $allStorageAccounts = Check-TLSversion -objList $objs

        # Pre-group storage accounts by subscription name for O(1) lookup
        $storageBySubscription = @{}
        foreach ($sa in $allStorageAccounts) {
            $subName = $sa.SubscriptionName
            if (-not $storageBySubscription.ContainsKey($subName)) {
                $storageBySubscription[$subName] = [System.Collections.Generic.List[PSCustomObject]]::new()
            }
            $storageBySubscription[$subName].Add($sa)
        }

        foreach ($obj in $objs) {
            $IsCompliant = $false

            # O(1) hashtable lookup instead of O(n) Where-Object filter
            $subStorageAccounts = $storageBySubscription[$obj.Name]

            if (-not $subStorageAccounts -or $subStorageAccounts.Count -eq 0) {
                $IsCompliant = $true
                $commentsArray = @($msgTable.isCompliant, $msgTable.storageAccValidTLS)
            }
            else {
                # .Where() method avoids pipeline overhead
                $nonCompliantAccounts = $subStorageAccounts.Where({
                    $_.PSObject.Properties["MinimumTlsVersion"] -and
                    $_.MinimumTlsVersion -ne "TLS1_2" -and 
                    $_.TLSversionNumeric -lt 1.2 
                })

                if ($nonCompliantAccounts.Count -eq 0) {
                    $IsCompliant = $true
                    $commentsArray = @($msgTable.isCompliant, $msgTable.storageAccValidTLS)
                }
                else {
                    $IsCompliant = $false
                    $nonCompliantStorageAccountNames = $nonCompliantAccounts.ForEach({$_.StorageAccountName}) -join ', '
                    Write-Verbose "Subscription '$($obj.Name)': Storage accounts using TLS1.1 or less: $nonCompliantStorageAccountNames"
                    $commentsArray = @($msgTable.isNotCompliant, $msgTable.storageAccNotValidTLS, $msgTable.storageAccNotValidList -f $nonCompliantStorageAccountNames)
                }
            }

            $Comments = $commentsArray -join " "

            $DisplayName = if ($null -eq $obj.DisplayName) { $obj.Name } else { $obj.DisplayName }

            $c = [PSCustomObject]@{ 
                Type             = [string]"subscription"
                Id               = [string]$obj.Id
                Name             = [string]$obj.Name
                DisplayName      = [string]$DisplayName
                ComplianceStatus = [boolean]$IsCompliant
                Comments         = [string]$Comments
                ItemName         = [string]$ItemName
                itsgcode         = [string]$itsgcode
                ControlName      = [string]$ControlName
                ReportTime       = [string]$ReportTime
            }

            if ($EnableMultiCloudProfiles) {
                $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $obj.Id

                if (!$evalResult.ShouldEvaluate) {
                    if (!$evalResult.ShouldAvailable) {
                        if ($evalResult.Profile -gt 0) {
                            $c.ComplianceStatus = "Not Applicable"
                            $c | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                            $c.Comments = "Not available - Profile $($evalResult.Profile) not applicable for this guardrail"
                        } else {
                            $ErrorList.Add("Error occurred while evaluating profile configuration availability for subscription '$($obj.Name)'")
                        }
                    } else {
                        if ($evalResult.Profile -gt 0) {
                            $c.ComplianceStatus = "Not Applicable"
                            $c | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                            $c.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
                        } else {
                            $ErrorList.Add("Error occurred while evaluating profile configuration for subscription '$($obj.Name)'")
                        }
                    }
                } else {
                    $c | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                }
            }

            $ObjectList.Add($c)
        }
    }
    catch {
        $errorMsg = "Error creating compliance results: $_"
        $ErrorList.Add($errorMsg)
        Write-Warning $errorMsg
        return $moduleOutput
    }

    $moduleOutput.ComplianceResults = $ObjectList
    $moduleOutput.Errors = $ErrorList
    $moduleOutput.AdditionalResults = $AdditionalResults

    return $moduleOutput
}

