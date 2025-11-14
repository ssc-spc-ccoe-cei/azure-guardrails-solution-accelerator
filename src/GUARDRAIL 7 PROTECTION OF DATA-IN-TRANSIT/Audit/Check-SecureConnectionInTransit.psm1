function Verify-SecureConnectionInTransit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
            [string] $ControlName,
            [string] $ItemName,
            [string] $PolicyID, 
            [string] $itsgcode,
            [hashtable] $msgTable,
            [Parameter(Mandatory=$true)]
            [string] $ReportTime,
            [Parameter(Mandatory=$false)]
            [string] $CBSSubscriptionName,
            [string] $CloudUsageProfiles = "3",  # Passed as a string
            [string] $ModuleProfiles,  # Passed as a string
            [switch] $EnableMultiCloudProfiles, # New feature flag, default to false
            [string] $LogType
    )
    [PSCustomObject] $ObjectList = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    $AdditionalResults = @()
    $grRequiredPolicies=@("OnlySecureConnectionsToYourRedisCacheShouldBeEnabled","SecureTransferToStorageAccountsShouldBeEnabled")

    #Check Subscriptions
    try {
        $objs = Get-AzSubscription -ErrorAction Stop | Where-Object {$_.State -eq "Enabled"} 
    }
    catch {
        $Errorlist.Add("Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_")
        throw "Error: Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_"
    }
    [string]$type = "subscription"

    if ($EnableMultiCloudProfiles) {   
        $ObjectList += Check-PBMMPolicies -objList $objs -objType $type -itsgcode $itsgcode -requiredPolicyExemptionIds $grRequiredPolicies -PolicyID $PolicyID -ReportTime $ReportTime -ItemName $ItemName -LogType $LogType -msgTable $msgTable  -ControlName $ControlName -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -EnableMultiCloudProfiles
    }
    else {
        $ObjectList += Check-PBMMPolicies -objList $objs -objType $type -itsgcode $itsgcode -requiredPolicyExemptionIds $grRequiredPolicies -PolicyID $PolicyID -ReportTime $ReportTime -ItemName $ItemName -LogType $LogType -msgTable $msgTable -ControlName $ControlName
    } 
    Write-Host "$type(s) compliance results are collected"

    # Filter out objects of type PSAzureContext
    $ObjectList_filtered = $ObjectList | Where-Object { $null -ne $_ -and $_.GetType() -notlike "*PSAzureContext*" }

    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $ObjectList_filtered 
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput  
}

