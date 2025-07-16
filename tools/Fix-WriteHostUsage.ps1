#!/usr/bin/env pwsh
<#
    .SYNOPSIS
        Fixes Write-Host -Object "([^"]+)"\s+-ForegroundColor\s+Red'                                                                          = 'Write-Error -Message "'
    'Write-Host\s+"([^"]+)"\s+-ForegroundColor\s+DarkRed'                                                                      = 'Write-Error -Message "'

    # Warning patterns (yellow color)
    'Write-Host\s+"([^"]+)"\s+-ForegroundColor\s+Yellow'                                                                       = 'Write-Warning -Message "'
    'Write-Host\s+"([^"]+)"\s+-ForegroundColor\s+DarkYellow'                                                                   = 'Write-Warning -Message "'

    # Information patterns (most other colors)
    'Write-Host\s+"([^"]+)"\s+-ForegroundColor\s+(Green|Cyan|Blue|Magenta|White|Gray|DarkGreen|DarkCyan|DarkBlue|DarkMagenta)' = 'Write-Information -MessageData " -InformationAction Continue'

    # Dynamic color expressions - convert to Write-Information -MessageData since most are status messages
    'Write-Host\s+" -InformationAction Continue([^"]+)"\s+-ForegroundColor\s+\$\([^}]+\}'                                                                  = 'Write-Information -MessageData " -InformationAction Continue'
    'Write-Host\s+" -InformationAction Continue([^"]+)"\s+-ForegroundColor\s+\$\([^)]+\)\s*\)\s*\)'                                                        = 'Write-Information -MessageData " -InformationAction Continue'
    'Write-Host\s+" -InformationAction Continue([^"]+)"\s+-ForegroundColor\s+\$\([^)]+\)'                                                                  = 'Write-Information -MessageData " -InformationAction Continue'

    # Simple Write-Host -Object " -InformationAction Continue([^"]+)"(?!\s+-ForegroundColor)'                                                                            = 'Write-Output -InputObject "'

    # Menu and status displays that should remain as Write-Host -Object "(=+|─+|\*+)"'                                                                                               = 'Write-Output -InputObject "'  # Keep decorative lines
    'Write-Host\s+"(\s*[0-9]+\)|\s*[A-Z]\)|\s*•)"'                                                                             = 'Write-Output -InputObject "'  # Keep menu items
}

# Function to process a single file
[OutputType([object[]])]\n    function Update-WriteHostUsage {
    param(
        [string]$FilePath,
        [switch]$WhatIf
    )

    if (-not (Test-Path $FilePath)) {
        Write-Warning -Message "
        return 0
    }

    $content = Get-Content -Path $FilePath -Raw
    if (-not $content) {
        Write-Warning -Message "File is empty or could not be read: $FilePath"
        return 0
    }

    $changesMade = 0
    $modifiedContent = $content

    # Apply each pattern in order
    foreach ($pattern in $WriteHostPatterns.Keys) {
        $replacement = $WriteHostPatterns[$pattern]

        try {
            # Find all matches first
            $regex = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $matches = $regex.Matches($modifiedContent)

            if ($matches.Count -gt 0) {
                foreach ($match in $matches) {
                    $oldText = $match.Value
                    $newText = $regex.Replace($oldText, $replacement)

                    if ($WhatIf) {
                        Write-Information -MessageData " -InformationAction Continue
                        Write-Error -Message " -InformationAction Continue
                        Write-Information -MessageData " -InformationAction Continue
                    }
                    else {
                        # Use simple string replacement for safety
                        $modifiedContent = $modifiedContent.Replace($oldText, $newText)
                        $changesMade++
                    }
                }
            }
        }
        catch {
            Write-Warning -Message "
            continue
        }
    }

    # Write changes back to file if not in WhatIf mode
    if (-not $WhatIf -and $changesMade -gt 0) {
        try {
            Set-Content -Path $FilePath -Value $modifiedContent -Encoding UTF8
            Write-Information -MessageData " -InformationAction Continue
        }
        catch {
            Write-Error -Message " -InformationAction Continue
            return 0
        }
    }

    return $changesMade
}

# Main execution
try {
    $rootPath = Split-Path -Parent $PSScriptRoot

    # Determine files to process
    if ($TargetFiles) {
        $filesToProcess = $TargetFiles | ForEach-Object {
            if (Test-Path $_) { $_ } else { Join-Path $rootPath $_ }
        }
    }
    else {
        # Get all PowerShell files except in Modules directory (third-party code)
        $filesToProcess = Get-ChildItem -Path $rootPath -Recurse -Include "*.ps1" |
        Where-Object { $_.FullName -notlike "*\Modules\*" } |
        Select-Object -ExpandProperty FullName
    }

    Write-Information -MessageData " -InformationAction Continue
    Write-Information -MessageData " -InformationAction Continue=================================" -InformationAction Continue

    if ($WhatIf) {
        Write-Warning -Message "
    }

    $totalChanges = 0
    $filesProcessed = 0

    foreach ($file in $filesToProcess) {
        $changes = Update-WriteHostUsage -FilePath $file -WhatIf:$WhatIf
        if ($changes -gt 0) {
            $totalChanges += $changes
            $filesProcessed++
        }
    }

    Write-Information -MessageData " -InformationAction Continue
    Write-Information -MessageData " -InformationAction ContinueFiles processed: $filesProcessed" -InformationAction Continue
    Write-Information -MessageData " -InformationAction Continue

    if ($WhatIf) {
        Write-Warning -Message "
    }

}
catch {
    Write-Error -Message "Failed to process Write-Host -Object replacements: $($_.Exception.Message)"
    exit 1
}





