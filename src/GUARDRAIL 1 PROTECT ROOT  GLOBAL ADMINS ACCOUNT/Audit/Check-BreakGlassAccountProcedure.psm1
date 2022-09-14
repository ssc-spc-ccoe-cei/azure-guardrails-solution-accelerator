<#
.SYNOPSIS
   The module Check if you have uploaded the required txt file that shows the Break Glass 
   accounts documentation , the results are sent to the identified log analytics workspace.

.DESCRIPTION
    The module Check if you have uploaded the required txt file that shows the Break Glass 
    accounts documentation , the results are sent to the identified log analytics workspace.
.PARAMETER Name
        token : auth token 
        WorkSpaceID : Workspace ID to ingest the logs 
        WorkSpaceKey: Workspace Key for the Workdspace 
        LogType: GuardrailsCompliance, it will show in log Analytics search as GuardrailsCompliance_CL
#>
$PSDefaultParameterValues.Clear()
function Check-ProcedureDocument {
    param (
        [string] $StorageAccountName,
        [string] $ContainerName, 
        [string] $ResourceGroupName,
        [string] $SubscriptionID, 
        [string] $DocumentName, 
        [string] $ControlName, 
        [string]$ItemName,
        [hashtable] $msgTable, 
        [string] $WorkSpaceID, 
        [string] $workspaceKey, 
        [string] $LogType,
        [string]$itsgcode,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime
    )

    [bool] $IsCompliant = $false
    [string] $Comments = $null

    try {
        Connect-AzAccount -Identity -Subscription  $SubscriptionID -ErrorAction Stop
    }
    catch {
        Add-LogEntry 'Error' "Failed to run 'Connect-AzAccount' with error: $_" -workspaceKey $workspaceKey -workspaceGuid $WorkSpaceID
        throw "Error: Failed to run 'Connect-AzAccount' with error: $_"
    }

    try {
        $StorageAccount = Get-Azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction Stop
    }
    catch {
        Add-LogEntry 'Error' "Could not find storage account '$storageAccountName' in resoruce group '$resourceGroupName' of `
            subscription '$subscriptionId'; verify that the storage account exists and that you have permissions to it. Error: $_" `
            -workspaceKey $workspaceKey -workspaceGuid $WorkSpaceID
        Write-Error "Could not find storage account '$storageAccountName' in resoruce group '$resourceGroupName' of `
            subscription '$subscriptionId'; verify that the storage account exists and that you have permissions to it. Error: $_"
    }

    # check for procedure doc in blob storage account
    $blobs = Get-AzStorageBlob -Container $ContainerName -Context $StorageAccountContext -Blob $DocumentName -ErrorAction SilentlyContinue

    If ($blobs) {
        # a blob wit the name $DocumentName was located in the specified storage account
        $IsCompliant = $True
        $Comments = $msgTable.procedureFileFound -f $DocumentName, $Containername, $StorageAccountName 
    }
    else {
        # no blob with the name $DocumentName was found in the specified storage account
        $Comments = $msgTable.procedureFileNotFound -f $ItemName, $DocumentName
    }

    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        ItemName         = $ItemName
        DocumentName     = $DocumentName
        Comments         = $Comments
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }
    $JsonObject = convertTo-Json -inputObject $PsObject 
    Send-OMSAPIIngestionFile -customerId $WorkSpaceID  -sharedkey $workspaceKey -body $JsonObject -logType $LogType -TimeStampField Get-Date 
}
