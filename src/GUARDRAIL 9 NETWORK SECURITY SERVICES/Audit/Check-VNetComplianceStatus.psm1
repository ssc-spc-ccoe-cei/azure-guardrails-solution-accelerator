function Invoke-ArgPagedQuery {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string] $Query,
        [Parameter(Mandatory = $true)][string] $SubscriptionId
    )

    # Resource Graph returns large result sets a page at a time.
    # This helper keeps requesting the next page until there are no more rows.
    $allResults = [System.Collections.ArrayList]::new()
    $skipToken = $null

    do {
        if ($skipToken) {
            $pageResults = Search-AzGraph -Query $Query -Subscription $SubscriptionId -First 1000 -SkipToken $skipToken -ErrorAction Stop
        }
        else {
            $pageResults = Search-AzGraph -Query $Query -Subscription $SubscriptionId -First 1000 -ErrorAction Stop
        }

        foreach ($row in $pageResults) {
            $allResults.Add($row) | Out-Null
        }

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
        [Parameter(Mandatory = $true)][System.Collections.ArrayList] $ErrorList
    )

    # We count all public IP resources in the
    # subscription and check whether they show a DDoS protection mode.
    $publicIpQuery = @"
resources
| where type =~ 'microsoft.network/publicipaddresses'
| project publicIpName = name,
          protectionMode = tostring(properties.ddosSettings.protectionMode)
"@

    try {
        $publicIpResults = Invoke-ArgPagedQuery -Query $publicIpQuery -SubscriptionId $SubscriptionId
    }
    catch {
        $errorMessage = $msgTable.ddosPublicIpCheckFailed -f $SubscriptionName, $_
        $ErrorList.Add($errorMessage) | Out-Null
        Write-Warning $errorMessage

        return [PSCustomObject]@{
            QueryFailed        = $true
            PublicIpCount      = 0
            ProtectedPublicIps = 0
        }
    }

    $publicIps = @($publicIpResults)
    $protectedPublicIps = @(
        $publicIps | Where-Object {
            $_.protectionMode -in @('Enabled', 'VirtualNetworkInherited')
        }
    )

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
        [Parameter(Mandatory = $true)][System.Collections.ArrayList] $ErrorList,
        [string] $CloudUsageProfiles,
        [string] $ModuleProfiles
    )

    # For this check, any included VNet with VNet DDoS or
    # any public IP with DDoS protection will mark the
    # subscription compliant.
    $protectedVNetCount = @($includedVNETs | Where-Object { $_.EnableDdosProtection }).Count
    $includedVNetCount = @($includedVNETs).Count
    $protectedPublicIpCount = $publicIpStatus.ProtectedPublicIps
    $publicIpCount = $publicIpStatus.PublicIpCount
    $hasNoScopedResources = (-not $publicIpStatus.QueryFailed -and $includedVNetCount -eq 0 -and $publicIpCount -eq 0)

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

    try {
        $subs = Get-AzSubscription -ErrorAction Stop | Where-Object { $_.State -eq 'Enabled' }
    }
    catch {
        $errorMessage = "Failed to execute 'Get-AzSubscription'. Verify permissions and Az.Accounts module installation. Error: $_"
        $ErrorList.Add($errorMessage) | Out-Null
        throw $errorMessage
    }

    $ExcludedVNetsList = if ($ExcludedVNets) { $ExcludedVNets.Split(",") } else { @() }

    foreach ($sub in $subs) {
        Write-Verbose "Processing subscription: $($sub.Name)"
        Select-AzSubscription -SubscriptionObject $sub | Out-Null

        $allVNETs = Get-AzVirtualNetwork
        $includedVNETs = @($allVNETs | Where-Object {
            $_.Tag.$ExcludeVnetTag -ine 'true' -and $_.Name -notin $ExcludedVNetsList
        })
        Write-Verbose "Subscription '$($sub.Name)': Found $(@($allVNETs).Count) VNet(s); $($includedVNETs.Count) included after exclusions."

        $publicIpStatus = Get-SubscriptionPublicIpStatus -SubscriptionId $sub.Id -SubscriptionName $sub.Name -msgTable $msgTable -ErrorList $ErrorList
        $resultObject = Get-SubscriptionComplianceObject -sub $sub -includedVNETs $includedVNETs -publicIpStatus $publicIpStatus -msgTable $msgTable -ControlName $ControlName -itsgcode $itsgcode -ReportTime $ReportTime -EnableMultiCloudProfiles $EnableMultiCloudProfiles.IsPresent -ErrorList $ErrorList -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        $ResultList.Add($resultObject) | Out-Null
    }

    if ($debuginfo) {
        Write-Output "Listing $($ResultList.Count) List members."
        $ResultList | ForEach-Object { Write-Output "Subscription: $($_.SubscriptionName) - Compliant: $($_.ComplianceStatus) Comments: $($_.Comments)" }
    }

    return [PSCustomObject]@{
        ComplianceResults = $ResultList
        Errors            = $ErrorList
    }
}
