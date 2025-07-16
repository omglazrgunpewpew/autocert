#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Comprehensive code quality fix tool for AutoCert project
.DESCRIPTION
    This script applies automated formatting, fixes PSScriptAnalyzer issues,
    and enforces AutoCert style guide standards using custom rules.
.PARAMETER Paths
    Array of file or directory paths to process
.PARAMETER WhatIf
    Show what would be changed without making actual changes
.PARAMETER FixFormatting
    Apply automated PowerShell formatting (braces, indentation, whitespace)
.PARAMETER FixMarketingLanguage
    Fix marketing language issues flagged by custom rules
.PARAMETER Severity
    Minimum severity level to address (Error, Warning, Information)
#>

[CmdletBinding()]
param(
    [string[]]$Paths = @('Main.ps1', 'Core', 'Functions', 'Utilities', 'UI'),
    [switch]$WhatIf,
    [switch]$FixFormatting = $true,
    [switch]$FixMarketingLanguage = $true,
    [ValidateSet('Error', 'Warning', 'Information')]
    [string]$Severity = 'Warning'
)

# Import required modules
try {
    Import-Module PSScriptAnalyzer -Force -ErrorAction Stop
}
catch {
    Write-Error -Message "
    exit 1
}

# Custom formatting settings
$FormattingSettings = @{
    IncludeRules = @(
        'PSPlaceOpenBrace',
        'PSUseConsistentWhitespace',
        'PSUseConsistentIndentation',
        'PSAlignAssignmentStatement'
    )
    Rules        = @{
        PSPlaceOpenBrace           = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSUseConsistentWhitespace  = @{
            Enable          = $true
            CheckInnerBrace = $true
            CheckOpenBrace  = $true
            CheckOpenParen  = $true
            CheckOperator   = $true
            CheckPipe       = $true
            CheckSeparator  = $true
            CheckParameter  = $false
        }
        PSUseConsistentIndentation = @{
            Enable              = $true
            IndentationSize     = 4
            PipelineIndentation = 'IncreaseIndentationAfterEveryPipeline'
            Kind                = 'space'
        }
        PSAlignAssignmentStatement = @{
            Enable         = $true
            CheckHashtable = $true
        }
    }
}

[OutputType([object[]])]\n    function Invoke-PowerShellFormatter {
    param(
        [string]$Content,
        [hashtable]$Settings
    )

    try {
        # Use Invoke-Formatter if available (PowerShell 7+)
        if (Get-Command Invoke-Formatter -ErrorAction SilentlyContinue) {
            return Invoke-Formatter -ScriptDefinition $Content -Settings $Settings
        }

        # Fallback: Basic formatting for PowerShell 5.x
        Write-Warning -Message "

        # Fix opening braces - ensure they're on the same line
        $Content = $Content -replace '(\w+)\s*\r?\n\s*\{', '$1 {'
        $Content = $Content -replace '(\))\s*\r?\n\s*\{', '$1 {'
        $Content = $Content -replace '(else)\s*\r?\n\s*\{', '$1 {'
        $Content = $Content -replace '(elseif.*?)\s*\r?\n\s*\{', '$1 {'
        $Content = $Content -replace '(catch.*?)\s*\r?\n\s*\{', '$1 {'
        $Content = $Content -replace '(finally)\s*\r?\n\s*\{', '$1 {'

        # Ensure space before opening brace
        $Content = $Content -replace '(\w)\{', '$1 {'
        $Content = $Content -replace '\)\{', ') {'

        # Basic whitespace cleanup
        $Content = $Content -replace '[ \t]+(\r?\n)', '$1'
        $Content = $Content -replace '[ \t]+$', ''

        return $Content

    }
    catch {
        Write-Warning -Message "Formatting failed: $($_.Exception.Message)"
        return $Content
    }
}

[OutputType([object[]])]\n    function Fix-MarketingLanguage {
    param(
        [string]$Content,
        [string]$FilePath
    )

    # Marketing words to replace with neutral alternatives
    $Replacements = @{
        'successfully' = ''
        'complete'     = 'finished'
    }

    $originalContent = $Content

    foreach ($word in $Replacements.Keys) {
        $replacement = $Replacements[$word]

        # Replace in strings, being careful about context (case-insensitive)
        if ($replacement -eq '') {
            # Remove "successfully" adverb (case-insensitive)
            $Content = $Content -replace "(?i)\b$word\b\.?\s*", ''
            $Content = $Content -replace "(?i)\s+$word\b", ''
        }
        else {
            # Replace with alternative (case-insensitive, preserve case)
            $Content = $Content -replace "(?i)\b$word\b", $replacement
        }
    }

    if ($Content -ne $originalContent) {
        Write-Warning -Message "
    }

    return $Content
}

[OutputType([object[]])]\n    function Repair-PowerShellFile {
    param(
        [string]$FilePath,
        [switch]$WhatIf,
        [switch]$FixFormatting,
        [switch]$FixMarketingLanguage
    )

    Write-Information -MessageData " -InformationAction Continue

    try {
        # Read the file content
        $content = Get-Content $FilePath -Raw -ErrorAction Stop

        if (-not $content) {
            Write-Warning -Message "
            return
        }

        $originalContent = $content
        $changesMade = @()

        # Apply PowerShell formatting
        if ($FixFormatting) {
            $formattedContent = Invoke-PowerShellFormatter -Content $content -Settings $FormattingSettings
            if ($formattedContent -and $formattedContent -ne $content) {
                $content = $formattedContent
                $changesMade += "Applied PowerShell formatting"
            }
        }

        # Fix marketing language
        if ($FixMarketingLanguage) {
            $content = Fix-MarketingLanguage -Content $content -FilePath $FilePath
            if ($content -ne $originalContent) {
                $changesMade += "Fixed marketing language"
            }
        }

        # Fix trailing whitespace (always apply)
        $content = $content -replace '[ \t]+(\r?\n)', '$1'
        $content = $content -replace '[ \t]+$', ''

        if ($content -ne $originalContent) {
            if ($WhatIf) {
                Write-Information -MessageData " -InformationAction Continue
                $changesMade | ForEach-Object { Write-Information -MessageData " -InformationAction Continue    • $_" -InformationAction Continue }
            }
            else {
                # Write back with UTF8-BOM encoding
                $utf8WithBom = New-Object System.Text.UTF8Encoding $true
                [System.IO.File]::WriteAllText((Resolve-Path $FilePath), $content, $utf8WithBom)

                Write-Information -MessageData " -InformationAction Continue
                $changesMade | ForEach-Object { Write-Information -MessageData " -InformationAction Continue    • $_" -InformationAction Continue }
            }
        }
        else {
            Write-Information -MessageData " -InformationAction Continue
        }

    }
    catch {
        Write-Error -Message " -InformationAction Continue
    }
}

Write-Information -MessageData " -InformationAction Continue
Write-Information -MessageData " -InformationAction Continue=======================================" -InformationAction Continue

if ($WhatIf) {
    Write-Warning -Message "
}

# Process each path
foreach ($path in $Paths) {
    if (Test-Path $path) {
        if ((Get-Item $path).PSIsContainer) {
            # Directory - process all .ps1 files
            Write-Information -MessageData " -InformationAction Continue
            Get-ChildItem -Path $path -Filter " -InformationAction Continue*.ps1" -Recurse | ForEach-Object {
                Repair-PowerShellFile -FilePath $_.FullName -WhatIf:$WhatIf -FixFormatting:$FixFormatting -FixMarketingLanguage:$FixMarketingLanguage
            }
        }
        else {
            # Single file
            Write-Information -MessageData " -InformationAction Continue
            Repair-PowerShellFile -FilePath $path -WhatIf:$WhatIf -FixFormatting:$FixFormatting -FixMarketingLanguage:$FixMarketingLanguage
        }
    }
    else {
        Write-Warning -Message "
    }
}

Write-Information -MessageData " -InformationAction Continue

# Run comprehensive PSScriptAnalyzer check to verify improvements
if (-not $WhatIf) {
    Write-Information -MessageData " -InformationAction Continue`nRunning PSScriptAnalyzer to verify improvements..." -InformationAction Continue

    $allIssues = @()
    foreach ($path in $Paths) {
        if (Test-Path $path) {
            try {
                $pathIssues = Invoke-ScriptAnalyzer -Path $path -Settings "tools\PSScriptAnalyzerSettings.psd1" -ErrorAction SilentlyContinue
                if ($pathIssues) {
                    $allIssues += $pathIssues
                }
            }
            catch {
                Write-Warning -Message "
            }
        }
    }

    # Categorize results
    $errors = $allIssues | Where-Object { $_.Severity -eq 'Error' }
    $warnings = $allIssues | Where-Object { $_.Severity -eq 'Warning' }
    $information = $allIssues | Where-Object { $_.Severity -eq 'Information' }

    Write-Information -MessageData " -InformationAction Continue
    Write-Information -MessageData " -InformationAction Continue  Errors: $($errors.Count)" -InformationAction Continue else { 'Red' })
    Write-Information -MessageData " -InformationAction Continue elseif ($warnings.Count -lt 10) { 'Yellow' } else { 'Red' })
    Write-Information -MessageData " -InformationAction Continue  Information: $($information.Count)" -InformationAction Continue

    # Show remaining critical issues
    $criticalIssues = $allIssues | Where-Object {
        $_.Severity -eq 'Error' -or
        ($_.Severity -eq 'Warning' -and $_.RuleName -in @('PSUseShouldProcessForStateChangingFunctions', 'PSAvoidUsingPlainTextForPassword'))
    }

    if ($criticalIssues) {
        Write-Error -Message "
        $criticalIssues | Select-Object -First 10 | ForEach-Object {
            Write-Error -Message "  $($_.ScriptName):$($_.Line) - $($_.RuleName): $($_.Message)"
        }

        if ($criticalIssues.Count -gt 10) {
            Write-Error -Message "
        }
    }
    else {
        Write-Information -MessageData " -InformationAction Continue
    }

    # Show summary of most common remaining issues
    if ($warnings.Count -gt 0) {
        Write-Warning -Message "
        $warnings | Group-Object RuleName | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object {
            Write-Warning -Message "  $($_.Name): $($_.Count) occurrences"
        }
    }
}





