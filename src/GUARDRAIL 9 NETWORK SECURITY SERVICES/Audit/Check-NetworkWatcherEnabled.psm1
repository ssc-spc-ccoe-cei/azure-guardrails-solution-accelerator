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
        [Parameter(Mandatory=$false)]
        [string] 
        $ModuleProfiles,  # Passed as a string
        [Parameter(Mandatory=$false)]        
        [string] 
        $CloudUsageProfiles = "3",  # Passed as a string
        [Parameter(Mandatory=$false)]        
        [string] 
        $EnableMultiCloudProfiles = "false"  # New feature flag, default to false
    )
    [PSCustomObject] $RegionList = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    $DebugMessage.Add("Starting Get-NetworkWatcherStatus function...")
    $ExcludeVnetTag="GR9-ExcludeVNetFromCompliance"
    try {
        $subs=Get-AzSubscription -ErrorAction Stop | Where-Object {$_.State -eq 'Enabled' -and $_.Name -ne $CBSSubscriptionName}
        $DebugMessage.Add("Found $($subs.count) subscriptions." 
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
        $DebugMessage.Add("Working on subscription '$($sub.Name)'...")

        Write-Verbose "Selecting subscription..."
        Select-AzSubscription -SubscriptionObject $sub | Out-Null
        
        $allVNETs=Get-AzVirtualNetwork
        $includedVNETs=$allVNETs | Where-Object { $_.Tag.$ExcludeVnetTag -ine 'true' -and $_.Name -notin $ExcludedVNetsList }
        Write-Debug "Found $($allVNETs.count) VNets total; $($includedVNETs.count) not excluded by tag or -ExcludedVNets parameter."

        $nonExcludedVnetRegions = @()
        if ($includedVNETs.count -gt 0)
        {
            foreach ($VNet in $includedVNETs)
            {
                $DebugMessage.Add("Working on VNET '$($VNet.Name)'...")
                Write-Debug "Working on VNET '$($VNet.Name)'..."
                # add vnet region to regions list - used in checking for network watcher in that region
                $nonExcludedVnetRegions += $VNet.Location  
            }

            # check if network watcher is enabled in the region
            $comments = $null
            $ComplianceStatus = $false
            ForEach ($region in ($ | Get-Unique)) {
                $nw = Get-AzNetworkWatcher -Location $region -ErrorAction SilentlyContinue
                if ($nw) {
                    $ComplianceStatus = $true 
                    $Comments= $msgTable.networkWatcherEnabled -f $region
                }
                else {
                    $ComplianceStatus = $false
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
                $RegionList.add($RegionObject) | Out-Null                               
            }
        }
        else {
            $ComplianceStatus = $true
            $RegionObject = [PSCustomObject]@{ 
                SubscriptionName  = $sub.Name 
                ComplianceStatus = $ComplianceStatus
                Comments = $msgTable.networkWatcherConfigNoRegions
                ItemName = $msgTable.networkWatcherConfigNoRegions
                itsgcode = $itsgcode
                ControlName = $ControlName
                ReportTime = $ReportTime
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
        DebugMessage=$DebugMessage
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput
}


