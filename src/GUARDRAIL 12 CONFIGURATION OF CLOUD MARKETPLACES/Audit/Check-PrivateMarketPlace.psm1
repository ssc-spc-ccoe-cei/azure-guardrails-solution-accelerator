function Check-PrivateMarketPlaceCreation {
        param (
                [string] $ControlName, `
                [string] $WorkSpaceID, [string] $workspaceKey, [string] $LogType,
                [Parameter(Mandatory=$true)]
                [string]
                $ReportTime
        )
                
    
$IsCompliance=$false 
$Object = New-Object PSObject
[String] $Comment1 = "The Private Marketplace has been created."
[String] $Comment2 = "The Private Marketplace has not been created."
[String] $PrivateMarketPlace=  Get-AzMarketplacePrivateStore

if($null -eq $PrivateMarketPlace){
        $Object| Add-Member NoteProperty -Name ComplianceStatus  -Value $IsCompliance
        $Object| Add-Member NoteProperty -Name Comments  -Value $Comment2
}else {       
        $IsCompliance= $true
        $Object| Add-Member NoteProperty -Name ComplianceStatus  -Value $IsCompliance
        $Object| Add-Member NoteProperty -Name Comments  -Value "$Comment1 - $($PrivateMarketPlace.PrivateStoreId)"
}
$Object| Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName -Force
$Object| Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
$JsonObject = $Object | convertTo-Json  
Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
    -sharedkey $workspaceKey `
    -body $JsonObject `
    -logType $LogType `
    -TimeStampField Get-Date
}
