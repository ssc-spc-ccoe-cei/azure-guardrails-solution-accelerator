#Future Params:
#Security
function get-apiLinkedServicesData {
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $subscriptionId,
        [Parameter(Mandatory=$true)]
        [string]
        $resourceGroup,
        [Parameter(Mandatory=$true)]
        [string]
        $LAWName
    )
    $token=(Get-AzAccessToken).Token
    $apiUrl="https://management.azure.com/subscriptions/$subscriptionId/resourcegroups/$resourceGroup/providers/Microsoft.OperationalInsights/workspaces/$LAWName/linkedServices?api-version=2020-08-01"
    try {
        $Data = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)"} -Uri $apiUrl -Method Get
    }
    catch {
        Add-LogEntry 'Error' "Failed to call Azure Resource Manager REST API at URL '$apiURL'; returned error message: $_" -workspaceGuid $WorkSpaceID -workspaceKey $WorkSpaceKey
        Write-Error "Error: Failed to call Azure Resource Manager REST API at URL '$apiURL'; returned error message: $_"
    }
    return $Data
}

function get-activitylogstatus {
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $LAWResourceId
    )
    $subs=get-azsubscription
    $totalsubs=$subs.Count
    $GraphAccessToken = (Get-AzAccessToken).Token
    $pcount=0
    foreach ($sub in $subs) {
        $URL="https://management.azure.com/subscriptions/$($sub.Id)/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview"
        $configuredWSs=(Invoke-RestMethod -Headers @{Authorization = "Bearer $($GraphAccessToken)" } -Uri $URL -Method Get ).value.Properties.workspaceId
        if ($LAWResourceId -in $configuredWSs) {
            $pcount++
        }
    }
    if ($pcount -ne $totalsubs) {
        Write-Warning "Not all subscriptions are configured to send logs to the Log Analytics Workspace"
        return $false
    }
    else {
        Write-Host "All subscriptions are configured to send logs to the Log Analytics Workspace"
        return $true
    }
}
function get-tenantDiagnosticsSettings {
    #AadGraph, AnalysisServices, Arm, Attestation, Batch, DataLake, KeyVault, MSGraph, OperationalInsights, ResourceManager, Storage, Synapse
    $token=(Get-AzAccessToken -ResourceTypeName Arm).Token

    #$apiUrl="https://graph.microsoft.com/beta/auditLogs/directoryAudits"
    $apiUrl = "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01-preview"
    try {
        $Data = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)"} -Uri $apiUrl -Method Get
    }
    catch {
        Add-LogEntry 'Error' "Failed to call Azure Resource Manager REST API at URL '$apiURL'; returned error message: $_" -workspaceGuid $WorkSpaceID -workspaceKey $WorkSpaceKey
        Write-Error "Error: Failed to call Azure Resource Manager REST API at URL '$apiURL'; returned error message: $_"
    }

    return $data.value.properties
}
function Check-LoggingAndMonitoring {
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $SecurityLAWResourceId,
        [Parameter(Mandatory=$true)]
        [string]
        $HealthLAWResourceId,
        [Parameter(Mandatory=$true)]
        [string]
        $ControlName,
        [Parameter(Mandatory=$true)]
        [string]
        $WorkSpaceID,
        [Parameter(Mandatory=$true)]
        [string]
        $workspaceKey,
        [Parameter(Mandatory=$true)]
        [string]
        $LogType,
        [string] $itsginfosecmon,
        [string] $itsginfohealthmon,
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

    #$LogType="GuardrailsCompliance"
    #Code

    #Add test for proper right format of the LAW parameters
    $Subscription=$SecurityLAWResourceId.Split("/")[2]
    $LAWRG=$SecurityLAWResourceId.Split("/")[4]
    $LAWName=$SecurityLAWResourceId.Split("/")[8]
    $HealthLAWRG=$HealthLAWResourceId.Split("/")[4]
    $HealthLAWName=$HealthLAWResourceId.Split("/")[8]
    
    $IsCompliant=$true
    $MitigationCommands=""

    try{
        Select-AzSubscription -Subscription $Subscription -ErrorAction Stop
    }
    catch {
        Add-LogEntry 'Error' "Failed to execute the 'Select-AzSubscription' command with subscription ID '$($subscription)'--`
            ensure you have permissions to the subscription, the ID is correct, and that it exists in this tenant; returned `
            error message: $_" -workspaceGuid $WorkSpaceID -workspaceKey $WorkSpaceKey
        throw "Error: Failed to execute the 'Select-AzSubscription' command with subscription ID '$($subscription)'--ensure `
            you have permissions to the subscription, the ID is correct, and that it exists in this tenant; returned error message: $_"
    }

    try {
        $LAW=Get-AzOperationalInsightsWorkspace -Name $LAWName -ResourceGroupName $LAWRG -ErrorAction Stop
    }
    catch {
        Add-LogEntry 'Error' "Failed to retrieve Log Analytics workspace '$LAWName' from resource group '$LAWRG'--verify that the `
            workspace exists and that permissions are sufficient; returned error message: $_" -workspaceGuid $WorkSpaceID -workspaceKey $WorkSpaceKey
    }
    if ($null -eq $LAW)
    {
        $IsCompliant=$false
        $Comments=$msgTable.securityLAWNotFound
        $MitigationCommands = $msgTable.createLAW
    }
    else {
        # Test linked automation account
        $LinkedServices=get-apiLinkedServicesData -subscriptionId $Subscription `
            -resourceGroup $LAWRG `
            -LAWName $LAWName
        if (($LinkedServices.value.properties.resourceId | Where-Object {$_ -match "automationAccounts"}).count -lt 1)
        {
            $IsCompliant=$false
            $Comments+=$msgTable.lawNoAutoAcct #"No linked automation account has been found."
            $MitigationCommands+=@"
$($msgTable.connectAutoAcct) ($LAWName).
https://docs.microsoft.com/en-us/azure/automation/quickstarts/create-account-portal
https://docs.microsoft.com/en-us/azure/automation/how-to/region-mappings
`n
"@
        }
        #Test Retention Days
        $Retention=$LAW.retentionInDays
        if ($Retention -ne 730)
        {
            $IsCompliant=$false
            $Comments+=$msgTable.lawRetention730Days
            $MitigationCommands += "$($msgTable.setRetention730Days) ($LAWName) -https://docs.microsoft.com/en-us/azure/azure-monitor/logs/data-retention-archive?tabs=api-1%2Capi-2 `n"
        }
        #Verify presense of the Activity Logs as a source
        #Verify presense of the Activity Logs as a source
        #old way:
        #$ActivityLogDS=Get-AzOperationalInsightsDataSource -Workspace $LAW -Kind AzureActivityLog
        #If ($ActivityLogDS -eq $null)
        #{
        #    $IsCompliant=$false
        #    $Comments+=$msgTable.lawNoActivityLogs
        #    $MitigationCommands+="$($msgTable.addActivityLogs) ($LAWName) - https://docs.microsoft.com/en-us/azure/active-directory/reports-monitoring/howto-analyze-activity-logs-log-analytics  `n"
        #}
        #New way:
        if (!(get-activitylogstatus -LAWResourceId $LAW.ResourceId)) {
            $IsCompliant=$false
            $Comments+=$msgTable.lawNoActivityLogs
            $MitigationCommands+="$($msgTable.addActivityLogs) ($LAWName) - https://docs.microsoft.com/en-us/azure/active-directory/reports-monitoring/howto-analyze-activity-logs-log-analytics  `n"    
        }
        # Tests for required Solutions
        $enabledSolutions=(Get-AzOperationalInsightsIntelligencePack -ResourceGroupName $LAW.ResourceGroupName -WorkspaceName $LAW.Name| Where-Object {$_.Enabled -eq "True"}).Name
        if ($enabledSolutions -notcontains "Updates" -or $enabledSolutions -notcontains "AntiMalware")
        {
            $IsCompliant=$false
            $Comments+=$msgTable.lawSolutionNotFound # "Required solutions not present in the Log Analytics Workspace."
            $MitigationCommands+=@"
$($msgTable.addUpdatesAndAntiMalware) ($LAWName)"
https://docs.microsoft.com/en-us/azure/automation/update-management/overview
https://azuremarketplace.microsoft.com/en-us/marketplace/apps/Microsoft.AntiMalwareOMS?tab=Overview
`n
"@
        }
        # Tenant Diagnostics configuration. Needs Graph API...
        $tenantWS=get-tenantDiagnosticsSettings
        if ($SecurityLAWResourceId -notin $tenantWS.workspaceId)
        {
            $IsCompliant=$false
            $Comments+=$msgTable.lawNoTenantDiag # "Tenant Diagnostics settings are not pointing to the provided log analysitcs workspace."
            $MitigationCommands+="$($msgTable.configTenantDiag) ($LAWName) https://docs.microsoft.com/en-us/azure/active-directory/reports-monitoring/howto-integrate-activity-logs-with-log-analytics#send-logs-to-azure-monitor  `n"
        }
        else {
            #Workspace is there but need to check if logs are enabled.
            $enabledLogs=(($tenantWS| ? {$_.workspaceId -eq $SecurityLAWResourceId}).logs | ? {$_.enabled -eq $true}).category
            if ("AuditLogs" -notin $enabledLogs -or "SignInLogs" -notin $enabledLogs)
            {
                $IsCompliant=$false
                $Comments+=$msgTable.lawMissingLogTypes # "Workspace set in tenant config but not all required log types are enabled (Audit and signin)."
                $MitigationCommands+="$($msgTable.addAuditAndSignInsLogs) ($LAWName) - https://docs.microsoft.com/en-us/azure/active-directory/reports-monitoring/howto-integrate-activity-logs-with-log-analytics#send-logs-to-azure-monitor `n"
            }
        }
        #Blueprint redirection
        # Sentinel, not sure how to detect this.
        if ($IsCompliant)
        {
            $Comments= $msgTable.logsAndMonitoringCompliantForSecurity
            $MitigationCommands+="N/A"
        }
        $object = [PSCustomObject]@{ 
            ComplianceStatus = $IsCompliant
            Comments = $Comments
            ItemName = $msgTable.securityMonitoring
            itsgcode = $itsginfosecmon
            ControlName = $ControlName
            ReportTime = $ReportTime
            MitigationCommands=$MitigationCommands
        }
        $JSON= ConvertTo-Json -inputObject $object

        Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
        -sharedkey $workspaceKey `
        -body $JSON `
        -logType $LogType `
        -TimeStampField Get-Date 
        $IsCompliant=$true
    }
    #
    #Health
    #
    $MitigationCommands=""
    $IsCompliant=$true
    $Comments=""
    $HSubscription=$SecurityLAWResourceId.Split("/")[2]
    if ($Subscription -ne $HSubscription)
    {
        try{
            Select-AzSubscription -Subscription $HSubscription -ErrorAction Stop
        }
        catch {
            Add-LogEntry 'Error' "Failed to execute the 'Select-AzSubscription' command with subscription ID '$($HSubscription)'--`
                ensure you have permissions to the subscription, the ID is correct, and that it exists in this tenant; returned `
                error message: $_" -workspaceGuid $WorkSpaceID -workspaceKey $WorkSpaceKey
            throw "Error: Failed to execute the 'Select-AzSubscription' command with subscription ID '$($HSubscription)'--ensure `
                you have permissions to the subscription, the ID is correct, and that it exists in this tenant; returned error message: $_"
        }
    }
    $LAW=Get-AzOperationalInsightsWorkspace -Name $HealthLAWName -ResourceGroupName $HealthLAWRG
    if ($null -eq $LAW)
    {
        $IsCompliant=$false
        $Comments+=$msgTable.healthLAWNotFound # "The specified Log Analytics Workspace for Health monitoring has not been found."
        $MitigationCommands+= "$($msgTable.createHealthLAW) ($HealthLAWName)"
    }
    else {
        $LinkedServices=get-apiLinkedServicesData -subscriptionId $HSubscription `
        -resourceGroup $LAW.ResourceGroupName `
        -LAWName $LAW.Name
        if (($LinkedServices.value.properties.resourceId | Where-Object {$_ -match "automationAccounts"}).count -lt 1)
        {
            $IsCompliant=$false
            $Comments+=$msgTable.lawNoAutoAcct #"No linked automation account has been found."
            $MitigationCommands+=@"
$($msgTable.connectAutoAcct) ($HealthLAWName).
https://docs.microsoft.com/en-us/azure/automation/quickstarts/create-account-portal
https://docs.microsoft.com/en-us/azure/automation/how-to/region-mappings
`n
"@
        }
        $Retention=$LAW.retentionInDays
        if ($Retention -lt 90)
        {
            $IsCompliant=$false
            $Comments+=$msgTable.lawRetention90Days # "Retention not set to at least90 days."
            $MitigationCommands+= "$($msgTable.setRetention60Days) ($HealthLAWName) - https://docs.microsoft.com/en-us/azure/azure-monitor/logs/data-retention-archive?tabs=api-1%2Capi-2 `n"
        }
        #Checks required solutions
        $enabledSolutions=(Get-AzOperationalInsightsIntelligencePack -ResourceGroupName $LAW.ResourceGroupName -WorkspaceName $LAW.Name| Where-Object {$_.Enabled -eq "True"}).Name
        if ($enabledSolutions -notcontains "AgentHealthAssessment")
        {
            $IsCompliant=$false
            $Comments+=$msgTable.lawHealthNoSolutionFound # "Required solutions not present in the Health Log Analytics Workspace."
            $MitigationCommands+= "$($msgTable.enableAgentHealthSolution) ($HealthLAWName) - https://docs.microsoft.com/en-us/azure/azure-monitor/insights/solution-agenthealth `n"
        }
        #Tenant...No information on how to detect it.
        #Blueprint
    }
    if ($IsCompliant)
    {
        $Comments= $msgTable.logsAndMonitoringCompliantForHealth
        $MitigationCommands+="N/A."
    }
    $object = [PSCustomObject]@{ 
        ComplianceStatus = $IsCompliant
        Comments = $Comments
        ItemName = $msgTable.healthMonitoring
        itsgcode = $itsginfohealthmon
        ControlName = $ControlName
        ReportTime = $ReportTime  
        MitigationCommands=$MitigationCommands      
    }
    $JSON= ConvertTo-Json -inputObject $object

    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
    -sharedkey $workspaceKey `
    -body $JSON `
    -logType $LogType `
    -TimeStampField Get-Date 
   
    #
    # Defender for cloud detection.
    #
    $IsCompliant=$true
    $MitigationCommands=""
    $Comments=""
    $sublist=Get-AzSubscription | Where-Object {$_.State -eq 'Enabled' -and $_.Name -ne $CBSSubscriptionName} 
    
    # This will look for specific Defender for Cloud, on a per subscription basis.
    foreach ($sub in $sublist)
    {
        Select-AzSubscription -SubscriptionObject $sub
        $ContactInfo=Get-AzSecurityContact
        if (($null -eq $ContactInfo.Email) -or ($null -eq $ContactInfo.Phone))
        {
            $IsCompliant=$false
            $Comments= $msgTable.noSecurityContactInfo -f $sub.Name
            $MitigationCommands += $msgTable.setSecurityContact -f $sub.Name
        }
        
        # We need to exlude 
        # - CloudPosture since this plan is always shows as Free
        # - KubernetesService and ContainerRegistry because two plans are deprecated in favor of the Container plan.
        if ((Get-AzSecurityPricing | Where-Object {$_.PricingTier -eq 'Free' -and $_.Name -ne "CloudPosture" -and $_.Name -ne "KubernetesService" -and $_.Name -ne "ContainerRegistry"}).Count -gt 0)
        {
            $IsCompliant=$false
            $Comments += $msgTable.notAllDfCStandard -f $sub.Name
            $MitigationCommands += $msgTable.setDfCToStandard -f $sub.Name
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
        MitigationCommands=$MitigationCommands
    }
    $JSON = ConvertTo-Json -inputObject $object

    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
    -sharedkey $workspaceKey `
    -body $JSON `
    -logType $LogType `
    -TimeStampField Get-Date 
    $IsCompliant=$true
}

# SIG # Begin signature block
# MIInngYJKoZIhvcNAQcCoIInjzCCJ4sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDIxequP5zeq2Zk
# t90YxRm9cwx3IM8L2kLTl44NKaZX4aCCDYEwggX/MIID56ADAgECAhMzAAACzI61
# lqa90clOAAAAAALMMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjIwNTEyMjA0NjAxWhcNMjMwNTExMjA0NjAxWjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQCiTbHs68bADvNud97NzcdP0zh0mRr4VpDv68KobjQFybVAuVgiINf9aG2zQtWK
# No6+2X2Ix65KGcBXuZyEi0oBUAAGnIe5O5q/Y0Ij0WwDyMWaVad2Te4r1Eic3HWH
# UfiiNjF0ETHKg3qa7DCyUqwsR9q5SaXuHlYCwM+m59Nl3jKnYnKLLfzhl13wImV9
# DF8N76ANkRyK6BYoc9I6hHF2MCTQYWbQ4fXgzKhgzj4zeabWgfu+ZJCiFLkogvc0
# RVb0x3DtyxMbl/3e45Eu+sn/x6EVwbJZVvtQYcmdGF1yAYht+JnNmWwAxL8MgHMz
# xEcoY1Q1JtstiY3+u3ulGMvhAgMBAAGjggF+MIIBejAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUiLhHjTKWzIqVIp+sM2rOHH11rfQw
# UAYDVR0RBEkwR6RFMEMxKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMRYwFAYDVQQFEw0yMzAwMTIrNDcwNTI5MB8GA1UdIwQYMBaAFEhu
# ZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNpZ1BDQTIwMTFfMjAxMS0w
# Ny0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUFBzAChkVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0NvZFNpZ1BDQTIwMTFfMjAx
# MS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAeA8D
# sOAHS53MTIHYu8bbXrO6yQtRD6JfyMWeXaLu3Nc8PDnFc1efYq/F3MGx/aiwNbcs
# J2MU7BKNWTP5JQVBA2GNIeR3mScXqnOsv1XqXPvZeISDVWLaBQzceItdIwgo6B13
# vxlkkSYMvB0Dr3Yw7/W9U4Wk5K/RDOnIGvmKqKi3AwyxlV1mpefy729FKaWT7edB
# d3I4+hldMY8sdfDPjWRtJzjMjXZs41OUOwtHccPazjjC7KndzvZHx/0VWL8n0NT/
# 404vftnXKifMZkS4p2sB3oK+6kCcsyWsgS/3eYGw1Fe4MOnin1RhgrW1rHPODJTG
# AUOmW4wc3Q6KKr2zve7sMDZe9tfylonPwhk971rX8qGw6LkrGFv31IJeJSe/aUbG
# dUDPkbrABbVvPElgoj5eP3REqx5jdfkQw7tOdWkhn0jDUh2uQen9Atj3RkJyHuR0
# GUsJVMWFJdkIO/gFwzoOGlHNsmxvpANV86/1qgb1oZXdrURpzJp53MsDaBY/pxOc
# J0Cvg6uWs3kQWgKk5aBzvsX95BzdItHTpVMtVPW4q41XEvbFmUP1n6oL5rdNdrTM
# j/HXMRk1KCksax1Vxo3qv+13cCsZAaQNaIAvt5LvkshZkDZIP//0Hnq7NnWeYR3z
# 4oFiw9N2n3bb9baQWuWPswG0Dq9YT9kb+Cs4qIIwggd6MIIFYqADAgECAgphDpDS
# AAAAAAADMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMTAeFw0xMTA3MDgyMDU5MDlaFw0yNjA3MDgyMTA5MDla
# MH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMT
# H01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQCr8PpyEBwurdhuqoIQTTS68rZYIZ9CGypr6VpQqrgG
# OBoESbp/wwwe3TdrxhLYC/A4wpkGsMg51QEUMULTiQ15ZId+lGAkbK+eSZzpaF7S
# 35tTsgosw6/ZqSuuegmv15ZZymAaBelmdugyUiYSL+erCFDPs0S3XdjELgN1q2jz
# y23zOlyhFvRGuuA4ZKxuZDV4pqBjDy3TQJP4494HDdVceaVJKecNvqATd76UPe/7
# 4ytaEB9NViiienLgEjq3SV7Y7e1DkYPZe7J7hhvZPrGMXeiJT4Qa8qEvWeSQOy2u
# M1jFtz7+MtOzAz2xsq+SOH7SnYAs9U5WkSE1JcM5bmR/U7qcD60ZI4TL9LoDho33
# X/DQUr+MlIe8wCF0JV8YKLbMJyg4JZg5SjbPfLGSrhwjp6lm7GEfauEoSZ1fiOIl
# XdMhSz5SxLVXPyQD8NF6Wy/VI+NwXQ9RRnez+ADhvKwCgl/bwBWzvRvUVUvnOaEP
# 6SNJvBi4RHxF5MHDcnrgcuck379GmcXvwhxX24ON7E1JMKerjt/sW5+v/N2wZuLB
# l4F77dbtS+dJKacTKKanfWeA5opieF+yL4TXV5xcv3coKPHtbcMojyyPQDdPweGF
# RInECUzF1KVDL3SV9274eCBYLBNdYJWaPk8zhNqwiBfenk70lrC8RqBsmNLg1oiM
# CwIDAQABo4IB7TCCAekwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFEhuZOVQ
# BdOCqhc3NyK1bajKdQKVMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1Ud
# DwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO
# 4eqnxzHRI4k0MFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwubWljcm9zb2Z0
# LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcmwwXgYIKwYBBQUHAQEEUjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcnQwgZ8GA1UdIASBlzCBlDCBkQYJKwYBBAGCNy4DMIGDMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2RvY3MvcHJpbWFyeWNw
# cy5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AcABvAGwAaQBjAHkA
# XwBzAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAGfyhqWY
# 4FR5Gi7T2HRnIpsLlhHhY5KZQpZ90nkMkMFlXy4sPvjDctFtg/6+P+gKyju/R6mj
# 82nbY78iNaWXXWWEkH2LRlBV2AySfNIaSxzzPEKLUtCw/WvjPgcuKZvmPRul1LUd
# d5Q54ulkyUQ9eHoj8xN9ppB0g430yyYCRirCihC7pKkFDJvtaPpoLpWgKj8qa1hJ
# Yx8JaW5amJbkg/TAj/NGK978O9C9Ne9uJa7lryft0N3zDq+ZKJeYTQ49C/IIidYf
# wzIY4vDFLc5bnrRJOQrGCsLGra7lstnbFYhRRVg4MnEnGn+x9Cf43iw6IGmYslmJ
# aG5vp7d0w0AFBqYBKig+gj8TTWYLwLNN9eGPfxxvFX1Fp3blQCplo8NdUmKGwx1j
# NpeG39rz+PIWoZon4c2ll9DuXWNB41sHnIc+BncG0QaxdR8UvmFhtfDcxhsEvt9B
# xw4o7t5lL+yX9qFcltgA1qFGvVnzl6UJS0gQmYAf0AApxbGbpT9Fdx41xtKiop96
# eiL6SJUfq/tHI4D1nvi/a7dLl+LrdXga7Oo3mXkYS//WsyNodeav+vyL6wuA6mk7
# r/ww7QRMjt/fdW1jkT3RnVZOT7+AVyKheBEyIXrvQQqxP/uozKRdwaGIm1dxVk5I
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZczCCGW8CAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAsyOtZamvdHJTgAAAAACzDAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgdO6vm2/6
# 3vE2ZRjt/Cs73H3UwIUccrmm0S+/FgMP8zswQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQAbEHqLZju5wCx2T6aeSX0evfzclQl5Wp8tcFQtIoHk
# U+8hbLotR6fVSLR03FDI842IcPAkehJXIkdyDNcDJod1jAAl+Ph4ssJ0VRH/QQ/a
# jn3I4h1MsR46yX4908jCEPxCws/tT67TdGXjtRkY9HrvRLuzMa95NTY4zEJqSTc1
# wdrs8i7KyBrQHAUeVqhrdQ7iw5f2lGdX2fICaLAaTj5M2yZv8m/36S7zYHKeGqbF
# XdqMyRY/hLyPohfQ4l1bdq6b8SfzOHynejiOAEFKzv6DcP4lMaOhB19F3HMXNrZ2
# cKRKuvWtGpBWblw/VoKoSud1hd1GTBWMwkMUzVsaavSaoYIW/TCCFvkGCisGAQQB
# gjcDAwExghbpMIIW5QYJKoZIhvcNAQcCoIIW1jCCFtICAQMxDzANBglghkgBZQME
# AgEFADCCAVEGCyqGSIb3DQEJEAEEoIIBQASCATwwggE4AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEICzZzVeaUOscCreqVgcOBH9+5/4rR+vX/V+D1AgA
# urXvAgZjI12tJdkYEzIwMjIxMDA0MTQzOTE0LjMxNlowBIACAfSggdCkgc0wgcox
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1p
# Y3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJjAkBgNVBAsTHVRoYWxlcyBUU1Mg
# RVNOOjQ5QkMtRTM3QS0yMzNDMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNloIIRVDCCBwwwggT0oAMCAQICEzMAAAGXA89ZnGuJeD8AAQAAAZcw
# DQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcN
# MjExMjAyMTkwNTE0WhcNMjMwMjI4MTkwNTE0WjCByjELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2Eg
# T3BlcmF0aW9uczEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046NDlCQy1FMzdBLTIz
# M0MxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDtAErqSkFN8/Ce/csrHVWcv1iSjNTA
# rPKEMqKPUTpYJX8TBZl88LNrpw4bEpPimO+Etcli5RBoZEieo+SzYUnb0+nKEWaE
# Ygubgp+HTFZiD85Lld7mk2Xg91KMDE2yMeOIH2DHpTsn5p0Lf0CDlfPE5HOwpP5/
# vsUxNeDWMW6zsSuKU69aL7Ocyk36VMyCKjHNML67VmZMJBO7bX1vYVShOvQqZUkx
# CpCR3szmxHT09s6nhwLeNCz7nMnU7PEiNGVxSYu+V0ETppFpK7THcGYAMa3SYZjQ
# xGyDOc7J20kEud6tz5ArSRzG47qscDfPYqv1+akex81w395E+1kc4uukfn0CeKtA
# Dum7PqRrbRMD7wyFnX2FvyaytGj0uaKuMXFJsZ+wfdk0RsuPeWHtVz4MRCEwfYr1
# c+JTkmS3n/pvHr/b853do28LoPHezk3dSxbniQojW3BTYJLmrUei/n4BHK5mTT8N
# uxG6zoP3t8HVmhCW//i2sFwxVHPsyQ6sdrxs/hapsPR5sti2ITG/Hge4SeH7Sne9
# 42OHeA/T7sOSJXAhhx9VyUiEUUax+dKIV7Gu67rjq5SVr5VNS4bduOpLsWEjeGHp
# Mei//3xd8dxZ42G/EDkr5+L7UFxIuBAq+r8diP/D8yR/du7vc4RGKw1ppxpo4JH9
# MnYfd+zUDuUgcQIDAQABo4IBNjCCATIwHQYDVR0OBBYEFG3PAc8o6zBullUL0bG+
# 3X69FQBgMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRY
# MFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01p
# Y3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEF
# BQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
# a2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAo
# MSkuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZI
# hvcNAQELBQADggIBAARI2GHSJO0zHnshct+Hgu4dsPU0b0yUsDXBhAdAGdH1T+uD
# eq3c3Hp7v5C4QowSEqp0t/eDlFHhH+hkvm8QlVZR8hIf+hJZ3OqtKGpyZPg7HNzY
# IGzRS2fKilUObhbYK6ajeq7KRg+kGgZ16Ku8N13XncDCwmQgyCb/yzEkpsgF5Pza
# 2etSeA2Y2jy7uXW4TSGwwCrVuK9Drd9Aiev5Wpgm9hPRb/Q9bukDeqHihw2OJfpn
# x32SPHwvu4E8j8ezGJ8KP/yYVG+lUFg7Ko/tjl2LlkCeNMNIcxk1QU8e36eEVdRw
# eNc9FEcIyqomDgPrdfpvRXRHztD3eKnAYhcEzM4xA0i0k5F6Qe0eUuLduDouemOz
# RoKjn9GUcKM2RIOD7FXuph5rfsv84pM2OqYfek0BrcG8/+sNCIYRi+ABtUcQhDPt
# YxZJixZ5Q8VkjfqYKOBRjpXnfwKRC0PAzwEOIBzL6q47x6nKSI/QffbKrAOHznYF
# 5abV60X4+TD+3xc7dD52IW7saCKqN16aPhV+lGyba1M30ecB7CutvRfBjxATa2nS
# FF03ZvRSJLEyYHiE3IopdVoMs4UJ2Iuex+kPSuM4fyNsQJk5tpZYuf14S8Ov5A1A
# +9Livjsv0BrwuvUevjtXAnkTaAISe9jAhEPOkmExGLQqKNg3jfJPpdIZHg32MIIH
# cTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAAAAAAFTANBgkqhkiG9w0BAQsFADCB
# iDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMp
# TWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMjEw
# OTMwMTgyMjI1WhcNMzAwOTMwMTgzMjI1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAOThpkzntHIh
# C3miy9ckeb0O1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDivbk+F2Az/1xPx2b3lVNx
# WuJ+Slr+uDZnhUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU88V29YZQ3MFEyHFc
# UTE3oAo4bo3t1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqYO7oaezOtgFt+jBAc
# nVL+tuhiJdxqD89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzpcGkNyjYtcI4xyDUo
# veO0hyTD4MmPfrVUj9z6BVWYbWg7mka97aSueik3rMvrg0XnRm7KMtXAhjBcTyzi
# YrLNueKNiOSWrAFKu75xqRdbZ2De+JKRHh09/SDPc31BmkZ1zcRfNN0Sidb9pSB9
# fvzZnkXftnIv231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZNN3SUHDSCD/AQ8rdH
# GO2n6Jl8P0zbr17C89XYcz1DTsEzOUyOArxCaC4Q6oRRRuLRvWoYWmEBc8pnol7X
# KHYC4jMYctenIPDC+hIK12NvDMk2ZItboKaDIV1fMHSRlJTYuVD5C4lh8zYGNRiE
# R9vcG9H9stQcxWv2XFJRXRLbJbqvUAV6bMURHXLvjflSxIUXk8A8FdsaN8cIFRg/
# eKtFtvUeh17aj54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB2TASBgkrBgEEAYI3
# FQEEBQIDAQABMCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSavoKRPEY1Kc8Q/y8E7jAd
# BgNVHQ4EFgQUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0gBFUwUzBRBgwrBgEE
# AYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUFBwMI
# MBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMB
# Af8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1Ud
# HwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3By
# b2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQRO
# MEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2Vy
# dHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MA0GCSqGSIb3DQEBCwUAA4IC
# AQCdVX38Kq3hLB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOXPTEztTnXwnE2P9pk
# bHzQdTltuw8x5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjYNi6cqYJWAAOwBb6J6Gng
# ugnue99qb74py27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/zjj3G82jfZfakVqr3
# lbYoVSfQJL1AoL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz/AyeixmJ5/ALaoHC
# gRlCGVJ1ijbCHcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyRgNI95ko+ZjtPu4b6
# MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdUbZ1jdEgssU5HLcEU
# BHG/ZPkkvnNtyo4JvbMBV0lUZNlz138eW0QBjloZkWsNn6Qo3GcZKCS6OEuabvsh
# VGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4Ku+xBZj1p/cvBQUl+
# fpO+y/g75LcVv7TOPqUxUYS8vwLBgqJ7Fx0ViY1w/ue10CgaiQuPNtq6TPmb/wrp
# NPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9vMvpe784cETRkPHI
# qzqKOghif9lwY1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGCAsswggI0AgEBMIH4
# oYHQpIHNMIHKMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUw
# IwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMSYwJAYDVQQLEx1U
# aGFsZXMgVFNTIEVTTjo0OUJDLUUzN0EtMjMzQzElMCMGA1UEAxMcTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAYUDSsI2YSTTNTXYN
# g0YxTcHWY9GggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAN
# BgkqhkiG9w0BAQUFAAIFAObmP4QwIhgPMjAyMjEwMDQxMzEzNDBaGA8yMDIyMTAw
# NTEzMTM0MFowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA5uY/hAIBADAHAgEAAgIF
# PDAHAgEAAgISUTAKAgUA5ueRBAIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEE
# AYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBBQUAA4GB
# ACIBDbclNZFY/LNvOvPaYdIIh/iPXXDbY8IxOXAG4h92IS/sPtoCErAPKTXwFsQD
# KmehP3fm6UEf6BaI/PQE170P14zRbLij/JZxfAdufCbfweUHvLiMDYMit0TW+mnx
# QfCPr8qQifNKngT5plQ6Nqq3ArAeT65gVZMVZjIruICUMYIEDTCCBAkCAQEwgZMw
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGXA89ZnGuJeD8AAQAA
# AZcwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRAB
# BDAvBgkqhkiG9w0BCQQxIgQgcajv8l/DeBOQ0U5hQayBnUzq+QkruRHVPLd0DS1D
# DvMwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCBbe9obEJV6OP4EDMVJ8zF8
# dD5vHGSoLDwuQxj9BnimvzCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAABlwPPWZxriXg/AAEAAAGXMCIEIIYlnC1Z2Wr0P+w+KHHwH+Fc
# I8jDxtFpVa7lI0RlP659MA0GCSqGSIb3DQEBCwUABIICAIyBDCGHAjPsgChVMXVa
# 6U51PSXnziNF1J8DVhWE5t30kh2IHTwhNc0o2tMIBkca+UOxMWb7BIv+s8EUjkif
# wEAOuS+VItRZzP2tH/ESc8SGmY16Cx1X1U9H2F+EgAfMZkR5N4WqutRUwX8283H5
# xRlM6OieHchGHPm4UiVAedXhMC6bB6Bc7PkZHVavX/QO9zR6drXNm/kbkmqjO38F
# tRTxQv3xbGrGa2gjZabLkNDp68HMePngD56TskZI/Dxr/QoihNz4NCObTlZTvpiO
# 0rKeUwh8+ukRuXOJ87WbzjAYq6z3QYJY4jcgnRbKrWv1I5uHxpP2hu2uiqhuO6YU
# 0HFcu+a92fKS5DVfWallVXyoHECotHUGU/GWH6U4u/jtJhdJ9Q5MyHHUmNQyf634
# BSevTZQmMtXky2pjsEahe2nCcBZMO5DJrBtZVb1AKiI+O1RLpOxUedudkqZVDsZ8
# q4f0cEAjdgunq4LGPbXi1kWJ9nFYKCzbZpcx0eii265JOpzNxSOk9T/7nr359ORU
# 0r5a6vWTH7Nd2nAhHIkYKzbBJdZJHIT6JzmFmrERt/N8E8KaO6JpdDD15tUzQSIW
# KnHdB2IMBQdjBOeFzM1z7c9i/Qu0mFkir/uhqgrzmwJ+ZAC8JHXolJvFWGDmK2OD
# EmZnX91OOsZt18f5qbaFT1ti
# SIG # End signature block
