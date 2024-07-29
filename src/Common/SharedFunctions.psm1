function Get-ResourceProfile {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ResourceId
    )

    # Ensure Az module is imported
    if (-not (Get-Module -ListAvailable -Name Az)) {
        Import-Module Az
    }

    # Get the resource details
    $resource = Get-AzResource -ResourceId $ResourceId

    if ($null -eq $resource) {
        throw "Resource not found: $ResourceId"
    }

    # Get the subscription ID from the resource
    $subscriptionId = $resource.ResourceId.Split("/")[2]

    # Select the subscription
    Select-AzSubscription -SubscriptionId $subscriptionId

    # Get the resource tags
    $tags = $resource.Tags

    if ($null -eq $tags -or -not $tags.ContainsKey('profile')) {
        throw "Profile tag not found for resource: $ResourceId"
    }

    # Get the profile tag value
    $profileTagValue = $tags['profile']

    # Split the profile tag value into an array of integers
    $profileValues = $profileTagValue -split ',\s*' | ForEach-Object { [int]$_ }

    if ($profileValues.Count -eq 0) {
        throw "No valid profile values found for resource: $ResourceId"
    }

    # Get the highest profile value
    $highestProfile = $profileValues | Sort-Object -Descending | Select-Object -First 1

    return $highestProfile
}
