#!/usr/bin/env pwsh
# Simple validation script

Write-Host "=== AutoCert Validation ===" -ForegroundColor Cyan

# Check PSScriptAnalyzer
Write-Host "`n1. Checking PSScriptAnalyzer..." -ForegroundColor Yellow
try {
    $allIssues = @()
    $pathsToCheck = @('./Core', './Functions', './Main.ps1', './Build-Validation.ps1')
    
    foreach ($path in $pathsToCheck) {
        if (Test-Path $path) {
            $issues = Invoke-ScriptAnalyzer -Path $path -Settings ./PSScriptAnalyzerSettings.psd1
            $allIssues += $issues
        }
    }
    
    if ($allIssues) {
        Write-Host "Found $($allIssues.Count) PSScriptAnalyzer issues" -ForegroundColor Yellow
        $errors = $allIssues | Where-Object Severity -eq 'Error'
        if ($errors) {
            Write-Host "❌ Found $($errors.Count) critical errors" -ForegroundColor Red
            $errors | Format-Table RuleName, ScriptName, Line, Message -AutoSize
        } else {
            Write-Host "✅ No critical errors found" -ForegroundColor Green
        }
    } else {
        Write-Host "✅ No PSScriptAnalyzer issues found" -ForegroundColor Green
    }
} catch {
    Write-Host "❌ PSScriptAnalyzer failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Check syntax of core files
Write-Host "`n2. Checking file syntax..." -ForegroundColor Yellow
$syntaxErrors = 0
Get-ChildItem -Path @('./Core', './Functions') -Filter '*.ps1' -Recurse | ForEach-Object {
    try {
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $_.FullName -Raw), [ref]$null)
        Write-Host "✅ $($_.Name)" -ForegroundColor Green
    } catch {
        Write-Host "❌ $($_.Name): $($_.Exception.Message)" -ForegroundColor Red
        $syntaxErrors++
    }
}

if ($syntaxErrors -eq 0) {
    Write-Host "`n✅ All files have valid syntax" -ForegroundColor Green
} else {
    Write-Host "`n❌ Found $syntaxErrors files with syntax errors" -ForegroundColor Red
}

Write-Host "`n=== Validation Complete ===" -ForegroundColor Cyan
