function Verify-TLSConfiguration {
    param (
        [string] $ControlName,
        [string] $ItemName,
        [string] $itsgcode,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string] $ReportTime,
        [string] $ModuleProfiles,
        [string] $CloudUsageProfiles = "3",
        [switch] $EnableMultiCloudProfiles
    )

    [PSCustomObject] $ObjectList = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    
    # Define required policies based on ItemName
    $grRequiredPolicies = @()
    
    switch ($ItemName) {
        "App Service TLS Configuration" {
            $grRequiredPolicies = @(
                "/providers/Microsoft.Authorization/policyDefinitions/f0e6e85b-9b9f-4a4b-b67b-f730d42f1b0b",
                "/providers/Microsoft.Authorization/policyDefinitions/817dcf37-e83d-4999-a472-644eada2ea1e",
                "/providers/Microsoft.Authorization/policyDefinitions/d6545c6b-dd9d-4265-91e6-0b451e2f1c50"
            )
        }
        "Function App TLS Configuration" {
            $grRequiredPolicies = @(
                "/providers/Microsoft.Authorization/policyDefinitions/fa3a6357-c6d6-4120-8429-855577ec0063",
                "/providers/Microsoft.Authorization/policyDefinitions/1f01f1c7-539c-49b5-9ef4-d4ffa37d22e0"
            )
        }
        "Azure SQL Database TLS Configuration" {
            $grRequiredPolicies = @(
                "/providers/Microsoft.Authorization/policyDefinitions/32e6bbec-16b6-44c2-be37-c5b672d103cf"
            )
        }
        "Application Gateway WAF" {
            $grRequiredPolicies = @(
                "/providers/Microsoft.Authorization/policyDefinitions/564feb30-bf6a-4854-b4bb-0d2d2d1e6c66"
            )
        }
    }

    try {
        $objs = Get-AzSubscription -ErrorAction Stop | Where-Object {$_.State -eq "Enabled"}
    }
    catch {
        $ErrorList.Add("Failed to execute Get-AzSubscription command: $_")
        throw "Error: Failed to execute Get-AzSubscription command: $_"
    }

    [string]$type = "subscription"
    
    if ($EnableMultiCloudProfiles) {
        $ObjectList += Check-BuiltInPolicies -objList $objs -objType $type -requiredPolicyIds $grRequiredPolicies -ReportTime $ReportTime -ItemName $ItemName -msgTable $msgTable -ControlName $ControlName
    } else {
        $ObjectList += Check-BuiltInPolicies -objList $objs -objType $type -requiredPolicyIds $grRequiredPolicies -ReportTime $ReportTime -ItemName $ItemName -msgTable $msgTable -ControlName $ControlName
    }

    Write-Host "$type(s) compliance results are collected"
    
    # Filter out PSAzureContext objects
    $ObjectList_filtered = $ObjectList | Where-Object { $_.GetType() -notlike "*PSAzureContext*" }

    $moduleOutput = [PSCustomObject]@{
        ComplianceResults = $ObjectList_filtered
        Errors = $ErrorList
    }

    return $moduleOutput
}

function Check-BuiltInPolicies {
    param (
        [Parameter(Mandatory=$true)]
        $objList,
        [Parameter(Mandatory=$true)]
        [string]$objType,
        [Parameter(Mandatory=$true)]
        [array]$requiredPolicyIds,
        [Parameter(Mandatory=$true)]
        [string]$ReportTime,
        [Parameter(Mandatory=$true)]
        [string]$ItemName,
        [Parameter(Mandatory=$true)]
        [hashtable]$msgTable,
        [Parameter(Mandatory=$true)]
        [string]$ControlName
    )

    $results = New-Object System.Collections.ArrayList
    
    # Get tenant root management group
    $tenantId = (Get-AzContext).Tenant.Id
    $rootScope = "/providers/Microsoft.Management/managementGroups/$tenantId"

    foreach ($policyId in $requiredPolicyIds) {
        # Check for policy assignments at tenant level
        $tenantPolicyAssignment = Get-AzPolicyAssignment -Scope $rootScope | 
            Where-Object { $_.Properties.PolicyDefinitionId -eq $policyId }
        
        if ($tenantPolicyAssignment) {
            # Initialize an array to store all policy states
            $policyStates = @()
            $skipToken = $null
            
            do {
                # Get policy states with pagination
                if ($skipToken) {
                    $response = Get-AzPolicyState -PolicyDefinitionId $policyId -Top 1000 -SkipToken $skipToken
                } else {
                    $response = Get-AzPolicyState -PolicyDefinitionId $policyId -Top 1000
                }
                
                # Add current batch to results
                $policyStates += $response
                
                # Get skipToken for next batch if available
                $skipToken = $response.SkipToken | Select-Object -Last 1
            } while ($skipToken)

            # Filter for unique resources
            $policyStates = $policyStates | Sort-Object -Property ResourceId -Unique

            # If no resources are found that the policy applies to
            if ($null -eq $policyStates -or $policyStates.Count -eq 0) {
                $results.Add([PSCustomObject]@{
                    Type = $objType
                    Id = $tenantId
                    Name = "N/A"
                    DisplayName = "N/A"
                    ComplianceStatus = $true
                    Comments = "No applicable resources found. Policy is assigned at tenant level."
                    ItemName = $ItemName
                    ControlName = $ControlName
                    ReportTime = $ReportTime
                }) | Out-Null
                continue
            }

            # Check if any resources are non-compliant
            $nonCompliantResources = $policyStates | 
                Where-Object { $_.ComplianceState -eq "NonCompliant" -or $_.IsCompliant -eq $false }
            
            if ($nonCompliantResources) {
                foreach ($resource in $nonCompliantResources) {
                    $results.Add([PSCustomObject]@{
                        Type = $resource.ResourceType
                        Id = $resource.ResourceId
                        Name = $resource.ResourceGroup + "/" + ($resource.ResourceId -split '/')[-1]
                        DisplayName = $resource.ResourceGroup + "/" + ($resource.ResourceId -split '/')[-1]
                        ComplianceStatus = $false
                        Comments = $msgTable.policyNotCompliant
                        ItemName = $ItemName
                        ControlName = $ControlName
                        ReportTime = $ReportTime
                    }) | Out-Null
                }
            } else {
                $results.Add([PSCustomObject]@{
                    Type = $objType
                    Id = $tenantId
                    Name = "All Resources"
                    DisplayName = "All Resources"
                    ComplianceStatus = $true
                    Comments = $msgTable.policyCompliant
                    ItemName = $ItemName
                    ControlName = $ControlName
                    ReportTime = $ReportTime
                }) | Out-Null
            }
        } else {
            # Policy not assigned at tenant level
            $results.Add([PSCustomObject]@{
                Type = $objType
                Id = $tenantId
                Name = "N/A"
                DisplayName = "N/A"
                ComplianceStatus = $false
                Comments = $msgTable.policyNotConfigured
                ItemName = $ItemName
                ControlName = $ControlName
                ReportTime = $ReportTime
            }) | Out-Null
        }
    }

    return $results
} 