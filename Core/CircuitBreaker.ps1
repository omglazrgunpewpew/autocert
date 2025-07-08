# Core/CircuitBreaker.ps1
<#
    .SYNOPSIS
        Circuit breaker pattern implementation for resilience.
#>

class CircuitBreaker {
    [int]$FailureThreshold
    [int]$SuccessThreshold
    [int]$Timeout
    [int]$FailureCount
    [int]$SuccessCount
    [datetime]$LastFailureTime
    [string]$State
    [hashtable]$FailureHistory
    
    CircuitBreaker([int]$FailureThreshold, [int]$SuccessThreshold, [int]$Timeout) {
        $this.FailureThreshold = $FailureThreshold
        $this.SuccessThreshold = $SuccessThreshold
        $this.Timeout = $Timeout
        $this.FailureCount = 0
        $this.SuccessCount = 0
        $this.LastFailureTime = [datetime]::MinValue
        $this.State = 'Closed'
        $this.FailureHistory = @{}
    }
    
    [object] Execute([scriptblock]$Operation, [string]$OperationName) {
        if ($this.State -eq 'Open') {
            if ((Get-Date) - $this.LastFailureTime -gt [timespan]::FromSeconds($this.Timeout)) {
                $this.State = 'HalfOpen'
                $this.SuccessCount = 0
                Write-Log "Circuit breaker for $OperationName transitioning to Half-Open state" -Level 'Info'
            } else {
                $remainingTime = $this.Timeout - ((Get-Date) - $this.LastFailureTime).TotalSeconds
                throw "Circuit breaker is OPEN for $OperationName. Retry in $([math]::Round($remainingTime)) seconds"
            }
        }
        
        try {
            $result = & $Operation
            $this.OnSuccess($OperationName)
            return $result
        } catch {
            $this.OnFailure($OperationName, $_.Exception.Message)
            throw
        }
    }
    
    [void] OnSuccess([string]$OperationName) {
        $this.SuccessCount++
        
        if ($this.State -eq 'HalfOpen') {
            if ($this.SuccessCount -ge $this.SuccessThreshold) {
                $this.State = 'Closed'
                $this.FailureCount = 0
                $this.FailureHistory.Clear()
                Write-Log "Circuit breaker for $OperationName reset to Closed state" -Level 'Info'
            }
        } else {
            $this.FailureCount = 0
        }
    }
    
    [void] OnFailure([string]$OperationName, [string]$ErrorMessage) {
        $this.FailureCount++
        $this.LastFailureTime = Get-Date
        
        # Track failure patterns
        $failureKey = Get-Date -Format "yyyy-MM-dd HH"
        if (-not $this.FailureHistory.ContainsKey($failureKey)) {
            $this.FailureHistory[$failureKey] = @{
                Count = 0
                Errors = @()
            }
        }
        $this.FailureHistory[$failureKey].Count++
        $this.FailureHistory[$failureKey].Errors += $ErrorMessage
        
        if ($this.FailureCount -ge $this.FailureThreshold) {
            $this.State = 'Open'
            Write-Log "Circuit breaker for $OperationName opened due to $($this.FailureCount) failures" -Level 'Warning'
        }
    }
    
    [hashtable] GetStatus() {
        return @{
            State = $this.State
            FailureCount = $this.FailureCount
            SuccessCount = $this.SuccessCount
            LastFailureTime = $this.LastFailureTime
            FailureHistory = $this.FailureHistory
        }
    }
}

# Global circuit breakers for different operations
$script:CircuitBreakers = @{
    'DNSValidation' = [CircuitBreaker]::new(3, 2, 300)  # 3 failures, 2 successes, 5 min timeout
    'CertificateRenewal' = [CircuitBreaker]::new(2, 1, 600)  # 2 failures, 1 success, 10 min timeout
    'CertificateInstallation' = [CircuitBreaker]::new(3, 2, 180)  # 3 failures, 2 successes, 3 min timeout
    'EmailNotification' = [CircuitBreaker]::new(5, 3, 900)  # 5 failures, 3 successes, 15 min timeout
}

function Invoke-WithCircuitBreaker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OperationName,
        [Parameter(Mandatory)]
        [scriptblock]$Operation,
        [string]$FallbackOperation = $null
    )
    
    if (-not $script:CircuitBreakers.ContainsKey($OperationName)) {
        throw "No circuit breaker configured for operation: $OperationName"
    }
    
    try {
        return $script:CircuitBreakers[$OperationName].Execute($Operation, $OperationName)
    } catch {
        if ($FallbackOperation) {
            Write-Log "Circuit breaker triggered for $OperationName, executing fallback" -Level 'Warning'
            return & $FallbackOperation
        } else {
            throw
        }
    }
}

function Get-CircuitBreakerStatus {
    [CmdletBinding()]
    param(
        [string]$OperationName
    )
    
    if ($OperationName) {
        if ($script:CircuitBreakers.ContainsKey($OperationName)) {
            return $script:CircuitBreakers[$OperationName].GetStatus()
        } else {
            throw "No circuit breaker found for operation: $OperationName"
        }
    } else {
        $status = @{}
        foreach ($name in $script:CircuitBreakers.Keys) {
            $status[$name] = $script:CircuitBreakers[$name].GetStatus()
        }
        return $status
    }
}

function Reset-CircuitBreaker {
    [CmdletBinding()]
    param(
        [string]$OperationName
    )
    
    if ($OperationName) {
        if ($script:CircuitBreakers.ContainsKey($OperationName)) {
            $script:CircuitBreakers[$OperationName].State = 'Closed'
            $script:CircuitBreakers[$OperationName].FailureCount = 0
            $script:CircuitBreakers[$OperationName].SuccessCount = 0
            $script:CircuitBreakers[$OperationName].FailureHistory.Clear()
            Write-Log "Circuit breaker for $OperationName manually reset" -Level 'Info'
        }
    } else {
        foreach ($name in $script:CircuitBreakers.Keys) {
            Reset-CircuitBreaker -OperationName $name
        }
    }
}
