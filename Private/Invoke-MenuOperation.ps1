# Menu Operation Helper
# Part of AutoCert Certificate Management System
# Version: 1.0
# Date: July 21, 2025

<#
.SYNOPSIS
    Error handling wrapper for menu operations
.DESCRIPTION
    Provides standardized error handling and user feedback for menu operations
.NOTES
    Internal helper function for menu system
#>

function Invoke-MenuOperation
{
    <#
    .SYNOPSIS
        Executes a menu operation with error handling
    .DESCRIPTION
        Wraps menu operations with standardized error handling, logging, and user feedback
    .PARAMETER Operation
        Script block containing the operation to execute
    .PARAMETER OperationName
        Human-readable name of the operation for logging and error messages
    .EXAMPLE
        Invoke-MenuOperation -Operation { Register-Certificate } -OperationName "certificate registration"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Operation,

        [Parameter(Mandatory)]
        [string]$OperationName
    )

    try
    {
        Write-Information -MessageData "Starting $OperationName..." -InformationAction Continue

        # Log the operation start
        if (Get-Command Write-AutoCertLog -ErrorAction SilentlyContinue)
        {
            Write-AutoCertLog "Starting menu operation: $OperationName" -Level 'Info'
        }

        # Execute the operation
        & $Operation

        # Log successful completion
        if (Get-Command Write-AutoCertLog -ErrorAction SilentlyContinue)
        {
            Write-AutoCertLog "Completed menu operation: $OperationName" -Level 'Info'
        }

        Write-Information -MessageData "Operation completed successfully." -InformationAction Continue
    } catch
    {
        $errorMessage = "Failed to execute $OperationName`: $($_.Exception.Message)"

        # Log the error
        if (Get-Command Write-AutoCertLog -ErrorAction SilentlyContinue)
        {
            Write-AutoCertLog $errorMessage -Level 'Error'
        }

        Write-Error -Message $errorMessage
        Write-Warning -Message "Please check the logs for more details."
    } finally
    {
        # Ensure user can continue
        Write-Host -Object "`nPress Enter to continue..." -ForegroundColor Yellow
        $null = Read-Host
    }
}

# Export functions for dot-sourcing (commented out for script execution)
# Export-ModuleMember -Function Invoke-MenuOperation
