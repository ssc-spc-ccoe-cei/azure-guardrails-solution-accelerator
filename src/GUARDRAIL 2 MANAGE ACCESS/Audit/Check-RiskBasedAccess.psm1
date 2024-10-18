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
    
    # Check 1: Password Changes –Conditional Access Policy
    $IsCompliantPasswordCAP = $false
    
    $CAPUrl = '/identity/conditionalAccess/policies'
    try {
        $response = Invoke-GraphQuery -urlPath $CAPUrl -ErrorAction Stop

        $caps = $response.Content.value
    }
    catch {
        $Errorlist.Add("Failed to call Microsoft Graph REST API at URL '$CAPUrl'; returned error message: $_")
        Write-Warning "Error: Failed to call Microsoft Graph REST API at URL '$CAPUrl'; returned error message: $_"
    }

    # check for a conditional access policy which meets these requirements:
    # 1. state =  'enabled'
    # 2. includedUsers = 'All'
    # 3. applications.includedApplications = 'All'
    # 4. grantControls.builtInControls contains 'mfa' and 'passwordChange'
    # 5. clientAppTypes contains 'all'
    # 6. userRiskLevels = 'high'
    # 7. signInRiskLevels = @()
    # 8. platforms = null
    # 9. locations = null
    # 10. devices = null
    # 11. clientApplications = null
    # 12. signInFrequency.frequencyInterval = 'everyTime'
    # 13. signInFrequency.isEnabled = true
    # 14. signInFrequency.authenticationType = 'primaryAndSecondaryAuthentication'

    $validPolicies = $caps | Where-Object {
        $_.state -eq 'enabled' -and
        $_.conditions.users.includeUsers -contains 'All' -and
        ($_.conditions.applications.includeApplications -contains 'All' -or
         $_.conditions.applications.includeApplications -contains 'MicrosoftAdminPortals') -and
        $_.grantControls.builtInControls -contains 'mfa' -and
        $_.grantControls.builtInControls -contains 'passwordChange' -and
        $_.conditions.clientAppTypes -contains 'all' -and
        $_.conditions.userRiskLevels -contains 'high' -and
        $_.sessionControls.signInFrequency.frequencyInterval -contains 'everyTime' -and
        $_.sessionControls.signInFrequency.authenticationType -contains 'primaryAndSecondaryAuthentication' -and
        $_.sessionControls.signInFrequency.isEnabled -eq $true -and
        [string]::IsNullOrEmpty($_.conditions.signInRiskLevels) -and
        [string]::IsNullOrEmpty($_.conditions.platforms) -and
        [string]::IsNullOrEmpty($_.conditions.locations) -and
        [string]::IsNullOrEmpty($_.conditions.devices)  -and
        [string]::IsNullOrEmpty($_.conditions.clientApplications) 
    }
    if ($validPolicies.count -ne 0) {
        $IsCompliantPasswordCAP = $true
    }
    else {
        # Failed. Reason: No policies meet the requirements
        $IsCompliantPasswordCAP = $false
    }

    # Check 2: Allowed Location – Conditional Access Policy
    $PsObjectLocation = Get-allowedLocationCAPCompliance -ErrorList $ErrorList -IsCompliant $IsCompliant
    $ErrorList = $PsObjectLocation.Errors

    # Combine status
    if ($IsCompliantPasswordCAP -eq $true -and $PsObjectLocation.ComplianceStatus -eq $true){
        $IsCompliant = $true
        $Comments = $msgTable.isCompliant + " " + $msgTable.compliantC1C2
    }
    elseif ($IsCompliantPasswordCAP -eq $true -and $PsObjectLocation.ComplianceStatus -eq $false){
        $IsCompliant = $false
        $Comments = $msgTable.isNotCompliant + " " + $msgTable.nonCompliantC1
    }
    elseif($PsObjectLocation.ComplianceStatus -eq $true -and $IsCompliantPasswordCAP -eq $false){
        $IsCompliant = $false
        $Comments = $msgTable.isNotCompliant + " " + $msgTable.nonCompliantC2
    }
    else{
        $IsCompliant = $false
        $Comments = $msgTable.isNotCompliant + " " + $msgTable.nonCompliantC1C2
    }
    
    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        Comments         = $Comments
        ItemName         = $ItemName
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }

    # Conditionally add the Profile field based on the feature flag
    if ($EnableMultiCloudProfiles) {
        $result = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        if ($result -gt 0) {
            Write-Output "Valid profile returned: $result"
            $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $result
        } elseif ($result -eq 0) {
            Write-Output "No matching profile found or error occurred"
            $PsObject.ComplianceStatus = "Not Applicable"
        } else {
            Write-Error "Unexpected result: $result"
        }
    }

    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput
}
