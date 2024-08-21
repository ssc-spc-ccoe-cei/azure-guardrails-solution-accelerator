    # Checking for GUEST accounts  
    # Note that this URL only reads from the All-Users (not the deleted accounts) in the directory, 
    # This query looks for accounts marked as GUEST
    # It does not list GUEST accounts from the list of deleted accounts.
    
    function Check-ExternalUsers  {
        Param ( 
            [string] $ControlName, 
            [string] $ItemName, 
            [string] $itsgcode,
            [hashtable] $msgTable,
            [Parameter(Mandatory=$true)]
            [string] $ReportTime,
            [string] $CloudUsageProfiles = "3",  # Passed as a string
            [string] $ModuleProfiles,  # Passed as a string
            [switch] $EnableMultiCloudProfiles # New feature flag, default to false    
        )
    
    [psCustomObject] $guestUsersArray = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    [bool] $IsCompliant= $false

    $guestUsers_wo_matchedUsers = @()
    $guestUsersArray_grouped = @()
    $unique_guestUsersArray = @()
    
    $stopWatch = New-Object -TypeName System.Diagnostics.Stopwatch 
    $stopWatch.Start()

    # Only get the Guests accounts
    if ($debug) {Write-Output "Getting guest users in the tenant"}
    $guestUsers = Get-AzADUser -Filter "usertype eq 'guest'"
    
    # Default pass (v2.0) for no guest account OR if Guest accounts whether or not have any permissions on the Azure subscriptions
    $IsCompliant= $true
    
    # Find the number of guest accounts
    if ($null -eq $guestUsers) {
        # There are no Guest users in the tenant
        Write-Output "No Guest Users found in the tenant"
        $comment = $msgTable.noGuestAccounts
        $MitigationCommands = "N/A"
    }
    else {
        if ($debug) {Write-Output "Found $($guestUsers.Count) Guest Users in the tenant"}
        # get the Azure subscriptions
        $subs=Get-AzSubscription -ErrorAction SilentlyContinue| Where-Object {$_.State -eq 'Enabled'}
        if ($debug) {Write-Output "Found $($subs.Count) subscriptions"}

        foreach ($sub in $subs) {
            $scope="/subscriptions/$($sub.Id)"
            if ($debug) {Write-Output "Looking in subscription $($sub.Name)"}

            # Get the role assignments for this subscription
            $subRoleAssignments = Get-AzRoleAssignment -Scope $scope

            if (!$null -eq $subRoleAssignments) {
                if ($debug) {Write-Output "Found $($subRoleAssignments.Count) Role Assignments in that subscription"}

                # Find each guest users having a role assignment
                $matchedUser = $guestUsers | Where-Object {$subRoleAssignments.ObjectId -contains $_.Id}
                if (!$null -eq $matchedUser) {
                    if ($debug) {Write-Output "Found $($matchedUser.Count) Guest users with role assignment"}

                    foreach ($user in $matchedUser) {
                        # What should we do if the same user may has multiple role assignments ?

                        $Customuser = [PSCustomObject] @{
                            DisplayName = $user.DisplayName
                            Subscription = $sub.Name
                            Mail = $user.mail
                            Type = $user.userType
                            CreatedDate = $user.createdDateTime
                            Enabled = $user.accountEnabled
                            Roles = "True"                           # At least one role assigned to the user in this scope(i.e. subscription)
                            Comments = $msgTable.guestAssigned
                            ItemName= $ItemName 
                            ReportTime = $ReportTime
                            itsgcode = $itsgcode                            
                        }
                        $guestUsersArray.add($Customuser)
                    }
                }
                else{
                    Write-Output "Found no Guest users with role assignment"
                }
                
                # Find any guest users without having a role assignment
                $guestUsers_wo_matchedUsers = $guestUsers | Where-Object { $_ -notin $matchedUser }  
                if (!$null -eq $guestUsers_wo_matchedUsers) {
                    
                    # Add the guest users without role assignment to the list
                    foreach ($user in $guestUsers_wo_matchedUsers) {
                        $Customuser_noMatch = [PSCustomObject] @{
                            DisplayName = $user.DisplayName
                            Subscription = $sub.Name
                            Mail = $user.mail
                            Type = $user.userType
                            CreatedDate = $user.createdDateTime
                            Enabled = $user.accountEnabled
                            Roles = "False"                        # No role assigned to the user in this scope(i.e. subscription)
                            Comments = $msgTable.guestNotAssigned
                            ItemName= $ItemName 
                            ReportTime = $ReportTime
                            itsgcode = $itsgcode                            
                        }
                        $guestUsersArray.add($Customuser_noMatch)
                    }
                }
                else{
                    Write-Output "All Guest users have role assignment"
                }

                
            }
        }
    }

    # If there are no Guest accounts or Guest accounts don't have any permissions on the Azure subscriptions, it's fine
    # we still create the Log Analytics table
    if ($guestUsersArray.Count -eq 0) {
        $MitigationCommands = "N/A"             
        # Don't overwrite the comment if there are no guest users
        if (!$null -eq $guestUsers) {
            $comment = $msgTable.guestAccountsNoPermission
        }
        
        $Customuser = [PSCustomObject] @{
            DisplayName = "N/A"
            Subscription = "N/A"
            Mail = "N/A"
            Type = "N/A"
            CreatedDate = "N/A"
            Enabled = "N/A"
            Roles = "N/A"
            Comments = $comment
            ItemName= $ItemName 
            ReportTime = $ReportTime
            itsgcode = $itsgcode
        }
        $guestUsersArray.add($Customuser)
    }
    else {
        $comment = $msgTable.existingGuestAccountsComment
        $MitigationCommands = $msgTable.existingGuestAccounts

        # Group by DisplayName and others, aggregate Subscription
        $guestUsersArray_grouped = $guestUsersArray | Group-Object -Property DisplayName, Roles, Comments | ForEach-Object {
            $subscriptions = $_.Group.Subscription -join ', '
            [PSCustomObject]@{
                DisplayName = $_.Group[0].DisplayName
                Subscription = $subscriptions
                Mail = $_.Group[0].Mail
                Type = $_.Group[0].Type
                CreatedDate = $_.Group[0].CreatedDate
                Enabled = $_.Group[0].Enabled
                Role = $_.Group[0].Roles
                Comments = $_.Group[0].Comments
                ItemName= $_.Group[0].ItemName 
                ReportTime = $_.Group[0].ReportTime
                itsgcode = $_.Group[0].itsgcode
            }
        } 
        $filtered_unique_guestUsersArray_grouped = $guestUsersArray_grouped |
            Sort-Object -Property Role -Descending |  # Sort by Role descending so True comes before False
            Sort-Object -Property DisplayName -Unique  # Get unique DisplayNames, keeping the first occurrence  

        # Modify Subscription field to blank if Role = False
        $unique_guestUsersArray = $filtered_unique_guestUsersArray_grouped | ForEach-Object {
            if ($_.Role -eq "False") {
                $_.Subscription = ""
            }
            $_  # Output the modified object
        }
    }

    # Convert data to JSON format for input in Azure Log Analytics
    # $JSONGuestUsers = ConvertTo-Json -inputObject $guestUsersArray
    # Write-Output "Creating or updating Log Analytics table 'GR2ExternalUsers' and adding '$($guestUsers.Count)' guest user entries"

    # Add the list of non-compliant users to Log Analytics (in a different table)
    <#Send-OMSAPIIngestionFile  -customerId $WorkSpaceID -sharedkey $workspaceKey `
    -body $JSONGuestUsers -logType "GR2ExternalUsers" -TimeStampField Get-Date#>

    $GuestUserStatus = [PSCustomObject]@{
        ComplianceStatus= $IsCompliant
        ControlName = $ControlName
        Comments= $comment
        ItemName= $ItemName
        itsgcode = $itsgcode        
        ReportTime = $ReportTime
        MitigationCommands = $MitigationCommands
    }
    $AdditionalResults = [PSCustomObject]@{
        records = $unique_guestUsersArray
        logType = "GR2ExternalUsers"
    }

    # Conditionally add the Profile field based on the feature flag
    if ($EnableMultiCloudProfiles) {
        $result = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        if ($result -is [int]) {
            Write-Output "Valid profile returned: $result"
            $GuestUserStatus | Add-Member -MemberType NoteProperty -Name "Profile" -Value $result
        } elseif ($result -is [hashtable] -and $result.Status -eq "Error") {
            Write-Error "Error occurred: $($result.Message)"
            $GuestUserStatus.ComplianceStatus = "Not Applicable"            
            Errorslist.Add($result.Message)
        } else {
            Write-Error "Unexpected result type: $($result.GetType().Name), Value: $result"
        }        
    }
    

    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $GuestUserStatus
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput 
    <#
    $logAnalyticsEntry = ConvertTo-Json -inputObject $GuestUserStatus
        
    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID -sharedkey $workspaceKey -body $logAnalyticsEntry `
                                -logType $LogType -TimeStampField Get-Date                 
    #>
    
    $stopWatch.Stop()
    if ($debug) {Write-Output "CheckExternalAccounts ran for: $($StopWatch.Elapsed.ToString()) "}
}
