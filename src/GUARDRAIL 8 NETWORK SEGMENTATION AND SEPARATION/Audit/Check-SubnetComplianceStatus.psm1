
function Get-SubnetComplianceInformation {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $ControlName,
        [string] $itsgcodesegmentation,
        [string] $itsgcodeseparation,
        [Parameter(Mandatory = $false)]
        [string]
        $ExcludedSubnetsList, #Separated by command, simple string
        [Parameter(Mandatory = $false)]
        [string]$ReservedSubnetList, #Separated by command, simple string
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
    #module for Tags handling
    #import-module '..\..\GUARDRAIL COMMON\Get-Tags.psm1'
    [PSCustomObject] $SubnetList = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    $AdditionalResults = $null
    $ExcludeVnetTag = "GR8-ExcludeVNetFromCompliance"
    $ExcludedSubnetListTag = "GR-ExcludedSubnets"
    $reservedSubnetNames = $ReservedSubnetList.Split(",")
    $ExcludedSubnets = $ExcludedSubnetsList.Split(",")
    $allexcluded = $ExcludedSubnets + $reservedSubnetNames

    try {
        $subs = Get-AzSubscription -ErrorAction Stop  | Where-Object { $_.State -eq 'Enabled' -and $_.Name -ne $CBSSubscriptionName }  
    }
    catch {
        $ErrorList.Add("Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Accounts module; returned error message: $_")
        throw "Error: Failed to execute the 'Get-AzSubscription'--verify your permissions and the installion of the Az.Accounts module; returned error message: $_"                
    }

    foreach ($sub in $subs) {
        Write-Verbose "Selecting subscription: $($sub.Name)"
        Select-AzSubscription -SubscriptionObject $sub | Out-Null
        
        $allVNETs = Get-AzVirtualNetwork
        $includedVNETs = $allVNETs | Where-Object { $_.Tag.$ExcludeVnetTag -ine 'true' }
        Write-Debug "Found $($allVNETs.count) VNets total; $($includedVNETs.count) not excluded by tag."
        if ($includedVNETs.count -gt 0) {
            foreach ($VNet in $allVNETs) {
                If ($vnet -in $includedVNETs) {
                    Write-Debug "Working on $($VNet.Name) VNet..."

                    $ExcludeSubnetsTag = get-tagValue -tagKey $ExcludedSubnetListTag -object $VNet
                    if (!([string]::IsNullOrEmpty($ExcludeSubnetsTag))) {
                        $ExcludedSubnetListFromTag = $ExcludeSubnetsTag.Split(",")
                    }
                    else {
                        $ExcludedSubnetListFromTag = @()
                    }

                    #Handles the subnets
                    foreach ($subnet in Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $VNet) {
                        Write-Debug "Working on $($subnet.Name) Subnet..."
                        if ($subnet.Name -notin $allexcluded -and $subnet.Name -notin $ExcludedSubnetListFromTag) {
                            #checks NSGs
                            $ComplianceStatus = $false
                            $Comments = ''
                            if ($null -ne $subnet.NetworkSecurityGroup) {
                                Write-Debug "Found $($subnet.NetworkSecurityGroup.Id.Split("/")[8]) NSG"
                                #Add routine to analyze NSG regarding standard rules.
                                $nsg = Get-AzNetworkSecurityGroup -Name $subnet.NetworkSecurityGroup.Id.Split("/")[8] -ResourceGroupName $subnet.NetworkSecurityGroup.Id.Split("/")[4]
                                if ($nsg.SecurityRules.count -ne 0) { #NSG has other rules on top of standard rules.

                                    $LastInboundSecurityRule = $nsg.SecurityRules | Sort-Object Priority -Descending | Where-Object { $_.Direction -eq 'Inbound' } | Select-Object -First 1
                                    $LastOutboundSecurityRule = $nsg.SecurityRules | Sort-Object Priority -Descending | Where-Object { $_.Direction -eq 'Outbound' } | Select-Object -First 1

                                    if ($LastInboundSecurityRule -and $LastOutboundSecurityRule -and
                                        $LastInboundSecurityRule.SourceAddressPrefix -eq '*' -and $LastInboundSecurityRule.destinationPortRange -eq '*' -and $LastInboundSecurityRule.sourcePortRange -eq '*' -and $LastInboundSecurityRule.Access -eq "Deny" -and 
                                        $LastOutboundSecurityRule.DestinationAddressPrefix -eq '*' -and $LastOutboundSecurityRule.destinationPortRange -eq '*' -and $LastOutboundSecurityRule.sourcePortRange -eq '*' -and $LastOutboundSecurityRule.Access -eq "Deny") {
                                        $ComplianceStatus = $true
                                        $Comments = $msgTable.subnetCompliant
                                    }
                                    else {
                                        $ComplianceStatus = $false
                                        $Comments = $msgTable.nsgConfigDenyAll
                                    }
                                }
                                else {
                                    #NSG is present but has no custom rules at all.
                                    $ComplianceStatus = $false
                                    $Comments = $msgTable.nsgCustomRule

                                }
                            }
                            else {
                                $Comments = $msgTable.noNSG
                            }
                            $SubnetObject = [PSCustomObject]@{ 
                                SubscriptionName = $sub.Name 
                                SubnetName       = "$($VNet.Name)\$($subnet.Name)"
                                ComplianceStatus = $ComplianceStatus
                                Comments         = $Comments
                                ItemName         = $msgTable.networkSegmentation
                                ControlName      = $ControlName
                                itsgcode         = $itsgcodesegmentation
                                ReportTime       = $ReportTime
                            }
                            $SubnetList.add($SubnetObject) | Out-Null
                            #Checks Routes
                            if ($subnet.RouteTable) {
                                $UDR = $subnet.RouteTable.Id.Split("/")[8]
                                Write-Debug "Found $UDR UDR"
                                $routeTable = Get-AzRouteTable -ResourceGroupName $subnet.RouteTable.Id.Split("/")[4] -name $UDR
                                $ComplianceStatus = $false # I still don´t know if it has a UDR with 0.0.0.0 being sent to a Virtual Appliance.
                                $Comments = $msgTable.routeNVA
                                foreach ($route in $routeTable.Routes) {
                                    if ($route.NextHopType -eq "VirtualAppliance" -and $route.AddressPrefix -eq "0.0.0.0/0") { # Found the required UDR
                                        $ComplianceStatus = $true
                                        $Comments = $msgTable.subnetCompliant
                                    }
                                }
                            }
                        }
                        else {
                            #subnet excluded - log reason
                            $ComplianceStatus = $true
                            
                            If ($subnet.Name -in $reservedSubnetNames) {
                                $Comments = $msgTable.subnetExcludedByReservedName -f $subnet.Name,$ReservedSubnetList
                            }
                            ElseIf ($subnet.Name -in $ExcludedSubnetListFromTag) {
                                $Comments = $msgTable.subnetExcludedByTag -f $subnet.Name,$VNet.Name,$ExcludedSubnetListTag
                            }
                        }
                        $SubnetObject = [PSCustomObject]@{ 
                            SubscriptionName = $sub.Name 
                            SubnetName       = "$($VNet.Name)\$($subnet.Name)"
                            ComplianceStatus = $ComplianceStatus
                            Comments         = $Comments
                            ItemName         = $msgTable.networkSeparation
                            itsgcode         = $itsgcodeseparation
                            ControlName      = $ControlName
                            ReportTime       = $ReportTime
                        }
                        $SubnetList.add($SubnetObject) | Out-Null
                    }
               
                }
                else {
                    # VNET not in $includedVNETs
                    $subnetsInExcludedVnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $VNet

                    ForEach ($subnet in $subnetsInExcludedVnet) {

                        $comments = $msgTable.subnetExcludedByVNET -f $VNet.Name,$subnet.name,$ExcludeVnetTag

                        $SubnetObject = [PSCustomObject]@{ 
                            SubscriptionName = $sub.Name 
                            SubnetName       = "$($VNet.Name)\$($subnet.Name)"
                            ComplianceStatus = $true
                            Comments         = $Comments
                            ItemName         = $msgTable.networkSeparation
                            itsgcode         = $itsgcodeseparation
                            ControlName      = $ControlName
                            ReportTime       = $ReportTime
                        }
                        $SubnetList.add($SubnetObject) | Out-Null
                    }
                }
            }
        }
        
        if ($includedVNETs.count -eq 0 -or $SubnetList.count -eq 0) {
            #No vnets found or no subnets found in vnets
            $ComplianceStatus = $true
            $Comments = "$($msgTable.noSubnets) - $($sub.Name)"
            $SubnetObject = [PSCustomObject]@{ 
                SubscriptionName = $sub.Name 
                SubnetName       = $msgTable.noSubnets
                ComplianceStatus = $ComplianceStatus
                Comments         = $Comments
                ItemName         = $msgTable.networkSegmentation
                ControlName      = $ControlName
                itsgcode         = $itsgcodesegmentation
                ReportTime       = $ReportTime
            }
            $SubnetList.add($SubnetObject) | Out-Null
        }
    }
    if ($debug) {
        Write-Output "Listing $($SubnetList.Count) List members."
        $SubnetList |  select-object SubnetName, ComplianceStatus, Comments
    }
    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = $SubnetList
        Errors            = $ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput
}

