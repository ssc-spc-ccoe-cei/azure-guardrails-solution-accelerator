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
    $Object = [PSCustomObject]@{
        ControlName = $ControlName
        ReportTime = $ReportTime
        ItemName = $ItemName
        itsgcode = $itsgcode
    }

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
        $Object.Comments = $msgTable.cbsSubDoesntExist
        $MitigationCommands = $msgTable.cbssMitigation -f $SubscriptionName
    } else {
        Set-AzContext -Subscription $sub

        if ($EnableMultiCloudProfiles) {        
            $result = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $sub.Id
            if ($result -is [int]) {
                Write-Output "Valid profile returned: $result"
                $Object | Add-Member -MemberType NoteProperty -Name "Profile" -Value $result
            } elseif ($result.Status -eq "Error") {
                Write-Error "Error occurred: $($result.Message)"
                $c.ComplianceStatus = "Not Applicable"
                Errorlist.Add($result.Message)
            } else {
                Write-Error "Unexpected result: $result"
            }
        }
        foreach ($CBSResourceName in $CBSResourceNames) {
            if ($debug) { Write-Output "Searching for CBS Sensor: $CBSResourceName" }
            if ([string]::IsNullOrEmpty((Get-AzResource -Name $CBSResourceName))) {
                if ($debug) { Write-Output "Missing $CBSResourceName" }
                $IsCompliant = $false 
                break
            }
        }

        if ($IsCompliant) {
            $Object | Add-Member -MemberType NoteProperty -Name Comments -Value "$($msgTable.cbssCompliant) $SubscriptionName)"| Out-Null
            $MitigationCommands = "N/A."
        } else {
            $Object | Add-Member -MemberType NoteProperty -Name Comments -Value $Comment2 | Out-Null   
            $MitigationCommands = "Contact CBS to deploy sensors."
        }
    }

    $Object | Add-Member -MemberType NoteProperty -Name ComplianceStatus -Value $IsCompliant| Out-Null
    $Object | Add-Member -MemberType NoteProperty -Name MitigationCommands -Value $MitigationCommands| Out-Null

    [PSCustomObject]@{ 
        ComplianceResults = $Object 
        Errors = $ErrorList
        AdditionalResults = $AdditionalResults
    }
}

