function Get-SentinelInUse {
    param (
        [string]$LAWResourceId
    )

    # check that the tenant-based defender for cloud data connector for Sentinel is enabled
    $installedDefenderConnectorsForSentinel = ((Invoke-AzRestMethod -uri "https://management.azure.com/$LAWResourceId/providers/Microsoft.SecurityInsights/dataConnectors?api-version=2025-07-01-preview").Content | ConvertFrom-Json).value | Where-Object { $_.name -eq 'MicrosoftDefenderForCloudTenantBased' }

    # check that defender related incidents are being closed in Sentinel i.e. someone is monitoring / closing incidents
    $filter = "`$filter=properties/status eq 'Closed' and properties/additionalData/alertProductNames/any(apn: apn eq 'Azure Security Center')"
    $orderby = "`$orderby=properties/createdTimeUtc desc"
    $top = "`$top=1"
    $lastClosedDefenderIncident = ((Invoke-AzRestMethod -uri "https://management.azure.com/$LAWResourceId/providers/Microsoft.SecurityInsights/incidents?api-version=2025-06-01&$filter&$orderby&$top").Content | ConvertFrom-Json).value 

    return ($installedDefenderConnectorsForSentinel.count -gt 0) -and ($lastClosedDefenderIncident.properties.createdTimeUtc -gt (Get-Date).AddDays(-30))
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
        [string]$LAWResourceId,
        [string]$ReportTime,
        [string]$CloudUsageProfiles = "3",  # Passed as a string
        [string]$ModuleProfiles,  # Passed as a string
        [switch]$EnableMultiCloudProfiles # default is false
    )

    [PSCustomObject] $PsObject = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList

    # Get All the Subscriptions
    try {
        $tenantId = (Get-AzContext).Subscription.TenantId
        $subs = Get-AzSubscription -TenantId $tenantId -ErrorAction Stop | Where-Object {$_.State -eq "Enabled"} 
    }
    catch {
        $ErrorList.Add("Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installation of the Az.Resources module; returned error message: $_" )
        throw "Error: Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installation of the Az.Resources module; returned error message: $_"
    }

    $sentinelInUse = Get-SentinelInUse -LAWResourceId $LAWResourceId

    foreach($subscription in $subs){
        # Initialize
        $isCompliant = $true
        $Comments = ""

        # find subscription information
        $subId = $subscription.Id
        Set-AzContext -SubscriptionId $subId -TenantId $tenantId

        $defenderPlans = Get-AzSecurityPricing
        $defenderEnabled = $defenderPlans | Where-Object {$_.PricingTier -eq 'Standard'} #A paid plan should exist on the sub resource

        if(-not $defenderEnabled){
            $isCompliant = $false
            $Comments = $msgTable.NotAllSubsHaveDefenderPlans -f $subscription 
        }
        else{
            # Retrieve notifications for alert and attack paths
            $restUri = "https://management.azure.com/subscriptions/$($subId)/providers/Microsoft.Security/securityContacts/default?api-version=2023-12-01-preview"

            try{
                $response = (Invoke-AzRestMethod -Uri $restUri -Method Get).Content | ConvertFrom-Json
            }
            catch{
                $isCompliant = $false
                $Comments = $msgTable.errorRetrievingNotifications
                $ErrorList = "Error invoking $restUri for notifications for the subscription: $_"
                
            }
            
            $notificationSources = $response.properties.notificationsSources
            $notificationEmails = $response.properties.emails
            $ownerRole = $response.properties.notificationsByRole.roles | Where-Object {$_ -eq "Owner"}
            $ownerState = $response.properties.notificationsByRole.State

            # Filter to get required notification types
            $alertNotification = $notificationSources | Where-Object {$_.sourceType -eq "Alert" -and $_.minimalSeverity -in @("Medium","Low")}
            $attackPathNotification = $notificationSources | Where-Object {$_.sourceType -eq "AttackPath" -and $_.minimalRiskLevel -in @("Medium","Low")}

            $emailCount = ($notificationEmails -split ";").Count

            # CONDITION: Check if there is minimum two emails and owner is also notified
            if(($emailCount -lt 2 -and -not $sentinelInUse) -or ($ownerState -ne "On" -or $ownerRole -ne "Owner")){
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

        }

        # If it reaches here, then this subscription is compliant
        if ($isCompliant){
            $Comments = $msgTable.DefenderCompliant
        }

        $C = [PSCustomObject]@{
            SubscriptionName = $subscription.Name
            ComplianceStatus = $isCompliant
            ControlName = $ControlName
            Comments = $Comments
            ItemName = $ItemName
            ReportTime = $ReportTime
            itsgcode = $itsgcode
        }
        
        # Add profile information if MCUP feature is enabled
        $result = Add-ProfileInformation -Result $C -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId -ErrorList $ErrorList
        Write-Host "$result"

        $PsObject.add($result) | Out-Null
        
    }
    
    $moduleOutput = [PSCustomObject]@{
        ComplianceResults = $PsObject
        Errors = $ErrorList
    }

    return $moduleOutput
}
