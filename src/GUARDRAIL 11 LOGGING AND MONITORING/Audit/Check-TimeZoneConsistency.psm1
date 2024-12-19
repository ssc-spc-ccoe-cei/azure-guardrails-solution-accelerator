function Check-TimeZoneConsistency {
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
        [string] $CloudUsageProfiles = "3",
        [string] $ModuleProfiles,
        [switch] $EnableMultiCloudProfiles
    )

    $complianceResults = [System.Collections.ArrayList]@()
    $ErrorList = [System.Collections.ArrayList]@()
    $tzSettings = [System.Collections.ArrayList]@()

    try {
        # Get all subscriptions
        $subs = Get-AzSubscription -ErrorAction Stop | Where-Object { $_.State -eq 'Enabled' }
        
        foreach ($sub in $subs) {
            $IsCompliant = $false
            $Comments = ""
            $tzSettings = [System.Collections.ArrayList]@()

            Select-AzSubscription -SubscriptionObject $sub | Out-Null

            # # 1. Check App Services and Functions
            # $webApps = Get-AzWebApp
            # foreach ($app in $webApps) {
            #     $appKind = $app.Kind.ToLower()
            #     $resourceType = if ($appKind -contains "functionapp") { "Function App" } else { "App Service" }
                
            #     $tzSettings.Add([PSCustomObject]@{
            #         ResourceType = $resourceType
            #         ResourceName = $app.Name
            #         TimeZone = $app.SiteConfig.TimeZone
            #         Subscription = $sub.Name
            #     }) | Out-Null
            # }

            # 2. Check Virtual Machines
            # $vms = Get-AzVM
            # foreach ($vm in $vms) {
            #     # Get VM timezone through run command (Windows) or SSH (Linux)
            #     $isWindowsVM = $null -ne $vm.OSProfile.WindowsConfiguration
            #     if ($isWindowsVM) {
            #         $tzCommand = Invoke-AzVMRunCommand -ResourceGroupName $vm.ResourceGroupName -VMName $vm.Name -CommandId 'RunPowerShellScript' -ScriptString '[System.TimeZoneInfo]::Local.Id'
            #         $vmTimeZone = $tzCommand.Value[0].Message
            #     } else {
            #         # For Linux, we'd read /etc/timezone if accessible
            #         $tzCommand = Invoke-AzVMRunCommand -ResourceGroupName $vm.ResourceGroupName -VMName $vm.Name -CommandId 'RunShellScript' -ScriptString 'cat /etc/timezone'
            #         $vmTimeZone = $tzCommand.Value[0].Message
            #     }

            #     $tzSettings.Add([PSCustomObject]@{
            #         ResourceType = "Virtual Machine"
            #         ResourceName = $vm.Name
            #         TimeZone = $vmTimeZone
            #         Subscription = $sub.Name
            #     }) | Out-Null
            # }

            # # 3. Check SQL Databases
            # $sqlServers = Get-AzSqlServer
            # foreach ($server in $sqlServers) {
            #     $databases = Get-AzSqlDatabase -ServerName $server.ServerName -ResourceGroupName $server.ResourceGroupName
            #     foreach ($db in $databases) {
            #         $tzSettings.Add([PSCustomObject]@{
            #             ResourceType = "SQL Database"
            #             ResourceName = "$($server.ServerName)/$($db.DatabaseName)"
            #             TimeZone = $server.TimeZone
            #             Subscription = $sub.Name
            #         }) | Out-Null
            #     }
            # }

            # # 4. Check Container Apps
            # $containerApps = Get-AzContainerApp
            # foreach ($app in $containerApps) {
            #     $tzSettings.Add([PSCustomObject]@{
            #         ResourceType = "Container App"
            #         ResourceName = $app.Name
            #         TimeZone = $app.Configuration.ActiveRevisionsMode # Need to check actual TZ property
            #         Subscription = $sub.Name
            #     }) | Out-Null
            # }

            # # 5. Check AKS Clusters
            # $aksClusters = Get-AzAksCluster
            # foreach ($cluster in $aksClusters) {
            #     $tzSettings.Add([PSCustomObject]@{
            #         ResourceType = "AKS Cluster"
            #         ResourceName = $cluster.Name
            #         TimeZone = $cluster.TimeZone # Need to verify actual property
            #         Subscription = $sub.Name
            #     }) | Out-Null
            # }

            # # 6. Check Logic Apps
            # $logicApps = Get-AzLogicApp
            # foreach ($app in $logicApps) {
            #     $tzSettings.Add([PSCustomObject]@{
            #         ResourceType = "Logic App"
            #         ResourceName = $app.Name
            #         TimeZone = $app.Parameters.timeZone.Value
            #         Subscription = $sub.Name
            #     }) | Out-Null
            # }

            # # 7. Check Data Factory
            # $factories = Get-AzDataFactory
            # foreach ($factory in $factories) {
            #     $tzSettings.Add([PSCustomObject]@{
            #         ResourceType = "Data Factory"
            #         ResourceName = $factory.DataFactoryName
            #         TimeZone = $factory.Configuration.TimeZone
            #         Subscription = $sub.Name
            #     }) | Out-Null
            # }

            # # 8. Check Synapse Workspaces
            # $synapseWorkspaces = Get-AzSynapseWorkspace
            # foreach ($workspace in $synapseWorkspaces) {
            #     $tzSettings.Add([PSCustomObject]@{
            #         ResourceType = "Synapse Workspace"
            #         ResourceName = $workspace.Name
            #         TimeZone = $workspace.TimeZone # Need to verify actual property
            #         Subscription = $sub.Name
            #     }) | Out-Null
            # }

            # # 9. Check Batch Accounts
            # $batchAccounts = Get-AzBatchAccount
            # foreach ($account in $batchAccounts) {
            #     $tzSettings.Add([PSCustomObject]@{
            #         ResourceType = "Batch Account"
            #         ResourceName = $account.AccountName
            #         TimeZone = $account.TimeZone # Need to verify actual property
            #         Subscription = $sub.Name
            #     }) | Out-Null
            # }

            # Analyze time zone consistency for this subscription
            $tzGroups = $tzSettings | Where-Object { $null -ne $_.TimeZone } | Group-Object TimeZone
            $totalResources = ($tzSettings | Where-Object { $null -ne $_.TimeZone }).Count
            $resourcesWithoutTZ = ($tzSettings | Where-Object { $null -eq $_.TimeZone }).Count

            if ($totalResources -eq 0) {
                $IsCompliant = $true
                $Comments = "$($sub.Name): $($msgTable.noResourcesFound)"
                if ($resourcesWithoutTZ -gt 0) {
                    $Comments += " $($msgTable.resourcesWithoutTimezone -f $resourcesWithoutTZ)"
                }
            }
            elseif ($tzGroups.Count -eq 1) {
                $IsCompliant = $true
                $Comments = "$($sub.Name): $($msgTable.allResourcesSameTimezone -f $tzGroups[0].Name)"
                if ($resourcesWithoutTZ -gt 0) {
                    $Comments += " $($msgTable.resourcesWithoutTimezone -f $resourcesWithoutTZ)"
                }
            }
            elseif ($tzGroups.Count -eq 2) {
                $IsCompliant = $true
                $majorityTZ = ($tzGroups | Sort-Object Count -Descending)[0]
                $Comments = "$($sub.Name): $($msgTable.twoTimezonesFound -f $majorityTZ.Name, ($majorityTZ.Count / $totalResources * 100))"
                if ($resourcesWithoutTZ -gt 0) {
                    $Comments += " $($msgTable.resourcesWithoutTimezone -f $resourcesWithoutTZ)"
                }
            }
            else {
                $IsCompliant = $false
                $Comments = "$($sub.Name): $($msgTable.multipleTimezonesFound -f $tzGroups.Count)"
                if ($resourcesWithoutTZ -gt 0) {
                    $Comments += " $($msgTable.resourcesWithoutTimezone -f $resourcesWithoutTZ)"
                }
            }

            $PsObject = [PSCustomObject]@{
                ComplianceStatus = $IsCompliant
                ControlName = $ControlName
                Comments = $Comments
                ItemName = $ItemName
                ReportTime = $ReportTime
                itsgcode = $itsgcode
                SubscriptionId = $sub.Id
            }

            # Add profile evaluation if enabled
            if ($EnableMultiCloudProfiles) {
                $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $sub.Id
                if (!$evalResult.ShouldEvaluate) {
                    if ($evalResult.Profile -gt 0) {
                        $PsObject.ComplianceStatus = "Not Applicable"
                        $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                        $PsObject.Comments = "$($sub.Name): Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
                    } else {
                        $ErrorList.Add("Error occurred while evaluating profile configuration for subscription $($sub.Id)")
                    }
                } else {
                    $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
                }
            }

            $complianceResults.Add($PsObject) | Out-Null
        }
    }
    catch {
        $IsCompliant = $false
        $ErrorList.Add("Error checking time zone configurations: $_")
    }

    $moduleOutput = [PSCustomObject]@{
        ComplianceResults = $complianceResults
        Errors = $ErrorList
        AdditionalResults = $tzSettings
    }
    return $moduleOutput
} 