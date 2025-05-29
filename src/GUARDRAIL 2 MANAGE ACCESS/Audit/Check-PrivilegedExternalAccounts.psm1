# Checking for GUEST accounts (Privileged)
# Note that this URL only reads from the All-Users (not the deleted accounts) in the directory, 
# This query looks for accounts marked as GUEST
# It does not list GUEST accounts from the list of deleted accounts.
    
function Check-PrivilegedExternalUsers  {
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
    
    [PSCustomObject] $guestUsersArray = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    [bool] $IsCompliant= $false
    
    $guestUsers_wo_matchedUsers = @()
    $guestUsersArray_grouped = @()
    $unique_guestUsersArray = @()
    
    # Privileged Roles at Subscription level (requirement for GR2 validation 9)
    $privilegedRolesSubscriptionLevel = @("Owner","Contributor","Access Review Operator Service Role","Custom - Landing Zone Application Owner","Custom - Landing Zone Subscription Owner","Role Based Access Control Administrator","User Access Administrator")
    
    $stopWatch = New-Object -TypeName System.Diagnostics.Stopwatch 
    $stopWatch.Start()
    
    # Only get the Guests accounts
    if ($debug) {Write-Output "Getting guest users in the tenant"}
    $guestUsers = Get-AzADUser -Filter "usertype eq 'guest'"

    # Default pass (v2.0) for no guest account OR if Guest accounts whether or not have any permissions on the Azure subscriptions
    $IsCompliant= $true
    
    # Find the number of guest accounts
    if ($null -eq $guestUsers -or $guestUsers.Count -eq 0) {
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
            if ($debug) {Write-Host "Looking in subscription $($sub.Name)"}
    
            # Get the role assignments for this subscription
            $subRoleAssignments = Get-AzRoleAssignment -Scope $scope
    
            if (!$null -eq $subRoleAssignments) {
                if ($debug) {Write-Host "Found $($subRoleAssignments.Count) Role Assignments in that subscription"}
    
                # Find each guest users having a role assignment
                $matchedUser = $guestUsers | Where-Object {$subRoleAssignments.ObjectId -contains $_.Id}
    
                # Filter for User type
                $subRoleAssignmentsUpdated = $subRoleAssignments | Where-Object { @("User","Group") -contains $_.ObjectType }

                # Create a single list with users and their role definitions
                $matchedUserUpdated =@()
                if(!$null -eq $matchedUser){
                    $matchedUserSelected = $matchedUser | Select-Object DisplayName, Id, UserPrincipalName, Mail | Select-Object @{Name='SignInName';Expression={$_.UserPrincipalName}}, DisplayName, Id, Mail
                
                    foreach ($usr in $matchedUserSelected) {
                        $matched = $subRoleAssignmentsUpdated | Where-Object { $_.SignInName -eq $usr.SignInName -and $_.DisplayName -eq $usr.DisplayName }

                        if (!$null -eq $matched) {
                            $joinedItem = [PSCustomObject]@{
                                DisplayName = $usr.DisplayName
                                SignInName = $usr.SignInName
                                Id = $usr.Id
                                Mail = $usr.Mail
                                RoleAssignmentName = $matched.RoleAssignmentName
                                RoleAssignmentId = $matched.RoleAssignmentId
                                Scope = $matched.Scope
                                RoleDefinitionName = $matched.RoleDefinitionName
                                RoleDefinitionId = $matched.RoleDefinitionId
                                ObjectId = $matched.ObjectId
                                ObjectType = $matched.ObjectType
                                CanDelegate = $matched.CanDelegate
                                Description = $matched.Description
                            }
                        }
                        else {
                            $joinedItem = [PSCustomObject]@{
                                DisplayName = $usr.DisplayName
                                SignInName = $usr.SignInName
                                Id = $usr.Id
                                Mail = $usr.Mail
                                RoleAssignmentName = $null
                                RoleAssignmentId = $null
                                Scope = $null
                                RoleDefinitionName = $null
                                RoleDefinitionId = $null
                                ObjectId = $null
                                ObjectType = $null
                                CanDelegate = $null
                                Description = $null
                            }
                        }
                        $matchedUserUpdated += $joinedItem
                    }
                    
                }
                
                if (!$null -eq  $matchedUserUpdated) {
                    # Find matched users with privileged roles
                    $newMatchedUserList = $matchedUserUpdated | ForEach-Object {
                        $roleDefinitions = @($_.RoleDefinitionName)
                        $hasPrivilegedRole = $privilegedRolesSubscriptionLevel | Where-Object { $roleDefinitions -contains $_ }
                        $hasPrivilegedRoleString = if ($hasPrivilegedRole) {'True'} else {'False'}
                        $_ | Add-Member -MemberType NoteProperty -Name privilegedRole -Value $hasPrivilegedRoleString -PassThru
                    }

                    if ($debug) {Write-Output "Found $($newMatchedUserList.Count) Guest users with role assignment"}
    
                    foreach ($user in $newMatchedUserList) {
                        # What should we do if the same user may has multiple role assignments ? - create Unique rows
    
                        $Customuser = [PSCustomObject] @{
                            DisplayName = $user.DisplayName
                            Subscription = $sub.Name
                            Mail = $user.mail
                            Type = $user.userType
                            CreatedDate = $user.createdDateTime
                            Enabled = $user.accountEnabled
                            Role = "True"                           # At least one role assigned to the user in this scope(i.e. subscription)
                            PrivilegedRole = $user.privilegedRole
                            Comments = $msgTable.guestAssigned
                            ItemName= $ItemName 
                            ReportTime = $ReportTime
                            itsgcode = $itsgcode                            
                        }
                        $guestUsersArray.add($Customuser)
                    }
                }
                else{
                    Write-Output "Found no Guest users with role assignment for $($sub.Name)"
                    Write-Host "Found no Guest users with role assignment for $($sub.Name)"
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
                            Role = "False"                        # No role assigned to the user in this scope(i.e. subscription)
                            PrivilegedRole = "False"
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
            $comment = $msgTable.guestAccountsNoPrivilegedPermission
        }
        
        $CustomUser = [PSCustomObject] @{
            DisplayName = "N/A"
            Subscription = "N/A"
            Mail = "N/A"
            Type = "N/A"
            CreatedDate = "N/A"
            Enabled = "N/A"
            Role = "N/A"
            PrivilegedRole = "N/A"
            Comments = $comment
            ItemName= $ItemName 
            ReportTime = $ReportTime
            itsgcode = $itsgcode
        }
    }
    else {
        $comment = $msgTable.existingPrivilegedGuestAccountsComment
        $MitigationCommands = $msgTable.existingPrivilegedGuestAccounts
    
        # Group by DisplayName and others, aggregate Subscription
        $guestUsersArray_grouped = $guestUsersArray | Group-Object -Property DisplayName, Role, Comments | ForEach-Object {
            $subscriptions = $_.Group.Subscription -join ', '
            [PSCustomObject]@{
                DisplayName = $_.Group[0].DisplayName
                Subscription = $subscriptions
                Mail = $_.Group[0].Mail
                Type = $_.Group[0].Type
                CreatedDate = $_.Group[0].CreatedDate
                Enabled = $_.Group[0].Enabled
                Role = $_.Group[0].Role
                PrivilegedRole = $_.Group[0].PrivilegedRole
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
            if ($_.PrivilegedRole -eq "True") {
                $_.Comments += " " + $msgTable.guestHasPrivilegedRole
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
    #condition: no guest user in the tenant
    if($guestUsersArray.Count -eq 0){
        $unique_guestUsersArray = $CustomUser
    }

    $AdditionalResults = [PSCustomObject]@{
        records = $unique_guestUsersArray
        logType = "GR2ExternalUsers"
    }

    # Conditionally add the Profile field based on the feature flag
    if ($EnableMultiCloudProfiles) {        
        $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        if (!$evalResult.ShouldEvaluate) {
            if ($evalResult.Profile -gt 0) {
                $GuestUserStatus.ComplianceStatus = "Not Applicable"
                $GuestUserStatus | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                $GuestUserStatus.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
            } else {
                $ErrorList.Add("Error occurred while evaluating profile configuration")
            }
        } else {
            
            $GuestUserStatus | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
        }
    }
    
    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $GuestUserStatus
        Errors            = $ErrorList
        AdditionalResults = $AdditionalResults
    }

    return $moduleOutput 
    <#
    $logAnalyticsEntry = ConvertTo-Json -inputObject $GuestUserStatus
        
    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID -sharedkey $workspaceKey -body $logAnalyticsEntry `
                                -logType $LogType -TimeStampField Get-Date                 
    #>
    
    $stopWatch.Stop()
    if ($debug) {Write-Output "Check-PriviligedExternalAccounts ran for: $($StopWatch.Elapsed.ToString()) "}
}
    