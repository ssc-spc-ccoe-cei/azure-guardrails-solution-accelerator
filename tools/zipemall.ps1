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
    Write-Host "Processing module: $($moduleManifest.BaseName)"
    
    # Check if specific modules were provided and if the current module is in the list
    if ($specificModules -and $specificModules.Count -gt 0) {
        if ($specificModules -notcontains $moduleManifest.BaseName) {
            Write-Host "Skipping module '$($moduleManifest.BaseName)' as it's not in the specified list."
            continue
        }
    }
    
    $manifestFile = Join-Path $moduleManifest.Directory "$($moduleManifest.BaseName).psd1"
    $codeFile = Join-Path $moduleManifest.Directory "$($moduleManifest.BaseName).psm1"
    
    Write-Host "Manifest file: $manifestFile"
    Write-Host "Code file: $codeFile"
    
    If ((Test-Path $manifestFile) -or (Test-Path $codeFile)) {
        Write-Host "Module '$($moduleManifest.BaseName)' found, zipping module files..."
        $destPath = "./psmodules/$($moduleManifest.BaseName).zip"
        
        # Create a temporary directory
        $tempDir = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())) -Force
        Write-Host "Temporary directory created: $($tempDir.FullName)"
        
        # Copy manifest file (.psd1) if it exists
        if (Test-Path $manifestFile) {
            Copy-Item -Path $manifestFile -Destination $tempDir -Force
            Write-Host "Copied manifest file: $manifestFile to $($tempDir.FullName)"
        }
        
        # Copy code file (.psm1) if it exists
        if (Test-Path $codeFile) {
            Copy-Item -Path $codeFile -Destination $tempDir -Force
            Write-Host "Copied code file: $codeFile to $($tempDir.FullName)"
        }
        
        # Copy any additional files in the same directory that start with the module base name (e.g., GR-ComplianceChecks-Msgs.psd1)
        $additionalFiles = Get-ChildItem -Path $moduleManifest.Directory -File | Where-Object { $_.Name -like "$($moduleManifest.BaseName)-*" -or ($_.BaseName -eq $moduleManifest.BaseName -and $_.Extension -notin @('.psd1', '.psm1')) }
        foreach ($file in $additionalFiles) {
            Copy-Item -Path $file.FullName -Destination $tempDir -Force
            Write-Host "Copied additional file: $($file.FullName) to $($tempDir.FullName)"
        }
        
        # Copy any subdirectories that match culture/locale patterns (e.g., fr-CA, en-US for localization)
        $subDirectories = Get-ChildItem -Path $moduleManifest.Directory -Directory | Where-Object { $_.Name -match '^[a-z]{2}-[A-Z]{2}$' }
        foreach ($subDir in $subDirectories) {
            Copy-Item -Path $subDir.FullName -Destination $tempDir -Recurse -Force
            Write-Host "Copied subdirectory: $($subDir.FullName) to $($tempDir.FullName)"
        }
        
        # List files in temporary directory
        Write-Host "Files in temporary directory:"
        Get-ChildItem -Path $tempDir | ForEach-Object { Write-Host $_.FullName }
        
        # Compress files from the temporary directory
        Compress-Archive -Path "$tempDir\*" -DestinationPath $destPath -Force
        Write-Host "Compressed files to: $destPath"
        
        # Remove the temporary directory
        Remove-Item -Path $tempDir -Recurse -Force
        Write-Host "Removed temporary directory: $($tempDir.FullName)"
        
        Write-Host "Module '$($moduleManifest.BaseName)' zipped successfully."
    }
    Else {
        Write-Host "Neither the manifest '$($moduleManifest.FullName.toLower())' or script file '$($moduleCodeFile.FullName.ToLower())' for module '$($moduleManifest.BaseName)' was changed, skipping zipping..."
    }
}
