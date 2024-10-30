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

        $allVNETs = Get-AzVirtualNetwork
        $includedVNETs = $allVNETs | Where-Object { $_.Tag.$ExcludeVnetTag -ine 'true' }
        Write-Debug "Found $($allVNETs.count) VNets total; $($includedVNETs.count) not excluded by tag."

        if ($includedVNETs.count -gt 0) {
            foreach ($VNet in $allVNETs) {
                $VNetObject = Get-VNetComplianceObject -VNet $VNet -sub $sub -ExcludedVNetsList $ExcludedVNetsList -includedVNETs $includedVNETs -msgTable $msgTable -ControlName $ControlName -itsgcode $itsgcode -ReportTime $ReportTime -EnableMultiCloudProfiles $EnableMultiCloudProfiles
                $VNetList.Add($VNetObject) | Out-Null
            }
        }
        else {
            $VNetObject = Get-NoVNetsComplianceObject -sub $sub -msgTable $msgTable -ControlName $ControlName -itsgcode $itsgcode -ReportTime $ReportTime -EnableMultiCloudProfiles $EnableMultiCloudProfiles
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

function Get-VNetComplianceObject {
    param ($VNet, $sub, $ExcludedVNetsList, $includedVNETs, $msgTable, $ControlName, $itsgcode, $ReportTime, $EnableMultiCloudProfiles)

    if ($vnet.Name -notin $ExcludedVNetsList -and $vnet.id -in $includedVNETs.id) {
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

    if ($EnableMultiCloudProfiles) {        
        $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $sub.Id
        if (!$evalResult.ShouldEvaluate) {
            if ($evalResult.Profile -gt 0) {
                $VNetObject.ComplianceStatus = "Not Applicable"
                $VNetObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                $VNetObject.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
            } else {
                $ErrorList.Add("Error occurred while evaluating profile configuration")
            }
        } else {
            Write-Output "Valid profile returned: $($evalResult.Profile)"
            $VNetObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
        }
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
        $EnableMultiCloudProfiles
    )

    $ComplianceStatus = $true

    $Comments = "$($msgTable.noVNets) - $($sub.Name)"

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

    if ($EnableMultiCloudProfiles) {        
        $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $sub.Id
        if (!$evalResult.ShouldEvaluate) {
            if ($evalResult.Profile -gt 0) {
                $VNetObject.ComplianceStatus = "Not Applicable"
                $VNetObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                $VNetObject.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
            } else {
                $ErrorList.Add("Error occurred while evaluating profile configuration")
            }
        } else {
            Write-Output "Valid profile returned: $($evalResult.Profile)"
            $VNetObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
        }
    }
    return $VNETObject
}


