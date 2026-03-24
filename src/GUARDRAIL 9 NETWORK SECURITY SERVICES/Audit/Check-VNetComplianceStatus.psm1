function Invoke-ArgPagedQuery {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string] $Query,
        [Parameter(Mandatory = $true)][string] $SubscriptionId
    )

    # Azure Resource Graph may split one query result into multiple pages.
    # This helper keeps reading until we have every row for the subscription.
    $allResults = [System.Collections.ArrayList]::new()
    $skipToken = $null

    do {
        # When Azure gives us a skip token, use it to request the next page.
        if ($skipToken) {
            $pageResults = Search-AzGraph -Query $Query -Subscription $SubscriptionId -First 1000 -SkipToken $skipToken -ErrorAction Stop
        }
        else {
            $pageResults = Search-AzGraph -Query $Query -Subscription $SubscriptionId -First 1000 -ErrorAction Stop
        }

        # Add each row to one shared list so the caller gets one complete result set.
        foreach ($row in $pageResults) {
            $allResults.Add($row) | Out-Null
        }

        # An empty skip token means there are no more pages to read.
        $skipToken = $pageResults.SkipToken
    } while ($skipToken)

    return $allResults
}

function Get-SubscriptionPublicIpStatus {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string] $SubscriptionId,
        [Parameter(Mandatory = $true)][string] $SubscriptionName,
        [Parameter(Mandatory = $true)][hashtable] $msgTable,
        [AllowEmptyCollection()]
        [Parameter(Mandatory = $true)][System.Collections.ArrayList] $ErrorList
    )

    # This query reads every public IP resource in the subscription.
    # For each public IP, it also reads the DDoS protection mode value that
    # Azure stores on that resource.
    $publicIpQuery = @"
resources
| where type =~ 'microsoft.network/publicipaddresses'
| project publicIpName = name,
          protectionMode = tostring(properties.ddosSettings.protectionMode)
"@

    try {
        # Use the paging helper so the query still works when the subscription
        # has more results than Azure returns in one page.
        $publicIpResults = Invoke-ArgPagedQuery -Query $publicIpQuery -SubscriptionId $SubscriptionId
    }
    catch {
        # If Azure cannot return the public IP data, record the problem and
        # return a status object that clearly says the check failed.
        $errorMessage = $msgTable.ddosPublicIpCheckFailed -f $SubscriptionName, $_
        $ErrorList.Add($errorMessage) | Out-Null
        Write-Warning $errorMessage

        return [PSCustomObject]@{
            QueryFailed        = $true
            PublicIpCount      = 0
            ProtectedPublicIps = 0
        }
    }

    # Wrap the results in a normal array so Count behaves consistently.
    $publicIps = @($publicIpResults)

    # Count a public IP as protected when Azure reports one of the
    # protection modes this control accepts.
    $protectedPublicIps = @(
        $publicIps | Where-Object {
            $_.protectionMode -in @('Enabled', 'VirtualNetworkInherited')
        }
    )

    # Return only the values needed by the subscription compliance decision.
    return [PSCustomObject]@{
        QueryFailed        = $false
        PublicIpCount      = $publicIps.Count
        ProtectedPublicIps = $protectedPublicIps.Count
    }
}

function Get-SubscriptionComplianceObject {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] $sub,
        [Parameter(Mandatory = $true)] $includedVNETs,
        [Parameter(Mandatory = $true)] $publicIpStatus,
        [Parameter(Mandatory = $true)][hashtable] $msgTable,
        [Parameter(Mandatory = $true)][string] $ControlName,
        [Parameter(Mandatory = $true)][string] $itsgcode,
        [Parameter(Mandatory = $true)][string] $ReportTime,
        [Parameter(Mandatory = $true)][bool] $EnableMultiCloudProfiles,
        [AllowEmptyCollection()]
        [Parameter(Mandatory = $true)][System.Collections.ArrayList] $ErrorList,
        [string] $CloudUsageProfiles,
        [string] $ModuleProfiles
    )

    # Count how many included VNets have VNet DDoS protection enabled.
    # Count how many public IPs report a protected DDoS mode.
    # These numbers are also shown in the comment text.
    $protectedVNetCount = @($includedVNETs | Where-Object { $_.EnableDdosProtection }).Count
    $includedVNetCount = @($includedVNETs).Count
    $protectedPublicIpCount = $publicIpStatus.ProtectedPublicIps
    $publicIpCount = $publicIpStatus.PublicIpCount

    # This is the "nothing to check" case:
    # - the public IP query succeeded
    # - there are no included VNets
    # - there are no public IPs
    $hasNoScopedResources = (-not $publicIpStatus.QueryFailed -and $includedVNetCount -eq 0 -and $publicIpCount -eq 0)

    # Create the result object once, then fill in the final status and comment below.
    $subscriptionObject = [PSCustomObject]@{
        VNETName         = $msgTable.subscriptionScope
        SubscriptionName = $sub.Name
        ComplianceStatus = $false
        Comments         = ''
        ItemName         = $msgTable.vnetDDosConfig
        itsgcode         = $itsgcode
        ControlName      = $ControlName
        ReportTime       = $ReportTime
    }

    # Apply the subscription-level rules in order:
    # 1. If there is nothing to check, mark it compliant.
    # 2. If any included VNet or any public IP is protected, mark it compliant.
    # 3. If the public IP check failed and there is no protection signal, mark it non-compliant.
    #    This is a "fail closed" choice: when the public IP result is unknown,
    #    do not assume the subscription is protected.
    # 4. Otherwise, resources exist but none are protected, so mark it non-compliant.
    if ($hasNoScopedResources) {
        $subscriptionObject.ComplianceStatus = $true
        $subscriptionObject.Comments = $msgTable.ddosSubscriptionNoResources -f $sub.Name
    }
    elseif ($protectedVNetCount -gt 0 -or $protectedPublicIpCount -gt 0) {
        $subscriptionObject.ComplianceStatus = $true
        $subscriptionObject.Comments = $msgTable.ddosSubscriptionProtectionFound -f $sub.Name, $protectedVNetCount, $includedVNetCount, $protectedPublicIpCount, $publicIpCount
    }
    elseif ($publicIpStatus.QueryFailed) {
        $subscriptionObject.ComplianceStatus = $false
        $subscriptionObject.Comments = $msgTable.ddosPublicIpCheckFailedNoProtection -f $sub.Name, $protectedVNetCount, $includedVNetCount
    }
    else {
        $subscriptionObject.ComplianceStatus = $false
        $subscriptionObject.Comments = $msgTable.ddosSubscriptionProtectionMissing -f $sub.Name, $protectedVNetCount, $includedVNetCount, $protectedPublicIpCount, $publicIpCount
    }

    # Add profile details when this run is using the multi-cloud profile feature.
    if ($EnableMultiCloudProfiles) {
        $subscriptionObject = Add-ProfileInformation -Result $subscriptionObject -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $sub.Id -ErrorList $ErrorList
    }

    return $subscriptionObject
}

function Get-VNetComplianceInformation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)][string] $token,
        [Parameter(Mandatory = $true)][string] $ControlName,
        [string] $itsgcode,
        [Parameter(Mandatory = $false)][string] $ExcludedVNets,
        [hashtable] $msgTable,
        [Parameter(Mandatory = $true)][string] $ReportTime,
        [Parameter(Mandatory = $false)][string] $CBSSubscriptionName,
        [Parameter(Mandatory = $false)][switch] $debuginfo,
        [string] $ModuleProfiles,
        [string] $CloudUsageProfiles = "3",
        [switch] $EnableMultiCloudProfiles
    )

    $ResultList = [System.Collections.ArrayList]::new()
    $ErrorList = [System.Collections.ArrayList]::new()
    $ExcludeVnetTag = "GR9-ExcludeVNetFromCompliance"

    # Get the enabled subscriptions this module should inspect.
    try {
        $subs = Get-AzSubscription -ErrorAction Stop | Where-Object { $_.State -eq 'Enabled' }
    }
    catch {
        $errorMessage = "Failed to execute 'Get-AzSubscription'. Verify permissions and Az.Accounts module installation. Error: $_"
        $ErrorList.Add($errorMessage) | Out-Null
        throw $errorMessage
    }

    # Convert the comma-separated exclusion list into an array so name matching is simple.
    $ExcludedVNetsList = if ($ExcludedVNets) { $ExcludedVNets.Split(",") } else { @() }

    # Check each subscription and create one compliance row for each one.
    foreach ($sub in $subs) {
        Write-Verbose "Processing subscription: $($sub.Name)"
        Select-AzSubscription -SubscriptionObject $sub | Out-Null

        # Read all VNets in the subscription.
        # Then remove any VNet that is excluded by tag or by the explicit exclusion list.
        $allVNETs = Get-AzVirtualNetwork
        $includedVNETs = @($allVNETs | Where-Object {
            $_.Tag.$ExcludeVnetTag -ine 'true' -and $_.Name -notin $ExcludedVNetsList
        })
        Write-Verbose "Subscription '$($sub.Name)': Found $(@($allVNETs).Count) VNet(s); $($includedVNETs.Count) included after exclusions."

        # Read the public IP counts and protection counts for the same subscription.
        $publicIpStatus = Get-SubscriptionPublicIpStatus -SubscriptionId $sub.Id -SubscriptionName $sub.Name -msgTable $msgTable -ErrorList $ErrorList

        # Combine the VNet data and public IP data into one final compliance row.
        $resultObject = Get-SubscriptionComplianceObject -sub $sub -includedVNETs $includedVNETs -publicIpStatus $publicIpStatus -msgTable $msgTable -ControlName $ControlName -itsgcode $itsgcode -ReportTime $ReportTime -EnableMultiCloudProfiles $EnableMultiCloudProfiles.IsPresent -ErrorList $ErrorList -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        $ResultList.Add($resultObject) | Out-Null
    }

    # Optional debug output that prints the rows this module produced.
    if ($debuginfo) {
        Write-Output "Listing $($ResultList.Count) List members."
        $ResultList | ForEach-Object { Write-Output "Subscription: $($_.SubscriptionName) - Compliant: $($_.ComplianceStatus) Comments: $($_.Comments)" }
    }

    # Return the results
    return [PSCustomObject]@{
        ComplianceResults = $ResultList
        Errors            = $ErrorList
    }
}
