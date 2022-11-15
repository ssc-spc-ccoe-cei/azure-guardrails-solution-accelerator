function Get-VNetComplianceInformation {
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
        $debuginfo
    )
    [PSCustomObject] $VNetList = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList

    try {
        $subs=Get-AzSubscription -ErrorAction Stop | Where-Object {$_.State -eq 'Enabled' -and $_.Name -ne $CBSSubscriptionName}  
    }
    catch {
        $ErrorList.Add("Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Accounts module; returned error message: $_" )
        #Add-LogEntry2 'Error' 
        throw "Error: Failed to execute the 'Get-AzSubscription'--verify your permissions and the installion of the Az.Accounts module; returned error message: $_"                
    }

    if ($ExcludedVNets -ne $null)
    {
        $ExcludedVNetsList=$ExcludedVNets.Split(",")
    }
    foreach ($sub in $subs)
    {
        Write-Verbose "Selecting subscription..."
        Select-AzSubscription -SubscriptionObject $sub | Out-Null
        
        $VNets=Get-AzVirtualNetwork
        Write-Debug "Found $($VNets.count) VNets."
        if ($VNets)
        {
            foreach ($VNet in $VNets)
            {
                Write-Debug "Working on $($VNet.Name) VNet..."
                $ev=get-tagValue -tagKey "ExcludeFromCompliance" -object $VNet
                if ($ev -ne "true" -and $vnet.Name -notin $ExcludedVNetsList)
                {
                    if ($Vnet.EnableDdosProtection) 
                    {
                        $ComplianceStatus = $true 
                        $Comments="$($msgTable.ddosEnabled) $($VNet.DdosProtectionPlan.Id)"
                        #$MitigationCommands="N/A"
                    }
                    else {
                        $ComplianceStatus = $false
                        $Comments= $msgTable.ddosNotEnabled
                        <#$MitigationCommands=@"
                        # https://docs.microsoft.com/en-us/azure/ddos-protection/ddos-protection-overview
                        # Selects Subscription
                        Select-azsubscription $($sub.SubscriptionId)
                        # Create a new DDos Plan
                        `$plan=new-azddosProtectionPlan -ResourceGroupName $($Vnet.ResourceGroupName) -Name '$($Vnet.Name)-plan' -Location '$($vnet.Location)'
                        `$vnet=Get-AzVirtualNetwork -Name $($vnet.Name) -ResourceGroupName $($Vnet.ResourceGroupName)
                        #change DDos configuration
                        `$vnet.EnableDdosProtection=$true
                        `$vnet.DdosProtectionPlan.Id=`$plan.id
                        #Apply configuration
                        Set-azvirtualNetwork -VirtualNetwork `$vnet
    "@#>
                    }
                    # Create PSOBject with Information.
                    $VNetObject = [PSCustomObject]@{ 
                        VNETName = $VNet.Name
                        SubscriptionName  = $sub.Name 
                        ComplianceStatus = $ComplianceStatus
                        Comments = $Comments
                        ItemName = $msgTable.vnetDDosConfig
                        itsgcode = $itsgcode
                        ControlName = $ControlName
                        #MitigationCommands=$MitigationCommands
                        ReportTime = $ReportTime
                    }
                    $VNetList.add($VNetObject) | Out-Null                
                }
                else {
                    Write-Verbose "Excluding $($VNet.Name) (Tag or parameter)."
                }    
            }
        }
    }
    if ($debuginfo){ 
        Write-Output "Listing $($VNetList.Count) List members."
        $VNetList | Write-Output "VNet: $($_.VNETName) - Compliant: $($_.ComplianceStatus) Comments: $($_.Comments)" 
    }
    #Creates Results object:
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $VNetList 
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput

}

