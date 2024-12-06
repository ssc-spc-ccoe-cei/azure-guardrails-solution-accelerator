function Expand-ListColumns {
    param (
        [Parameter(Mandatory = $true)]
        [Array]$accessReviewList  # The input list of access review objects
    )

    $expandedList = @()

    # Iterate through each item in the $accessReviewList
    foreach ($reviewInfo in $accessReviewList) {
        # Determine the maximum number of elements in the lists you want to expand
        $maxCount = @(
            $reviewInfo.AccessReviewScopeList.Count,
            $reviewInfo.AccessReviewResourceScopeList.Count,
            $reviewInfo.AccessReviewReviewerList.Count
        ) | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

        # Expand the lists by iterating through each element
        for ($i = 0; $i -lt $maxCount; $i++) {
            $expandedReviewInfo = [PSCustomObject]@{
                AccessReviewName                            = $reviewInfo.AccessReviewName
                AccessReviewInstanceId                      = $reviewInfo.AccessReviewInstanceId
                DescriptionForAdmins                        = $reviewInfo.DescriptionForAdmins
                DescriptionForReviewers                     = $reviewInfo.DescriptionForReviewers
                AccessReviewCreatedBy                       = $reviewInfo.AccessReviewCreatedBy
                AccessReviewStartDate                       = $reviewInfo.AccessReviewStartDate
                AccessReviewEndDate                         = $reviewInfo.AccessReviewEndDate
                AccessReviewStatus                          = $reviewInfo.AccessReviewStatus
                AccesReviewRecurrenceType                   = $reviewInfo.AccesReviewRecurrenceType
                AccesReviewRecurrencePattern                = $reviewInfo.AccesReviewRecurrencePattern
                AccessReviewScope                           = if ($reviewInfo.AccessReviewScopeList.Count -gt $i) { $reviewInfo.AccessReviewScopeList[$i] } else { $null }
                AccessReviewReviewer                        = if ($reviewInfo.AccessReviewReviewerList.Count -gt $i) { $reviewInfo.AccessReviewReviewerList[$i] } else { $null }
                AccessReviewResourceScope                   = if ($reviewInfo.AccessReviewResourceScopeList.Count -gt $i) { $reviewInfo.AccessReviewResourceScopeList[$i] } else { $null }
            }

            # Add the expanded row to the new list
            $expandedList += $expandedReviewInfo
        }
    }

    # Return the expanded list
    return $expandedList
}

function Check-GuestRoleReviews {
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
            
            # Condition: any access review exist. if not, non-compliant
            if ($accessReviewsSorted.Count -eq 0) {
                $commentsArray = $msgTable.isNotCompliant + " " + $msgTable.noAutomatedAccessReview
            }
            else{
                Write-Host "Tenant has been onboarded to automated MS Access Reviews and has at least one access review."

                # filter out non-active the access reviews
                # query status can be 'Completed','InProgress', 'Applied', 'NotStarted'
                $accessReviewHistory = $accessReviewsSorted | Where-Object { $_.status -ne 'Completed'} 
                $accessReviewHistory = $accessReviewHistory | Where-Object { $_.status -ne 'NotStarted'}
                Write-Host "Number of most recent access review with in-progress review:  $($accessReviewHistory.count)"
                # Condition: any access review are in active status. if not, non-compliant
                if ($accessReviewHistory.Count -eq 0) {
                    $commentsArray = $msgTable.isNotCompliant + " " + $msgTable.noInProgressAccessReview
                }
                else{
                    # Get roles and user data
                    $allRoleDefinitions = Get-AzRoleDefinition | Select-Object Name, Id, Description, IsCustom, Actions
                    # $allGroupDefinitions =  Get-AzADGroup
                    $allUserInfo = Get-AzADUser

                    # loop through the access reviews to get metadata
                    foreach($review in $accessReviewHistory){
                        
                        $accessReviewInfo = [PSCustomObject]@{
                            AccessReviewName                = $review.displayName
                            AccessReviewInstanceId          = $review.id
                            DescriptionForAdmins            = $review.descriptionForAdmins
                            DescriptionForReviewers         = $review.descriptionForReviewers
                            AccessReviewCreatedBy           = $review.createdBy.userPrincipalName
                            AccessReviewStartDate           = $review.settings.recurrence.range.startDate
                            AccessReviewEndDate             = $review.settings.recurrence.range.endDate
                            AccessReviewStatus              = $review.status
                            AccesReviewRecurrenceType       = $review.settings.recurrence.range.type
                            AccesReviewRecurrencePattern    = $review.settings.recurrence.pattern.type
                            AccessReviewScopeList           = $review.scope.principalScopes.query
                            AccessReviewResourceScopeList   = $review.scope.resourceScopes
                            AccessReviewReviewerList        = $review.reviewers.query    # For iteration2, get the UPN of these reviewers 
                        }
                
                        $accessReviewList +=  $accessReviewInfo
                    }
                    
                    # Expand the list
                    $expandedList = Expand-ListColumns -accessReviewList $accessReviewList

                    foreach ($review in $expandedList){
                        $reviewerUPN = ""
                        foreach ($reviewer in $review.AccessReviewReviewerList) {
                            $user = $allUserInfo | Where-Object { $_.Id -eq $reviewer }
                            if ($user) {
                                $reviewerUPN = $user.UserPrincipalName
                            }
                        }
                        $review | Add-Member -MemberType NoteProperty -Name "reviewerUPN" -Value $reviewerUPN

                    }
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