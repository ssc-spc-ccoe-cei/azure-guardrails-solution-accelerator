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
        [Parameter(Mandatory=$true)]
        [string]
        $CBSSubscriptionName
    )
    [PSCustomObject] $FinalObjectList = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    #$LogType="GuardrailsCompliance"
    #Code
    #
    # Defender for cloud detection.
    #
    $IsCompliant=$true
    
    $Comments=""
    $sublist=Get-AzSubscription -ErrorAction SilentlyContinue| Where-Object {$_.State -eq 'Enabled' -and $_.Name -ne $CBSSubscriptionName} 
    
    # This will look for specific Defender for Cloud, on a per subscription basis.
    foreach ($sub in $sublist)
    {
        Select-AzSubscription -SubscriptionObject $sub | Out-Null
        $ContactInfo=Get-AzSecurityContact
        if ([string]::IsNullOrEmpty($ContactInfo.Email) -or [string]::IsNullOrEmpty($null -eq $ContactInfo.Phone))
        {
            $IsCompliant=$false
            $Comments= $msgTable.noSecurityContactInfo -f $sub.Name
            # $MitigationCommands += $msgTable.setSecurityContact -f $sub.Name
        }
        
        # We need to exlude 
        # - CloudPosture since this plan is always shows as Free
        # - KubernetesService and ContainerRegistry because two plans are deprecated in favor of the Container plan.

        # check that ALL Defender pricing tier is not set to Free
        $defenderPlans = Get-AzSecurityPricing -ErrorAction Stop | Where-Object {$_.Name -notin 'CloudPosture', 'KubernetesService', 'ContainerRegistry'}

        if ($defenderPlans.PricingTier -contains 'Free')
        {
            $IsCompliant=$false
            $Comments += $msgTable.notAllDfCStandard -f $sub.Name
            # $MitigationCommands += $msgTable.setDfCToStandard -f $sub.Name
        }

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
        # MitigationCommands=$MitigationCommands
    }
    $FinalObjectList+=$object

    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $FinalObjectList 
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput
}
