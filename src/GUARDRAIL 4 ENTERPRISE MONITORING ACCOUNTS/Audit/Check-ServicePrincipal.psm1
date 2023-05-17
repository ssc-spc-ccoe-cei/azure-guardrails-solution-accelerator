function Verify-Roles {
    param (
        [PSCustomObject]$ServicePrincipal,
        [hashtable] $msgTable
    )
    
    [bool] $isCompliantR = $false  
    [bool] $isCompliantMPA = $false  
    [string] $TenantId = (Get-AzContext).Tenant.Id
    [string] $ManagementScope = "/providers/Microsoft.Management/managementGroups/" + $TenantId    
    [string] $MarketplaceScope = "/providers/Microsoft.Marketplace"
    [string] $SPNObjectID = $ServicePrincipal.ServicePrincipalNameID

    $CostManagmentReader = Get-AzRoleAssignment | Where-Object { $_.ObjectId -eq $SPNObjectID -and $_.RoleDefinitionName -eq "Cost Management Reader" -and $_.Scope -eq $ManagementScope } -ErrorAction SilentlyContinue

    $PrivateMarketplaceAdmin = Get-AzRoleAssignment -Scope $MarketplaceScope | Where-Object { $_.ObjectId -eq $SPNObjectID -and $_.RoleDefinitionName -eq "Marketplace Admin" } -ErrorAction SilentlyContinue 

    if ([string]::IsNullOrEmpty($CostManagmentReader)) {

        $isCompliantR = $false
    
        $ServicePrincipal.ComplianceComments += $msgTable.ServicePrincipalNameHasNoReaderRole
    }
    else {

        $isCompliantR = $true
    
        $ServicePrincipal.ComplianceComments += $msgTable.ServicePrincipalNameHasReaderRole
    }
    if ([string]::IsNullOrEmpty($PRivateMarketplaceAdmin)) {

        $isCompliantMPA = $false
 
        $ServicePrincipal.ComplianceComments += $msgTable.ServicePrincipalNameHasNoMarketPlaceAdminRole
    }
    else {
        $isCompliantMPA = $true

        $ServicePrincipal.ComplianceComments += $msgTable.ServicePrincipalNameHasMarketPlaceAdminRole
    }

    $ServicePrincipal.ComplianceStatus = $isCompliantR -and $isCompliantMPA
}
    
function Check-DepartmentServicePrincipalName {
    param (
        [string] $SPNID = "0000000000",
        [string] $ControlName, 
        [string] $ItemName, 
        [string] $itsgcode,
        [hashtable] $msgTable,
        [Parameter(Mandatory = $true)]
        [string]
        $ReportTime)
        
    [bool] $IsCompliant = $false

    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList

    $servicePrincipalName = [PSCustomObject]@{
        ServicePrincipalNameAPPID = $msgTable.NoSPN   
        ServicePrincipalNameID    = $null
        ComplianceStatus          = $false
        ComplianceComments        = $null
    } 

    $SPNObject = Get-AzADServicePrincipal -ApplicationId $SPNID -ErrorAction SilentlyContinue

    if ([string]::IsNullOrEmpty($SPNObject)) {
        $servicePrincipalName.ServicePrincipalNameAPPID = $msgTable.NoSPN
        $servicePrincipalName.ServicePrincipalNameID = $null
        $ServicePrincipalName.ComplianceStatus = $false
        $servicePrincipalName.ComplianceComments = $msgTable.NoSPN
    } 
    else {
        $urlPath = "/servicePrincipals/" + $SPNObject.Id
        try {
            $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop 
                   
            if ($response.statusCode -eq 200) {
                $servicePrincipalName.ServicePrincipalNameAPPID = $SPNObject.AppId
                $servicePrincipalName.ServicePrincipalNameID = $SPNObject.Id
                $servicePrincipalName.ComplianceComments = $msgTable.SPNExist
                $servicePrincipalName.ComplianceStatus = $true
                
                Verify-Roles -ServicePrincipal $servicePrincipalName -msgTable $msgTable
           
            }
            elseif ($response.statusCode -eq 404) {
                $IsCompliant = $false
                $ServicePrincipalName.ComplianceStatus = $IsCompliant
                $ServicePrincipalName.ComplianceComments = $msgTable.NoSPN  
            }
            else {
                $ErrorList.Add("Failed to call Microsoft Graph REST API at URL '$urlPath'$($response.statusCode)" )
                Write-Error "Error: Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $($response.statusCode)"
                $IsCompliant = $false
                $ServicePrincipalName.ComplianceComments = $msgTable.NoSPN
            }
        }
        catch {
            $ErrorList.Add("Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_" )
            Write-Error "Error: Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"
            $IsCompliant = $false
            $ServicePrincipalName.ComplianceComments = $msgTable.NoSPN
        } 
    }
    $Results = [pscustomobject]@{
        ControlName      = $ControlName  
        ComplianceStatus = $servicePrincipalName.ComplianceStatus
        ItemName         = $ItemName
        itsgcode         = $itsgcode
        Comments         = $servicePrincipalName.ComplianceComments
        ReportTime       = $ReportTime
    }
    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = $Results 
        Errors            = $ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput 
}
