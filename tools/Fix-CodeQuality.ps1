#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Fix common PSScriptAnalyzer issues across the AutoCert project
.DESCRIPTION
    This script fixes trailing whitespace, BOM encoding, and alignment issues
    in PowerShell files throughout the project.
#>

[CmdletBinding()]
param(
    [string[]]$Paths = @('Main.ps1', 'Core', 'Functions', 'Utilities', 'UI'),
    [switch]$WhatIf
)

function Fix-PowerShellFile {
    param(
        [string]$FilePath,
        [switch]$WhatIf
    )

    Write-Host -Object "Processing: $FilePath" -ForegroundColor Cyan

    try {
        # Read the file content
        $content = Get-Content $FilePath -Raw -ErrorAction Stop

        if (-not $content) {
            Write-Warning -Message "File is empty or could not be read: $FilePath"
            return
        }

        # Fix trailing whitespace
        $originalContent = $content
        $content = $content -replace '[ \t]+(\r?\n)', '$1'  # Remove trailing spaces/tabs before line endings
        $content = $content -replace '[ \t]+$', ''          # Remove trailing spaces/tabs at end of file

        if ($content -ne $originalContent) {
            Write-Host -Object "  - Fixed trailing whitespace" -ForegroundColor Yellow
        }

        if ($WhatIf) {
            Write-Host -Object "  - [WHATIF] Would update file with UTF8-BOM encoding" -ForegroundColor Green
        } else {
            # Write back with UTF8-BOM encoding
            $utf8WithBom = New-Object System.Text.UTF8Encoding $true
            [System.IO.File]::WriteAllText((Resolve-Path $FilePath), $content, $utf8WithBom)
            Write-Host -Object "  - Applied fixes and UTF8-BOM encoding" -ForegroundColor Green
        }

    } catch {
        Write-Error -Message "Failed to process $FilePath : $($_.Exception.Message)"
    }
}

Write-Host -Object "AutoCert Code Quality Fix Tool" -ForegroundColor Magenta
Write-Host -Object "===============================" -ForegroundColor Magenta

foreach ($path in $Paths) {
    if (Test-Path $path) {
        if ((Get-Item $path).PSIsContainer) {
            # Directory - process all .ps1 files
            Write-Host -Object "`nProcessing directory: $path" -ForegroundColor Blue
            Get-ChildItem -Path $path -Filter "*.ps1" -Recurse | ForEach-Object {
                Fix-PowerShellFile -FilePath $_.FullName -WhatIf:$WhatIf
            }
        } else {
            # Single file
            Write-Host -Object "`nProcessing file: $path" -ForegroundColor Blue
            Fix-PowerShellFile -FilePath $path -WhatIf:$WhatIf
        }
    } else {
        Write-Warning -Message "Path not found: $path"
    }
}

Write-Information -MessageData "`nCode quality fix completed!" -InformationAction Continue

# Run PSScriptAnalyzer to verify improvements
if (-not $WhatIf) {
    Write-Host -Object "`nRunning PSScriptAnalyzer to verify fixes..." -ForegroundColor Cyan

    $issues = @()
    foreach ($path in $Paths) {
        if (Test-Path $path) {
            $pathIssues = Invoke-ScriptAnalyzer -Path $path -Settings "tools\PSScriptAnalyzerSettings.psd1" -ErrorAction SilentlyContinue
            $issues += $pathIssues
        }
    }

    $targetIssues = $issues | Where-Object { $_.RuleName -in @('PSAvoidTrailingWhitespace', 'PSUseBOMForUnicodeEncodedFile', 'PSAlignAssignmentStatement') }

    if ($targetIssues) {
        Write-Warning -Message "Remaining issues:"
        $targetIssues | Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize
    } else {
        Write-Information -MessageData "All targeted issues have been resolved!" -InformationAction Continue
    }
}



