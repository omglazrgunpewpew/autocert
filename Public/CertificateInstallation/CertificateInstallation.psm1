# CertificateInstallation.psm1
<#
.SYNOPSIS
    Aggregated certificate installation feature module.
.DESCRIPTION
    Lightweight wrapper module that exposes the refactored certificate installation
    component functions by dot-sourcing the already existing Private implementations.
    This keeps the refactored Install-Certificate command (Public/Install-Certificate.ps1)
    working without duplicating code or changing the current private/public layout.

    The public script Import-Module's this folder expecting CertificateInstallation.psm1.
    We simply re-export the required functions which remain maintained in the Private
    folder per project architectural guidelines (flat public commands, private helpers).
.NOTES
    Creating this file resolves the missing module failure that blocked Install-Certificate.
#>

# Prevent double-loading
if ($script:CertificateInstallationModuleLoaded) { return }
$script:CertificateInstallationModuleLoaded = $true

# Resolve Private directory (two levels up from Public\CertificateInstallation)
$privatePath = Join-Path (Join-Path $PSScriptRoot '..') '..'
$privatePath = Join-Path $privatePath 'Private'

# List of private implementation files needed for installation features
$implementationFiles = @(
    'Select-CertificateForInstallation.ps1',
    'Show-CertificateInformation.ps1',
    'Show-DetailedCertificateInformation.ps1',
    'Show-InstallationOptionsMenu.ps1',
    'Show-PostInstallationMenu.ps1',
    'Install-CertificateToStore.ps1',
    'Install-CertificateToPEM.ps1',
    'Export-CertificateToPFX.ps1',
    'Export-CertificateMultipleFormats.ps1'
)

foreach ($file in $implementationFiles) {
    $full = Join-Path $privatePath $file
    if (Test-Path $full) {
        . $full
    }
    else {
        Write-Warning "CertificateInstallation module: missing implementation file: $full"
    }
}

# Explicitly export only the functions that the public Install-Certificate workflow expects
$exportFunctions = @(
    'Select-CertificateForInstallation',
    'Show-CertificateInformation',
    'Show-DetailedCertificateInformation',
    'Show-InstallationOptionsMenu',
    'Show-PostInstallationMenu',
    'Install-CertificateToStore',
    'Install-CertificateToPEM',
    'Export-CertificateToPFX',
    'Export-CertificateMultipleFormats'
) | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue }

Export-ModuleMember -Function $exportFunctions
