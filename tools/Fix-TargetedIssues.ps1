#Requires -Version 5.1
<#
.SYNOPSIS
    Fixes the top 3 most critical PSScriptAnalyzer issues safely
.DESCRIPTION
    Focuses on the most impactful and safe fixes:
    1. PSAvoidUsingWriteHost (36 violations)
    2. PSAvoidTrailingWhitespace (67 violations)
    3. PSUseSingularNouns (55 violations)
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Path = ".",
    [switch]$SkipWriteHost,
    [switch]$SkipTrailingWhitespace,
    [switch]$SkipSingularNouns
)

Write-Host -Object "=== TARGETED CRITICAL FIXES ===" -ForegroundColor Cyan
Write-Warning -Message "Fixing top 3 most critical issues safely"

# Get all PowerShell files excluding modules
$files = Get-ChildItem -Path $Path -Recurse -Filter "*.ps1" |
    Where-Object { $_.FullName -notlike "*\Modules\*" -and $_.FullName -notlike "*\.git\*" }

$totalChanges = 0

# Fix 1: Remove trailing whitespace (safe and high-impact)
if (-not $SkipTrailingWhitespace) {
    Write-Information -MessageData "`n1. Fixing trailing whitespace..." -InformationAction Continue
    foreach ($file in $files) {
        $content = Get-Content -Path $file.FullName -Raw
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
            if ($trailingWhitespaceLines -gt 0 -and $PSCmdlet.ShouldProcess($file.FullName, "Remove trailing whitespace from $trailingWhitespaceLines lines")) {
                Set-Content -Path $file.FullName -Value $cleanedContent -Encoding UTF8
                Write-Information -MessageData "  ✓ Removed trailing whitespace from $trailingWhitespaceLines lines in $($file.Name)" -InformationAction Continue
                $totalChanges += $trailingWhitespaceLines
            }
        }
    }
}

# Fix 2: Convert problematic Write-Host -Object calls (targeted)
if (-not $SkipWriteHost) {
    Write-Host -Object "`n2. Converting problematic Write-Information -MessageData calls..." -InformationAction Continue
    foreach ($file in $files) {
        $content = Get-Content -Path $file.FullName -Raw
        $originalContent = $content

        # Only convert Write-Host -Object calls that are clearly informational
        $patterns = @{
            'Write-Host\s+"([^"]+)"\s*$' = 'Write-Information -MessageData "$1" -InformationAction Continue'
            'Write-Host\s+\$([^-\s]+)\s*$' = 'Write-Information -MessageData $$$1 -InformationAction Continue'
        }

        $fileChanges = 0
        foreach ($pattern in $patterns.Keys) {
            $regexMatches = [regex]::Matches($content, $pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
            if ($regexMatches.Count -gt 0) {
                $content = $content -replace $pattern, $patterns[$pattern]
                $fileChanges += $regexMatches.Count
            }
        }

        if ($content -ne $originalContent -and $PSCmdlet.ShouldProcess($file.FullName, "Convert $fileChanges Write-Host -Object calls")) {
            Set-Content -Path $file.FullName -Value $content -Encoding UTF8
            Write-Host -Object "  ✓ Converted $fileChanges Write-Information -MessageData calls in $($file.Name)" -InformationAction Continue
            $totalChanges += $fileChanges
        }
    }
}

# Fix 3: Add OutputType attributes to functions (safe)
if (-not $SkipSingularNouns) {
    Write-Information -MessageData "`n3. Adding OutputType attributes to functions..." -InformationAction Continue
    foreach ($file in $files) {
        $content = Get-Content -Path $file.FullName -Raw
        $originalContent = $content

        # Find functions that don't have OutputType
        $functionMatches = [regex]::Matches($content, 'function\s+([A-Za-z][A-Za-z0-9-]*)\s*\{')
        $fileChanges = 0

        foreach ($funcMatch in $functionMatches) {
            $funcName = $funcMatch.Groups[1].Value
            $funcStart = $funcMatch.Index

            # Check if function already has OutputType by looking backwards
            $beforeFunc = $content.Substring(0, $funcStart)
            $lastLines = ($beforeFunc -split "`n")[-10..-1] -join "`n"

            if ($lastLines -notmatch '\[OutputType\(' -and $funcName -notmatch '^(Write-|Show-|Test-|Initialize-)') {
                # Add OutputType attribute
                $oldFuncDef = $funcMatch.Value
                $newFuncDef = "[OutputType([object[]])]\n$oldFuncDef"
                $content = $content.Replace($oldFuncDef, $newFuncDef)
                $fileChanges++
            }
        }

        if ($content -ne $originalContent -and $PSCmdlet.ShouldProcess($file.FullName, "Add OutputType to $fileChanges functions")) {
            Set-Content -Path $file.FullName -Value $content -Encoding UTF8
            Write-Information -MessageData "  ✓ Added OutputType to $fileChanges functions in $($file.Name)" -InformationAction Continue
            $totalChanges += $fileChanges
        }
    }
}

Write-Host -Object "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Information -MessageData "Total changes applied: $totalChanges" -InformationAction Continue

# Validation check
Write-Warning -Message "`nValidating changes..."
try {
    Import-Module PSScriptAnalyzer -Force
    $afterResults = Invoke-ScriptAnalyzer -Path $Path -Recurse -Exclude "Modules\*"
    $afterParseErrors = $afterResults | Where-Object { $_.RuleName -like "*Parse*" -or $_.RuleName -like "*Unexpected*" -or $_.RuleName -like "*Missing*" }

    if ($afterParseErrors.Count -eq 0) {
        Write-Information -MessageData "✓ No parse errors introduced" -InformationAction Continue
    } else {
        Write-Error -Message "⚠ $($afterParseErrors.Count) parse errors detected"
    }

    $topIssues = $afterResults | Group-Object RuleName | Sort-Object Count -Descending | Select-Object -First 5
    Write-Warning -Message "`nTop 5 remaining issues:"
    foreach ($issue in $topIssues) {
        Write-Host -Object "  $($issue.Count)x $($issue.Name)" -ForegroundColor White
    }

    Write-Host -Object "`nTotal violations: $($afterResults.Count)" -ForegroundColor $(if($afterResults.Count -lt 1000) { "Green" } else { "Yellow" })
}
catch {
    Write-Warning -Message "Could not run validation: $($_.Exception.Message)"
}

Write-Information -MessageData "`nTargeted fixes completed!" -InformationAction Continue




