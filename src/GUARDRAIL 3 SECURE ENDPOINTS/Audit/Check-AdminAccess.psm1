function Get-AdminAccess {
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

    $IsCompliant = $true
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    
    # Get conditional access policies
    $CABaseAPIUrl = '/identity/conditionalAccess/policies'
    try {
        $response = Invoke-GraphQuery -urlPath $CABaseAPIUrl -ErrorAction Stop
        $caps = $response.Content.value
    }
    catch {
        $ErrorList.Add("Failed to call Microsoft Graph REST API at URL '$CABaseAPIUrl'; returned error message: $_")
        Write-Warning "Error: Failed to call Microsoft Graph REST API at URL '$CABaseAPIUrl'; returned error message: $_"
        $IsCompliant = $false
    }

    # Administrative users roles to be checked -> App Admin, Global Admin, Security Admin, User Admin
    $adminUserIds = @('9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3', '62e90394-69f5-4237-9190-012177145e10', '194ae4cb-b126-40b2-bd5b-6091b380977d', 'fe930be7-5e62-47db-91af-98c3a49a38b1')

    # Check for device-based policies with admin users that include target resources
    $devicePolicies = $caps | Where-Object { 
        $null -ne $_.conditions.devices.deviceFilter -and 
        $null -ne $_.conditions.applications.includeApplications -and
        ($adminUserIds -contains $_.conditions.users.includeRoles)
    }
    if (-not $devicePolicies) {
        $IsCompliant = $false
        $Comments = $msgTable.noDeviceFilterPolicies
    }

    # Check for location-based policies with admin users
    $locationPolicies = $caps | Where-Object { 
        $null -ne $_.conditions.locations.includeLocations -and 
        $_.state -eq 'enabled' -and
        ($adminUserIds -contains $_.conditions.users.includeRoles)
    }
    if (-not $locationPolicies) {
        $IsCompliant = $false
        $Comments += " " + $msgTable.noLocationFilterPolicies
    }
    
    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        Comments         = $Comments
        ItemName         = $ItemName
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }

    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors = $ErrorList
    }

    return $moduleOutput   
}