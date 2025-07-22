# Test-InteractiveMain.ps1
# Test the main script in a non-interactive way

$env:AUTOCERT_TESTING_MODE = $true
$env:POSHACME_SKIP_UPGRADE_CHECK = $true

Write-Host "Testing AutoCert Main Script (Non-Interactive)..." -ForegroundColor Cyan

# Create a test script that simulates menu interaction
$testScript = @'
# Simulate running Main.ps1 and checking if it initializes properly
try {
    $ErrorActionPreference = 'Stop'

    # Load Main.ps1 components manually to test initialization
    $script:ScriptVersion = "2.0.0"
    $script:ScriptName = "AutoCert Certificate Management System"
    $script:StartTime = Get-Date
    $script:LoadedModules = @()
    $script:InitializationErrors = @()

    # Test auto-detection of development environment
    $repoModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Modules\Posh-ACME'
    if ((Test-Path $repoModulePath) -and -not $env:AUTOCERT_TESTING_MODE) {
        Write-Host "Development environment detected: Setting testing mode to prevent module updates"
        $env:AUTOCERT_TESTING_MODE = $true
        $env:POSHACME_SKIP_UPGRADE_CHECK = $true
    }

    # Load core system modules
    . "$PSScriptRoot\Core\SystemInitialization.ps1"
    . "$PSScriptRoot\Core\RenewalOperations.ps1"
    . "$PSScriptRoot\Core\SystemDiagnostics.ps1"
    . "$PSScriptRoot\Core\RenewalConfig.ps1"

    Write-Host "✓ Core system modules loaded" -ForegroundColor Green

    # Initialize system
    $moduleLoadSuccess = Initialize-ScriptModule -NonInteractive

    if ($moduleLoadSuccess) {
        Write-Host "✓ System initialization completed successfully" -ForegroundColor Green

        # Test that all critical functions are available
        $criticalFunctions = @('Register-Certificate', 'Install-Certificate', 'Show-Menu',
                              'Show-CertificateManagementMenu', 'Show-CredentialManagementMenu',
                              'Show-Help', 'Test-SystemHealth', 'Invoke-MenuOperation')

        $allAvailable = $true
        foreach ($func in $criticalFunctions) {
            if (Get-Command $func -ErrorAction SilentlyContinue) {
                Write-Host "✓ $func available" -ForegroundColor Green
            } else {
                Write-Host "✗ $func NOT available" -ForegroundColor Red
                $allAvailable = $false
            }
        }

        if ($allAvailable) {
            Write-Host "`n🎉 AutoCert Main Script Test PASSED!" -ForegroundColor Green
            Write-Host "All critical functions are available and ready for interactive use." -ForegroundColor Green
            exit 0
        } else {
            Write-Host "`n⚠️ Some functions are missing." -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Host "✗ System initialization failed" -ForegroundColor Red
        exit 1
    }

} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
'@

# Execute the test
$testScript | Out-File -FilePath "$env:TEMP\AutoCert-MainTest.ps1" -Force
& "$env:TEMP\AutoCert-MainTest.ps1"
$exitCode = $LASTEXITCODE

# Clean up
Remove-Item "$env:TEMP\AutoCert-MainTest.ps1" -Force -ErrorAction SilentlyContinue

if ($exitCode -eq 0)
{
    Write-Host "`n✅ Main script test completed successfully!" -ForegroundColor Green
    Write-Host "The AutoCert system is ready for interactive use." -ForegroundColor Green
} else
{
    Write-Host "`n❌ Main script test failed." -ForegroundColor Red
}

exit $exitCode


