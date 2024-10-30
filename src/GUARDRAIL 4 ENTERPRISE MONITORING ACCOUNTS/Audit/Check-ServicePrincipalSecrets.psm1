function Get-DepartmentServicePrincipalNameSecrets {
    param (
        [string] $SPNID = "0000000000",
        [string] $ControlName, 
        [string] $ItemName, 
        [string] $itsgcode,
        [hashtable] $msgTable,
        [Parameter(Mandatory = $true)]
        [string] $ReportTime,
        [string] $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] $EnableMultiCloudProfiles # New feature flag, default to false    
    )
        
    #[bool] $IsCompliant = $false

    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList

    $servicePrincipalName = [PSCustomObject]@{
        ServicePrincipalNameAPPID = $msgTable.NoSPN   # Here
        ServicePrincipalNameID    = $null
        ComplianceStatus          = $false
        ComplianceComments        = $null
    } 
    try {
        $SPNObject = Get-AzADServicePrincipal -ApplicationId $SPNID -ErrorAction SilentlyContinue
    }
    catch {
        $ErrorList.Add("Failed to retrieve Service Principal $SPNID. Error message $_" )
        Write-Error "Error: Failed to retrieve Service Principal $SPNID. Error message $_"
        $servicePrincipalName.ServicePrincipalNameAPPID = $msgTable.NoSPN
        $servicePrincipalName.ServicePrincipalNameID = $null
        $ServicePrincipalName.ComplianceStatus = $false
        $ServicePrincipalName.ComplianceComments = $msgTable.NoSPN
    }

    if ([string]::IsNullOrEmpty($SPNObject)) {
        $servicePrincipalName.ServicePrincipalNameAPPID = $msgTable.NoSPN
        $servicePrincipalName.ServicePrincipalNameID = $null
        $ServicePrincipalName.ComplianceStatus = $false
        $servicePrincipalName.ComplianceComments = $msgTable.NoSPN
    } 
    else {
        $servicePrincipalName.ServicePrincipalNameAPPID = $SPNObject.AppId
        $servicePrincipalName.ServicePrincipalNameID = $SPNObject.Id
        # All good. We have an SPN. Now check for valid credentials
        $allCredentials = Get-AzADAppCredential -ApplicationId $SPNID -ErrorAction SilentlyContinue 
        $validCredentials=$allCredentials | Where-Object { $_.EndDateTime -ge (Get-Date) } 

        switch ($validCredentials.count) { #non compliant and report  name/expiration dates for each in the message
            0 { 
                $ct="" # just a temp variable to hold the list of credentials
                $allCredentials | ForEach-Object {$ct+="$($_.DisplayName): $($_.EndDateTime);"}
                $servicePrincipalName.ComplianceComments = $msgTable.SPNNoValidCredentials -f $ct
                $servicePrincipalName.ComplianceStatus = $false
             }
            1 { #compliant and report name/expiration date in the message
                $servicePrincipalName.ComplianceComments = $msgTable.SPNSingleValidCredential -f "$($validCredentials.DisplayName): $($validCredentials.EndDateTime)"
                $servicePrincipalName.ComplianceStatus = $true
            }
            Default { # non-compliant as error multiple valid app secrets present and report name/expiration dates for each in the message
                $ct="" # just a temp variable to hold the list of credentials
                $validCredentials | ForEach-Object {$ct+="$($_.DisplayName): $($_.EndDateTime);"}
                $servicePrincipalName.ComplianceComments = $msgTable.SPNMultipleValidCredentials -f $ct
                $servicePrincipalName.ComplianceStatus = $false
            }
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

    # Conditionally add the Profile field based on the feature flag
    if ($EnableMultiCloudProfiles) {
        $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        if (!$evalResult.ShouldEvaluate) {
            if ($evalResult.Profile -gt 0) {
                $Results.ComplianceStatus = "Not Applicable"
                $Results | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                $Results.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
            } else {
                $ErrorList.Add("Error occurred while evaluating profile configuration")
            }
        } else {
            Write-Output "Valid profile returned: $($evalResult.Profile)"
            $Results | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
        }
    }

    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = $Results 
        Errors            = $ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput 
}
