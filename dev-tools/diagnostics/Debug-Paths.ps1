# Debug-Paths.ps1
# Debug the path resolution in Initialize-ScriptModule

Write-Host "Debugging Path Resolution..." -ForegroundColor Cyan

# Simulate the path construction from SystemInitialization.ps1
$PSScriptRoot_Simulated = "$PSScriptRoot\Core"  # This is where SystemInitialization.ps1 is located

Write-Host "Simulated PSScriptRoot (from Core folder): $PSScriptRoot_Simulated" -ForegroundColor Yellow

# Test the paths that are constructed in Initialize-ScriptModule
$testPaths = @(
    @{ Path = "$PSScriptRoot_Simulated\..\UI\MainMenu.ps1"; Name = "MainMenu" },
    @{ Path = "$PSScriptRoot_Simulated\..\Public\Register-Certificate.ps1"; Name = "RegisterCertificate" },
    @{ Path = "$PSScriptRoot_Simulated\..\Public\Install-Certificate.ps1"; Name = "InstallCertificate" }
)

foreach ($pathInfo in $testPaths)
{
    $resolvedPath = Resolve-Path $pathInfo.Path -ErrorAction SilentlyContinue
    if ($resolvedPath)
    {
        Write-Host "✓ $($pathInfo.Name): $($pathInfo.Path) → $resolvedPath" -ForegroundColor Green

        # Test if the file contains the expected function
        $content = Get-Content $resolvedPath -Raw
        $expectedFunction = switch ($pathInfo.Name)
        {
            "MainMenu" { "function Show-Menu" }
            "RegisterCertificate" { "function Register-Certificate" }
            "InstallCertificate" { "function Install-Certificate" }
        }

        if ($content -match [regex]::Escape($expectedFunction))
        {
            Write-Host "  ✓ Contains expected function: $expectedFunction" -ForegroundColor Green
        } else
        {
            Write-Host "  ✗ Does NOT contain expected function: $expectedFunction" -ForegroundColor Red
        }
    } else
    {
        Write-Host "✗ $($pathInfo.Name): $($pathInfo.Path) → NOT FOUND" -ForegroundColor Red
    }
}

# Now test loading one of these paths exactly as Initialize-ScriptModule does
Write-Host "`nTesting dot-sourcing with exact paths..." -ForegroundColor Cyan

$testPath = "$PSScriptRoot_Simulated\..\UI\MainMenu.ps1"
Write-Host "Testing path: $testPath" -ForegroundColor Yellow

# Check if Show-Menu exists before loading
$beforeLoad = Get-Command Show-Menu -ErrorAction SilentlyContinue
Write-Host "Show-Menu before load: $(if ($beforeLoad) { 'EXISTS' } else { 'NOT FOUND' })" -ForegroundColor Gray

try
{
    if (Test-Path $testPath)
    {
        Write-Host "Loading with: . `"$testPath`"" -ForegroundColor Yellow
        . $testPath

        # Check if Show-Menu exists after loading
        $afterLoad = Get-Command Show-Menu -ErrorAction SilentlyContinue
        if ($afterLoad)
        {
            Write-Host "✓ Show-Menu available after loading with exact path" -ForegroundColor Green
        } else
        {
            Write-Host "✗ Show-Menu NOT available after loading with exact path" -ForegroundColor Red
        }
    } else
    {
        Write-Host "✗ Path does not exist: $testPath" -ForegroundColor Red
    }
} catch
{
    Write-Host "✗ Error loading: $($_.Exception.Message)" -ForegroundColor Red
}

# Compare with working approach
Write-Host "`nTesting with working approach..." -ForegroundColor Cyan
$workingPath = ".\UI\MainMenu.ps1"
Write-Host "Testing path: $workingPath" -ForegroundColor Yellow

# Clear Show-Menu first
if (Get-Command Show-Menu -ErrorAction SilentlyContinue)
{
    Remove-Item Function:\Show-Menu -Force
}

try
{
    . $workingPath
    if (Get-Command Show-Menu -ErrorAction SilentlyContinue)
    {
        Write-Host "✓ Show-Menu available with working path" -ForegroundColor Green
    } else
    {
        Write-Host "✗ Show-Menu NOT available with working path" -ForegroundColor Red
    }
} catch
{
    Write-Host "✗ Error with working path: $($_.Exception.Message)" -ForegroundColor Red
}


