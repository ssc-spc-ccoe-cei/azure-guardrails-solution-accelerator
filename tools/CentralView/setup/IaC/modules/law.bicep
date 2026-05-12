param subscriptionId string
param logAnalyticsWorkspaceName string
param rg string
param location string
param version string
param releaseDate string

@description('When true, skips creating GuardrailsTenantsCompliance_CL here and references an existing table (brownfield): avoids schema conflicts when the workspace already defines that table.')
param deferGuardrailsTenantsComplianceTableProvisioning bool = false

var wbConfig1 ='''
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 1,
      "content": {
        "json": "## SSC Central View\n---\n\nSelect a Department and Tenant to review results."
      },
      "name": "text - 2"
    },
    {
      "type": 9,
      "content": {
        "version": "KqlParameterItem/1.0",
        "parameters": [
          {
            "id": "4c3da7bc-165c-4edc-8fc3-0a0236f4b665",
            "version": "KqlParameterItem/1.0",
            "name": "Departments",
            "type": 2,
            "isRequired": true,
            "query": "let mrt=GuardrailsTenantsCompliance_CL | where TimeGenerated > ago(6h)| summarize mrt=max(ReportTime_s);\nGuardrailsTenantsCompliance_CL \n| where ReportTime_s == toscalar(mrt)\n| summarize by Department=DepartmentName_s//, [\"Dep. Number\"]=DepartmentNumber_s, TenantDomain_s\n| summarize by Department",
            "typeSettings": {
              "additionalResourceOptions": [],
              "showDefault": false
            },
            "timeContext": {
              "durationMs": 86400000
            },
            "queryType": 0,
            "resourceType": "microsoft.operationalinsights/workspaces",
            "value": null
          },
          {
            "id": "646611b4-e874-4008-8b32-0be7f94e1f82",
            "version": "KqlParameterItem/1.0",
            "name": "Tenants",
            "type": 2,
            "query": "let mrt=GuardrailsTenantsCompliance_CL \n| summarize mrt=max(ReportTime_s);\nGuardrailsTenantsCompliance_CL \n| where Status_s == \"Non-Compliant\" and ReportTime_s == toscalar(mrt) and DepartmentName_s == \"{Departments}\"\n| summarize sum(toint(Count_s)) by ControlName_s, TenantDomain_s\n| summarize by TenantDomain=TenantDomain_s\n",
            "typeSettings": {
              "additionalResourceOptions": [],
              "showDefault": false
            },
            "timeContext": {
              "durationMs": 86400000
            },
            "queryType": 0,
            "resourceType": "microsoft.operationalinsights/workspaces",
            "value": "fehsecorp.onmicrosoft.com"
          }
        ],
        "style": "pills",
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces"
      },
      "name": "parameters - 2"
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "let mrt=GuardrailsTenantsCompliance_CL \n    | summarize mrt=max(ReportTime_s);\nGuardrailsTenantsCompliance_CL \n| where Status_s == \"Non-Compliant\"\n    and ReportTime_s == toscalar(mrt)\n    and DepartmentName_s == '{Departments}'\n| summarize sum(toint(Count_s)) by ControlName_s, TenantDomain_s\n| summarize Total=round(1-todouble(count())/12,2)*100 by TenantDomain_s\n| top 10 by Total desc ",
        "size": 0,
        "timeContext": {
          "durationMs": 86400000
        },
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces",
        "visualization": "barchart",
        "chartSettings": {
          "ySettings": {
            "numberFormatSettings": {
              "unit": 1,
              "options": {
                "style": "decimal",
                "useGrouping": true
              }
            }
          }
        }
      },
      "name": "query - 3"
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "let mrt=GuardrailsTenantsCompliance_CL \n| summarize mrt=max(ReportTime_s);\nGuardrailsTenantsCompliance_CL \n| where ReportTime_s == toscalar(mrt) and TenantDomain_s == \"{Tenants}\" \n| parse ControlName_s with * \"GUARDRAIL\" number \":\" rest\n| project-away rest\n| extend Mandatory=iff(Mandatory_s != \"\", iff(Mandatory_s==\"True\",\" (M)\", \" (R)\"),\" - N/A\")\n| summarize by Control=ControlName_s, Mandatory=Mandatory_s, ItemName=strcat(ItemName_s, Mandatory),[\"ITSG Control\"]=ITSG_Control_s,Status=Status_s, Profile=Profile_s, number\n| sort by toint(number) asc\n| project-away number",
        "size": 2,
        "timeContext": {
          "durationMs": 43200000
        },
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces"
      },
      "name": "query - 2"
    }
  ],
  "fallbackResourceIds": [
}'''
var wbConfig2='"/subscriptions/${subscriptionId}/resourceGroups/${rg}/providers/Microsoft.OperationalInsights/workspaces/${logAnalyticsWorkspaceName}"'
var wbConfig3='''
  ]
}
'''
var wbConfig='${wbConfig1}${wbConfig2}${wbConfig3}'

resource guardrailsLogAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: {
    version: version
    releasedate: releaseDate
  }
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource existingCentralTenantsComplianceTableForDcr 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' existing = if (deferGuardrailsTenantsComplianceTableProvisioning) {
  parent: guardrailsLogAnalytics
  name: 'GuardrailsTenantsCompliance_CL'
}

resource centralTableGuardrailsTenantsCompliance 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = if (!deferGuardrailsTenantsComplianceTableProvisioning) {
  parent: guardrailsLogAnalytics
  name: 'GuardrailsTenantsCompliance_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 90
    totalRetentionInDays: 90
    schema: {
      // Schema must declare every column the DCR transform projects (see
      // law-centralview-tenantscompliance-transform.kql). Any column projected by the
      // transform that isn't listed here is silently dropped by the LAW pipeline,
      // which is why prior runs showed rows with only TimeGenerated populated.
      // RawData is retained because LAW does not allow column removal once provisioned.
      name: 'GuardrailsTenantsCompliance_CL'
      columns: [
        { name: 'TimeGenerated',                  type: 'dateTime' }
        { name: 'RawData',                        type: 'string'   }
        // Source-table-style columns (mirror GuardrailsCompliance_CL on client tenants)
        { name: 'ControlName_s',                  type: 'string'   }
        { name: 'ItemName_s',                     type: 'string'   }
        { name: 'ComplianceStatus_s',             type: 'string'   }
        { name: 'ComplianceStatus_b',             type: 'boolean'  }
        { name: 'Comments_s',                     type: 'string'   }
        { name: 'ReportTime_s',                   type: 'string'   }
        { name: 'itsgcode_s',                     type: 'string'   }
        { name: 'Required_s',                     type: 'string'   }
        { name: 'Profile_d',                      type: 'real'     }
        { name: 'Profile_s',                      type: 'string'   }
        { name: 'DisplayName_s',                  type: 'string'   }
        { name: 'SubscriptionName_s',             type: 'string'   }
        { name: 'VNETName_s',                     type: 'string'   }
        { name: 'SubnetName_s',                   type: 'string'   }
        { name: 'Definition_s',                   type: 'string'   }
        { name: 'Remediation_s',                  type: 'string'   }
        // Aggregation-specific columns from get-tenantdata
        { name: 'Status_s',                       type: 'string'   }
        { name: 'Count_s',                        type: 'string'   }
        { name: 'Count_d',                        type: 'long'     }
        { name: 'ITSG_Control_s',                 type: 'string'   }
        { name: 'Mandatory_s',                    type: 'string'   }
        // Central reporting / tenant / department context
        { name: 'TenantDomain_s',                 type: 'string'   }
        { name: 'DepartmentName_s',               type: 'string'   }
        { name: 'DepartmentNumber_s',             type: 'string'   }
        { name: 'DepartmentTenantName_s',         type: 'string'   }
        { name: 'DepartmentTenantID_s',           type: 'string'   }
        { name: 'DepartmentTenantID_g',           type: 'guid'     }
        { name: 'DepartmentCloudUsageProfiles_s', type: 'string'   }
        { name: 'AggregationTenantID_s',          type: 'string'   }
        { name: 'AggregationTenantName_s',        type: 'string'   }
        { name: 'AggregationTenantUPN_s',         type: 'string'   }
        { name: 'DepartmentReportTime_s',         type: 'string'   }
        { name: 'DeployedVersion_s',              type: 'string'   }
        { name: 'AvailableVersion_s',             type: 'string'   }
        { name: 'UpdatedNeeded_b',                type: 'boolean'  }
        { name: 'DepartmentVersionCheckDate_s',   type: 'string'   }
        { name: 'WSId_s',                         type: 'string'   }
      ]
    }
  }
}

resource guarrailsWorkbooks 'Microsoft.Insights/workbooks@2022-04-01' = {
  location: location
  kind: 'shared'
  name: guid('guardrails')
  properties:{
    displayName: 'Department Compliance Report'
    serializedData: wbConfig
    category: 'guardrails'
    sourceId: guardrailsLogAnalytics.id
  }
}
resource f1 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  name: 'controlconfig'
  parent: guardrailsLogAnalytics
  properties: {
    category: 'grcentral_functions'
    displayName: 'controlconfig'
    //query: 'let baseurl="${GRDocsBaseUrl}";\nlet Link=strcat(baseurl,control,"-", replace_string(replace_string(itsgcode,"(","-"),")",""),".md");\nLink\n'
    query: 'let controlconfig = datatable(Control:string, mandatory:bool)\n[\n"GUARDRAIL 1: PROTECT USER ACCOUNTS AND IDENTITIES", false,\n"GUARDRAIL 8: SEGMENT AND SEPARATE", true,\n"GUARDRAIL 11: LOGGING AND MONITORING", true,\n"GUARDRAIL 5: DATA LOCATION", true,\n"GUARDRAIL 2: MANAGE ACCESS", false,\n"GUARDRAIL 6: PROTECTION OF DATA-AT-REST",true,\n"GUARDRAIL 7: PROTECTION OF DATA-IN-TRANSIT",   true,\n"GUARDRAIL 12: CONFIGURATION OF CLOUD MARKETPLACES",false,\n"GUARDRAIL 10: CYBER DEFENSE SERVICES",true,\n"GUARDRAIL 3: SECURE ENDPOINTS",true,\n"GUARDRAIL 4: ENTERPRISE MONITORING ACCOUNTS",true,\n"GUARDRAIL 9: NETWORK SECURITY SERVICES",true\n];\ncontrolconfig'
    functionAlias: 'controlconfig'
    version: 2
  }
}

// DCR for Send-GuardrailsData (Log Ingestion API). CentralView posts LogType GuardrailsTenantsCompliance only.
// 'Direct' kind DCRs expose their own logsIngestion endpoint (properties.endpoints.logsIngestion),
// so a separate DCE resource is no longer needed
// (see https://learn.microsoft.com/azure/azure-monitor/logs/tutorial-logs-ingestion-portal).
// Grant the Function App service principal (used after Connect-AzAccount -ServicePrincipal in run.ps1) Monitoring Metrics Publisher on this DCR.
// Expose logsIngestionEndpoint (DCR's own ingestion endpoint) + dcrImmutableId to the Function App as LOGS_INGESTION_ENDPOINT and DCR_IMMUTABLE_ID app settings.
var centralDcrName = 'guardrails-cv-dcr'
var centralTenantsComplianceTransformKql = loadTextContent('law-centralview-tenantscompliance-transform.kql')

resource centralDataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  // NOTE: 2023-03-11 (and later) expose the DCR's built-in logsIngestion endpoint at
  //       properties.endpoints.logsIngestion, removing the need for a separate DCE resource.
  name: centralDcrName
  location: location
  tags: {
    version: version
    releasedate: releaseDate
  }
  kind: 'Direct'
  dependsOn: [
    centralTableGuardrailsTenantsCompliance
  ]
  properties: {
    dataFlows: [
      {
        streams: ['Custom-GuardrailsTenantsCompliance']
        destinations: ['central-law']
        transformKql: centralTenantsComplianceTransformKql
        outputStream: 'Custom-GuardrailsTenantsCompliance_CL'
      }
    ]
    destinations: {
      logAnalytics: [
        {
          name: 'central-law'
          workspaceResourceId: guardrailsLogAnalytics.id
        }
      ]
    }
    streamDeclarations: {
      'Custom-GuardrailsTenantsCompliance': {
        columns: [
          {
            name: 'TimeGenerated'
            type: 'datetime'
          }
          {
            name: 'Mandatory'
            type: 'string'
          }
          {
            name: 'ControlName_s'
            type: 'string'
          }
          {
            name: 'ItemName'
            type: 'string'
          }
          {
            name: 'Profile'
            type: 'string'
          }
          {
            name: 'Status'
            type: 'string'
          }
          {
            name: 'Count'
            type: 'long'
          }
          {
            name: 'ITSG Control'
            type: 'string'
          }
          {
            name: 'SubnetName'
            type: 'string'
          }
          {
            name: 'Definition'
            type: 'string'
          }
          {
            name: 'Remediation'
            type: 'string'
          }
          {
            name: 'VNet Name'
            type: 'string'
          }
          {
            name: 'TenantDomain'
            type: 'string'
          }
          {
            name: 'DepartmentName'
            type: 'string'
          }
          {
            name: 'DepartmentNumber'
            type: 'string'
          }
          {
            name: 'DepartmentTenantName'
            type: 'string'
          }
          {
            name: 'DepartmentTenantID'
            type: 'string'
          }
          {
            name: 'DepartmentCloudUsageProfiles'
            type: 'string'
          }
          {
            name: 'AggregationTenantID'
            type: 'string'
          }
          {
            name: 'AggregationTenantName'
            type: 'string'
          }
          {
            name: 'AggregationTenantUPN'
            type: 'string'
          }
          {
            name: 'ReportTime'
            type: 'string'
          }
          {
            name: 'DepartmentReportTime'
            type: 'string'
          }
          {
            name: 'DeployedVersion'
            type: 'string'
          }
          {
            name: 'AvailableVersion'
            type: 'string'
          }
          {
            name: 'UpdatedNeeded'
            type: 'boolean'
          }
          {
            name: 'DepartmentVersionCheckDate'
            type: 'string'
          }
          {
            name: 'WSId'
            type: 'string'
          }
          // Optional per-record fields. Currently summarized away in get-tenantdata so
          // they're absent from the payload, but declared here so that if get-tenantdata
          // is later changed to project them through, the DCE will forward them to the
          // transform. String-typed declared columns null-coalesce silently when missing.
          {
            name: 'Comments'
            type: 'string'
          }
          {
            name: 'DisplayName'
            type: 'string'
          }
          {
            name: 'SubscriptionName'
            type: 'string'
          }
        ]
      }
    }
  }
}

output customerId string = guardrailsLogAnalytics.properties.customerId
output lawresourceid string = guardrailsLogAnalytics.id
// DCR's own Logs Ingestion endpoint - no separate DCE resource is created/required.
// Surfaced to the Function App as the LOGS_INGESTION_ENDPOINT app setting.
output logsIngestionEndpoint string = centralDataCollectionRule.properties.endpoints.logsIngestion
output dcrImmutableId string = centralDataCollectionRule.properties.immutableId
output dcrResourceId string = centralDataCollectionRule.id
