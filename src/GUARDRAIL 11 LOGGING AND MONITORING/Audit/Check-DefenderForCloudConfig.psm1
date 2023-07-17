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
        $CBSSubscriptionName
    )
    [PSCustomObject] $FinalObjectList = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    # Defender for cloud detection.
    #
    $IsCompliant=$false
    
    $Comments=""
    $sublist=Get-AzSubscription -ErrorAction SilentlyContinue| Where-Object {$_.State -eq 'Enabled' -and $_.Name -ne $CBSSubscriptionName} 
    
    # This will look for specific Defender for Cloud, on a per subscription basis.
    $nonCompliantSubs=0
    foreach ($sub in $sublist)
    {
        Select-AzSubscription -SubscriptionObject $sub | Out-Null
        $ContactInfo=Get-AzSecurityContact
        if ([string]::IsNullOrEmpty($ContactInfo.Email) -or [string]::IsNullOrEmpty($null -eq $ContactInfo.Phone))
        {
            $nonCompliantSubs++
            $Comments+= $msgTable.noSecurityContactInfo -f $sub.Name
        }
        # We need to exlude 
        # - CloudPosture since this plan is always shows as Free
        # - KubernetesService and ContainerRegistry because two plans are deprecated in favor of the Container plan.

        # check that ALL Defender pricing tier is not set to Free
        $defenderPlans = Get-AzSecurityPricing -ErrorAction Stop | Where-Object {$_.Name -notin 'CloudPosture', 'KubernetesService', 'ContainerRegistry'}

        if ($defenderPlans.PricingTier -contains 'Free')
        {
            $nonCompliantSubs++
            $Comments += $msgTable.notAllDfCStandard -f $sub.Name
        }
    
    }
    if ($nonCompliantSubs -eq 0)
    {
        $IsCompliant=$true
        $Comments += "All subscriptions have a security contact and Defender for Cloud is set to Standard."
    }
    else {
        $IsCompliant=$false
    }
    if ($IsCompliant)
    {
        $Comments= $msgTable.logsAndMonitoringCompliantForDefender
    }

    $object = [PSCustomObject]@{ 
        ComplianceStatus = $IsCompliant
        Comments = $Comments
        ItemName = $msgTable.defenderMonitoring
        itsgcode = $itsginfosecdefender
        ControlName = $ControlName
        ReportTime = $ReportTime
    }
    $FinalObjectList+=$object

    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $FinalObjectList 
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput
}
