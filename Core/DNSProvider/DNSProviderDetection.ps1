# Core/DNSProvider/DNSProviderDetection.ps1
<#
    .SYNOPSIS
        DNS provider detection and public suffix list management for AutoCert.
    .DESCRIPTION
        This is now a lightweight wrapper that imports the modular DNS provider detection system.
        The actual functionality has been split into focused modules for better maintainability.
    .NOTES
        Version: 1.0.0
        Author: AutoCert Team
        Created: 2025-01-01
        Updated: 2025-01-19

        This file now imports the modular DNS provider detection system.
        See DNSProviderDetection.psm1 and its component modules for the implementation.
#>

# Import the modular DNS provider detection system
$ModulePath = Join-Path $PSScriptRoot "DNSProviderDetection.psm1"
if (Test-Path $ModulePath)
{
    Import-Module $ModulePath -Force -Global
    Write-Verbose "Loaded modular DNS Provider Detection system"
} else
{
    Write-Error "Could not find DNS Provider Detection module at: $ModulePath"
}
