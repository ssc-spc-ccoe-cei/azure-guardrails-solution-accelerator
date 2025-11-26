function Get-SubscriptionNetworkSecurityStatus {
    param (
        [Parameter(Mandatory=$true)]
        [object]$Subscription,
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [System.Collections.ArrayList]$ErrorList
    )
    
    try {
        Select-AzSubscription -SubscriptionObject $Subscription | Out-Null
        
        # Get Azure Firewalls
        $azureFirewalls = @(Get-AzFirewall -ErrorAction SilentlyContinue)
        
        # Get Fortigate VMs (optimized: only query if we haven't found a firewall yet)
        $fortigateVMs = @()
        if ($azureFirewalls.Count -eq 0) {
            try {
                $allVMs = @(Get-AzVM -ErrorAction SilentlyContinue)
                if ($allVMs.Count -gt 0) {
                    $fortigateVMs = @($allVMs | Where-Object { 
                        $null -ne $_.StorageProfile -and
                        $null -ne $_.StorageProfile.ImageReference -and
                        $_.StorageProfile.ImageReference.Publisher -eq "fortinet" -and
                        $_.StorageProfile.ImageReference.Offer -like "*fortinet*fortigate*"
                    })
                }
            }
            catch {
                $ErrorList.Add("Error retrieving VMs in subscription $($Subscription.Name): $_") | Out-Null
            }
        }
        
        # Get Application Gateways
        $appGateways = @(Get-AzApplicationGateway -ErrorAction SilentlyContinue)
        $hasWAFEnabled = $false
        
        if ($appGateways.Count -gt 0) {
            foreach ($ag in $appGateways) {
                if ($null -ne $ag.Sku -and $null -ne $ag.Sku.Tier -and $ag.Sku.Tier -like "*WAF*") {
                    $hasWAFEnabled = $true
                    break
                }
            }
        }
        
        $hasFirewall = ($azureFirewalls.Count -gt 0) -or ($fortigateVMs.Count -gt 0)
        
        return @{
            HasFirewall = $hasFirewall
            HasAppGateway = ($appGateways.Count -gt 0)
            HasWAFEnabled = $hasWAFEnabled
            FirewallType = if ($azureFirewalls.Count -gt 0) { "Azure Firewall" } elseif ($fortigateVMs.Count -gt 0) { "Fortigate Firewall" } else { $null }
        }
    }
    catch {
        $ErrorList.Add("Error checking network security status in subscription $($Subscription.Name): $_") | Out-Null
        return @{
            HasFirewall = $false
            HasAppGateway = $false
            HasWAFEnabled = $false
            FirewallType = $null
        }
    }
}

function Check-NetworkSecurityTools {
    param (
        [Parameter(Mandatory=$true)]
        [string] $ControlName,
        [Parameter(Mandatory=$true)]
        [string] $ItemName,
        [Parameter(Mandatory=$true)]
        [string] $itsgcode,
        [Parameter(Mandatory=$true)]
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string] $ReportTime,
        [string] $CloudUsageProfiles = "3",
        [string] $ModuleProfiles,
        [switch] $EnableMultiCloudProfiles
    )

    $ResultsList = [System.Collections.ArrayList]::new()
    $ErrorList = [System.Collections.ArrayList]::new()

    try {
        $subs = @(Get-AzSubscription -ErrorAction Stop | Where-Object { $_.State -eq 'Enabled' })
    }
    catch {
        $errorMessage = "Failed to get subscriptions. Error: $_"
        $ErrorList.Add($errorMessage) | Out-Null
        throw $errorMessage
    }

    if ($subs.Count -eq 0) {
        return [PSCustomObject]@{
            ComplianceResults = $ResultsList
            Errors = $ErrorList
        }
    }

    # Single pass: evaluate subscriptions and track tenant-wide compliance
    $hasCompliantSetupInTenant = $false
    $subscriptionStatuses = @{}
    
    foreach ($sub in $subs) {
        $status = Get-SubscriptionNetworkSecurityStatus -Subscription $sub -ErrorList $ErrorList
        $subscriptionStatuses[$sub.Id] = $status
        
        # Update tenant-wide compliance flag (only check once)
        if (-not $hasCompliantSetupInTenant) {
            $hasCompliantSetupInTenant = $status.HasFirewall -or 
                                         ($status.HasAppGateway -and $status.HasWAFEnabled)
        }
    }

    # Generate results for each subscription
    foreach ($sub in $subs) {
        $status = $subscriptionStatuses[$sub.Id]
        
        # Safety check: if status is null, skip this subscription (shouldn't happen, but defensive programming)
        if ($null -eq $status) {
            $ErrorList.Add("Status data missing for subscription $($sub.Name) (ID: $($sub.Id))") | Out-Null
            continue
        }
        
        $IsCompliant = $false
        $Comments = ""
        
        try {
            # Determine compliance and comments
            if ($status.HasFirewall) {
                # If firewall exists, always compliant regardless of WAF status
                $IsCompliant = $true
                $firewallTypeName = if ($null -ne $status.FirewallType) { $status.FirewallType } else { "Unknown Firewall" }
                $Comments = $msgTable.firewallFound -f $firewallTypeName
            }
            elseif ($status.HasAppGateway -and $status.HasWAFEnabled) {
                # App Gateway with WAF is compliant
                $IsCompliant = $true
                $Comments = $msgTable.wAFEnabled
            }
            elseif ($status.HasAppGateway -and -not $status.HasWAFEnabled) {
                # App Gateway without WAF - compliant only if another sub has compliant setup
                $IsCompliant = $hasCompliantSetupInTenant
                $Comments = if ($hasCompliantSetupInTenant) {
                    $msgTable.noFirewallOrGatewayCompliant
                } else {
                    $msgTable.wAFNotEnabled
                }
            }
            else {
                # No firewall or gateway - compliant only if another sub has compliant setup
                $IsCompliant = $hasCompliantSetupInTenant
                $Comments = if ($hasCompliantSetupInTenant) {
                    $msgTable.noFirewallOrGatewayCompliant
                } else {
                    $msgTable.noFirewallOrGateway
                }
            }

            $resultObject = [PSCustomObject]@{
                SubscriptionName = $sub.Name
                ComplianceStatus = $IsCompliant
                Comments = $Comments
                ItemName = $ItemName
                ControlName = $ControlName
                itsgcode = $itsgcode
                ReportTime = $ReportTime
            }

            if ($EnableMultiCloudProfiles) {
                $resultObject = Add-ProfileInformation -Result $resultObject -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $sub.Id -ErrorList $ErrorList
                Write-Host "Compliance Output: $resultObject"
            }

            $ResultsList.Add($resultObject) | Out-Null
        }
        catch {
            $ErrorList.Add("Error processing subscription $($sub.Name): $_") | Out-Null
        }
    }

    return [PSCustomObject]@{
        ComplianceResults = $ResultsList
        Errors = $ErrorList
    }
}