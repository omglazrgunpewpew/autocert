# Tests/Autocert.Complete.Tests.ps1
<#
    .SYNOPSIS
        Complete system integration test suite for AutoCert.
#>

Describe 'AutoCert Complete System' -Tag 'Resilience', 'ErrorHandling' {
    BeforeAll {
        $ErrorActionPreference = 'Stop'

        # Set testing environment variables
        $env:AUTOCERT_TESTING_MODE = $true
        $env:POSHACME_SKIP_UPGRADE_CHECK = $true

        # Calculate path to main repository (go up two levels from Tests directory)
        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

        # Load Core modules
        . "$repoRoot\Core\Logging.ps1"
        . "$repoRoot\Core\Initialize-PoshAcme.ps1"
        . "$repoRoot\Core\Helpers.ps1"
        . "$repoRoot\Core\ConfigurationManager.ps1"

        # Load Functions from Public directory
        Get-ChildItem "$repoRoot\Public" -Filter '*.ps1' | ForEach-Object { . $_.FullName }

        # Load UI modules
        Get-ChildItem "$repoRoot\UI" -Filter '*.ps1' | ForEach-Object { . $_.FullName }

        # Load Utilities modules
        Get-ChildItem "$repoRoot\Utilities" -Filter '*.ps1' | ForEach-Object { . $_.FullName }
    }

    Context 'Function Module Tests' {
        It 'All function modules should be defined' {
            @( 'Register-Certificate', 'Install-Certificate', 'Revoke-Certificate', 'Remove-Certificate',
                'Get-ExistingCertificates', 'Set-AutomaticRenewal', 'Show-Options', 'Update-AllCertificates' ) | ForEach-Object {
                Get-Command $_ | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'UI Module Tests' {
        It 'All UI functions should be defined' {
            @( 'Show-Menu', 'Show-CertificateManagementMenu', 'Show-CredentialManagementMenu', 'Show-Help',
                'Invoke-SingleCertificateManagement' ) | ForEach-Object {
                Get-Command $_ | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Utility Module Tests' {
        It 'All utility functions should be defined' {
            @( 'Test-SystemHealth', 'Test-SystemConfiguration', 'Invoke-AutomatedRenewal',
                'Initialize-AutoCertModules', 'Invoke-MenuOperation' ) | ForEach-Object {
                Get-Command $_ | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Core Module Tests' {
        It 'All core functions should be defined' {
            @( 'Write-Log', 'Invoke-WithRetry', 'Write-ProgressHelper', 'Get-ValidatedInput',
                'Test-ValidDomain', 'Get-ScriptSettings' ) | ForEach-Object {
                Get-Command $_ | Should -Not -BeNullOrEmpty
            }
        }
    }
}

