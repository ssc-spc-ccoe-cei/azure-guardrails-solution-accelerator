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
        [string] $CloudUsageProfiles = "3",  # Passed as a string
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
                $commentsArray = $msgTable.isNotCompliant + " " + $msgTable.noAutomatedAccessReviewForGuests
            }
            else{
                Write-Host "Tenant has been onboarded to automated MS Access Reviews and has at least one access review."

                # filter out non-active the access reviews
                # status can be 'Completed','InProgress', 'Applied', 'NotStarted'
                $accessReviewHistory = $accessReviewsSorted | Where-Object { $_.status -ne 'Completed'} 
                $accessReviewHistory = $accessReviewHistory | Where-Object { $_.status -ne 'NotStarted'}
                Write-Host "Number of most recent access review with in-progress review:  $($accessReviewHistory.count)"
                # Condition: any access review are in active status. if not, non-compliant
                if ($accessReviewHistory.Count -eq 0) {
                    $commentsArray = $msgTable.isNotCompliant + " " + $msgTable.noInProgressGuestAccessReview
                }
                else{
                    # get user info
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
                            AccesReviewRecurrencePattern    = if($null -eq $review.settings.recurrence.pattern) {"oneTime"} else {$review.settings.recurrence.pattern.type}
                            AccessReviewScopeList           = if($null -eq $review.scope.principalScopes) {$review.scope.query} else {$review.scope.principalScopes.query}
                            AccessReviewResourceScopeList   = $review.scope.resourceScopes
                            AccessReviewReviewerList        = $review.reviewers.query     
                        }
                
                        $accessReviewList +=  $accessReviewInfo
                    }
                    
                    # Expand the list
                    $expandedList = Expand-ListColumns -accessReviewList $accessReviewList

                    # Get Reviewers' UPN, Iteration #2 work to follow
                    foreach ($review in $expandedList){
                        $reviewerUPN = ""
                        foreach ($reviewer in $review.AccessReviewReviewer) {
                            $id = $reviewer -replace '/v1.0/users/', ''
                            $user = $allUserInfo | Where-Object { $_.Id -eq $id }
                            if ($user) {
                                $reviewerUPN = $user.UserPrincipalName
                            }
                            Write-Host " reviewerUPN:  $reviewerUPN"
                        }
                        $review | Add-Member -MemberType NoteProperty -Name "reviewerUPN" -Value $reviewerUPN
                    }

                    # Get Access review Scope
                    $expandedList | ForEach-Object {
                        $review = $_
                        $scope = if ($null -eq $review.AccessReviewScope) {$null} else { if ($review.AccessReviewScope.ToLower() -like '*guest*') { 'Guest' } else { if($review.AccessReviewScope.ToLower() -like '*groups*') {'Groups'} else {if ($review.AccessReviewScope.ToLower() -like '*users*') {'Users' } else {'Custom'}}}}
                        $review | Add-Member -MemberType NoteProperty -Name "Scope" -Value $scope
                    }

                    # Filter for guest scoped only
                    $guestAccessReviewList = $expandedList | Where-Object { $_.Scope -like '*Guest*' }
                    # Condition: if any access reviews scoped to guest user
                    if( $guestAccessReviewList.Count -eq 0){
                        # No scheduled guest access review
                        $commentsArray = $msgTable.isNotCompliant + " " + $msgTable.noScheduledGuestAccessReview
                    }
                    else{
                        # scheduled guest access review exists
                        # Get scheduled recurrence time and type
                        $guestAccessReviewList | ForEach-Object {
                            $review = $_
                            $today = Get-Date
                            $isPassedToday = if ([datetime]::Parse($_.AccessReviewEndDate) -gt $today) {$true} else {$false}
                            $review | Add-Member -MemberType NoteProperty -Name "isPassedToday" -Value $isPassedToday
                        }

                        $guestAccessReviewList | ForEach-Object {
                            $review = $_
                            $recurrence = if ($review.AccesReviewRecurrenceType -eq 'noEnd' -or $isPassedToday -eq $true) { `
                                if ($review.AccesReviewRecurrencePattern -ne 'oneTime') {'pass'} else {'fail'} `
                        } else {'fail'}
                            $review | Add-Member -MemberType NoteProperty -Name "recurrence" -Value $recurrence
                        }
                        
                        # condition: Check if at-least one object in the guest access review list has 'recurrence' containing 'pass'
                        if ($guestAccessReviewList.recurrence -contains 'pass') {
                            $IsCompliant = $true
                            $commentsArray = $msgTable.isCompliant + " " + $msgTable.compliantRecurrenceGuestReviews
                        } else {
                            $commentsArray = $msgTable.isNotCompliant + " " + $msgTable.nonCompliantRecurrenceReviews
                        }
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
        $result = Add-ProfileInformation -Result $PsObject -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId
        Write-Host "$result"
    }
    
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults   = $PsObject
        Errors              = $ErrorList
        AdditionalResults   = $AdditionalResults
    }
    return $moduleOutput   
}