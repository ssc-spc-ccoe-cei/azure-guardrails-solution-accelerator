function Check-CBSSensors {
    param (
        [string] $SubscriptionName , [string] $TenantID , [string] $ControlName, `
        [string] $WorkSpaceID, [string] $workspaceKey, [string] $LogType,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime
    )

    $IsCompliant = $true 
    [string] $Comment1 = "CBS Subscription doesnt exist"
    [string] $Comment2 = "The expected CBC sensors do not exist"
    $SubsFound=""
    $Object = New-Object PSObject

    $Object | Add-Member -MemberType NoteProperty -Name ControlName  -Value $ControlName

    $FirstTokenInTenantID = $TenantID.Split("-")[0]

    [string]$CBSFunctionName = "cbs-" + $FirstTokenInTenantID 
    [string]$CBSCCEventHubsNameSpace = "cbs-" + $FirstTokenInTenantID + "-CanadaCentral"
    [string]$CBSCEEventHubsNameSpace = "cbs-" + $FirstTokenInTenantID + "-CanadaEast"
    [string]$CBSKeyVaultName = "cbs-vault-" + $FirstTokenInTenantID
    [string]$CBSStorageAccountName = $FirstTokenInTenantID
    [string]$CBSAppServicePlanName = "CbsSitePlan"
    $subs=Get-AzSubscription | Where-Object {$_.State -eq 'Enabled'}
    if ($null -ne $subs)
    {
        foreach ($sub in $subs)
        {
            Set-AzContext -Subscription $sub

            $CBSFunctionNameRS = Get-AzResource -Name $CBSFunctionName
            $CBSCCEventHubsNameSpaceRS = Get-AzResource -Name $CBSCCEventHubsNameSpace
            $CBSCEEventHubsNameSpaceRS = Get-AzResource -Name $CBSCEEventHubsNameSpace
            $CBSKeyVaultNameRS = Get-AzResource -Name $CBSKeyVaultName
            $CBSStorageAccountNameRS = Get-AzResource -Name $CBSStorageAccountName
            $CBSAppServicePlanNameRS = Get-Azresource -Name $CBSAppServicePlanName
            if ((-$null -eq $CBSFunctionNameRS) -or (-$null -eq $CBSCCEventHubsNameSpaceRS) -or `
                (-$null -eq $CBSCEEventHubsNameSpaceRS) -or (-$null -eq $CBSKeyVaultNameRS) -or `
                (-$null -eq $CBSStorageAccountNameRS) -or (-$null -eq $CBSAppServicePlanNameRS)) {
                $IsCompliant = $false 
                $Object | Add-Member -MemberType NoteProperty -Name Comments -Value $Comment2
            }
            else {
                $SubsFound+="$($sub.Name);"
            }
        }
    }
    else {
        $IsCompliant = $false
        $Object | Add-Member -MemberType NoteProperty -Name Comments -Value $Comment1
    }
    if ($IsCompliant)
    {
        $object | Add-Member -MemberType NoteProperty -Name ComplianceStatus -Value $IsCompliant
        $object | Add-Member -MemberType NoteProperty -Name Comments -Value "Found resources in these subscriptions: $SubsFound"
    }
    $object | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime
    $JsonObject = convertTo-Json -inputObject $Object     
    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
        -sharedkey $workspaceKey `
        -body $JsonObject `
        -logType $LogType `
        -TimeStampField Get-Date          
}

