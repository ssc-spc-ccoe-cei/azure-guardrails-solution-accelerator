targetScope = 'resourceGroup'

// A separate deployment makes the Automation Account's principal ID available
// as an input before Azure evaluates the role assignment name.
param automationAccountMSI string

var tagContributorRoleId = '4a9ae827-6dc8-4573-8ac7-8239d42aa03f'

// Include the principal in the name so a recreated identity gets its own
// assignment instead of trying to change the principal on an old assignment.
// This grants the backend permission to repair tags only within the CaC RG.
resource mandatoryTagRepairRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, automationAccountMSI, tagContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', tagContributorRoleId)
    principalId: automationAccountMSI
    principalType: 'ServicePrincipal'
  }
}
