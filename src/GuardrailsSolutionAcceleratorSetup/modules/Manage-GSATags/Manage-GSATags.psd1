@{
    RootModule = 'Manage-GSATags.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'ec2bcdd3-eb37-4631-8a0c-bfd73860394c'
    Author = 'Cloud Security Compliance'
    CompanyName = 'Shared Services Canada'
    Description = 'Resolves trusted mandatory tags and manages deployment tag-policy enforcement.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('ConvertTo-GSATagTable', 'Get-GSADeploymentTags', 'Set-GSATagPolicies', 'Invoke-GSATagPolicyOperation')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}