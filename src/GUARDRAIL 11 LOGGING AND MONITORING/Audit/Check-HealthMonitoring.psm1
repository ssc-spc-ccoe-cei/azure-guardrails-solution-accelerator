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
    $apiUrl="https://management.azure.com/subscriptions/$subscriptionId/resourcegroups/$resourceGroup/providers/Microsoft.OperationalInsights/workspaces/$LAWName/linkedServices?api-version=2020-08-01"
    try {
        $response = Invoke-AzRestMethod -Uri $apiUrl -Method Get
    }
    catch {
        Write-Error "Error: Failed to call Azure Resource Manager REST API at URL '$apiURL'; returned error message: $_"
    }

    $data = $response.Content | ConvertFrom-Json
    return $data
}

function get-tenantDiagnosticsSettings {

    $apiUrl = "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01-preview"
    try {
        $response = Invoke-AzRestMethod -Uri $apiUrl -Method Get -ErrorAction Stop
    }
    catch {
        Write-Error "Error: Failed to call Azure Resource Manager REST API at URL '$apiURL'; returned error message: $_"
    }

    $data = $response.Content | ConvertFrom-Json
    return $data.value.properties
}

function Get-HealthMonitoringStatus {
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $HealthLAWResourceId,
        [Parameter(Mandatory=$true)]
        [string]
        $ControlName,
        [string] $itsginfohealthmon,
        [hashtable]
        $msgTable,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime,
        [int]
        $RetentionDays=90,
        [Parameter(Mandatory=$true)]
        [string]
        $CBSSubscriptionName
    )
    [PSCustomObject] $FinalObjectList = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    #$LogType="GuardrailsCompliance"
    #Code

    #Add test for proper right format of the LAW parameters
    $Subscription=$HealthLAWResourceId.Split("/")[2]
    $HealthLAWRG=$HealthLAWResourceId.Split("/")[4]
    $HealthLAWName=$HealthLAWResourceId.Split("/")[8]
    
    $IsCompliant=$false
    try{
        Select-AzSubscription -Subscription $Subscription -ErrorAction Stop | Out-Null
    }
    catch {
        $ErrorList.Add("Failed to execute the 'Select-AzSubscription' command with subscription ID '$($subscription)'--`
            ensure you have permissions to the subscription, the ID is correct, and that it exists in this tenant; returned `
            error message: $_")
        #    ensure you have permissions to the subscription, the ID is correct, and that it exists in this tenant; returned `
        #    error message: $_"
        throw "Error: Failed to execute the 'Select-AzSubscription' command with subscription ID '$($subscription)'--ensure `
            you have permissions to the subscription, the ID is correct, and that it exists in this tenant; returned error message: $_"
    }
    #
    #Health
    #
    $Comments=""
    $uncompliantParameters=4
    $LAW=Get-AzOperationalInsightsWorkspace -Name $HealthLAWName -ResourceGroupName $HealthLAWRG
    if ($null -eq $LAW)
    {
        $Comments+=$msgTable.healthLAWNotFound 
    }
    else {
        #1
        $LinkedServices=get-apiLinkedServicesData -subscriptionId $Subscription `
            -resourceGroup $LAW.ResourceGroupName `
            -LAWName $LAW.Name
        if (($LinkedServices.value.properties.resourceId | Where-Object {$_ -match "automationAccounts"}).count -gt 0)
        {
            $uncompliantParameters--
            $Comments+=$msgTable.lawNoAutoAcct 
        }
        #2
        #Test Retention
        $Retention=$LAW.retentionInDays
        if ($Retention -ge $RetentionDays)
        {
            $uncompliantParameters--
            $Comments+=$msgTable.lawRetentionHealthDays -f $RetentionDays
        }
        #3
        #Checks required solutions
        $enabledSolutions=(Get-AzOperationalInsightsIntelligencePack -ResourceGroupName $LAW.ResourceGroupName -WorkspaceName $LAW.Name| Where-Object {$_.Enabled -eq "True"}).Name
        if ($enabledSolutions -contains "AgentHealthAssessment")
        {
            $uncompliantParameters--
            $Comments+=$msgTable.lawHealthNoSolutionFound # "Required solutions not present in the Health Log Analytics Workspace."
        }
        #4
        # add as per SSC request, github issue 
        if ($enabledSolutions -contains "Updates")
        {
            $uncompliantParameters--
            $Comments+=$msgTable.lawSolutionNotFound # "Required solutions not present in the Log Analytics Workspace."
        }
        #Tenant...No information on how to detect it.
        #Blueprint
    }
    if ($uncompliantParameters -eq 0)
    {
        $IsCompliant=$true
        $Comments= $msgTable.logsAndMonitoringCompliantForHealth
    }
    else {
        $IsCompliant=$false #Not compliant
    }
    $object = [PSCustomObject]@{ 
        ComplianceStatus = $IsCompliant
        Comments = $Comments
        ItemName = $msgTable.healthMonitoring
        itsgcode = $itsginfohealthmon
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
