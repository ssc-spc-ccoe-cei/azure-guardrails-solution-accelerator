function Get-NetworkWatcherStatus {
    param (
        [Parameter(Mandatory=$false)]
        [string]
        $token,
        [Parameter(Mandatory=$true)]
        [string]
        $ControlName,
        [string] $itsgcode,
        [Parameter(Mandatory=$false)]
        [string]
        $ExcludedVNets,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime,
        [Parameter(Mandatory=$true)]
        [string]
        $CBSSubscriptionName,
        [Parameter(Mandatory=$false)]
        [switch]
        $debuginfo,
        [string] 
        $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] $EnableMultiCloudProfiles # New feature flag, default to false    
    )
    [PSCustomObject] $RegionList = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    $evalResult = $null
    $ExcludeVnetTag="GR9-ExcludeVNetFromCompliance"
    try {
        $subs=Get-AzSubscription -ErrorAction Stop | Where-Object {$_.State -eq 'Enabled' -and $_.Name -ne $CBSSubscriptionName}  
    }
    catch {
        $ErrorList.Add("Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Accounts module; returned error message: $_" )
        throw "Error: Failed to execute the 'Get-AzSubscription'--verify your permissions and the installion of the Az.Accounts module; returned error message: $_"                
    }
    if ($null -ne $ExcludedVNets)
    {
        $ExcludedVNetsList=$ExcludedVNets.Split(",")
    }
    foreach ($sub in $subs)
    {
        Write-Verbose "Selecting subscription..."
        Select-AzSubscription -SubscriptionObject $sub | Out-Null

        if ($EnableMultiCloudProfiles) {        
            $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $sub.Id
            if (!$evalResult.ShouldEvaluate) {
                Write-Output "No matching profile found"
                $ComplianceStatus = "Not Applicable"
            } else {
                Write-Output "Valid profile returned: $($evalResult.Profile)"
                $ComplianceStatus = $null  # Will be set later based on Network Watcher status
            }
        } else {
            $ComplianceStatus = $null  # Will be set later based on Network Watcher status
        }

        $allVNETs=Get-AzVirtualNetwork
        $includedVNETs=$allVNETs | Where-Object { $_.Tag.$ExcludeVnetTag -ine 'true' -and $_.Name -notin $ExcludedVNetsList }
        Write-Debug "Found $($allVNETs.count) VNets total; $($includedVNETs.count) not excluded by tag or -ExcludedVNets parameter."

        $nonExcludedVnetRegions = @()
        if ($includedVNETs.count -gt 0)
        {
            foreach ($VNet in $includedVNETs)
            {
                Write-Debug "Working on VNET '$($VNet.Name)'..."
                # add vnet region to regions list - used in checking for network watcher in that region
                $nonExcludedVnetRegions += $VNet.Location  
            }

            # check if network watcher is enabled in the region
            $comments = $null
            $ComplianceStatus = if ($null -eq $ComplianceStatus) { $true } else { $ComplianceStatus }
            ForEach ($region in ($nonExcludedVnetRegions | Get-Unique)) {
                $nw = Get-AzNetworkWatcher -Location $region -ErrorAction SilentlyContinue
                if ($nw) {
                    $ComplianceStatus = if ($null -eq $ComplianceStatus) { $true } else { $ComplianceStatus }
                    $Comments = $msgTable.networkWatcherEnabled -f $region
                }
                else {
                    $ComplianceStatus = if ($null -eq $ComplianceStatus) { $false } else { $ComplianceStatus }
                    $Comments = $msgTable.networkWatcherNotEnabled -f $region
                }
                # Create PSOBject with Information.
                $RegionObject = [PSCustomObject]@{ 
                    SubscriptionName  = $sub.Name 
                    ComplianceStatus = $ComplianceStatus
                    Comments = $Comments
                    ItemName = $msgTable.networkWatcherConfig
                    itsgcode = $itsgcode
                    ControlName = $ControlName
                    ReportTime = $ReportTime
                }
                if ($EnableMultiCloudProfiles -and $evalResult -ne 0) {
                    $RegionObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                }
                $RegionList.add($RegionObject) | Out-Null                               
            }
        }
        else {
            $ComplianceStatus = if ($null -eq $ComplianceStatus) { $true } else { $ComplianceStatus }
            $RegionObject = [PSCustomObject]@{ 
                SubscriptionName  = $sub.Name 
                ComplianceStatus = $ComplianceStatus
                Comments = $msgTable.networkWatcherConfigNoRegions
                ItemName = $msgTable.networkWatcherConfigNoRegions
                itsgcode = $itsgcode
                ControlName = $ControlName
                ReportTime = $ReportTime
            }
            if ($EnableMultiCloudProfiles -and $evalResult -ne 0) {
                $RegionObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
            }
            $RegionList.add($RegionObject) | Out-Null   
        }
    }
    if ($debuginfo){ 
        Write-Output "Listing $($RegionList.Count) List members."
    }
    #Creates Results object:
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $RegionList 
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput
}

