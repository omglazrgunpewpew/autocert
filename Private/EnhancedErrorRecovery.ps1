# Private/EnhancedErrorRecovery.ps1
<#
    .SYNOPSIS
        Enhanced error recovery mechanisms with automatic retry and failure handling.

    .DESCRIPTION
        Provides advanced error recovery capabilities including:
        - Intelligent retry strategies with exponential backoff
        - Transient error detection and handling
        - Recovery state management
        - Failure pattern analysis
        - Automatic fallback mechanisms

    .NOTES
        This module extends the existing error handling with more sophisticated recovery patterns.
#>

class RetryStrategy
{
    [int]$MaxAttempts
    [int]$BaseDelaySeconds
    [double]$BackoffMultiplier
    [int]$MaxDelaySeconds
    [bool]$UseJitter
    [hashtable]$TransientErrorPatterns

    RetryStrategy()
    {
        $this.MaxAttempts = 5
        $this.BaseDelaySeconds = 2
        $this.BackoffMultiplier = 2.0
        $this.MaxDelaySeconds = 300  # 5 minutes max
        $this.UseJitter = $true
        $this.TransientErrorPatterns = @{
            'Network'        = @('timeout', 'connection', 'network', 'dns', 'unreachable')
            'RateLimit'      = @('rate limit', 'too many requests', '429', 'quota exceeded')
            'Service'        = @('service unavailable', '503', 'temporary', 'maintenance')
            'Authentication' = @('unauthorized', '401', 'token expired', 'authentication failed')
        }
    }

    [bool] IsTransientError([string]$ErrorMessage)
    {
        $errorLower = $ErrorMessage.ToLower()

        foreach ($category in $this.TransientErrorPatterns.Keys)
        {
            foreach ($pattern in $this.TransientErrorPatterns[$category])
            {
                if ($errorLower -like "*$pattern*")
                {
                    Write-Log "Identified transient error ($category): $pattern" -Level 'Debug'
                    return $true
                }
            }
        }

        return $false
    }

    [int] CalculateDelay([int]$AttemptNumber)
    {
        $delay = $this.BaseDelaySeconds * [Math]::Pow($this.BackoffMultiplier, $AttemptNumber - 1)

        # Apply jitter to prevent thundering herd
        if ($this.UseJitter)
        {
            $jitterRange = $delay * 0.1  # 10% jitter
            $jitter = (Get-Random -Minimum (-$jitterRange) -Maximum $jitterRange)
            $delay += $jitter
        }

        # Cap at maximum delay
        return [Math]::Min($delay, $this.MaxDelaySeconds)
    }
}

class RecoveryState
{
    [string]$OperationName
    [datetime]$LastAttempt
    [int]$ConsecutiveFailures
    [int]$TotalFailures
    [int]$TotalAttempts
    [hashtable]$ErrorHistory
    [string]$LastError
    [string]$RecoveryAction

    RecoveryState([string]$OperationName)
    {
        $this.OperationName = $OperationName
        $this.LastAttempt = [datetime]::MinValue
        $this.ConsecutiveFailures = 0
        $this.TotalFailures = 0
        $this.TotalAttempts = 0
        $this.ErrorHistory = @{}
        $this.LastError = ""
        $this.RecoveryAction = ""
    }

    [void] RecordAttempt([bool]$Success, [string]$ErrorMessage = "")
    {
        $this.LastAttempt = Get-Date
        $this.TotalAttempts++

        if ($Success)
        {
            $this.ConsecutiveFailures = 0
            $this.RecoveryAction = "Operation succeeded"
        } else
        {
            $this.ConsecutiveFailures++
            $this.TotalFailures++
            $this.LastError = $ErrorMessage

            # Track error patterns
            $errorKey = Get-Date -Format "yyyy-MM-dd HH"
            if (-not $this.ErrorHistory.ContainsKey($errorKey))
            {
                $this.ErrorHistory[$errorKey] = @()
            }
            $this.ErrorHistory[$errorKey] += $ErrorMessage
        }
    }

    [hashtable] GetStatus()
    {
        $successRate = if ($this.TotalAttempts -gt 0)
        {
            (($this.TotalAttempts - $this.TotalFailures) / $this.TotalAttempts) * 100
        } else { 0 }

        return @{
            OperationName       = $this.OperationName
            LastAttempt         = $this.LastAttempt
            ConsecutiveFailures = $this.ConsecutiveFailures
            TotalFailures       = $this.TotalFailures
            TotalAttempts       = $this.TotalAttempts
            SuccessRate         = [math]::Round($successRate, 2)
            LastError           = $this.LastError
            RecoveryAction      = $this.RecoveryAction
            ErrorHistory        = $this.ErrorHistory
        }
    }
}

# Global recovery state tracking
$script:RecoveryStates = @{}

function Invoke-EnhancedRetry
{
    <#
    .SYNOPSIS
        Execute an operation with enhanced retry logic and error recovery.

    .DESCRIPTION
        Provides intelligent retry mechanisms with:
        - Transient error detection
        - Exponential backoff with jitter
        - Recovery state tracking
        - Fallback operation support
        - Circuit breaker integration
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Operation,

        [Parameter(Mandatory)]
        [string]$OperationName,

        [RetryStrategy]$Strategy = [RetryStrategy]::new(),

        [scriptblock]$FallbackOperation = $null,

        [scriptblock]$PreRetryAction = $null,

        [switch]$UseCircuitBreaker,

        [hashtable]$Context = @{}
    )

    # Initialize or get recovery state
    if (-not $script:RecoveryStates.ContainsKey($OperationName))
    {
        $script:RecoveryStates[$OperationName] = [RecoveryState]::new($OperationName)
    }
    $recoveryState = $script:RecoveryStates[$OperationName]

    $attempt = 1
    $lastException = $null

    Write-Log "Starting enhanced retry for operation: $OperationName" -Level 'Debug'

    while ($attempt -le $Strategy.MaxAttempts)
    {
        try
        {
            Write-Log "Attempt $attempt of $($Strategy.MaxAttempts) for $OperationName" -Level 'Debug'

            # Execute with circuit breaker if requested
            if ($UseCircuitBreaker -and $script:CircuitBreakers.ContainsKey($OperationName))
            {
                $result = $script:CircuitBreakers[$OperationName].Execute($Operation, $OperationName)
            } else
            {
                $result = & $Operation
            }

            # Record successful attempt
            $recoveryState.RecordAttempt($true)
            Write-Log "Operation $OperationName succeeded on attempt $attempt" -Level 'Success'

            return $result

        } catch
        {
            $lastException = $_
            $errorMessage = $_.Exception.Message

            # Record failed attempt
            $recoveryState.RecordAttempt($false, $errorMessage)

            Write-Log "Attempt $attempt failed for $OperationName`: $errorMessage" -Level 'Warning'

            # Check if this is the last attempt
            if ($attempt -eq $Strategy.MaxAttempts)
            {
                Write-Log "All $($Strategy.MaxAttempts) attempts failed for $OperationName" -Level 'Error'
                break
            }

            # Determine if error is transient and worth retrying
            $isTransient = $Strategy.IsTransientError($errorMessage)

            if (-not $isTransient)
            {
                Write-Log "Non-transient error detected for $OperationName`: $errorMessage" -Level 'Warning'

                # For non-transient errors, try fallback immediately if available
                if ($FallbackOperation)
                {
                    Write-Log "Attempting fallback operation for $OperationName" -Level 'Info'
                    try
                    {
                        $fallbackResult = & $FallbackOperation
                        $recoveryState.RecoveryAction = "Fallback operation succeeded"
                        Write-Log "Fallback operation succeeded for $OperationName" -Level 'Success'
                        return $fallbackResult
                    } catch
                    {
                        Write-Log "Fallback operation also failed for $OperationName`: $($_.Exception.Message)" -Level 'Error'
                    }
                }

                # For non-transient errors without successful fallback, fail fast
                break
            }

            # Calculate delay for next attempt
            $delay = $Strategy.CalculateDelay($attempt)
            Write-Log "Waiting $delay seconds before retry attempt $($attempt + 1) for $OperationName" -Level 'Info'

            # Execute pre-retry action if provided
            if ($PreRetryAction)
            {
                try
                {
                    Write-Log "Executing pre-retry action for $OperationName" -Level 'Debug'
                    & $PreRetryAction -AttemptNumber $attempt -ErrorMessage $errorMessage -Context $Context
                } catch
                {
                    Write-Log "Pre-retry action failed for $OperationName`: $($_.Exception.Message)" -Level 'Warning'
                }
            }

            Start-Sleep -Seconds $delay
            $attempt++
        }
    }

    # All attempts failed, try fallback if available
    if ($FallbackOperation)
    {
        Write-Log "All retry attempts failed, trying fallback operation for $OperationName" -Level 'Warning'
        try
        {
            $fallbackResult = & $FallbackOperation
            $recoveryState.RecoveryAction = "Fallback operation succeeded after all retries failed"
            Write-Log "Fallback operation succeeded for $OperationName" -Level 'Success'
            return $fallbackResult
        } catch
        {
            $recoveryState.RecoveryAction = "Both main operation and fallback failed"
            Write-Log "Fallback operation also failed for $OperationName`: $($_.Exception.Message)" -Level 'Error'
        }
    }

    # Complete failure
    $recoveryState.RecoveryAction = "Operation failed after all attempts"
    throw $lastException
}

function Get-RecoveryStatus
{
    <#
    .SYNOPSIS
        Get the current status of all recovery operations.
    #>
    [CmdletBinding()]
    param(
        [string]$OperationName = $null
    )

    if ($OperationName)
    {
        if ($script:RecoveryStates.ContainsKey($OperationName))
        {
            return $script:RecoveryStates[$OperationName].GetStatus()
        } else
        {
            Write-Warning "No recovery state found for operation: $OperationName"
            return $null
        }
    } else
    {
        $allStatus = @{}
        foreach ($key in $script:RecoveryStates.Keys)
        {
            $allStatus[$key] = $script:RecoveryStates[$key].GetStatus()
        }
        return $allStatus
    }
}

function Reset-RecoveryState
{
    <#
    .SYNOPSIS
        Reset recovery state for specified operation or all operations.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$OperationName = $null
    )

    if ($OperationName)
    {
        if ($script:RecoveryStates.ContainsKey($OperationName))
        {
            if ($PSCmdlet.ShouldProcess("Recovery state for $OperationName", "Reset"))
            {
                $script:RecoveryStates.Remove($OperationName)
                Write-Log "Recovery state reset for operation: $OperationName" -Level 'Info'
            }
        }
    } else
    {
        if ($PSCmdlet.ShouldProcess("All recovery states", "Reset"))
        {
            $script:RecoveryStates.Clear()
            Write-Log "All recovery states reset" -Level 'Info'
        }
    }
}

function Invoke-RecoveryHealthCheck
{
    <#
    .SYNOPSIS
        Perform health check on recovery mechanisms and provide recommendations.
    #>
    [CmdletBinding()]
    param()

    $healthReport = @{
        OverallHealth   = "Good"
        Issues          = @()
        Recommendations = @()
        RecoveryStates  = @()
        CircuitBreakers = @()
    }

    # Check recovery states
    foreach ($operationName in $script:RecoveryStates.Keys)
    {
        $state = $script:RecoveryStates[$operationName].GetStatus()
        $healthReport.RecoveryStates += $state

        # Analyze for issues
        if ($state.ConsecutiveFailures -gt 3)
        {
            $healthReport.Issues += "Operation '$operationName' has $($state.ConsecutiveFailures) consecutive failures"
            $healthReport.Recommendations += "Investigate recurring issues with operation '$operationName'"
        }

        if ($state.SuccessRate -lt 80 -and $state.TotalAttempts -gt 5)
        {
            $healthReport.Issues += "Operation '$operationName' has low success rate: $($state.SuccessRate)%"
            $healthReport.Recommendations += "Review and improve reliability of operation '$operationName'"
        }
    }

    # Check circuit breakers
    foreach ($cbName in $script:CircuitBreakers.Keys)
    {
        $cbStatus = $script:CircuitBreakers[$cbName].GetStatus()
        $healthReport.CircuitBreakers += @{
            Name   = $cbName
            Status = $cbStatus
        }

        if ($cbStatus.State -eq 'Open')
        {
            $healthReport.Issues += "Circuit breaker '$cbName' is currently OPEN"
            $healthReport.Recommendations += "Wait for circuit breaker '$cbName' to transition to Half-Open, or investigate underlying issues"
        }
    }

    # Determine overall health
    if ($healthReport.Issues.Count -gt 5)
    {
        $healthReport.OverallHealth = "Poor"
    } elseif ($healthReport.Issues.Count -gt 2)
    {
        $healthReport.OverallHealth = "Fair"
    }

    return $healthReport
}

# Export functions for module usage
# Export-ModuleMember -Function @(
#     'Invoke-EnhancedRetry',
#     'Get-RecoveryStatus',
#     'Reset-RecoveryState',
#     'Invoke-RecoveryHealthCheck'
# ) -Variable @('RecoveryStates')
