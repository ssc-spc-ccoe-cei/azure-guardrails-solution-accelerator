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

    # Fetch group settings
    try {
        $groupSettings = Invoke-GraphQuery -urlPath "/groupSettings" -ErrorAction Stop
        Write-Output "groupSettings: $groupSettings"
        $groupSettingsJsonObject = $groupSettings.Content | ConvertFrom-Json
        $passwordRuleSettings = $groupSettingsJsonObject.value | Where-Object { $_.displayName -eq "Password Rule Settings" }
        
        if ($null -eq $passwordRuleSettings) {
            throw "Password Rule Settings not found in group settings"
        }
        Write-Output "passwordRuleSettings: $passwordRuleSettings"
        # Check 1: Lockout Threshold
        $lockoutThreshold = ($passwordRuleSettings.values | Where-Object { $_.name -eq "LockoutThreshold" }).value
        Write-Output "Lockout Threshold: $lockoutThreshold"

        if ([int]$lockoutThreshold -gt 10) {
            $IsCompliant = $false
            $Comments += $msgTable.onlineAttackNonCompliantC1 + " "
        }

        # Check 2: Banned Password List
        $bannedPasswordListSetting = ($passwordRuleSettings.values | Where-Object { $_.name -eq "BannedPasswordList" }).value
        $bannedPasswords = $bannedPasswordListSetting -split '\t'
        Write-Output "Banned Passwords: $($bannedPasswords -join ', ')"

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
        $ErrorList.Add("Failed to retrieve or process group settings: $_")
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

    Write-Output "PsObject: $PsObject"
    # Conditionally add the Profile field based on the feature flag
    if ($EnableMultiCloudProfiles) {
        Write-Ouput "Enabling MultiCloudProfiles"
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