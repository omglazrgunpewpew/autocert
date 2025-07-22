# Public/Initialize-CircuitBreakers.ps1
<#
    .SYNOPSIS
        Initializes circuit breakers for AutoCert operations

    .DESCRIPTION
        Public function to initialize and configure circuit breakers for various
        AutoCert operations. Circuit breakers provide resilience against cascading
        failures by temporarily stopping operations that are likely to fail.

    .PARAMETER Force
        Force re-initialization of circuit breakers even if already configured

    .PARAMETER CustomConfiguration
        Hashtable with custom circuit breaker configurations

    .EXAMPLE
        Initialize-CircuitBreakers
        Initializes circuit breakers with default settings

    .EXAMPLE
        $config = @{
            'CertificateRenewal' = @{ FailureThreshold = 5; SuccessThreshold = 2; Timeout = 900 }
        }
        Initialize-CircuitBreakers -CustomConfiguration $config
        Initializes with custom configuration

    .OUTPUTS
        System.Collections.Hashtable
        Returns initialization status and circuit breaker information
#>

function Initialize-CircuitBreaker
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Collections.Hashtable])]
    param(
        [switch]$Force,

        [hashtable]$CustomConfiguration = @{}
    )

    Write-Log "Initializing AutoCert circuit breaker system..." -Level 'Info'

    try
    {
        # Check if circuit breakers are already initialized
        if ($script:CircuitBreakers -and $script:CircuitBreakers.Count -gt 0 -and -not $Force)
        {
            Write-Log "Circuit breakers already initialized with $($script:CircuitBreakers.Count) breakers" -Level 'Info'
            return @{
                Success = $true
                Message = "Circuit breakers already initialized"
                CircuitBreakerCount = $script:CircuitBreakers.Count
                InitializationTime = $null
            }
        }

        if ($PSCmdlet.ShouldProcess("AutoCert Circuit Breaker System", "Initialize"))
        {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            # Default circuit breaker configurations
            $defaultConfigurations = @{
                'DNSValidation' = @{
                    FailureThreshold = 3
                    SuccessThreshold = 2
                    Timeout = 300  # 5 minutes
                    Description = "DNS validation operations"
                }
                'CertificateRenewal' = @{
                    FailureThreshold = 2
                    SuccessThreshold = 1
                    Timeout = 600  # 10 minutes
                    Description = "Certificate renewal operations"
                }
                'CertificateInstallation' = @{
                    FailureThreshold = 3
                    SuccessThreshold = 2
                    Timeout = 180  # 3 minutes
                    Description = "Certificate installation operations"
                }
                'EmailNotification' = @{
                    FailureThreshold = 5
                    SuccessThreshold = 3
                    Timeout = 900  # 15 minutes
                    Description = "Email notification operations"
                }
                'HealthCheck' = @{
                    FailureThreshold = 4
                    SuccessThreshold = 2
                    Timeout = 600  # 10 minutes
                    Description = "System health check operations"
                }
                'ConfigurationLoad' = @{
                    FailureThreshold = 2
                    SuccessThreshold = 1
                    Timeout = 120  # 2 minutes
                    Description = "Configuration loading operations"
                }
                'BackupOperation' = @{
                    FailureThreshold = 3
                    SuccessThreshold = 2
                    Timeout = 300  # 5 minutes
                    Description = "Backup and restore operations"
                }
                'NetworkConnectivity' = @{
                    FailureThreshold = 5
                    SuccessThreshold = 3
                    Timeout = 240  # 4 minutes
                    Description = "Network connectivity checks"
                }
            }

            # Merge custom configurations with defaults
            foreach ($key in $CustomConfiguration.Keys)
            {
                if ($defaultConfigurations.ContainsKey($key))
                {
                    # Merge custom settings with defaults
                    foreach ($setting in $CustomConfiguration[$key].Keys)
                    {
                        $defaultConfigurations[$key][$setting] = $CustomConfiguration[$key][$setting]
                    }
                } else
                {
                    # Add completely new circuit breaker
                    $defaultConfigurations[$key] = $CustomConfiguration[$key]
                }
            }

            # Ensure CircuitBreaker class is available
            if (-not ([System.Management.Automation.PSTypeName]'CircuitBreaker').Type)
            {
                throw "CircuitBreaker class not available. Ensure CircuitBreaker.ps1 is loaded."
            }

            # Initialize circuit breakers
            $script:CircuitBreakers = @{}

            foreach ($name in $defaultConfigurations.Keys)
            {
                $config = $defaultConfigurations[$name]

                try
                {
                    $circuitBreaker = [CircuitBreaker]::new(
                        $config.FailureThreshold,
                        $config.SuccessThreshold,
                        $config.Timeout
                    )

                    $script:CircuitBreakers[$name] = $circuitBreaker

                    Write-Log "Initialized circuit breaker '$name': F=$($config.FailureThreshold), S=$($config.SuccessThreshold), T=$($config.Timeout)s" -Level 'Debug'
                } catch
                {
                    Write-Log "Failed to initialize circuit breaker '$name': $($_.Exception.Message)" -Level 'Error'
                    throw
                }
            }

            $stopwatch.Stop()

            $circuitBreakerCount = $script:CircuitBreakers.Count
            $initTime = $stopwatch.ElapsedMilliseconds

            Write-Log "Circuit breaker system initialized successfully with $circuitBreakerCount breakers in $initTime ms" -Level 'Info'

            # Log circuit breaker details
            foreach ($name in $script:CircuitBreakers.Keys)
            {
                $config = $defaultConfigurations[$name]
                Write-Log "Circuit breaker '$name': $($config.Description)" -Level 'Debug'
            }

            return @{
                Success = $true
                Message = "Circuit breakers initialized successfully"
                CircuitBreakerCount = $circuitBreakerCount
                InitializationTime = $initTime
                AvailableCircuitBreakers = $script:CircuitBreakers.Keys | Sort-Object
                Configurations = $defaultConfigurations
            }
        }
    } catch
    {
        $errorMessage = "Failed to initialize circuit breakers: $($_.Exception.Message)"
        Write-Log $errorMessage -Level 'Error'

        return @{
            Success = $false
            Message = $errorMessage
            CircuitBreakerCount = 0
            InitializationTime = $null
            Error = $_.Exception
        }
    }
}

function Get-CircuitBreakerStatus
{
    <#
    .SYNOPSIS
        Gets the current status of all circuit breakers

    .DESCRIPTION
        Returns comprehensive status information about all configured circuit breakers
        including their current state, failure counts, and recent activity.

    .PARAMETER CircuitBreakerName
        Get status for a specific circuit breaker only

    .EXAMPLE
        Get-CircuitBreakerStatus
        Returns status of all circuit breakers

    .EXAMPLE
        Get-CircuitBreakerStatus -CircuitBreakerName "CertificateRenewal"
        Returns status of specific circuit breaker
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [string]$CircuitBreakerName
    )

    if (-not $script:CircuitBreakers -or $script:CircuitBreakers.Count -eq 0)
    {
        return @{
            Initialized = $false
            Message = "Circuit breakers not initialized"
            CircuitBreakers = @{}
        }
    }

    $statusReport = @{
        Initialized = $true
        TotalCircuitBreakers = $script:CircuitBreakers.Count
        CircuitBreakers = @{}
        Summary = @{
            Closed = 0
            Open = 0
            HalfOpen = 0
        }
        LastChecked = Get-Date
    }

    $circuitBreakersToCheck = if ($CircuitBreakerName)
    {
        if ($script:CircuitBreakers.ContainsKey($CircuitBreakerName))
        {
            @($CircuitBreakerName)
        } else
        {
            throw "Circuit breaker '$CircuitBreakerName' not found"
        }
    } else
    {
        $script:CircuitBreakers.Keys
    }

    foreach ($name in $circuitBreakersToCheck)
    {
        try
        {
            $status = $script:CircuitBreakers[$name].GetStatus()
            $statusReport.CircuitBreakers[$name] = $status

            # Update summary counts
            $statusReport.Summary[$status.State]++
        } catch
        {
            Write-Log "Failed to get status for circuit breaker '$name': $($_.Exception.Message)" -Level 'Warning'
            $statusReport.CircuitBreakers[$name] = @{
                State = 'Error'
                ErrorMessage = $_.Exception.Message
            }
        }
    }

    return $statusReport
}

function Test-CircuitBreakerInitialization
{
    <#
    .SYNOPSIS
        Tests if circuit breakers are properly initialized

    .DESCRIPTION
        Validates that the circuit breaker system is initialized and all expected
        circuit breakers are available and functioning.

    .OUTPUTS
        System.Boolean
        True if circuit breakers are properly initialized, False otherwise
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param()

    try
    {
        # Check if circuit breakers are initialized
        if (-not $script:CircuitBreakers -or $script:CircuitBreakers.Count -eq 0)
        {
            Write-Log "Circuit breakers not initialized" -Level 'Warning'
            return $false
        }

        # Verify expected circuit breakers exist
        $expectedCircuitBreakers = @(
            'DNSValidation',
            'CertificateRenewal',
            'CertificateInstallation',
            'NetworkConnectivity'
        )

        $missingCircuitBreakers = @()
        foreach ($cb in $expectedCircuitBreakers)
        {
            if (-not $script:CircuitBreakers.ContainsKey($cb))
            {
                $missingCircuitBreakers += $cb
            }
        }

        if ($missingCircuitBreakers.Count -gt 0)
        {
            Write-Log "Missing critical circuit breakers: $($missingCircuitBreakers -join ', ')" -Level 'Warning'
            return $false
        }

        # Test that circuit breakers are functional
        foreach ($name in $script:CircuitBreakers.Keys | Select-Object -First 3)
        {
            try
            {
                $status = $script:CircuitBreakers[$name].GetStatus()
                if (-not $status -or -not $status.ContainsKey('State'))
                {
                    Write-Log "Circuit breaker '$name' status is invalid" -Level 'Warning'
                    return $false
                }
            } catch
            {
                Write-Log "Circuit breaker '$name' is not functional: $($_.Exception.Message)" -Level 'Warning'
                return $false
            }
        }

        Write-Log "Circuit breaker system validation successful" -Level 'Debug'
        return $true
    } catch
    {
        Write-Log "Circuit breaker validation failed: $($_.Exception.Message)" -Level 'Error'
        return $false
    }
}

function Reset-AllCircuitBreaker
{
    <#
    .SYNOPSIS
        Reset all circuit breakers to closed state

    .DESCRIPTION
        Resets all circuit breakers to their initial closed state, clearing
        failure counts and history. Use this for recovery after resolving
        underlying issues.

    .PARAMETER Confirm
        Confirm before resetting all circuit breakers

    .EXAMPLE
        Reset-AllCircuitBreakers
        Resets all circuit breakers with confirmation
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param()

    if (-not $script:CircuitBreakers -or $script:CircuitBreakers.Count -eq 0)
    {
        Write-Log "No circuit breakers to reset" -Level 'Info'
        return
    }

    if ($PSCmdlet.ShouldProcess("All $($script:CircuitBreakers.Count) circuit breakers", "Reset to closed state"))
    {
        $resetCount = 0

        foreach ($name in $script:CircuitBreakers.Keys)
        {
            try
            {
                $cb = $script:CircuitBreakers[$name]
                $cb.State = 'Closed'
                $cb.FailureCount = 0
                $cb.SuccessCount = 0
                $cb.FailureHistory.Clear()

                $resetCount++
                Write-Log "Reset circuit breaker '$name' to closed state" -Level 'Debug'
            } catch
            {
                Write-Log "Failed to reset circuit breaker '$name': $($_.Exception.Message)" -Level 'Warning'
            }
        }

        Write-Log "Reset $resetCount circuit breakers to closed state" -Level 'Info'
    }
}
