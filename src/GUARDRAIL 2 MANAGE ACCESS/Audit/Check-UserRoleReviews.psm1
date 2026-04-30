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
        [string] $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] 
        $EnableMultiCloudProfiles # New feature flag, default to false
    )

    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    [bool] $IsCompliant = $false
    [string] $Comments = $null
    
    $accessReviewList = @()

    # Query 1: fetch only active access review definitions using server-side $filter.
    # Graph does not support 'ne' on status for this endpoint; use explicit 'eq' per active
    # status joined with 'or'. $select limits each record to only the fields consumed below.
    # Full status enum per Graph docs: Initializing, NotStarted, Starting, InProgress,
    # Completing, Completed, AutoReviewing, AutoReviewed.
    # 'eq' is the only supported operator on status ($filter eq only - ne/gt/lt return HTTP 400).
    # Exclude only the two terminal/inactive states: Completed and NotStarted.
    $activeStatusFilter = "status eq 'Initializing' or status eq 'Starting' or status eq 'InProgress' or status eq 'Completing' or status eq 'AutoReviewing' or status eq 'AutoReviewed'"
    $urlPath = "/identityGovernance/accessReviews/definitions" +
        "?`$select=id,displayName,status,createdBy,createdDateTime,settings,scope,reviewers,descriptionForAdmins,descriptionForReviewers" +
        "&`$filter=$activeStatusFilter"

    try {
        $response = Invoke-GraphQueryEX -urlPath $urlPath -ErrorAction Stop
        $data = $response.Content
        
        if ($null -ne $data -and $null -ne $data.value) {
            $accessReviewHistory = $data.value | Sort-Object -Property displayName, createdDateTime -Descending
            Write-Host "Number of active access reviews (server-filtered): $($accessReviewHistory.count)"

            if ($accessReviewHistory.Count -eq 0) {
                # No active reviews found; run a cheap single-record existence check to pick the
                # right non-compliant message: "never set up" vs "set up but nothing active now"
                $existCheck = Invoke-GraphQuery -urlPath "/identityGovernance/accessReviews/definitions?`$select=id&`$top=1"
                if ($null -eq $existCheck.Content -or $existCheck.Content.value.Count -eq 0) {
                    $commentsArray = $msgTable.isNotCompliant + " " + $msgTable.noAutomatedAccessReviewForUsers
                } else {
                    $commentsArray = $msgTable.isNotCompliant + " " + $msgTable.noInProgressAccessReview
                }
            }
            else{
                Write-Host "Tenant has been onboarded to automated MS Access Reviews and has at least one active review."
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

                    # Get scheduled recurrence time and type
                    $expandedList | ForEach-Object {
                        $review = $_
                        $today = Get-Date
                        $isPassedToday = if ([datetime]::Parse($_.AccessReviewEndDate) -gt $today) {$true} else {$false}
                        $review | Add-Member -MemberType NoteProperty -Name "isPassedToday" -Value $isPassedToday
                    }

                    $expandedList | ForEach-Object {
                        $review = $_
                        $recurrence = if ($review.AccesReviewRecurrenceType -eq 'noEnd' -or $isPassedToday -eq $true) { `
                            if ($review.AccesReviewRecurrencePattern -ne 'oneTime') {'pass'} else {'fail'} `
                        } else {'fail'}
                        $review | Add-Member -MemberType NoteProperty -Name "recurrence" -Value $recurrence
                    }

                    # Filter for users scoped only i.e. exclude 'guest' reviews
                    $usersAccessReviewList = $expandedList | Where-Object { $_.Scope -like '*Users*' -or $_.Scope -like '*Groups*' }
                    # Condition: if any role access reviews scoped to user or groups
                    if( $usersAccessReviewList.Count -eq 0){
                        # No scheduled user role access review
                        $commentsArray = $msgTable.isNotCompliant + " " + $msgTable.noScheduledUserAccessReview
                    }
                    else{
                        # condition: Check if at-least one object in the role access review list has 'recurrence' containing 'pass'
                        if ($usersAccessReviewList.recurrence -contains 'pass') {
                            $IsCompliant = $true
                            $commentsArray = $msgTable.isCompliant + " " + $msgTable.compliantRecurrenceReviews
                        } else {
                            $commentsArray = $msgTable.isNotCompliant + " " + $msgTable.nonCompliantRecurrenceReviews
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
    
    # Add profile information if MCUP feature is enabled
    if ($EnableMultiCloudProfiles) {
        $result = Add-ProfileInformation -Result $PsObject -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subscriptionId -ErrorList $ErrorList
        Write-Host "$result"
    }
    
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults   = $PsObject
        Errors              = $ErrorList
        AdditionalResults   = $AdditionalResults
    }
    return $moduleOutput   
}