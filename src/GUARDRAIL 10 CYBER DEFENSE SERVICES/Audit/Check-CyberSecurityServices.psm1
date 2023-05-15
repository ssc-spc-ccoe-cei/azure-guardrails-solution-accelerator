function Check-CBSSensors {
    param (
        [string] $SubscriptionName , 
        [string] $TenantID , 
        [string] $ControlName, `
        [string] $ItemName,  
        [string] $itsgcode,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime
    ) 

    $IsCompliant = $true 
    $Object = New-Object PSObject

    $Object | Add-Member -MemberType NoteProperty -Name ControlName  -Value $ControlName

    $FirstTokenInTenantID = $TenantID.Split("-")[0]

    $CBSResourceNames=@("cbs-" + $FirstTokenInTenantID)
    $CBSResourceNames+="cbs-" + $FirstTokenInTenantID + "-CanadaCentral"
    $CBSResourceNames+="cbs-" + $FirstTokenInTenantID + "-CanadaEast"
    $CBSResourceNames+="cbs-vault-" + $FirstTokenInTenantID
    
    if ($debug) { Write-Output $CBSResourceNames}
    $sub=Get-AzSubscription -ErrorAction SilentlyContinue | Where-Object {$_.State -eq 'Enabled' -and $_.Name -eq $SubscriptionName}
    if ($null -ne $sub)
    {
        Set-AzContext -Subscription $sub

        foreach ($CBSResourceName in $CBSResourceNames)
        {
            if ($debug) { Write-output "Searching for CBS Sensor: $CBSResourceName"}
            if ([string]::IsNullOrEmpty($(Get-AzResource -Name $CBSResourceName)))
            {
                if ($debug) {Write-Output "Missing $CBSResourceName"}
                $IsCompliant = $false 
            }
        }
        if ($IsCompliant)
        {
            $object | Add-Member -MemberType NoteProperty -Name Comments -Value "$($msgTable.cbssCompliant) $SubscriptionName)"| Out-Null
            $MitigationCommands = "N/A."
        }
        else {
            $Object | Add-Member -MemberType NoteProperty -Name Comments -Value $Comment2 | Out-Null   
            $MitigationCommands = "Contact CBS to deploy sensors."
        }
    }
    else {
        $IsCompliant = $false
        $Object | Add-Member -MemberType NoteProperty -Name Comments -Value $msgTable.cbsSubDoesntExist
        $MitigationCommands = "$($msgTable.cbssMitigation)" -f $SubscriptionName
    }
    $object | Add-Member -MemberType NoteProperty  -Name ReportTime -Value $ReportTime | Out-Null
    $object | Add-Member -MemberType NoteProperty -Name ComplianceStatus -Value $IsCompliant| Out-Null
    $object | Add-Member -MemberType NoteProperty -Name MitigationCommands -Value $MitigationCommands| Out-Null
    $object | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName| Out-Null
    $object | Add-Member -MemberType NoteProperty -Name itsgcode -Value $itsgcode| Out-Null
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $Object 
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput
}

