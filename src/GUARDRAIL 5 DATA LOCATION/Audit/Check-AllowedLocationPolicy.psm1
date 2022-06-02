function Verify-AllowedLocationPolicy {
    param (
        [string] $ControlName,
        [string] $ItemName,
        [string] $PolicyID, 
        [string] $WorkSpaceID,
        [string] $workspaceKey,
        [string] $LogType,
        [switch] $Debug,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime,
        [Parameter(Mandatory=$true)]
        [string]
        $CBSSubscriptionName
    )

    #$PolicyID = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"

    [System.Object] $RootMG = $null
    [string] $PolicyID = $policyID
    [PSCustomObject] $MGList = New-Object System.Collections.ArrayList
    [PSCustomObject] $MGItems = New-Object System.Collections.ArrayList
    [PSCustomObject] $SubscriptionList = New-Object System.Collections.ArrayList
    [PSCustomObject] $CompliantList = New-Object System.Collections.ArrayList
    [PSCustomObject] $NonCompliantList = New-Object System.Collections.ArrayList
    [string] $Comment1 = "The Policy or Initiative is not assigned on the "
    [string] $Comment2 = " is excluded from the scope of the assignment"
    [string] $Comment3 = "Compliant"
    [string] $Comment4 = "The Policy or Initiative is not assigned on the Root Management Groups. "
    [string] $Comment5 = "This Root Management Groups is excluded from the scope of the assignment"

    $AllowedLocations = @("canada" , "canadaeast" , "canadacentral")

    foreach ($mg in Get-AzManagementGroup) {
        $MG = Get-AzManagementGroup -GroupName $mg.Name -Expand -Recurse
        $MGItems.Add($MG)
        if ($null -eq $MG.ParentId) {
            $RootMG = $MG
        }
    }
    foreach ($items in $MGItems) {
        foreach ($Children in $items.Children ) {
            foreach ($c in $Children) {
                if ($c.Type -eq "/subscriptions" -and (-not $SubscriptionList.Contains($c) -and $c.DisplayName -ne $CBSSubscriptionName)) {
                    [string]$type = "subscription"
                    $SubscriptionList.Add($c)
                    $AssignedPolicyList = Get-AzPolicyAssignment -scope $c.Id -PolicyDefinitionId $PolicyID
                    $AssignedPolicyLocation = $AssignedPolicyList.Properties.Parameters.listOfAllowedLocations.value

                    If ($null -eq $AssignedPolicyList) {
                        $c | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
                        $c | Add-Member -MemberType NoteProperty -Name Comments -Value "$Comment1$type"
                        $c | Add-Member -MemberType NoteProperty -Name ComplianceStatus -Value $false
                        $c | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName
                        $c | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName
                        $NonCompliantList.add($c)
                    }
                    elseif (-not ([string]::IsNullOrEmpty(($AssignedPolicyList.Properties.NotScopesScope)))   ) {
                        $c | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
                        $c | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName
                        $c | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName
                        $c | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $false
                        if (-not (Test-AllowedLocation -AssignedLocations $AssignedPolicyLocation -AllowedLocations $AllowedLocations)  ) {
                            $c | Add-Member -MemberType NoteProperty -Name Comments -Value $("$type$Comment2" + " Location is outside of the allowed locations. ")
                        }
                        else {
                            $c | Add-Member -MemberType NoteProperty -Name Comments -Value "$type$Comment2"
                        }
                        $NonCompliantList.add($c)  
                    }
                    else {
                        $c | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
                        $c | Add-Member -MemberType NoteProperty -Name Comments -Value $Comment3
                        $c | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $true
                        $c | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName
                        $c | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName
                        $CompliantList.add($c) 
                    }
                }
                elseif ($c.Type -like "*managementGroups*" -and (-not $MGList.Contains($c)) ) {
                    [string]$type = "Management Groups"
                    $MGList.Add($c)
                    $AssignedPolicyList = Get-AzPolicyAssignment -scope $c.Id -PolicyDefinitionId $PolicyID
                    If ($null -eq $AssignedPolicyList) {
                        $c | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
                        $c | Add-Member -MemberType NoteProperty -Name Comments -Value "$Comment1$type"
                        $c | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $false
                        $c | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName
                        $c | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName
                        $NonCompliantList.add($c)
                    }
                    elseif (-not ([string]::IsNullOrEmpty(($AssignedPolicyList.Properties.NotScopesScope)))) {
                        $c | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
                        $c | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName
                        $c | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName
                        $c | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $false
                        if (-not (Test-AllowedLocation -AssignedLocations $AssignedPolicyLocation -AllowedLocations $AllowedLocations)  ) {
                            $c | Add-Member -MemberType NoteProperty -Name Comments -Value $("$type$Comment2 - Location is outside of the allowed locations.")
                        }
                        else {
                            $c | Add-Member -MemberType NoteProperty -Name Comments -Value "$type$Comment2"
                        }
                        $NonCompliantList.add($c)  
                    }
                    else {       
                        $c | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
                        $c | Add-Member -MemberType NoteProperty -Name Comments -Value $Comment3
                        $c | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $true
                        $c | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName
                        $c | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName
                        $CompliantList.add($c) 
                    }
                }
            }                
        }
    }


    $AssignedPolicyList = Get-AzPolicyAssignment -scope $RootMG.Id -PolicyDefinitionId $PolicyID
    If ($null -eq $AssignedPolicyList) {
        $RootMG | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
        $RootMG | Add-Member -MemberType NoteProperty -Name Comments -Value $Comment4
        $RootMG | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $false
        $RootMG | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName
        $RootMG | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName
        $NonCompliantList.add($RootMG)
    }
    elseif (-not ([string]::IsNullOrEmpty(($AssignedPolicyList.Properties.NotScopesScope)))) {
        $RootMG | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
        $RootMG | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName
        $RootMG | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName
        $RootMG | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $false
        if (-not (Test-AllowedLocation -AssignedLocations $AssignedPolicyLocation -AllowedLocations $AllowedLocations)  ) {
            $RootMG | Add-Member -MemberType NoteProperty -Name Comments -Value $($Comment5 + "- Location is outside of the allowed locations. ")
        }
        else {
            $RootMG | Add-Member -MemberType NoteProperty -Name Comments -Value $Comment5
        }
        $NonCompliantList.add($RootMG)  
    }
    else {       
        $RootMG | Add-Member -MemberType NoteProperty -Name Comments -Value $Comment3
        $RootMG | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $true
        $RootMG | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName -Force
        $RootMG | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName -Force
        $RootMG | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
        $CompliantList.add($RootMG) 
    }
    if ($CompliantList.Count -gt 0) {
        $JsonObject = $CompliantList | convertTo-Json
        if ($Debug) {
            "Sending Compliant data."
            "Id: $WorkSpaceID"
            "Key: $workspaceKey"
            "Body: $JsonObject"
        }
        Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
            -sharedkey $workspaceKey `
            -body $JsonObject `
            -logType $LogType `
            -TimeStampField Get-Date
    }
    if ($NonCompliantList.Count -gt 0) {
        $JsonObject = $NonCompliantList | convertTo-Json  
        if ($Debug) {
            "Sending Non-Compliant data."
            "Id: $WorkSpaceID"
            "Key: $workspaceKey"
            "Body: $JsonObject"
        }
        Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
            -sharedkey $workspaceKey `
            -body $JsonObject `
            -logType $LogType `
            -TimeStampField Get-Date
    }
}


function Test-AllowedLocation {
    param (
        [array] $AssignedLocations,
        [array] $AllowedLocations
    )
    $IsCompliant = $true
    foreach ($AssignedLocation in $AssignedLocations) {
        if ( $AssignedLocation -notin $AllowedLocations) {
            $IsCompliant = $false
        }
    }
    return $IsCompliant 
}


