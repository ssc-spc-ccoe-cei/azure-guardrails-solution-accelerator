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
        $subs = Get-AzSubscription -ErrorAction Stop | 
                Where-Object { $_.State -eq 'Enabled' }
    }
    catch {
        $errorMessage = "Failed to get subscriptions. Error: $_"
        $ErrorList.Add($errorMessage)
        throw $errorMessage
    }

    # First scan all subscriptions to check if any have compliant setup
    $hasCompliantSetupInTenant = $false
    foreach ($sub in $subs) {
        try {
            Select-AzSubscription -SubscriptionObject $sub | Out-Null
            
            $azureFirewalls = Get-AzFirewall -ErrorAction SilentlyContinue
            $fortigateVMs = Get-AzVM | Where-Object { 
                $_.StorageProfile.ImageReference.Publisher -eq "fortinet" -and
                $_.StorageProfile.ImageReference.Offer -like "*fortinet*fortigate*"
            }
            
            $appGateways = Get-AzApplicationGateway -ErrorAction SilentlyContinue
            foreach ($ag in $appGateways) {
                if ($ag.Sku.Tier -like "*WAF*") {
                    $hasCompliantSetupInTenant = $true
                    break
                }
            }
            
            if ($azureFirewalls.Count -gt 0 -or $fortigateVMs.Count -gt 0) {
                $hasCompliantSetupInTenant = $true
                break
            }
        }
        catch {
            $ErrorList.Add("Error checking tenant-wide compliance in subscription $($sub.Name): $_")
        }
    }

    # Now evaluate each subscription
    foreach ($sub in $subs) {
        $IsCompliant = $false
        $Comments = ""
        
        try {
            Select-AzSubscription -SubscriptionObject $sub | Out-Null

            # Check for Azure Firewall
            $azureFirewalls = Get-AzFirewall -ErrorAction SilentlyContinue
            
            # Check for Fortigate VMs (basic check based on naming convention)
            $fortigateVMs = Get-AzVM | Where-Object { 
                # Verify it's using Fortigate publisher and offer
                $_.StorageProfile.ImageReference.Publisher -eq "fortinet" -and
                $_.StorageProfile.ImageReference.Offer -like "*fortinet*fortigate*"
            }
            
            # Check for Application Gateway with WAF
            $appGateways = Get-AzApplicationGateway -ErrorAction SilentlyContinue
            $hasWAFEnabled = $false
            
            if ($appGateways) {
                foreach ($ag in $appGateways) {
                    if ($ag.Sku.Tier -like "*WAF*") {
                        $hasWAFEnabled = $true
                        break
                    }
                }
            }

            # Determine compliance and comments
            $hasFirewall = $azureFirewalls.Count -gt 0 -or $fortigateVMs.Count -gt 0
            $hasAppGateway = $appGateways.Count -gt 0

            if ($hasAppGateway -and -not $hasWAFEnabled) {
                # App Gateway without WAF is always non-compliant
                $IsCompliant = $false
                $Comments = $msgTable.wAFNotEnabled
            }
            elseif ($hasFirewall) {
                $firewallType = if ($azureFirewalls.Count -gt 0) { "Azure Firewall" } else { "Fortigate Firewall" }
                $IsCompliant = $true
                $Comments = $msgTable.firewallFound -f $firewallType
            }
            elseif ($hasAppGateway -and $hasWAFEnabled) {
                $IsCompliant = $true
                $Comments = $msgTable.wAFEnabled
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
                $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $sub.Id
                if (!$evalResult.ShouldEvaluate) {
                    if(!$evalResult.ShouldAvailable ){
                        if ($evalResult.Profile -gt 0) {
                            $resultObject.ComplianceStatus = "Not Applicable"
                            $resultObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                            $resultObject.Comments = "Not available - Profile $($evalResult.Profile) not applicable for this guardrail"
                        } else {
                            $ErrorList.Add("Error occurred while evaluating profile configuration availability")
                        }
                    } else {
                        if ($evalResult.Profile -gt 0) {
                            $resultObject.ComplianceStatus = "Not Applicable"
                            $resultObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                            $resultObject.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
                        } else {
                            $ErrorList.Add("Error occurred while evaluating profile configuration")
                        }
                    }
                } else {
                    $resultObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                }
            }

            $ResultsList.Add($resultObject) | Out-Null
        }
        catch {
            $ErrorList.Add("Error processing subscription $($sub.Name): $_")
        }
    }

    return [PSCustomObject]@{
        ComplianceResults = $ResultsList
        Errors = $ErrorList
    }
}