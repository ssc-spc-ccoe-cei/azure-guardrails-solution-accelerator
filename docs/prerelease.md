# Installing or Updating from Prerelease

Updates to the Guardrails Solution Accelerator are made continuously and rolled up into a publish release about once a month. To install updates made before a release, there are a couple options:

- **Deploy the latest interim release:** When critical bugfixes are implemented, an interim release of the solution will be published to GitHub. This interim release will be marked as 'latest', so running a new installation or an update installation without specifying a release number or alternate URL will include the changes from the interim release. This is the recommended approach for installing updates made since the last official release.
- **Deploy from the prerelease/development source:** When an interim release has not been created, but you want to deploy or update to the latest in development/prerelease version of the solution, you can do so by following the documentation below. This is not recommend outside of specific testing scenarios, and it is recommended that if you do deploy with this process, that you update your deployment once the next release is available.

## Installing individual modules from pre-release

1. Clone the solution from GitHub with Git (if you do not have a copy already): `git clone https://github.com/Azure/GuardrailsSolutionAccelerator.git`
1. Checkout the `main` branch: `git checkout main`
1. Ensure you have the latest copy of the `main` branch locally: `git pull https://github.com/Azure/GuardrailsSolutionAccelerator.git main`
1. In the cloned repo, navigate to the `./src` directory and find the module or modules you want to upload under the named Guardrail directories
1. For each module you want to update, create a Zip file containing both the `.psd1` and `.psm1` files for the module. Make sure the Zip file name matches the module name.
1. In the Azure Portal, navigate to the Azure Automation account. Under *Shared Resources*, click *Modules*.
1. Change the filter at the top of the screen to *Module type: custom*
1. Select the module to update and click *Delete* to remove the existing version of the module
1. Go back to the modules list and click *+ Add Module*
1. Choose *Browse for file*, select the zip, and enter the module name, and select *Runtime Version 5.1*
1. Repeat above steps for each module to update

## Installing the complete solution or all modules from a pre-release

Installing the complete solution from the source code requires that you provide a public accessible location for the Automation Account to source the PowerShell modules from. The script below uses an Azure Storage Account which is publicly-accessible from a service firewall configuration and which allows anonymous access to download the modules. This configuration may not be permitted by organization policy or Azure Policy by default, but considered acceptable here because the published Zips are publicly available in the source repo. Alternatively, a custom web server could be used.

The script below creates a Storage Account in the specified Resource Group and Azure Region, then uploads zipped modules from the local repo. Lastly, the script outputs the URL to pass to the -alternatePSModulesURL parameter when running the Deploy-GuardrailsSolutionAcclerator command to deploy or update a deployment. 

```azurepowershell
# create a storage account and container for staging the zipped modules 
$resourceGroupName = 'REPLACE' # name of the resource group where the storage account will be created
$storageAccountName = 'REPLACE' # globally unique name of the temporary storage account used to stage the zipped modules. must be publicly accessible
$location = 'REPLACE' # Azure location where the storage account will be created, ex 'centralcanada'

If (-NOT(Test-Path -Path ./src -PathType Container) -or -NOT(Test-Path -Path ./psmodules -PathType Container)) {
    Write-Error "Unable to find ./src and/or ./psmodules directories at '$($pwd)'. Please run this script from the root of the repository." -ErrorAction Stop
}

If ($storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction SilentlyContinue) {
    Write-Host "Storage account '$storageAccountName' already exists, skipping creation..."
}
Else {
    Write-Host "Creating storage account '$storageAccountName'..."
    $storageAccount = New-AzStorageAccount -ResourceGroupName $resourceGroupName -Location $location -Name $storageAccountName -SkuName Standard_LRS -EnableHTTPSTrafficOnly $true -AllowBlobPublicAccess $true
}

$container = New-AzStorageContainer -name psmodules -Permission Container -Context $storageAccount.Context -ErrorAction SilentlyContinue

$moduleManifestFilesObjs = Get-ChildItem -Path .\src -Recurse -Include *.psm1
Write-Host "'$($moduleManifestFilesObjs.count)' module manifest files "

# zip all modules and place in ./psmodules directory in repo
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

# upload zipped modules to storage account
$zippedModules = Get-ChildItem -Path ./psmodules/* -Include *.zip -File
ForEach ($moduleZip in $zippedModules) {

  Set-AzStorageBlobContent -Context $storageAccount.Context -Container psmodules -File $moduleZip.FullName -Blob $moduleZip.Name -Force -ErrorAction Stop
}

# return container URI - use with -alternatePSModulesURL parameter
$URL = $storageAccount.PrimaryEndpoints.Blob + 'psmodules'
Write-Host "Use -alternatePSModulesURL '$URL' with 'Deploy-GuardrailsSolutionAccelerator' to deploy using the staged modules"

```