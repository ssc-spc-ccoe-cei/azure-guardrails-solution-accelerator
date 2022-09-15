    # PART 2 - Checking for GUEST accounts  
    # Note that this URL only reads from the All-Users (not the deleted accounts) in the directory, 
    # This querly looks for accounts marked as GUEST
    # It does not list GUEST accounts from the list of deleted accounts.
    
    function Check-ExternalUsers  {
        Param ( 
            [string] $token, 
            [string] $ControlName, 
            [string] $ItemName, 
            [string] $WorkSpaceID, 
            [string] $workspaceKey, 
            [string] $LogType,
            [string] $itsgcode,
            [hashtable] $msgTable,
            [Parameter(Mandatory=$true)]
            [string]
            $ReportTime
            )
    
    [psCustomObject] $guestUsersArray = New-Object System.Collections.ArrayList
    [bool] $IsCompliant= $false
    
    $stopWatch = New-Object -TypeName System.Diagnostics.Stopwatch 
    $stopWatch.Start()

    # Only get the Guests accounts
    Write-Output "Getting guest users in the tenant"
    $guestUsers = Get-AzADUser -Filter "usertype eq 'guest'" 

    if ($null -eq $guestUsers) {
        # There are no Guest users in the tenant
        $IsCompliant= $true
        $comment = $msgTable.noGuestAccounts
        $MitigationCommands = "N/A"
    }
    else {
        Write-Output "Found $($guestUsers.Count) Guest Users in the tenant"

        $subs=Get-AzSubscription | Where-Object {$_.State -eq 'Enabled'}
        Write-Output "Found $($subs.Count) subscriptions"

        foreach ($sub in $subs) {
            $scope="/subscriptions/$($sub.Id)"
            Write-Output "Looking in subscription $($sub.Name)"

            # Get the role assignments for this subscription
            $subRoleAssignments = Get-AzRoleAssignment -Scope $scope

            if (!$null -eq $subRoleAssignments) {
                Write-Output "Found $($subRoleAssignments.Count) Role Assignments in that subscription"

                # Find each guest users having a role assignment
                $matchedUser = $guestUsers | Where-Object {$subRoleAssignments.ObjectId -contains $_.Id}  

                if (!$null -eq $matchedUser) {
                    Write-Output "Found $($matchedUser.Count) Guest users with role assignment"

                    foreach ($user in $matchedUser) {
                        # What should we do if the same user may has multiple role assignments ?

                        $Customuser = [PSCustomObject] @{
                            DisplayName = $user.DisplayName
                            Subscription = $sub.Name
                            Mail = $user.mail
                            Type = $user.userType
                            CreatedDate = $user.createdDateTime
                            Enabled = $user.accountEnabled
                            Comments = $msgTable.guestMustbeRemoved
                            ItemName= $ItemName 
                            ReportTime = $ReportTime
                            itsgcode = $itsgcode                            
                        }
                        $guestUsersArray.add($Customuser)
                    }
                }
            }
        }

        if ($guestUsersArray.Count -eq 0) {
            # Guest accounts don't have any permissions on the Azure subscriptions, it's fine
            $IsCompliant= $true
            $comment = $msgTable.guestAccountsNoPermission
            $MitigationCommands = "N/A"    

            $Customuser = [PSCustomObject] @{
                DisplayName = "N/A"
                Subscription = "N/A"
                Mail = "N/A"
                Type = "N/A"
                CreatedDate = "N/A"
                Enabled = "N/A"
                Comments = $comment
                ItemName= $ItemName 
                ReportTime = $ReportTime
                itsgcode = $itsgcode                
            }
            $guestUsersArray.add($Customuser)    
        }
        else {
            $IsCompliant= $false
            $comment = $msgTable.removeGuestAccountsComment
            $MitigationCommands = $msgTable.removeGuestAccounts
        }

        # Convert data to JSON format for input in Azure Log Analytics
        $JSONGuestUsers = ConvertTo-Json -inputObject $guestUsersArray
        Write-Output "Creating Log Analytics entry for $($guestUsersArray.Count) Guest Users"

        # Add the list of non-compliant users to Log Analytics (in a different table)
        Send-OMSAPIIngestionFile  -customerId $WorkSpaceID -sharedkey $workspaceKey `
        -body $JSONGuestUsers -logType "GR2ExternalUsers" -TimeStampField Get-Date
    }

    $GuestUserStatus = [PSCustomObject]@{
        ComplianceStatus= $IsCompliant
        ControlName = $ControlName
        Comments= $comment
        ItemName= $ItemName
        itsgcode = $itsgcode        
        ReportTime = $ReportTime
        MitigationCommands = $MitigationCommands
    }

    $logAnalyticsEntry = ConvertTo-Json -inputObject $GuestUserStatus
        
    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID -sharedkey $workspaceKey -body $logAnalyticsEntry `
                                -logType $LogType -TimeStampField Get-Date                 

    
    $stopWatch.Stop()
    Write-Output "CheckExternalAccounts ran for: $($StopWatch.Elapsed.ToString()) "
}