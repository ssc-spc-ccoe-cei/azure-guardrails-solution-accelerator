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
        [string] $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] $EnableMultiCloudProfiles # default to false
    )

    # Call KQL function to get compliance results with retry logic
    $complianceResult = $null
    $maxRetries = 10
    $retryDelay = 30 # seconds
    $success = $false
    
    try {
        $kqlQuery = "gr_mfa_evaluation('$ReportTime')"
        
        Write-Verbose "Calling KQL function with retry logic (max $maxRetries attempts, $retryDelay second delay)"
        
        for ($i = 1; $i -le $maxRetries; $i++) {
            try {
                Write-Warning "WorkspaceID is $WorkspaceID query is $kqlQuery"
                $queryResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkSpaceID -Query $kqlQuery -ErrorAction Stop
                
                $resultsArray = @($queryResults.Results)
                if ($resultsArray.Count -gt 0) {
                    $complianceResult = $resultsArray[0]
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
            $ErrorList.Add("Failed to call gr_mfa_evaluation KQL function after $maxRetries attempts")
        }
    } catch {
        Write-Error "Failed to call KQL function: $_"
        $ErrorList.Add("Failed to call gr_mfa_evaluation KQL function: $_")
    }
    
    # Add Profile information to compliance result if KQL function was successful
    if ($complianceResult -and $EnableMultiCloudProfiles) {
        try {
            Write-Verbose "Adding Profile information to compliance result"
            $result = Add-ProfileInformation -Result $complianceResult -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId -ErrorList $ErrorList
            $complianceResult = $result
            Write-Verbose "Profile information added successfully"
        } catch {
            Write-Warning "Failed to add Profile information: $_"
            $ErrorList.Add("Failed to add Profile information: $_")
        }
    }
    
    # Performance reporting
    $stopwatch.Stop()
    $finalMemory = [System.GC]::GetTotalMemory($false)
    $memoryUsed = ($finalMemory - $initialMemory) / 1MB
    
    Write-Verbose "Performance Summary: Data collection completed in $($stopwatch.ElapsedMilliseconds) ms, Memory used: $([math]::Round($memoryUsed, 2)) MB"

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
