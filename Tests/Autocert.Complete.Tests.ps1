# Tests/Autocert.Complete.Tests.ps1
<#
    .SYNOPSIS
        Complete system integration test suite for AutoCert.
#>

Describe 'AutoCert Complete System' {
    BeforeAll {
        $ErrorActionPreference = 'Stop'
        
        # Load Core modules
        . "$PSScriptRoot/../Core/Logging.ps1"
        . "$PSScriptRoot/../Core/Initialize-PoshAcme.ps1"
        . "$PSScriptRoot/../Core/Helpers.ps1"
        . "$PSScriptRoot/../Core/ConfigurationManager.ps1"
        
        # Load Functions
        Get-ChildItem "$PSScriptRoot/../Functions" -Filter '*.ps1' | ForEach-Object { . $_.FullName }
        
        # Load UI modules
        Get-ChildItem "$PSScriptRoot/../UI" -Filter '*.ps1' | ForEach-Object { . $_.FullName }
        
        # Load Utilities modules
        Get-ChildItem "$PSScriptRoot/../Utilities" -Filter '*.ps1' | ForEach-Object { . $_.FullName }
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
