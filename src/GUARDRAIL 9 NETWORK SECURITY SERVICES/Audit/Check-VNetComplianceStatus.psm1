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

    # Initialize result collections
    $VNetList = [System.Collections.ArrayList]::new()
    $ErrorList = [System.Collections.ArrayList]::new()
    $ExcludeVnetTag = "GR9-ExcludeVNetFromCompliance"

    # Get subscriptions
    try {
        $subs = Get-AzSubscription -ErrorAction Stop | Where-Object { $_.State -eq 'Enabled' -and $_.Name -ne $CBSSubscriptionName }
    }
    catch {
        $errorMessage = "Failed to execute 'Get-AzSubscription'. Verify permissions and Az.Accounts module installation. Error: $_"
        $ErrorList.Add($errorMessage)
        throw $errorMessage
    }

    $ExcludedVNetsList = if ($ExcludedVNets) { $ExcludedVNets.Split(",") } else { @() }

    foreach ($sub in $subs) {
        Write-Verbose "Processing subscription: $($sub.Name)"
        Select-AzSubscription -SubscriptionObject $sub | Out-Null

        $evaluationProfile = Get-EvaluationProfileForSubscription -sub $sub -EnableMultiCloudProfiles $EnableMultiCloudProfiles -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles

        $allVNETs = Get-AzVirtualNetwork
        $includedVNETs = $allVNETs | Where-Object { $_.Tag.$ExcludeVnetTag -ine 'true' }
        Write-Debug "Found $($allVNETs.count) VNets total; $($includedVNETs.count) not excluded by tag."

        if ($includedVNETs.count -gt 0) {
            foreach ($VNet in $allVNETs) {
                $VNetObject = Get-VNetComplianceObject -VNet $VNet -sub $sub -ExcludedVNetsList $ExcludedVNetsList -includedVNETs $includedVNETs -msgTable $msgTable -ControlName $ControlName -itsgcode $itsgcode -ReportTime $ReportTime -evaluationProfile $evaluationProfile -EnableMultiCloudProfiles $EnableMultiCloudProfiles
                $VNetList.Add($VNetObject) | Out-Null
            }
        }
        else {
            $VNetObject = Get-NoVNetsComplianceObject -sub $sub -msgTable $msgTable -ControlName $ControlName -itsgcode $itsgcode -ReportTime $ReportTime -evaluationProfile $evaluationProfile -EnableMultiCloudProfiles $EnableMultiCloudProfiles
            $VNetList.Add($VNetObject) | Out-Null
        }
    }

    if ($debuginfo) { 
        Write-Output "Listing $($VNetList.Count) List members."
        $VNetList | ForEach-Object { Write-Output "VNet: $($_.VNETName) - Compliant: $($_.ComplianceStatus) Comments: $($_.Comments)" }
    }

    return [PSCustomObject]@{ 
        ComplianceResults = $VNetList 
        Errors            = $ErrorList
    }
}

function Get-EvaluationProfileForSubscription {
    param ($sub, $EnableMultiCloudProfiles, $CloudUsageProfiles, $ModuleProfiles)
    
    if (-not $EnableMultiCloudProfiles) { return $null }

    $result = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $sub.Id
    switch ($result) {
        { $_ -is [int] } { return $_ }
        { $_.Status -eq "Error" } { Write-Error $_.Message; return "Not Applicable" }
        default { Write-Error "Unexpected result: $_"; return $null }
    }
}

function Get-VNetComplianceObject {
    param ($VNet, $sub, $ExcludedVNetsList, $includedVNETs, $msgTable, $ControlName, $itsgcode, $ReportTime, $evaluationProfile, $EnableMultiCloudProfiles)

    if ($EnableMultiCloudProfiles -and $evaluationProfile -isnot [int]) {
        $ComplianceStatus = "Not Applicable"
        $Comments = "Profile is not applicable for this subscription"
    }
    elseif ($vnet.Name -notin $ExcludedVNetsList -and $vnet.id -in $includedVNETs.id) {
        $ComplianceStatus = $Vnet.EnableDdosProtection
        $Comments = if ($ComplianceStatus) { "$($msgTable.ddosEnabled) $($VNet.DdosProtectionPlan.Id)" } else { $msgTable.ddosNotEnabled }
    }
    else {
        $ComplianceStatus = $true
        $Comments = if ($VNet.Name -in $ExcludedVNetsList) {
            $msgTable.vnetExcludedByParameter -f $Vnet.name, $ExcludedVNets
        }
        elseif ($VNet.Name -notin $includedVNETs.Name) {
            $msgTable.vnetExcludedByTag -f $VNet.Name, $ExcludeVnetTag
        }
    }

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

    if ($EnableMultiCloudProfiles -and $evaluationProfile -is [int]) {
        $VNetObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evaluationProfile
    }

    return $VNetObject
}

function Get-NoVNetsComplianceObject {
    param (
        $sub,
        $msgTable,
        $ControlName,
        $itsgcode,
        $ReportTime,
        $evaluationProfile,  # Renamed from 'profile'
        $EnableMultiCloudProfiles
    )

    $ComplianceStatus = if ($EnableMultiCloudProfiles -and $evaluationProfile -isnot [int]) {
        "Not Applicable"
    } else {
        $true
    }

    $Comments = if ($EnableMultiCloudProfiles -and $evaluationProfile -isnot [int]) {
        "Profile is not applicable for this subscription"
    } else {
        "$($msgTable.noVNets) - $($sub.Name)"
    }

    $VNETObject = [PSCustomObject]@{ 
        SubscriptionName = $sub.Name 
        SubnetName       = $msgTable.noVNets
        ComplianceStatus = $ComplianceStatus
        Comments         = $Comments
        ItemName         = $msgTable.networkSegmentation
        ControlName      = $ControlName
        itsgcode         = $itsgcode
        ReportTime       = $ReportTime
    }

    if ($EnableMultiCloudProfiles -and $evaluationProfile -is [int]) {
        $VNETObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evaluationProfile
    }

    return $VNETObject
}


