<#
.SYNOPSIS
    
.DESCRIPTION
    
.NOTES
    
.LINK
    
.EXAMPLE

#>

Function Remove-GSACentralizedDefenderCustomerComponents {
    param (
        [Parameter(mandatory = $true, parameterSetName = 'hashtable', ValueFromPipelineByPropertyName = $true)]
        [string]
        $configString,

        [Parameter(mandatory = $true, ParameterSetName = 'configFile')]
        [string]
        [Alias(
            'configFileName'
        )]
        $configFilePath,

        # Parameter help description
        [Parameter(Mandatory = $true, parameterSetname = 'manualParams')]
        [string]
        $lighthouseTargetManagementGroupID,

        # force removal of resources
        [Parameter(Mandatory = $false)]
        [switch]
        $force,

        # wait for removal of resources
        [Parameter(Mandatory = $false)]
        [switch]
        $wait
    )
    $ErrorActionPreference = 'Stop'
    
    Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Deploy-GuardrailsSolutionAccelerator\Deploy-GuardrailsSolutionAccelerator.psd1") -Function 'Confirm-GSASubscriptionSelection', 'Confirm-GSAConfigurationParameters'

    If ($configString) {
        If (Test-Json -Json $configString) {
            $config = ConvertFrom-Json -InputObject $configString
        }
        Else {
            Write-Error -Message "The config parameter (or value from the pipeline) is not valid JSON. Please ensure that the config parameter is a valid JSON string or a path to a valid JSON file." -ErrorAction Stop
        }
    }
    ElseIf ($configFilePath) {
        $config = Confirm-GSAConfigurationParameters -configFilePath $configFilePath
    }

    If (!$lighthouseTargetManagementGroupID) {
        $lighthouseTargetManagementGroupID = $config.lighthouseTargetManagementGroupID
    }

    If (!$force.IsPresent) {
        Write-Warning "This action will delete the role definitions and assignments associated with granting managing tenant access to Defender for Cloud in this tenant at management group '$lighthouseTargetManagementGroupID'. `n`nIf you are not certain you want to perform this action, press CTRL+C to cancel; otherwise, press ENTER to continue."
        Read-Host
    }

$lighthouseTargetManagementGroupID = 'mb_co'
If ($lighthouseTargetManagementGroupID -eq (Get-AzContext).Tenant.Id) {
    $assignmentScopeMgmtmGroupId = '/'
}
Else {
    $assignmentScopeMgmtmGroupId = $lighthouseTargetManagementGroupID
}

# check if a lighthouse defender for cloud policy MSI role assignment already exists - assignment name always 2cb8e1b1-fcf1-439e-bab7-b1b8b008c294 
Write-Verbose "Checking for role assignments at management group '$assignmentScopeMgmtmGroupId' for role 'Owner'"
$uri = 'https://management.azure.com/providers/Microsoft.Management/managementGroups/{0}/providers/Microsoft.Authorization/roleAssignments/{1}?&api-version=2018-01-01-preview' -f $lighthouseTargetManagementGroupID, '2cb8e1b1-fcf1-439e-bab7-b1b8b008c294'
$response = Invoke-AzRestMethod -Uri $uri -Method GET -Verbose 

If ($response.StatusCode -notin 200, 404) {
    Write-Error "Error checking for role assignments at management group '$assignmentScopeMgmtmGroupId' for role 'Owner'. Status code: $($response.StatusCode). Response: $($response.Content)"
    Return
}

$roleAssignments = $response | Select-Object -Expand Content | ConvertFrom-Json
If ($roleAssignments.id) {
    Write-Verbose "Deleteing role assignments '$roleAssignments'"
    $uri = 'https://management.azure.com/{0}?api-version=2015-07-01' -f $roleAssignments.id
    $response = Invoke-AzRestMethod -Uri $uri -Method DELETE -Verbose

    If ($response.StatusCode -in 200, 202, 204) {
        Write-Verbose "Role assignment deleted successfully"
    }
    Else {
        Write-Error "Error deleting role assignment: $response"
    }
}
Else {
    Write-Verbose "No DfC role assignments found..."
}

      
# check if a lighthouse Azure Automation MSI role assignment to register the Lighthouse resource provider already exists - assignment name always  5de3f84b-8866-4432-8811-24859ccf8146
Write-Verbose "Checking for role assignments at management group '$assignmentScopeMgmtmGroupId' for role 'Custom-RegisterLighthouseResourceProvider'"
$uri = 'https://management.azure.com/providers/Microsoft.Management/managementGroups/{0}/providers/Microsoft.Authorization/roleAssignments/{1}?&api-version=2018-01-01-preview' -f $lighthouseTargetManagementGroupID, '5de3f84b-8866-4432-8811-24859ccf8146'
$response = Invoke-AzRestMethod -Uri $uri -Method GET 

If ($response.StatusCode -notin 200, 404) {
    Write-Error "Error checking for role assignments at management group '$assignmentScopeMgmtmGroupId' for role 'Custom-RegisterLighthouseResourceProvider'. Status code: $($response.StatusCode). Response: $($response.Content)"
    Return
}
      
$roleAssignments = $response | Select-Object -Expand Content | ConvertFrom-Json   

If ($roleAssignments.id) { 
    Write-Verbose "Deleteing role assignments '$roleAssignments'"
    $uri = 'https://management.azure.com/{0}?api-version=2015-07-01' -f $roleAssignments.id
    $response = Invoke-AzRestMethod -Uri $uri -Method DELETE -verbose

    If ($response.StatusCode -in 200, 202, 204) {
        Write-Verbose "Role assignment deleted successfully"
    }
    Else {
        Write-Error "Error deleting role assignment: $response"
    }
}
else {
    Write-Verbose "No MSI role assignemnts found"
}

# check if lighthouse Custom-RegisterLighthouseResourceProvider exists at a different scope
Write-Verbose "Checking for existing role definitions with name 'Custom-RegisterLighthouseResourceProvider'"
$uri = "https://management.azure.com/providers/Microsoft.Management/managementGroups/{0}/providers/Microsoft.Authorization/roleDefinitions?`$filter=roleName eq '{1}'&api-version=2018-01-01-preview" -f $lighthouseTargetManagementGroupID, 'Custom-RegisterLighthouseResourceProvider'
$response = Invoke-AzRestMethod -Uri $uri -Method Get

If ($response.StatusCode -notin 200, 404) {
    Write-Error "Error checking for role definition 'Custom-RegisterLighthouseResourceProvider' at management group '$lighthouseTargetManagementGroupID'. Status code: $($response.StatusCode). Response: $($response.Content)"
    Return
}

$roleDefinition = $response.Content | ConvertFrom-Json
If ($roleDefId = $roleDefinition.Name) {
    $uri = 'https://management.azure.com/providers/Microsoft.Management/managementGroups/{0}/providers/Microsoft.Authorization/roleDefinitions/{1}?api-version=2018-01-01-preview' -f $lighthouseTargetManagementGroupID, $roleDefId

    $response = Invoke-AzRestMethod -Method DELETE -Uri $uri

    If ($response.StatusCode -notin 200, 202, 204) {
        Write-Error "Error deleting role definition '$roleDefId' at management group '$lighthouseTargetManagementGroupID'. Status code: $($response.StatusCode). Response: $($response.Content)"
        Return
    }
    Else {
        Write-Verbose "Role definition '$roleDefId' deleted successfully"
    }
}
Else {
    Write-Verbose "No role definition found with name 'Custom-RegisterLighthouseResourceProvider'"
}

Write-Host "Completed removing Lighthouse role assignments and role definitions for Defender for Cloud access" -ForegroundColor Green
}
