# Configuration.ps1
# Configuration validation and management utilities

<#
.SYNOPSIS
    Validates the system configuration for AutoCert certificate management.

.DESCRIPTION
    Performs configuration validation including PowerShell version,
    required modules, file permissions, and network connectivity.

.PARAMETER Detailed
    Performs detailed validation with additional checks.

.EXAMPLE
    Test-SystemConfiguration

.EXAMPLE
    Test-SystemConfiguration -Detailed
#>

function Test-SystemConfiguration {
    [CmdletBinding()]
    param(
        [switch]$Detailed
    )

    Write-Host -Object "Running configuration validation..." -ForegroundColor Cyan

    $configIssues = @()
    $configWarnings = @()

    try {
        # Test PowerShell version
        if ($PSVersionTable.PSVersion.Major -lt 5) {
            $configIssues += "PowerShell version $($PSVersionTable.PSVersion) is not supported. Minimum version 5.1 required."
        } elseif ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -eq 0) {
            $configWarnings += "PowerShell 5.0 detected. Version 5.1 or later recommended for best compatibility."
        }

        # Test Posh-ACME module
        if (-not (Get-Module -Name Posh-ACME -ListAvailable)) {
            $configIssues += "Posh-ACME module not found. Run 'Install-Module Posh-ACME' to install."
        }

        # Test script files
        $requiredFiles = @(
            "$PSScriptRoot\..\Core\Logging.ps1",
            "$PSScriptRoot\..\Core\Helpers.ps1",
            "$PSScriptRoot\..\Functions\Register-Certificate.ps1",
            "$PSScriptRoot\..\Functions\Install-Certificate.ps1"
        )

        foreach ($file in $requiredFiles) {
            if (-not (Test-Path $file)) {
                $configIssues += "Required file missing: $file"
            }
        }

        # Test UI modules
        $uiFiles = @(
            "$PSScriptRoot\..\UI\MainMenu.ps1",
            "$PSScriptRoot\..\UI\CertificateMenu.ps1",
            "$PSScriptRoot\..\UI\CredentialMenu.ps1",
            "$PSScriptRoot\..\UI\HelpSystem.ps1"
        )

        foreach ($file in $uiFiles) {
            if (-not (Test-Path $file)) {
                $configWarnings += "UI module missing: $file"
            }
        }

        # Test write permissions
        try {
            $testPath = "$env:LOCALAPPDATA\Posh-ACME\config_test.tmp"
            New-Item -Path (Split-Path $testPath) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
            "test" | Out-File -FilePath $testPath -ErrorAction Stop
            Remove-Item $testPath -Force -ErrorAction SilentlyContinue
        } catch {
            $configIssues += "Insufficient write permissions to %LOCALAPPDATA%\Posh-ACME\"
        }

        # Test certificate store access
        try {
            Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction Stop | Out-Null
        } catch {
            $configWarnings += "Limited access to certificate store. Some operations may fail."
        }

        # Test internet connectivity
        try {
            $response = Invoke-WebRequest -Uri "https://acme-v02.api.letsencrypt.org/directory" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            if ($response.StatusCode -ne 200) {
                $configWarnings += "Let's Encrypt API accessibility issue (Status: $($response.StatusCode))"
            }
        } catch {
            $configWarnings += "Cannot reach Let's Encrypt API: $($_.Exception.Message)"
        }

        if ($Detailed) {
            # Additional checks

            # Check DNS resolution
            try {
                Resolve-DnsName -Name "letsencrypt.org" -Type A -ErrorAction Stop | Out-Null
            } catch {
                $configWarnings += "DNS resolution issues detected: $($_.Exception.Message)"
            }

            # Check proxy settings
            $proxySettings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
            if ($proxySettings.ProxyEnable -eq 1) {
                $configWarnings += "Proxy detected: $($proxySettings.ProxyServer). May affect ACME operations."
            }

            # Check available disk space
            $systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $env:SystemDrive }
            $freeSpaceGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
            if ($freeSpaceGB -lt 1) {
                $configIssues += "Low disk space: Only $freeSpaceGB GB free"
            } elseif ($freeSpaceGB -lt 5) {
                $configWarnings += "Limited disk space: $freeSpaceGB GB free"
            }
        }

        # Display results
        Write-Host -Object "`nConfiguration Validation Results:" -ForegroundColor Cyan

        if ($configIssues.Count -eq 0) {
            Write-Information -MessageData "✓ Configuration validation passed" -InformationAction Continue
        } else {
            Write-Error -Message "✗ Configuration issues found:"
            $configIssues | ForEach-Object { Write-Error -Message "  • $_" }
        }

        if ($configWarnings.Count -gt 0) {
            Write-Warning -Message "⚠ Configuration warnings:"
            $configWarnings | ForEach-Object { Write-Warning -Message "  • $_" }
        }

        return @{
            Success = ($configIssues.Count -eq 0)
            Issues = $configIssues
            Warnings = $configWarnings
        }

    } catch {
        Write-Error -Message "Configuration validation failed: $($_.Exception.Message)"
        return @{
            Success = $false
            Issues = @("Configuration validation exception: $($_.Exception.Message)")
            Warnings = @()
        }
    }
}

function Get-ConfigurationPath {
    <#
    .SYNOPSIS
        Gets the configuration directory path for AutoCert.
    #>
    return "$env:LOCALAPPDATA\Posh-ACME"
}

function Test-RequiredModules {
    <#
    .SYNOPSIS
        Tests if all required PowerShell modules are available.
    #>
    param(
        [string[]]$RequiredModules = @('Posh-ACME')
    )

    $missingModules = @()

    foreach ($module in $RequiredModules) {
        if (-not (Get-Module -Name $module -ListAvailable)) {
            $missingModules += $module
        }
    }

    return @{
        AllPresent = ($missingModules.Count -eq 0)
        MissingModules = $missingModules
    }
}

function Test-NetworkConnectivity {
    <#
    .SYNOPSIS
        Tests network connectivity to ACME services.
    #>
    param(
        [string[]]$TestHosts = @('acme-v02.api.letsencrypt.org', 'letsencrypt.org'),
        [int]$TimeoutSeconds = 10
    )

    $results = @{}

    foreach ($testHost in $TestHosts) {
        try {
            $response = Invoke-WebRequest -Uri "https://$testHost" -UseBasicParsing -TimeoutSec $TimeoutSeconds -ErrorAction Stop
            $results[$testHost] = @{
                Success = $true
                StatusCode = $response.StatusCode
                ResponseTime = (Measure-Command { Invoke-WebRequest -Uri "https://$testHost" -UseBasicParsing -TimeoutSec $TimeoutSeconds }).TotalMilliseconds
            }
        } catch {
            $results[$host] = @{
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }

    return $results
}

# Export functions for module use
# Export functions for dot-sourcing (commented out for script execution)
# Export-ModuleMember -Function Test-SystemConfiguration, Get-ConfigurationPath, Test-RequiredModules, Test-NetworkConnectivity



