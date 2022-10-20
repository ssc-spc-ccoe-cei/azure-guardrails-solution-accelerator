
function Get-SubnetComplianceInformation {
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $ControlName,
        [Parameter(Mandatory=$true)]
        [string]
        $WorkSpaceID,
        [Parameter(Mandatory=$true)]
        [string]
        $workspaceKey,
        [Parameter(Mandatory=$false)]
        [string]
        $LogType="GuardrailsCompliance",
        [string] $itsgcodesegmentation,
        [string] $itsgcodeseparation,
        [Parameter(Mandatory=$false)]
        [array]
        $ExcludedSubnets,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime,
        [Parameter(Mandatory=$true)]
        [string]
        $CBSSubscriptionName
    )
    #module for Tags handling
    #import-module '..\..\GUARDRAIL COMMON\Get-Tags.psm1'
    [PSCustomObject] $SubnetList = New-Object System.Collections.ArrayList
    $reservedSubnetNames=@("GatewaySubnet","AzureFirewallSubnet","AzureBastionSubnet","AzureFirewallManagementSubnet","RouteServerSubnet")
    $allexcluded=$ExcludedSubnets+$reservedSubnetNames

    try {
        $subs=Get-AzSubscription -ErrorAction Stop | Where-Object {$_.State -eq 'Enabled' -and $_.Name -ne $CBSSubscriptionName}  
    }
    catch {
        Add-LogEntry 'Error' "Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Accounts module; returned error message: $_" -workspaceGuid $WorkSpaceID -workspaceKey $WorkSpaceKey
        throw "Error: Failed to execute the 'Get-AzSubscription'--verify your permissions and the installion of the Az.Accounts module; returned error message: $_"                
    }

    if ($ExcludedSubnets -ne $null)
    {
        $ExcludedSubnetsList=$ExcludedSubnets.Split(",")
    }
    foreach ($sub in $subs)
    {
        Write-Verbose "Selecting subscription: $($sub.Name)"
        Select-AzSubscription -SubscriptionObject $sub
        
        $VNets=Get-AzVirtualNetwork
        Write-Debug "Found $($VNets.count) VNets."
        if ($VNets)
        {
            foreach ($VNet in $VNets)
            {
                Write-Debug "Working on $($VNet.Name) VNet..."
                $ev=get-tagValue -tagKey "ExcludeFromCompliance" -object $VNet
                if ($ev -ne "true")
                {
                    #Handles the subnets
                    foreach ($subnet in Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $VNet)
                    {
                        Write-Debug "Working on $($subnet.Name) Subnet..."
                        if ($subnet.Name -notin $allexcluded)
                        {
                            #checks NSGs
                            $ComplianceStatus=$false
                            $Comments = $msgTable.noNSG
                            $MitigationCommands=@"
# https://docs.microsoft.com/en-us/powershell/module/az.network/set-azvirtualnetworksubnetconfig?view=azps-8.0.0#2-add-a-network-security-group-to-a-subnet
#Creates NSG Resource for subnet $($subnet.Name)
Select-azsubscription $($sub.SubscriptionId)
`$nsg=New-AzNetworkSecurityGroup -Name '$($subnet.Name)-nsg' -ResourceGroupName $($vnet.ResourceGroupName) -Location $($VNet.Location)
# Assign NSG to subnet
`$subnet=(Get-AzVirtualNetwork -ResourceGroupName $($vnet.ResourceGroupName) -Name $($vnet.Name)).Subnets | Where-Object Name -eq $($subnet.Name)
`$subnet.NetworkSecurityGroup = `$nsg
Get-AzVirtualNetwork -ResourceGroupName $($vnet.ResourceGroupName) -Name $($vnet.Name) | set-azvirtual-network
"@
                            if ($null -ne $subnet.NetworkSecurityGroup)
                            {
                                Write-Debug "Found $($subnet.NetworkSecurityGroup.Id.Split("/")[8]) NSG"
                                #Add routine to analyze NSG regarding standard rules.
                                $nsg=Get-AzNetworkSecurityGroup -Name $subnet.NetworkSecurityGroup.Id.Split("/")[8] -ResourceGroupName $subnet.NetworkSecurityGroup.Id.Split("/")[4]
                                if ($nsg.SecurityRules.count -ne 0) #NSG has other rules on top of standard rules.
                                {
                                    $LastSecurityRule=($nsg.SecurityRules | Sort-Object Priority -Descending)[0]
                                    if ($LastSecurityRule.DestinationAddressPrefix -eq '*' -and $LastSecurityRule.Access -eq "Deny") # Determine all criteria for good or bad here...
                                    {
                                        $ComplianceStatus=$true
                                        $Comments = $msgTable.subnetCompliant
                                        $MitigationCommands="N/A"
                                    }
                                    else {
                                        $ComplianceStatus=$false
                                        $Comments = $msgTable.nsgConfigDenyAll
                                        $MitigationCommands=@"
Select-azsubscription $($sub.SubscriptionId)
`$nsg=Get-AzNetworkSecurityGroup -Name $($subnet.NetworkSecurityGroup.Id.Split("/")[8]) -ResourceGroupName $($subnet.NetworkSecurityGroup.Id.Split("/")[4])
`$RuleParams = @{
    'Name'                     = 'Denyall'
    'NetworkSecurityGroup'     = `$nsg
    'Protocol'                 = '*'
    'Direction'                = 'Inbound'
    'Priority'                 = 4096
    'SourceAddressPrefix'      = '*'
    'SourcePortRange'          = '*'
    'DestinationAddressPrefix' = '*'
    'DestinationPortRange'     = '*'
    'Access'                   = 'Deny'
    }
Add-AzNetworkSecurityRuleConfig @RuleParams | Set-AzNetworkSecurityGroup
"@
                                    }
                                }
                                else {
                                    #NSG is present but has no custom rules at all.
                                    $ComplianceStatus=$false
                                    $Comments = $msgTable.nsgCustomRule
                                    $MitigationCommands=@"
Select-azsubscription $($sub.SubscriptionId)
`$nsg=Get-AzNetworkSecurityGroup -Name $($subnet.NetworkSecurityGroup.Id.Split("/")[8]) -ResourceGroupName $($subnet.NetworkSecurityGroup.Id.Split("/")[4])
`$RuleParams = @{
    'Name'                     = 'Denyall'
    'NetworkSecurityGroup'     = `$nsg
    'Protocol'                 = '*'
    'Direction'                = 'Inbound'
    'Priority'                 = 4096
    'SourceAddressPrefix'      = '*'
    'SourcePortRange'          = '*'
    'DestinationAddressPrefix' = '*'
    'DestinationPortRange'     = '*'
    'Access'                   = 'Deny'
    }
Add-AzNetworkSecurityRuleConfig @RuleParams | Set-AzNetworkSecurityGroup
"@
                                }
                            }
                            $SubnetObject = [PSCustomObject]@{ 
                                SubscriptionName  = $sub.Name 
                                SubnetName="$($VNet.Name)\$($subnet.Name)"
                                ComplianceStatus = $ComplianceStatus
                                Comments = $Comments
                                ItemName = $msgTable.networkSegmentation
                                ControlName = $ControlName
                                itsgcode = $itsgcodesegmentation
                                MitigationCommands=$MitigationCommands
                                ReportTime = $ReportTime
                            }
                            $SubnetList.add($SubnetObject) | Out-Null

                            #Checks Routes
                            if ($subnet.RouteTable)
                            {
                                $UDR=$subnet.RouteTable.Id.Split("/")[8]
                                Write-Debug "Found $UDR UDR"
                                $routeTable=Get-AzRouteTable -ResourceGroupName $subnet.RouteTable.Id.Split("/")[4] -name $UDR
                                $ComplianceStatus=$false # I still don´t know if it has a UDR with 0.0.0.0 being sent to a Virtual Appliance.
                                $Comments = $msgTable.routeNVA
                                $MitigationCommands = $msgTable.routeNVAMitigation
                                $MitigationCommands="N/A"
                                foreach ($route in $routeTable.Routes)
                                {
                                    if ($route.NextHopType -eq "VirtualAppliance" -and $route.AddressPrefix -eq "0.0.0.0/0") # Found the required UDR
                                    {
                                        $ComplianceStatus=$true
                                        $Comments= $msgTable.subnetCompliant
                                        $MitigationCommands="N/A"
                                    }
                                }
                            }
                        }
                        else { #subnet excluded
                            $ComplianceStatus=$true
                            $Comments=$msgTable.subnetExcluded
                            $MitigationCommands="N/A"                            
                        }
                        $SubnetObject = [PSCustomObject]@{ 
                            SubscriptionName  = $sub.Name 
                            SubnetName="$($VNet.Name)\$($subnet.Name)"
                            ComplianceStatus = $ComplianceStatus
                            Comments = $Comments
                            ItemName = $msgTable.networkSeparation
                            itsgcode = $itsgcodeseparation
                            ControlName = $ControlName
                            ReportTime = $ReportTime
                            MitigationCommands=$MitigationCommands
                        }
                        $SubnetList.add($SubnetObject) | Out-Null
                    }
                }
                else {
                    Write-Verbose "Excluding $($VNet.Name) based on tagging."
                }    
            }
        }
        else {
            #No subnets found
            $ComplianceStatus=$true
            $Comments="$($msgTable.noSubnets) - $($sub.Name)"
            $SubnetObject = [PSCustomObject]@{ 
                SubscriptionName  = $sub.Name 
                SubnetName=$msgTable.noSubnets
                ComplianceStatus = $ComplianceStatus
                Comments = $Comments
                ItemName = $msgTable.networkSegmentation
                ControlName = $ControlName
                itsgcode = $itsgcodesegmentation
                MitigationCommands="N/A"
                ReportTime = $ReportTime
            }
            $SubnetList.add($SubnetObject) | Out-Null
        }
    }
    if ($debug) {
        Write-Output "Listing $($SubnetList.Count) List members."
        $SubnetList |  select-object SubnetName, ComplianceStatus, Comments
    }
    $JSONSubnetList = ConvertTo-Json -inputObject $SubnetList 

    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
    -sharedkey $workspaceKey `
    -body $JSONSubnetList `
    -logType $LogType `
    -TimeStampField Get-Date 
}
