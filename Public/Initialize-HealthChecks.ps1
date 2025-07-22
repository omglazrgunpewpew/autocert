# Public/Initialize-HealthChecks.ps1
<#
    .SYNOPSIS
        Initializes the health check system for AutoCert

    .DESCRIPTION
        Public wrapper function that initializes the comprehensive health monitoring
        system. This function sets up all health checks and makes them available
        for monitoring certificate management operations.

    .PARAMETER Force
        Force re-initialization of health checks even if already initialized

    .EXAMPLE
        Initialize-HealthChecks
        Initializes the health check system with default settings

    .EXAMPLE
        Initialize-HealthChecks -Force
        Forces re-initialization of the health check system

    .OUTPUTS
        System.Collections.Hashtable
        Returns initialization status and health check count

    .NOTES
        This function is a public API wrapper around the internal Initialize-HealthCheck
        function in Core/HealthMonitor.ps1. It provides a clean interface for
        initializing the health monitoring system.
#>

function Initialize-HealthCheck
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Collections.Hashtable])]
    param(
        [switch]$Force
    )

    Write-Log "Initializing AutoCert health check system..." -Level 'Info'

    try
    {
        # Check if health checks are already initialized
        if ($script:HealthChecks -and $script:HealthChecks.Count -gt 0 -and -not $Force)
        {
            Write-Log "Health checks already initialized with $($script:HealthChecks.Count) checks" -Level 'Info'
            return @{
                Success = $true
                Message = "Health checks already initialized"
                CheckCount = $script:HealthChecks.Count
                InitializationTime = $null
            }
        }

        if ($PSCmdlet.ShouldProcess("AutoCert Health Check System", "Initialize"))
        {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            # Call the internal initialization function
            if (Get-Command Initialize-HealthCheck -ErrorAction SilentlyContinue)
            {
                Initialize-HealthCheck
            } else
            {
                throw "Core health check initialization function not available. Ensure HealthMonitor.ps1 is loaded."
            }

            $stopwatch.Stop()

            # Verify initialization succeeded
            if (-not $script:HealthChecks -or $script:HealthChecks.Count -eq 0)
            {
                throw "Health check initialization failed - no health checks were configured"
            }

            $checkCount = $script:HealthChecks.Count
            $initTime = $stopwatch.ElapsedMilliseconds

            Write-Log "Health check system initialized successfully with $checkCount checks in $initTime ms" -Level 'Info'

            # Log available health check categories
            $categories = $script:HealthChecks.Values |
                Group-Object Category |
                ForEach-Object { "$($_.Name): $($_.Count)" }
            Write-Log "Available health check categories: $($categories -join ', ')" -Level 'Debug'

            return @{
                Success = $true
                Message = "Health checks initialized successfully"
                CheckCount = $checkCount
                InitializationTime = $initTime
                Categories = $script:HealthChecks.Values | Group-Object Category | ForEach-Object { $_.Name }
            }
        }
    } catch
    {
        $errorMessage = "Failed to initialize health checks: $($_.Exception.Message)"
        Write-Log $errorMessage -Level 'Error'

        return @{
            Success = $false
            Message = $errorMessage
            CheckCount = 0
            InitializationTime = $null
            Error = $_.Exception
        }
    }
}

function Get-HealthCheckStatus
{
    <#
    .SYNOPSIS
        Gets the current status of the health check system

    .DESCRIPTION
        Returns information about the health check system initialization status
        and available health checks.

    .OUTPUTS
        System.Collections.Hashtable
        Status information about the health check system
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param()

    $isInitialized = $script:HealthChecks -and $script:HealthChecks.Count -gt 0

    if ($isInitialized)
    {
        $categories = $script:HealthChecks.Values | Group-Object Category
        $criticalCount = ($script:HealthChecks.Values | Where-Object { $_.IsCritical }).Count

        return @{
            Initialized = $true
            TotalChecks = $script:HealthChecks.Count
            Categories      = $categories | ForEach-Object {
                @{
                    Name = $_.Name
                    Count = $_.Count
                }
            }
            CriticalChecks = $criticalCount
            AvailableChecks = $script:HealthChecks.Keys | Sort-Object
        }
    } else
    {
        return @{
            Initialized = $false
            TotalChecks = 0
            Categories = @()
            CriticalChecks = 0
            AvailableChecks = @()
        }
    }
}

function Test-HealthCheckInitialization
{
    <#
    .SYNOPSIS
        Tests if the health check system is properly initialized

    .DESCRIPTION
        Validates that the health check system is initialized and all expected
        health checks are available.

    .OUTPUTS
        System.Boolean
        True if health checks are properly initialized, False otherwise
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param()

    try
    {
        # Check if health checks are initialized
        if (-not $script:HealthChecks -or $script:HealthChecks.Count -eq 0)
        {
            Write-Log "Health checks not initialized" -Level 'Warning'
            return $false
        }

        # Verify expected critical health checks exist
        $expectedCriticalChecks = @(
            'PowerShellVersion',
            'AdminPrivileges',
            'PoshACMEModule'
        )

        $missingCritical = @()
        foreach ($check in $expectedCriticalChecks)
        {
            if (-not $script:HealthChecks.ContainsKey($check))
            {
                $missingCritical += $check
            }
        }

        if ($missingCritical.Count -gt 0)
        {
            Write-Log "Missing critical health checks: $($missingCritical -join ', ')" -Level 'Warning'
            return $false
        }

        Write-Log "Health check system validation successful" -Level 'Debug'
        return $true
    } catch
    {
        Write-Log "Health check validation failed: $($_.Exception.Message)" -Level 'Error'
        return $false
    }
}
