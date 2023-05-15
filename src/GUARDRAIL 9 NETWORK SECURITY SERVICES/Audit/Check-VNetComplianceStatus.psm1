function Get-VNetComplianceInformation {
    param (
        [Parameter(Mandatory = $false)]
        [string]
        $token,
        [Parameter(Mandatory = $true)]
        [string]
        $ControlName,
        [string] $itsgcode,
        [Parameter(Mandatory = $false)]
        [string]
        $ExcludedVNets,
        [hashtable] $msgTable,
        [Parameter(Mandatory = $true)]
        [string]
        $ReportTime,
        [Parameter(Mandatory = $true)]
        [string]
        $CBSSubscriptionName,
        [Parameter(Mandatory = $false)]
        [switch]
        $debuginfo
    )
    [PSCustomObject] $VNetList = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    $ExcludeVnetTag = "GR9-ExcludeVNetFromCompliance"
    try {
        $subs = Get-AzSubscription -ErrorAction Stop | Where-Object { $_.State -eq 'Enabled' -and $_.Name -ne $CBSSubscriptionName }  
    }
    catch {
        $ErrorList.Add("Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Accounts module; returned error message: $_" )
        throw "Error: Failed to execute the 'Get-AzSubscription'--verify your permissions and the installion of the Az.Accounts module; returned error message: $_"                
    }
    if ($null -ne $ExcludedVNets) {
        $ExcludedVNetsList = $ExcludedVNets.Split(",")
    }
    foreach ($sub in $subs) {
        Write-Verbose "Selecting subscription..."
        Select-AzSubscription -SubscriptionObject $sub | Out-Null
        
        $allVNETs = Get-AzVirtualNetwork
        $includedVNETs = $allVNETs | Where-Object { $_.Tag.$ExcludeVnetTag -ine 'true' }
        Write-Debug "Found $($allVNETs.count) VNets total; $($includedVNETs.count) not excluded by tag."

        if ($includedVNETs.count -gt 0) {
            foreach ($VNet in $includedVNETs) {
                Write-Debug "Working on $($VNet.Name) VNet..."
                if ($vnet.Name -notin $ExcludedVNetsList) {
                    if ($Vnet.EnableDdosProtection) {
                        $ComplianceStatus = $true 
                        $Comments = "$($msgTable.ddosEnabled) $($VNet.DdosProtectionPlan.Id)"
                    }
                    else {
                        $ComplianceStatus = $false
                        $Comments = $msgTable.ddosNotEnabled
                    }
                    # Create PSOBject with Information.
                    $VNetObject = [PSCustomObject]@{ 
                        VNETName         = $VNet.Name
                        SubscriptionName = $sub.Name 
                        ComplianceStatus = $ComplianceStatus
                        Comments         = $Comments
                        ItemName         = $msgTable.vnetDDosConfig
                        itsgcode         = $itsgcode
                        ControlName      = $ControlName
                        ReportTime       = $ReportTime
                    }
                    $VNetList.add($VNetObject) | Out-Null                
                }
                else {
                    Write-Verbose "Excluding $($VNet.Name) (Tag or parameter)."
                }    
            }
        }
        if ($includedVNETs.count -eq 0) {
            #No vnets found or no subnets found in vnets
            $ComplianceStatus = $true
            $Comments = "$($msgTable.noVNets) - $($sub.Name)"
            $VNETObject = [PSCustomObject]@{ 
                SubscriptionName = $sub.Name 
                SubnetName       = $msgTable.noVNets
                ComplianceStatus = $ComplianceStatus
                Comments         = $Comments
                ItemName         = $msgTable.networkSegmentation
                ControlName      = $ControlName
                itsgcode         = $itsgcodesegmentation
                ReportTime       = $ReportTime
            }
            $VNETList.add($VNETObject) | Out-Null
        }
    }
    if ($debuginfo) { 
        Write-Output "Listing $($VNetList.Count) List members."
        $VNetList | Write-Output "VNet: $($_.VNETName) - Compliant: $($_.ComplianceStatus) Comments: $($_.Comments)" 
    }
    #Creates Results object:
    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = $VNetList 
        Errors            = $ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput
}


