function Check-UserRoleReviews {
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
        [string] 
        $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] 
        $EnableMultiCloudProfiles # New feature flag, default to false
    )

    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    [bool] $IsCompliant = $false
    [string] $Comments = $null

    # list all acces reviews in identity governance
    $urlPath = "/identityGovernance/accessReviews/definitions"

    # $urlPath = "/beta/accessReviews?$filter=businessFlowTemplateId+eq+'6e4f3d20-c5c3-407f-9695-8460952bcc68'&$top=100&$skip=0"
    # $urlPath = "/beta/accessReviews?$filter=businessFlowTemplateId+eq+'6e4f3d20-c5c3-407f-9695-8460952bcc68'"

    try {
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
        # # portal
        $data = $response.Content
        # # localExecution
        # $data = $response

        if ($null -ne $data -and $null -ne $data.value) {
            $accessReviewsAll = $data.value 
            $accessReviewsSorted = $accessReviewsAll | Sort-Object -Property displayName, createdDateTime -Descending 

            # Check if any policies exist
            if ($accessReviewsSorted.Count -lt 1) {
                Write-Host "Non-compliant. Tenant has not been onboarded to automated MS Access Reviews."
            }
            else{
                Write-Host "Tenant has been onboarded to automated MS Access Reviews and has at least one access review."
                $accessReviewHistory = $accessReviewsSorted | Group-Object -Property displayName | ForEach-Object {
                    $_.Group | Select-Object -First 1  # Get the most recent review for each ReviewName
                }

                # check if the access review is within the last year
                $oneYearAgo = (Get-Date).AddYears(-1)
                $accessReviewHistory | ForEach-Object {
                    $review = $_
                    $reviewAge = [datetime]::Parse($review.lastModifiedDateTime)
                    $isWithinLastOneYear = if ($reviewAge -ge $oneYearAgo){$true} else {$false}
                    $review | Add-Member -MemberType NoteProperty -Name "isWithinLastOneYear" -Value $isWithinLastOneYear
                    $review
                }
                
                # validation: any of the access review is within last one year
                $anyReviewWithinOneYear = $accessReviewHistory | Where-Object { $_.isWithinLastOneYear -eq $true }
                if ($anyReviewWithinOneYear.Count -ge 1){
                    Write-Host "Compliant. Tenant has scheduled access review(s)."
                }
                else{
                    Write-Host "Non-compliant. Tenant has not scheduled at least one access review."
                }

            }
        }
    }
    catch {
        $errorMsg = "Failed to call Microsoft Graph REST API at URL '$urlPath'; returned error message: $_"                
        $ErrorList.Add($errorMsg)
        Write-Error "Error: $errorMsg"
    }
    



    $Comments = $commentsArray -join ";"
    
    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        ItemName         = $ItemName
        Comments         = $Comments
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }
    
    # Conditionally add the Profile field based on the feature flag
    if ($EnableMultiCloudProfiles) {        
        $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        if (!$evalResult.ShouldEvaluate) {
            if ($evalResult.Profile -gt 0) {
                $PsObject.ComplianceStatus = "Not Applicable"
                $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                $PsObject.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
            } else {
                $ErrorList.Add("Error occurred while evaluating profile configuration")
            }
        } else {
            
            $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
        }
    }
    
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $PsObject
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput   
}