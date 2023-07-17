

function Check-PolicyStatus {
    param (
        [System.Object] $objList,
        [Parameter(Mandatory=$true)]
        [string] $objType, #subscription or management Group
        [string] $PolicyID, # full policy id, not just the GUID
        [string] $ControlName,
        [string] $ItemName,
        [string] $itsgcode,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime,
        [array] $AllowedLocations
    )   
    [PSCustomObject] $tempObjectList = New-Object System.Collections.ArrayList
    foreach ($obj in $objList)
    {
        Write-Verbose "Checking $objType : $($obj.Name)"
        if ($objType -eq "subscription") {
            $tempId="/subscriptions/$($obj.Id)"
        }
        else {
            $tempId=$obj.Id
        }
        try {
            $AssignedPolicyList = Get-AzPolicyAssignment -scope $tempId -PolicyDefinitionId $PolicyID
        }
        catch {
            $Errorlist.Add("Failed to execute the 'Get-AzPolicyAssignment' command for scope '$($tempId)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_" )
            Write-Error "Error: Failed to execute the 'Get-AzPolicyAssignment' command for scope '$($tempId)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_"                
        }
        If ($null -eq $AssignedPolicyList -or (-not ([string]::IsNullOrEmpty(($AssignedPolicyList.Properties.NotScopesScope)))))
        {
            $Comment=$($msgTable.policyNotAssigned -f $objType)
            $ComplianceStatus=$false
        }
        else {
            # Test for allowed locations if not null
            $ComplianceStatus=$true # should be true unless we find a non-compliant location
            $Comment=$msgTable.isCompliant 
            if (!([string]::IsNullOrEmpty($AllowedLocations)))
            {
                $AssignedLocations = $AssignedPolicyList.Properties.Parameters.listOfAllowedLocations.value # gets currently assigned locations
                foreach ($AssignedLocation in $AssignedLocations) {
                    if ( $AssignedLocation -notin $AllowedLocations) {
                        $ComplianceStatus=$false
                        $Comment=$msgTable.notAllowedLocation
                    }
                }
            }
        }
        if ($null -eq $obj.DisplayName)
        {
            $DisplayName=$obj.Name
        }
        else {
            $DisplayName=$obj.DisplayName
        }

        $c = New-Object -TypeName PSCustomObject -Property @{ 
            Type = [string]$objType
            Id = [string]$obj.Id
            Name = [string]$obj.Name
            DisplayName = [string]$DisplayName
            ComplianceStatus = [boolean]$ComplianceStatus
            Comments = [string]$Comment
            ItemName = [string]$ItemName
            itsgcode = [string]$itsgcode
            ControlName = [string]$ControlName
            ReportTime = [string]$ReportTime
        }
        
        $tempObjectList.add($c)| Out-Null
    }
    return $tempObjectList
}

function Verify-AllowedLocationPolicy {
    param (
        [switch] $DebugData,
        [string] $ControlName,
        [string] $ItemName,
        [string] $PolicyID, 
        [string] $LogType,
        [string] $itsgcode,
        [Parameter(Mandatory=$true)]
        [string] $AllowedLocationsString,#locations, separated by comma.
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime,
        [Parameter(Mandatory=$false)]
        [string]
        $CBSSubscriptionName
    )

    [PSCustomObject] $FinalObjectList = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    $AllowedLocations = $AllowedLocationsString.Split(",")
    if ($AllowedLocations.Count -eq 0 -or $AllowedLocations -eq $null) {
        $Errorlist.Add("No allowed locations were provided. Please provide a list of allowed locations separated by commas.")
        throw "No allowed locations were provided. Please provide a list of allowed locations separated by commas."
        break
    }
    # @("canada" , "canadaeast" , "canadacentral")
    #Check management groups   
    try {
        $objs = Get-AzManagementGroup -ErrorAction Stop
    }
    catch {
        $Errorlist.Add("Failed to execute the 'Get-AzManagementGroup' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_")
        throw "Error: Failed to execute the 'Get-AzManagementGroup' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_"
    }

    try {
        $ErrorActionPreference = 'Stop'
        $type = "Management Group"
        $FinalObjectList+=Check-PolicyStatus -AllowedLocations $AllowedLocations -objList $objs -objType $type -PolicyID $PolicyID -itsgcode $itsgcode -ReportTime $ReportTime -ItemName $ItemName -msgTable $msgTable -ControlName $ControlName
    }
    catch {
        $Errorlist.Add("Failed to execute the 'Check-PolicyStatus' function. ReportTime: '$ReportTime' Error message: $_")
        throw "Failed to execute the 'Check-PolicyStatus' function. Error message: $_"
    }
    finally {
        $ErrorActionPreference = 'Continue'
    }
    #Check Subscriptions
    try {
        $objs = Get-AzSubscription -ErrorAction Stop
    }
    catch {
        $Errorlist.Add("Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_" )
        throw "Error: Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_"
    }

    try {
        $ErrorActionPreference = 'Stop'
        $type = "subscription"
        $FinalObjectList+=Check-PolicyStatus -AllowedLocations $AllowedLocations -objList $objs -objType $type -PolicyID $PolicyID -itsgcode $itsgcode -ReportTime $ReportTime -ItemName $ItemName -msgTable $msgTable -ControlName $ControlName
    }
    catch {
        $Errorlist.Add("Failed to execute the 'Check-PolicyStatus' function. ReportTime: '$ReportTime' Error message: $_" )
        throw "Failed to execute the 'Check-PolicyStatus' function. Error message: $_"
    }
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $FinalObjectList 
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput
}

