<#
    .SYNOPSIS
        Ensures Posh-ACME is installed, up to date, and imported.
        Also defines a function to ensure the ACME server is set.

    .DESCRIPTION
        This script handles Posh-ACME module management with improved logic:
        - Efficient version checking to avoid unnecessary network calls
        - Better error handling and logging
        - Support for testing mode and update skip flags
        - Automatic repository synchronization
#>

# Initialize script variables
$script:PoshAcmeInitialized = $false
$script:PoshAcmeVersion = $null

# Helper function for safe logging
function Write-SafeLog
{
    param($Message, $Level = 'Info')
    if (Get-Command Write-Log -ErrorAction SilentlyContinue)
    {
        Write-Log $Message -Level $Level
    } else
    {
        # Fallback to Write-Verbose if Write-Log not available
        switch ($Level)
        {
            'Error' { Write-Warning "ERROR: $Message" }
            'Warning' { Write-Warning $Message }
            default { Write-Verbose $Message }
        }
    }
}

# Check if we're in testing mode (use repo's module) or should prevent updates
$isTestingMode = $env:AUTOCERT_TESTING_MODE -or $env:POSHACME_SKIP_UPGRADE_CHECK
$repoModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Modules\Posh-ACME'

function Test-PoshAcmeModule
{
    <#
    .SYNOPSIS
        Tests if Posh-ACME module is available and gets version information
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $result = @{
        IsInstalled = $false
        Version = $null
        ModulePath = $null
        Error = $null
    }

    try
    {
        $modules = Get-Module -ListAvailable -Name Posh-ACME -ErrorAction SilentlyContinue
        if ($modules)
        {
            $latestModule = $modules | Sort-Object Version -Descending | Select-Object -First 1
            $result.IsInstalled = $true
            $result.Version = $latestModule.Version
            $result.ModulePath = $latestModule.ModuleBase
            Write-Verbose "Found Posh-ACME version $($result.Version) at $($result.ModulePath)"
        } else
        {
            Write-Verbose "Posh-ACME module not found"
        }
    } catch
    {
        $result.Error = $_.Exception.Message
        Write-Verbose "Error checking Posh-ACME module: $($result.Error)"
    }

    return $result
}

function Get-LatestPoshAcmeVersion
{
    <#
    .SYNOPSIS
        Gets the latest available version from PowerShell Gallery with caching
    #>
    [CmdletBinding()]
    [OutputType([version])]
    param()

    # Cache the result for the session to avoid repeated network calls
    if ($script:LatestPoshAcmeVersion -and $script:VersionCheckTime -and
        ((Get-Date) - $script:VersionCheckTime).TotalMinutes -lt 15)
    {
        Write-Verbose "Using cached latest version: $script:LatestPoshAcmeVersion"
        return $script:LatestPoshAcmeVersion
    }

    try
    {
        Write-Verbose "Checking PowerShell Gallery for latest Posh-ACME version..."
        $latestModule = Find-Module -Name Posh-ACME -ErrorAction Stop
        $script:LatestPoshAcmeVersion = $latestModule.Version
        $script:VersionCheckTime = Get-Date
        Write-Verbose "Latest Posh-ACME version available: $script:LatestPoshAcmeVersion"
        return $script:LatestPoshAcmeVersion
    } catch
    {
        Write-Warning "Could not check for latest Posh-ACME version: $($_.Exception.Message)"
        Write-SafeLog "Failed to check PowerShell Gallery for Posh-ACME updates: $($_.Exception.Message)" -Level 'Warning'
        return $null
    }
}
function Install-PoshAcmeModule
{
    <#
    .SYNOPSIS
        Installs Posh-ACME module with proper error handling
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try
    {
        Write-Information -MessageData "Posh-ACME module not found. Installing..." -InformationAction Continue
        Write-SafeLog "Installing Posh-ACME module from PowerShell Gallery" -Level 'Info'

        Install-Module -Name Posh-ACME -Scope CurrentUser -Force -ErrorAction Stop

        # Verify installation
        $moduleCheck = Test-PoshAcmeModule
        if ($moduleCheck.IsInstalled)
        {
            Write-Information -MessageData "Posh-ACME module installed successfully (version $($moduleCheck.Version))" -InformationAction Continue
            Write-SafeLog "Posh-ACME module installed successfully (version $($moduleCheck.Version))" -Level 'Info'
            return $true
        } else
        {
            throw "Module installation verification failed"
        }
    } catch
    {
        $errorMsg = "Failed to install Posh-ACME module: $($_.Exception.Message)"
        Write-Error -Message $errorMsg
        Write-SafeLog $errorMsg -Level 'Error'
        return $false
    }
}

function Update-PoshAcmeModule
{
    <#
    .SYNOPSIS
        Updates Posh-ACME module and synchronizes repository copy
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [version]$CurrentVersion,

        [Parameter(Mandatory)]
        [version]$LatestVersion
    )

    try
    {
        Write-Information -MessageData "`nUpdating Posh-ACME from version $CurrentVersion to $LatestVersion..." -InformationAction Continue
        Write-SafeLog "Updating Posh-ACME module: $CurrentVersion -> $LatestVersion" -Level 'Info'

        Update-Module -Name Posh-ACME -Force -ErrorAction Stop

        # Verify update
        $moduleCheck = Test-PoshAcmeModule
        if ($moduleCheck.IsInstalled -and $moduleCheck.Version -ge $LatestVersion)
        {
            Write-Information -MessageData "Posh-ACME module updated successfully to version $($moduleCheck.Version)" -InformationAction Continue
            Write-SafeLog "Posh-ACME module updated successfully to version $($moduleCheck.Version)" -Level 'Info'

            # Update repository copy
            Sync-PoshAcmeRepository -ModulePath $moduleCheck.ModulePath
            return $true
        } else
        {
            throw "Module update verification failed. Expected version $LatestVersion, found $($moduleCheck.Version)"
        }
    } catch
    {
        $errorMsg = "Failed to update Posh-ACME module: $($_.Exception.Message)"
        Write-Warning -Message $errorMsg
        Write-SafeLog $errorMsg -Level 'Error'
        return $false
    }
}

function Sync-PoshAcmeRepository
{
    <#
    .SYNOPSIS
        Synchronizes the repository copy of Posh-ACME with the installed version
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModulePath
    )

    try
    {
        if (-not (Test-Path $repoModulePath))
        {
            New-Item -ItemType Directory -Path $repoModulePath -Force | Out-Null
            Write-Verbose "Created repository module directory: $repoModulePath"
        }

        # Copy with error handling
        Copy-Item -Path "$ModulePath\*" -Destination $repoModulePath -Recurse -Force -ErrorAction Stop
        Write-SafeLog "Posh-ACME repository copy synchronized successfully" -Level 'Info'
        Write-Verbose "Repository copy updated at: $repoModulePath"
    } catch
    {
        $errorMsg = "Failed to update repository copy: $($_.Exception.Message)"
        Write-Warning -Message $errorMsg
        Write-SafeLog $errorMsg -Level 'Warning'
    }
}

# Main initialization logic
if ($isTestingMode -and (Test-Path $repoModulePath))
{
    # Testing mode: Use the repo's module directly
    Write-Verbose "Testing mode: Using Posh-ACME module from repository"
    Write-SafeLog "Testing mode: Using Posh-ACME module from repository" -Level 'Info'

    try
    {
        Import-Module $repoModulePath -Force -ErrorAction Stop
        $version = (Get-Module Posh-ACME).Version
        $script:PoshAcmeVersion = $version
        $script:PoshAcmeInitialized = $true
        Write-Verbose "Loaded Posh-ACME version $version from repository"
        Write-SafeLog "Loaded Posh-ACME version $version from repository" -Level 'Info'
    } catch
    {
        $errorMsg = "Failed to load Posh-ACME from repository: $($_.Exception.Message)"
        Write-Error -Message $errorMsg
        Write-SafeLog $errorMsg -Level 'Error'
        exit 1
    }
} else
{
    # Normal mode: Check installation and updates
    Write-Verbose "Normal mode: Managing Posh-ACME installation and updates"

    $moduleStatus = Test-PoshAcmeModule

    if (-not $moduleStatus.IsInstalled)
    {
        # Install module if not found
        if (-not (Install-PoshAcmeModule))
        {
            exit 1
        }
        $moduleStatus = Test-PoshAcmeModule
    }

    # Check for updates only if not explicitly disabled
    if (-not $env:POSHACME_SKIP_UPGRADE_CHECK)
    {
        Write-Verbose "Checking for Posh-ACME updates..."
        $currentVersion = $moduleStatus.Version
        $latestVersion = Get-LatestPoshAcmeVersion

        if ($latestVersion -and $currentVersion -lt $latestVersion)
        {
            Write-Verbose "Update available: $currentVersion -> $latestVersion"
            Update-PoshAcmeModule -CurrentVersion $currentVersion -LatestVersion $latestVersion
        } elseif ($latestVersion)
        {
            Write-Verbose "Posh-ACME is up to date (version $currentVersion)"
            Write-SafeLog "Posh-ACME is up to date (version $currentVersion)" -Level 'Info'
        }
    } else
    {
        Write-Verbose "Posh-ACME update check skipped (POSHACME_SKIP_UPGRADE_CHECK is set)"
        Write-SafeLog "Posh-ACME update check skipped (environment variable set)" -Level 'Info'
    }

    # Import the module
    try
    {
        Import-Module Posh-ACME -Force -ErrorAction Stop
        $importedVersion = (Get-Module Posh-ACME).Version
        $script:PoshAcmeVersion = $importedVersion
        $script:PoshAcmeInitialized = $true
        Write-Verbose "Posh-ACME module imported successfully (version $importedVersion)"
        Write-SafeLog "Posh-ACME module imported successfully (version $importedVersion)" -Level 'Info'
    } catch
    {
        $errorMsg = "Failed to import Posh-ACME module: $($_.Exception.Message)"
        Write-Error -Message $errorMsg
        Write-SafeLog $errorMsg -Level 'Error'
        exit 1
    }
}
function Initialize-ACMEServer
{
    <#
    .SYNOPSIS
        Initializes the ACME server configuration for Let's Encrypt

    .DESCRIPTION
        Sets the ACME server to Let's Encrypt Production if not already configured.
        This function should be called after Posh-ACME module is loaded.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:PoshAcmeInitialized)
    {
        Write-Warning "Posh-ACME module not initialized. Call this function after module loading."
        return
    }

    try
    {
        $currentServer = Get-PAServer -ErrorAction SilentlyContinue
        if (-not $currentServer)
        {
            Set-PAServer LE_PROD
            Write-Verbose "ACME server set to Let's Encrypt Production"
            Write-SafeLog "ACME server set to Let's Encrypt Production" -Level 'Info'
        } else
        {
            Write-Verbose "ACME server already configured: $($currentServer.location)"
            Write-SafeLog "ACME server already configured: $($currentServer.location)" -Level 'Info'
        }
    } catch
    {
        Write-Warning "Failed to initialize ACME server: $($_.Exception.Message)"
        Write-SafeLog "Failed to initialize ACME server: $($_.Exception.Message)" -Level 'Warning'
    }
}

function Get-PoshAcmeStatus
{
    <#
    .SYNOPSIS
        Returns the current status of Posh-ACME initialization
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        IsInitialized = $script:PoshAcmeInitialized
        Version = $script:PoshAcmeVersion
        TestingMode = $isTestingMode
        UpdateCheckEnabled = (-not $env:POSHACME_SKIP_UPGRADE_CHECK)
        ModuleLoaded       = $null -ne (Get-Module Posh-ACME)
    }
}


