#Future Params:
#Security

function Get-DefenderForCloudConfig {
    param (
         [Parameter(Mandatory=$true)]
        [string]
        $ControlName,
        [string] $itsginfosecdefender,
        [hashtable]
        $msgTable,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime,
        [Parameter(Mandatory=$false)]
        [string]
        $CBSSubscriptionName,
        [string] 
        $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] $EnableMultiCloudProfiles # New feature flag, default to false    
    )
    [PSCustomObject] $FinalObjectList = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    # Defender for cloud detection.
    #
    $IsCompliant=$true
    
    $Comments=""
    $sublist=Get-AzSubscription -ErrorAction SilentlyContinue| Where-Object {$_.State -eq 'Enabled' -and $_.Name -ne $CBSSubscriptionName}
    
    # This will look for specific Defender for Cloud, on a per subscription basis.
    foreach ($sub in $sublist)
    {
        Select-AzSubscription -SubscriptionObject $sub | Out-Null

        try{
            $azContext = Get-AzContext
            $token = Get-AzAccessToken -TenantId $azContext.Subscription.TenantId
            $authHeader = @{
                'Content-Type'  = 'application/json'
                'Authorization' = 'Bearer ' + $token.Token
            }
            $restUri = "https://management.azure.com/subscriptions/$($azContext.Subscription.Id)/providers/Microsoft.Security/securityContacts?api-version=2020-01-01-preview"
            $response = Invoke-RestMethod -Uri $restUri -Method Get -Headers $authHeader
            $ContactInfo  = $response.properties
            # This line will be used for debugging
            Write-Host "contactInfo $ContactInfo"
        }catch {
            $errorMsg = "Error in response: $_"
            $ErrorList.Add($errorMsg)
        }

        if ([string]::IsNullOrEmpty($ContactInfo.emails) -or [string]::IsNullOrEmpty($null -eq $ContactInfo.phone))
        {
            $IsCompliant=$false
            $Comments+= $msgTable.noSecurityContactInfo -f $sub.Name
        }
        # We need to exlude 
        # - CloudPosture since this plan is always shows as Free
        # - KubernetesService and ContainerRegistry because two plans are deprecated in favor of the Container plan.

        # check that ALL Defender pricing tier is not set to Free
        $defenderPlans = Get-AzSecurityPricing -ErrorAction Stop | Where-Object {$_.Name -notin 'CloudPosture', 'KubernetesService', 'ContainerRegistry'}

        if ($defenderPlans.PricingTier -contains 'Free')
        {
            $IsCompliant=$false
            if ($Comments -eq ""){
                $Comments += $msgTable.notAllDfCStandard -f $sub.Name
            }
            else{
                $Comments += " " + $msgTable.notAllDfCStandard -f $sub.Name
            }            
        }

        $object = [PSCustomObject]@{ 
            ComplianceStatus = $IsCompliant
            Comments = $Comments
            ItemName = $msgTable.defenderMonitoring
            itsgcode = $itsginfosecdefender
            ControlName = $ControlName
            ReportTime = $ReportTime
        }

        if ($EnableMultiCloudProfiles) {        
            $result = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $sub.Id
            if ($result -is [int]) {
                Write-Output "Valid profile returned: $result"
                $object | Add-Member -MemberType NoteProperty -Name "Profile" -Value $result
            } elseif ($result.Status -eq "Error") {
                Write-Error "Error occurred: $($result.Message)"
                $c.ComplianceStatus = "Not Applicable"
                Errorlist.Add($result.Message)
            } else {
                Write-Error "Unexpected result: $result"
                continue
            }
        }
        $FinalObjectList+=$object        
    }

    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $FinalObjectList 
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput
}
