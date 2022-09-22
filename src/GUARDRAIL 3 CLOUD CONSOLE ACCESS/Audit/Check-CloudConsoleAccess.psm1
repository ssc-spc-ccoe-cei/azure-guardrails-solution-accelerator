
function Get-CloudConsoleAccess {
    param (      
        #[Parameter(Mandatory=$true)]
[string] $ControlName,
        #[Parameter(Mandatory=$true)]
[string] $ItemName,
        #[Parameter(Mandatory=$true)]
[string] $WorkSpaceID,
        #[Parameter(Mandatory=$true)]
[string] $workspaceKey,
        #[Parameter(Mandatory=$true)]
[string] $LogType,
        #[Parameter(Mandatory=$true)]
[string] $itsgcode,
        #[Parameter(Mandatory=$true)]
[hashtable] $msgTable,
        #[Parameter(Mandatory=$true)]
[string] $ReportTime
    )
    #[PSCustomObject] $FinalObjectList = New-Object System.Collections.ArrayList
    [String] $GraphAccessToken = (Get-AzAccessToken -ResourceTypeName MSGraph).Token
    $IsCompliant=$false
    Write-Debug "Token: $GraphAccessToken"
    $locationsBaseAPIUrl = "https://graph.microsoft.com/v1.0/identity/conditionalAccess/namedLocations"
    $CABaseAPIUrl="https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies"

    $locations=(Invoke-RestMethod -Headers @{Authorization = "Bearer $($GraphAccessToken)" } -Uri $locationsBaseAPIUrl -Method Get -ErrorAction Stop).value
    #$locations
    $validLocations=@()
    foreach ($location in $locations)
    {
        #Determine location conditions
        #get all valid locations: needs to have Canada Only
        if ($location.countriesAndRegions.Count -eq 1 -and $location.countriesAndRegions -eq "CA")
        {
            $validLocations+=$location
        }
    }
    if ($validLocations.count -ne 0)
    {
        #if there is at least one location with Canada only, we are good. If no Canada Only policy, not compliant.
        # Conditional access Policies
        # Need a location based policy, for admins (owners, contributors) that uses one of the valid locations above.
        # If there is no policy or the policy doesn't use one of the locations above, not compliant.
        $caps=(Invoke-RestMethod -Headers @{Authorization = "Bearer $($GraphAccessToken)" } -Uri $CABaseAPIUrl -Method Get -ErrorAction Stop).value
        $validPolicies = $caps | Where-Object {$_.conditions.locations.includeLocations -in $validLocations.ID -and $cap.state -eq 'enabled'}
        if (!$validPolicies)
        {
            #failed. No policies have valid locations.
            $Comments=$msgTable.noCompliantPoliciesfound
            $IsCompliant=$false
        }
        else {
            "Compliant Policies."
            $IsCompliant = $true
            $Comments=$msgTable.allPoliciesAreCompliant
        }      
    }
    else {
        # Failed. Reason: No locations have only Canada.
        $Comments=$msgTable.noLocationsCompliant
        $IsCompliant=$false
    }
    $PsObject = [PSCustomObject]@{
        ComplianceStatus= $IsCompliant
        ControlName = $ControlName
        Comments= $Comments
        ItemName= $ItemName
        ReportTime = $ReportTime
        itsgcode = $itsgcode
     }
     $JsonObject = convertTo-Json -inputObject $PsObject 

     Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
                               -sharedkey $workspaceKey `
                               -body $JsonObject `
                               -logType $LogType `
                               -TimeStampField Get-Date 
}
