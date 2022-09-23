targetScope = 'managementGroup'

@description('MSI ID of the Guardrails Azure Automation account - ex: 160c3c00-2e1b-4bea-9734-30031357f46c')
param guardrailsAutomationAccountMSI string
@description('Role definition ID of the custom role created to grant the AA permissions to register the Lighthouse resource provider')
param lighthouseRegisterRPRoleDefinitionID string

var roleAssignmentGUIDRandom = '5de3f84b-8866-4432-8811-24859ccf8146'

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: roleAssignmentGUIDRandom
  properties: {
    principalId: guardrailsAutomationAccountMSI
    roleDefinitionId: lighthouseRegisterRPRoleDefinitionID
    description: 'Permission for the Guardrails Azure Automation account to register the Lighthouse resource provider'
  }
}

output policyAssignmentMSIRoleAssignmentID string = roleAssignment.id
