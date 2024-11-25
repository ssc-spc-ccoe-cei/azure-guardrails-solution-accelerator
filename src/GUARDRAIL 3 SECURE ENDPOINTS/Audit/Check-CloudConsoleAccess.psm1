function Get-CloudConsoleAccess {
    param (      
        [Parameter(Mandatory=$true)]
        [string] $ControlName,
        [Parameter(Mandatory=$true)]
        [string] $ItemName,
        [Parameter(Mandatory=$true)]
        [string] $itsgcode,
        [Parameter(Mandatory=$true)]
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string] $ReportTime,
        [string] $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] $EnableMultiCloudProfiles # New feature flag, default to false    
    )
    $IsCompliant = $false
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    
    # get named locations
    $PsObjectLocation = Get-allowedLocationCAPCompliance -ErrorList $ErrorList -IsCompliant $IsCompliant
    $ErrorList = $PsObjectLocation.Errors

    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $PsObjectLocation.ComplianceStatus
        ControlName      = $PsObjectLocation.ControlName
        Comments         = $PsObjectLocation.Comments
        ItemName         = $PsObjectLocation.ItemName
        ReportTime       = $PsObjectLocation.ReportTime
        itsgcode         = $PsObjectLocation.itsgcode
    }

    # Conditionally add the Profile field based on the feature flag
    if ($EnableMultiCloudProfiles) {        
        $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        if (!$evalResult.ShouldEvaluate) {
            if ($evalResult.Profile -gt 0) {
                $PsObject.ComplianceStatus = "Not Applicable"
                $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                $PsObject.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
            } else {
                $ErrorList.Add("Error occurred while evaluating profile configuration")
            }
        } else {
            
            $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
        }
    }

    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput   
}

