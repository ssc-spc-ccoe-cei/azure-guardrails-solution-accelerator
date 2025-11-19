function Get-LocationBasedCAP {
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
        [string] $CloudUsageProfiles = "3",     # Passed as a string
        [string] $ModuleProfiles,               # Passed as a string
        [switch] $EnableMultiCloudProfiles      # feature flag, default to false    
    )
    $IsCompliant = $false
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList


    # Check 2: Allowed Location – Conditional Access Policy
    $PsObjectLocation = Get-allowedLocationCAPCompliance -ErrorList $ErrorList -IsCompliant $IsCompliant
    $ErrorList = $PsObjectLocation.Errors
    $CommentsArray = $PsObjectLocation.Comments

    if ($PsObjectLocation.ComplianceStatus -eq $true){
        $IsCompliant = $true
        $Comments = $msgTable.isCompliant + " " + $msgTable.compliantC2 + " " + ($CommentsArray -join "; ") 
    }
    else{
        $Comments = $msgTable.isNotCompliant + " " + $msgTable.nonCompliantC2 + " " + ($CommentsArray -join "; ")
    }


    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        Comments         = $Comments
        ItemName         = $ItemName
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }

    # Add profile information if MCUP feature is enabled
    if ($EnableMultiCloudProfiles) {
        $result = Add-ProfileInformation -Result $PsObject -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId -ErrorList $ErrorList
        Write-Host "$result"
    }

    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput
}
