function Check-DeprecatedUsers {
    [CmdletBinding()]
    Param (
        
        [string] $token, 
        [string] $ControlName, 
        [string] $ItemName, 
        [string] $itsgcode,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string] $ReportTime,
        [string] $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] $EnableMultiCloudProfiles # New feature flag, default to false    
    )
    [bool] $IsCompliant = $false
    [string] $UComments = $msgTable.noncompliantUsers
    [string] $CComments = $msgTable.compliantComment

    $ErrorList = [System.Collections.ArrayList]::new()
        
    # A Deprecated account is an account that is disabled and not synchronized to AD
    $DeprecatedUsers = Get-AzADUser -Filter "accountEnabled eq false" -Select OnPremisesSyncEnabled,UserPrincipalName | 
                       Where-Object {$null -eq $_.onPremisesSyncEnabled}

    if ($DeprecatedUsers.Count -gt 0) {
        $UComments += ($DeprecatedUsers.UserPrincipalName -join "  ")
        $Comments = $msgTable.noncompliantComment -f $DeprecatedUsers.Count, $UComments
        $MitigationCommands = $msgTable.mitigationCommands 
    }
    else {
        $Comments = $CComments
        $IsCompliant = $true
        $MitigationCommands = "N/A"
    }

    $DeprecatedUserStatusParams = @{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        Comments         = $Comments
        ItemName         = $ItemName
        MitigationCommands = $MitigationCommands
        ReportTime = $ReportTime
        itsgcode = $itsgcode
    }
    $DeprecatedUserStatus = [PSCustomObject]$DeprecatedUserStatusParams

    # Add profile information if MCUP feature is enabled
    if ($EnableMultiCloudProfiles) {
        $result = Add-ProfileInformation -Result $DeprecatedUserStatus -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId -ErrorList $ErrorList
        Write-Host "$result"
    }

    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = $DeprecatedUserStatus
        Errors = $ErrorList
    }
    return $moduleOutput
}



