@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'SharedFunctions.psm1'

    # Version number of this module.
    ModuleVersion = '1.0.0'

    # ID used to uniquely identify this module
    GUID = 'a1234567-89ab-cdef-1234-56789abcdef0'

    # Author of this module
    Author = 'Gurpreet Singh'

    # Company or vendor of this module
    CompanyName = 'Shared Services Canada'

    # Description of the functionality provided by this module
    Description = 'A module containing shared functions for Azure resource profile management.'

    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Minimum version of the .NET Framework required by this module
    DotNetFrameworkVersion = '4.5.2'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @()

    # Assemblies that must be loaded prior to importing this module
    RequiredAssemblies = @()

    # Functions to export from this module
    FunctionsToExport = @('Get-ResourceProfile')

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @()

    # List of all modules packaged with this module
    NestedModules = @()

    # DSC resources to export from this module
    DscResourcesToExport = @()

    # List of all files packaged with this module
    FileList = @('SharedFunctions.psm1')

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('Azure', 'ResourceProfile', 'SharedFunctions')

            # A URL to the license for this module.
            LicenseUri = ''

            # A URL to the main website for this project.
            ProjectUri = ''

            # A URL to an icon representing this module.
            IconUri = ''
        }
    }
}
