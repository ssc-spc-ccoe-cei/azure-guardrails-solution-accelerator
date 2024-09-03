function Test-ExemptionExists {
    [OutputType([bool])]
    param (
        [Parameter(Mandatory=$true)]
        [string] $ScopeId,
        [Parameter(Mandatory=$true)]
        [array]  $requiredPolicyExemptionIds
    )
    $exemptionsIds = (Get-AzPolicyExemption -Scope $ScopeId -ErrorAction SilentlyContinue).Properties.PolicyDefinitionReferenceIds
    return $null -ne $exemptionsIds -and ($exemptionsIds | Where-Object { $_ -in $requiredPolicyExemptionIds })
}

function Check-StatusDataInTransit {
    [CmdletBinding()]
    [OutputType([System.Collections.ArrayList])]
    param (
        [System.Object] $objList,
        [string] $objType, #subscription or management Group
        [array]  $requiredPolicyExemptionIds,
        [string] $PolicyID,
        [string] $ControlName,
        [string] $ItemName,
        [string] $LogType,
        [string] $itsgcode,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string] $ReportTime,
        [string] $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,
        [switch] $EnableMultiCloudProfiles # New feature flag, default to false    
    )   
    $tempObjectList = [System.Collections.ArrayList]@()
    foreach ($obj in $objList)
    {

        if ($objType -eq "subscription") {
            $tempId="/subscriptions/$($obj.Id)"
        }
        else {
            $tempId=$obj.Id
        }
        $AssignedPolicyList = Get-AzPolicyAssignment -scope $tempId -PolicyDefinitionId $PolicyID
        If ($null -eq $AssignedPolicyList -or (-not ([string]::IsNullOrEmpty(($AssignedPolicyList.Properties.NotScopesScope)))))
        {
            $Comment=$msgTable.pbmmNotApplied 
            $ComplianceStatus=$false
        }
        else {
            #PBMM is applied and not excluded. Testing if specific policies haven't been excluded.
            if (Test-ExemptionExists -ScopeId $tempId -requiredPolicyExemptionIds $requiredPolicyExemptionIds)
            { # boolean, exemption for gr6 required policies exists.
                $ComplianceStatus=$false
                $Comment=$msgTable.grexemptionFound -f $obj.Id,$objType
            }
            else {
                $ComplianceStatus=$true
                $Comment=$msgTable.isCompliant 
                #No exemption exists. All good.
            }
        }
        if ($null -eq $obj.DisplayName)
        {
            $DisplayName=$obj.Name
        }
        else {
            $DisplayName=$obj.DisplayName
        }

        $c = New-Object -TypeName PSCustomObject -Property @{ 
            Type = [string]$objType
            Id = [string]$obj.Id
            Name = [string]$obj.Name
            DisplayName = [string]$DisplayName
            ComplianceStatus = [boolean]$ComplianceStatus
            Comments = [string]$Comment
            ItemName = [string]$ItemName
            itsgcode = [string]$itsgcode
            ControlName = [string]$ControlName
            ReportTime = [string]$ReportTime
        }

        if ($EnableMultiCloudProfiles) {
            if ($objType -eq "subscription") {
                $result = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $obj.Id
            } else {
                $result = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
            }
            if ($result -eq 0) {
                Write-Output "No matching profile found or error occurred"
                $c.ComplianceStatus = "Not Applicable"
            } else {
                Write-Output "Valid profile returned: $result"
                $c | Add-Member -MemberType NoteProperty -Name "Profile" -Value $result
            }
        }        
        $tempObjectList.add($c)| Out-Null
    }
    return $tempObjectList
}

function Verify-ProtectionDataInTransit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
            [string] $ControlName,
            [string] $ItemName,
            [string] $PolicyID, 
            [string] $itsgcode,
            [hashtable] $msgTable,
            [Parameter(Mandatory=$true)]
            [string] $ReportTime,
            [Parameter(Mandatory=$false)]
            [string] $CBSSubscriptionName,
            [string] $CloudUsageProfiles = "3",  # Passed as a string
            [string] $ModuleProfiles,  # Passed as a string
            [switch] $EnableMultiCloudProfiles # New feature flag, default to false    
    )
    $FinalObjectList = [System.Collections.ArrayList]@()
    $ErrorList = [System.Collections.ArrayList]@()
    $grRequiredPolicies=@("FunctionAppShouldOnlyBeAccessibleOverHttps","WebApplicationShouldOnlyBeAccessibleOverHttps", "ApiAppShouldOnlyBeAccessibleOverHttps", "OnlySecureConnectionsToYourRedisCacheShouldBeEnabled","SecureTransferToStorageAccountsShouldBeEnabled")
    #Check management groups
    try {
        $objs = Get-AzManagementGroup -ErrorAction Stop
    }
    catch {
        $Errorlist.Add("Failed to execute the 'Get-AzManagementGroup' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_")
        throw "Error: Failed to execute the 'Get-AzManagementGroup' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_"
    }
    [string]$type = "Management Group"
    if($EnableMultiCloudProfiles) {
        $FinalObjectList+=Check-StatusDataInTransit -objList $objs -objType $type -itsgcode $itsgcode -requiredPolicyExemptionIds $grRequiredPolicies -PolicyID $PolicyID -ReportTime $ReportTime -ItemName $ItemName -LogType $LogType -msgTable $msgTable -ControlName $ControlName -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -EnableMultiCloudProfiles
    }
    else {
        $FinalObjectList+=Check-StatusDataInTransit -objList $objs -objType $type -itsgcode $itsgcode -requiredPolicyExemptionIds $grRequiredPolicies -PolicyID $PolicyID -ReportTime $ReportTime -ItemName $ItemName -LogType $LogType -msgTable $msgTable -ControlName $ControlName
    }
    #Check Subscriptions
    try {
        $objs = Get-AzSubscription -ErrorAction Stop | Where-Object {$_.State -eq "Enabled"} 
    }
    catch {
        $Errorlist.Add("Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_")
        throw "Error: Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Resources module; returned error message: $_"
    }
    [string]$type = "subscription"

    if ($EnableMultiCloudProfiles) {   
        $FinalObjectList+=Check-StatusDataInTransit -objList $objs -objType $type -itsgcode $itsgcode -requiredPolicyExemptionIds $grRequiredPolicies -PolicyID $PolicyID -ReportTime $ReportTime -ItemName $ItemName -LogType $LogType -msgTable $msgTable  -ControlName $ControlName -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -EnableMultiCloudProfiles
    }
    else {
        $FinalObjectList+=Check-StatusDataInTransit -objList $objs -objType $type -itsgcode $itsgcode -requiredPolicyExemptionIds $grRequiredPolicies -PolicyID $PolicyID -ReportTime $ReportTime -ItemName $ItemName -LogType $LogType -msgTable $msgTable -ControlName $ControlName
    } 
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $FinalObjectList 
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput  
}

