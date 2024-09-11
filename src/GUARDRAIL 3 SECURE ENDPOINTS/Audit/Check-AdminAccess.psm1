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

    # Administrative users roles to be checked
    $adminUserIds = @('owner', 'contributor', 'administrator')

    # Check for device-based policies with admin users
    $devicePolicies = $caps | Where-Object { 
        $null -ne $_.conditions.devices.includeDeviceStates -and 
        $_.state -eq 'enabled' -and
        ($_.assignments.includeUsers -contains $adminUserIds)
    }
    if (-not $devicePolicies) {
        $IsCompliant = $false
        #$Comments = $msgTable.noDeviceFilterPolicies
    }

    # Check for location-based policies with admin users
    $locationPolicies = $caps | Where-Object { 
        $null -ne $_.conditions.locations.includeLocations -and 
        $_.state -eq 'enabled' -and
        ($_.assignments.includeUsers -contains $adminUserIds)
    }
    if (-not $locationPolicies) {
        $IsCompliant = $false
        #$Comments += " " + $msgTable.noLocationFilterPolicies
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