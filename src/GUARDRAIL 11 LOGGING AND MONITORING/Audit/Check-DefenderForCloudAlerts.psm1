
function Get-SecurityResources{
    param (
        [AllowEmptyCollection()]
        [System.Collections.ArrayList]$ErrorList
    )

    [PSCustomObject] $queryResults = New-Object System.Collections.ArrayList

    $query = @"
securityresources
| where type =~ 'microsoft.security/pricings'
| project subscriptionId,
plan = name,
tier = tostring(properties.pricingTier)
| distinct subscriptionId, tier, plan
| join kind=inner (
ResourceContainers
| where type =~ 'microsoft.resources/subscriptions'
| project subscriptionId, subscriptionName = name, state = properties.state
| where state == 'Enabled'
) on subscriptionId
| project subscriptionName, plan, tier, subscriptionId
| order by subscriptionName asc
"@

    try{

        Write-Verbose "Executing Azure Resource Graph query for retrieving security resources for defender for cloud plan"
        $cache = @{}
        $skipToken = $null
        $pageCount = 0

        do {
            $pageCount++
            if ($skipToken) {
                $results = Search-AzGraph -Query $query -UseTenantScope -First 1000 -SkipToken $skipToken
            } 
            else {
                $results = Search-AzGraph -Query $query -UseTenantScope -First 1000
            }

            # Process results from this page
            foreach ($result in $results) {
                $page = [PSCustomObject]@{
                    subscriptionName = $result.subscriptionName
                    plan = $result.plan
                    tier = $result.tier
                    subscriptionId = $result.subscriptionId
                }
                $queryResults += $page

            }
            # Get SkipToken for next page (if any)
            $skipToken = $results.SkipToken
            Write-Verbose "ARG query page $pageCount returned $($queryResults.Count) subscription(s), SkipToken: $($null -ne $skipToken)"
            
        } while ($skipToken)

        Write-Verbose "ARG query completed - total subscriptions cached: $($cache.Count)"
        return $queryResults
        
    }
    catch {
        Write-Verbose "ARG query failed: $_"
        $Errorlist.Add("ARG query failed: $_")
        return @()
    }

}


function Get-DFCAcheckComplaicneStatus{
    param(
        [Parameter (Mandatory)] 
        [pscustomobject] $apiResponse
    )

    # Initialize
    $isCompliant = $true
    $Comments = ""

    $notificationSources = $apiResponse.properties.notificationsSources
    $notificationEmails = $apiResponse.properties.emails
    $ownerRole = $apiResponse.properties.notificationsByRole.roles | Where-Object {$_ -eq "Owner"}
    $ownerState = $apiResponse.properties.notificationsByRole.State

    # Filter to get required notification types
    $alertNotification = $notificationSources | Where-Object {$_.sourceType -eq "Alert" -and $_.minimalSeverity -in @("Medium","Low")}
    $attackPathNotification = $notificationSources | Where-Object {$_.sourceType -eq "AttackPath" -and $_.minimalRiskLevel -in @("Medium","Low")}

    $emailCount = ($notificationEmails -split ";").Count

    # CONDITION: Check if there is minimum two emails and owner is also notified
    if(($emailCount -lt 2) -or ($ownerState -ne "On" -or $ownerRole -ne "Owner")){
        $isCompliant = $false
        $Comments = $msgTable.EmailsOrOwnerNotConfigured -f $($subscription.Name)
    }

    if($null -eq $alertNotification){
        $isCompliant = $false
        $Comments = $msgTable.AlertNotificationNotConfigured
        
    }

    if($null -eq $attackPathNotification){
        $isCompliant = $false
        $Comments = $msgTable.AttackPathNotificationNotConfigured
        
    }
    #If it reaches here, then this subscription is compliant
    if ($isCompliant){
        $Comments = $msgTable.DefenderCompliant
    }

    return [PSCustomObject]@{
        Comments = $Comments 
        isCompliant = $isCompliant
    }
}


function Get-DefenderForCloudAlerts {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ControlName,
        [Parameter(Mandatory=$true)]
        [string]$ItemName,
        [Parameter(Mandatory=$true)]
        [string]$itsgcode,
        [Parameter(Mandatory=$true)]
        [hashtable]$msgTable,
        [Parameter(Mandatory=$true)]
        [string]$ReportTime,
        [string] 
        $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] 
        $EnableMultiCloudProfiles # default is false
    )

    [PSCustomObject] $PsObject = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList

    try {
        $subs = Get-AzSubscription -ErrorAction Stop | Where-Object {$_.State -eq "Enabled"} 
    }
    catch {
        $Errorlist.Add("Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_" )
        throw "Error: Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_"
    }
    
    # Fetch security resources data for defender for cloud plan using ARG on All the Subscriptions in the tenant scope
    try{
        $defenderPlans = Get-SecurityResources -ErrorList $ErrorList
    }
    catch{
        Write-Verbose "ARG query failed: $_"
        $defenderPlans = @{}
    }

    # USE CASE: Subs with no defender plans
    $defenderPlanSubs = $defenderPlans | Select-Object -ExpandProperty subscriptionId
    $noDefenderPlanSubs = $subs | Where-Object {$_.SubscriptionId -notin $defenderPlanSubs}
    $noDefenderPlanSubIds = $noDefenderPlanSubs | Select-Object -ExpandProperty subscriptionId
    
    if($null -eq $defenderPlans){
        # USE CASE: No subscriptions has the security resources data i.e. defender plan is not enabled for any sub
        $isCompliant = $false
        $Comments = $msgTable.noDefenderAtAll
    }
    else{
        # Get the subscription with paid defender plan
        $defenderStandardTier = $defenderPlans | Where-Object {$_.tier -eq 'Standard'} # A paid plan should exist on the sub resources
        if ($defenderStandardTier.Count -gt 0) {
            Write-Verbose "Successfully fetched the resource data for the standard tier subscriptions."
        } else {
            # Evaluation logic for this Use case (defenderNonStandardTier) will be evaluated in the later section
            Write-Verbose "No resource data found for standard tier defender subscription."
        }

        # A paid plan exists on the sub resources 
        $defenderStandard = $defenderStandardTier | Select-Object * -ExcludeProperty plan | Sort-Object * -Unique

        # Subscription with free plan on the sub resources
        $defenderNonStandardTier = $defenderPlans | Where-Object {$_.tier -ne 'Standard'} 
        
        # Filter out subscriptions from defenderNonStandardTier that already registered in the standard (paid) tier plan
        $subsToExcl = $defenderStandard | Select-Object -ExpandProperty subscriptionId
        $defenderNonStandardTierFiltered = $defenderNonStandardTier | Where-Object {$_.subscriptionId -notin $subsToExcl}

        if($defenderNonStandardTierFiltered.count -ne 0){
            # Use case: these subscriptions enabled either Foundational CSPM only
            Write-Verbose "No action needed at this step with the subs that enabled Foundational CSPM only."

        }
        elseif($defenderNonStandardTierFiltered.count -eq 0){
            Write-Verbose "All subscriptions have enabled defender plan and that a paid plan exists on the sub resources of all these subs"

            # USE CASE: Get compliant status for Subs
            foreach($subscription in $subs){
                
                # find subscription information
                $subId = $subscription.Id
                $subscriptionName = $subscription.Name
                Write-Verbose "Subscription: $($subscriptionName)"

                # Evaluation logic for subs with no defender plan will be evaluated in the later foreach section
                if($noDefenderPlanSubIds -contains $subId){
                    Write-Host "Compliance for subscription $($subscriptionName) will be evaluated in later section"
                    continue
                }

                # Initialize
                $isCompliant = $true
                $Comments = ""
                Set-AzContext -SubscriptionId $subId

                # Create auth
                $azContext = Get-AzContext
                $token = Get-AzAccessToken -TenantId $azContext.Subscription.TenantId 
                
                $authHeader = @{
                    'Content-Type'  = 'application/json'
                    'Authorization' = 'Bearer ' + $token.Token
                }

                # Retrieve notifications for alert and attack paths
                $restUri = "https://management.azure.com/subscriptions/$($azContext.Subscription.Id)/providers/Microsoft.Security/securityContacts/default?api-version=2023-12-01-preview"
                try{
                    $response = Invoke-RestMethod -Uri $restUri -Method Get -Headers $authHeader
                    $result = Get-DFCAcheckComplaicneStatus -apiResponse $response
                    $isCompliant = $result.isCompliant
                    $Comments = $result.Comments
                }
                catch{
                    $restUri2 = "https://management.azure.com/subscriptions/$($azContext.Subscription.Id)/providers/Microsoft.Security/securityContacts?api-version=2023-12-01-preview"
                    try{
                        $response2 = Invoke-RestMethod -Uri $restUri2 -Method Get -Headers $authHeader
                        if (-not ($response2.value) -or $response2.value.Count -eq 0){
                            $isCompliant = $false
                            $Comments = $msgTable.DefenderNonCompliant
                            Write-Verbose "Notification alert default security contact is not configured properly"

                        }
                        else{
                            # use case:
                            Write-Verbose "Find use case"

                        }

                    }
                    catch{
                        $isCompliant = $false
                        $Comments = $msgTable.errorRetrievingNotifications
                        $ErrorList = "Error invoking $restUri for notifications for the subscription: $_"
                    }
                }

                $C = [PSCustomObject]@{
                    SubscriptionName = $subscriptionName
                    ComplianceStatus = $isCompliant
                    ControlName = $ControlName
                    Comments = $Comments
                    ItemName = $ItemName
                    ReportTime = $ReportTime
                    itsgcode = $itsgcode
                }
                
                # Add profile information if MCUP feature is enabled
                if($EnableMultiCloudProfiles){
                    $result = Add-ProfileInformation -Result $C -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subId -ErrorList $ErrorList
                    Write-Host "$result"
                    $PsObject.add($result) | Out-Null
                } else {
                    $PsObject.add($C) | Out-Null
                }
            }
            
        }
        


        ## ****** USE CASE: Subs with no defender plans **********

        # compliant output for the subs with no defender plan
        foreach($sub in  $noDefenderPlanSubs){ 
            # Initialize to false as they would be nonCompliant
            $isCompliant = $false
            $Comments = ""

            # find subscription information
            $subId = $sub.Id
            Set-AzContext -SubscriptionId $subId
            Write-Host "Subscription: $($sub.Name)"

            $Comments = $msgTable.NotAllSubsHaveDefenderPlans -f $sub.Name 

            $C = [PSCustomObject]@{
                SubscriptionName = $sub.Name
                ComplianceStatus = $isCompliant
                ControlName = $ControlName
                Comments = $Comments
                ItemName = $ItemName
                ReportTime = $ReportTime
                itsgcode = $itsgcode
            }
            
            # Add profile information if MCUP feature is enabled
            if($EnableMultiCloudProfiles){
                $result = Add-ProfileInformation -Result $C -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subId -ErrorList $ErrorList
                Write-Host "$result"
                $PsObject.add($result) | Out-Null
            } else {
                $PsObject.add($C) | Out-Null
            }
        }
    }
    
    $moduleOutput = [PSCustomObject]@{
        ComplianceResults = $PsObject
        Errors = $ErrorList
    }

    return $moduleOutput
}
