
Function Show-GSADeploymentSummary {
    param (
        # parameters from deploy function call
        [Parameter(Mandatory=$true)]
        [psobject]
        $deployParams,
        
        # deploy function parameter set name
        [Parameter(Mandatory = $true)]
        [string]
        $deployParamSet,

        # proceed through imput prompts
        [Parameter(Mandatory = $false)]
        [Alias('y')]
        [switch]
        $yes
    )
    $ErrorActionPreference = 'Stop'
    Write-Verbose "Starting Show-GSADeploymentSummary..."

    # determine the resources and configurations to be deployed
    switch -regex ($deployParamSet) {
        'newDeployment' {
            $deployType = 'New component'
            $components = $deployParams.newComponents

            $messages = ""
            If ($components -contains 'CoreComponents' -or [string]::IsNullOrEmpty($components)) {
                $messages += @"
Core components deployments will make the following changes to your environment:
    - Create a new resource group
    - Create a Log Analyics workspace, Automation Account, Storage Account, Key Vault, and Workbook resources in the new resource group
    - Grant the Automation Account Managed Service Identity (MSI) permissions to the Key Vault, Storage Account, and Log Analytics workspace in the new resource group
    - Grant the Automation Account Managed Service Identity (MSI) reader rights to your Azure tenant at the root Management Group scope
    - Grant the Automation Account MSI the following roles in Azure AD: "Organization.Read.All", "User.Read.All", "UserAuthenticationMethod.Read.All", "Policy.Read.All", "Directory.Read.All"`n
"@
            }
            If ($components -contains 'CentralizedCustomerReportingSupport') {
                $messages += @"
Centralized Customer Reporting Support will make the following changes to your environment:
    - Add a Lighthouse delegation definition, allowing Reader, Monitoring Reader, and Managed Services Registration assignment Delete Role
    - Assign the Lighthouse delegation at the Guardrails resource group scope, allowing access to the managing tenant principal specified in the configuration file`n
"@
            }
            If ($components -contains 'CentralizedCustomerDefenderForCloudSupport') {
                $messages += @"
Centralized Customer Defender for Cloud Support will make the following changes to your environment:
    - Creates a new Policy definition and assignment at the Management Group specified in the configuration file (lighthouseTargetManagementGroupID)
    - The Policy deploys a Lighthouse definition and assignment at each Subscription under the Management Group specified in the configuration file (lighthouseTargetManagementGroupID) which grants the Security Reader to the managing tenant service principal specified in the configuration file.
    - Creates a new custom RBAC definition allowing the registration of the Lighthouse Resource Provider
    - Assigns the custom RBAC definition to the Automation Account MSI at the Management Group specified in the configuration file (lighthouseTargetManagementGroupID)
    - Enables a step in the Automation Account 'backend' runbook to register the Lighthouse Resource Provider`n
"@
            }
        }
        'updateDeployment' {
            $deployType = 'Update component'

            If ($deployParams['componentsToUpdate']) {
                $components = $deployParams.componentsToUpdate
            }
            Else {
                $components = 'Workbook','GuardrailPowerShellModules','AutomationAccountRunbooks', 'CoreComponents'
            }
        }
    }

    # display the resources and configurations to be deployed
    $actionString = ""
    ForEach ($component in $components) {
        $actionString += "`n`t-  {0}: {1}" -f $deployType, $component
    }

    # verify the user's acceptance
    Write-Host "Executing this command will perform the following actions: $actionString"
    Write-Host $messages -ForegroundColor Yellow

    If (!$yes.IsPresent) {
        do { $prompt = Read-Host -Prompt 'Do you want to continue? (y/n)' }
        until ($prompt -match '[yn]')

        if ($prompt -ieq 'y') {
            Write-Verbose "Continuing with resource removal..."
        }
        elseif ($prompt -ieq 'n') {
            Write-Output "Exiting without removing Guardrails Solution Accelerator core resources..."
            break
        }
    }

    Write-Verbose "Show-GSADeploymentSummary completed."
}
