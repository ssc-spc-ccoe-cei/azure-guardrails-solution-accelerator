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
        $Comments += $msgTable.SPNNotExist + " "
    }
    else {
        # Check 2: Verify Permissions (only if SPN exists)
        $hasCorrectPermissions = Check-ServicePrincipalPermissions "CloudabilityUtilizationDataCollector"
        if (-not $hasCorrectPermissions) {
            $IsCompliant = $false
            $Comments += $msgTable.SPNIncorrectPermissions + " "
        }
    }

    # # Check 3: Verify Roles
    # $hasCorrectRoles = Check-ServicePrincipalRoles "CloudabilityUtilizationDataCollector"
    # if (-not $hasCorrectRoles) {
    #     $IsCompliant = $false
    #     $Comments += $msgTable.SPNIncorrectRoles + " "
    # }

    if ($IsCompliant) {
        $Comments = $msgTable.FinOpsToolCompliant
    } else {
        $Comments = $msgTable.FinOpsToolNonCompliant -f $Comments.Trim()
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
        $result = Add-ProfileInformation -Result $PsObject -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -ErrorList $ErrorList
        $PsObject = $result
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
        $response = Invoke-GraphQueryEX -urlPath $urlPath -ErrorAction Stop
        $data = $response.Content.value
                
        if ($null -ne $data -and $data.Count -gt 0) {
            return $true
        } else {
            Write-Warning "SPN '$spnName' not found"
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
        # First, get the Service Principal
        $urlPath = "/servicePrincipals?`$filter=displayName eq '$spnName'"
        $response = Invoke-GraphQueryEX -urlPath $urlPath -ErrorAction Stop
        $spnList = $response.Content.value
        
        if ($null -eq $spnList -or $spnList.Count -eq 0) {
            Write-Warning "Service Principal '$spnName' not found"
            return $false
        }
        
        $spn = $spnList[0]

        # Get the oauth2PermissionGrants
        $urlPath = "/servicePrincipals/{0}/oauth2PermissionGrants" -f $spn.id
        $permissionResponse = Invoke-GraphQueryEX -urlPath $urlPath -ErrorAction Stop
        $permissionGrants = $permissionResponse.Content.value
        
        # Check delegated permissions (oauth2PermissionGrants)
        $delegatedPermissions = @()
        foreach ($grant in $permissionGrants) {
            $delegatedPermissions += $grant.scope -split ' '
        }

        Write-Verbose "Found delegated permissions: $($delegatedPermissions -join ', ')"

        # Define required permissions to check
        $requiredPermissions = @(
            "User.Read",              # for Microsoft Graph
            "user_impersonation"      # for Azure Resource Manager and Partner Center
        )

        foreach ($required in $requiredPermissions) {
            if ($delegatedPermissions -notcontains $required) {
                Write-Warning "Missing required permission: $required"
                return $false
            }
        }

        return $true
    }
    catch {
        Write-Error "Error checking Service Principal permissions: $_"
        return $false
    }
}

# function Check-ServicePrincipalRoles {
#     param (
#         [string] $spnName
#     )
#     try {
#         # First, get the Service Principal's Object ID
#         $urlPath = "/servicePrincipals?`$filter=displayName eq '$spnName'"
#         $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
#         $spnObjectId = $response.Content.value[0].id

#         # Now, check for the required role assignments
#         $urlPath = "/roleManagement/directory/roleAssignments?`$filter=principalId eq '$spnObjectId'"
#         $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
#         $roleAssignments = $response.Content.value

#         $cloudAppAdminRoleId = "158c047a-c907-4556-b7ef-446551a6b5f7" # Object ID for Cloud Application Administrator role
#         $reportsReaderRoleId = "4a5d8f65-41da-4de4-8968-e035b65339cf" # Object ID for Reports Reader role

#         $hasCloudAppAdminRole = $roleAssignments | Where-Object { $_.roleDefinitionId -eq $cloudAppAdminRoleId }
#         $hasReportsReaderRole = $roleAssignments | Where-Object { $_.roleDefinitionId -eq $reportsReaderRoleId }

#         return ($null -ne $hasCloudAppAdminRole) -and ($null -ne $hasReportsReaderRole)
#     }
#     catch {
#         Write-Error "Error checking Service Principal roles: $_"
#         return $false
#     }
# }