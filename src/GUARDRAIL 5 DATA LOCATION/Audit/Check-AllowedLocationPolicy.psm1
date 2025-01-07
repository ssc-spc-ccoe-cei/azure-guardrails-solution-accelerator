function Check-PolicyStatus {
    param (
        [System.Object] $objList,
        [Parameter(Mandatory=$true)]
        [string] $objType, #subscription or management Group
        [string] $PolicyID, # full policy id, not just the GUID
        [string] $InitiativeID,
        [string] $ControlName,
        [string] $ItemName,
        [string] $itsgcode,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime,
        [array] $AllowedLocations,
        [string] 
        $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] $EnableMultiCloudProfiles # New feature flag, default to false    
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
            try{
                $AssignedPolicyList = Get-AzPolicyAssignment -scope $tempId -PolicyDefinitionId $PolicyID

            }
            catch{
                $Errorlist.Add("Failed to execute the 'Get-AzPolicyAssignment' command on policy list for scope '$($tempId)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_" )
                Write-Error "Error: Failed to execute the 'Get-AzPolicyAssignment' command on policy list for scope '$($tempId)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_"  
            }
            try{
                $AssignedInitiatives = Get-AzPolicyAssignment -scope $tempId -PolicyDefinitionId $InitiativeID #Retrieve Initiatives
            }
            catch{
                $Errorlist.Add("Failed to execute the 'Get-AzPolicyAssignment' command on initiatives for scope '$($tempId)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_" )
                Write-Error "Error: Failed to execute the 'Get-AzPolicyAssignment' command on initiatives for scope '$($tempId)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_"  
            }
        }
        catch {
            $Errorlist.Value.Add("Failed to execute the 'Get-AzPolicyAssignment' command for scope '$($tempId)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_" )
            Write-Error "Error: Failed to execute the 'Get-AzPolicyAssignment' command for scope '$($tempId)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_"                
        }
        If (($null -eq $AssignedPolicyList -and ($null -eq $AssignedInitiatives -or $AssignedInitiatives -eq "")) -or ((-not ([string]::IsNullOrEmpty(($AssignedPolicyList.Properties.NotScopesScope)))) -or (-not ([string]::IsNullOrEmpty(($AssignedInitiatives.Properties.NotScopesScope))))))
        {
            $Comment=$($msgTable.policyNotAssigned -f $objType)
            $ComplianceStatus=$false
        }
        else {

            # Test for allowed locations in policies if not null
            $ComplianceStatus=$true # should be true unless we find a non-compliant location
            $Comment=$msgTable.isCompliant
            
            if ($null -ne $AssignedPolicyList){
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

            if ($null -ne $AssignedInitiatives -and $AssignedInitiatives -ne ""){
                if (!([string]::IsNullOrEmpty($AllowedLocations)))
                {
                    $AssignedLocations = $AssignedInitiatives.Properties.Parameters.listOfAllowedLocations.value # gets currently assigned locations
                    foreach ($AssignedLocation in $AssignedLocations) {
                        if ( $AssignedLocation -notin $AllowedLocations) {
                            $ComplianceStatus=$false
                            $Comment=$msgTable.notAllowedLocation
                        }
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

        Write-Output "Policies for $($DisplayName) : $($AssignedPolicyList)"
        Write-Output "Initiatives for $($DisplayName) : $($AssignedInitiatives)"

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

        if ($EnableMultiCloudProfiles) {
            if ($objType -eq "subscription") {
                $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $obj.Id
            } else {
                $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
            }
            
            if (!$evalResult.ShouldEvaluate) {
                if ($evalResult.Profile -gt 0) {
                    $c.ComplianceStatus = "Not Applicable"
                    $c | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                    $c.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
                } else {
                    $ErrorList.Add("Error occurred while evaluating profile configuration")
                }
            } else {
                
                $c | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
            }
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
        [string] $InitiativeID,
        [string] $LogType,
        [string] $itsgcode,
        [Parameter(Mandatory=$true)]
        [string] $AllowedLocationsString,#locations, separated by comma.
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string] $ReportTime,
        [Parameter(Mandatory=$false)]
        [string] $CBSSubscriptionName,
        [string] $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] $EnableMultiCloudProfiles # New feature flag, default to false    
    )

    [PSCustomObject] $FinalObjectList = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    $AllowedLocations = $AllowedLocationsString.Split(",")
    if ($AllowedLocations.Count -eq 0 -or $null -eq $AllowedLocations) {
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
        if ($EnableMultiCloudProfiles) {
            $FinalObjectList+=Check-PolicyStatus -AllowedLocations $AllowedLocations -objList $objs -objType $type -PolicyID $PolicyID -InitiativeID $InitiativeID -itsgcode $itsgcode -ReportTime $ReportTime -ItemName $ItemName -msgTable $msgTable -ControlName $ControlName -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -EnableMultiCloudProfiles
        } else {
            $FinalObjectList+=Check-PolicyStatus -AllowedLocations $AllowedLocations -objList $objs -objType $type -PolicyID $PolicyID -InitiativeID $InitiativeID -itsgcode $itsgcode -ReportTime $ReportTime -ItemName $ItemName -msgTable $msgTable -ControlName $ControlName -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        }
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
        if ($EnableMultiCloudProfiles) {
            $FinalObjectList+=Check-PolicyStatus -AllowedLocations $AllowedLocations -objList $objs -objType $type -PolicyID $PolicyID -InitiativeID $InitiativeID -itsgcode $itsgcode -ReportTime $ReportTime -ItemName $ItemName -msgTable $msgTable -ControlName $ControlName -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -EnableMultiCloudProfiles 
        } else {
            $FinalObjectList+=Check-PolicyStatus -AllowedLocations $AllowedLocations -objList $objs -objType $type -PolicyID $PolicyID -InitiativeID $InitiativeID -itsgcode $itsgcode -ReportTime $ReportTime -ItemName $ItemName -msgTable $msgTable -ControlName $ControlName -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles 
        }
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

