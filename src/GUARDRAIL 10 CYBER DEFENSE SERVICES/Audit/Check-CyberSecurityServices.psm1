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
    $CBSResourceNames = @(
        "cbs-$FirstTokenInTenantID",
        "cbs-$FirstTokenInTenantID-CanadaCentral",
        "cbs-$FirstTokenInTenantID-CanadaEast",
        "cbs-vault-$FirstTokenInTenantID"
    )
    
    if ($debug) { Write-Output $CBSResourceNames }

    $sub = Get-AzSubscription -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Enabled' -and $_.Name -eq $SubscriptionName }
    if ($null -eq $sub) {
        $IsCompliant = $false
        # $Object | Add-Member -MemberType NoteProperty -Name Comments -Value $msgTable.cbsSubDoesntExist
        $Comments = $msgTable.cbsSubDoesntExist
        $MitigationCommands = $msgTable.cbssMitigation -f $SubscriptionName
        
    } else {
        Set-AzContext -Subscription $sub

        foreach ($CBSResourceName in $CBSResourceNames) {
            if ($debug) { Write-Output "Searching for CBS Sensor: $CBSResourceName" }
            if ([string]::IsNullOrEmpty((Get-AzResource -Name $CBSResourceName))) {
                if ($debug) { Write-Output "Missing $CBSResourceName" }
                $IsCompliant = $false 
                break
            }
        }

        if ($IsCompliant) {
            $Comments = "$($msgTable.cbssCompliant) $SubscriptionName"
            $MitigationCommands = "N/A."
        } else { 
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
        $result = Add-ProfileInformation -Result $Object -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId -ErrorList $ErrorList
        Write-Host "$result"
    }

    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = $Object 
        Errors = $ErrorList
        AdditionalResults = $AdditionalResults
    }
    
    return $moduleOutput

}
