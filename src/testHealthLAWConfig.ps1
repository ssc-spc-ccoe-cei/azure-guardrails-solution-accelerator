$subs=get-azsubscription
$totalsubs=$subs.Count
$GraphAccessToken = (Get-AzAccessToken).Token
$lawId="/subscriptions/6c64f9ed-88d2-4598-8de6-7a9527dc16ca/resourceGroups/qGuardrails-6eb08c2c/providers/Microsoft.OperationalInsights/workspaces/qguardrails-6eb08c2c"
$pcount=0
foreach ($sub in $subs) {
    $URL="https://management.azure.com/subscriptions/$($sub.Id)/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview"
    $configuredWSs=(Invoke-RestMethod -Headers @{Authorization = "Bearer $($GraphAccessToken)" } -Uri $URL -Method Get ).value.Properties.workspaceId
    if ($lawId -in $configuredWSs) {
        $pcount++
    }
}
if ($pcount -ne $totalsubs) {
    Write-Warning "Not all subscriptions are configured to send logs to the Log Analytics Workspace"
}
else {
    Write-Host "All subscriptions are configured to send logs to the Log Analytics Workspace"
}

