param(
    $pipelineModulesStagingRGName,
    $pipelineModulesStagingStorageAccountName,
    $configFilePath
    )

# zip all modules
    $moduleManifestFilesObjs = Get-ChildItem -Path .\src -Recurse -Include *.psm1
    Write-Host "'$($moduleManifestFiles.count)' module manifest files "
    ForEach ($moduleManifest in $moduleManifestFilesObjs) {
        $moduleCodeFile = Get-Item -Path $moduleManifest.FullName.replace('psd1','psm1')
        If ($moduleManifestFilesObjs.FullName -icontains $moduleManifest.FullName -or $moduleManifestFilesObjs.FullName -icontains $moduleCodeFile.FullName) {
            Write-Host "Module '$($moduleManifest.BaseName)' found, zipping module files..."
            $destPath = "./psmodules/$($moduleManifest.BaseName).zip"
            Compress-Archive -Path "$($moduleManifest.Directory)/*" -DestinationPath $destPath -Force
        }
        Else {
            Write-Host "Neither the manifest '$($moduleManifest.FullName.toLower())' or script file '$($moduleCodeFile.FullName.ToLower())' for module '$($moduleManifest.BaseName)' was changed, skipping zipping..."
        }
    }
# 