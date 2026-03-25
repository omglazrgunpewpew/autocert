# Core/Logging.ps1
<#
    .SYNOPSIS
        Logging utilities with filtering.
#>
# Set up the log file
$script:scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:LogFile = Join-Path -Path $env:LOCALAPPDATA -ChildPath "Posh-ACME\certificate_script.log"
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Debug')]
        [string]$Level = 'Info'
    )
    # Only log if the message is meaningful
    if ([string]::IsNullOrWhiteSpace($Message)) {
        return
    }
    # Filter out routine info messages
    if ($Level -eq 'Info') {
        $routinePatterns = @(
            'ACME server set to',
            'Certificate cache cleared',
            'User exited the script',
            'Selected certificate:',
            'Detecting DNS provider'
        )
        foreach ($pattern in $routinePatterns) {
            if ($Message -like "*$pattern*") {
                return
            }
        }
    }
    # Ensure log directory exists
    $logDir = Split-Path -Path $script:LogFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "$timestamp [$Level] $Message"
    try {
        $logEntry | Out-File -FilePath $script:LogFile -Append -Encoding UTF8
    }
    catch {
        # Fallback if log file is locked
        Write-Verbose "Failed to write to log file: $_"
    }
}

# Backward-compatible unified logging function expected by newer components
if (-not (Get-Command Write-AutoCertLog -ErrorAction SilentlyContinue)) {
    function Write-AutoCertLog {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)] [string]$Message,
            [ValidateSet('Debug', 'Info', 'Warning', 'Error', 'Success')] [string]$Level = 'Info'
        )
        Write-Log -Message $Message -Level $Level
    }
    Set-Alias -Name Write-LogMessage -Value Write-AutoCertLog -ErrorAction SilentlyContinue
}
