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
        $EnableMultiCloudProfiles # New feature flag, default to false
    )

    $isCompliant = $false
    $Comments = ""
    $ErrorList = @()
    $subCompliance = @()

    #Get All the Subscriptions
    $subs = Get-AzSubscription -ErrorAction SilentlyContinue| Where-Object {$_.State -eq "Enabled"}

    foreach($subscription in $subs){
        $subId = $subscription.Id
        Set-AzContext -SubscriptionId $subId

        $defenderPlans = Get-AzSecurityPricing
        $defenderEnabled = $defenderPlans | Where-Object {$_.PricingTier -eq 'Standard'} #A paid plan should exist on the sub resource

        if(-not $defenderEnabled){
            $Comments += $msgTable.NotAllSubsHaveDefenderPlans -f $subscription
            break
        }

        $azContext = Get-AzContext
        $token = Get-AzAccessToken -TenantId $azContext.Subscription.TenantId 
        
        $authHeader = @{
            'Content-Type'  = 'application/json'
            'Authorization' = 'Bearer ' + $token.Token
        }

        #Retrieve notifications for alert and attack paths
        $restUri = "https://management.azure.com/subscriptions/$($azContext.Subscription.Id)/providers/Microsoft.Security/securityContacts/default?api-version=2023-12-01-preview"

        try{
            $response = Invoke-RestMethod -Uri $restUri -Method Get -Headers $authHeader
        }
        catch{
            $Comments += $msgTable.errorRetrievingNotifications
            $ErrorList += "Error invoking $restUri for notifications for the subscription: $_"
            break
        }
        
        $notificationSources = $response.properties.notificationsSources
        $notificationEmails = $response.properties.emails
        $ownerRole = $response.properties.notificationsByRole.roles | Where-Object {$_ -eq "Owner"}
        $ownerState = $response.properties.notificationsByRole.State

        #Filter so we get required notification types
        $alertNotification = $notificationSources | Where-Object {$_.sourceType -eq "Alert" -and $_.minimalSeverity -in @("Medium","Low")}
        $attackPathNotification = $notificationSources | Where-Object {$_.sourceType -eq "AttackPath" -and $_.minimalRiskLevel -in @("Medium","Low")}

        $emailCount = ($notificationEmails -split ";").Count

        #Check theres minimum two emails and owner is also notified
        if(($emailCount -lt 2) -or ($ownerState -ne "On" -or $ownerRole -ne "Owner")){
            $Comments += $msgTable.EmailsOrOwnerNotConfigured -f $subscription
            break
        }

        if($null -eq $alertNotification){
            $Comments += $msgTable.AlertNotificationNotConfigured
            break
        }

        if($null -eq $attackPathNotification){
            $Comments += $msgTable.AttackPathNotifictionNotConfigured
            break
        }

        #If it reaches here, then subscription is compliant
        $subCompliance += $true
    }
    
    #Check if all subscriptions are compliant
    if ($subCompliance -notcontains $false -and $null -ne $subCompliance -and $subCompliance.Count -eq $subs.Count){
        $isCompliant = $true
        $Comments += $msgTable.DefenderCompliant
    }

    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $isCompliant
        ControlName = $ControlName
        Comments = $Comments
        ItemName = $ItemName
        ReportTime = $ReportTime
        itsgcode = $itsgcode
    }

    # Conditionally add the Profile field based on the feature flag
    if ($EnableMultiCloudProfiles) {
        $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        if (!$evalResult.ShouldEvaluate) {
            if ($evalResult.Profile -gt 0) {
                $PsObject.ComplianceStatus = "Not Applicable"
                $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                $PsObject.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
            } else {
                $ErrorList.Add("Error occurred while evaluating profile configuration")
            }
        } else {
            
            $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
        }
    }
    
    $moduleOutput = [PSCustomObject]@{
        ComplianceResults = $PsObject
        Errors = $ErrorList
    }

    return $moduleOutput
}
