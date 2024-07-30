
function Get-CloudConsoleAccess {
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
        [string] $ReportTime
    )
    $IsCompliant = $false
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    
    # get named locations
    $locationsBaseAPIUrl = '/identity/conditionalAccess/namedLocations'
    try {
        $response = Invoke-GraphQuery -urlPath $locationsBaseAPIUrl -ErrorAction Stop
        $data = $response.Content
        $locations = $data.value
    }
    catch {
        $Errorlist.Add("Failed to call Microsoft Graph REST API at URL '$locationsBaseAPIUrl'; returned error message: $_") 
        Write-Warning "Error: Failed to call Microsoft Graph REST API at URL '$locationsBaseAPIUrl'; returned error message: $_"
    }

    # get conditional access policies
    $CABaseAPIUrl = '/identity/conditionalAccess/policies'
    try {
        $response = Invoke-GraphQuery -urlPath $CABaseAPIUrl -ErrorAction Stop

        $caps = $response.Content.value
    }
    catch {
        $Errorlist.Add("Failed to call Microsoft Graph REST API at URL '$CABaseAPIUrl'; returned error message: $_")
        Write-Warning "Error: Failed to call Microsoft Graph REST API at URL '$CABaseAPIUrl'; returned error message: $_"
    }
    
    # check that a named location for Canada exists and that a policy exists that uses it
    $validLocations = @()

    foreach ($location in $locations) {
        #Determine location conditions
        #get all valid locations: needs to have Canada Only
        if ($location.countriesAndRegions.Count -eq 1 -and $location.countriesAndRegions[0] -eq "CA") {
            $validLocations += $location
        }
    }

    $locationBasedPolicies = $caps | Where-Object { $_.conditions.locations.includeLocations -in $validLocations.ID -and $_.state -eq 'enabled' }

    if ($validLocations.count -ne 0) {
        #if there is at least one location with Canada only, we are good. If no Canada Only policy, not compliant.
        # Conditional access Policies
        # Need a location based policy, for admins (owners, contributors) that uses one of the valid locations above.
        # If there is no policy or the policy doesn't use one of the locations above, not compliant.

        if (!$locationBasedPolicies) {
            #failed. No policies have valid locations.
            $Comments = $msgTable.noCompliantPoliciesfound
            $IsCompliant = $false
        }
        else {
            #"Compliant Policies."
            $IsCompliant = $true
            $Comments = $msgTable.allPoliciesAreCompliant
        }      
    }
    else {
        # Failed. Reason: No locations have only Canada.
        $Comments = $msgTable.noLocationsCompliant
        $IsCompliant = $false
    }
    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        Comments         = $Comments
        ItemName         = $ItemName
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput   
}

