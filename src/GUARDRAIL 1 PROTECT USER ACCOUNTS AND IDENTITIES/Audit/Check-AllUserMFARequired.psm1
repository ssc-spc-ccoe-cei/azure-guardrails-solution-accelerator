function Check-AllUserMFARequired {
    [CmdletBinding()]
    param (      
        [Parameter(Mandatory=$true)]
        [string] $ControlName,
        [Parameter(Mandatory=$true)]
        [string] $ItemName,
        [Parameter(Mandatory=$true)]
        [string] $itsgcode,
        [Parameter(Mandatory=$true)]
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string] $ReportTime,
        [Parameter(Mandatory=$true)]
        [string] $WorkSpaceID,
        [Parameter(Mandatory=$true)]
        [string] $mfaGracePeriod,
        [string] $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] $EnableMultiCloudProfiles # default to false
    )

    [System.Collections.ArrayList]$ErrorList = New-Object System.Collections.ArrayList
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Return a real compliance row when current source data is unavailable. This
    # lets the workbook show Not Applicable instead of retaining a false pass or
    # receiving no row at all, while the Errors collection records the failure.
    function New-MfaNotAssessedResult {
        return [PSCustomObject]@{
            ComplianceStatus = 'Not Applicable'
            ControlName      = $ControlName
            ItemName         = $ItemName
            Comments         = [string]$msgTable['allUserMfaNotAssessedIncompleteData']
            ReportTime       = $ReportTime
            itsgcode         = $itsgcode
        }
    }

    # FetchAllUserRawData runs earlier in the same main runbook. If it reports an
    # incomplete collection, do not turn the absence of current rows into a false pass.
    $rawCollectionState = Get-Variable -Name GuardrailsUserRawDataCollectionComplete -Scope Global -ErrorAction SilentlyContinue
    if ($rawCollectionState -and $rawCollectionState.Value -eq $false) {
        $errorMessage = 'MFA compliance was not evaluated because current raw user data collection did not complete.'
        Write-Error $errorMessage
        [void]$ErrorList.Add($errorMessage)
        return [PSCustomObject]@{
            ComplianceResults = (New-MfaNotAssessedResult)
            Errors = $ErrorList
        }
    }
    # The main runbook provides the number of rows it uploaded. A standalone MFA
    # run may not have that value, so the current ReportTime row count below remains
    # an independent check that current user data actually exists.
    $expectedRawRecordState = Get-Variable -Name GuardrailsUserRawDataExpectedRecordCount -Scope Global -ErrorAction SilentlyContinue
    $expectedRawRecordCount = if ($expectedRawRecordState) { [long]$expectedRawRecordState.Value } else { 0 }

    # Log Analytics can take time to make newly uploaded rows queryable. Ten attempts
    # with 30-second pauses allow roughly 4.5 minutes of ingestion time before the
    # module stops without publishing a potentially incorrect compliance result.
    $complianceResult = $null
    $maxRetries = 10
    $retryDelay = 30 # seconds
    $success = $false
    
    try {
        # Return the current raw-row count with the compliance result. The saved
        # function returns "No users found" as compliant, so zero rows must be
        # treated as missing input and retried instead of accepted as evidence.
        $kqlQuery = @"
let rawUserRecordCount = toscalar(
    GuardrailsUserRaw_CL
    | where ReportTime_s == '$ReportTime'
    | count
);
gr_mfa_evaluation('$ReportTime', '$mfaGracePeriod')
| extend RawUserRecordCount = rawUserRecordCount
"@
        
        Write-Verbose "Calling KQL function with retry logic (max $maxRetries attempts, $retryDelay second delay)"
        
        for ($i = 1; $i -le $maxRetries; $i++) {
            try {
                $queryResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkSpaceID -Query $kqlQuery -ErrorAction Stop
                
                $resultsArray = @($queryResults.Results)
                if ($resultsArray.Count -gt 0) {
                    $candidateResult = $resultsArray[0]
                    $rawUserRecordCount = 0
                    if ($candidateResult.PSObject.Properties.Match('RawUserRecordCount').Count -gt 0) {
                        $rawUserRecordCount = [long]$candidateResult.RawUserRecordCount
                    }

                    # Require current rows to exist. When this run supplied an expected
                    # count, also wait until Log Analytics exposes at least that many rows.
                    # This is the second guard against the previous "No users found" pass.
                    $rawDataIncomplete = $rawUserRecordCount -le 0 -or
                        ($expectedRawRecordCount -gt 0 -and $rawUserRecordCount -lt $expectedRawRecordCount)
                    if ($rawDataIncomplete) {
                        Write-Warning "Attempt $i - Current raw user data is incomplete for ReportTime '$ReportTime' ($rawUserRecordCount/$expectedRawRecordCount rows). Retrying after $retryDelay seconds..."
                        if ($i -lt $maxRetries) { Start-Sleep -Seconds $retryDelay }
                        continue
                    }

                    # The count is only an input-safety check; do not add it to the
                    # established GuardrailsCompliance output schema.
                    [void]$candidateResult.PSObject.Properties.Remove('RawUserRecordCount')
                    $complianceResult = $candidateResult
                    $success = $true
                    Write-Verbose "Successfully retrieved compliance result from KQL function on attempt $i"
                    break
                } else {
                    Write-Warning "Attempt $i - KQL function returned no results, retrying after $retryDelay seconds..."
                    if ($i -lt $maxRetries) { Start-Sleep -Seconds $retryDelay }
                }
            } catch {
                Write-Warning "Attempt $i failed: $_"
                if ($i -eq $maxRetries) {
                    throw "All $maxRetries attempts failed. Last error: $_"
                } else {
                    Start-Sleep -Seconds $retryDelay
                }
            }
        }
        
        if (-not $success) {
            Write-Error "Failed to get compliance results after $maxRetries attempts"
            [void]$ErrorList.Add("Failed to call gr_mfa_evaluation KQL function after $maxRetries attempts")        }
    } catch {
        Write-Error "Failed to call KQL function: $_"
        [void]$ErrorList.Add("Failed to call gr_mfa_evaluation KQL function: $_")
    }

    # Every unsuccessful query path now returns an explicit Not Applicable row.
    # This keeps missing or partially ingested source data out of the compliance
    # calculation without causing main.ps1 to attempt to upload a null result.
    if ($null -eq $complianceResult) {
        $complianceResult = New-MfaNotAssessedResult
    }

    # Add profile information to either an evaluated or Not Applicable result.
    if ($complianceResult -and $EnableMultiCloudProfiles) {
        try {
            Write-Verbose "Adding Profile information to compliance result"
            $result = Add-ProfileInformation -Result $complianceResult -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId -ErrorList $ErrorList
            $complianceResult = $result
            Write-Verbose "Profile information added successfully"
        } catch {
            Write-Warning "Failed to add Profile information: $_"
            [void]$ErrorList.Add("Failed to add Profile information: $_")
        }
    }
    
    # Performance reporting
    $stopwatch.Stop()
    
    Write-Warning "Performance Summary: Query Executed in $($stopwatch.ElapsedMilliseconds) ms"

    # 6) Return compliance results from KQL function
    # Raw data already sent to GuardrailsUserRaw_CL table
    # Compliance logic handled by KQL function for better performance
    
    # 7) Return in the expected envelope; main.ps1 will send ComplianceResults to Log Analytics
    $moduleOutput = [PSCustomObject]@{ 
        ComplianceResults = $complianceResult
        Errors            = $ErrorList
    }
    return $moduleOutput
}