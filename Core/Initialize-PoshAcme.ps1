<#
    .SYNOPSIS
        Ensures Posh-ACME is installed, up to date, and imported.
        Also defines a function to ensure the ACME server is set.
#>

# Check if we're in testing mode (use repo's module) or should prevent updates
$isTestingMode = $env:AUTOCERT_TESTING_MODE -or $env:POSHACME_SKIP_UPGRADE_CHECK
$repoModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Modules\Posh-ACME'

if ($isTestingMode -and (Test-Path $repoModulePath)) {
    # In testing mode, use the repo's module directly
    Write-Verbose "Testing mode: Using Posh-ACME module from repository"
    Write-Log "Testing mode: Using Posh-ACME module from repository" -Level 'Info'
    
    try {
        Import-Module $repoModulePath -Force -ErrorAction Stop
        $version = (Get-Module Posh-ACME).Version
        Write-Verbose "Loaded Posh-ACME version $version from repository"
        Write-Log "Loaded Posh-ACME version $version from repository" -Level 'Info'
    } catch {
        Write-Error "Failed to load Posh-ACME from repository: $($_)"
        Write-Log "Failed to load Posh-ACME from repository: $($_)" -Level 'Error'
        Exit
    }
} else {
    # Normal mode: Check installation and updates
    
    # Check if Posh-ACME module is installed; if not, install it
    if (-not (Get-Module -ListAvailable -Name Posh-ACME)) {
        Write-Information -MessageData "Posh-ACME module not found. Installing..." -InformationAction Continue
        try {
            Install-Module -Name Posh-ACME -Scope CurrentUser -Force -ErrorAction Stop
            Write-Information -MessageData "Posh-ACME module installed." -InformationAction Continue
        } catch {
            Write-Error "Failed to install Posh-ACME module: $($_)"
            Exit
        }
    } else {
        # Check for updates only if not explicitly disabled
        if (-not $env:POSHACME_SKIP_UPGRADE_CHECK) {
            $currentVersion = (Get-Module -Name Posh-ACME -ListAvailable | Select-Object -Last 1).Version
            try {
                $latestVersion = (Find-Module -Name Posh-ACME).Version
                if ($currentVersion -lt $latestVersion) {
                    Write-Information -MessageData "`nA newer version of Posh-ACME is available. Updating..." -InformationAction Continue
                    Update-Module -Name Posh-ACME -Force -ErrorAction Stop
                    Write-Information -MessageData "Posh-ACME module updated to version $latestVersion." -InformationAction Continue

                    # Update repository copy after successful update
                    $modulePath = (Get-Module -Name Posh-ACME -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).ModuleBase
                    try {
                        if (-not (Test-Path $repoModulePath)) {
                            New-Item -ItemType Directory -Path $repoModulePath -Force | Out-Null
                        }
                        Copy-Item -Path $modulePath\* -Destination $repoModulePath -Recurse -Force
                        Write-Log "Posh-ACME module updated in repository to version $latestVersion"
                    } catch {
                        Write-Warning -Message "Failed to update repository copy: $($_)"
                        Write-Log "Failed to update repository copy: $($_)" -Level 'Warning'
                    }
                }
            } catch {
                Write-Warning -Message "Could not check for updates to Posh-ACME module: $($_)"
            }
        } else {
            Write-Verbose "Posh-ACME update check skipped (POSHACME_SKIP_UPGRADE_CHECK is set)"
        }
    }
    
    # Import the system module
    Import-Module Posh-ACME -Force
}
function Initialize-ACMEServer {
    if (-not (Get-PAServer)) {
        Set-PAServer LE_PROD
        Write-Verbose "ACME server set to Let's Encrypt Production."
        Write-Log "ACME server set to Let's Encrypt Production."
    }
}

