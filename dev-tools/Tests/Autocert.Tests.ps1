# Tests/Autocert.Tests.ps1
<#
    .SYNOPSIS
        Basic test suite for AutoCert core functions.
#>

Describe 'Autocert Functions' -Tag 'Unit' {
    BeforeAll {
        $ErrorActionPreference = 'Stop'

        # Set testing environment variables
        $env:AUTOCERT_TESTING_MODE = $true
        $env:POSHACME_SKIP_UPGRADE_CHECK = $true

        # Calculate path to main repository (go up two levels from Tests directory)
        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

        . "$repoRoot\Core\Logging.ps1"
        . "$repoRoot\Core\Initialize-PoshAcme.ps1"
        . "$repoRoot\Core\Helpers.ps1"
        Get-ChildItem "$repoRoot\Public" -Filter '*.ps1' | ForEach-Object { . $_.FullName }
    }

    It 'All functions should be defined' {
        @( 'Register-Certificate', 'Install-Certificate', 'Revoke-Certificate', 'Remove-Certificate',
            'Get-ExistingCertificates', 'Set-AutomaticRenewal', 'Show-Options', 'Update-AllCertificates' ) | ForEach-Object {
            Get-Command $_ | Should -Not -BeNullOrEmpty
        }
    }
}
