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
                name: 'CurrentVersion_s'
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

module alertNewVersion 'modules/alert.bicep' = {
    name: 'guardrails-alertNewVersion'
    dependsOn: [
      featuresTable
    ]
    params: {
      alertRuleDescription: 'Alerts when a new version of the Guardrails Solution Accelerator is available'
      alertRuleName: 'GuardrailsNewVersion'
      alertRuleDisplayName: 'Guardrails New Version Available.'
      alertRuleSeverity: 3
      location: location
      query: 'GR_VersionInfo_CL | summarize total=count() by UpdateAvailable=iff(CurrentVersion_s != AvailableVersion_s, "Yes",\'No\') | where UpdateAvailable == \'Yes\''
      scope: lawId
      autoMitigate: true
      evaluationFrequency: 'PT6H'
      windowSize: 'PT6H'
    }
  }
