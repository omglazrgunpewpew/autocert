# Test-FunctionScope2.ps1
# Test function scoping in detail

Write-Host "Testing Function Scoping Issues..." -ForegroundColor Cyan

# Clear any existing functions to start fresh
Get-Command | Where-Object { $_.Name -eq 'Show-Menu' } | ForEach-Object {
    Remove-Item -Path "Function:\$($_.Name)" -Force -ErrorAction SilentlyContinue
}

Write-Host "Step 1: Direct load of MainMenu.ps1" -ForegroundColor Yellow
. ".\UI\MainMenu.ps1"

if (Get-Command Show-Menu -ErrorAction SilentlyContinue)
{
    Write-Host "✓ Show-Menu available after direct load" -ForegroundColor Green
    $funcBefore = Get-Command Show-Menu
    Write-Host "  Scope: Global" -ForegroundColor Gray
} else
{
    Write-Host "✗ Show-Menu NOT available after direct load" -ForegroundColor Red
}

Write-Host "`nStep 2: Test if loading Initialize-ScriptModule affects the function" -ForegroundColor Yellow

# Setup environment
$script:ScriptVersion = "2.0.0"
$script:LoadedModules = @()
$script:InitializationErrors = @()
$env:AUTOCERT_TESTING_MODE = $true

# Load SystemInitialization
. ".\Core\SystemInitialization.ps1"

# Test if Show-Menu is still there
if (Get-Command Show-Menu -ErrorAction SilentlyContinue)
{
    Write-Host "✓ Show-Menu still available after loading SystemInitialization" -ForegroundColor Green
} else
{
    Write-Host "✗ Show-Menu disappeared after loading SystemInitialization" -ForegroundColor Red
}

Write-Host "`nStep 3: Load just a few critical modules manually" -ForegroundColor Yellow

# Load only the essential modules
$essentialModules = @(
    "Core\Logging.ps1",
    "Core\Helpers.ps1",
    "Utilities\ErrorHandling.ps1"
)

foreach ($module in $essentialModules)
{
    if (Test-Path $module)
    {
        Write-Host "Loading $module..." -ForegroundColor Gray
        . ".\$module"
    }
}

# Test again
if (Get-Command Show-Menu -ErrorAction SilentlyContinue)
{
    Write-Host "✓ Show-Menu still there after loading essential modules" -ForegroundColor Green
} else
{
    Write-Host "✗ Show-Menu disappeared after loading essential modules" -ForegroundColor Red
}

Write-Host "`nStep 4: Test loading UI module through the normal path" -ForegroundColor Yellow

# Load UI modules the way SystemInitialization does
$uiModulePath = "$PSScriptRoot\UI\MainMenu.ps1"
if (Test-Path $uiModulePath)
{
    Write-Host "Loading UI module from: $uiModulePath" -ForegroundColor Gray
    . $uiModulePath
}

if (Get-Command Show-Menu -ErrorAction SilentlyContinue)
{
    Write-Host "✓ Show-Menu available after normal path load" -ForegroundColor Green
    $funcAfter = Get-Command Show-Menu

    # Compare with the original function
    if ($funcBefore -and $funcAfter)
    {
        if ($funcBefore.Definition -eq $funcAfter.Definition)
        {
            Write-Host "  Function definition unchanged" -ForegroundColor Green
        } else
        {
            Write-Host "  Function definition changed!" -ForegroundColor Yellow
        }
    }
} else
{
    Write-Host "✗ Show-Menu NOT available after normal path load" -ForegroundColor Red
}

Write-Host "`nStep 5: Check all function names in Function: drive" -ForegroundColor Yellow
$allFunctions = Get-ChildItem Function: | Where-Object { $_.Name -like "*Menu*" -or $_.Name -like "*Show*" }
if ($allFunctions)
{
    Write-Host "Functions with Menu/Show in name:" -ForegroundColor Gray
    $allFunctions | ForEach-Object {
        Write-Host "  $($_.Name)" -ForegroundColor Gray
    }
} else
{
    Write-Host "No functions with Menu/Show found in Function: drive" -ForegroundColor Red
}

Write-Host "`nStep 6: Try to call Show-Menu to see what happens" -ForegroundColor Yellow
try
{
    # Don't actually call it, just test if we can get help
    Get-Help Show-Menu -ErrorAction Stop | Out-Null
    Write-Host "✓ Show-Menu help available - function is properly defined" -ForegroundColor Green
} catch
{
    Write-Host "✗ Show-Menu help failed: $($_.Exception.Message)" -ForegroundColor Red
}


