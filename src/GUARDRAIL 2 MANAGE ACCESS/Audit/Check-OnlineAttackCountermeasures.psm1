function Check-OnlineAttackCountermeasures {
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

    [bool] $IsCompliant = $true
    [string] $Comments = ""
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList

    # Check 1: Lockout Threshold
    try {
        $authenticationMethodsPolicy = Invoke-GraphQuery -urlPath "/policies/authenticationMethodsPolicy" -ErrorAction Stop
        $lockoutThreshold = $authenticationMethodsPolicy.Content.lockoutThreshold

        if ($lockoutThreshold -gt 10) {
            $IsCompliant = $false
            $Comments += $msgTable.onlineAttackNonCompliantC1 + " "
        }
    }
    catch {
        $ErrorList.Add("Failed to retrieve authentication methods policy: $_")
        $IsCompliant = $false
    }

    # Check 2: Banned Password List
    try {
        $bannedPasswordList = Invoke-GraphQuery -urlPath "/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/passwordConfiguration" -ErrorAction Stop
        $bannedPasswords = $bannedPasswordList.Content.bannedPasswords

        if ($null -eq $bannedPasswords -or $bannedPasswords.Count -eq 0) {
            $IsCompliant = $false
            $Comments += $msgTable.onlineAttackNonCompliantC2 + " "
        }
        else {
            $requiredBannedPasswords = @("password", "Password!", "Summer2018")
            $missingPasswords = $requiredBannedPasswords | Where-Object { $_ -notin $bannedPasswords }

            if ($missingPasswords.Count -gt 0) {
                $IsCompliant = $false
                $Comments += $msgTable.onlineAttackNonCompliantC2 + " "
            }
        }
    }
    catch {
        $ErrorList.Add("Failed to retrieve banned password list: $_")
        $IsCompliant = $false
    }

    if (-not $IsCompliant -and $Comments -eq "") {
        $Comments = $msgTable.onlineAttackNonCompliantC1C2
    }
    elseif ($IsCompliant) {
        $Comments = $msgTable.onlineAttackIsCompliant
    }

    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        Comments         = $Comments.Trim()
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
            Write-Output "No matching profile found or an error occurred"
            $PsObject.ComplianceStatus = "Not Applicable"
            $ErrorList.Add("No matching profile found or an error occurred in Get-EvaluationProfile")
        } else {
            Write-Error "Unexpected result from Get-EvaluationProfile: $result"
            $PsObject.ComplianceStatus = "Not Applicable"
            $ErrorList.Add("Unexpected result from Get-EvaluationProfile: $result")
        }
    }

    $moduleOutput = [PSCustomObject]@{
        ComplianceResults = $PsObject
        Errors            = $ErrorList
    }

    return $moduleOutput
}