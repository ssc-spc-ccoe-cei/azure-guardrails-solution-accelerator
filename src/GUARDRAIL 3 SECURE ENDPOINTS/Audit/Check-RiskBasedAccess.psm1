function Get-RiskBasedAccess {
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
    
    # Check #2 Allowed Location – Conditional Access Policy
    $PsObject = Get-CloudConsoleAccess -ControlName $msgTable.CtrName3 -ItemName $msgTable.consoleAccessConditionalPolicy -MsgTable $msgTable  -ReportTime $ReportTime -itsgcode $vars.itsgcode -CloudUsageProfiles $cloudUsageProfilesString -ModuleProfiles $ModuleProfilesString

    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput   
}

