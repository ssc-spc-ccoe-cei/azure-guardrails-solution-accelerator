param subscriptionId string
param logAnalyticsWorkspaceName string
param rg string
param location string
param version string
param releaseDate string

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
            "query": "let mrt=GuardrailsTenantsCompliance_CL | where TimeGenerated > ago(6h)| summarize mrt=max(ReportTime_s);\nGuardrailsTenantsCompliance_CL \n| where ReportTime_s == toscalar(mrt)\n| summarize by Department=DepartmentName_s",
            "typeSettings": {
              "additionalResourceOptions": [],
              "showDefault": false
            },
            "timeContext": {
              "durationMs": 86400000
            },
            "queryType": 0,
            "resourceType": "microsoft.operationalinsights/workspaces",
            "value": "Canadian Grain Commission"
          },
          {
            "id": "646611b4-e874-4008-8b32-0be7f94e1f82",
            "version": "KqlParameterItem/1.0",
            "name": "Tenants",
            "type": 2,
            "query": "let mrt=GuardrailsTenantsCompliance_CL \n| summarize mrt=max(ReportTime_s);\nGuardrailsTenantsCompliance_CL \n| where ReportTime_s == toscalar(mrt) and DepartmentName_s == \"{Departments}\"\n| summarize sum(toint(Count_s)) by ControlName_s_s, TenantDomain_s\n| summarize by TenantDomain=TenantDomain_s\n",
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
        "query": "let mrt=GuardrailsTenantsCompliance_CL \n| summarize mrt=max(ReportTime_s);\nGuardrailsTenantsCompliance_CL \n| where Status_s == \"Non-Compliant\" and ReportTime_s == toscalar(mrt) and DepartmentName_s == \"{Departments}\"\n| summarize sum(toint(Count_s)) by ControlName_s_s, TenantDomain_s\n| summarize  Total=round(todouble((1-count(ControlName_s_s))/12)*100) by TenantDomain=TenantDomain_s\n| top 10 by Total desc \n",
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
        "query": "let mrt=GuardrailsTenantsCompliance_CL \n| summarize mrt=max(ReportTime_s);\nGuardrailsTenantsCompliance_CL \n| where ReportTime_s == toscalar(mrt) and TenantDomain_s == \"{Tenants}\" \n| parse ControlName_s_s with * \"GUARDRAIL\" number \":\" rest\n| project-away rest\n| extend Mandatory=iff(Mandatory_s != \"\", iff(Mandatory_s==\"True\",\" (M)\", \" (R)\"),\" - N/A\")\n| summarize by Control=ControlName_s_s, Mandatory=Mandatory_s, ItemName=strcat(ItemName_s, Mandatory),[\"ITSG Control\"]=ITSG_Control_s,Status=Status_s, number\n| sort by toint(number) asc\n| project-away number",
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
'''
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
    query: 'let controlconfig = datatable(Control:string, mandatory:bool)\n[\n"GUARDRAIL 1: PROTECT ROOT / GLOBAL ADMINS ACCOUNT", false,\n"GUARDRAIL 8: NETWORK SEGMENTATION AND SEPARATION", true,\n"GUARDRAIL 11: LOGGING AND MONITORING", true,\n"GUARDRAIL 5: DATA LOCATION", true,\n"GUARDRAIL 2: MANAGEMENT OF ADMINISTRATIVE PRIVILEGES", false,\n"GUARDRAIL 6: PROTECTION OF DATA-AT-REST",true,\n"GUARDRAIL 7: PROTECTION OF DATA-IN-TRANSIT",   true,\n"GUARDRAIL 12: CONFIGURATION OF CLOUD MARKETPLACES",false,\n"GUARDRAIL 10: CYBER DEFENSE SERVICES",true,\n"GUARDRAIL 3: CLOUD CONSOLE ACCESS",true,\n"GUARDRAIL 4: ENTERPRISE MONITORING ACCOUNTS",true,\n"GUARDRAIL 9: NETWORK SECURITY SERVICES",true\n];\ncontrolconfig'
    functionAlias: 'controlconfig'
    version: 2
  }
}
output customerId string = guardrailsLogAnalytics.properties.customerId
output lawresourceid string = guardrailsLogAnalytics.id
