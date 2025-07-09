# Tests/Autocert.Tests.ps1
<#
    .SYNOPSIS
        Basic test suite for AutoCert core functions.
#>

Describe 'Autocert Functions' {
    BeforeAll {
        $ErrorActionPreference = 'Stop'
        . "$PSScriptRoot/../Core/Logging.ps1"
        . "$PSScriptRoot/../Core/Initialize-PoshAcme.ps1"
        . "$PSScriptRoot/../Core/Helpers.ps1"
        Get-ChildItem "$PSScriptRoot/../Functions" -Filter '*.ps1' | ForEach-Object { . $_.FullName }
    }

    It 'All functions should be defined' {
        @( 'Register-Certificate', 'Install-Certificate', 'Revoke-Certificate', 'Remove-Certificate',
           'Get-ExistingCertificates', 'Set-AutomaticRenewal', 'Show-Options', 'Update-AllCertificates' ) | ForEach-Object {
            Get-Command $_ | Should -Not -BeNullOrEmpty
        }
    }
}