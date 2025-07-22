# Error Handling Functions
# Part of AutoCert Certificate Management System
# Version: 1.0
# Date: July 21, 2025

<#
.SYNOPSIS
    Enhanced error handling functions for AutoCert system
.DESCRIPTION
    Provides comprehensive error handling including error categorization,
    recovery strategies, and user-friendly error reporting.
.NOTES
    This file contains error handling helper functions
#>

function Invoke-SafeOperation
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Operation,

        [Parameter()]
        [string]$OperationName = "Operation",

        [Parameter()]
        [scriptblock]$OnError,

        [Parameter()]
        [switch]$SuppressErrorOutput
    )

    try
{
        Write-Log "Starting operation: $OperationName" -Level 'Debug'
        $result = & $Operation
        Write-Log "Operation completed successfully: $OperationName" -Level 'Debug'
        return @{
            Success = $true
            Result = $result
            OperationName = $OperationName
        }
    } catch
     {
        $errorDetails = @{
            Success = $false
            OperationName = $OperationName
            ErrorMessage = $_.Exception.Message
            ErrorType = $_.Exception.GetType().Name
            StackTrace = $_.ScriptStackTrace
            Timestamp = Get-Date
        }

        Write-Log "Operation failed: $OperationName - $($_.Exception.Message)" -Level 'Error'

        if (-not $SuppressErrorOutput)
{
            Write-Error -Message "Failed to execute $OperationName`: $($_.Exception.Message)"
        }

        # Execute error handler if provided
        if ($OnError)
                                           {
            try
                       {
                & $OnError $errorDetails
            } catch
             {
                Write-Log "Error handler failed: $($_.Exception.Message)" -Level 'Error'
            }
        }

        return $errorDetails
    }
}

function Get-ErrorCategory
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Exception]$Exception
    )

    $errorType = $Exception.GetType().Name

    switch -Regex ($errorType)
{
        'UnauthorizedAccessException|SecurityException'
                                {
            return @{
                Category = 'Security'
                Severity = 'High'
                UserMessage = 'Access denied. Please check permissions or run as administrator.'
                TechnicalMessage = $Exception.Message
            }
        }
        'NetworkException|HttpRequestException|WebException'
         {
            return @{
                Category = 'Network'
                Severity = 'Medium'
                UserMessage = 'Network connectivity issue. Please check your internet connection.'
                TechnicalMessage = $Exception.Message
            }
        }
        'FileNotFoundException|DirectoryNotFoundException|PathTooLongException'
         {
            return @{
                Category = 'FileSystem'
                Severity = 'Medium'
                UserMessage = 'File or directory not found. Please verify the path exists.'
                TechnicalMessage = $Exception.Message
            }
        }
        'ArgumentException|ArgumentNullException|ArgumentOutOfRangeException'
         {
            return @{
                Category = 'Validation'
                Severity = 'Low'
                UserMessage = 'Invalid input provided. Please check your parameters.'
                TechnicalMessage = $Exception.Message
            }
        }
        'TimeoutException'
         {
            return @{
                Category = 'Timeout'
                Severity = 'Medium'
                UserMessage = 'Operation timed out. Please try again or check network connectivity.'
                TechnicalMessage = $Exception.Message
            }
        }
        default
         {
            return @{
                Category = 'General'
                Severity = 'Medium'
                UserMessage = 'An unexpected error occurred. Please check the logs for details.'
                TechnicalMessage = $Exception.Message
            }
        }
    }
}

function Show-FriendlyError
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Exception]$Exception,

        [Parameter()]
        [string]$Context = "operation",

        [Parameter()]
        [switch]$ShowTechnicalDetails
    )

    $errorInfo = Get-ErrorCategory -Exception $Exception

    Write-Host "`n❌ Error during $Context" -ForegroundColor Red
    Write-Host "   $($errorInfo.UserMessage)" -ForegroundColor Yellow

    if ($ShowTechnicalDetails)
{
        Write-Host "`nTechnical Details:" -ForegroundColor Gray
        Write-Host "   Category: $($errorInfo.Category)" -ForegroundColor Gray
        Write-Host "   Severity: $($errorInfo.Severity)" -ForegroundColor Gray
        Write-Host "   Technical Message: $($errorInfo.TechnicalMessage)" -ForegroundColor Gray
        Write-Host "   Error Type: $($Exception.GetType().Name)" -ForegroundColor Gray
    }

    # Provide recovery suggestions
    switch ($errorInfo.Category)
                                  {
        'Security'
                                  {
            Write-Host "`n💡 Suggestions:" -ForegroundColor Cyan
            Write-Host "   • Try running PowerShell as Administrator" -ForegroundColor Cyan
            Write-Host "   • Check file/folder permissions" -ForegroundColor Cyan
            Write-Host "   • Verify user account has necessary rights" -ForegroundColor Cyan
        }
        'Network'
         {
            Write-Host "`n💡 Suggestions:" -ForegroundColor Cyan
            Write-Host "   • Check your internet connection" -ForegroundColor Cyan
            Write-Host "   • Verify firewall settings" -ForegroundColor Cyan
            Write-Host "   • Try again in a few minutes" -ForegroundColor Cyan
        }
        'FileSystem'
         {
            Write-Host "`n💡 Suggestions:" -ForegroundColor Cyan
            Write-Host "   • Verify the file or folder exists" -ForegroundColor Cyan
            Write-Host "   • Check the path is correct" -ForegroundColor Cyan
            Write-Host "   • Ensure sufficient disk space" -ForegroundColor Cyan
        }
        'Validation'
         {
            Write-Host "`n💡 Suggestions:" -ForegroundColor Cyan
            Write-Host "   • Check input parameters are correct" -ForegroundColor Cyan
            Write-Host "   • Verify required fields are provided" -ForegroundColor Cyan
            Write-Host "   • Review parameter format requirements" -ForegroundColor Cyan
        }
        'Timeout'
         {
            Write-Host "`n💡 Suggestions:" -ForegroundColor Cyan
            Write-Host "   • Retry the operation" -ForegroundColor Cyan
            Write-Host "   • Check network connectivity" -ForegroundColor Cyan
            Write-Host "   • Increase timeout settings if available" -ForegroundColor Cyan
        }
    }

    Write-Host ""
}

function New-ErrorReport
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Exception]$Exception,

        [Parameter()]
        [string]$Context,

        [Parameter()]
        [hashtable]$AdditionalInfo
    )

    $errorInfo = Get-ErrorCategory -Exception $Exception

    $report = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
        Context = $Context
        ErrorCategory = $errorInfo.Category
        Severity = $errorInfo.Severity
        UserMessage = $errorInfo.UserMessage
        TechnicalMessage = $errorInfo.TechnicalMessage
        ExceptionType = $Exception.GetType().Name
        StackTrace = if ($Exception.StackTrace) { $Exception.StackTrace } else { "Not available" }
        Environment = @{
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            OSVersion = [System.Environment]::OSVersion.ToString()
            MachineName = $env:COMPUTERNAME
            UserName = $env:USERNAME
        }
    }

    if ($AdditionalInfo)
{
        $report.AdditionalInfo = $AdditionalInfo
    }

    return $report
}

function Save-ErrorReport
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ErrorReport
    )

    try
{
        $logDir = Join-Path $env:LOCALAPPDATA "AutoCert\ErrorReports"
        if (-not (Test-Path $logDir))
                                                                     {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }

        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $reportPath = Join-Path $logDir "error_report_$timestamp.json"

        $ErrorReport | ConvertTo-Json -Depth 10 | Set-Content $reportPath -Encoding UTF8

        Write-Log "Error report saved to: $reportPath" -Level 'Info'
        return $reportPath
    } catch
     {
        Write-Log "Failed to save error report: $($_.Exception.Message)" -Level 'Warning'
        return $null
    }
}

function Test-CommonIssue
{
    [CmdletBinding()]
    param()

    $issues = @()

    # Check PowerShell execution policy
    $executionPolicy = Get-ExecutionPolicy
    if ($executionPolicy -eq 'Restricted')
                                          {
        $issues += @{
            Issue = 'PowerShell Execution Policy is Restricted'
            Impact = 'Scripts cannot run'
            Solution = 'Run: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser'
            Severity = 'High'
        }
    }

    # Check internet connectivity
    try
                                 {
        # Use well-known public DNS servers for connectivity testing
        $testDnsServer = 'dns.google'
        $testConnection = Test-NetConnection -ComputerName $testDnsServer -Port 53 -InformationLevel Quiet -WarningAction SilentlyContinue
        if (-not $testConnection)
                                                                                                                                          {
            $issues += @{
                Issue = 'No internet connectivity detected'
                Impact = 'Certificate operations will fail'
                Solution = 'Check network connection and DNS settings'
                Severity = 'High'
            }
        }
    } catch
     {
        $issues += @{
            Issue = 'Cannot test internet connectivity'
            Impact = 'Unknown network status'
            Solution = 'Manually verify internet connection'
            Severity = 'Medium'
        }
    }

    # Check disk space
    try
                      {
        $systemDrive = [System.Environment]::SystemDirectory.Substring(0, 2)
        $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$systemDrive'"
        $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)

        if ($freeSpaceGB -lt 1)
{
            $issues += @{
                Issue = "Low disk space on system drive ($freeSpaceGB GB free)"
                Impact = 'File operations may fail'
                Solution = 'Free up disk space'
                Severity = 'High'
            }
        }
    } catch
     {
        # Ignore disk space check if it fails
    }

    return $issues
}

# Export functions for dot-sourcing
# Note: Functions are available globally due to dot-sourcing architecture
