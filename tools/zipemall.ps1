param(
    $pipelineModulesStagingRGName,
    $pipelineModulesStagingStorageAccountName,
    $configFilePath,
    [string[]]$specificModules # New optional parameter
)

# zip all modules or specific modules if provided
$moduleManifestFilesObjs = Get-ChildItem -Path .\src -Recurse -Include *.psm1

Write-Host "'$($moduleManifestFilesObjs.count)' module manifest files found"

ForEach ($moduleManifest in $moduleManifestFilesObjs) {
    $moduleCodeFile = Get-Item -Path $moduleManifest.FullName.replace('psd1','psm1')
    
    # Check if specific modules were provided and if the current module is in the list
    if ($specificModules -and $specificModules.Count -gt 0) {
        if ($specificModules -notcontains $moduleManifest.BaseName) {
            Write-Host "Skipping module '$($moduleManifest.BaseName)' as it's not in the specified list."
            continue
        }
    }
    
    If ($moduleManifestFilesObjs.FullName -icontains $moduleManifest.FullName -or $moduleManifestFilesObjs.FullName -icontains $moduleCodeFile.FullName) {
        Write-Host "Module '$($moduleManifest.BaseName)' found, zipping module files..."
        $destPath = "./psmodules/$($moduleManifest.BaseName).zip"
        Compress-Archive -Path "$($moduleManifest.Directory)/*" -DestinationPath $destPath -Force
    }
    Else {
        Write-Host "Neither the manifest '$($moduleManifest.FullName.toLower())' or script file '$($moduleCodeFile.FullName.ToLower())' for module '$($moduleManifest.BaseName)' was changed, skipping zipping..."
    }
}

# ... (rest of the script remains unchanged)
