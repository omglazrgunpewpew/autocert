#Requires -Version 5.1
<#
.SYNOPSIS
    Fixes critical PSScriptAnalyzer issues across all PowerShell files
.DESCRIPTION
    Systematically addresses the most critical and high-frequency issues found by PSScriptAnalyzer
.PARAMETER Path
    Path to scan and fix (defaults to current directory)
.PARAMETER WhatIf
    Shows what would be changed without making changes
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Path = "."
)

Write-Host -Object "=== CRITICAL ISSUES FIXER ===" -ForegroundColor Cyan
Write-Host -Object "Starting systematic fixes for high-priority PSScriptAnalyzer issues" -ForegroundColor Yellow
Write-Host -Object "

# Get all PowerShell files excluding modules
$files = Get-ChildItem -Path $Path -Recurse -Filter "*.ps1" |
    Where-Object { $_.FullName -notlike "*\Modules\*" -and $_.FullName -notlike "*\.git\*" }

$totalFiles = $files.Count
$processedFiles = 0
$totalChanges = 0

Write-Host -Object "Found $totalFiles PowerShell files to process" -ForegroundColor Green
Write-Host -Object "

foreach ($file in $files) {
    $processedFiles++
    Write-Progress -Activity "Fixing Critical Issues" -Status "Processing $($file.Name)" -PercentComplete (($processedFiles / $totalFiles) * 100)

    $content = Get-Content -Path $file.FullName -Raw
    $originalContent = $content
    $fileChanges = 0

    Write-Host -Object "Processing: $($file.Name)" -ForegroundColor Yellow

    # Fix 1: Convert Write-Host -Object "([^"]+)"\s+-ForegroundColor\s+(\w+)')
    if ($writeHostMatches.Count -gt 0) {
        Write-Host -Object "  • Fixed $($writeHostMatches.Count) Write-Host -Object " -ForegroundColor Green
        foreach ($match in $writeHostMatches) {
            $oldPattern = $match.Value
            $text = $match.Groups[1].Value
            $color = $match.Groups[2].Value
            $newPattern = "Write-Host -Object `"$text`" -ForegroundColor $color"
            $content = $content -replace [regex]::Escape($oldPattern), $newPattern
            $fileChanges++
        }
    }

    # Fix 2: Convert simple Write-Host -Object "([^"]+)"(?!\s+-)')
    if ($simpleWriteHostMatches.Count -gt 0) {
        Write-Host -Object "  • Converting $($simpleWriteHostMatches.Count) simple Write-Host -Object " -ForegroundColor Green
        foreach ($match in $simpleWriteHostMatches) {
            $oldPattern = $match.Value
            $text = $match.Groups[1].Value
            $newPattern = "Write-Information -MessageData `"$text`" -InformationAction Continue"
            $content = $content -replace [regex]::Escape($oldPattern), $newPattern
            $fileChanges++
        }
    }

    # Fix 3: Fix Write-Output -InputObject "([^"]+)"\s+-ForegroundColor\s+(\w+)')
    if ($writeOutputMatches.Count -gt 0) {
        Write-Host -Object "  • Fixed $($writeOutputMatches.Count) Write-Output -InputObject " -ForegroundColor Green
        foreach ($match in $writeOutputMatches) {
            $oldPattern = $match.Value
            $text = $match.Groups[1].Value
            $color = $match.Groups[2].Value
            $newPattern = "Write-Host -Object `"$text`" -ForegroundColor $color"
            $content = $content -replace [regex]::Escape($oldPattern), $newPattern
            $fileChanges++
        }
    }

    # Fix 4: Fix simple positional parameters for common cmdlets
    $positionalFixes = @{
        'Write-Host\s+([^-][^"]*)"([^"]+)"' = 'Write-Host -Object "$2"'
        'Write-Output\s+([^-][^"]*)"([^"]+)"' = 'Write-Output -InputObject "$2"'
        'Write-Warning\s+([^-][^"]*)"([^"]+)"' = 'Write-Warning -Message "$2"'
        'Write-Error\s+([^-][^"]*)"([^"]+)"' = 'Write-Error -Message "$2"'
        'Write-Information\s+([^-][^"]*)"([^"]+)"' = 'Write-Information -MessageData "$2" -InformationAction Continue'
    }

    foreach ($pattern in $positionalFixes.Keys) {
        $regexMatches = [regex]::Matches($content, $pattern)
        if ($regexMatches.Count -gt 0) {
            $content = $content -replace $pattern, $positionalFixes[$pattern]
            Write-Host -Object "  • Fixed $($regexMatches.Count) positional parameters for pattern" -ForegroundColor Green
            $fileChanges += $regexMatches.Count
        }
    }

    # Fix 5: Add [OutputType] attributes for functions that need them
    $functionMatches = [regex]::Matches($content, 'function\s+([^{\s]+)\s*{')
    foreach ($funcMatch in $functionMatches) {
        $funcName = $funcMatch.Groups[1].Value
        # Check if function already has OutputType
        $hasOutputType = $content -match "\[OutputType\([^\]]+\)\]\s*function\s+$([regex]::Escape($funcName))"
        if (-not $hasOutputType -and $funcName -notmatch '^(Show-|Test-|Write-|Initialize-)') {
            # Add generic OutputType for functions that likely return objects
            $oldFuncDef = $funcMatch.Value
            $newFuncDef = "[OutputType([object[]])]\n    $oldFuncDef"
            $content = $content -replace [regex]::Escape($oldFuncDef), $newFuncDef
            Write-Host -Object "  • Added OutputType attribute to function: $funcName" -ForegroundColor Green
            $fileChanges++
        }
    }

    # Fix 6: Remove trailing whitespace
    $lines = $content -split "`r?`n"
    $cleanedLines = $lines | ForEach-Object { $_.TrimEnd() }
    $cleanedContent = $cleanedLines -join "`n"

    if ($cleanedContent -ne $content) {
        $trailingWhitespaceLines = 0
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -ne $cleanedLines[$i]) {
                $trailingWhitespaceLines++
            }
        }
        if ($trailingWhitespaceLines -gt 0) {
            Write-Host -Object "  • Removed trailing whitespace from $trailingWhitespaceLines lines" -ForegroundColor Green
            $content = $cleanedContent
            $fileChanges += $trailingWhitespaceLines
        }
    }

    # Write changes if any were made
    if ($content -ne $originalContent) {
        if ($PSCmdlet.ShouldProcess($file.FullName, "Apply $fileChanges fixes")) {
            Set-Content -Path $file.FullName -Value $content -Encoding UTF8
            Write-Host -Object "  ✓ Applied $fileChanges fixes to $($file.Name)" -ForegroundColor Green
            $totalChanges += $fileChanges
        }
        else {
            Write-Host -Object "  ? Would apply $fileChanges fixes to $($file.Name)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host -Object "  • No changes needed for $($file.Name)" -ForegroundColor Gray
    }

    Write-Host -Object "
}

Write-Progress -Activity "Fixing Critical Issues" -Completed

Write-Host -Object "=== SUMMARY ===" -ForegroundColor Cyan
Write-Host -Object "Files processed: $processedFiles" -ForegroundColor Green
Write-Host -Object "Total changes applied: $totalChanges" -ForegroundColor Green
Write-Host -Object "

if (-not $WhatIfPreference) {
    Write-Host -Object "Running PSScriptAnalyzer to check improvements..." -ForegroundColor Yellow
    try {
        Import-Module PSScriptAnalyzer -Force
        $afterResults = Invoke-ScriptAnalyzer -Path $Path -Recurse -Exclude "Modules\*"
        $topIssues = $afterResults | Group-Object RuleName | Sort-Object Count -Descending | Select-Object -First 5

        Write-Host -Object "Top 5 remaining issues:" -ForegroundColor Yellow
        foreach ($issue in $topIssues) {
            Write-Host -Object "  $($issue.Count)x $($issue.Name)" -ForegroundColor White
        }
        Write-Host -Object "
        Write-Host -Object "Total remaining violations: $($afterResults.Count)" -ForegroundColor $(if($afterResults.Count -lt 500) { "Green" } else { "Yellow" })
    }
    catch {
        Write-Warning -Message "
    }
}

Write-Host -Object "Critical issues fix completed!" -ForegroundColor Green



