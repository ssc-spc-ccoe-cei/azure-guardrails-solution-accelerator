[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]
    $GitHubActor,

    [Parameter(Mandatory = $true)]
    [string]
    $GitHubRunId,

    [Parameter(Mandatory = $true)]
    [string]
    $GitHubRunAttempt,

    [Parameter(Mandatory = $true)]
    [string]
    $SuffixEnvironmentVariableName,

    [Parameter(Mandatory = $true)]
    [string]
    $BaseSuffixEnvironmentVariableName
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:GITHUB_ENV)) {
    throw 'GITHUB_ENV is not set. This script is intended to run inside GitHub Actions.'
}

$sanitizedActor = ($GitHubActor.ToLowerInvariant() -replace '[^a-z0-9]', '')
if ($sanitizedActor.Length -ge 2) {
    $actorPrefix = $sanitizedActor.Substring(0, 2)
}
elseif ($sanitizedActor.Length -eq 1) {
    $actorPrefix = "$sanitizedActor" + 'x'
}
else {
    $actorPrefix = 'ci'
}

$suffixLengthLimit = 16
$runAttemptText = $GitHubRunAttempt -replace '[^0-9]', ''
if ([string]::IsNullOrWhiteSpace($runAttemptText)) {
    $runAttemptText = '1'
}

$runIdText = $GitHubRunId -replace '[^0-9]', ''
if ([string]::IsNullOrWhiteSpace($runIdText)) {
    throw "GitHub run id '$GitHubRunId' does not contain any digits."
}

$maxRunIdLength = $suffixLengthLimit - $actorPrefix.Length - $runAttemptText.Length
if ($maxRunIdLength -lt 1) {
    throw "GitHub run attempt '$GitHubRunAttempt' is too long to build a deployment suffix under $suffixLengthLimit characters."
}

$shortRunId = if ($runIdText.Length -gt $maxRunIdLength) {
    $runIdText.Substring($runIdText.Length - $maxRunIdLength)
}
else {
    $runIdText
}

$ciSuffix = "$actorPrefix$shortRunId$runAttemptText"
if ($ciSuffix.Length -gt $suffixLengthLimit) {
    throw "CI suffix '$ciSuffix' is too long. Generated suffixes must stay under $suffixLengthLimit characters so generated Key Vault names stay under Azure's 24-character limit."
}

# Intentionally empty: actor-prefixed suffixes do not have a stable common base,
# so stale cleanup matches all CI resource groups under the configured prefix.
"$BaseSuffixEnvironmentVariableName=" | Out-File -FilePath $env:GITHUB_ENV -Append
"$SuffixEnvironmentVariableName=$ciSuffix" | Out-File -FilePath $env:GITHUB_ENV -Append
Write-Output "Using CI deployment suffix '$ciSuffix'."