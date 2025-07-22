# Debug-FunctionScope.ps1
# Debug function availability and scoping issues

Write-Host "Debugging function scoping issues..." -ForegroundColor Cyan

$env:AUTOCERT_TESTING_MODE = $true
$env:POSHACME_SKIP_UPGRADE_CHECK = $true

# Load modules one by one and check Show-Menu availability
Write-Host "Step 1: Load just the MainMenu.ps1 file" -ForegroundColor Yellow
. ".\UI\MainMenu.ps1"

if (Get-Command Show-Menu -ErrorAction SilentlyContinue)
{
    Write-Host "✓ Show-Menu available after loading MainMenu.ps1" -ForegroundColor Green
} else
{
    Write-Host "✗ Show-Menu NOT available after loading MainMenu.ps1" -ForegroundColor Red
}

Write-Host "`nStep 2: Check function definition" -ForegroundColor Yellow
$func = Get-Command Show-Menu -ErrorAction SilentlyContinue
if ($func)
{
    Write-Host "Function type: $($func.CommandType)" -ForegroundColor Gray
    Write-Host "Function module: $($func.Source)" -ForegroundColor Gray
    Write-Host "Function name: $($func.Name)" -ForegroundColor Gray

    # Try to call it with a test
    Write-Host "`nStep 3: Test calling Show-Menu function" -ForegroundColor Yellow
    try
    {
        # We can't actually call Show-Menu as it will start the interactive loop,
        # but we can check if it would work by testing its parameters
        $params = (Get-Command Show-Menu).Parameters
        if ($params)
        {
            Write-Host "✓ Show-Menu has parameters defined" -ForegroundColor Green
            $params.Keys | ForEach-Object {
                Write-Host "  Parameter: $_" -ForegroundColor Gray
            }
        } else
        {
            Write-Host "✓ Show-Menu has no parameters (which is correct)" -ForegroundColor Green
        }
    } catch
    {
        Write-Host "✗ Error testing Show-Menu: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nStep 4: Now test with full system initialization" -ForegroundColor Yellow

# Initialize script variables
$script:ScriptVersion = "2.0.0"
$script:ScriptName = "AutoCert Certificate Management System"
$script:StartTime = Get-Date
$script:LoadedModules = @()
$script:InitializationErrors = @()

# Load core modules
. ".\Core\SystemInitialization.ps1"
. ".\Core\Logging.ps1"
. ".\Core\Helpers.ps1"
. ".\Utilities\ErrorHandling.ps1"

# Run initialization
$result = Initialize-ScriptModule -NonInteractive

Write-Host "`nAfter full initialization:" -ForegroundColor Yellow
$func2 = Get-Command Show-Menu -ErrorAction SilentlyContinue
if ($func2)
{
    Write-Host "✓ Show-Menu available after full initialization" -ForegroundColor Green
    Write-Host "Function type: $($func2.CommandType)" -ForegroundColor Gray
    Write-Host "Function module: $($func2.Source)" -ForegroundColor Gray

    # Check if it's the same function or different
    if ($func.Definition -eq $func2.Definition)
    {
        Write-Host "✓ Function definition is the same" -ForegroundColor Green
    } else
    {
        Write-Host "⚠️ Function definition has changed!" -ForegroundColor Yellow
        Write-Host "Original length: $($func.Definition.Length)" -ForegroundColor Gray
        Write-Host "New length: $($func2.Definition.Length)" -ForegroundColor Gray
    }
} else
{
    Write-Host "✗ Show-Menu NOT available after full initialization" -ForegroundColor Red

    # Check what functions we DO have
    Write-Host "`nFunctions containing 'Menu':" -ForegroundColor Yellow
    Get-Command | Where-Object { $_.Name -like "*Menu*" } | ForEach-Object {
        Write-Host "  $($_.Name) (from $($_.Source))" -ForegroundColor Gray
    }
}

Write-Host "`nStep 5: Check all loaded functions by pattern" -ForegroundColor Yellow
$menuFunctions = Get-Command | Where-Object { $_.Name -match "Show|Menu|Help" } | Sort-Object Name
if ($menuFunctions)
{
    Write-Host "Functions matching Show/Menu/Help pattern:" -ForegroundColor Gray
    $menuFunctions | ForEach-Object {
        Write-Host "  $($_.Name) (Type: $($_.CommandType), Source: $($_.Source))" -ForegroundColor Gray
    }
} else
{
    Write-Host "No functions found matching Show/Menu/Help pattern" -ForegroundColor Red
}



