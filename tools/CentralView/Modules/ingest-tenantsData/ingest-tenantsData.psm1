function Send-GuardrailsData {
    # Local copy of the DCR-based ingestion function from src/Guardrails-Common/GR-Common.psm1
    # so the Function App package is self-contained (the src/ folder is not deployed to wwwroot).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $Data,
        [Parameter(Mandatory = $true)] [string] $LogType,
        [Parameter(Mandatory = $false)] [string] $WorkSpaceID,
        [Parameter(Mandatory = $false)] [string] $WorkSpaceKey
    )

    $dceEndpoint    = $env:DCE_ENDPOINT
    $dcrImmutableId = $env:DCR_IMMUTABLE_ID

    if (-not $dceEndpoint)    { throw "DCE_ENDPOINT app setting is not set on the Function App." }
    if (-not $dcrImmutableId) { throw "DCR_IMMUTABLE_ID app setting is not set on the Function App." }

    $streamName = switch ($LogType) {
        'GuardrailsTenantsCompliance' { 'Custom-GuardrailsTenantsCompliance' }
        default                       { "Custom-$LogType" }
    }

    if ($Data.Trim().StartsWith('{')) { $Data = "[$Data]" }
    if ([string]::IsNullOrWhiteSpace($Data) -or $Data.Trim() -eq '[]') {
        Write-Warning "Send-GuardrailsData: empty payload for '$LogType', skipping."
        return
    }

    # DCR Log Ingestion API does NOT auto-coerce types and does NOT auto-fill TimeGenerated.
    # The stream declaration in law.bicep declares the type of every column; the payload must match.
    # If we send 'Mandatory' as a boolean but the schema says string, the whole batch is rejected with 400.
    # So:
    #   - inject TimeGenerated (ISO 8601 UTC) on every record
    #   - force every field to the type the schema expects (per Custom-GuardrailsTenantsCompliance stream).
    $stringFields = @(
        'Mandatory','ControlName_s','ItemName','Profile','Status','ITSG Control','SubnetName',
        'Definition','Remediation','VNet Name','TenantDomain','DepartmentName','DepartmentNumber',
        'DepartmentTenantName','DepartmentTenantID','DepartmentCloudUsageProfiles','AggregationTenantID',
        'AggregationTenantName','AggregationTenantUPN','ReportTime','DepartmentReportTime',
        'DeployedVersion','AvailableVersion','DepartmentVersionCheckDate','WSId','ControlName',
        'Comments','itsgcode','Required','DisplayName','SubscriptionName','VNETName'
    )
    $longFields    = @('Count')
    $boolFields    = @('UpdatedNeeded')
    try {
        $records = $Data | ConvertFrom-Json
        if ($records -isnot [System.Collections.IEnumerable] -or $records -is [string]) {
            $records = @($records)
        }
        $nowIso = (Get-Date).ToUniversalTime().ToString('o')
        foreach ($r in $records) {
            # TimeGenerated (datetime) - required by every DCR stream
            if (-not ($r.PSObject.Properties.Name -contains 'TimeGenerated')) {
                $r | Add-Member -MemberType NoteProperty -Name TimeGenerated -Value $nowIso -Force
            }

            foreach ($p in @($r.PSObject.Properties)) {
                if ($null -eq $p.Value) { continue }

                if ($stringFields -contains $p.Name) {
                    if ($p.Value -is [System.Collections.IEnumerable] -and $p.Value -isnot [string]) {
                        # arrays/objects -> JSON literal so the string column is still useful
                        $p.Value = ($p.Value | ConvertTo-Json -Compress -Depth 5)
                    }
                    elseif ($p.Value -is [bool]) {
                        $p.Value = if ($p.Value) { 'True' } else { 'False' }
                    }
                    else {
                        $p.Value = [string]$p.Value
                    }
                }
                elseif ($longFields -contains $p.Name) {
                    try { $p.Value = [int64]$p.Value } catch { $p.Value = 0 }
                }
                elseif ($boolFields -contains $p.Name) {
                    if ($p.Value -is [bool]) {
                        # already correct
                    }
                    elseif ($p.Value -is [string]) {
                        $p.Value = ($p.Value -match '^(?i:true|1|yes)$')
                    }
                    else {
                        try { $p.Value = [bool]$p.Value } catch { $p.Value = $false }
                    }
                }
            }
        }
        $Data = $records | ConvertTo-Json -Depth 10
        if ($Data.Trim().StartsWith('{')) { $Data = "[$Data]" }
    }
    catch {
        Write-Warning "Send-GuardrailsData: could not normalize payload ($($_.Exception.Message)); attempting raw send."
    }

    try {
        $tokenResponse = Get-AzAccessToken -ResourceUrl 'https://monitor.azure.com' -AsSecureString -ErrorAction Stop
        $tokenPlain    = [System.Net.NetworkCredential]::new('', $tokenResponse.Token).Password
    }
    catch {
        $tokenResponse = Get-AzAccessToken -ResourceUrl 'https://monitor.azure.com'
        $tokenPlain    = $tokenResponse.Token
    }

    $uri     = "$dceEndpoint/dataCollectionRules/$dcrImmutableId/streams/$streamName" + '?api-version=2023-01-01'
    $body    = [System.Text.Encoding]::UTF8.GetBytes($Data)
    $headers = @{
        Authorization            = "Bearer $tokenPlain"
        'Content-Type'           = 'application/json'
        'x-ms-client-request-id' = [System.Guid]::NewGuid().ToString()
    }

    try {
        Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body -ErrorAction Stop | Out-Null
        Write-Output "Send-GuardrailsData: posted $($body.Length) bytes to '$streamName'."
    }
    catch {
        # PS 7+ surfaces the response body via $_.ErrorDetails.Message; fall back to scanning the exception
        $serverBody = $null
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $serverBody = $_.ErrorDetails.Message
        }
        elseif ($_.Exception.Response) {
            try {
                $stream  = $_.Exception.Response.GetResponseStream()
                $reader  = New-Object System.IO.StreamReader($stream)
                $serverBody = $reader.ReadToEnd()
            } catch {}
        }
        if ($serverBody) {
            Write-Output "DCE response body: $serverBody"
        }
        # Also dump the first record we sent so you can compare it to the schema
        try {
            $first = ($records | Select-Object -First 1) | ConvertTo-Json -Depth 5 -Compress
            Write-Output "First record sent: $first"
        } catch {}
        throw
    }
}

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
    $wsidList=Search-azgraph -first 300 -Query 'resources| where type == "microsoft.operationalinsights/workspaces"| project name, rg=split(id, "/")[4],wsid=properties.customerId | where tolower(rg) contains "guardrails"' -UseTenantScope
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
    | project Mandatory=Required_s,ControlName_s, ItemName=ItemName_s, Profile=column_ifexists('Profile_d',''), Status=case(
        column_ifexists('ComplianceStatus_s', '') == "Not Applicable", "Not Applicable",
        tostring(ComplianceStatus_b)=="True", "Compliant",
        "Non-Compliant"
    ),["ITSG Control"]=itsgcode_s
    | summarize Count=count() by Mandatory,ControlName_s,ItemName, Profile,Status, ["ITSG Control"]
"@
    $gr567Query=@"
    GuardrailsCompliance_CL
    | where ControlName_s has "{0}" and ReportTime_s == "{1}"
    | where TimeGenerated > ago (24h)
    | project Mandatory=Required_s,ControlName_s, ItemName=ItemName_s, Profile=column_ifexists('Profile_d',''), Status=case(
        column_ifexists('ComplianceStatus_s', '') == "Not Applicable", "Not Applicable",
        tostring(ComplianceStatus_b)=="True", "Compliant",
        "Non-Compliant"
    ),["ITSG Control"]=itsgcode_s
    | summarize Count=count() by Mandatory, ControlName_s,ItemName, Profile, Status,["ITSG Control"]
"@
        $gr8query=@"
    let itsgcodes=GRITSGControls_CL | summarize arg_max(TimeGenerated, *) by itsgcode_s;
    let ctrlprefix="GUARDRAIL 8";
    GuardrailsCompliance_CL
    | where ControlName_s has ctrlprefix and ReportTime_s == "{0}"
    | where TimeGenerated > ago (24h)
    |join kind=inner (itsgcodes) on itsgcode_s
    | project Mandatory=Required_s,ControlName_s, SubnetName=SubnetName_s, ItemName=ItemName_s, Profile=column_ifexists('Profile_d',''), Status=case(
        column_ifexists('ComplianceStatus_s', '') == "Not Applicable", "Not Applicable",
        tostring(ComplianceStatus_b)=="True", "Compliant",
        "Non-Compliant"
    ), ["ITSG Control"]=itsgcode_s, Definition=Definition_s,Remediation=gr_geturl(replace_string(ctrlprefix," ",""),itsgcode_s)
    | summarize Count=count(SubnetName) by Mandatory, ControlName_s, Status,ItemName, Profile, ['ITSG Control']
"@
        $gr9query=@"
    let itsgcodes=GRITSGControls_CL | summarize arg_max(TimeGenerated, *) by itsgcode_s;
    let ctrlprefix="GUARDRAIL 9";
    GuardrailsCompliance_CL
    | where ControlName_s has ctrlprefix and ReportTime_s == "{0}"
    | where TimeGenerated > ago (24h)
    |join kind=inner (itsgcodes) on itsgcode_s
    | project Mandatory=Required_s,ControlName_s, ['VNet Name']= column_ifexists('VNETName_s', ''), ItemName=ItemName_s, Profile=column_ifexists('Profile_d',''), Status=case(
        column_ifexists('ComplianceStatus_s', '') == "Not Applicable", "Not Applicable",
        tostring(ComplianceStatus_b)=="True", "Compliant",
        "Non-Compliant"
    ), ["ITSG Control"]=itsgcode_s, Definition=Definition_s,Remediation=gr_geturl(replace_string(ctrlprefix," ",""),itsgcode_s)
    | summarize Count=count() by Mandatory,ControlName_s, Status, ItemName, Profile, ['ITSG Control']
"@
    [PSCustomObject] $FinalObjectList = New-Object System.Collections.ArrayList
    foreach ($ws in $wsidList.wsid)
    {
        "Working on $ws workspace."

        # Get latest report time for that Tenant
        # Keeping SilentlyContinue to avoid throwing error for tenant that dont have GR_TenantInfo_CL and GR_VersionInfo_CL tables i.e central reporting tenant itself
        try {
            $Query="GR_TenantInfo_CL | summarize arg_max(ReportTime_s, *) by TenantDomain_s | project  DepartmentTenantID=column_ifexists('DepartmentTenantID_g','N/A'),TenantDomain=column_ifexists('TenantDomain_s','N/A'),TenantDomainName=column_ifexists('DepartmentTenantName_s','N/A'), DepartmentName=column_ifexists('DepartmentName_s','N/A'), DepartmentNumber=column_ifexists('DepartmentNumber_s','N/A'),CloudUsageProfiles=column_ifexists('cloudUsageProfiles_s','N/A')"
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
            $Query="GR_VersionInfo_CL | summarize arg_max(ReportTime_s, *) by Type | project DeployedVersion=DeployedVersion_s, AvailableVersion=AvailableVersion_s, UpdatedNeeded=UpdateNeeded_b, CheckDate=ReportTime_s"
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
        if ($TenantDomain -ne "" -and $TenantDomain -ne "N/A")
        {
            $ReportTimeQuery="GuardrailsCompliance_CL | where TimeGenerated > ago(24h)| summarize mrt=max(ReportTime_s)"
            try {
                $queryResult = Invoke-AzOperationalInsightsQuery -WorkspaceId $ws -Query $ReportTimeQuery -ErrorAction SilentlyContinue
                if ($null -eq $queryResult -or $null -eq $queryResult.Results) {
                    "No query results for $TenantDomain workspace $ws - table may not exist yet."
                    continue
                }
                $resultsArray = [System.Linq.Enumerable]::ToArray($queryResult.Results)
                if ($null -eq $resultsArray -or $resultsArray.Count -eq 0) {
                    "No data found for $TenantDomain in workspace $ws."
                    continue
                }
                $LatestRT = $resultsArray[0].mrt
            }
            catch {
                "Error querying ReportTime for $TenantDomain in workspace $ws : $_"
                continue
            }
            
            if ([string]::IsNullOrEmpty($LatestRT)) {
                "No recent data found for $TenantDomain."
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
                $QueryList+=$generalQuery -f "GUARDRAIL 13",$LatestRT

                
                foreach ($Query in $QueryList)
                {
                    if ($DebugInfo) { $Query }
                    try {
                        $response=(Invoke-AzOperationalInsightsQuery -WorkspaceId $ws -Query $Query).Results
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
            # Best-effort debug dump; the Functions runtime sometimes refuses writes to the
            # script's cwd, so swallow failures to avoid breaking ingestion.
            try {
                $tempDebug = Join-Path ([System.IO.Path]::GetTempPath()) 'debubinfo_finalobjectlist.txt'
                $FinalObjectList | Out-File -FilePath $tempDebug -ErrorAction Stop
                "Debug dump written to $tempDebug."
            }
            catch {
                "Skipping debug dump ($($_.Exception.Message))."
            }
        }
        $FinalObjectListJson = $FinalObjectList | ConvertTo-Json
        try {
            Send-GuardrailsData -Data $FinalObjectListJson -LogType $LogType -WorkSpaceID $WorkSpaceID -WorkSpaceKey $workspaceKey
        }
        catch {
            "Send-GuardrailsData FAILED: $($_.Exception.Message)"
            if ($_.Exception.Response) {
                try {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $body = $reader.ReadToEnd()
                    "Response body: $body"
                } catch {}
            }
            throw
        }
    }
    else { "No data to send" }
}