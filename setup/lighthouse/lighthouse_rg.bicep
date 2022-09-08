targetScope = 'subscription'

@description('Specify a unique name for your offer')
param managedByName string = 'Guardrails Accelerator'

@description('Name of the Managed Service Provider offering')
param managedByDescription string = 'Guardrails Accelerator'

@description('Specify the tenant id of the Managed Service Provider')
param managedByTenantId string

@description('Specify an array of objects, containing tuples of Azure Active Directory principalId, a Azure roleDefinitionId, and an optional principalIdDisplayName. The roleDefinition specified is granted to the principalId in the provider\'s Active Directory and the principalIdDisplayName is visible to customers.')
param authorizations array
param rgName string

var mspRegistrationName_var = guid(managedByName)
var mspAssignmentName = guid(managedByName)

resource mspRegistrationName 'Microsoft.ManagedServices/registrationDefinitions@2019-06-01' = {
  name: mspRegistrationName_var
  properties: {
    registrationDefinitionName: managedByName
    description: managedByDescription
    managedByTenantId: managedByTenantId
    authorizations: authorizations
  }
}

module rgAssignment '../lighthouse/nested_lighthouse_rgAssignment.bicep' = {
  name: 'rgAssignment'
  scope: resourceGroup(rgName)
  params: {
    msdRegistrationId: mspRegistrationName.id
    mspAssignmentName: mspAssignmentName
  }
}

output managedByName string = 'Managed by ${managedByName}'
output authorizations array = authorizations
