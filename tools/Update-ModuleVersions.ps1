param (
    # can be a tag, branch, or commit - this is what you will merge into
    [Parameter(Mandatory = $false)]
    [string]
    $targetGitRef = 'upstream/main',

    # whatif
    [Parameter(Mandatory = $false)]
    [switch]
    $WhatIf
)

$headCommit = git rev-parse --short HEAD
$changedFiles = (git diff-tree --name-status -r $targetGitRef $headCommit | Select-String -Pattern "^[^A]") -replace '^\w\s+?',''

$moduleVersionRegex = [regex]"(?:ModuleVersion\s?=\s?')([\d\.]*)'" 
$moduleChangedFileList = $changedFiles | where-object { $_ -match '\.psm1$'}

$repoRoot = "$PSScriptRoot/.."
ForEach ($moduleChangedFile in $moduleChangedFileList) {
    $modulePath = Join-Path -path $repoRoot -childPath ($moduleChangedFile -replace '\.psm1$','.psd1')
    try {
        $moduleManifestPath = Get-Item -Path $modulePath -ErrorAction Stop
    }
    catch {
        Write-Error "Error locating .psd1 file for module '$moduleChangedFile'. This file should reside in the same directory as the psm1."
    }
    
    $moduleManifest = Get-Item $moduleManifestPath
    $content = Get-Content $moduleManifest
    If ($moduleVersionMatches = $moduleVersionRegex.matches($content)) {
        If ($moduleVersionMatches.count -eq 1) {
            $moduleVersionLine = $moduleVersionMatches[0].Groups[0].Value
            $currentModuleVersion = $moduleVersionMatches[0].Groups[1].Value
            If ($version = $currentModuleVersion -as [version]) {
                $major = $version.Major
                $minor = $version.Minor
                $build = $version.Build + 1 # add 1 to current version build number
                $newVersion = [version]::new($major,$minor,$build)
            }
            Else {
                Write-Error "Version string '$currentModuleVersion' cannot be converted to type [Version]. File: '$moduleManifest'"
            }

            # get target module version
            $moduleManifestRelativePath = $moduleChangedFile -replace '\.psm1$','.psd1'
            $targetBranchModuleContent = git show $targetGitRef`:$moduleManifestRelativePath
            $targetBranchModuleVersionMatches = $moduleVersionRegex.matches($targetBranchModuleContent)
            If ($targetBranchModuleVersionMatches.count -eq 1) {
                $targetBranchModuleVersion = $targetBranchModuleVersionMatches[0].Groups[1].Value -as [version]
            }
            Else {
                Write-Error "Error getting target branch module version. File: '$moduleManifestRelativePath'"
            }
            If ($targetBranchModuleVersion -eq $newVersion) {
                Write-Error "There is a conflict with the target branch module version. Target branch module version: '$targetBranchModuleVersion'. New module version: '$newVersion'. File: '$moduleManifestRelativePath'"
                break
            }
            ElseIf ($targetBranchModuleVersion -gt $newVersion) {
                Write-Error "The target branch module version is greater than the new module version. Target branch module version: '$targetBranchModuleVersion'. New module version: '$newVersion'. File: '$moduleManifestRelativePath'. Make sure to merge upstream/main before running this script!"
            }

            $newVersionLine = $moduleVersionLine -replace $currentModuleVersion,$newVersion
            $moduleManifest | Set-Content -Value ($content -replace $moduleVersionLine,$newVersionLine) -WhatIf:$WhatIf.IsPresent
        }
        Else {
            Write-Error "More than one matches for regex '$moduleVersionRegex' found in file '$moduleManifest'"
        }
    }
}