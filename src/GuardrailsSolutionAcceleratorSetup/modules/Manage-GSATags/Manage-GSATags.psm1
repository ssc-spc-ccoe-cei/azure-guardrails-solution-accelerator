# Deployment tags come from two sources: GitHub owns the three release keys;
# clients own every other key. Never use the editable file as a release fallback.
$script:MandatoryTagKeys = @('Solution', 'ReleaseVersion', 'ReleaseDate')

function ConvertTo-GSATagTable {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][object]$InputObject)

    # Keep compatibility with tags.json's historical single-object array.
    if ($InputObject -is [array]) {
        if ($InputObject.Count -ne 1) { throw 'Tags must be an object or an array containing exactly one object.' }
        $InputObject = $InputObject[0]
    }
    if ($InputObject -isnot [System.Collections.IDictionary]) {
        throw 'Tags must be a JSON object of tag names and values.'
    }
    # Copy into a table that treats tag names without regard to case, as Azure does.
    # This lets the installer remove local mandatory keys even when a client writes
    # them as 'solution' or 'RELEASEVERSION', before inserting the official values.
    $result = @{}
    foreach ($key in $InputObject.Keys) {
        $result[$key] = $InputObject[$key]
    }
    return $result
}

function Get-GSADeploymentTags {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SourceRef,
        [Parameter(Mandatory)][object]$ClientTags
    )
    $sourceUri = 'https://raw.githubusercontent.com/ssc-spc-ccoe-cei/azure-guardrails-solution-accelerator/{0}/setup/tags.json' -f [uri]::EscapeDataString($SourceRef)
    # Fetch exactly the selected source. Any HTTP/JSON/metadata failure stops the
    # deployment before Azure writes; local mandatory values are never a fallback.
    $response = Invoke-WebRequest -Uri $sourceUri -TimeoutSec 120 -ErrorAction Stop -Verbose:$false
    $official = ConvertTo-GSATagTable -InputObject (ConvertFrom-Json -InputObject $response.Content -AsHashtable -ErrorAction Stop)
    $mandatory = @{}
    foreach ($key in $script:MandatoryTagKeys) {
        if ($official[$key] -isnot [string] -or [string]::IsNullOrWhiteSpace($official[$key])) {
            throw "GitHub source '$SourceRef' must define a non-empty string for mandatory tag '$key'."
        }
        $mandatory[$key] = $official[$key]
    }
    $custom = ConvertTo-GSATagTable -InputObject $ClientTags
    foreach ($key in $script:MandatoryTagKeys) { $custom.Remove($key) }
    # Match the earlier Az tag conversion for client scalars, including null.
    # Do this after removing reserved keys so GitHub metadata stays strictly typed.
    foreach ($key in @($custom.Keys)) {
        $value = $custom[$key]
        if ($null -eq $value) {
            $custom[$key] = ''
        }
        elseif ($value -is [string] -or $value -is [ValueType]) {
            $custom[$key] = $value.ToString()
        }
        else {
            throw "Custom tag '$key' must contain a scalar value, not an array or object."
        }
    }
    foreach ($key in $script:MandatoryTagKeys) { $custom[$key] = $mandatory[$key] }
    return $custom
}

function Set-GSATagPolicies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [switch]$Prepare
    )
    $subscriptionScope = '/subscriptions/{0}' -f $Config.runtime.subscriptionId
    $scope = '{0}/resourceGroups/{1}' -f $subscriptionScope, $Config.runtime.resourceGroup
    $names = @('guardrails-mandatory-rg-tags', 'guardrails-mandatory-resource-tags')
    $newTags = [ordered]@{}
    foreach ($key in $script:MandatoryTagKeys) {
        $value = $Config.runtime.tagsTable[$key]
        if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) {
            throw "Cannot configure tag policies without an official '$key' value."
        }
        $newTags[$key] = $value
    }
    $allowed = @($newTags)

    if ($Prepare) {
        $hasAssignments = $false
        # Reuse only sets already accepted by these assignments, never editable
        # resource tags. Keeping the old set lets the backend use its saved baseline
        # until this deployment succeeds. Read both assignments before changing either.
        foreach ($name in $names) {
            $response = Invoke-AzRestMethod -Method GET -Path "$scope/providers/Microsoft.Authorization/policyAssignments/${name}?api-version=2024-04-01" -ErrorAction Stop
            if ([int]$response.StatusCode -eq 404) { continue }
            if ([int]$response.StatusCode -ne 200) { throw "Could not read tag policy '$name': $($response.Content)" }
            $hasAssignments = $true
            $assignment = $response.Content | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            $sets = @($assignment.properties.parameters.allowedTagSets.value)
            if ($sets.Count -eq 0) { throw "Tag policy '$name' has no accepted tag sets." }
            foreach ($set in $sets) {
                $previous = [ordered]@{}
                foreach ($key in $script:MandatoryTagKeys) {
                    if ($set[$key] -isnot [string] -or [string]::IsNullOrWhiteSpace($set[$key])) {
                        throw "Tag policy '$name' has an invalid '$key' value."
                    }
                    $previous[$key] = $set[$key]
                }
                $serialized = ConvertTo-Json $previous -Compress
                if (@($allowed | Where-Object { (ConvertTo-Json $_ -Compress) -ceq $serialized }).Count -eq 0) {
                    $allowed += $previous
                }
            }
        }
        # A failed update can leave two accepted sets. Retry that release (or the
        # previous one) before introducing a third; do not accumulate old exceptions.
        if ($allowed.Count -gt 2) {
            throw 'A previous tag-policy transition is unfinished. Rerun that release or the previous release before deploying a different release.'
        }

        # Write definitions directly so policy management needs no subscription
        # deployment permission. Inherited User Access Administrator, Resource
        # Policy Contributor or Owner can supply the required authorization rights.
        # Definitions are shared within the subscription; assignments below limit
        # enforcement to this CaC RG. Stop before core writes if either PUT fails.
        foreach ($name in $names) {
            $isResourceGroup = $name -eq $names[0]
            $target = if ($isResourceGroup) {
                @{ field = 'type'; equals = 'Microsoft.Resources/subscriptions/resourceGroups' }
            }
            else {
                # Indexed mode skips unsupported types. Match only top-level
                # resources; children need separate deployment and repair coverage.
                @{ value = "[length(split(field('type'), '/'))]"; equals = 2 }
            }
            # Accept a complete release set, not a mixture of old and new values.
            # Array contains compares values case-sensitively, unlike policy equals.
            $tagConditions = @(foreach ($key in $script:MandatoryTagKeys) {
                @{ value = "[contains(createArray(field('tags[$key]')), current('tagSet').$key)]"; equals = $true }
            })
            $body = @{
                properties = @{
                    displayName = if ($isResourceGroup) { 'Protect CaC mandatory resource group tags' } else { 'Protect CaC mandatory resource tags' }
                    policyType = 'Custom'
                    mode = if ($isResourceGroup) { 'All' } else { 'Indexed' }
                    metadata = @{ category = 'Tags' }
                    parameters = @{
                        allowedTagSets = @{
                            type = 'Array'
                            metadata = @{ description = 'Complete mandatory tag sets accepted for this deployment. Custom tags are unrestricted.' }
                        }
                    }
                    policyRule = @{
                        if = @{
                            allOf = @($target, @{
                                count = @{
                                    value = "[parameters('allowedTagSets')]"
                                    name = 'tagSet'
                                    where = @{ allOf = $tagConditions }
                                }
                                equals = 0
                            })
                        }
                        then = @{ effect = 'deny' }
                    }
                }
            } | ConvertTo-Json -Depth 20
            $response = Invoke-AzRestMethod -Method PUT -Path "$subscriptionScope/providers/Microsoft.Authorization/policyDefinitions/${name}?api-version=2023-04-01" -Payload $body -ErrorAction Stop
            if ([int]$response.StatusCode -notin 200, 201) { throw "Could not create tag policy definition '$name': $($response.Content)" }
        }

        # On first enablement, wait until deployment and configuration export
        # succeed before assigning either policy. This applies to fresh installs
        # and existing installations without policies: a failed attempt must not
        # block repair using their previously saved Key Vault baseline.
        if (-not $hasAssignments) { return }
    }

    # Apply the accepted sets to both RG-scoped assignments. Before deployment,
    # -Prepare includes the previous and selected sets so upgrades can proceed.
    # The installer calls again without -Prepare only after the selected components
    # and configuration export succeed; that call allows only the newly saved set.
    # First enablement also reaches this block only on that successful final call.
    foreach ($name in $names) {
        $body = @{
            properties = @{
                displayName = $name
                policyDefinitionId = "$subscriptionScope/providers/Microsoft.Authorization/policyDefinitions/$name"
                enforcementMode = 'Default'
                parameters = @{ allowedTagSets = @{ value = $allowed } }
                nonComplianceMessages = @(@{ message = 'Solution, ReleaseVersion and ReleaseDate must match an accepted Guardrails deployment. Custom tags are allowed.' })
            }
        } | ConvertTo-Json -Depth 10
        $response = Invoke-AzRestMethod -Method PUT -Path "$scope/providers/Microsoft.Authorization/policyAssignments/${name}?api-version=2024-04-01" -Payload $body -ErrorAction Stop
        if ([int]$response.StatusCode -notin 200, 201) { throw "Could not assign tag policy '$name': $($response.Content)" }
    }
    # Assignment writes do not make enforcement instantaneous. Core writes retry
    # denials from these policies while Azure propagates the new accepted set.
    if ($Prepare) {
        Write-Verbose 'Mandatory tag policies accept the previous and selected release during deployment.'
    }
    else {
        Write-Host 'Mandatory tag policies now specify only the saved release. Azure enforcement changes can take several minutes to propagate.'
    }
}

function Invoke-GSATagPolicyOperation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][scriptblock]$Operation)

    # Retry only our tag-policy denials, at most 20 times with 30-second waits.
    # A new assignment can still enforce its previous parameters briefly. Do not hide unrelated
    # policy, permission or deployment failures behind a generic retry loop.
    for ($attempt = 0; $attempt -le 20; $attempt++) {
        try { return (& $Operation) }
        catch {
            $errorText = ($_ | Out-String) + $_.ErrorDetails.Message
            if ($attempt -eq 20 -or $errorText -notmatch 'RequestDisallowedByPolicy' -or
                $errorText -notmatch 'guardrails-mandatory-(rg|resource)-tags') { throw }
            Write-Warning 'Waiting 30 seconds for the Guardrails tag-policy update to propagate before retrying.'
            Start-Sleep -Seconds 30
        }
    }
}

Export-ModuleMember -Function ConvertTo-GSATagTable, Get-GSADeploymentTags, Set-GSATagPolicies, Invoke-GSATagPolicyOperation
