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
            $Comment = $msgTable.pbmmNotApplied 
            $ComplianceStatus=$false
        }
        else {
            # PBMM initiative applied
            $Comment = $msgTable.pbmmApplied

            # List the policies within the PBMM initiative (policy set definition)
            $policySetDefinition = Get-AzPolicySetDefinition | `
                Where-Object { $_.PolicySetDefinitionId -like "*$PolicyID*" } 

            $listPolicies = $policySetDefinition.Properties.policyDefinitions
            # Check all policies are applied for this scope
            $appliedPolicies = $listPolicies.policyDefinitionReferenceId | Where-Object { $requiredPolicyExemptionIds -contains $_ }
            if($appliedPolicies.Count -ne  $requiredPolicyExemptionIds.Count){
                # some required policies are not applied
                $ComplianceStatus=$false
                $Comment += ' ' + $msgTable.reqPolicyNotApplied
            }
            else{
                # All required policies are applied
                $Comment += ' ' + $msgTable.reqPolicyApplied

                # PBMM is applied and not excluded. Testing if specific policies haven't been excluded.
                $policyExemptionList = Test-PolicyExemptionExists -ScopeId $tempId -requiredPolicyExemptionIds $requiredPolicyExemptionIds

                $exemptList = $policyExemptionList.exemptionId
                # $nonExemptList = $policyExemptionList | Where-Object { $_.isExempt -eq $false }
                if ($ExemptList.Count -gt 0){   
                    
                    # join all exempt policies to a string
                    if(-not($null -eq $exemptList)){
                        $exemptListAllPolicies = $exemptList -join ", "
                    }
                    # boolean, exemption for GR, required policies exists.
                    $ComplianceStatus=$false
                    $Comment += ' ' + $msgTable.grExemptionFound -f $exemptListAllPolicies

                }
                else {
                    # Required Policy Definitions are not exempt. 
                    $Comment += ' ' + $msgTable.grExemptionNotFound
                    $ComplianceStatus=$true
                }
            }
        }

        if ($ComplianceStatus) {
            $Comment = $msgTable.isCompliant + ' ' + $Comment
        }
        else {
            $Comment = $msgTable.isNotCompliant + ' ' + $Comment
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
                $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $obj.Id
            } else {
                $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
            }
            
            if (!$evalResult.ShouldEvaluate) {
                if(!$evalResult.ShouldAvailable ){
                    if ($evalResult.Profile -gt 0) {
                        $c.ComplianceStatus = "Not Available"
                        $c | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                        $c.Comments = "Not available - Profile $($evalResult.Profile) not applicable for this guardrail"
                    } else {
                        $ErrorList.Add("Error occurred while evaluating profile configuration availability")
                    }
                } else {
                    if ($evalResult.Profile -gt 0) {
                        $c.ComplianceStatus = "Not Applicable"
                        $c | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                        $c.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
                    } else {
                        $ErrorList.Add("Error occurred while evaluating profile configuration")
                    }
                }
            } else {
                
                $c | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
            }
        }        
        $tempObjectList.add($c)| Out-Null
    }
    return $tempObjectList
}

function Verify-SecureConnectionInTransit {
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
    $grRequiredPolicies=@("OnlySecureConnectionsToYourRedisCacheShouldBeEnabled","SecureTransferToStorageAccountsShouldBeEnabled")

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

