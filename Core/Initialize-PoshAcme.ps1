<#
    .SYNOPSIS
        Ensures Posh-ACME is installed, up to date, and imported.
        Also defines a function to ensure the ACME server is set.
#>

# Check if Posh-ACME module is installed; if not, install it
if (-not (Get-Module -ListAvailable -Name Posh-ACME)) {
    Write-Host "Posh-ACME module not found. Installing..."
    try {
        Install-Module -Name Posh-ACME -Scope CurrentUser -Force -ErrorAction Stop
        Write-Host "Posh-ACME module installed."
    } catch {
        Write-Host "Failed to install Posh-ACME module: $($_)" -ForegroundColor Red
        Exit
    }
} else {
    # Check for updates
    $currentVersion = (Get-Module -Name Posh-ACME -ListAvailable | Select-Object -Last 1).Version
    try {
        $latestVersion = (Find-Module -Name Posh-ACME).Version
        if ($currentVersion -lt $latestVersion) {
            Write-Host "`nA newer version of Posh-ACME is available. Updating..."
            Update-Module -Name Posh-ACME -Force -ErrorAction Stop
            Write-Host "Posh-ACME module updated to version $latestVersion."
        }
    } catch {
        Write-Host "Could not check for updates to Posh-ACME module: $($_)" -ForegroundColor Yellow
    }
}

Import-Module Posh-ACME -Force

function Initialize-ACMEServer {
    if (-not (Get-PAServer)) {
        Set-PAServer LE_PROD
        Write-Verbose "ACME server set to Let's Encrypt Production."
        Write-Log "ACME server set to Let's Encrypt Production."
    }
}
