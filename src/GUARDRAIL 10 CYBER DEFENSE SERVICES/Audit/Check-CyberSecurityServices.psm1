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
    $Object = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName = $ControlName
        ItemName = $ItemName
        Comments = $Comments
        ReportTime = $ReportTime
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
        $Object | Add-Member -MemberType NoteProperty -Name Comments -Value $msgTable.cbsSubDoesntExist
        $MitigationCommands = $msgTable.cbssMitigation -f $SubscriptionName
        if ($EnableMultiCloudProfiles) {
            $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $sub.Id
            if (!$evalResult.ShouldEvaluate) {
                if(!$evalResult.ShouldAvailable ){
                    if ($evalResult.Profile -gt 0) {
                        $Object.ComplianceStatus = "Not Available"
                        $Object | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                        $Object.Comments = "Not available - Profile $($evalResult.Profile) not applicable for this guardrail"
                    } else {
                        $ErrorList.Add("Error occurred while evaluating profile configuration availability")
                    }
                } else {
                    if ($evalResult.Profile -gt 0) {
                        $Object.ComplianceStatus = "Not Applicable"
                        $Object | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                        $Object.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
                    } else {
                        $ErrorList.Add("Error occurred while evaluating profile configuration")
                    }
                }
            } else {
                
                $Object | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
            }
        }
    } else {
        Set-AzContext -Subscription $sub

        if ($EnableMultiCloudProfiles) {        
            $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $sub.Id
            if (!$evalResult.ShouldEvaluate) {
                if(!$evalResult.ShouldAvailable ){
                    if ($evalResult.Profile -gt 0) {
                        $Object.ComplianceStatus = "Not Available"
                        $Object | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                        $Object.Comments = "Not available - Profile $($evalResult.Profile) not applicable for this guardrail"
                    } else {
                        $ErrorList.Add("Error occurred while evaluating profile configuration availability")
                    }
                } else {
                    if ($evalResult.Profile -gt 0) {
                        $Object.ComplianceStatus = "Not Applicable"
                        $Object | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                        $Object.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
                    } else {
                        $ErrorList.Add("Error occurred while evaluating profile configuration")
                    }
                }
            } else {
                
                $Object | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
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
