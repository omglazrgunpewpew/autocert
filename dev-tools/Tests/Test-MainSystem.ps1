# Test-MainSystem.ps1
# Comprehensive test of the main AutoCert system

# Set testing environment variables
$env:AUTOCERT_TESTING_MODE = $true
$env:POSHACME_SKIP_UPGRADE_CHECK = $true

# Set up script metadata like Main.ps1
$script:ScriptVersion = "2.0.0-TEST"
$script:ScriptName = "AutoCert Certificate Management System"
$script:StartTime = Get-Date
$script:LoadedModules = @()
$script:InitializationErrors = @()

$ErrorActionPreference = 'Stop'

Write-Host "Testing complete AutoCert system loading..." -ForegroundColor Cyan

try
{
    # Load core system modules (like Main.ps1 does)
    Write-Host "Loading core system modules..." -ForegroundColor Yellow
    . "$PSScriptRoot\Core\SystemInitialization.ps1"
    . "$PSScriptRoot\Core\RenewalOperations.ps1"
    . "$PSScriptRoot\Core\SystemDiagnostics.ps1"
    . "$PSScriptRoot\Core\RenewalConfig.ps1"

    Write-Host "✓ Core system modules loaded" -ForegroundColor Green

    # Initialize the complete system
    Write-Host "Initializing complete system..." -ForegroundColor Yellow
    $moduleLoadSuccess = Initialize-ScriptModule -NonInteractive

    if ($moduleLoadSuccess)
    {
        Write-Host "✓ System initialization completed successfully" -ForegroundColor Green
    } else
    {
        Write-Host "✗ System initialization failed" -ForegroundColor Red
        exit 1
    }

    # Test critical functions
    Write-Host "`nTesting critical functions..." -ForegroundColor Yellow
    $criticalFunctions = @(
        'Register-Certificate', 'Install-Certificate', 'Write-AutoCertLog',
        'Show-Menu', 'Show-CertificateManagementMenu', 'Show-CredentialManagementMenu',
        'Show-Help', 'Test-SystemHealth', 'Invoke-MenuOperation'
    )

    $failedFunctions = @()
    foreach ($func in $criticalFunctions)
    {
        if (Get-Command $func -ErrorAction SilentlyContinue)
        {
            Write-Host "✓ $func function available" -ForegroundColor Green
        } else
        {
            Write-Host "✗ $func function NOT available" -ForegroundColor Red
            $failedFunctions += $func
        }
    }

    # Test configuration
    Write-Host "`nTesting system configuration..." -ForegroundColor Yellow
    $configValid = Test-SystemConfiguration
    if ($configValid)
    {
        Write-Host "✓ System configuration is valid" -ForegroundColor Green
    } else
    {
        Write-Host "✗ System configuration has issues" -ForegroundColor Red
    }

    # Summary
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "AUTOCERT SYSTEM TEST SUMMARY" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    Write-Host "Core modules loaded: ✓" -ForegroundColor Green
    Write-Host "System initialization: $(if ($moduleLoadSuccess) { '✓' } else { '✗' })" -ForegroundColor $(if ($moduleLoadSuccess) { 'Green' } else { 'Red' })
    Write-Host "Configuration valid: $(if ($configValid) { '✓' } else { '✗' })" -ForegroundColor $(if ($configValid) { 'Green' } else { 'Red' })
    Write-Host "Critical functions: $($criticalFunctions.Count - $failedFunctions.Count)/$($criticalFunctions.Count) available" -ForegroundColor $(if ($failedFunctions.Count -eq 0) { 'Green' } else { 'Yellow' })

    if ($failedFunctions.Count -gt 0)
    {
        Write-Host "`nMissing functions:" -ForegroundColor Red
        foreach ($func in $failedFunctions)
        {
            Write-Host "  - $func" -ForegroundColor Red
        }
    }

    Write-Host "`nLoaded modules: $($script:LoadedModules.Count)" -ForegroundColor White
    if ($script:InitializationErrors.Count -gt 0)
    {
        Write-Host "Initialization errors: $($script:InitializationErrors.Count)" -ForegroundColor Yellow
    }

    if ($failedFunctions.Count -eq 0 -and $configValid -and $moduleLoadSuccess)
    {
        Write-Host "`n🎉 ALL TESTS PASSED! AutoCert system is ready for use." -ForegroundColor Green
        exit 0
    } else
    {
        Write-Host "`n⚠️  Some issues detected. System may have limited functionality." -ForegroundColor Yellow
        exit 1
    }

} catch
{
    Write-Host "`nFATAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Location: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    exit 1
}


