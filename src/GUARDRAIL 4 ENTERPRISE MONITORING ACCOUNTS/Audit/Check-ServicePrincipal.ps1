function CheckSPNCreation {
    Param(
    [string] $token, 
    [string] $SPNName,
    [string] $ControlName, 
    [string] $ItemName,
    [string] $itsgcode,
    [string] $WorkSpaceID, 
    [string] $WorkSpaceKey, 
    [string] $LogType,
    [hashtable] $msgTable,
    [Parameter(Mandatory=$true)]
    [string]
    $ReportTime )

[String] $token = (Get-AzAccessToken -ResourceTypeName MSGraph).Token
[string] $SPNUri = "https://graph.microsoft.com/beta/servicePrincipals?$"+"filter"+"=DisplayName  eq 'SSC-CBS-Reporting-PrivateMarketplace' " 
$spn= Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)"} -Uri $SPNUri -Method Get
    

$url1 = "https://graph.microsoft.com/v1.0/servicePrincipals/ff83f151-bfa5-4ca3-a9f0-046771079f10/delegatedPermissionClassifications"

$role= Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)"} -Uri $url1 -Method Get
}