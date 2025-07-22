# Debug-ModuleLoadingDetailed.ps1
# Debug module loading with detailed error reporting

Write-Host "Detailed Module Loading Debug..." -ForegroundColor Cyan

# Set the exact environment
$script:ScriptVersion = "2.0.0"
$script:ScriptName = "AutoCert Certificate Management System"
$script:StartTime = Get-Date
$ErrorActionPreference = 'Stop'

# Auto-detect testing environment
$repoModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Modules\Posh-ACME'
if ((Test-Path $repoModulePath) -and -not $env:AUTOCERT_TESTING_MODE)
{
    $env:AUTOCERT_TESTING_MODE = $true
    $env:POSHACME_SKIP_UPGRADE_CHECK = $true
}

# Initialize script-wide variables
$script:LoadedModules = @()
$script:InitializationErrors = @()

# Load core system modules with error handling
try
{
    Write-Host "Loading SystemInitialization.ps1..." -ForegroundColor Yellow
    . "$PSScriptRoot\Core\SystemInitialization.ps1"
    Write-Host "✓ SystemInitialization.ps1 loaded" -ForegroundColor Green
} catch
{
    Write-Host "✗ Error loading SystemInitialization.ps1: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

try
{
    Write-Host "Loading RenewalOperations.ps1..." -ForegroundColor Yellow
    . "$PSScriptRoot\Core\RenewalOperations.ps1"
    Write-Host "✓ RenewalOperations.ps1 loaded" -ForegroundColor Green
} catch
{
    Write-Host "✗ Error loading RenewalOperations.ps1: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Warning: This may not be critical, continuing..." -ForegroundColor Yellow
}

try
{
    Write-Host "Loading SystemDiagnostics.ps1..." -ForegroundColor Yellow
    . "$PSScriptRoot\Core\SystemDiagnostics.ps1"
    Write-Host "✓ SystemDiagnostics.ps1 loaded" -ForegroundColor Green
} catch
{
    Write-Host "✗ Error loading SystemDiagnostics.ps1: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

try
{
    Write-Host "Loading RenewalConfig.ps1..." -ForegroundColor Yellow
    . "$PSScriptRoot\Core\RenewalConfig.ps1"
    Write-Host "✓ RenewalConfig.ps1 loaded" -ForegroundColor Green
} catch
{
    Write-Host "✗ Error loading RenewalConfig.ps1: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Now test Initialize-ScriptModule with detailed error reporting
Write-Host "`nTesting Initialize-ScriptModule with detailed errors..." -ForegroundColor Cyan

# Temporarily change error handling to capture details
$originalErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'

try
{
    $moduleLoadSuccess = Initialize-ScriptModule -NonInteractive:$false -Verbose

    Write-Host "`nInitialize-ScriptModule result: $moduleLoadSuccess" -ForegroundColor $(if ($moduleLoadSuccess) { 'Green' } else { 'Red' })

    # Check what modules were loaded
    Write-Host "`nLoaded modules count: $($script:LoadedModules.Count)" -ForegroundColor Cyan
    if ($script:LoadedModules.Count -gt 0)
    {
        Write-Host "Loaded modules:" -ForegroundColor Gray
        $script:LoadedModules | ForEach-Object {
            Write-Host "  $_" -ForegroundColor Gray
        }
    }

    # Check for initialization errors
    if ($script:InitializationErrors.Count -gt 0)
    {
        Write-Host "`nInitialization errors:" -ForegroundColor Red
        $script:InitializationErrors | ForEach-Object {
            Write-Host "  $_" -ForegroundColor Red
        }
    } else
    {
        Write-Host "`nNo initialization errors recorded" -ForegroundColor Green
    }

} catch
{
    Write-Host "✗ Initialize-ScriptModule threw exception: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Exception type: $($_.Exception.GetType().Name)" -ForegroundColor Red
    Write-Host "Stack trace: $($_.Exception.StackTrace)" -ForegroundColor Red
}

$ErrorActionPreference = $originalErrorActionPreference

# Now test specific function availability
Write-Host "`nTesting function availability..." -ForegroundColor Cyan

$criticalFunctions = @(
    'Write-ProgressHelper',
    'Write-AutoCertLog',
    'Show-Menu',
    'Register-Certificate',
    'Install-Certificate',
    'Invoke-MenuOperation'
)

foreach ($func in $criticalFunctions)
{
    if (Get-Command $func -ErrorAction SilentlyContinue)
    {
        Write-Host "✓ $func is available" -ForegroundColor Green
    } else
    {
        Write-Host "✗ $func is NOT available" -ForegroundColor Red
    }
}

# List all functions that look like they're from our modules
Write-Host "`nAll custom functions found:" -ForegroundColor Cyan
Get-Command | Where-Object {
    $_.Source -eq '' -and
    $_.CommandType -eq 'Function' -and
    $_.Name -notlike "Get-*" -and
    $_.Name -notlike "Set-*" -and
    $_.Name -notlike "New-*" -and
    $_.Name -notlike "Remove-*" -and
    $_.Name -notlike "Clear-*" -and
    $_.Name -notmatch "^[a-z]" # Exclude lowercase functions
} | Sort-Object Name | ForEach-Object {
    Write-Host "  $($_.Name)" -ForegroundColor Gray
}



