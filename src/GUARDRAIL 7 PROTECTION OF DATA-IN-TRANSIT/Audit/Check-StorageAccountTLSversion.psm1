function Check-TLSversion {
    param (
        [System.Object] $objList
    )

    Write-Verbose "Starting subscription access verification..."
    
    $storageAccountList = @()
    foreach ($obj in $objList)
    {
        Write-Verbose "Processing Subscription: $($obj.Name) ($($obj.Id))" 

        try {
            # Simplified query to match exactly what we see in Resource Graph
            $query = @"
            resources
            | where type =~ 'Microsoft.Storage/storageAccounts'
            | where subscriptionId =~ '$($obj.Id)'
            | extend minimumTlsVersion = properties.minimumTlsVersion
            | project subscriptionId,
                     resourceGroup = resourceGroup,
                     name,
                     minimumTlsVersion
"@
            
            Write-Verbose "Executing Resource Graph query for subscription: $($obj.Id)"
            $storageAccounts = Search-azgraph -Query $query -ErrorAction Stop
            Write-Verbose "Found $($storageAccounts.Count) storage accounts in subscription"
            
            foreach ($storageAcc in $storageAccounts) {
                Write-Verbose "Processing storage account: $($storageAcc.name)"
                $TLSversionNumeric = $storageAcc.minimumTlsVersion -replace "TLS", "" -replace "_", "."
                $storageAccInfo = [PSCustomObject]@{
                    SubscriptionName   = $obj.Name
                    ResourceGroupName  = $storageAcc.resourceGroup
                    StorageAccountName = $storageAcc.name
                    MinimumTlsVersion = $storageAcc.minimumTlsVersion
                    TLSversionNumeric  = $TLSversionNumeric
                }
                $storageAccountList += $storageAccInfo
            }
        }
        catch {
            Write-Warning "Failed to query storage accounts for subscription '$($obj.Name)': $_"
            continue
        }
    }

    if ($storageAccountList.Count -eq 0) {
        Write-Verbose "No storage accounts found. Current subscription context: $((Get-AzContext).Subscription.Id)"
        Write-Verbose "Number of subscriptions checked: $($objList.Count)"
        Write-Verbose "Subscription IDs checked: $($objList.Id -join ', ')"
    }

    Write-Verbose "Total storage accounts found across all subscriptions: $($storageAccountList.Count)"
    return $storageAccountList
}

function Verify-TLSForStorageAccount {
    <#
    .SYNOPSIS
        Verifies that all storage accounts use TLS 1.2 or higher.

    .DESCRIPTION
        Evaluates storage account TLS configuration per subscription. For each enabled
        subscription, queries Azure Resource Graph for storage accounts and checks their
        minimum TLS version. Produces one compliance result per subscription, enabling
        proper MCUP (Multi-Cloud Usage Profiles) integration.

    .PARAMETER ControlName
        The display name for this guardrail control.

    .PARAMETER ItemName
        The line-item name shown in compliance results.

    .PARAMETER msgTable
        A hashtable containing localized message strings.

    .PARAMETER ReportTime
        The timestamp for this compliance report run.

    .PARAMETER itsgcode
        The ITSG control code associated with this guardrail.

    .PARAMETER CloudUsageProfiles
        A string representing the cloud usage profiles to evaluate against.

    .PARAMETER ModuleProfiles
        A string representing the module profiles configuration.

    .PARAMETER EnableMultiCloudProfiles
        Switch to enable MCUP per-subscription profile evaluation.
    #>
    param (
        [string] $ControlName,
        [string] $ItemName,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string] $ReportTime,
        [string] $itsgcode,
        [string] $CloudUsageProfiles = "3",
        [string] $ModuleProfiles,
        [switch] $EnableMultiCloudProfiles
    )

    [PSCustomObject] $ResultList = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList

    # -------------------------
    # 1) Get enabled subscriptions
    # -------------------------
    try {
        $subs = Get-AzSubscription -ErrorAction Stop | Where-Object { $_.State -eq "Enabled" }
        if (-not $subs) {
            $errorMsg = "No enabled subscriptions found"
            $ErrorList.Add($errorMsg) | Out-Null
            Write-Warning $errorMsg
            return [PSCustomObject]@{
                ComplianceResults = $ResultList
                Errors            = $ErrorList
            }
        }
    }
    catch {
        $errorMsg = "Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installation of the Az.Resources module; returned error message: $_"
        $ErrorList.Add($errorMsg) | Out-Null
        Write-Warning $errorMsg
        throw "Error: $errorMsg"
    }

    # -------------------------
    # 2) Evaluate each subscription individually
    # -------------------------
    foreach ($sub in $subs) {
        $subId   = [string]$sub.Id
        $subName = [string]$sub.Name

        Write-Verbose "Evaluating TLS compliance for subscription: $subName ($subId)"

        $IsCompliant = $false
        $commentsArray = @()

        try {
            $storageAccounts = Check-TLSversion -objList @($sub)

            if ($null -eq $storageAccounts -or @($storageAccounts).Count -eq 0) {
                # No storage accounts in this subscription — compliant by default
                $IsCompliant = $true
                $commentsArray = @($msgTable.isCompliant, $msgTable.storageAccValidTLS)
            }
            else {
                # Filter for non-compliant accounts within this subscription
                $nonCompliantAccounts = @($storageAccounts) |
                    Where-Object { $_.PSObject.Properties["MinimumTlsVersion"] } |
                    Where-Object {
                        $_.MinimumTlsVersion -ne "TLS1_2" -and
                        $_.TLSversionNumeric -lt 1.2
                    }

                if ($nonCompliantAccounts.Count -eq 0) {
                    $IsCompliant = $true
                    $commentsArray = @($msgTable.isCompliant, $msgTable.storageAccValidTLS)
                }
                else {
                    $IsCompliant = $false
                    $nonCompliantNames = ($nonCompliantAccounts |
                        Select-Object -ExpandProperty StorageAccountName) -join ', '
                    Write-Verbose "Non-compliant storage accounts in $subName : $nonCompliantNames"
                    $commentsArray = @($msgTable.isNotCompliant, $msgTable.storageAccNotValidTLS, $msgTable.storageAccNotValidList -f $nonCompliantNames)
                }
            }
        }
        catch {
            $IsCompliant = $false
            $commentsArray = @("Error evaluating storage accounts: $_")
            $ErrorList.Add("Error evaluating storage accounts for subscription $subName ($subId): $_") | Out-Null
        }

        $Comments = $commentsArray -join " "

        $C = [PSCustomObject]@{
            SubscriptionName = $subName
            ComplianceStatus = $IsCompliant
            ControlName      = $ControlName
            ItemName         = $ItemName
            Comments         = $Comments
            ReportTime       = $ReportTime
            itsgcode         = $itsgcode
        }

        # Add profile information if MCUP feature is enabled
        if ($EnableMultiCloudProfiles) {
            $result = Add-ProfileInformation -Result $C -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -SubscriptionId $subId -ErrorList $ErrorList
            [void]$ResultList.Add($result)
        }
        else {
            [void]$ResultList.Add($C)
        }

        Write-Verbose "Completed compliance output for subscription: $subName"
    }

    $moduleOutput = [PSCustomObject]@{
        ComplianceResults = $ResultList
        Errors            = $ErrorList
    }
    return $moduleOutput
}

