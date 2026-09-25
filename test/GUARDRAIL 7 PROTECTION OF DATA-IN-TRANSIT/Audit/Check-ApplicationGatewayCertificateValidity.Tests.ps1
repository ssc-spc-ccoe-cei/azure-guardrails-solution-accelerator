BeforeAll {
    $script:originalEAP = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'

    function global:add-documentFileExtensions { param($DocumentName) return @('approved-ca.txt') }
    function global:New-ConnectedStorageContext { }
    function global:Add-ProfileInformation { param($Result) return $Result }
    function global:Set-SubscriptionNotEvaluatedStatus { param($Result) return $Result }

    Import-Module (Join-Path $PSScriptRoot '..\..\..\src\GUARDRAIL 7 PROTECTION OF DATA-IN-TRANSIT\Audit\Check-ApplicationGatewayCertificateValidity.psm1') -Force
}

AfterAll {
    Remove-Item Function:\add-documentFileExtensions -ErrorAction SilentlyContinue
    Remove-Item Function:\New-ConnectedStorageContext -ErrorAction SilentlyContinue
    Remove-Item Function:\Add-ProfileInformation -ErrorAction SilentlyContinue
    Remove-Item Function:\Set-SubscriptionNotEvaluatedStatus -ErrorAction SilentlyContinue
    $global:ErrorActionPreference = $script:originalEAP
}

Describe 'Test-KeyVaultAccess' {
    It 'Returns success when the secret can be retrieved' {
        Mock Get-AzKeyVaultSecret -ModuleName Check-ApplicationGatewayCertificateValidity { [pscustomobject]@{ Name = 'secret1' } }

        $result = Test-KeyVaultAccess -KeyVaultName 'kv1' -SecretName 'secret1'

        $result.Success | Should -BeTrue
        $result.Error | Should -BeNullOrEmpty
    }
}

Describe 'Get-LeafCertificate and Test-CertificateAuthorityApproved' {
    BeforeAll {
        $rootRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            'CN=Approved Root CA',
            [System.Security.Cryptography.RSA]::Create(2048),
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
        $rootCert = $rootRequest.CreateSelfSigned([datetimeoffset]::UtcNow.AddDays(-1), [datetimeoffset]::UtcNow.AddDays(30))

        $leafRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            'CN=Leaf Cert',
            [System.Security.Cryptography.RSA]::Create(2048),
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
        $serial = [byte[]](1,2,3,4)
        $script:leafCert = $leafRequest.Create($rootCert, [datetimeoffset]::UtcNow.AddDays(-1), [datetimeoffset]::UtcNow.AddDays(30), $serial)
        $script:certCollection = @($script:leafCert, $rootCert)
    }

    It 'Identifies the leaf certificate from a collection' {
        $result = Get-LeafCertificate -CertificateCollection $script:certCollection
        $result.Subject | Should -Be $script:leafCert.Subject
    }

    It 'Accepts a certificate chain when an approved CA is present' {
        $result = Test-CertificateAuthorityApproved -Certificate $script:leafCert -CertificateCollection $script:certCollection -ApprovedCAList @('Approved Root CA')
        $result.IsApproved | Should -BeTrue
        $result.MatchedCA | Should -Be 'Approved Root CA'
    }
}

Describe 'Check-ApplicationGatewayCertificateValidity' {
    BeforeAll {
        $script:msgTable = @{ }
        $script:params = @{
            ControlName      = 'GUARDRAIL 7'
            ItemName         = 'Gateway Certificates'
            itsgcode         = 'SC-8'
            msgTable         = $script:msgTable
            ReportTime       = '2026-09-25'
            StorageAccountName = 'stg'
            ContainerName    = 'docs'
            ResourceGroupName = 'rg1'
            SubscriptionID   = 'sub-1'
            DocumentName     = @('approved-ca')
        }
    }

    It 'Returns a storage access error when the storage context cannot be created' {
        Mock Select-AzSubscription -ModuleName Check-ApplicationGatewayCertificateValidity { }
        Mock Get-AzContext -ModuleName Check-ApplicationGatewayCertificateValidity { [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'Subscription One' } } }
        Mock New-ConnectedStorageContext -ModuleName Check-ApplicationGatewayCertificateValidity { throw 'no access' }

        $result = Check-ApplicationGatewayCertificateValidity @script:params

        $result.ComplianceResults | Should -BeNullOrEmpty
        $result.Errors.Count | Should -Be 1
    }
}
