# Core/ErrorHandlingHelpers.ps1
<#
    .SYNOPSIS
        Additional error handling helper functions for Core modules

    .DESCRIPTION
        Provides specialized error handling functions that are used throughout
        the Core modules to ensure consistent error handling and recovery.

    .NOTES
        These functions supplement the main ErrorHandling.ps1 module with
        Core-specific error handling utilities.
#>

function Write-CoreModuleError
{
    <#
    .SYNOPSIS
        Standardized error logging for Core modules

    .DESCRIPTION
        Provides consistent error logging for Core modules with proper
        categorization and context information.

    .PARAMETER Message
        The error message to log

    .PARAMETER ModuleName
        Name of the Core module that generated the error

    .PARAMETER Exception
        The exception object if available

    .PARAMETER Category
        Error category (e.g., 'Initialization', 'Configuration', 'Network')

    .PARAMETER Severity
        Error severity level ('Low', 'Medium', 'High', 'Critical')

    .EXAMPLE
        Write-CoreModuleError -Message "Failed to load configuration" -ModuleName "ConfigurationManager" -Category "Configuration" -Severity "High"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [string]$ModuleName,

        [System.Exception]$Exception,

        [ValidateSet('Initialization', 'Configuration', 'Network', 'Security', 'FileSystem', 'Certificate', 'Validation')]
        [string]$Category = 'General',

        [ValidateSet('Low', 'Medium', 'High', 'Critical')]
        [string]$Severity = 'Medium'
    )

    $errorDetails = @{
        Timestamp = Get-Date
        Module = $ModuleName
        Category = $Category
        Severity = $Severity
        Message = $Message
        Exception = if ($Exception) { $Exception.GetType().Name } else { $null }
        ExceptionMessage = if ($Exception) { $Exception.Message } else { $null }
        StackTrace = if ($Exception) { $Exception.StackTrace } else { $null }
    }

    # Format the error message
    $formattedMessage = "[$ModuleName/$Category/$Severity] $Message"
    if ($Exception)
    {
        $formattedMessage += " | Exception: $($Exception.GetType().Name) - $($Exception.Message)"
    }

    # Log based on severity
    switch ($Severity)
    {
        'Critical'
        {
            Write-Log $formattedMessage -Level 'Error'
            Write-Error $formattedMessage
        }
        'High'
        {
            Write-Log $formattedMessage -Level 'Error'
        }
        'Medium'
        {
            Write-Log $formattedMessage -Level 'Warning'
        }
        'Low'
        {
            Write-Log $formattedMessage -Level 'Info'
        }
    }

    # Store error details for troubleshooting
    if (-not $script:CoreModuleErrors)
    {
        $script:CoreModuleErrors = @()
    }
    $script:CoreModuleErrors += $errorDetails

    # Limit error history to last 100 entries
    if ($script:CoreModuleErrors.Count -gt 100)
    {
        $script:CoreModuleErrors = $script:CoreModuleErrors | Select-Object -Last 100
    }
}

function Invoke-CoreModuleOperation
{
    <#
    .SYNOPSIS
        Execute operations with standardized error handling for Core modules

    .DESCRIPTION
        Wraps Core module operations with consistent error handling, retry logic,
        and error reporting. Provides fallback mechanisms and proper error categorization.

    .PARAMETER Operation
        The scriptblock operation to execute

    .PARAMETER OperationName
        Human-readable name for the operation

    .PARAMETER ModuleName
        Name of the Core module performing the operation

    .PARAMETER Category
        Category of the operation for error classification

    .PARAMETER MaxRetries
        Maximum number of retry attempts (default: 3)

    .PARAMETER RetryDelay
        Delay between retries in seconds (default: 2)

    .PARAMETER FallbackOperation
        Optional fallback operation to execute if main operation fails

    .PARAMETER SuppressErrors
        Suppress error output (still logs errors)

    .EXAMPLE
        Invoke-CoreModuleOperation -Operation { Get-Content "config.json" } -OperationName "Load Configuration" -ModuleName "ConfigurationManager"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Operation,

        [Parameter(Mandatory)]
        [string]$OperationName,

        [Parameter(Mandatory)]
        [string]$ModuleName,

        [ValidateSet('Initialization', 'Configuration', 'Network', 'Security', 'FileSystem', 'Certificate', 'Validation')]
        [string]$Category = 'General',

        [int]$MaxRetries = 3,

        [int]$RetryDelay = 2,

        [scriptblock]$FallbackOperation,

        [switch]$SuppressErrors
    )

    $attempt = 1
    $lastException = $null

    Write-Log "Starting operation '$OperationName' in module '$ModuleName'" -Level 'Debug'

    while ($attempt -le $MaxRetries)
    {
        try
        {
            Write-Log "Attempt $attempt of $MaxRetries for operation '$OperationName'" -Level 'Debug'

            $result = & $Operation

            Write-Log "Operation '$OperationName' completed successfully on attempt $attempt" -Level 'Info'
            return $result
        } catch
        {
            $lastException = $_
            $errorMessage = "Operation '$OperationName' failed on attempt $attempt`: $($_.Exception.Message)"

            if ($attempt -eq $MaxRetries)
            {
                Write-CoreModuleError -Message $errorMessage -ModuleName $ModuleName -Exception $_.Exception -Category $Category -Severity 'High'
                break
            } else
            {
                Write-CoreModuleError -Message $errorMessage -ModuleName $ModuleName -Exception $_.Exception -Category $Category -Severity 'Medium'

                Write-Log "Retrying operation '$OperationName' in $RetryDelay seconds..." -Level 'Info'
                Start-Sleep -Seconds $RetryDelay
                $attempt++
            }
        }
    }

    # Try fallback operation if available
    if ($FallbackOperation)
    {
        try
        {
            Write-Log "Executing fallback operation for '$OperationName'" -Level 'Warning'
            $fallbackResult = & $FallbackOperation
            Write-Log "Fallback operation for '$OperationName' completed successfully" -Level 'Info'
            return $fallbackResult
        } catch
        {
            $fallbackError = "Fallback operation for '$OperationName' also failed: $($_.Exception.Message)"
            Write-CoreModuleError -Message $fallbackError -ModuleName $ModuleName -Exception $_.Exception -Category $Category -Severity 'Critical'
        }
    }

    # Final failure
    $finalError = "All attempts failed for operation '$OperationName' in module '$ModuleName'"
    Write-CoreModuleError -Message $finalError -ModuleName $ModuleName -Exception $lastException.Exception -Category $Category -Severity 'Critical'

    if (-not $SuppressErrors)
    {
        throw $lastException
    }

    return $null
}

function Test-CoreModuleHealth
{
    <#
    .SYNOPSIS
        Perform health check on Core module error states

    .DESCRIPTION
        Analyzes recent Core module errors to identify patterns and health issues.
        Provides recommendations for addressing systematic problems.

    .OUTPUTS
        System.Collections.Hashtable
        Health report with error analysis and recommendations
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param()

    $healthReport = @{
        OverallHealth = 'Good'
        TotalErrors = 0
        CriticalErrors = 0
        RecentErrors = @()
        ErrorsByModule = @{}
        ErrorsByCategory = @{}
        Recommendations = @()
        AnalysisTime = Get-Date
    }

    if (-not $script:CoreModuleErrors -or $script:CoreModuleErrors.Count -eq 0)
    {
        $healthReport.OverallHealth = 'Excellent'
        return $healthReport
    }

    $healthReport.TotalErrors = $script:CoreModuleErrors.Count

    # Analyze recent errors (last 24 hours)
    $recentThreshold = (Get-Date).AddHours(-24)
    $recentErrors = $script:CoreModuleErrors | Where-Object { $_.Timestamp -gt $recentThreshold }
    $healthReport.RecentErrors = $recentErrors

    # Count critical errors
    $healthReport.CriticalErrors = ($script:CoreModuleErrors | Where-Object { $_.Severity -eq 'Critical' }).Count

    # Group errors by module
    $errorsByModule = $script:CoreModuleErrors | Group-Object Module
    foreach ($group in $errorsByModule)
    {
        $healthReport.ErrorsByModule[$group.Name] = @{
            Count = $group.Count
            CriticalCount = ($group.Group | Where-Object { $_.Severity -eq 'Critical' }).Count
            HighCount = ($group.Group | Where-Object { $_.Severity -eq 'High' }).Count
        }
    }

    # Group errors by category
    $errorsByCategory = $script:CoreModuleErrors | Group-Object Category
    foreach ($group in $errorsByCategory)
    {
        $healthReport.ErrorsByCategory[$group.Name] = $group.Count
    }

    # Generate recommendations
    if ($healthReport.CriticalErrors -gt 0)
    {
        $healthReport.Recommendations += "Address $($healthReport.CriticalErrors) critical errors immediately"
        $healthReport.OverallHealth = 'Poor'
    }

    if ($recentErrors.Count -gt 10)
    {
        $healthReport.Recommendations += "High error rate detected: $($recentErrors.Count) errors in last 24 hours"
        if ($healthReport.OverallHealth -eq 'Good') { $healthReport.OverallHealth = 'Fair' }
    }

    # Check for problematic modules
    foreach ($module in $healthReport.ErrorsByModule.Keys)
    {
        $moduleErrors = $healthReport.ErrorsByModule[$module]
        if ($moduleErrors.CriticalCount -gt 0)
        {
            $healthReport.Recommendations += "Module '$module' has $($moduleErrors.CriticalCount) critical errors - requires immediate attention"
        }
        if ($moduleErrors.Count -gt 5)
        {
            $healthReport.Recommendations += "Module '$module' has high error count ($($moduleErrors.Count)) - review implementation"
        }
    }

    # Check for problematic categories
    foreach ($category in $healthReport.ErrorsByCategory.Keys)
    {
        $categoryCount = $healthReport.ErrorsByCategory[$category]
        if ($categoryCount -gt 8)
        {
            $healthReport.Recommendations += "Category '$category' has high error count ($categoryCount) - systematic issue likely"
        }
    }

    return $healthReport
}

function Get-CoreModuleErrorHistory
{
    <#
    .SYNOPSIS
        Retrieve Core module error history with optional filtering

    .DESCRIPTION
        Returns stored error history for Core modules with optional filtering
        by module, category, severity, or time range.

    .PARAMETER ModuleName
        Filter by specific module name

    .PARAMETER Category
        Filter by error category

    .PARAMETER Severity
        Filter by error severity

    .PARAMETER Hours
        Only return errors from the last N hours

    .EXAMPLE
        Get-CoreModuleErrorHistory -ModuleName "ConfigurationManager" -Severity "Critical"
    #>
    [CmdletBinding()]
    param(
        [string]$ModuleName,

        [ValidateSet('Initialization', 'Configuration', 'Network', 'Security', 'FileSystem', 'Certificate', 'Validation')]
        [string]$Category,

        [ValidateSet('Low', 'Medium', 'High', 'Critical')]
        [string]$Severity,

        [int]$Hours
    )

    if (-not $script:CoreModuleErrors)
    {
        return @()
    }

    $filteredErrors = $script:CoreModuleErrors

    if ($ModuleName)
    {
        $filteredErrors = $filteredErrors | Where-Object { $_.Module -eq $ModuleName }
    }

    if ($Category)
    {
        $filteredErrors = $filteredErrors | Where-Object { $_.Category -eq $Category }
    }

    if ($Severity)
    {
        $filteredErrors = $filteredErrors | Where-Object { $_.Severity -eq $Severity }
    }

    if ($Hours)
    {
        $threshold = (Get-Date).AddHours(-$Hours)
        $filteredErrors = $filteredErrors | Where-Object { $_.Timestamp -gt $threshold }
    }

    return $filteredErrors | Sort-Object Timestamp -Descending
}

function Clear-CoreModuleErrorHistory
{
    <#
    .SYNOPSIS
        Clear Core module error history

    .DESCRIPTION
        Clears stored error history for Core modules. Can clear all errors
        or filter by specific criteria.

    .PARAMETER ModuleName
        Clear errors only for specific module

    .PARAMETER OlderThanHours
        Clear errors older than specified hours

    .PARAMETER Confirm
        Confirm before clearing
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [string]$ModuleName,

        [int]$OlderThanHours
    )

    if (-not $script:CoreModuleErrors)
    {
        Write-Log "No Core module error history to clear" -Level 'Info'
        return
    }

    $beforeCount = $script:CoreModuleErrors.Count

    if ($ModuleName)
    {
        if ($PSCmdlet.ShouldProcess("Core module error history for $ModuleName", "Clear"))
        {
            $script:CoreModuleErrors = $script:CoreModuleErrors | Where-Object { $_.Module -ne $ModuleName }
            $afterCount = $script:CoreModuleErrors.Count
            Write-Log "Cleared $($beforeCount - $afterCount) errors for module '$ModuleName'" -Level 'Info'
        }
    } elseif ($OlderThanHours)
    {
        if ($PSCmdlet.ShouldProcess("Core module errors older than $OlderThanHours hours", "Clear"))
        {
            $threshold = (Get-Date).AddHours(-$OlderThanHours)
            $script:CoreModuleErrors = $script:CoreModuleErrors | Where-Object { $_.Timestamp -gt $threshold }
            $afterCount = $script:CoreModuleErrors.Count
            Write-Log "Cleared $($beforeCount - $afterCount) errors older than $OlderThanHours hours" -Level 'Info'
        }
    } else
    {
        if ($PSCmdlet.ShouldProcess("All Core module error history", "Clear"))
        {
            $script:CoreModuleErrors = @()
            Write-Log "Cleared all $beforeCount Core module errors" -Level 'Info'
        }
    }
}

# Initialize error tracking
$script:CoreModuleErrors = @()
