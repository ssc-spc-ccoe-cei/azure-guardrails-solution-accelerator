param alertRuleName string
param alertRuleDisplayName string
param alertRuleDescription string
param scope string // log analytics workspace resource id
param alertRuleSeverity int
param location string
param windowSize string = 'PT15M'
param evaluationFrequency string = 'PT15M'
param autoMitigate bool = false
param query string

var parentname = split(scope, '/')[8]

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
            {
              name: 'TimeGenerated'
              type: 'datetime'
            }
        ]
    }
    retentionInDays: 31
  }  
}


resource rule 'Microsoft.Insights/scheduledQueryRules@2022-08-01-preview' = {
  location: location
  name: alertRuleName
  dependsOn: [
    featuresTable
  ]
  properties: {
    description: alertRuleDescription
    displayName: alertRuleDisplayName
    enabled: true
    scopes: [
      scope
    ]
    targetResourceTypes: [
      'Microsoft.OperationalInsights/workspaces'
    ]
    windowSize: windowSize
    evaluationFrequency: evaluationFrequency
    severity: alertRuleSeverity
    criteria: {
      allOf: [
          {
              query: query
              timeAggregation: 'Count'
              dimensions: []
              operator: 'GreaterThan'
              threshold: 0
              failingPeriods: {
                  numberOfEvaluationPeriods: 1
                  minFailingPeriodsToAlert: 1
              }
          }
      ]
    }
    autoMitigate: autoMitigate
  }
}
