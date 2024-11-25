#Future Params:
#Security

function Get-DefenderForCloudConfig {
    param (
        [Parameter(Mandatory=$true)]
        [string] $ControlName,
        [string] $itsginfosecdefender,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string] $ReportTime,
        [Parameter(Mandatory=$false)]
        [string] $CBSSubscriptionName,
        [string] $CloudUsageProfiles = "3",
        [string] $ModuleProfiles,
        [switch] $EnableMultiCloudProfiles
    )

    # Initialize result collections
    $FinalObjectList = [System.Collections.ArrayList]::new()
    $ErrorList = [System.Collections.ArrayList]::new()

    # Get enabled subscriptions
    $sublist = Get-AzSubscription -ErrorAction SilentlyContinue | 
               Where-Object { $_.State -eq 'Enabled' -and $_.Name -ne $CBSSubscriptionName }

    foreach ($sub in $sublist) {
        $result = Get-SubscriptionDefenderConfig -Subscription $sub -MsgTable $msgTable
        
        if ($EnableMultiCloudProfiles) {
            Add-ProfileToResult -Result $result -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $sub.Id
        }

        $FinalObjectList.Add($result)
        $ErrorList.AddRange($result.Errors)
    }

    return [PSCustomObject]@{ 
        ComplianceResults = $FinalObjectList 
        Errors = $ErrorList
    }
}

function Get-SubscriptionDefenderConfig {
    param (
        [Parameter(Mandatory=$true)]
        $Subscription,
        [Parameter(Mandatory=$true)]
        $MsgTable
    )

    Select-AzSubscription -SubscriptionObject $Subscription | Out-Null

    $isCompliant = $true
    $comments = ""
    $errors = [System.Collections.ArrayList]::new()

    # Check security contact info
    try {
        $contactInfo = Get-SecurityContactInfo
        if ([string]::IsNullOrEmpty($contactInfo.emails) -or [string]::IsNullOrEmpty($contactInfo.phone)) {
            $isCompliant = $false
            $comments += $MsgTable.noSecurityContactInfo -f $Subscription.Name
        }
    } catch {
        $errors.Add("Error getting security contact info: $_")
    }

    # Check defender plans
    try {
        $defenderPlans = Get-AzSecurityPricing -ErrorAction Stop | 
                         Where-Object { $_.Name -notin 'CloudPosture', 'KubernetesService', 'ContainerRegistry' }
        
        if ($defenderPlans.PricingTier -contains 'Free') {
            $isCompliant = $false
            $comments += if ($comments) { " " } else { "" }
            $comments += $MsgTable.notAllDfCStandard -f $Subscription.Name
        }
    } catch {
        $errors.Add("Error checking defender plans: $_")
    }

    return [PSCustomObject]@{
        ComplianceStatus = $isCompliant
        Comments = $comments
        ItemName = $MsgTable.defenderMonitoring
        itsgcode = $itsginfosecdefender
        ControlName = $ControlName
        ReportTime = $ReportTime
        Errors = $errors
    }
}

function Get-SecurityContactInfo {
    $azContext = Get-AzContext
    $token = Get-AzAccessToken -TenantId $azContext.Subscription.TenantId 
    
    $authHeader = @{
        'Content-Type'  = 'application/json'
        'Authorization' = 'Bearer ' + $token.Token
    }
    $restUri = "https://management.azure.com/subscriptions/$($azContext.Subscription.Id)/providers/Microsoft.Security/securityContacts?api-version=2020-01-01-preview"
    $response = Invoke-RestMethod -Uri $restUri -Method Get -Headers $authHeader
    return $response.properties
}

function Add-ProfileToResult {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject] $Result,
        [string] $CloudUsageProfiles,
        [string] $ModuleProfiles,
        [string] $SubscriptionId
    )

    try {
        $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $SubscriptionId
        if (!$evalResult.ShouldEvaluate) {
            if ($evalResult.Profile -gt 0) {
                $Result.ComplianceStatus = "Not Applicable"
                $Result | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                $Result.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
            } else {
                $Result.Errors.Add("Error occurred while evaluating profile configuration")
            }
        } else {
            
            $Result | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
        }
    }
    catch {
        $Result.Errors.Add("Error getting evaluation profile: $_")
    }
}
