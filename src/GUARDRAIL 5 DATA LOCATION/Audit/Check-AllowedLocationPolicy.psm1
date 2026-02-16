function Get-PolicyComplianceDataOptimized {
    param (
        [Parameter(Mandatory=$true)]
        [string] $PolicyID,
        [string] $InitiativeID
    )

    # ARG query matching Get-AzPolicyState behavior exactly:
    # - Include Exempt resources in total count
    # - Only count explicitly 'Compliant' as compliant, explicitly 'NonCompliant' as non-compliant
    # - When InitiativeID is "N/A", only check standalone policies (correct behavior)
    
    $checkInitiative = ![string]::IsNullOrEmpty($InitiativeID) -and $InitiativeID -ne "N/A"
    
    # When InitiativeID is N/A, filter to only standalone policies
    $standaloneOnlyFilter = if (!$checkInitiative) { "| where isempty(policySetDefId)" } else { "" }
    
    $query = @"
policyresources
| where type == 'microsoft.policyinsights/policystates'
| where properties.policyDefinitionId contains '$PolicyID'
| extend subscriptionId = tostring(split(properties.resourceId, '/')[2])
| extend resourceId = tostring(properties.resourceId)
| extend timestamp = todatetime(properties.timestamp)
| extend complianceState = tostring(properties.complianceState)
| extend policySetDefId = tostring(properties.policySetDefinitionId)
| extend policyDefId = tostring(properties.policyDefinitionId)
| where isnotempty(subscriptionId)
$standaloneOnlyFilter
| summarize arg_max(timestamp, complianceState, policySetDefId, policyDefId, subscriptionId) by resourceId
| extend isCompliant = (complianceState == 'Compliant')
| extend isNonCompliant = (complianceState == 'NonCompliant')
| extend matchesInitiative = (policySetDefId == '$InitiativeID' and policyDefId contains '$PolicyID')
| extend matchesStandalone = (isempty(policySetDefId) and policyDefId contains '$PolicyID')
| summarize 
    InitiativeCompliantCount = countif(matchesInitiative and isCompliant),
    InitiativeNonCompliantCount = countif(matchesInitiative and isNonCompliant),
    InitiativeTotalCount = countif(matchesInitiative),
    PolicyCompliantCount = countif(matchesStandalone and isCompliant),
    PolicyNonCompliantCount = countif(matchesStandalone and isNonCompliant),
    PolicyTotalCount = countif(matchesStandalone)
    by subscriptionId
"@

    try {
        Write-Verbose "Executing Azure Resource Graph query for policy compliance states..."
        
        $cache = @{}
        $skipToken = $null
        $pageCount = 0
        
        # Paginate through all results using SkipToken
        do {
            $pageCount++
            if ($skipToken) {
                $results = Search-AzGraph -Query $query -First 1000 -SkipToken $skipToken
            } else {
                $results = Search-AzGraph -Query $query -First 1000
            }
            
            # Process results from this page
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
            
            # Get SkipToken for next page (if any)
            $skipToken = $results.SkipToken
            Write-Verbose "ARG query page $pageCount returned $($results.Count) subscription(s), SkipToken: $($null -ne $skipToken)"
            
        } while ($skipToken)
        
        Write-Verbose "ARG query completed - total subscriptions cached: $($cache.Count)"
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
                    # Fallback: no cached data, use Get-AzPolicyState
                    Write-Verbose "No cached data, using Get-AzPolicyState for subscription $($obj.Name)"
                    
                    $currentSubscription = Get-AzContext
                    if($currentSubscription.Subscription.Id -ne $obj.Id){
                        Set-AzContext -SubscriptionId $obj.Id | Out-Null
                        Write-Verbose "AzContext set to $($obj.Name)"
                    }

                    if(!($null -eq $AssignedInitiatives -or $AssignedInitiatives -eq "N/A")){
                        $InitiativeState = Get-AzPolicyState | Where-Object { ($_.PolicySetDefinitionId -eq $InitiativeID) -and ($_.PolicyDefinitionId -like "*$PolicyID*")} 
                        $TotalInitResources = $InitiativeState.Count
                        $InitCompliantResources = ($InitiativeState | Where-Object {$_.IsCompliant -eq $true}).Count
                        $InitNonCompliantResources = ($InitiativeState | Where-Object {$_.IsCompliant -eq $false}).Count
                    }
                    if(!($null -eq $AssignedPolicyList)){
                        # FIXED: Correct filter for standalone policies (empty PolicySetDefinitionId)
                        $PolicyState = Get-AzPolicyState | Where-Object { [string]::IsNullOrEmpty($_.PolicySetDefinitionId) -and ($_.PolicyDefinitionId -like "*$PolicyID*") }
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

        $props = @{ 
            Type = [string]$objType
            Id = [string]$obj.Id
            # Only populate SubscriptionName for subscription-scoped rows; other row types (tenant/resource) would be misleading.
            SubscriptionName = $(if ($objType -eq "subscription") { [string]$obj.Name } else { "" })
            Name = [string]$obj.Name
            ComplianceStatus = [boolean]$ComplianceStatus
            Comments = [string]$Comment
            ItemName = [string]$ItemName
            itsgcode = [string]$itsgcode
            ControlName = [string]$ControlName
            ReportTime = [string]$ReportTime
        }
        if ($objType -ne "subscription") {
            # Only compute DisplayName for non-subscription rows; subscription rows omit DisplayName to avoid duplication.
            if ($null -eq $obj.DisplayName)
            {
                $DisplayName=$obj.Name
            }
            else {
                $DisplayName=$obj.DisplayName
            }
            $props.DisplayName = [string]$DisplayName
        }
        $c = New-Object -TypeName PSCustomObject -Property $props

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
