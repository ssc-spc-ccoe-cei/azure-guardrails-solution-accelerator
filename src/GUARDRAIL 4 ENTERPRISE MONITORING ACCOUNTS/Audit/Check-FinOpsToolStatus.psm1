function Check-FinOpsToolStatus {
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
        [string] $CloudUsageProfiles = "3",
        [string] $ModuleProfiles,
        [switch] $EnableMultiCloudProfiles
    )

    [bool] $IsCompliant = $true
    [string] $Comments = ""
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList

    # Check 1: Verify Service Principal existence
    $spnExists = Check-ServicePrincipalExists "CloudabilityUtilizationDataCollector"
    if (-not $spnExists) {
        $IsCompliant = $false
        $Comments += $msgTable.spnNotExist + " "
    }

    # Check 2: Verify Permissions
    $hasCorrectPermissions = Check-ServicePrincipalPermissions "CloudabilityUtilizationDataCollector"
    if (-not $hasCorrectPermissions) {
        $IsCompliant = $false
        $Comments += $msgTable.spnIncorrectPermissions + " "
    }

    # Check 3: Verify Roles
    $hasCorrectRoles = Check-ServicePrincipalRoles "CloudabilityUtilizationDataCollector"
    if (-not $hasCorrectRoles) {
        $IsCompliant = $false
        $Comments += $msgTable.spnIncorrectRoles + " "
    }

    if ($IsCompliant) {
        $Comments = $msgTable.finOpsToolCompliant
    } else {
        $Comments = $msgTable.finOpsToolNonCompliant -f $Comments.Trim()
    }

    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        Comments         = $Comments
        ItemName         = $ItemName
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }

    if ($EnableMultiCloudProfiles) {
        $result = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        if ($result -eq 0) {
            Write-Output "No matching profile found or error occurred"
            $PsObject.ComplianceStatus = "Not Applicable"
        } elseif ($result -gt 0) {
            Write-Output "Valid profile returned: $result"
            $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $result
        } else {
            Write-Error "Unexpected result: $result"
        }
    }

    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors            = $ErrorList
    }
    return $moduleOutput
}

function Check-ServicePrincipalExists {
    param (
        [string] $spnName
    )
    try {
        $urlPath = "/servicePrincipals?`$filter=displayName eq '$spnName'"
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
        $data = $response.Content
        
        if ($data.value.Count -gt 0) {
            return $true
        } else {
            return $false
        }
    }
    catch {
        Write-Error "Error checking Service Principal existence: $_"
        return $false
    }
}

function Check-ServicePrincipalPermissions {
    param (
        [string] $spnName
    )
    try {
        # First, get the Service Principal's Object ID
        $urlPath = "/servicePrincipals?`$filter=displayName eq '$spnName'"
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
        $spnObjectId = $response.Content.value[0].id

        # Now, check for the Reader role assignment
        $urlPath = "/roleManagement/directory/roleAssignments?`$filter=principalId eq '$spnObjectId'"
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
        $roleAssignments = $response.Content.value

        $readerRoleId = "acdd72a7-3385-48ef-bd42-f606fba81ae7" # Object ID for Reader role
        $hasReaderRole = $roleAssignments | Where-Object { $_.roleDefinitionId -eq $readerRoleId }

        return $null -ne $hasReaderRole
    }
    catch {
        Write-Error "Error checking Service Principal permissions: $_"
        return $false
    }
}

function Check-ServicePrincipalRoles {
    param (
        [string] $spnName
    )
    try {
        # First, get the Service Principal's Object ID
        $urlPath = "/servicePrincipals?`$filter=displayName eq '$spnName'"
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
        $spnObjectId = $response.Content.value[0].id

        # Now, check for the required role assignments
        $urlPath = "/roleManagement/directory/roleAssignments?`$filter=principalId eq '$spnObjectId'"
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
        $roleAssignments = $response.Content.value

        $cloudAppAdminRoleId = "158c047a-c907-4556-b7ef-446551a6b5f7" # Object ID for Cloud Application Administrator role
        $reportsReaderRoleId = "4a5d8f65-41da-4de4-8968-e035b65339cf" # Object ID for Reports Reader role

        $hasCloudAppAdminRole = $roleAssignments | Where-Object { $_.roleDefinitionId -eq $cloudAppAdminRoleId }
        $hasReportsReaderRole = $roleAssignments | Where-Object { $_.roleDefinitionId -eq $reportsReaderRoleId }

        return ($null -ne $hasCloudAppAdminRole) -and ($null -ne $hasReportsReaderRole)
    }
    catch {
        Write-Error "Error checking Service Principal roles: $_"
        return $false
    }
}
