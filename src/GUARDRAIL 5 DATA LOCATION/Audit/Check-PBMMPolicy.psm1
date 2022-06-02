function new-customObject {
    param (
        [string] $Type,
        [string] $Id,
        [string] $Name,
        [string] $DisplayName,
        [string] $CtrlName,
        [bool] $ComplianceStatus,
        [string] $Comments,
        [string] $ItemName,
        [string] $test,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime
    )
    $tempObject=[PSCustomObject]@{ 
        Type = $Type
        Id= $Id
        Name = $Name
        DisplayName = $DisplayName
        ComplianceStatus = $ComplianceStatus
        Comments = $Comments
        ItemName = $ItemName
        ControlName = $CtrlName
        ReportTime = $ReportTime
    }
    return $tempObject
}
function update-object 
{
    param (
        [Object] $object, [string] $comments, [string] $ControlName, [string] $ItemName, [bool] $ComplianceStatus,
        [string] $ReportTime
    )

    $object | Add-Member -MemberType NoteProperty -Name Comments -Value $comments
    $object | Add-Member -MemberType NoteProperty -Name "ComplianceStatus" -Value $ComplianceStatus
    $object | Add-Member -MemberType NoteProperty -Name ControlName -Value $ControlName -Force   
    $object | Add-Member -MemberType NoteProperty -Name ItemName -Value $ItemName -Force
    $object | Add-Member -MemberType NoteProperty -Name ReportTime -Value $ReportTime -Force
    return $object
}
function Test-ExemptionExists {
    param (
        [object] $object,
        [string] $ControlName,
        [string] $ItemName,
        [string] $ScopeId,
        [array]  $requiredPolicyExemptionIds,
        [string] $ReportTime
    )
    $newObject=new-customObject -Type $object.Type -Name $object.Name -DisplayName $object.DisplayName `
    -Id $object.Id -ComplianceStatus $true -Comments "" -ItemName $ItemName  `
    -CtrlName $ControlName -ReportTime $ReportTime
    $exemptionsIds=(Get-AzPolicyExemption -Scope $ScopeId).Properties.PolicyDefinitionReferenceIds
    if ($null -ne $exemptionsIds)
    {
        foreach ($exemptionId in $exemptionsIds)
        {
            if ($exemptionId -in $requiredPolicyExemptionIds)
            {
                $newObject.ComplianceStatus=$false
                $newObject.Comments+="Exemption for $exemptionId found."
            }
        }
    }
    else {
        $newObject.Comments="No exemptions found."
    }
    return $newObject
}

function Verify-PBMMPolicy {
    param (
            [string] $ControlName,
            [string] $CtrName6,
            [string] $CtrName7,
            [string]$ItemName,
            [string]$ItemName6, 
            [string]$ItemName7, 
            [string] $PolicyID, `
            [string] $WorkSpaceID,
            [string] $workspaceKey,
            [string] $LogType,
            [Parameter(Mandatory=$true)]
            [string]
            $ReportTime,
            [Parameter(Mandatory=$true)]
            [string]
            $CBSSubscriptionName
    )
    [System.Object] $RootMG = $null
    [string] $PolicyID = $policyID
    [PSCustomObject] $MGList = New-Object System.Collections.ArrayList
    [PSCustomObject] $MGItems = New-Object System.Collections.ArrayList
    [PSCustomObject] $SubscriptionList = New-Object System.Collections.ArrayList
    [PSCustomObject] $CompliantList = New-Object System.Collections.ArrayList
    [PSCustomObject] $NonCompliantList = New-Object System.Collections.ArrayList
    [string] $Comment1 = "The Policy or Initiative is not assigned to the "
    [string] $Comment2 = " is excluded from the scope of the assignment"
    [string] $Comment3 = "Compliant"
    [string] $Comment4 = "The Policy or Initiative is not assigned on the Root Management Groups"
    [string] $Comment5="This Root Management Groups is excluded from the scope of the assignment"
    [string] $Comment6="PBMM Initiative is not applied."

    $gr6RequiredPolicies=@("TransparentDataEncryptionOnSqlDatabasesShouldBeEnabled","DiskEncryptionShouldBeAppliedOnVirtualMachines")
    $gr7RequiredPolicies=@("FunctionAppShouldOnlyBeAccessibleOverHttps","WebApplicationShouldOnlyBeAccessibleOverHttps", "ApiAppShouldOnlyBeAccessibleOverHttps", "OnlySecureConnectionsToYourRedisCacheShouldBeEnabled","SecureTransferToStorageAccountsShouldBeEnabled")
    
    #Code Starts
    foreach ($mg in Get-AzManagementGroup) {
        $MG = Get-AzManagementGroup -GroupName $mg.Name -Expand -Recurse
        $MGItems.Add($MG)
        if ($null -eq $MG.ParentId) {
            $RootMG = $MG
        }
    }
    foreach ($items in $MGItems) {
        foreach ($Children in $items.Children ) {
            foreach ($c in $Children) {
                Write-Output "Children: $($c.DisplayName)"
                if ($c.Type -eq "/subscriptions" -and (-not $SubscriptionList.Contains($c)) -and $c.DisplayName -ne $CBSSubscriptionName) {
                    [string]$type = "subscription"
                    $SubscriptionList.Add($c)
                    $AssignedPolicyList = Get-AzPolicyAssignment -scope $c.Id -PolicyDefinitionId $PolicyID
                    If ($null -eq $AssignedPolicyList) {
                        $c=new-customObject -Type $c.Type -Id $c.Id -Name $c.Name `
                        -DisplayName $c.DisplayName `
                        -ComplianceStatus $false `
                        -Comments "$Comment1$type" `
                        -ItemName $ItemName `
                        -CtrlName $ControlName -ReportTime $ReportTime
                        $NonCompliantList.add($c)
                        # the lines below create an entry for modules 6 and 7
                        $GR6Object = new-customObject -Type $c.Type -Id $c.Id -Name $c.Name `
                            -DisplayName $c.DisplayName -ComplianceStatus $false `
                            -Comments $Comment6 `
                            -ItemName $ItemName6 `
                            -CtrlName $CtrName6 -ReportTime $ReportTime
                        $NonCompliantList.add($GR6Object)
                        $GR7Object = new-customObject -Type $c.Type -Id $c.Id -Name $c.Name `
                            -DisplayName $c.DisplayName `
                            -ComplianceStatus $false `
                            -Comments $Comment6 `
                            -ItemName $ItemName7 `
                            -CtrlName $CtrName7 -ReportTime $ReportTime
                        $NonCompliantList.add($GR7Object)
                    }
                    elseif (-not ([string]::IsNullOrEmpty(($AssignedPolicyList.Properties.NotScopesScope)))) {
                        $c=new-customObject -Type $c.Type -Id $c.Id -Name $c.Name `
                        -DisplayName $c.DisplayName `
                        -ComplianceStatus $false `
                        -Comments "$Comment1$type" `
                        -ItemName $ItemName `
                        -CtrlName $ControlName -ReportTime $ReportTime
                        $NonCompliantList.add($c)  
                        # the lines below create an entry for modules 6 and 7
                        $GR6Object = new-customObject -Type $c.Type -Id $c.Id -Name $c.Name `
                            -DisplayName $c.DisplayName -ComplianceStatus $false `
                            -Comments $Comment6 `
                            -ItemName $ItemName6 `
                            -CtrlName $CtrName6 -ReportTime $ReportTime
                        $NonCompliantList.add($GR6Object)
                        $GR7Object = new-customObject -Type $c.Type -Id $c.Id -Name $c.Name `
                            -DisplayName $c.DisplayName `
                            -ComplianceStatus $false `
                            -Comments $Comment6 `
                            -ItemName $ItemName7 `
                            -CtrlName $CtrName7 -ReportTime $ReportTime
                        $NonCompliantList.add($GR7Object)
                    }
                    else {
                        $c=new-customObject -Type $c.Type -Id $c.Id -Name $c.Name `
                        -DisplayName $c.DisplayName `
                        -ComplianceStatus $true `
                        -CtrlName $ControlName `
                        -Comments $Comment3 `
                        -ItemName $ItemName `
                        -Test $ControlName -ReportTime $ReportTime
                        $CompliantList.add($c) # it has PBMM, fine, but has anything been exempted and is related to GR6 or GR7?
                        #At this point the PBMM Initiative has been found and is applied at that scope.
                        #The funcion tests and updates the object with the proper status and control name.
                        $c2=Test-ExemptionExists -object $c -ControlName $CtrName6 -ItemName $ItemName6 `
                        -ScopeId $c.Id -requiredPolicyExemptionIds $gr6RequiredPolicies -ReportTime $ReportTime
                        if ($c2.ComplianceStatus)
                        {
                            $CompliantList.add($c2)
                        }
                        else {
                            $NonCompliantList.add($c2) 
                        }
                        $c3=Test-ExemptionExists -object $c -ControlName $CtrName7 -ItemName $ItemName7 `
                        -ScopeId $c.Id -requiredPolicyExemptionIds $gr7RequiredPolicies -ReportTime $ReportTime
                        if ($c3.ComplianceStatus)
                        {
                            $CompliantList.add($c3)
                        }
                        else {
                            $NonCompliantList.add($c3) 
                        }
                    }
                }
                elseif ($c.Type -like "*managementGroups*" -and (-not $MGList.Contains($c)) ) {
                    [string]$type = "Management Groups"
                    $MGList.Add($c)
                    $AssignedPolicyList = Get-AzPolicyAssignment -scope $C.Id -PolicyDefinitionId $PolicyID
                    If ($null -eq $AssignedPolicyList) {
                        $c=new-customObject -Type $c.Type -Id $c.Id -Name $c.Name -DisplayName $c.DisplayName `
                        -CtrlName $ControlName `
                        -ComplianceStatus $false `
                        -ItemName $ItemName `
                        -Comments "$Comment1$type" `
                        -ReportTime $ReportTime
                        $NonCompliantList.add($c)
                        # the lines below create an entry for modules 6 and 7
                        $GR6Object=new-customObject -Type $c.Type -Id $c.Id -Name $c.Name `
                        -DisplayName $c.DisplayName `
                        -ComplianceStatus $false `
                        -Comments $Comment6 `
                        -ItemName $ItemName6 `
                        -CtrlName $CtrName6 -ReportTime $ReportTime
                        $NonCompliantList.add($GR6Object)
                        $GR7Object=new-customObject -Type $c.Type -Id $c.Id -Name $c.Name `
                        -DisplayName $c.DisplayName `
                        -ComplianceStatus $false `
                        -Comments $Comment6 `
                        -ItemName $ItemName7 `
                        -CtrlName $CtrName7 -ReportTime $ReportTime
                        $NonCompliantList.add($GR7Object)
                    }
                    elseif (-not ([string]::IsNullOrEmpty(($AssignedPolicyList.Properties.NotScopesScope)))) {
                        $c=new-customObject -Type $c.Type -Id $c.Id -Name $c.Name -DisplayName $c.DisplayName `
                        -CtrlName $ControlName `
                        -ComplianceStatus $false `
                        -ItemName $ItemName `
                        -Comments "$type$Comment2" `
                        -ReportTime $ReportTime
                        $NonCompliantList.add($c)
                        # the lines below create an entry for modules 6 and 7
                        $GR6Object=new-customObject -Type $c.Type -Id $c.Id -Name $c.Name `
                        -DisplayName $c.DisplayName `
                        -ComplianceStatus $false `
                        -Comments $Comment6 `
                        -ItemName $ItemName6 `
                        -CtrlName $CtrName6 -ReportTime $ReportTime
                        $NonCompliantList.add($GR6Object)
                        $GR7Object=new-customObject -Type $c.Type -Id $c.Id -Name $c.Name `
                        -DisplayName $c.DisplayName -ComplianceStatus $false `
                        -Comments $Comment6 `
                        -ItemName $ItemName7 `
                        -CtrlName $CtrName7 -ReportTime $ReportTime
                        $NonCompliantList.add($GR7Object)
                    }
                    else {       
                        $c=new-customObject -Type $c.Type -Id $c.Id -Name $c.Name -DisplayName $c.DisplayName `
                        -CtrlName $ControlName `
                        -ComplianceStatus $true `
                        -ItemName $ItemName `
                        -Comments $Comment3 `
                        -ReportTime $ReportTime
                        $CompliantList.add($c)
                        # it has PBMM, fine, but has anything been exempted and is related to GR6 or GR7?
                        #At this point the PBMM Initiative has been found and is applied at that scope.
                        #The funcion tests and updates the object with the proper status and control name.
                        $c2=Test-ExemptionExists -object $c -ControlName $CtrName6 -ItemName $ItemName6 `
                        -ScopeId $c.Id -requiredPolicyExemptionIds $gr6RequiredPolicies -ReportTime $ReportTime
                        if ($c2.ComplianceStatus)
                        {
                            $CompliantList.add($c2)
                        }
                        else {
                            $NonCompliantList.add($c2) 
                        }
                        $c3=Test-ExemptionExists -object $c -ControlName $CtrName7 -ItemName $ItemName7 `
                        -ScopeId $c.Id -requiredPolicyExemptionIds $gr7RequiredPolicies -ReportTime $ReportTime
                        if ($c3.ComplianceStatus)
                        {
                            $CompliantList.add($c3)
                        }
                        else {
                            $NonCompliantList.add($c3) 
                        } 
                    }
                }
            }                
        }
    }
    $AssignedPolicyList = Get-AzPolicyAssignment -scope $RootMG.Id -PolicyDefinitionId $PolicyID
    If ($null -eq $AssignedPolicyList) {
        Write-Output "RootMG: $($RootMG.DisplayName)"
        $RootMG2=new-customObject -Type $RootMG.Type -Id $RootMG.Id -Name $RootMG.Name -DisplayName $RootMG.DisplayName `
        -comments $Comment4 -CtrlName $ControlName -ComplianceStatus $false -ItemName $ItemName -ReportTime $ReportTime
        $NonCompliantList.add($RootMG2)
        # the lines below create an entry for modules 6 and 7
        $GR6Object=new-customObject -Type $RootMG.Type -Id $RootMG.Id -Name $RootMG.Name -DisplayName $RootMG.DisplayName `
        -ComplianceStatus $false -Comments $Comment6 -ItemName $ItemName6 `
        -CtrlName $CtrName6 -ReportTime $ReportTime
        $NonCompliantList.add($GR6Object)
        $GR7Object=new-customObject -Type $RootMG.Type -Id $RootMG.Id -Name $RootMG.Name -DisplayName $RootMG.DisplayName `
        -ComplianceStatus $false -Comments $Comment6 -ItemName $ItemName7 `
        -CtrlName $CtrName7 -ReportTime $ReportTime
        $NonCompliantList.add($GR7Object)
    }
    elseif (-not ([string]::IsNullOrEmpty(($AssignedPolicyList.Properties.NotScopesScope)))) {
        $RootMG2=new-customObject -Type $RootMG.Type -Id $RootMG.Id -Name $RootMG.Name -DisplayName $RootMG.DisplayName `
        -comments $Comment5 -CtrlName $ControlName -ComplianceStatus $false -ItemName $ItemName -ReportTime $ReportTime
        $NonCompliantList.add($RootMG2)
        # the lines below create an entry for modules 6 and 7
        $GR6Object=new-customObject -Type $RootMG.Type -Id $RootMG.Id -Name $RootMG.Name -DisplayName $RootMG.DisplayName `
        -ComplianceStatus $false -Comments $Comment6 -ItemName $ItemName6 `
        -CtrlName $CtrName6 -ReportTime $ReportTime
        $NonCompliantList.add($GR6Object)
        $GR7Object=new-customObject -Type $RootMG.Type -Id $RootMG.Id -Name $RootMG.Name -DisplayName $RootMG.DisplayName `
        -ComplianceStatus $false -Comments $Comment6 -ItemName $ItemName7 `
        -CtrlName $CtrName7 -ReportTime $ReportTime
        $NonCompliantList.add($GR7Object)
    }
    else {       
        $RootMG1=new-customObject -Type $RootMG.Type -Id $RootMG.Id -Name $RootMG.Name -DisplayName $RootMG.DisplayName `
        -comments $Comment3 -CtrlName $ControlName -ComplianceStatus $true -ItemName $ItemName -ReportTime $ReportTime
        $CompliantList.add($RootMG1) 
        # add detection of exemptions
        $RootMG2=Test-ExemptionExists -object $RootMG -ControlName $CtrName6 -ItemName $ItemName6 `
        -ScopeId $RootMG -requiredPolicyExemptionIds $gr6RequiredPolicies -ReportTime $ReportTime
        if ($RootMG2.ComplianceStatus)
        {
            $CompliantList.add($RootMG2)
        }
        else {
            $NonCompliantList.add($RootMG2) 
        }
        $RootMG3=Test-ExemptionExists -object $RootMG -ControlName $CtrName7 -ItemName $ItemName6 `
        -ScopeId $RootMG.Id -requiredPolicyExemptionIds $gr7RequiredPolicies -ReportTime $ReportTime
        if ($RootMG3.ComplianceStatus)
        {
            $CompliantList.add($RootMG3)
        }
        else {
            $NonCompliantList.add($RootMG3) 
        }
    }
    #$CompliantList
    "Compliant list"
    $CompliantList | convertto-json -Depth 3
    if ($CompliantList.Count -gt 0)
    {
        $JsonObject = $CompliantList | convertTo-Json -Depth 3
        #"Compliant List"
        #$JsonObject
        Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
        -sharedkey $workspaceKey `
        -body $JsonObject `
        -logType $LogType `
        -TimeStampField Get-Date
    }
    "Non compliant list"
    $NonCompliantList | ConvertTo-Json -Depth 3
    if ($NonCompliantList.Count -gt 0)
    {
        $JsonObject = $NonCompliantList | convertTo-Json -Depth 3 
        #"NonCompliant List"
        #$NonCompliantList
        #"Json"
        #$JsonObject
        Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
            -sharedkey $workspaceKey `
            -body $JsonObject `
            -logType $LogType `
            -TimeStampField Get-Date
    }
}
