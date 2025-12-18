function Check-CBSSensors {
    param (
        [string] $SubscriptionName , 
        [string] $TenantID , 
        [string] $ControlName, `
        [string] $ItemName,  
        [string] $itsgcode,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime,
        [string] 
        $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] $EnableMultiCloudProfiles # New feature flag, default to false    
    ) 

    $IsCompliant = $true
    $Comments = ""


    $FirstTokenInTenantID = $TenantID.Split("-")[0]
    $CBSResourceNamesV3 = @(
        "cbsstate$FirstTokenInTenantID",
        "cbs-$FirstTokenInTenantID-CanadaCentral",
        "cbs-$FirstTokenInTenantID-CanadaEast"
    )

    $CBSResourceNamesV2 = @(
        "cbs-vault-$FirstTokenInTenantID",
        "cbs-$FirstTokenInTenantID",
        "cbs-$FirstTokenInTenantID-CanadaCentral",
        "cbs-$FirstTokenInTenantID-CanadaEast"
    )
    
    if ($debug) { Write-Output $CBSResourceNamesV3 }
    if ($debug) { Write-Output $CBSResourceNamesV2 }

    $sub = Get-AzSubscription -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Enabled' -and $_.Name -eq $SubscriptionName }
    if ($null -eq $sub) {
        $IsCompliant = $false
        # $Object | Add-Member -MemberType NoteProperty -Name Comments -Value $msgTable.cbsSubDoesntExist
        $Comments = $msgTable.cbsSubDoesntExist
        $MitigationCommands = $msgTable.cbssMitigation -f $SubscriptionName
        
    } else {
        Set-AzContext -Subscription $sub

        $isV3Sensor = $true
        foreach ($CBSResourceName in $CBSResourceNamesV3) {
            if ($debug) { Write-Output "Searching for CBS Sensor V3 resource: $CBSResourceName" }
            if ([string]::IsNullOrEmpty((Get-AzResource -Name $CBSResourceName))) {
                if ($debug) { Write-Output "Missing V3 resource: $CBSResourceName" }
                $isV3Sensor = $false
                break
            }
        }

        $isV2Sensor = $false
        if (-not $isV3Sensor) {
            $isV2Sensor = $true
            foreach ($CBSResourceName in $CBSResourceNamesV2) {
                if ($debug) { Write-Output "Searching for CBS Sensor V2 resource: $CBSResourceName" }
                if ([string]::IsNullOrEmpty((Get-AzResource -Name $CBSResourceName))) {
                    if ($debug) { Write-Output "Missing V2 resource: $CBSResourceName" }
                    $isV2Sensor = $false
                    break
                }
            }
        }

        $IsCompliant = ($isV3Sensor -or $isV2Sensor)

        if ($IsCompliant) {
            $Comments = "$($msgTable.cbssCompliant) $SubscriptionName"
            if ($isV3Sensor) {
                $Comments += " " + $msgTable.cbssV3DetectedSuffix
            }
            elseif ($isV2Sensor) {
                $Comments += " " + $msgTable.cbssV2DeprecatedWarning
            }
            $MitigationCommands = "N/A."
        } else { 
            $Comments = "$($msgTable.cbcSensorsdontExist) $SubscriptionName"
            $MitigationCommands = "Contact CBS to deploy sensors."
        }
    }

    $Object = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName = $ControlName
        Comments = $Comments
        ItemName = $ItemName
        ReportTime = $ReportTime
        itsgcode = $itsgcode
    }
    $Object | Add-Member -MemberType NoteProperty -Name MitigationCommands -Value $MitigationCommands| Out-Null

    # Add profile information if MCUP feature is enabled
    if ($EnableMultiCloudProfiles) {
        $result = Add-ProfileInformation -Result $Object -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $sub.Id -ErrorList $ErrorList
        Write-Host "$result"
    }

    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = $Object 
        Errors = $ErrorList
        AdditionalResults = $AdditionalResults
    }
    
    return $moduleOutput

}
