function Get-PolicyComplianceDataOptimized {
    param (
        [Parameter(Mandatory=$true)]
        [string] $PolicyID,
        [string] $InitiativeID
    )

    # Simple, reliable ARG query
    # Keep Get-AzPolicyAssignment for assignments (handles MG inheritance correctly)
    $queryParts = @()
    $queryParts += "policyresources"
    $queryParts += "| where type == 'microsoft.policyinsights/policystates'"
    $queryParts += "| where properties.policyDefinitionId contains '$PolicyID'"
    
    $queryParts += "| extend subscriptionId = tostring(split(properties.resourceId, '/')[2])"
    $queryParts += "| extend complianceState = tostring(properties.complianceState)"
    $queryParts += "| extend policySetDefId = tostring(properties.policySetDefinitionId)"
    $queryParts += "| extend policyDefId = tostring(properties.policyDefinitionId)"
    $queryParts += "| extend isCompliant = (properties.complianceState == 'Compliant')"
    $queryParts += "| where isnotempty(subscriptionId)"
    
    # Match original filtering logic
    if (![string]::IsNullOrEmpty($InitiativeID)) {
        # Initiative: PolicySetDefinitionId == InitiativeID AND PolicyDefinitionId contains PolicyID
        # Standalone: PolicySetDefinitionId == PolicyID
        $queryParts += "| summarize InitiativeCompliantCount = countif(policySetDefId == '$InitiativeID' and policyDefId contains '$PolicyID' and isCompliant), InitiativeNonCompliantCount = countif(policySetDefId == '$InitiativeID' and policyDefId contains '$PolicyID' and not(isCompliant)), InitiativeTotalCount = countif(policySetDefId == '$InitiativeID' and policyDefId contains '$PolicyID'), PolicyCompliantCount = countif(policySetDefId == '$PolicyID' and isCompliant), PolicyNonCompliantCount = countif(policySetDefId == '$PolicyID' and not(isCompliant)), PolicyTotalCount = countif(policySetDefId == '$PolicyID') by subscriptionId"
    } else {
        # No initiative specified - only check standalone: PolicySetDefinitionId == PolicyID
        $queryParts += "| summarize InitiativeCompliantCount = 0, InitiativeNonCompliantCount = 0, InitiativeTotalCount = 0, PolicyCompliantCount = countif(policySetDefId == '$PolicyID' and isCompliant), PolicyNonCompliantCount = countif(policySetDefId == '$PolicyID' and not(isCompliant)), PolicyTotalCount = countif(policySetDefId == '$PolicyID') by subscriptionId"
    }
    
    $query = $queryParts -join " "

    try {
        Write-Verbose "Executing Azure Resource Graph query for policy compliance states..."
        $results = Search-AzGraph -Query $query -First 1000
        
        Write-Verbose "ARG query returned compliance data for $($results.Count) subscription(s)"
        
        $cache = @{}
        foreach ($result in $results) {
            $cache[$result.subscriptionId] = @{
                InitiativeTotalCount = $result.InitiativeTotalCount
                InitiativeCompliantCount = $result.InitiativeCompliantCount
                InitiativeNonCompliantCount = $result.InitiativeNonCompliantCount
                PolicyTotalCount = $result.PolicyTotalCount
                PolicyCompliantCount = $result.PolicyCompliantCount
                PolicyNonCompliantCount = $result.PolicyNonCompliantCount
            }
        }
        return $cache
    }
    catch {
        Write-Verbose "ARG query failed, will use per-subscription method: $_"
        return @{}
    }
}

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
        $CloudUsageProfiles = "3",
        [string] $ModuleProfiles,
        [switch] $EnableMultiCloudProfiles, # default to false
        [hashtable] $ComplianceCache = @{}
    )

    [PSCustomObject] $tempObjectList = New-Object System.Collections.ArrayList
    $TotalInitResources = 0
    $TotalPolicyResources = 0
    $InitNonCompliantResources = 0
    $InitCompliantResources = 0
    $PolicyNonCompliantResources = 0
    $PolicyCompliantResources = 0

    foreach ($obj in $objList)
    {
        Write-Verbose "Checking $objType : $($obj.Name)"
        if ($objType -eq "subscription") {
            $tempId="/subscriptions/$($obj.Id)"
        }
        else {
            $tempId=$obj.Id
        }

        #Retrieving policies and initiatives
        try{
            $AssignedPolicyList = Get-AzPolicyAssignment -scope $tempId -PolicyDefinitionId $PolicyID 
            $AssignedInitiatives = Get-AzPolicyAssignment -scope $tempId -PolicyDefinitionId $InitiativeID
        }
        catch{
            $Errorlist.Add("Failed to retrieve policy or initiative assignments for scope '$($tempId)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_" )
            Write-Error "Error: Failed to retrieve policy or initiative assignments for scope '$($tempId)'--verify your permissions and the installion of the Az.Resources module; returned error message: $_" 
        }

        If (($null -eq $AssignedPolicyList -and ($null -eq $AssignedInitiatives -or $AssignedInitiatives -eq "N/A")) -or `
            ((-not ([string]::IsNullOrEmpty(($AssignedPolicyList.Properties.NotScopesScope)))) -or (-not ([string]::IsNullOrEmpty(($AssignedInitiatives.Properties.NotScopesScope))))))
        {
            $Comment=$($msgTable.policyNotAssigned -f $objType)
            $ComplianceStatus=$false
        }
        else {

            # Test for allowed locations in policies if not null
            $ComplianceStatus=$true # should be true unless we find a non-compliant location
            
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

            if ($null -ne $AssignedInitiatives -and $AssignedInitiatives -ne "N/A"){
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

        
        if($ComplianceStatus -eq $true){
            # Check the number of resources and compliance for the required policies in applied PBMM initiative
            # ----------------#
            # Subscription
            # ----------------#
            if ($objType -eq "subscription"){
                Write-Verbose "Find compliance details for Subscription : $($obj.Name)"
                
                # Try to use cached data first (from ARG query)
                if ($ComplianceCache.ContainsKey($obj.Id)) {
                    Write-Verbose "Using cached compliance data for subscription $($obj.Name)"
                    $cached = $ComplianceCache[$obj.Id]
                    $TotalInitResources = $cached.InitiativeTotalCount
                    $InitCompliantResources = $cached.InitiativeCompliantCount
                    $InitNonCompliantResources = $cached.InitiativeNonCompliantCount
                    $TotalPolicyResources = $cached.PolicyTotalCount
                    $PolicyCompliantResources = $cached.PolicyCompliantCount
                    $PolicyNonCompliantResources = $cached.PolicyNonCompliantCount
                }
                else {
                    # Fallback to Get-AzPolicyState if not in cache (no context switching needed!)
                    Write-Verbose "No cached data, using Get-AzPolicyState for subscription $($obj.Name)"

                    if(!($null -eq $AssignedInitiatives -or $AssignedInitiatives -eq "N/A")){
                        $InitiativeState = Get-AzPolicyState -SubscriptionId $obj.Id | Where-Object { ($_.PolicySetDefinitionId -eq $InitiativeID)  -and ($_.PolicyDefinitionId -like "*$PolicyID*")} 
                        $TotalInitResources = $InitiativeState.Count
                        $InitCompliantResources = ($InitiativeState | Where-Object {$_.IsCompliant -eq $true}).Count
                        $InitNonCompliantResources = ($InitiativeState | Where-Object {$_.IsCompliant -eq $false}).Count
                    }
                    if(!($null -eq $AssignedPolicyList)){
                        $PolicyState = Get-AzPolicyState -SubscriptionId $obj.Id | Where-Object { $_.PolicySetDefinitionId -eq $PolicyID }
                        $TotalPolicyResources = $PolicyState.Count
                        $PolicyCompliantResources = ($PolicyState | Where-Object {$_.IsCompliant -eq $true}).Count
                        $PolicyNonCompliantResources = ($PolicyState | Where-Object {$_.IsCompliant -eq $false}).Count
                    }
                }

                if (($TotalInitResources -gt 0 -and $TotalPolicyResources -eq 0) -or ($TotalPolicyResources -gt 0 -and $TotalInitResources -eq 0)) {
                    # Case 1: Only Initiative has resources, check initiative compliance
                    # Case 2: Only Policy has resources, check policy compliance
                    
                    if ($TotalInitResources -gt 0 -and $TotalInitResources -eq $InitNonCompliantResources) {
                        $ComplianceStatus = $false
                        $Comment = $msgTable.isNotCompliant + ' ' + $msgTable.allNonCompliantResources
                    } 
                    elseif ($TotalPolicyResources -gt 0 -and $TotalPolicyResources -eq $PolicyNonCompliantResources) {
                        $ComplianceStatus = $false
                        $Comment = $msgTable.isNotCompliant + ' ' + $msgTable.allNonCompliantResources
                    } 
                    elseif($InitNonCompliantResources -gt 0 -and ($InitNonCompliantResources -lt $TotalInitResources)){
                        $ComplianceStatus = $false
                        $Comment = $msgTable.isNotCompliant + ' ' + $msgTable.hasNonComplianceResource -f $InitNonCompliantResources, $TotalInitResources
                    }
                    elseif($PolicyNonCompliantResources -gt 0 -and ($PolicyNonCompliantResources -lt $TotalPolicyResources)){
                        $ComplianceStatus = $false
                        $Comment = $msgTable.isNotCompliant + ' ' + $msgTable.hasNonComplianceResource -f $PolicyNonCompliantResources, $TotalPolicyResources
                    }
                    else{
                        $ComplianceStatus = $true
                        $Comment = $msgTable.isCompliant + ' ' + $msgTable.allCompliantResources
                    }
                }
                elseif ($TotalInitResources -gt 0 -and $TotalPolicyResources -gt 0) {
                    # Case 3: Both Initiative and Policy have assigned resources, so check both
                
                    if ($TotalInitResources -eq $InitCompliantResources -and $TotalPolicyResources -eq $PolicyCompliantResources) {
                        $ComplianceStatus = $true
                        $Comment = $msgTable.isCompliant + ' ' + $msgTable.allCompliantResources
                    } 
                    elseif($InitNonCompliantResources -gt 0 -and ($InitNonCompliantResources -lt $TotalInitResources)){
                        $ComplianceStatus = $false
                        $Comment = $msgTable.isNotCompliant + ' ' + $msgTable.hasNonComplianceResource -f $InitNonCompliantResources, $TotalInitResources
                    }
                    elseif($PolicyNonCompliantResources -gt 0 -and ($PolicyNonCompliantResources -lt $TotalPolicyResources)){
                        $ComplianceStatus = $false
                        $Comment = $msgTable.isNotCompliant + ' ' + $msgTable.hasNonComplianceResource -f $PolicyNonCompliantResources, $TotalPolicyResources
                    }
                }
                elseif($TotalInitResources -eq 0 -and $TotalPolicyResources -eq 0){
                    $ComplianceStatus = $true
                    $Comment = $msgTable.isCompliant + ' ' + $msgTable.noResource
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

        if ($EnableMultiCloudProfiles) {
            if ($objType -eq "subscription") {
                $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $obj.Id
            } else {
                $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
            }
            
            if (!$evalResult.ShouldEvaluate) {
                if(!$evalResult.ShouldAvailable ){
                    if ($evalResult.Profile -gt 0) {
                        $c.ComplianceStatus = "Not Applicable"
                        $c | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                        $c.Comments = "Not available - Profile $($evalResult.Profile) not applicable for this guardrail"
                    } else {
                        $ErrorList.Add("Error occurred while evaluating profile configuration availability")
                    }
                } else {
                    if ($evalResult.Profile -gt 0) {
                        $c.ComplianceStatus = "Not Applicable"
                        $c | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                        $c.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
                    } else {
                        $ErrorList.Add("Error occurred while evaluating profile configuration")
                    }
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
        [string] $AllowedLocationsString,   #locations, separated by comma.
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
    #Check Subscriptions
    try {
        $objs = Get-AzSubscription -ErrorAction Stop | Where-Object {$_.State -eq "Enabled"} 
    }
    catch {
        $Errorlist.Add("Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_" )
        throw "Error: Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_"
    }

    # Try to fetch compliance data using optimized ARG query first
    Write-Verbose "Attempting to fetch compliance data using Azure Resource Graph..."
    try {
        $ComplianceCache = Get-PolicyComplianceDataOptimized -PolicyID $PolicyID -InitiativeID $InitiativeID
        if ($ComplianceCache.Count -gt 0) {
            Write-Verbose "Successfully cached compliance data for $($ComplianceCache.Count) subscriptions"
        } else {
            Write-Verbose "No compliance data found in ARG, will use per-subscription method"
        }
    }
    catch {
        Write-Verbose "ARG query failed, will use per-subscription method: $_"
        $ComplianceCache = @{}
    }

    try {
        $ErrorActionPreference = 'Stop'
        $type = "subscription"
        if ($EnableMultiCloudProfiles) {
            $ObjectList+=Check-PolicyStatus -AllowedLocations $AllowedLocations -objList $objs -objType $type -PolicyID $PolicyID -InitiativeID $InitiativeID -itsgcode $itsgcode -ReportTime $ReportTime -ItemName $ItemName -msgTable $msgTable -ControlName $ControlName -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -EnableMultiCloudProfiles -ComplianceCache $ComplianceCache
        } else {
            $ObjectList+=Check-PolicyStatus -AllowedLocations $AllowedLocations -objList $objs -objType $type -PolicyID $PolicyID -InitiativeID $InitiativeID -itsgcode $itsgcode -ReportTime $ReportTime -ItemName $ItemName -msgTable $msgTable -ControlName $ControlName -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -ComplianceCache $ComplianceCache
        }
    }
    catch {
        $Errorlist.Add("Failed to execute the 'Check-PolicyStatus' function. ReportTime: '$ReportTime' Error message: $_" )
        throw "Failed to execute the 'Check-PolicyStatus' function. Error message: $_"
    }

    # Filter out objects of type PSAzureContext
    $FinalObjectList = $ObjectList | Where-Object { $_.GetType() -notlike "*PSAzureContext*" }
    
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $FinalObjectList 
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }

    return $moduleOutput
}
