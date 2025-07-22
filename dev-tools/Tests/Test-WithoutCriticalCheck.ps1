# Test-WithoutCriticalCheck.ps1
# Test Initialize-ScriptModule without the critical function check

Write-Host "Testing without critical function verification..." -ForegroundColor Cyan

# Setup environment
$script:ScriptVersion = "2.0.0"
$script:ScriptName = "AutoCert Certificate Management System"
$script:StartTime = Get-Date
$ErrorActionPreference = 'Stop'
$script:LoadedModules = @()
$script:InitializationErrors = @()

$env:AUTOCERT_TESTING_MODE = $true
$env:POSHACME_SKIP_UPGRADE_CHECK = $true

# Load core modules
. "$PSScriptRoot\Core\SystemInitialization.ps1"
. "$PSScriptRoot\Core\Logging.ps1"
. "$PSScriptRoot\Core\Helpers.ps1"
. "$PSScriptRoot\Utilities\ErrorHandling.ps1"

Write-Host "Testing Initialize-ScriptModule with verbose output..." -ForegroundColor Yellow

# Temporarily modify the function to skip critical function check
# We'll do this by intercepting the exception
try
{
    $result = Initialize-ScriptModule -NonInteractive:$false -Verbose
    Write-Host "Initialize-ScriptModule completed normally with result: $result" -ForegroundColor Green
} catch
{
    if ($_.Exception.Message -like "*Critical function*")
    {
        Write-Host "Caught critical function error: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Let's check which functions are actually missing..." -ForegroundColor Yellow

        $criticalFunctions = @('Register-Certificate', 'Install-Certificate', 'Write-AutoCertLog', 'Show-Menu', 'Show-CertificateManagementMenu', 'Show-CredentialManagementMenu', 'Show-Help', 'Test-SystemHealth', 'Invoke-MenuOperation')
        foreach ($func in $criticalFunctions)
        {
            if (Get-Command $func -ErrorAction SilentlyContinue)
            {
                Write-Host "  ✓ $func is available" -ForegroundColor Green
            } else
            {
                Write-Host "  ✗ $func is NOT available" -ForegroundColor Red
            }
        }

        # Continue despite the error to see if functions are actually there
        Write-Host "`nIgnoring the critical function check error and continuing..." -ForegroundColor Yellow
        $result = $true
    } else
    {
        Write-Host "Different error: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

Write-Host "`nAfter Initialize-ScriptModule (result: $result):" -ForegroundColor Cyan

# Test Show-Menu availability
if (Get-Command Show-Menu -ErrorAction SilentlyContinue)
{
    Write-Host "✓ Show-Menu is available" -ForegroundColor Green
} else
{
    Write-Host "✗ Show-Menu is NOT available" -ForegroundColor Red
}

# Test other functions
$testFunctions = @('Write-AutoCertLog', 'Write-ProgressHelper', 'Invoke-MenuOperation', 'Register-Certificate')
foreach ($func in $testFunctions)
{
    if (Get-Command $func -ErrorAction SilentlyContinue)
    {
        Write-Host "✓ $func is available" -ForegroundColor Green
    } else
    {
        Write-Host "✗ $func is NOT available" -ForegroundColor Red
    }
}

Write-Host "`nLoaded modules count: $($script:LoadedModules.Count)" -ForegroundColor Cyan
if ($script:InitializationErrors.Count -gt 0)
{
    Write-Host "Initialization errors:" -ForegroundColor Red
    $script:InitializationErrors | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Red
    }
}


