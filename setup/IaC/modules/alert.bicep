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

resource rule 'Microsoft.Insights/scheduledQueryRules@2022-08-01-preview' = {
  location: location
  name: alertRuleName
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
    skipQueryValidation: true
    autoMitigate: autoMitigate
  }
}
