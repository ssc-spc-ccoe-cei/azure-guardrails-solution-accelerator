function Check-PrivateMarketPlaceCreation {
param (
        [string] $ControlName, 
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
    
$IsCompliant=$false 
$Object = New-Object PSObject
[PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList

try {
        $PrivateMarketPlace =  Get-AzMarketplacePrivateStore -ErrorAction Stop
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
        
        # Extract availability for the private store
        $availability =  $PrivateMarketPlace.Availability
        if ($availability -eq "enabled"){
                $Object| Add-Member NoteProperty -Name Comments  -Value "$($msgTable.mktPlaceCreatedEnabled) - $($PrivateMarketPlace.PrivateStoreId)"
                $MitigationCommands = ""
        }
        else{
                $IsCompliant= $false 
                $Object| Add-Member NoteProperty -Name Comments  -Value $msgTable.mktPlaceCreatedNotEnabled
                $MitigationCommands = $msgTable.enableMktPlace
        }
}
        
$Object| Add-Member NoteProperty -Name ComplianceStatus  -Value $IsCompliant
$Object| Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName -Force | Out-Null
$Object| Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force | Out-Null
$Object| Add-Member -MemberType NoteProperty -Name MitigationCommands -Value $MitigationCommands -Force| Out-Null
$Object| Add-Member -MemberType NoteProperty -Name ItemName -Value $msgTable.mktPlaceCreation -Force | Out-Null
$Object| Add-Member -MemberType NoteProperty -Name itsgcode -Value $itsgcode -Force | Out-Null

if ($EnableMultiCloudProfiles) {        
        $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        if (!$evalResult.ShouldEvaluate) {
            if ($evalResult.Profile -gt 0) {
                $Object.ComplianceStatus = "Not Applicable"
                $Object | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                $Object.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
            } else {
                $ErrorList.Add("Error occurred while evaluating profile configuration")
            }
        } else {
            Write-Output "Valid profile returned: $($evalResult.Profile)"
            $Object | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
        }
}    

$moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $Object
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
return $moduleOutput
}


