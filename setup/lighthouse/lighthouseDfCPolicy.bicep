targetScope = 'managementGroup'

@description('Add the tenant id provided by the MSP')
param managedByTenantId string

@description('Add the tenant name of the provided MSP')
param managedByName string = 'Guardrails Accelerator'

@description('Add the description of the offer provided by the MSP')
param managedByDescription string = 'Guardrails Accelerator - Defender for Cloud Access'

@description('Add the authZ array provided by the MSP')
param managedByAuthorizations array

@description('Location - used for Policy Assignment resource')
param location string

var policyDefinitionName_var = 'deploy-gr-accel-dfc-rbac'
//var rbacUserAccessAdministrator = '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9'
var rbacOwner = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'

resource policyDefinition 'Microsoft.Authorization/policyDefinitions@2018-05-01' = {
  name: policyDefinitionName_var
  properties: {
    description: 'Deploy Guardrails Accelerator Subscription Defender for Cloud RBAC'
    displayName: 'Deploy Guardrails Accelerator Subscription Defender for Cloud RBAC'
    mode: 'All'
    policyType: 'Custom'
    parameters: {
      managedByTenantId: {
        type: 'string'
        defaultValue: managedByTenantId
        metadata: {
          description: 'Add the tenant id provided by the MSP'
        }
      }
      managedByName: {
        type: 'string'
        defaultValue: managedByName
        metadata: {
          description: 'Add the tenant name of the provided MSP'
        }
      }
      managedByDescription: {
        type: 'string'
        defaultValue: managedByDescription
        metadata: {
          description: 'Add the description of the offer provided by the MSP'
        }
      }
      managedByAuthorizations: {
        type: 'array'
        defaultValue: managedByAuthorizations
        metadata: {
          description: 'Add the authZ array provided by the MSP'
        }
      }
    }
    policyRule: {
      if: {
        allOf: [
          {
            field: 'type'
            equals: 'Microsoft.Resources/subscriptions'
          }
        ]
      }
      then: {
        effect: 'deployIfNotExists'
        details: {
          type: 'Microsoft.ManagedServices/registrationDefinitions'
          deploymentScope: 'Subscription'
          existenceScope: 'Subscription'
          roleDefinitionIds: [
            '/providers/Microsoft.Authorization/roleDefinitions/${rbacOwner}'
          ]
          existenceCondition: {
            allOf: [
              {
                field: 'type'
                equals: 'Microsoft.ManagedServices/registrationAssignments'
              }
              {
                field: 'Microsoft.ManagedServices/registrationAssignments/registrationDefinition.managedByTenantId'
                equals: '[parameters(\'managedByTenantId\')]'
              }
              {
                count: {
                  field: 'Microsoft.ManagedServices/registrationAssignments/registrationDefinition.authorizations[*]'
                  where: {
                    allOf: [
                      {
                        field: 'Microsoft.ManagedServices/registrationAssignments/registrationDefinition.authorizations[*].principalId'
                        equals: managedByAuthorizations[1].principalId
                      }
                      {
                        field: 'Microsoft.ManagedServices/registrationAssignments/registrationDefinition.authorizations[*].roleDefinitionId'
                        equals: managedByAuthorizations[1].roleDefinitionId
                      }
                    ]
                  }
                }
                greater: 0
              }
            ]
          }
          deployment: {
            location: location
            properties: {
              mode: 'incremental'
              parameters: {
                managedByTenantId: {
                  value: '[parameters(\'managedByTenantId\')]'
                }
                managedByName: {
                  value: '[parameters(\'managedByName\')]'
                }
                managedByDescription: {
                  value: '[parameters(\'managedByDescription\')]'
                }
                managedByAuthorizations: {
                  value: '[parameters(\'managedByAuthorizations\')]'
                }
              }
              template: {
                '$schema': 'https://schema.management.azure.com/2018-05-01/subscriptionDeploymentTemplate.json#'
                contentVersion: '1.0.0.0'
                parameters: {
                  managedByTenantId: {
                    type: 'string'
                  }
                  managedByName: {
                    type: 'string'
                  }
                  managedByDescription: {
                    type: 'string'
                  }
                  managedByAuthorizations: {
                    type: 'array'
                  }
                }
                variables: {
                  managedByRegistrationName: '[guid(parameters(\'managedByName\'))]'
                  managedByAssignmentName: '[guid(parameters(\'managedByName\'))]'
                }
                resources: [
                  {
                    type: 'Microsoft.ManagedServices/registrationDefinitions'
                    apiVersion: '2019-06-01'
                    name: '[variables(\'managedByRegistrationName\')]'
                    properties: {
                      registrationDefinitionName: '[parameters(\'managedByName\')]'
                      description: '[parameters(\'managedByDescription\')]'
                      managedByTenantId: '[parameters(\'managedByTenantId\')]'
                      authorizations: '[parameters(\'managedByAuthorizations\')]'
                    }
                  }
                  {
                    type: 'Microsoft.ManagedServices/registrationAssignments'
                    apiVersion: '2019-06-01'
                    name: '[variables(\'managedByAssignmentName\')]'
                    dependsOn: [
                      '[resourceId(\'Microsoft.ManagedServices/registrationDefinitions/\', variables(\'managedByRegistrationName\'))]'
                    ]
                    properties: {
                      registrationDefinitionId: '[resourceId(\'Microsoft.ManagedServices/registrationDefinitions/\',variables(\'managedByRegistrationName\'))]'
                    }
                  }
                ]
              }
            }
          }
        }
      }
    }
  }
}

resource policyAssignment 'Microsoft.Authorization/policyassignments@2021-06-01' = {
  name: policyDefinitionName_var
  identity: {
    type: 'SystemAssigned'
  }
  location: location
  properties: {
    description: 'Guardrails Accelerator Lightrails Permissions Deployment Assignment'
    displayName: 'Deploy Guardrails Accelerator Defender for Cloud RBAC'
    policyDefinitionId: policyDefinition.id

  }
}

resource remediationTask 'Microsoft.PolicyInsights/remediations@2021-10-01' = {
  name: '${policyAssignment.name}-remediation'
  scope: managementGroup()
  properties: {
    parallelDeployments: 10
    resourceCount: 500
    resourceDiscoveryMode: 'ExistingNonCompliant'
    failureThreshold: {
      percentage: 1
    }
    policyAssignmentId: policyAssignment.id
    policyDefinitionReferenceId: policyDefinition.id
  }
}

output policyAssignmentMSIRoleAssignmentID string = policyAssignment.identity.principalId
output policyAssignmentId string = policyAssignment.id
