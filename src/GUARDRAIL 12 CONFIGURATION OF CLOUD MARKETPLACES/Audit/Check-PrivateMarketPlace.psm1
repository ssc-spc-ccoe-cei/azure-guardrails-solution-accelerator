function Check-PrivateMarketPlaceCreation {
param (
        [string] $ControlName, 
        [string] $itsgcode,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime
)
    
$IsCompliant=$false 
$Object = New-Object PSObject
[PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList

try {
        [String] $PrivateMarketPlace=  Get-AzMarketplacePrivateStore -ErrorAction Stop  
}
catch {
    $ErrorList.Add("Failed to execute the 'Get-AzMarketplacePrivateStore'--ensure that the Az.Marketplace module is installed `
    and up to date; returned error message: $_")
    throw "Error: Failed to execute the 'Get-AzMarketplacePrivateStore'--ensure that the Az.Marketplace module is installed `
        and up to date; returned error message: $_" 
}
 
if($null -eq $PrivateMarketPlace){
        $Object| Add-Member NoteProperty -Name ComplianceStatus  -Value $IsCompliant
        $Object| Add-Member NoteProperty -Name Comments  -Value $msgTable.mktPlaceNotCreated
        $MitigationCommands = $msgTable.enableMktPlace
}
else {       
        $IsCompliant= $true
        $Object| Add-Member NoteProperty -Name ComplianceStatus  -Value $IsCompliant
        $Object| Add-Member NoteProperty -Name Comments  -Value "$($msgTable.mktPlaceCreated) - $($PrivateMarketPlace.PrivateStoreId)"
        $MitigationCommands = ""
}
$Object| Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName -Force | Out-Null
$Object| Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force | Out-Null
$Object| Add-Member -MemberType NoteProperty -Name MitigationCommands -Value $MitigationCommands -Force| Out-Null
$Object| Add-Member -MemberType NoteProperty -Name ItemName -Value $msgTable.mktPlaceCreation -Force | Out-Null
$Object| Add-Member -MemberType NoteProperty -Name itsgcode -Value $itsgcode -Force | Out-Null

$moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $Object
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
return $moduleOutput
}


