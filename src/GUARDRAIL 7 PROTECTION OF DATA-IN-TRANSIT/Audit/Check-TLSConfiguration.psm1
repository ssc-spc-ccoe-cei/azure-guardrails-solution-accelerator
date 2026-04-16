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

    $ObjectList = New-Object System.Collections.ArrayList
    $ErrorList = New-Object System.Collections.ArrayList


    # Define required policies based on ItemName
    $grRequiredPolicies = @()
    
    switch ($ItemName) {
        $msgTable.appServiceTLSConfig {
            $grRequiredPolicies = @(
                "/providers/Microsoft.Authorization/policyDefinitions/f0e6e85b-9b9f-4a4b-b67b-f730d42f1b0b",
                "/providers/Microsoft.Authorization/policyDefinitions/817dcf37-e83d-4999-a472-644eada2ea1e",
                "/providers/Microsoft.Authorization/policyDefinitions/d6545c6b-dd9d-4265-91e6-0b451e2f1c50",
                "/providers/Microsoft.Authorization/policyDefinitions/4ee5b817-627a-435a-8932-116193268172"
            )
        }
        $msgTable.functionAppTLSConfig {
            $grRequiredPolicies = @(
                "/providers/Microsoft.Authorization/policyDefinitions/deb528de-8f89-4101-881c-595899253102",
                "/providers/Microsoft.Authorization/policyDefinitions/f9d614c5-c173-4d56-95a7-b4437057d193"
            )
        }
        $msgTable.sqlDbTLSConfig {
            $grRequiredPolicies = @(
                "/providers/Microsoft.Authorization/policyDefinitions/32e6bbec-16b6-44c2-be37-c5b672d103cf"
            )
        }
        $msgTable.appGatewayWAFConfig {
            $grRequiredPolicies = @(
                "/providers/Microsoft.Authorization/policyDefinitions/564feb30-bf6a-4854-b4bb-0d2d2d1e6c66"
            )
        }
    }

    $grParams = @{
        requiredPolicyIds      = $grRequiredPolicies
        ReportTime             = $ReportTime
        ItemName               = $ItemName
        msgTable               = $msgTable
        ControlName            = $ControlName
        itsgcode               = $itsgcode
        CloudUsageProfiles     = $CloudUsageProfiles
        ModuleProfiles         = $ModuleProfiles
        EnableMultiCloudProfiles = $EnableMultiCloudProfiles   # passes $false when not set
        ErrorList              = $ErrorList
    }


    $ObjectList.AddRange((Check-BuiltInPoliciesWithResourceGraph @grParams))
    
    # Filter out PSAzureContext objects
    $ObjectList_filtered = $ObjectList | Where-Object { $_.GetType() -notlike "*PSAzureContext*" }

    $moduleOutput = [PSCustomObject]@{
        ComplianceResults = $ObjectList_filtered
        Errors = $ErrorList
    }
    
    return $moduleOutput
}