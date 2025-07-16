#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Auto-fix common PSScriptAnalyzer issues in AutoCert
.DESCRIPTION
    Automatically fixes common formatting and style issues that can be corrected programmatically
.EXAMPLE
    .\Fix-CommonIssues.ps1
    Automatically fix common code quality issues
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-StatusMessage {
    param(
        [string]$Message,
        [ValidateSet('Success', 'Warning', 'Error', 'Info', 'Header')]
        [string]$Type = 'Info'
    )
    
    $colors = @{
        Success = 'Green'
        Warning = 'Yellow'
        Error   = 'Red'
        Info    = 'Cyan'
        Header  = 'Magenta'
    }
    
    Write-Host $Message -ForegroundColor $colors[$Type]
}

# Change to project root
Set-Location $PSScriptRoot\..

Write-StatusMessage "AutoCert Code Auto-Fix" -Type Header
Write-StatusMessage "=======================" -Type Header

# Install required modules
if (-not (Get-Module PSScriptAnalyzer -ListAvailable)) {
    Write-StatusMessage "Installing PSScriptAnalyzer..." -Type Info
    Install-Module PSScriptAnalyzer -Force -Scope CurrentUser
}

# Get all PowerShell files
$psFiles = Get-ChildItem -Path . -Recurse -Include '*.ps1' -Exclude 'Test-*.ps1', '*.Tests.ps1' | 
Where-Object { $_.FullName -notmatch '\\\.git\\|\\Modules\\Posh-ACME\\' }

Write-StatusMessage "Found $($psFiles.Count) PowerShell files to process" -Type Info

foreach ($file in $psFiles) {
    Write-StatusMessage "Processing: $($file.FullName)" -Type Info
    
    try {
        # Read file content
        $content = Get-Content -Path $file.FullName -Raw
        $originalContent = $content
        
        # Fix trailing whitespace
        $content = $content -replace '\s+$', ''
        
        # Fix multiple blank lines (more than 2 consecutive)
        $content = $content -replace '(\r?\n){3,}', "`n`n"
        
        # Ensure file ends with newline
        if (-not $content.EndsWith("`n")) {
            $content += "`n"
        }
        
        # Save if changed
        if ($content -ne $originalContent) {
            Set-Content -Path $file.FullName -Value $content -NoNewline
            Write-StatusMessage "  ✅ Fixed formatting issues" -Type Success
        }
        else {
            Write-StatusMessage "  ℹ️ No changes needed" -Type Info
        }
    }
    catch {
        Write-StatusMessage "  ❌ Failed to process: $($_.Exception.Message)" -Type Error
    }
}

Write-StatusMessage "`nAuto-fix complete!" -Type Header
Write-StatusMessage "Run Test-CodeQuality.ps1 to verify the fixes." -Type Info
