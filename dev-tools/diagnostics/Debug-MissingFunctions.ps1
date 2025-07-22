# Debug-MissingFunctions.ps1
# Debug which specific functions are missing and why

Write-Host "Debugging Missing Functions..." -ForegroundColor Cyan

# Setup environment (minimal)
$script:ScriptVersion = "2.0.0"
$script:LoadedModules = @()
$script:InitializationErrors = @()
$env:AUTOCERT_TESTING_MODE = $true

# Load core components
. "$PSScriptRoot\Core\SystemInitialization.ps1"
. "$PSScriptRoot\Core\Logging.ps1"
. "$PSScriptRoot\Core\Helpers.ps1"
. "$PSScriptRoot\Utilities\ErrorHandling.ps1"

Write-Host "Running Initialize-ScriptModule..." -ForegroundColor Yellow
try
{
    $result = Initialize-ScriptModule -NonInteractive:$true
    Write-Host "Initialize-ScriptModule result: $result" -ForegroundColor Green
} catch
{
    Write-Host "Initialize-ScriptModule error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nChecking function availability by category..." -ForegroundColor Cyan

# Check UI functions
Write-Host "`nUI Functions:" -ForegroundColor Yellow
$uiFunctions = @('Show-Menu', 'Show-CertificateManagementMenu', 'Show-CredentialManagementMenu', 'Show-Help')
foreach ($func in $uiFunctions)
{
    if (Get-Command $func -ErrorAction SilentlyContinue)
    {
        Write-Host "  ✓ $func" -ForegroundColor Green
    } else
    {
        Write-Host "  ✗ $func" -ForegroundColor Red
    }
}

# Check Public functions
Write-Host "`nPublic Functions:" -ForegroundColor Yellow
$publicFunctions = @('Register-Certificate', 'Install-Certificate', 'Update-AllCertificates', 'Remove-Certificate', 'Revoke-Certificate', 'Set-AutomaticRenewal', 'Show-Options', 'Get-ExistingCertificates')
foreach ($func in $publicFunctions)
{
    if (Get-Command $func -ErrorAction SilentlyContinue)
    {
        Write-Host "  ✓ $func" -ForegroundColor Green
    } else
    {
        Write-Host "  ✗ $func" -ForegroundColor Red
    }
}

# Check Core functions
Write-Host "`nCore Functions:" -ForegroundColor Yellow
$coreFunctions = @('Write-AutoCertLog', 'Write-ProgressHelper', 'Test-SystemHealth', 'Invoke-MenuOperation')
foreach ($func in $coreFunctions)
{
    if (Get-Command $func -ErrorAction SilentlyContinue)
    {
        Write-Host "  ✓ $func" -ForegroundColor Green
    } else
    {
        Write-Host "  ✗ $func" -ForegroundColor Red
    }
}

# Check what modules were reported as loaded
Write-Host "`nLoaded modules according to script:" -ForegroundColor Cyan
if ($script:LoadedModules.Count -gt 0)
{
    $script:LoadedModules | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Gray
    }
} else
{
    Write-Host "  No modules recorded" -ForegroundColor Red
}

# Now let's manually check if the files exist and try loading them directly
Write-Host "`nManual function loading test:" -ForegroundColor Cyan

# Test UI functions by loading directly
Write-Host "Loading UI\MainMenu.ps1 directly..." -ForegroundColor Yellow
if (Test-Path "UI\MainMenu.ps1")
{
    . ".\UI\MainMenu.ps1"
    if (Get-Command Show-Menu -ErrorAction SilentlyContinue)
    {
        Write-Host "  ✓ Show-Menu available after direct load" -ForegroundColor Green
    } else
    {
        Write-Host "  ✗ Show-Menu still not available after direct load" -ForegroundColor Red
    }
} else
{
    Write-Host "  ✗ UI\MainMenu.ps1 not found" -ForegroundColor Red
}

# Test Public functions
Write-Host "Loading Public\Register-Certificate.ps1 directly..." -ForegroundColor Yellow
if (Test-Path "Public\Register-Certificate.ps1")
{
    . ".\Public\Register-Certificate.ps1"
    if (Get-Command Register-Certificate -ErrorAction SilentlyContinue)
    {
        Write-Host "  ✓ Register-Certificate available after direct load" -ForegroundColor Green
    } else
    {
        Write-Host "  ✗ Register-Certificate still not available after direct load" -ForegroundColor Red
    }
} else
{
    Write-Host "  ✗ Public\Register-Certificate.ps1 not found" -ForegroundColor Red
}

# Check if there are any errors in loading these files
Write-Host "`nTesting file loading with error reporting..." -ForegroundColor Yellow
$testFiles = @(
    "UI\MainMenu.ps1",
    "Public\Register-Certificate.ps1",
    "Public\Install-Certificate.ps1"
)

foreach ($file in $testFiles)
{
    if (Test-Path $file)
    {
        try
        {
            Write-Host "Loading $file..." -ForegroundColor Gray
            . ".\$file"
            Write-Host "  ✓ $file loaded without errors" -ForegroundColor Green
        } catch
        {
            Write-Host "  ✗ Error loading $file`: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else
    {
        Write-Host "  ✗ $file not found" -ForegroundColor Red
    }
}

# Final function availability check
Write-Host "`nFinal availability check:" -ForegroundColor Cyan
$allTestFunctions = @('Show-Menu', 'Register-Certificate', 'Install-Certificate')
foreach ($func in $allTestFunctions)
{
    if (Get-Command $func -ErrorAction SilentlyContinue)
    {
        Write-Host "  ✓ $func" -ForegroundColor Green
    } else
    {
        Write-Host "  ✗ $func" -ForegroundColor Red
    }
}




