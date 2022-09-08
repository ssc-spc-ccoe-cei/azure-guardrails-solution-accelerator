targetScope = 'managementGroup'

@description('Principal ID of the MSI associated with the Deploy DfC Access Policy Assignment')
param policyAssignmentMSIPrincipalID string

var roleAssignmentGUIDRandom = '2cb8e1b1-fcf1-439e-bab7-b1b8b008c294'
var rbacOwner = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: roleAssignmentGUIDRandom
  properties: {
    principalId: policyAssignmentMSIPrincipalID
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/${rbacOwner}'
    description: 'Permission for the Policy Assignment managed identity to grant the Guardrails Lighthouse principal access to Defender for Cloud on each subscription'
  }
}

output policyAssignmentMSIRoleAssignmentID string = roleAssignment.id
