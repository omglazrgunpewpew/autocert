# Error Handling Utilities
# Part of AutoCert Certificate Management System
# Version: 1.0
# Date: July 8, 2025

<#
.SYNOPSIS
    Error handling utilities for AutoCert
.DESCRIPTION
    Provides consistent error handling, retry logic, and progress reporting
    functions for the AutoCert certificate management system
.NOTES
    Used throughout the application for robust error handling
#>

# Error handling wrapper for menu operations
function Invoke-MenuOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Operation,
        [Parameter(Mandatory = $true)]
        [string]$OperationName
    )
    
    try {
        Write-Host "`nStarting $OperationName..." -ForegroundColor Cyan
        Write-ProgressHelper -Activity "Certificate Management" -Status "Preparing $OperationName..." -PercentComplete 0
        
        $startTime = Get-Date
        & $Operation
        $duration = (Get-Date) - $startTime
        
        Write-Host "`n$OperationName completed successfully in $($duration.TotalSeconds.ToString('F1')) seconds." -ForegroundColor Green
        Write-Log "$OperationName completed successfully" -Level 'Success'
        
    } catch {
        $errorMsg = "$OperationName failed: $($_.Exception.Message)"
        Write-Error $errorMsg
        Write-Log $errorMsg -Level 'Error'
        
        # Enhanced error reporting
        Write-Host "`nError Details:" -ForegroundColor Red
        Write-Host "  Operation: $OperationName" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Location: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
        
        # Provide context-specific troubleshooting
        Write-Host "`nTroubleshooting suggestions:" -ForegroundColor Yellow
        switch ($OperationName) {
            "certificate registration" {
                Write-Host "• Check DNS provider credentials and permissions" -ForegroundColor Yellow
                Write-Host "• Verify domain ownership and DNS propagation" -ForegroundColor Yellow
                Write-Host "• Test internet connectivity to ACME servers" -ForegroundColor Yellow
            }
            "certificate installation" {
                Write-Host "• Ensure script is running as Administrator" -ForegroundColor Yellow
                Write-Host "• Check certificate store permissions" -ForegroundColor Yellow
                Write-Host "• Verify certificate file integrity" -ForegroundColor Yellow
            }
            default {
                Write-Host "• Check the log files for detailed error information" -ForegroundColor Yellow
                Write-Host "• Run system health check to identify configuration issues" -ForegroundColor Yellow
                Write-Host "• Verify all required modules are loaded correctly" -ForegroundColor Yellow
            }
        }
        
    } finally {
        Write-Progress -Activity "Certificate Management" -Completed
    }
}

# Retry logic for operations that may temporarily fail
function Invoke-WithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxAttempts = 3,
        
        [Parameter(Mandatory = $false)]
        [int]$InitialDelaySeconds = 1,
        
        [Parameter(Mandatory = $false)]
        [double]$BackoffMultiplier = 2.0,
        
        [Parameter(Mandatory = $false)]
        [string]$OperationName = "Operation"
    )
    
    $attempt = 1
    $delay = $InitialDelaySeconds
    $success = $false
    $result = $null
    $lastException = $null
    
    while (-not $success -and $attempt -le $MaxAttempts) {
        try {
            if ($attempt -gt 1) {
                Write-Verbose "Retry attempt $attempt of $MaxAttempts for $OperationName after $delay second delay"
            }
            
            $result = & $ScriptBlock
            $success = $true
        } catch {
            $lastException = $_
            
            if ($attempt -lt $MaxAttempts) {
                Write-Warning "$OperationName failed (Attempt $attempt of $MaxAttempts): $($_.Exception.Message). Retrying in $delay seconds..."
                Start-Sleep -Seconds $delay
                $delay = [math]::Min(60, $delay * $BackoffMultiplier) # Cap at 60 seconds
                $attempt++
            } else {
                Write-Error "$OperationName failed after $MaxAttempts attempts: $($_.Exception.Message)"
                throw $lastException
            }
        }
    }
    
    if ($success) {
        Write-Verbose "$OperationName succeeded on attempt $attempt"
        return $result
    }
}

# Helper function to display consistent progress bars
function Write-ProgressHelper {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Activity,
        
        [Parameter(Mandatory = $true)]
        [string]$Status,
        
        [Parameter(Mandatory = $true)]
        [int]$PercentComplete,
        
        [Parameter(Mandatory = $false)]
        [string]$CurrentOperation = ""
    )
    
    Write-Progress -Activity $Activity -Status $Status -CurrentOperation $CurrentOperation -PercentComplete $PercentComplete
}

# Improved logging function with support for different log levels
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Debug')]
        [string]$Level = 'Info',
        
        [Parameter(Mandatory = $false)]
        [string]$LogFile = "$env:LOCALAPPDATA\Posh-ACME\certificate_script.log",
        
        [Parameter(Mandatory = $false)]
        [switch]$NoConsole,
        
        [Parameter(Mandatory = $false)]
        [switch]$WriteEventLog
    )
    
    # Create timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Format log message
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Ensure log directory exists
    $logDir = Split-Path -Path $LogFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    # Write to log file
    Add-Content -Path $LogFile -Value $logEntry
    
    # Write to console if not disabled
    if (-not $NoConsole) {
        $color = switch ($Level) {
            'Info'    { 'White' }
            'Warning' { 'Yellow' }
            'Error'   { 'Red' }
            'Success' { 'Green' }
            'Debug'   { 'Gray' }
            default   { 'White' }
        }
        
        Write-Host $logEntry -ForegroundColor $color
    }
    
    # Write to event log if specified
    if ($WriteEventLog) {
        $eventId = switch ($Level) {
            'Info'    { 1000 }
            'Warning' { 2000 }
            'Error'   { 3000 }
            'Success' { 4000 }
            'Debug'   { 5000 }
            default   { 1000 }
        }
        
        $entryType = switch ($Level) {
            'Error'   { 'Error' }
            'Warning' { 'Warning' }
            default   { 'Information' }
        }
        
        try {
            New-EventLog -LogName Application -Source "Certificate Management" -ErrorAction SilentlyContinue
            Write-EventLog -LogName Application -Source "Certificate Management" -EventId $eventId -Message $Message -EntryType $entryType
        } catch {
            Write-Host "Failed to write to event log: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# Export functions
Export-ModuleMember -Function Invoke-MenuOperation, Invoke-WithRetry, Write-ProgressHelper, Write-Log
