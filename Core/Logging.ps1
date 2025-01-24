<#
    .SYNOPSIS
        Logging utilities: writes to console and to a log file.
#>

# Path to the log file
$script:LogFile = Join-Path -Path $env:LOCALAPPDATA -ChildPath "Posh-ACME\certificate_script.log"

function Write-Log {
    param (
        [string]$Message,
        [string]$Level = 'Info'
    )
    $timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    "$timestamp [$Level] $Message" | Out-File -FilePath $script:LogFile -Append
}
