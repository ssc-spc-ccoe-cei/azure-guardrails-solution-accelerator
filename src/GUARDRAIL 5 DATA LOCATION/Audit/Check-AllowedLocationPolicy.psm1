function Get-PolicyComplianceData {
    param (
        [Parameter(Mandatory=$true)]
        [string] $PolicyID,
        [string] $InitiativeID,
        [array] $AllowedLocations,
        [hashtable] $msgTable
    )

    # Extract policy GUID from full ID
    $policyGuid = ($PolicyID -split '/')[-1]
    $initiativeGuid = if ($InitiativeID) { ($InitiativeID -split '/')[-1] } else { "" }

    # Optimized Azure Resource Graph query
    $query = @"
// Get policy assignments with location configurations
let policyAssignments = policyresources
| where type == "microsoft.authorization/policyassignments"
| where properties.policyDefinitionId contains "$policyGuid"
| extend 
    subscriptionId = tostring(split(properties.scope, "/")[2]),
    scope = properties.scope,
    assignmentName = name,
    policyDefId = properties.policyDefinitionId,
    assignedLocations = properties.parameters.listOfAllowedLocations.value,
    notScopes = properties.notScopes,
    assignmentId = id,
    isInitiative = iff(properties.policyDefinitionId contains "policySetDefinitions", true, false)
| where isnotempty(subscriptionId)
| project subscriptionId, scope, assignmentName, policyDefId, assignedLocations, notScopes, assignmentId, isInitiative;
// Get compliance states for the policy
let policyComplianceStates = policyresources
| where type == "microsoft.policyinsights/policystates"
| where properties.policyDefinitionId contains "$policyGuid"
| where isempty("$initiativeGuid") or properties.policySetDefinitionId contains "$initiativeGuid"
| extend 
    subscriptionId = tostring(split(properties.resourceId, "/")[2]),
    complianceState = tostring(properties.complianceState),
    resourceId = properties.resourceId,
    policyAssignmentId = properties.policyAssignmentId,
    policySetDefId = tostring(properties.policySetDefinitionId),
    isInitiativeCompliance = isnotempty(properties.policySetDefinitionId)
| where isnotempty(subscriptionId)
| summarize 
    TotalResources = count(),
    CompliantResources = countif(complianceState == "Compliant"),
    NonCompliantResources = countif(complianceState == "NonCompliant"),
    InitiativeTotalResources = countif(isInitiativeCompliance),
    InitiativeCompliantResources = countif(isInitiativeCompliance and complianceState == "Compliant"),
    InitiativeNonCompliantResources = countif(isInitiativeCompliance and complianceState == "NonCompliant"),
    PolicyTotalResources = countif(not(isInitiativeCompliance)),
    PolicyCompliantResources = countif(not(isInitiativeCompliance) and complianceState == "Compliant"),
    PolicyNonCompliantResources = countif(not(isInitiativeCompliance) and complianceState == "NonCompliant")
    by subscriptionId;
// Join and create final result
policyAssignments
| join kind=leftouter (policyComplianceStates) on subscriptionId
| summarize 
    Assignments = make_list(pack(
        "name", assignmentName,
        "policyDefinitionId", policyDefId,
        "scope", scope,
        "assignedLocations", assignedLocations,
        "notScopes", notScopes,
        "assignmentId", assignmentId,
        "isInitiative", isInitiative
    )),
    TotalResources = max(TotalResources),
    CompliantResources = max(CompliantResources),
    NonCompliantResources = max(NonCompliantResources),
    InitiativeTotalResources = max(InitiativeTotalResources),
    InitiativeCompliantResources = max(InitiativeCompliantResources),
    InitiativeNonCompliantResources = max(InitiativeNonCompliantResources),
    PolicyTotalResources = max(PolicyTotalResources),
    PolicyCompliantResources = max(PolicyCompliantResources),
    PolicyNonCompliantResources = max(PolicyNonCompliantResources),
    HasPolicyAssigned = countif(isnotempty(assignmentName)) > 0
    by subscriptionId
| extend 
    TotalResources = coalesce(TotalResources, 0),
    CompliantResources = coalesce(CompliantResources, 0),
    NonCompliantResources = coalesce(NonCompliantResources, 0),
    InitiativeTotalResources = coalesce(InitiativeTotalResources, 0),
    InitiativeCompliantResources = coalesce(InitiativeCompliantResources, 0),
    InitiativeNonCompliantResources = coalesce(InitiativeNonCompliantResources, 0),
    PolicyTotalResources = coalesce(PolicyTotalResources, 0),
    PolicyCompliantResources = coalesce(PolicyCompliantResources, 0),
    PolicyNonCompliantResources = coalesce(PolicyNonCompliantResources, 0)
| project 
    subscriptionId,
    HasPolicyAssigned,
    Assignments,
    TotalResources,
    CompliantResources,
    NonCompliantResources,
    InitiativeTotalResources,
    InitiativeCompliantResources,
    InitiativeNonCompliantResources,
    PolicyTotalResources,
    PolicyCompliantResources,
    PolicyNonCompliantResources
| order by subscriptionId asc
"@

    try {
        Write-Verbose "Executing Azure Resource Graph query for policy compliance data..."
        $results = Search-AzGraph -Query $query -First 1000
        
        # Process results and validate locations
        $processedResults = @{}
        foreach ($result in $results) {
            $subData = @{
                SubscriptionId = $result.subscriptionId
                HasPolicyAssigned = $result.HasPolicyAssigned
                Assignments = $result.Assignments
                TotalResources = $result.TotalResources
                CompliantResources = $result.CompliantResources
                NonCompliantResources = $result.NonCompliantResources
                InitiativeTotalResources = $result.InitiativeTotalResources
                InitiativeCompliantResources = $result.InitiativeCompliantResources
                InitiativeNonCompliantResources = $result.InitiativeNonCompliantResources
                PolicyTotalResources = $result.PolicyTotalResources
                PolicyCompliantResources = $result.PolicyCompliantResources
                PolicyNonCompliantResources = $result.PolicyNonCompliantResources
                HasNotScopes = $false
                HasInvalidLocations = $false
                InvalidLocations = @()
            }

            # Check assignments for notScopes and invalid locations
            foreach ($assignment in $result.Assignments) {
                if ($assignment.notScopes -and $assignment.notScopes.Count -gt 0) {
                    $subData.HasNotScopes = $true
                }
                
                if ($AllowedLocations -and $AllowedLocations.Count -gt 0 -and $assignment.assignedLocations) {
                    foreach ($assignedLoc in $assignment.assignedLocations) {
                        if ($assignedLoc -notin $AllowedLocations) {
                            $subData.HasInvalidLocations = $true
                            $subData.InvalidLocations += $assignedLoc
                        }
                    }
                }
            }

            $processedResults[$result.subscriptionId] = $subData
        }

        return $processedResults
    }
    catch {
        Write-Error "Failed to execute Azure Resource Graph query: $_"
        throw
    }
}

function Check-PolicyStatus {
    param (
        [System.Object] $objList,
        [Parameter(Mandatory=$true)]
        [string] $objType,
        [string] $PolicyID,
        [string] $InitiativeID,
        [string] $ControlName,
        [string] $ItemName,
        [string] $itsgcode,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string] $ReportTime,
        [array] $AllowedLocations,
        [string] $CloudUsageProfiles = "3",
        [string] $ModuleProfiles,
        [switch] $EnableMultiCloudProfiles,
        [hashtable] $ComplianceDataCache
    )

    [PSCustomObject] $tempObjectList = New-Object System.Collections.ArrayList

    foreach ($obj in $objList)
    {
        Write-Verbose "Processing $objType : $($obj.Name)"
        
        $ComplianceStatus = $true
        $Comment = ""
        
        # Get cached compliance data for this subscription
        $complianceData = $ComplianceDataCache[$obj.Id]
        
        if ($null -eq $complianceData -or -not $complianceData.HasPolicyAssigned) {
            # Policy not assigned
            $Comment = $($msgTable.policyNotAssigned -f $objType)
            $ComplianceStatus = $false
        }
        elseif ($complianceData.HasNotScopes) {
            # Has notScopes configured
            $Comment = $($msgTable.policyNotAssigned -f $objType)
            $ComplianceStatus = $false
        }
        elseif ($complianceData.HasInvalidLocations) {
            # Has locations that are not in allowed list
            $ComplianceStatus = $false
            $Comment = $msgTable.notAllowedLocation
        }
        else {
            # Policy is assigned correctly, check resource compliance
            $TotalInitResources = $complianceData.InitiativeTotalResources
            $InitCompliantResources = $complianceData.InitiativeCompliantResources
            $InitNonCompliantResources = $complianceData.InitiativeNonCompliantResources
            $TotalPolicyResources = $complianceData.PolicyTotalResources
            $PolicyCompliantResources = $complianceData.PolicyCompliantResources
            $PolicyNonCompliantResources = $complianceData.PolicyNonCompliantResources

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

        if ($null -eq $obj.DisplayName)
        {
            $DisplayName = $obj.Name
        }
        else {
            $DisplayName = $obj.DisplayName
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
    $AllowedLocations = $AllowedLocationsString.Split(",") | ForEach-Object { $_.Trim() }
    if ($AllowedLocations.Count -eq 0 -or $null -eq $AllowedLocations) {
        $Errorlist.Add("No allowed locations were provided. Please provide a list of allowed locations separated by commas.")
        throw "No allowed locations were provided. Please provide a list of allowed locations separated by commas."
        break
    }
    
    Write-Host "Allowed locations for validation: $($AllowedLocations -join ', ')"
    
    #Check Subscriptions
    try {
        $objs = Get-AzSubscription -ErrorAction Stop | Where-Object {$_.State -eq "Enabled"} 
    }
    catch {
        $Errorlist.Add("Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_" )
        throw "Error: Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_"
    }

    # Fetch all compliance data using Azure Resource Graph (single efficient query)
    Write-Host "Fetching policy compliance data using Azure Resource Graph..."
    try {
        $ComplianceDataCache = Get-PolicyComplianceData -PolicyID $PolicyID -InitiativeID $InitiativeID -AllowedLocations $AllowedLocations -msgTable $msgTable
        Write-Host "Successfully retrieved compliance data for $($ComplianceDataCache.Count) subscriptions"
    }
    catch {
        $Errorlist.Add("Failed to retrieve policy compliance data using Azure Resource Graph: $_")
        Write-Warning "Failed to retrieve policy compliance data using Azure Resource Graph. Error: $_"
        # Initialize empty cache to allow processing to continue
        $ComplianceDataCache = @{}
    }

    try {
        $ErrorActionPreference = 'Stop'
        $type = "subscription"
        if ($EnableMultiCloudProfiles) {
            $ObjectList+=Check-PolicyStatus -AllowedLocations $AllowedLocations -objList $objs -objType $type -PolicyID $PolicyID -InitiativeID $InitiativeID -itsgcode $itsgcode -ReportTime $ReportTime -ItemName $ItemName -msgTable $msgTable -ControlName $ControlName -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -EnableMultiCloudProfiles -ComplianceDataCache $ComplianceDataCache
        } else {
            $ObjectList+=Check-PolicyStatus -AllowedLocations $AllowedLocations -objList $objs -objType $type -PolicyID $PolicyID -InitiativeID $InitiativeID -itsgcode $itsgcode -ReportTime $ReportTime -ItemName $ItemName -msgTable $msgTable -ControlName $ControlName -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -ComplianceDataCache $ComplianceDataCache
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
