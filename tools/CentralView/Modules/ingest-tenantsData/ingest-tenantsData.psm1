#$$wsidList=@("c2ffc603-69a7-4da1-a999-74b3fdc5f171","3235e0e7-74a4-481e-85e7-faa4d4fd6bc7")
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
        [Parameter(Mandatory=$false)]
        [switch]
        $DebugInfo
    )
    "Querying for tenant data - Workspaces"
    $wsidList=Search-azgraph -Query 'resources| where type == "microsoft.operationalinsights/workspaces"| project name, rg=split(id, "/")[4],wsid=properties.customerId | where tolower(rg) contains "guardrails"' -UseTenantScope
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
            $Query="GR_TenantInfo_CL | summarize arg_max(ReportTime_s, *) by TenantDomain_s | project TenantDomain=TenantDomain_s, DepartmentName=column_ifexists('DepartmentName_s','N/A'), DepartmentNumber=column_ifexists('DepartmentNumber_s','N/A')"
            $resultsArray = [System.Linq.Enumerable]::ToArray((Invoke-AzOperationalInsightsQuery -WorkspaceId $ws -Query $Query -errorAction SilentlyContinue).Results)   
            $TenantDomain=$resultsArray[0].TenantDomain
            $DepartmentName=$resultsArray[0].DepartmentName
            $DepartmentNumber=$resultsArray[0].DepartmentNumber
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
                        #$tempArray=$tempArray | Select-Object ControlName_s, ItemName, Status
                        $tempArray | Add-Member -MemberType NoteProperty -Name TenantDomain -Value $TenantDomain -Force | Out-Null
                        $tempArray | Add-Member -MemberType NoteProperty -Name DepartmentName -Value $DepartmentName -Force | Out-Null
                        $tempArray | Add-Member -MemberType NoteProperty -Name DepartmentNumber -Value $DepartmentNumber -Force | Out-Null
                        $tempArray | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force | Out-Null
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