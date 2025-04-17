function Check-NetworkInterfaceIPs {
    param (
        [string] $ControlName,
        [string] $ItemName,
        [string] $itsgcode,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string] $ReportTime,
        [string] $ModuleProfiles,
        [string] $CloudUsageProfiles = "3",
        [switch] $EnableMultiCloudProfiles
    )

    $ObjectList = New-Object System.Collections.ArrayList
    $ErrorList = New-Object System.Collections.ArrayList

    $grRequiredPolicies = @(
        "/providers/Microsoft.Authorization/policyDefinitions/83a86a26-fd1f-447c-b59d-e51f44264114"
    )

    if ($EnableMultiCloudProfiles) {
        $ObjectList += Check-BuiltInPolicies -requiredPolicyIds $grRequiredPolicies -ReportTime $ReportTime -ItemName $ItemName -msgTable $msgTable -ControlName $ControlName -itsgcode $itsgcode -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -EnableMultiCloudProfiles -ErrorList $ErrorList
    } else {
        $ObjectList += Check-BuiltInPolicies -requiredPolicyIds $grRequiredPolicies -ReportTime $ReportTime -ItemName $ItemName -msgTable $msgTable -ControlName $ControlName -itsgcode $itsgcode -ErrorList $ErrorList
    }
    
    # Filter out PSAzureContext objects
    $ObjectList_filtered = $ObjectList | Where-Object { $_.GetType() -notlike "*PSAzureContext*" }

    $moduleOutput = [PSCustomObject]@{
        ComplianceResults = $ObjectList_filtered
        Errors = $ErrorList
    }
    
    return $moduleOutput
}
