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
        [hashtable]
        $msgTable,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime,
        [Parameter(Mandatory=$true)]
        [string]
        $CBSSubscriptionName
    )

    $LogType="GuardrailsCompliance"
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
        $ActivityLogDS=Get-AzOperationalInsightsDataSource -Workspace $LAW -Kind AzureActivityLog
        If ($ActivityLogDS -eq $null)
        {
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
            $enabledLogs=(($p| ? {$_.workspaceId -eq $wsid}).logs | ? {$_.enabled -eq $true}).category
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
        if ((Get-AzSecurityPricing | Select-Object PricingTier | Where-Object {$_.PricingTier -eq 'Free'}).Count -gt 0)
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
# MIInpAYJKoZIhvcNAQcCoIInlTCCJ5ECAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAN7zHwcZFPCkki
# vlo2DGDVkNjBgGoD6LtoOq9i1LOEu6CCDXYwggX0MIID3KADAgECAhMzAAACURR2
# zMWFg24LAAAAAAJRMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjEwOTAyMTgzMjU5WhcNMjIwOTAxMTgzMjU5WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDBIpXR3b1IYAMunV9ZYBVYsaA7S64mqacKy/OJUf0Lr/LW/tWlJDzJH9nFAhs0
# zzSdQQcLhShOSTUxtlwZD9dnfIcx4pZgu0VHkqQw2dVc8Ob21GBo5sVrXgEAQxZo
# rlEuAl20KpSIFLUBwoZFGFSQNSMcqPudXOw+Mhvn6rXYv/pjXIjgBntn6p1f+0+C
# 2NXuFrIwjJIJd0erGefwMg//VqUTcRaj6SiCXSY6kjO1J9P8oaRQBHIOFEfLlXQ3
# a1ATlM7evCUvg3iBprpL+j1JMAUVv+87NRApprPyV75U/FKLlO2ioDbb69e3S725
# XQLW+/nJM4ihVQ0BHadh74/lAgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUMLgM7NX5EnpPfK5uU6FPvn2g/Ekw
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzQ2NzU5NjAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAIVJlff+Fp0ylEJhmvap
# NVv1bYLSWf58OqRRIDnXbHQ+FobsOwL83/ncPC3xl8ySR5uK/af4ZDy7DcDw0yEd
# mKbRLzHIfcztZVSrlsg0GKwZuaB2MEI1VizNCoZlN+HlFZa4DNm3J0LhTWrZjVR0
# M6V57cFW0GsV4NlqmtelT9JFEae7PomwgAV9xOScz8HzvbZeERcoSRp9eRsQwOw7
# 8XeCLeglqjUnz9gFM7RliCYP58Fgphtkht9LNEcErLOVW17m6/Dj75zg/IS+//6G
# FEK2oXnw5EIIWZraFHqSaee+NMgOw/R6bwB8qLv5ClOJEpGKA3XPJvS9YgOpF920
# Vu4Afqa5Rv5UJKrsxA7HOiuH4TwpkP3XQ801YLMp4LavXnvqNkX5lhFcITvb01GQ
# lcC5h+XfCv0L4hUum/QrFLavQXJ/vtirCnte5Bediqmjx3lswaTRbr/j+KX833A1
# l9NIJmdGFcVLXp1en3IWG/fjLIuP7BqPPaN7A1tzhWxL+xx9yw5vQiT1Yn14YGmw
# OzBYYLX0H9dKRLWMxMXGvo0PWEuXzYyrdDQExPf66Fq/EiRpZv2EYl2gbl9fxc3s
# qoIkyNlL1BCrvmzunkwt4cwvqWremUtqTJ2B53MbBHlf4RfvKz9NVuh5KHdr82AS
# MMjU4C8KNTqzgisqQdCy8unTMIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
# hkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
# IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQg
# Q29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03
# a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akr
# rnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0Rrrg
# OGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy
# 4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9
# sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAh
# dCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8k
# A/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTB
# w3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmn
# Eyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90
# lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0w
# ggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2o
# ynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBa
# BgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsG
# AQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNV
# HSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsG
# AQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABl
# AG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKb
# C5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11l
# hJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6
# I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0
# wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560
# STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQam
# ASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGa
# J+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ah
# XJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA
# 9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33Vt
# Y5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr
# /Xmfwb1tbWrJUnMTDXpQzTGCGYQwghmAAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAAJRFHbMxYWDbgsAAAAAAlEwDQYJYIZIAWUDBAIB
# BQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIMC+IWuDSLS82+tvghem5pAX
# f8SoKzgY7vLdkQ+pA4gUMEQGCisGAQQBgjcCAQwxNjA0oBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEcgBpodHRwczovL3d3dy5taWNyb3NvZnQuY29tIDANBgkqhkiG9w0B
# AQEFAASCAQBLEJNHuehihtDlHfpWFVJhTWSJ/s/jT+ZiybCiU35B/ilnFYwFPXFf
# NT6zT3qtFFAJmjs+n38ooMByb7on/WcZ6mVX0+NoOVbus1HNdR3rlAHueaMbG6+U
# jzZca02uVuHtrqMZjRdRKQ1dlkEzoMEFoIKgk3MI9HRqGa6b5mbChjHmOkwkqQa3
# /sgzyAxFupN+1EUx2HcvX5BvJcVGN7Ir7MQAGhtZDG9b090sBfj69Otsgb80efJ/
# 9wKkS2vBKrfVE3fRgeGS5a7ynwmKpbi1XRS+B8zJqKC0hnq4Zpn6InwpJ14+bs03
# Bvv8wecZXopoypIA+EnXZaEA56PbXlGLoYIXDDCCFwgGCisGAQQBgjcDAwExghb4
# MIIW9AYJKoZIhvcNAQcCoIIW5TCCFuECAQMxDzANBglghkgBZQMEAgEFADCCAVUG
# CyqGSIb3DQEJEAEEoIIBRASCAUAwggE8AgEBBgorBgEEAYRZCgMBMDEwDQYJYIZI
# AWUDBAIBBQAEIA6GD08HXJPDI1AwZqj92fTOElnkQN60q3cTlkroDnMbAgZi2wZN
# uI8YEzIwMjIwNzI2MTgzNjI2LjQyNlowBIACAfSggdSkgdEwgc4xCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBP
# cGVyYXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjo0
# RDJGLUUzREQtQkVFRjElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vy
# dmljZaCCEV8wggcQMIIE+KADAgECAhMzAAABsKHjgzLojTvAAAEAAAGwMA0GCSqG
# SIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# JjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTIyMDMw
# MjE4NTE0MloXDTIzMDUxMTE4NTE0Mlowgc4xCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjo0RDJGLUUzREQtQkVF
# RjElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCAiIwDQYJ
# KoZIhvcNAQEBBQADggIPADCCAgoCggIBAJzGbTsM19KCnQc5RC7VoglySXMKLut/
# yWWPQWD6VAlJgBexVKx2n1zgX3o/xA2ZgZ/NFGcgNDRCJ7mJiOeW7xeHnoNXPlg7
# EjYWulfk3oOAj6a7O15GvckpYsvLcx+o8Se8CrfIb40EJ8W0Qx4TIXf0yDwAJ4/q
# O94dJ/hGabeJYg4Gp0G0uQmhwFovAWTHlD1ci+sp36AxT9wIhHqw/70tzMvrnDF7
# jmQjaVUPnjOgPOyFWZiVr7e6rkSl4anT1tLv23SWhXqMs14wolv4ZeQcWP84rV2F
# rr1KbwkIa0vlHjlv4xG9a6nlTRfo0CYUQDfrZOMXCI5KcAN2BZ6fVb09qtCdsWdN
# NxB0y4lwMjnuNmx85FNfzPcMZjmwAF9aRUUMLHv626I67t1+dZoVPpKqfSNmGtVt
# 9DETWkmDipnGg4+BdTplvgGVq9F3KZPDFHabxbLpSWfXW90MZXOuFH8yCMzDJNUz
# eyAqytFFyLZir3j4T1Gx7lReCOUPw1puVzbWKspV7ModZjtN/IUWdVIdk3HPp4QN
# 1wwdVvdXOsYdhG8kgjGyAZID5or7C/75hyKQb5F0Z+Ee04uY9K+sDZ3l3z8TQZWA
# fYurbZCMWWnmJVsu5V4PR5PO+U6D7tAtMvMULNYibT9+sxVZK/WQer2JJ9q3Z7lj
# Fs4lgpmfc6AVAgMBAAGjggE2MIIBMjAdBgNVHQ4EFgQUOt8BJDcBJm4dy6ASZHrX
# IEfWNj8wHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXwYDVR0fBFgw
# VjBUoFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWlj
# cm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3JsMGwGCCsGAQUF
# BwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3Br
# aW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgx
# KS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkqhkiG
# 9w0BAQsFAAOCAgEA3XPih5sNtUfAyLnlXq6MZSpCh0TF+uG+nhIJ44//cMcQGEVi
# Z2N263NwvrQjCFOni/+oxf76jcmUhcKWLXk9hhd7vfFBhZZzcF5aNs07Uligs24p
# veasFuhmJ4y82OYm1G1ORYsFndZdvF//NrYGxaXqUNlRHQlskV/pmccqO3Oi6wLH
# cPB1/WRTLJtYbIiiwE/uTFEFEL45wWD/1mTCPEkFX3hliXEypxXzdZ1k6XqGTysG
# AtLXUB7IC6CH26YygKQuXG8QjcJBAUG/9F3yNZOdbFvn7FinZyNcIVLxld7h0bEL
# fQzhIjelj+5sBKhLcaFU0vbjbmf0WENgFmnyJNiMrL7/2FYOLsgiQDbJx6Dpy1Ef
# vuRGsdL5f+jVVds5oMaKrhxgV7oEobrA6Z56nnWYN47swwouucHf0ym1DQWHy2DH
# OFRRN7yv++zes0GSCOjRRYPK7rr1Qc+O3nsd604Ogm5nR9QqhOOc2OQTrvtSgXBS
# tu5vF6W8DPcsns53cQ4gdcR1Y9Ng5IYEwxCZzzYsq9oalxlH+ZH/A6J7ZMeSNKNk
# rXPx6ppFXUxHuC3k4mzVyZNGWP/ZgcUOi2qV03m6Imytvi1kfGe6YdCh32POgWeN
# H9lfKt+d1M+q4IhJLmX0E2ZZICYEb9Q0romeMX8GZ+cbhuNsFimJga/fjjswggdx
# MIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEBCwUAMIGI
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylN
# aWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAeFw0yMTA5
# MzAxODIyMjVaFw0zMDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA5OGmTOe0ciEL
# eaLL1yR5vQ7VgtP97pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/XE/HZveVU3Fa
# 4n5KWv64NmeFRiMMtY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1hlDcwUTIcVxR
# MTegCjhuje3XD9gmU3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7M62AW36MEByd
# Uv626GIl3GoPz130/o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3KNi1wjjHINSi9
# 47SHJMPgyY9+tVSP3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy1cCGMFxPLOJi
# ss254o2I5JasAUq7vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF803RKJ1v2lIH1+
# /NmeRd+2ci/bfV+AutuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQcNIIP8BDyt0cY
# 7afomXw/TNuvXsLz1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahhaYQFzymeiXtco
# dgLiMxhy16cg8ML6EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkLiWHzNgY1GIRH
# 29wb0f2y1BzFa/ZcUlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV2xo3xwgVGD94
# q0W29R6HXtqPnhZyacaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIGCSsGAQQBgjcV
# AQQFAgMBAAEwIwYJKwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUpzxD/LwTuMB0G
# A1UdDgQWBBSfpxVdAF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBTMFEGDCsGAQQB
# gjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20v
# cGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgw
# GQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB
# /wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0f
# BE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJv
# ZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4w
# TDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0
# cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcNAQELBQADggIB
# AJ1VffwqreEsH2cBMSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1OdfCcTY/2mRs
# fNB1OW27DzHkwo/7bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYAA7AFvonoaeC6
# Ce5732pvvinLbtg/SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbzaN9l9qRWqveV
# tihVJ9AkvUCgvxm2EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6LGYnn8AtqgcKB
# GUIZUnWKNsIdw2FzLixre24/LAl4FOmRsqlb30mjdAy87JGA0j3mSj5mO0+7hvoy
# GtmW9I/2kQH2zsZ0/fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0SCyxTkctwRQE
# cb9k+SS+c23Kjgm9swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxkoJLo4S5pu+yFU
# a2pFEUep8beuyOiJXk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFmPWn9y8FBSX5+
# k77L+DvktxW/tM4+pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC4822rpM+Zv/Cuk0
# +CQ1ZyvgDbjmjJnW4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7vzhwRNGQ8cir
# Ooo6CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIC0jCCAjsCAQEwgfyh
# gdSkgdEwgc4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAn
# BgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQL
# Ex1UaGFsZXMgVFNTIEVTTjo0RDJGLUUzREQtQkVFRjElMCMGA1UEAxMcTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAAp4vkN3fD5FN
# BVYZklZeS/JFPBiggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAx
# MDANBgkqhkiG9w0BAQUFAAIFAOaKIfswIhgPMjAyMjA3MjYxMjE5MDdaGA8yMDIy
# MDcyNzEyMTkwN1owdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA5ooh+wIBADAKAgEA
# AgIMIgIB/zAHAgEAAgIRYjAKAgUA5otzewIBADA2BgorBgEEAYRZCgQCMSgwJjAM
# BgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEB
# BQUAA4GBAChMVkTOe/m/aZSCOn6Gr9sFc/b4hGt2JLG5Wxn72b9WDxV41NYg1769
# PidGKBp5uPoZv8/wLCvmsL3dJ1JB0EFJSxU+AHW32IxGKHjNUXOeg4jJTwEHDHly
# r7C4+o2v8nPX96WU8rsWK2nLVjkEctlR7QL6apL5bjMY1+WL8sbiMYIEDTCCBAkC
# AQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGwoeODMuiN
# O8AAAQAAAbAwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG
# 9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQg+PEg1xYQ7Jkxo2RteaawehM62Qk0XXNG
# E8jZMZG9HgUwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCDNBgtDd8uf9KTj
# Gf1G67IfKmcNFJmeWTd6ilAy5xWEoDCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwAhMzAAABsKHjgzLojTvAAAEAAAGwMCIEIA2vHbeLA0GQLXd+
# ptCGtHpXQF9QLSTfeMbHLPhCe2V3MA0GCSqGSIb3DQEBCwUABIICAAbXZXVjPbQf
# GbLmwjgADGW5at+2q49a+9wHn+Dxt+jTAPOFYTVY2jI9AgDsJqtpySJsuCIEYQ1K
# w3Li+1y2RDzNiyeLSH4A9klS39xfbt/MlQEHyoYyKIGDbQjI29pII0+FnXYXWZ+1
# 5XWLDUWg6QEPOT5InS6fKNUfGuPjnPtkMiKdlAMUvzI4h33opluaxEssAZ73pokz
# SaxdjLtTxA301O7x15kejSbQ0fQKDKYI53IYkCGLoDUwAtZYTvTWhyt6LjSlxHJ0
# pEstrvITYVVdakRJnmTe8Ep6ThH2qEgoLiN4DkHtIzkaGnQg/gacZzqWp5p7AinK
# Rv/qPsnZG3d2cVEG3Dnuko8rRkbUzPUsrKZK+p2uZozP9BAYrnDO0KuCGmn7m63w
# /dWpeyrCe0kDPMbE2k+6p5zvmvXZ9PuO0h3YLJBj+uL1MC8Klt5drt55qBUGYgj5
# HuvrAcy9elUtMtAknxLcnTrQwwDT0OK5AXrflmOIYDUncZtQFgCzJO1iJVp2nIDb
# 31E79ObWKY7kXwG+bKTsQdymm159JYmehPXAN4hhJdV5lG5Z9BQNUAWtHw5FPhKo
# EiKWUdHhk4CfXO4OHugTLJ0rnAfBO8ihao83uDFrphap05BH8yoDJbNvpPSOiRaI
# 9Ib/Uelp48zLtsfK8FtQag4gPzKkAv7Z
# SIG # End signature block
