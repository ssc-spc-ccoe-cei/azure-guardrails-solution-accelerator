function Test-ExemptionExists {
    param (
        [string] $ScopeId,
        [array]  $requiredPolicyExemptionIds
    )
    $exemptionsIds=(Get-AzPolicyExemption -Scope $ScopeId).Properties.PolicyDefinitionReferenceIds
    if ($null -ne $exemptionsIds)
    {
        foreach ($exemptionId in $exemptionsIds)
        {
            if ($exemptionId -in $requiredPolicyExemptionIds)
            {
                return $true
            }
        }
    }
    else {
        return $false
    }
    
}

function Test-ComplianceForSubscription {
    param (
        [System.Object] $obj,
        [System.Object] $subscription,
        [string] $PolicyID,
        [array]  $requiredPolicyExemptionIds
    )
    Write-Host "Get compliance details for Subscription : $($subscription.DisplayName)"
    $complianceDetails = Get-AzPolicyState | Where-Object{ $_.SubscriptionId -eq $($subscription.SubscriptionID) } | Where-Object{ $_.PolicySetDefinitionName -eq $PolicyID}  
    
    If ($null -eq $complianceDetails) {
        Write-Host "No comliance details found for Management Group : $($obj.DisplayName) and subscription: $($subscription.DisplayName)"
    }
    else{   
        $complianceDetails = $complianceDetails | Where-Object{$_.PolicyAssignmentScope -like "*$($obj.TenantId)*" }
        $requiredPolicyExemptionIds_smallCaps = @()
        foreach ($str in $requiredPolicyExemptionIds) {
            $requiredPolicyExemptionIds_smallCaps += $str.ToLower()
        }
        # Filter for GR6 required policies
        $complianceDetails = $complianceDetails | Where-Object{ $_.PolicyDefinitionReferenceId -in $requiredPolicyExemptionIds_smallCaps}
        Write-Host "$($complianceDetails.count) Comliance details found for Management Group : $($obj.DisplayName) and subscription: $($subscription.DisplayName)"
    }


    return $complianceDetails
}

function Check-StatusDataAtRest {
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
        [string]
        $ReportTime
    )   
    [PSCustomObject] $tempObjectList = New-Object System.Collections.ArrayList

    foreach ($obj in $objList)
    {
        Write-Verbose "Checking $objType : $($obj.Name)"
        # Used for debugging
        if (!($PolicyID -like "/providers/microsoft.authorization/policysetdefinitions")) {
            $PolicyDefinitionID = "/providers/microsoft.authorization/policysetdefinitions/$PolicyID"
        }
        # Used for debugging
        Write-Host "PBMM policy PolicyDefinitionID is $PolicyDefinitionID" 
        Write-Host "PBMM policy PolicyID is $PolicyID"

        # Find scope
        if ($objType -eq "subscription"){
            $tempId="/subscriptions/$($obj.Id)"
        }
        else {
            $tempId=$obj.Id                              
        }
        Write-Host "Scope is $tempId for $($obj.Name)"
        
        # Find assigned policy list from PBMM policy for the scope

        # # Portal
        $AssignedPolicyList = Get-AzPolicyAssignment -scope $tempId -PolicyDefinitionId $PolicyID
        # # LocalExecution:
        # $AssignedPolicyList = Get-AzPolicyAssignment -scope $tempId -PolicyDefinitionId $PolicyDefinitionID
        If ($null -eq $AssignedPolicyList -or (-not ([string]::IsNullOrEmpty(($AssignedPolicyList.Properties.NotScopesScope)))))
        {
            $Comment=$msgTable.pbmmNotApplied 
            $ComplianceStatus=$false
        }
        else {
            $Comment = $msgTable.pbmmApplied
            #PBMM is applied and not excluded. Testing if specific policies haven't been excluded.
            if (Test-ExemptionExists -ScopeId $tempId -requiredPolicyExemptionIds $requiredPolicyExemptionIds)
            { # boolean, exemption for gr6 required policies exists.
                $ComplianceStatus=$false
                $Comment += $msgTable.grexemptionFound -f $obj.Id,$objType
            }
            else {
                # # No exemption exists. Find compliance details for the assigned PBMM policy
                
                # Check the number of resources and compliance status under required policies in applied PBMM
                if ($objType -eq "subscription"){
                    Write-Host "Subscription : $($obj.Name)"
                    $subscription = @()
                    $subscription += New-Object -TypeName psobject -Property ([ordered]@{'DisplayName'=$obj.Name;'SubscriptionID'=$obj.Id})
                    
                    $currentSubscription = Get-AzContext
                    if($currentSubscription -ne $subscription){
                        # Set Az context to the this subscription
                        Set-AzContext -SubscriptionId $subscription.SubscriptionID
                        Write-Host "AzContext set to $($subscription.DisplayName)"
                    }

                    # $complianceDetailsSubscription = (Get-AzPolicyState -SubscriptionId $($subscription.SubscriptionID) ) #| Where-Object{ $_.PolicySetDefinitionName -eq $PolicyID}
                    # $complianceDetailsSubscription = $complianceDetailsSubscription | Where-Object{ $_.PolicySetDefinitionName -eq $PolicyID}
                    $complianceDetailsSubscription = Test-ComplianceForSubscription -obj $obj -subscription $subscription -PolicyID $PolicyID -requiredPolicyExemptionIds $requiredPolicyExemptionIds
                    
                    # $complianceDetailsSubscription = $complianceDetailsSubscription | Where-Object{$_.PolicyAssignmentScope -like "*$($obj.TenantId)*" }
                    

                    $complianceDetailsList = $complianceDetailsSubscription | Select-Object `
                        Timestamp, ResourceId, ResourceLocation, ResourceType, SubscriptionId, `
                        ResourceGroup, PolicyDefinitionName, ManagementGroupIds, PolicyAssignmentScope, IsCompliant, `
                        ComplianceState, PolicyDefinitionAction, PolicyDefinitionReferenceId, ResourceTags, ResourceName
                }
                else {
                    Write-Host "Management Group : $($obj.Name)"
                    # get all subscription under this management group: $obj
                    $topLvlMgmtGrp =  $obj.Name        
                    $allSubscriptions = @()                   

                    # Collect data from managementgroups
                    $mgmtGroups = Get-AzManagementGroup -GroupId $topLvlMgmtGrp -Expand -Recurse

                    $children = $true
                    while ($children) {
                        $children = $false
                        $firstrun = $true
                        foreach ($entry in $mgmtGroups) {
                            if ($firstrun) {Clear-Variable mgmtGroups ; $firstrun = $false}
                            if ($entry.Children.length -gt 0) {
                                # Add management group to data that is being looped through
                                $children       = $true
                                $mgmtGroups    += $entry.Children
                            }
                            elseif ($entry.type -ne "Microsoft.Management/managementGroups") {
                                # Add subscription to output object
                                $allSubscriptions += New-Object -TypeName psobject -Property ([ordered]@{'DisplayName'=$entry.DisplayName;'SubscriptionID'=$entry.Name})
                            }
                        }
                    }

                    
                    $complianceDetailsList = @()
                    # [PSCustomObject] $complianceDetailsList = New-Object System.Collections.ArrayList
                    foreach ($subscription in $allSubscriptions) {
                        Write-Host "Subscription ID: $($subscription.SubscriptionId)"
                        
                        # Set context to the current subscription
                        Set-AzContext -SubscriptionId $subscription.SubscriptionID
                        Write-Host "AzContext set to $($subscription.DisplayName)"
                        $complianceDetailsSubscription = Test-ComplianceForSubscription -obj $obj -subscription $subscription -PolicyID $PolicyID -requiredPolicyExemptionIds $requiredPolicyExemptionIds
                        Write-Host "complianceDetailsSubscription count: $($complianceDetailsSubscription.count)"
                        
                        if ($null -eq $complianceDetailsSubscription) {
                            Write-Host "Compliance details for $($subscription.DisplayName) outputs as NULL"
                            $complianceDetailsList = $null
                        }
                        else{
                            $comD = $complianceDetailsSubscription | ForEach-Object {
                                [PSCustomObject]@{
                                    Timestamp                   = $_.Timestamp
                                    ResourceId                  = $_.ResourceId
                                    ResourceLocation            = $_.ResourceLocation
                                    ResourceType                = $_.ResourceType
                                    SubscriptionId              = $_.SubscriptionId
                                    ResourceGroup               = $_.ResourceGroup
                                    PolicyDefinitionName        = $_.PolicyDefinitionName
                                    ManagementGroupIds          = $_.ManagementGroupIds
                                    PolicyAssignmentScope       = $_.PolicyAssignmentScope
                                    IsCompliant                 = $_.IsCompliant
                                    ComplianceState             = $_.ComplianceState
                                    PolicyDefinitionAction      = $_.PolicyDefinitionAction
                                    PolicyDefinitionReferenceId = $_.PolicyDefinitionReferenceId
                                    ResourceTags                = $_.ResourceTags
                                    ResourceName                = $_.ResourceId
                            
                                }
                            }
                            Write-Host "comD count: $($comD.count)"
                            foreach($c in $comD){
                                [array]$complianceDetailsList += $c ## DEBUG THIS-not working
                            }
                            Write-Host " $($complianceDetailsList.count) complianceDetailsList count for Management Group $($obj.DisplayName) and subscription $($subscription.DisplayName)"
                        }
                    }
                    
                }

                if ($null -eq $complianceDetailsList) {
                    Write-Host "Check for compliance details; outputs as NULL"
                    $resourceCompliant = 0 ## DEBUG CHECK LATER
                }
                else{
                    # # check the compliant & non-compliant resources only for $requiredPolicyExemptionIds policies

                    # count compliant resource
                    $resourceCompliant = $complianceDetailsList | Where-Object {$_.ComplianceState -eq "Compliant" -and $_.ResourceName -ne $obj.Id}
                    $resourceIdResourceCompliant = $resourceCompliant.ResourceId | Select-Object -Unique
                    $policyResourceCompliant = $resourceCompliant.PolicyDefinitionReferenceId | Select-Object -Unique

                    # count non-compliant resources
                    $resourceNonCompliant = $complianceDetailsList | Where-Object {$_.ComplianceState -eq "NonCompliant" -and $_.ResourceName -ne $obj.Id}
                    $policyResourceNonCompliant = $resourceNonCompliant.PolicyDefinitionReferenceId | Select-Object -Unique
                    $resourceNonCompliantPolicyCount = $policyResourceNonCompliant.Count
                    # join all policies to a string
                    $resourceNonCompliantAllPolicies = $policyResourceNonCompliant -join ","
                }

                # find compliance status for this scope
                if ($null -eq $resourceNonCompliant.Count) {
                    $ComplianceStatus=$false
                    $Comment=$msgTable.isNullCompliantResource -f $PolicyId, $($obj.Name), $($obj.DisplayName)
                }
                elseif ($resourceNonCompliant.Count -eq 0) {
                    # all resources are compliant
                    $ComplianceStatus = $true
                    $Comment += ' ' + $msgTable.isCompliantResource -f $resourceIdResourceCompliant.Count, $policyResourceCompliant.Count
                }
                else {
                    # all or some resources are non-compliant
                    $ComplianceStatus = $false
                    $Comment += ' ' + $msgTable.isNotCompliantResource -f $resourceNonCompliantPolicyCount, $resourceNonCompliantAllPolicies, $resourceNonCompliant.Count
                }
            }
        }
        if ($null -eq $obj.DisplayName){
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

        $tempObjectList.add($c)| Out-Null
    }
    return $tempObjectList
}
function Verify-ProtectionDataAtRest {
    param (
            [string] $ControlName,
            [string]$ItemName,
            [string] $PolicyID, 
            [string] $itsgcode, 
            [hashtable] $msgTable,
            [Parameter(Mandatory=$true)]
            [string]
            $ReportTime,
            [Parameter(Mandatory=$false)]
            [string]
            $CBSSubscriptionName
    )
    [PSCustomObject] $ObjectList = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    $grRequiredPolicies=@("TransparentDataEncryptionOnSqlDatabasesShouldBeEnabled","DiskEncryptionShouldBeAppliedOnVirtualMachines","AuditUnrestrictedNetworkAccessToStorageAccounts","SecureTransferToStorageAccountsShouldBeEnabled")
    
    #Check management groups
    try {
        $objs = Get-AzManagementGroup -ErrorAction Stop
    }
    catch {
        $Errorlist.Add("Failed to execute the 'Get-AzManagementGroup' command--verify your permissions and the installion of `
            the Az.Resources module; returned error message: $_")
        throw "Error: Failed to execute the 'Get-AzManagementGroup' command--verify your permissions and the installion of the  `
            Az.Resources module; returned error message: $_"
    }
    [string]$type = "Management Group"  
    $ObjectList += Check-StatusDataAtRest -objList $objs -itsgcode $itsgcode -objType $type -requiredPolicyExemptionIds $grRequiredPolicies -PolicyID $PolicyID -ReportTime $ReportTime -ItemName $ItemName -LogType $LogType -msgTable $msgTable -ControlName $ControlName
    Write-Host "$type(s) compliance results are collected"

    #Check Subscriptions
    try {
        $objs = Get-AzSubscription -ErrorAction Stop| Where-Object {$_.State -eq "Enabled"} 
    }
    catch {
        $Errorlist.Add("Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of `
            the Az.Resources module; returned error message: $_")
        throw "Error: Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the `
            Az.Resources module; returned error message: $_"
    }
    [string]$type = "subscription"
    
    $ObjectList += Check-StatusDataAtRest -objList $objs -objType $type -itsgcode $itsgcode -requiredPolicyExemptionIds $grRequiredPolicies -PolicyID $PolicyID -ReportTime $ReportTime -ItemName $ItemName -LogType $LogType -msgTable $msgTable  -ControlName $ControlName
    Write-Host "$type(s) compliance results are collected"
    
    # Filter out objects of type PSAzureContext
    $ObjectList_filtered = $ObjectList | Where-Object { $_.GetType() -notlike "*PSAzureContext*" }

    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $ObjectList_filtered 
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }

    return $moduleOutput  
}

