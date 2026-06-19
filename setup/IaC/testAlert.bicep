var location = 'Canada Central'
var lawId='/subscriptions/6c64f9ed-88d2-4598-8de6-7a9527dc16ca/resourceGroups/Guardrails-6eb08c2c/providers/Microsoft.OperationalInsights/workspaces/guardrails-6eb08c2c'


var parentname = split(lawId, '/')[8]

resource featuresTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  name: '${parentname}/GR_VersionInfo_CL'
  properties: {
    totalRetentionInDays: 31
    plan: 'Analytics'
    schema: {
        name: 'GR_VersionInfo_CL'
        columns: [
            {
                name: 'DeployedVersion_s'
                type: 'string'
            }
            {
                name: 'AvailableVersion_s'
                type: 'string'
            }
            {
              name: 'ReportTime_s'
              type: 'string'
            }
            {
              name: 'UpdateNeeded_b'
              type: 'bool'
            }
        ]
    }
    retentionInDays: 31
  }  
}


