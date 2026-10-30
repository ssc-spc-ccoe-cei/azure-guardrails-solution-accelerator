function global:Check-PBMMPolicies {
    param($objList, $objType, $itsgcode, $requiredPolicyExemptionIds, $PolicyID, $ReportTime, $ItemName,
        $LogType, $msgTable, $ControlName, $CloudUsageProfiles, $ModuleProfiles,
        [switch]$EnableMultiCloudProfiles)
}
function global:Check-BuiltInPoliciesWithResourceGraph {
    param($requiredPolicyIds, $ReportTime, $ItemName, $msgTable, $ControlName, $itsgcode,
        $CloudUsageProfiles, $ModuleProfiles, [switch]$EnableMultiCloudProfiles, $ErrorList)
}
function global:Check-BuiltInPoliciesPerSubscription {
    param($requiredPolicyIds, $ReportTime, $ItemName, $msgTable, $ControlName, $itsgcode,
        $CloudUsageProfiles, $ModuleProfiles, [switch]$EnableMultiCloudProfiles, $ErrorList)
}
function global:add-documentFileExtensions { param($DocumentName, $ItemName) @("$($DocumentName[0]).pdf") }
function global:get-tagValue { param($tagKey, $object) $null }
function global:Invoke-GraphQueryEX { param($urlPath, $ErrorAction) }
function global:Add-ProfileInformation {
    param($Result, $CloudUsageProfiles, $ModuleProfiles, $SubscriptionId, $ErrorList)
    return $Result
}
function global:Hide-Email { param($email) return $email }

function global:Get-AzSubscription { param($ErrorAction) }
function global:Get-AzContext { param($Subscription) }
function global:Search-AzGraph { param($Query, $Subscription, $First, $SkipToken, $ErrorAction) }
function global:Select-AzSubscription { param($Subscription, $SubscriptionObject) }
function global:Set-AzContext { param($Subscription, $SubscriptionId, $ErrorAction) }
function global:Get-AzStorageAccount { param($ResourceGroupName, $Name, $ErrorAction) }
function global:Get-AzStorageBlob { param($Container, $Context, $Blob) }
function global:Get-AzStorageBlobContent { param($Container, $Blob, $Context, $Force) }
function global:Get-AzVirtualNetwork { }
function global:Get-AzVirtualNetworkSubnetConfig { param($VirtualNetwork) }
function global:Get-AzRouteTable { param($ResourceGroupName, $Name) }
function global:Get-AzNetworkWatcher { param($Location, $ErrorAction) }
function global:Get-AzResource { param($Name) }
function global:Get-AzMarketplacePrivateStore { param($ErrorAction) }
function global:Get-AzAccessToken { param($TenantId, $ErrorAction) }
function global:Get-AzRoleAssignment { param($RoleDefinitionId, $ErrorAction) }
function global:Get-AzFirewall { param($ErrorAction) }
function global:Get-AzVM { param($ErrorAction) }
function global:Get-AzApplicationGateway { param($ErrorAction) }
function global:Get-AzSecurityPricing { }

function global:Reset-UnitTestHelpers {
    @(
        'Check-PBMMPolicies', 'Check-BuiltInPoliciesWithResourceGraph',
        'Check-BuiltInPoliciesPerSubscription', 'add-documentFileExtensions',
        'get-tagValue', 'Invoke-GraphQueryEX', 'Add-ProfileInformation',
        'Hide-Email', 'Get-AzSubscription', 'Get-AzContext', 'Search-AzGraph',
        'Select-AzSubscription', 'Set-AzContext', 'Get-AzStorageAccount',
        'Get-AzStorageBlob', 'Get-AzStorageBlobContent', 'Get-AzVirtualNetwork',
        'Get-AzVirtualNetworkSubnetConfig', 'Get-AzRouteTable', 'Get-AzNetworkWatcher',
        'Get-AzResource', 'Get-AzMarketplacePrivateStore', 'Get-AzAccessToken',
        'Get-AzRoleAssignment', 'Get-AzFirewall', 'Get-AzVM',
        'Get-AzApplicationGateway', 'Get-AzSecurityPricing'
    ) | ForEach-Object { Remove-Item "Function:\$_" -ErrorAction SilentlyContinue }
    Remove-Item Function:\Reset-UnitTestHelpers -ErrorAction SilentlyContinue
}
