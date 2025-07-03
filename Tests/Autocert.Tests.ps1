Describe 'Autocert Functions' {
    BeforeAll {
        $ErrorActionPreference = 'Stop'
        . "$PSScriptRoot/../Core/Initialize-PoshAcme.ps1"
        . "$PSScriptRoot/../Core/Logging.ps1"
        . "$PSScriptRoot/../Core/Helpers.ps1"
        Get-ChildItem "$PSScriptRoot/../Functions" -Filter '*.ps1' | ForEach-Object { . $_.FullName }
    }

    It 'All functions should be defined' {
        @( 'Register-Certificate', 'Install-Certificate', 'Revoke-Certificate', 'Remove-Certificate',
           'Get-ExistingCertificates', 'Set-AutomaticRenewal', 'Show-AdvancedOptions', 'Update-Certificates' ) | ForEach-Object {
            Get-Command $_ | Should -Not -BeNullOrEmpty
        }
    }
}

