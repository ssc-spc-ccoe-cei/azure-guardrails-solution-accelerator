function get-tenantdata {
    param (
        $WorkSpaceID,
        [Parameter(Mandatory=$true)]
        [string]
        $workspaceKey,
        [Parameter(Mandatory=$false)]
        [string]
        $LogType="GuardrailsTenantsCompliance",
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime,
        [Parameter(Mandatory=$true)]
        [string]
        $TenantName, #aggregation tenant Name
        [Parameter(Mandatory=$true)]
        [string]
        $TenantID, #aggregation tenant ID
        [Parameter(Mandatory=$true)]
        [string]
        $tenantDomainUPN,
        [Parameter(Mandatory=$false)]
        [switch]
        $DebugInfo
    )
    "Querying for tenant data - Workspaces"
    $wsidList=Search-azgraph -first 300 -Query 'resources| where type == "microsoft.operationalinsights/workspaces"| project name, rg=split(id, "/")[4],wsid=properties.customerId' -UseTenantScope
    if ($wsidList.count -eq 0)
    {
        "No ws found."
        break
    }
    else {
        "Found $($wsidList.count) workspaces."
    }
    "Time of data collection: $ReportTime"

        $generalQuery=@"
    GuardrailsCompliance_CL | where ControlName_s has "{0}" and ReportTime_s == "{1}"
    | where TimeGenerated > ago (24h)
    | project Mandatory=Required_s,ControlName_s, ItemName=ItemName_s, Status=iif(tostring(ComplianceStatus_b)=="True", 'Compliant', 'Non-Compliant'),["ITSG Control"]=itsgcode_s
    | summarize Count=count() by Mandatory,ControlName_s,ItemName, Status, ["ITSG Control"]
"@
    $gr567Query=@"
GuardrailsCompliance_CL
| where ControlName_s has "{0}" and ReportTime_s == "{1}"
| where TimeGenerated > ago (24h)
| project Mandatory=Required_s,ControlName_s, Type=Type_s, Name=DisplayName_s, ItemName=ItemName_s, Status=iif(tostring(ComplianceStatus_b)=="True", 'Compliant', 'Non-Compliant'),["ITSG Control"]=itsgcode_s
| summarize Count=count() by Mandatory, ControlName_s,ItemName,Status,["ITSG Control"]
"@
        $gr8query=@"
    let itsgcodes=GRITSGControls_CL | summarize arg_max(TimeGenerated, *) by itsgcode_s;
    let ctrlprefix="GUARDRAIL 8";
    GuardrailsCompliance_CL
    | where ControlName_s has ctrlprefix and ReportTime_s == "{0}"
    | where TimeGenerated > ago (6h)
    |join kind=inner (itsgcodes) on itsgcode_s
    | project Mandatory=Required_s,ControlName_s, SubnetName=SubnetName_s, ItemName=ItemName_s, Status=iif(tostring(ComplianceStatus_b)=="True", 'Compliant', 'Non-Compliant'), ["ITSG Control"]=itsgcode_s, Definition=Definition_s,Mitigation=gr_geturl(replace_string(ctrlprefix," ",""),itsgcode_s)
    | summarize Count=count(SubnetName) by Mandatory, ControlName_s, Status,ItemName, ['ITSG Control']
"@
        $gr9query=@"
    let itsgcodes=GRITSGControls_CL | summarize arg_max(TimeGenerated, *) by itsgcode_s;
    let ctrlprefix="GUARDRAIL 9";
    GuardrailsCompliance_CL
    | where ControlName_s has ctrlprefix and ReportTime_s == "{0}"
    | where TimeGenerated > ago (12h)
    |join kind=inner (itsgcodes) on itsgcode_s
    | project Mandatory=Required_s,ControlName_s, ['VNet Name']=VNETName_s, ItemName=ItemName_s, Status=iif(tostring(ComplianceStatus_b)=="True", 'Compliant', 'Non-Compliant'), ["ITSG Control"]=itsgcode_s, Definition=Definition_s,Mitigation=gr_geturl(replace_string(ctrlprefix," ",""),itsgcode_s)
    | summarize Count=count('VNet Name') by Mandatory,ControlName_s, Status, ItemName,['ITSG Control']
"@
    [PSCustomObject] $FinalObjectList = New-Object System.Collections.ArrayList
    foreach ($ws in $wsidList.wsid)
    {
        "Working on $ws workspace."
        # Get latest report time for that Tenant
        try {
            $Query="GR_TenantInfo_CL | summarize arg_max(ReportTime_s, *) by TenantDomain_s | project  DepartmentTenantID=DepartmentTenantID_g,TenantDomain=TenantDomain_s,TenantDomainName=DepartmentTenantName_s, DepartmentName=column_ifexists('DepartmentName_s','N/A'), DepartmentNumber=column_ifexists('DepartmentNumber_s','N/A'),CloudUsageProfiles=cloudUsageProfiles_s"
            $resultsArray = [System.Linq.Enumerable]::ToArray((Invoke-AzOperationalInsightsQuery -WorkspaceId $ws -Query $Query -errorAction SilentlyContinue).Results)   
            $TenantDomain=$resultsArray[0].TenantDomain
            $DepartmentName=$resultsArray[0].DepartmentName
            $DepartmentNumber=$resultsArray[0].DepartmentNumber
            $DepartmentTenantName=$resultsArray[0].TenantDomainName
            $DepartmentTenantId=$resultsArray[0].DepartmentTenantID
            $DepartmentCloudUsageProfiles=$resultsArray[0].CloudUsageProfiles
        }
        catch {
            "Error reading info from $ws workspace."
            $TenantDomain=""
        }
        # Now getting version info for that tenant
        try {
            $Query="GR_VersionInfo_CL | project DeployedVersion=DeployedVersion_s, AvailableVersion=AvailableVersion_s, UpdatedNeeded=UpdateNeeded_b, CheckDate=ReportTime_s"
            $resultsArray = [System.Linq.Enumerable]::ToArray((Invoke-AzOperationalInsightsQuery -WorkspaceId $ws -Query $Query -errorAction SilentlyContinue).Results)   
            $DepartmentDeployedVersion=$resultsArray[0].DeployedVersion
            $DepartmentAvailableVersion=$resultsArray[0].AvailableVersion
            $DepartmentUpdatedNeeded=$resultsArray[0].UpdatedNeeded
            $DepartmentVersionCheckDate=$resultsArray[0].CheckDate
        }
        catch {
            "Error reading info from $ws workspace."
            $TenantDomain=""
        }
        if ($TenantDomain -ne "")
        {

            $ReportTimeQuery="GuardrailsCompliance_CL | where TimeGenerated > ago(6h)| summarize mrt=max(ReportTime_s)"
            $resultsArray = [System.Linq.Enumerable]::ToArray((Invoke-AzOperationalInsightsQuery -WorkspaceId $ws -Query $ReportTimeQuery).Results)   
            $LatestRT=$resultsArray[0].mrt
            if ([string]::IsNullOrEmpty($LatestRT)) {
                "No data found for $TenantDomain."
            }
            else {
                <# Action when all if and elseif conditions are false #>               
                "$TenantDomain @ $LatestRT"
                $QueryList=@($generalQuery -f "GUARDRAIL 1:",$LatestRT)
                $QueryList+=$generalQuery -f "GUARDRAIL 2",$LatestRT
                $QueryList+=$generalQuery -f "GUARDRAIL 3",$LatestRT
                $QueryList+=$generalQuery -f "GUARDRAIL 4",$LatestRT
                $QueryList+=$gr567Query -f "GUARDRAIL 5",$LatestRT
                $QueryList+=$gr567Query -f "GUARDRAIL 6",$LatestRT
                $QueryList+=$gr567Query -f "GUARDRAIL 7",$LatestRT
                $QueryList+= $gr8query -f $LatestRT
                $QueryList+= $gr9query -f $LatestRT
                $QueryList+=$generalQuery -f "GUARDRAIL 10",$LatestRT
                $QueryList+=$generalQuery -f "GUARDRAIL 11",$LatestRT
                $QueryList+=$generalQuery -f "GUARDRAIL 12",$LatestRT
                
                foreach ($Query in $QueryList)
                {
                    if ($DebugInfo) { $Query }
                    try {
                        $response=(Invoke-AzOperationalInsightsQuery -WorkspaceId $ws -Query $Query -errorAction SilentlyContinue).Results
                    }
                    catch {
                        "Error querying WS $ws."
                    }
                    if ($response)
                    {
                        $tempArray = [System.Linq.Enumerable]::ToArray($response)  
                        if ($debuginfo) {
                            " Found $($tempArray.count) items running the query."
                        }
                        # Gets aggregation tenant info. This is commented because it won't work without special permissions for the function MI.
                        # $response = Invoke-AzRestMethod -Method get -uri 'https://graph.microsoft.com/v1.0/organization' | Select-Object -expand Content | convertfrom-json
                        # $tenantId = $response.value.id
                        # $tenantName= $response.value.displayName
                        # $tenantDomainUPN = $response.value.verifiedDomains | Where-Object { $_.isDefault } | Select-Object -ExpandProperty name # onmicrosoft.com is verified and default by default
                        
                        #$tempArray=$tempArray | Select-Object ControlName_s, ItemName, Status
                        #tenant info
                        $tempArray | Add-Member -MemberType NoteProperty -Name TenantDomain -Value $TenantDomain -Force | Out-Null
                        $tempArray | Add-Member -MemberType NoteProperty -Name DepartmentName -Value $DepartmentName -Force | Out-Null
                        $tempArray | Add-Member -MemberType NoteProperty -Name DepartmentNumber -Value $DepartmentNumber -Force | Out-Null
                        $tempArray | Add-Member -MemberType NoteProperty -Name DepartmentTenantName -Value $DepartmentTenantName -Force | Out-Null
                        $tempArray | Add-Member -MemberType NoteProperty -Name DepartmentTenantID -Value $DepartmentTenantId -Force | Out-Null
                        $tempArray | Add-Member -MemberType NoteProperty -Name AggregationTenantID -Value $TenantID -Force | Out-Null
                        $tempArray | Add-Member -MemberType NoteProperty -Name AggregationTenantName -Value $TenantName -Force | Out-Null
                        $tempArray | Add-Member -MemberType NoteProperty -Name AggregationTenantUPN -Value $tenantDomainUPN -Force | Out-Null
                        $tempArray | Add-Member -MemberType NoteProperty -Name DepartmentCloudUsageProfiles -Value $DepartmentCloudUsageProfiles -Force | Out-Null
                        
                        # Report time info
                        $tempArray | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force | Out-Null
                        $tempArray | Add-Member -MemberType NoteProperty -Name DepartmentReportTime -Value $LatestRT -Force | Out-Null
                        # Version info
                        $tempArray | Add-Member -MemberType NoteProperty -Name DeployedVersion -Value $DepartmentDeployedVersion -Force | Out-Null
                        $tempArray | Add-Member -MemberType NoteProperty -Name AvailableVersion -Value $DepartmentAvailableVersion -Force | Out-Null
                        $tempArray | Add-Member -MemberType NoteProperty -Name UpdatedNeeded -Value $DepartmentUpdatedNeeded -Force | Out-Null
                        $tempArray | Add-Member -MemberType NoteProperty -Name DepartmentVersionCheckDate -Value $DepartmentVersionCheckDate -Force | Out-Null
                        # Workspace info
                        $tempArray | Add-Member -MemberType NoteProperty -Name WSId -Value $ws -Force 
                        if ($DebugInfo) { $tempArray}
                        $FinalObjectList+=$tempArray
                    }
                }  
            }
        }
    }
    if ($FinalObjectList) {
        "$($FinalObjectList.count) objects found to send."
        if ($DebugInfo) {
            "Writing to debug file."
            $FinalObjectList | Out-File ./debubinfo_finalobjectlist.txt
        }
        $FinalObjectListJson = $FinalObjectList | ConvertTo-Json
        Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
        -sharedkey $workspaceKey `
        -body $FinalObjectListJson `
        -logType $LogType `
        -TimeStampField Get-Date
    }
    else { "No data to send" }
}