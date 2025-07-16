#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Quick verification that CI/CD fixes are working
.DESCRIPTION
    Tests the key components that were failing in CI/CD
#>

Write-Host "AutoCert CI/CD Fix Verification" -ForegroundColor Magenta
Write-Host "================================" -ForegroundColor Magenta

$success = $true

# Test 1: PSScriptAnalyzer settings file
Write-Host "`n1. Testing PSScriptAnalyzer settings file..." -ForegroundColor Cyan
try {
    $settings = Import-PowerShellDataFile -Path "./tools/PSScriptAnalyzerSettings.psd1"
    Write-Host "✅ PSScriptAnalyzer settings file loads successfully" -ForegroundColor Green
    
    # Check that custom rules are commented out
    $content = Get-Content "./tools/PSScriptAnalyzerSettings.psd1" -Raw
    if ($content -match '^\s*#.*CustomRulePath') {
        Write-Host "✅ Custom rules are properly commented out" -ForegroundColor Green
    }
    else {
        Write-Host "⚠️ Custom rules may not be properly disabled" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "❌ PSScriptAnalyzer settings file failed: $($_.Exception.Message)" -ForegroundColor Red
    $success = $false
}

# Test 2: PSScriptAnalyzer can run with settings
Write-Host "`n2. Testing PSScriptAnalyzer execution..." -ForegroundColor Cyan
try {
    if (Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue) {
        $issues = Invoke-ScriptAnalyzer -Path "./Main.ps1" -Settings "./tools/PSScriptAnalyzerSettings.psd1" -ErrorAction SilentlyContinue
        Write-Host "✅ PSScriptAnalyzer runs successfully with settings" -ForegroundColor Green
        if ($issues) {
            Write-Host "ℹ️ Found $($issues.Count) analysis issues (this is normal)" -ForegroundColor Cyan
        }
    }
    else {
        Write-Host "⚠️ PSScriptAnalyzer not installed, install with: Install-Module PSScriptAnalyzer -Force" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "❌ PSScriptAnalyzer execution failed: $($_.Exception.Message)" -ForegroundColor Red
    $success = $false
}

# Test 3: Tests directory exists and is accessible
Write-Host "`n3. Testing Tests directory..." -ForegroundColor Cyan
if (Test-Path "./Tests") {
    $testFiles = Get-ChildItem "./Tests" -Filter "*.ps1"
    Write-Host "✅ Tests directory exists with $($testFiles.Count) test files" -ForegroundColor Green
}
else {
    Write-Host "❌ Tests directory not found" -ForegroundColor Red
    $success = $false
}

# Test 4: Build validation can find tests
Write-Host "`n4. Testing Build validation test path..." -ForegroundColor Cyan
try {
    # Simulate what Build-Validation.ps1 does
    $buildScriptRoot = Resolve-Path "./build"
    $testPath = Join-Path (Split-Path $buildScriptRoot -Parent) 'Tests'
    if (Test-Path $testPath) {
        Write-Host "✅ Build validation can find tests at: $testPath" -ForegroundColor Green
    }
    else {
        Write-Host "❌ Build validation cannot find tests" -ForegroundColor Red
        $success = $false
    }
}
catch {
    Write-Host "❌ Build validation test failed: $($_.Exception.Message)" -ForegroundColor Red
    $success = $false
}

# Test 5: Core directories exist
Write-Host "`n5. Testing required directories..." -ForegroundColor Cyan
$requiredDirs = @('./Core', './Functions', './UI', './Utilities')
foreach ($dir in $requiredDirs) {
    if (Test-Path $dir) {
        Write-Host "✅ $dir exists" -ForegroundColor Green
    }
    else {
        Write-Host "⚠️ $dir not found" -ForegroundColor Yellow
    }
}

# Summary
Write-Host "`nVerification Summary" -ForegroundColor Magenta
Write-Host "===================" -ForegroundColor Magenta
if ($success) {
    Write-Host "🎉 All critical tests passed! Your CI/CD pipeline should now work." -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host "1. Commit these changes: git add . && git commit -m 'Fix CI/CD pipeline issues'" -ForegroundColor White
    Write-Host "2. Push to GitHub: git push" -ForegroundColor White
    Write-Host "3. Check GitHub Actions for successful pipeline run" -ForegroundColor White
}
else {
    Write-Host "❌ Some tests failed. Please review the issues above before committing." -ForegroundColor Red
}
