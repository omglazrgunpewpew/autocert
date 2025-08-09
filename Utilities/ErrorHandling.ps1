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
        Write-Host -Object "`nStarting $OperationName..." -ForegroundColor Cyan
        Write-ProgressHelper -Activity "Certificate Management" -Status "Preparing $OperationName..." -PercentComplete 0

        $startTime = Get-Date
        & $Operation
        $duration = (Get-Date) - $startTime

        Write-Information -MessageData "`n$OperationName completed in $($duration.TotalSeconds.ToString('F1')) seconds." -InformationAction Continue
        Write-Log "$OperationName completed" -Level 'Success'

    } catch {
        $errorMsg = "$OperationName failed: $($_.Exception.Message)"
        Write-Error -Message $errorMsg
        Write-Log $errorMsg -Level 'Error'

        # Error reporting
        Write-Error -Message "`nError Details:"
        Write-Error -Message "  Operation: $OperationName"
        Write-Error -Message "  Error: $($_.Exception.Message)"
        Write-Error -Message "  Location: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)"

        # Provide context-specific troubleshooting
        Write-Warning -Message "`nTroubleshooting suggestions:"
        switch ($OperationName) {
            "certificate registration" {
                Write-Warning -Message "• Check DNS provider credentials and permissions"
                Write-Warning -Message "• Verify domain ownership and DNS propagation"
                Write-Warning -Message "• Test internet connectivity to ACME servers"
            }
            "certificate installation" {
                Write-Warning -Message "• Ensure script is running as Administrator"
                Write-Warning -Message "• Check certificate store permissions"
                Write-Warning -Message "• Verify certificate file integrity"
            }
            default {
                Write-Warning -Message "• Check the log files for detailed error information"
                Write-Warning -Message "• Run system health check to identify configuration issues"
                Write-Warning -Message "• Verify all required modules are loaded correctly"
            }
        }

    } finally {
        Write-Progress -Activity "Certificate Management" -Completed
    }
}

# Export functions
# Export functions for dot-sourcing (commented out for script execution)
# Export-ModuleMember -Function Invoke-MenuOperation



