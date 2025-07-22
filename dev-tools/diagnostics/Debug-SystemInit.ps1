# Debug-SystemInit.ps1
# Debug the SystemInitialization module loading

Write-Host "Testing SystemInitialization module loading..." -ForegroundColor Cyan

$env:AUTOCERT_TESTING_MODE = $true
$env:POSHACME_SKIP_UPGRADE_CHECK = $true

# Initialize script variables
$script:ScriptVersion = "2.0.0"
$script:ScriptName = "AutoCert Certificate Management System"
$script:StartTime = Get-Date
$script:LoadedModules = @()
$script:InitializationErrors = @()

# Load minimal required modules first
try
{
    Write-Host "Loading SystemInitialization..." -ForegroundColor Yellow
    . ".\Core\SystemInitialization.ps1"
    Write-Host "✓ SystemInitialization loaded" -ForegroundColor Green
} catch
{
    Write-Host "✗ Failed to load SystemInitialization: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Load some helper modules that Initialize-ScriptModule might need
$requiredModules = @(
    "Core\Logging.ps1",
    "Core\Helpers.ps1",
    "Utilities\ErrorHandling.ps1"
)

foreach ($module in $requiredModules)
{
    try
    {
        if (Test-Path $module)
        {
            Write-Host "Loading $module..." -ForegroundColor Yellow
            . ".\$module"
            Write-Host "✓ $module loaded" -ForegroundColor Green
        } else
        {
            Write-Host "✗ $module not found" -ForegroundColor Red
        }
    } catch
    {
        Write-Host "✗ Error loading $module`: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Now test Initialize-ScriptModule
Write-Host "`nTesting Initialize-ScriptModule..." -ForegroundColor Cyan
try
{
    $result = Initialize-ScriptModule -NonInteractive
    if ($result)
    {
        Write-Host "✓ Initialize-ScriptModule succeeded" -ForegroundColor Green
    } else
    {
        Write-Host "✗ Initialize-ScriptModule returned false" -ForegroundColor Red
    }
} catch
{
    Write-Host "✗ Initialize-ScriptModule failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Check if Show-Menu is available after system initialization
Write-Host "`nChecking Show-Menu availability..." -ForegroundColor Cyan
if (Get-Command Show-Menu -ErrorAction SilentlyContinue)
{
    Write-Host "✓ Show-Menu function is available" -ForegroundColor Green
} else
{
    Write-Host "✗ Show-Menu function NOT available" -ForegroundColor Red
}

# Show loaded modules
Write-Host "`nLoaded modules:" -ForegroundColor Cyan
if ($script:LoadedModules)
{
    $script:LoadedModules | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Gray
    }
} else
{
    Write-Host "  No modules recorded" -ForegroundColor Red
}

# Show any initialization errors
if ($script:InitializationErrors)
{
    Write-Host "`nInitialization errors:" -ForegroundColor Red
    $script:InitializationErrors | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Red
    }
}


