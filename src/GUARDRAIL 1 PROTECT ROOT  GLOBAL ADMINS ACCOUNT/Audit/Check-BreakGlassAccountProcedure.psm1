<#
.SYNOPSIS
   The module Check if you have uploaded the required txt file that shows the Break Glass 
   accounts documentation , the results are sent to the identified log analytics workspace.

.DESCRIPTION
    The module Check if you have uploaded the required txt file that shows the Break Glass 
    accounts documentation , the results are sent to the identified log analytics workspace.
.PARAMETER Name
        token : auth token 
        ControlName :-  GUARDRAIL 1 PROTECT ROOT  GLOBAL ADMINS ACCOUNT
        ItemName, 
        WorkSpaceID : Workspace ID to ingest the logs 
        WorkSpaceKey: Workspace Key for the Workdspace 
        LogType: GuardrailsCompliance, it will show in log Analytics search as GuardrailsCompliance_CL
#>
$PSDefaultParameterValues.Clear()
function Check-ProcedureDocument {
    param (
        [string] $StorageAccountName, [string] $ContainerName, [string] $ResourceGroupName, `
        [string] $SubscriptionID, [string] $DocumentName, [string] $ControlName, [string]$ItemName, `
        [string] $WorkSpaceID, [string] $workspaceKey, [string] $LogType,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime
        )

  [bool] $IsCompliant= $false
  [string] $Comments = $null
 Connect-AzAccount -Identity -Subscription  $SubscriptionID
 #$null= select-Azsubscription -SubscriptionID $SubscriptionID

  $StorageAccount= Get-Azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName

  $StorageAccountContext = $StorageAccount.Context
  try {
      $Blobs=Get-AzStorageBlob -Container $ContainerName -Context $StorageAccountContext
      if (($blobs | Where-Object {$_.Name -eq $DocumentName}) -ne $null) 
      { 
          $IsCompliant = $True
          $Comments = "File $DocumentName found in Container $Containername on $StorageAccountName Storage account."
      }
      else
      {
          $Comments = "Coudnt find index for " + $ItemName + ", please create upload a file with a name " +$DocumentName+ " to confirm you have completed the Item in the control "
      }
  }
  catch
  {
      Write-error "error reading file from storage."
  }

  $PsObject = [PSCustomObject]@{
        ComplianceStatus= $IsCompliant
        ControlName = $ControlName
        ItemName = $ItemName
        DocumentName = $DocumentName
        Comments = $Comments
        ReportTime = $ReportTime
}
  $JsonObject= convertTo-Json -inputObject $PsObject 
            Send-OMSAPIIngestionFile -customerId $WorkSpaceID  -sharedkey $workspaceKey -body $JsonObject -logType $LogType -TimeStampField Get-Date 
}
