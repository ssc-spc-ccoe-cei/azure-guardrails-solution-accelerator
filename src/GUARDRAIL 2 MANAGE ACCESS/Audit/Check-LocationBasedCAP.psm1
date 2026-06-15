function Get-LocationBasedCAP {
    param (      
        [Parameter(Mandatory=$true)]
        [string] $ControlName,
        [Parameter(Mandatory=$true)]
        [string] $ItemName,
        [Parameter(Mandatory=$true)]
        [string] $itsgcode,
        [Parameter(Mandatory=$true)]
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string] $ReportTime,
        [Parameter(Mandatory = $true)]
        [string] $StorageAccountName,
        [Parameter(Mandatory = $true)]
        [string] $ContainerName,
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroupName,
        [Parameter(Mandatory = $true)]
        [string] $SubscriptionID, 
        [Parameter(Mandatory = $true)]
        [string[]] $DocumentName, 
        [string] $CloudUsageProfiles = "3",     # Passed as a string
        [string] $ModuleProfiles,               # Passed as a string
        [switch] $EnableMultiCloudProfiles      # feature flag, default to false    
    )
    $IsCompliant = $false
    [System.Collections.ArrayList]$ErrorList = New-Object System.Collections.ArrayList

    # Check: Allowed Location – Conditional Access Policy
    $PsObjectLocation = Get-allowedLocationCAPCompliance -ErrorList $ErrorList -IsCompliant $IsCompliant -ItemName $ItemName `
        -DocumentName $DocumentName -SubscriptionID $SubscriptionID -StorageAccountName $StorageAccountName `
        -ResourceGroupName $ResourceGroupName -ContainerName $ContainerName -msgTable $msgTable
    
    $ErrorList = $PsObjectLocation.Errors
    $CommentsArray = $PsObjectLocation.Comments

    if ($PsObjectLocation.ComplianceStatus -eq $true){
        $IsCompliant = $true
        $Comments = $msgTable.isCompliant + " " + $msgTable.compliantC2 + " " + $CommentsArray
    }
    else{
        $Comments = $msgTable.isNotCompliant + " " + $msgTable.nonCompliantC2 + " " + $CommentsArray
    }


    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        Comments         = $Comments
        ItemName         = $ItemName
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }

    # Add profile information if MCUP feature is enabled
    if ($EnableMultiCloudProfiles) {
        $result = Add-ProfileInformation -Result $PsObject -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId -ErrorList $ErrorList
        Write-Host "$result"
    }

    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput
}