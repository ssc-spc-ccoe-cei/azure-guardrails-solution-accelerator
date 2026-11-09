# This file enables modules to be automatically managed by the Functions service.
# See https://aka.ms/functionsmanageddependency for additional information.
#
@{
    # For latest supported version, go to 'https://www.powershellgallery.com/packages/Az'. 
    # To use the Az module in your function app, please uncomment the line below.
    'Az.Accounts' = '5.5.3'
    'Az.ResourceGraph' = '1.2.1'
    'Az.OperationalInsights' = '3.3.0'
    # Az.KeyVault 6.6.1 or later is needed for the supported Key Vault management API; it requires Az.Accounts 5.5.3 or later.
    'Az.KeyVault' = '6.6.1'
}
