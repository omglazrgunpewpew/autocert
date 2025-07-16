#!/usr/bin/env pwsh
<#
    .SYNOPSIS
        Removes trailing whitespace from PowerShell files

    .DESCRIPTION
        Scans PowerShell files and removes trailing whitespace from all lines

    .PARAMETER WhatIf
        Shows what files would be modified without making changes
#>

[CmdletBinding()]
param(
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

try {
    $rootPath = Split-Path -Parent $PSScriptRoot

    # Get all PowerShell files except in Modules directory
    $filesToProcess = Get-ChildItem -Path $rootPath -Recurse -Include "*.ps1", "*.psm1", "*.psd1" |
    Where-Object { $_.FullName -notlike "*\Modules\*" } |
    Select-Object -ExpandProperty FullName

    Write-Information -MessageData " -InformationAction Continue
    Write-Information -MessageData " -InformationAction Continue=========================================" -InformationAction Continue

    if ($WhatIf) {
        Write-Warning -Message "
    }

    $filesModified = 0
    $totalLinesFixed = 0

    foreach ($file in $filesToProcess) {
        $content = Get-Content -Path $file
        $linesFixed = 0

        # Check for trailing whitespace
        for ($i = 0; $i -lt $content.Count; $i++) {
            if ($content[$i] -match '\s+$') {
                $linesFixed++
            }
        }

        if ($linesFixed -gt 0) {
            if ($WhatIf) {
                Write-Warning -Message "Would fix $linesFixed lines in: $file"
            }
            else {
                # Remove trailing whitespace
                $cleanContent = $content -replace '\s+$', ''
                Set-Content -Path $file -Value $cleanContent -Encoding UTF8
                Write-Information -MessageData " -InformationAction Continue
            }

            $filesModified++
            $totalLinesFixed += $linesFixed
        }
    }

    Write-Information -MessageData " -InformationAction Continue`nSummary:" -InformationAction Continue
    Write-Information -MessageData " -InformationAction Continue
    Write-Information -MessageData " -InformationAction ContinueFiles with trailing whitespace: $filesModified" -InformationAction Continue
    Write-Information -MessageData " -InformationAction Continue

    if ($WhatIf -and $filesModified -gt 0) {
        Write-Warning -Message "
    }

}
catch {
    Write-Error -Message "Failed to clean trailing whitespace: $($_.Exception.Message)"
    exit 1
}





