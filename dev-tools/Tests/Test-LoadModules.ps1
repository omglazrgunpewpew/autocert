# Test-LoadModules.ps1
# Quick test to see if modules load correctly

# Set testing environment variables to prevent module updates
$env:AUTOCERT_TESTING_MODE = $true
$env:POSHACME_SKIP_UPGRADE_CHECK = $true

# Set up script path and minimal environment
$ErrorActionPreference = 'Stop'
$script:ScriptVersion = "2.0.0-TEST"
$script:LoadedModules = @()
$script:InitializationErrors = @()

try
{
    Write-Host "Testing AutoCert module loading..." -ForegroundColor Cyan

    # Test basic module loading
    . "$PSScriptRoot\Core\Logging.ps1"
    Write-Host "✓ Logging module loaded" -ForegroundColor Green

    . "$PSScriptRoot\Utilities\ErrorHandling.ps1"
    Write-Host "✓ ErrorHandling module loaded" -ForegroundColor Green

    . "$PSScriptRoot\Core\SystemInitialization.ps1"
    Write-Host "✓ SystemInitialization module loaded" -ForegroundColor Green

    # Test function availability
    if (Get-Command Write-AutoCertLog -ErrorAction SilentlyContinue)
    {
        Write-Host "✓ Write-AutoCertLog function available" -ForegroundColor Green
    } else
    {
        Write-Host "✗ Write-AutoCertLog function NOT available" -ForegroundColor Red
    }

    if (Get-Command Invoke-MenuOperation -ErrorAction SilentlyContinue)
    {
        Write-Host "✓ Invoke-MenuOperation function available" -ForegroundColor Green
    } else
    {
        Write-Host "✗ Invoke-MenuOperation function NOT available" -ForegroundColor Red
    }

    # Test the initialization function
    Write-Host "`nTesting full system initialization..." -ForegroundColor Cyan
    $result = Initialize-ScriptModule -NonInteractive

    if ($result)
    {
        Write-Host "✓ System initialization completed successfully" -ForegroundColor Green
    } else
    {
        Write-Host "✗ System initialization failed" -ForegroundColor Red
    }

    # Test critical functions
    $criticalFunctions = @('Show-Menu', 'Show-CertificateManagementMenu', 'Show-Help')
    foreach ($func in $criticalFunctions)
    {
        if (Get-Command $func -ErrorAction SilentlyContinue)
        {
            Write-Host "✓ $func function available" -ForegroundColor Green
        } else
        {
            Write-Host "✗ $func function NOT available" -ForegroundColor Red
        }
    }

    Write-Host "`nModule loading test completed!" -ForegroundColor Cyan

} catch
{
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Location: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    exit 1
}


