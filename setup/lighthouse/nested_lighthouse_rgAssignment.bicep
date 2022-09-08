param msdRegistrationId string
param mspAssignmentName string

resource variables_mspAssignmentName_resource 'Microsoft.ManagedServices/registrationAssignments@2019-06-01' = {
  name: mspAssignmentName
  properties: {
    registrationDefinitionId: msdRegistrationId
  }
}
