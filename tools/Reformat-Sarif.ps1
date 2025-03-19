#requires -Version 7
<#
.SYNOPSIS
    This script reformats a SARIF file to include message text for each result.
    It is needed to work around a GitHub issue https://github.com/github/codeql/issues/11512
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [String]
    $sourceFile,
    [Parameter(Mandatory = $true)]
    [String]
    $targetFile
)

if (-not (Test-Path $sourceFile)) {
    Write-Error "Source file does not exist: $sourceFile"
    exit 1
}

$sourceObj = Get-Content $sourceFile | ConvertFrom-Json 

function Get-MessageTextById($run, $ruleId, $messageId) {
    $rules = $run.tool.driver.rules   
    foreach ($rule in $rules) {
        if ($rule.id -eq $ruleId) {
            return $rule.messageStrings.$messageId ? $rule.messageStrings.$messageId.text : $rule.fullDescription.text
        }
    }
    return "Rule $ruleId not found"
}

foreach ($run in $sourceObj.runs) {
    $run.results | ForEach-Object {
        if ($_.message.id) {
            if (-not ($_.message | Get-Member "text")) {
                $_.message | Add-Member -MemberType NoteProperty -Name "text" -Value (Get-MessageTextById -run $run -ruleId ($_.ruleId) -messageId ($_.message.id))
            }
            else {
                $_.message.text = Get-MessageTextById -run $run -ruleId ($_.ruleId) -messageId ($_.message.id)
            }
        }
    }
}

$sourceObj | ConvertTo-Json -Depth 20 | Out-File -FilePath $targetFile -Force