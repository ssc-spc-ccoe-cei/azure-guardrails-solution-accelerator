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
    
    $accessReviewList = @()

    # list all acces reviews in identity governance
    $urlPath = "/identityGovernance/accessReviews/definitions"

    try {
        $response = Invoke-GraphQuery -urlPath $urlPath -ErrorAction Stop
        # portal
        $data = $response.Content
        # # localExecution
        # $data = $response
        
        if ($null -ne $data -and $null -ne $data.value) {
            $accessReviewsAll = $data.value 
            $accessReviewsSorted = $accessReviewsAll | Sort-Object -Property displayName, createdDateTime -Descending 
            
            # Check if any policies exist
            if ($accessReviewsSorted.Count -eq 0) {
                $commentsArray = $msgTable.isNotCompliant + " " + $msgTable.noAutomatedAccessReview
            }
            else{
                Write-Host "Tenant has been onboarded to automated MS Access Reviews and has at least one access review."
                # Get the most recent review for each ReviewName
                $accessReviewHistory = $accessReviewsSorted | Group-Object -Property displayName | ForEach-Object {
                    $_.Group | Select-Object -First 1  
                }
                Write-Host "Number of most recent access review per displayName:  $($accessReviewHistory.count)"
                foreach($review in $accessReviewHistory){
                    # get the query for each instance
                    $queryURI = $review.'instances@odata.context'
                    Write-Host "Query: $queryURI "
                    
                    $cleanQueryURI = $queryURI -replace '\$metadata#', '' -replace '\(' , '/' -replace '\)', '' -replace "'", ''
                    $cleanQueryURI = $cleanQueryURI -replace 'https://graph.microsoft.com/v1.0', ''
                    try{
                        $queryResponse = Invoke-GraphQuery -urlPath $cleanQueryURI -ErrorAction Stop
                        # portal
                        $queryResponseData =  $queryResponse.Content
                        # # localExecution
                        # $queryResponseData = $queryResponse
                        
                        if($queryResponseData.'@odata.count' -ne 0){
                            if ($null -ne $queryResponseData -and $null -ne $queryResponseData.value) {
                                $queryData = $queryResponseData.value
                                Write-Host "Number of queryData:  $($queryData.count)"
                                # query data status can be 'Completed','InProgress', 'Applied', 'NotStarted'
                                $queryDataSorted = $queryData | Where-Object { $_.status -ne 'NotStarted'} | Sort-Object -Property startDateTime, endDateTime -Descending
                                $mostRecentQueryData =  $queryDataSorted[0]
        
                                $accessReviewInfo = [PSCustomObject]@{
                                    AccessReviewName                            = $review.displayName
                                    AccessReviewInstanceId                      = $review.id
                                    DescriptionForAdmins                        = $review.descriptionForAdmins
                                    DescriptionForReviewers                     = $review.descriptionForReviewers
                                    startDateTimeMostRecentAccessReview         = $mostRecentQueryData.startDateTime
                                    endDateTimeMostRecentAccessReview           = $mostRecentQueryData.endDateTime
                                    AccessReviewStatus                          = $mostRecentQueryData.status
                                }
                        
                                $accessReviewList +=  $accessReviewInfo 
                            }
                        }
                        else{
                            Write-Host "Query response data count is: $($queryResponseData.'@odata.count')"
                        }
                    }
                    catch {
                        $errorMsg = "Failed to call Microsoft Graph REST API at URL '$cleanQueryURI'; returned error message: $_"                
                        $ErrorList.Add($errorMsg)
                        Write-Error "Error: $errorMsg"
                    }
                }
                
                # check if the access review is within the last year
                $oneYearAgo = (Get-Date).AddYears(-1)
                $accessReviewList | ForEach-Object {
                    $review = $_
                    $reviewAge = [datetime]::Parse($review.endDateTimeMostRecentAccessReview)
                    $isWithinLastOneYear = if ($reviewAge -ge $oneYearAgo){$true} else {$false}
                    $review | Add-Member -MemberType NoteProperty -Name "isWithinLastOneYear" -Value $isWithinLastOneYear
                }
                
                # validation: any of the access review is within last one year
                $anyReviewWithinOneYear = $accessReviewList | Where-Object { $_.isWithinLastOneYear -eq $true }
                if ($anyReviewWithinOneYear.Count -ge 1){
                    $IsCompliant = $true
                    $commentsArray = $msgTable.isCompliant + " " + $msgTable.hasScheduledAccessReview
                }
                else{
                    $commentsArray = $msgTable.isNotCompliant + " " + $msgTable.noScheduledAccessReview
                }
            }
        }
        else{
            Write-Host "Graph query response data is null: $data"
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
        ComplianceResults   = $PsObject
        Errors              = $ErrorList
        AdditionalResults   = $AdditionalResults
    }
    return $moduleOutput   
}