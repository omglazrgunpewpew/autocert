# Test-MainWorkflow.ps1
# Test the exact workflow that Main.ps1 uses

Write-Host "Testing Main.ps1 Interactive Workflow..." -ForegroundColor Cyan

# Set the exact environment that Main.ps1 creates
$script:ScriptVersion = "2.0.0"
$script:ScriptName = "AutoCert Certificate Management System"
$script:StartTime = Get-Date
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'

# Auto-detect testing environment (copied from Main.ps1)
$repoModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Modules\Posh-ACME'
if ((Test-Path $repoModulePath) -and -not $env:AUTOCERT_TESTING_MODE)
{
    Write-Verbose "Development environment detected: Setting testing mode to prevent module updates"
    $env:AUTOCERT_TESTING_MODE = $true
    $env:POSHACME_SKIP_UPGRADE_CHECK = $true
}

# Initialize script-wide variables (copied from Main.ps1)
$script:LoadedModules = @()
$script:InitializationErrors = @()

# Load core system modules (copied from Main.ps1)
try
{
    Write-Host "Loading core system modules..." -ForegroundColor Yellow
    . "$PSScriptRoot\Core\SystemInitialization.ps1"
    . "$PSScriptRoot\Core\RenewalOperations.ps1"
    . "$PSScriptRoot\Core\SystemDiagnostics.ps1"
    . "$PSScriptRoot\Core\RenewalConfig.ps1"
    Write-Host "✓ Core system modules loaded" -ForegroundColor Green
} catch
{
    Write-Host "✗ Failed to load core system modules: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Initialize system (copied from Main.ps1)
try
{
    Write-Host "Initializing system..." -ForegroundColor Yellow
    $moduleLoadSuccess = Initialize-ScriptModule -NonInteractive:$false
    if (-not $moduleLoadSuccess)
    {
        Write-Host "✗ System initialization failed" -ForegroundColor Red
        exit 1
    }
    Write-Host "✓ System initialization succeeded" -ForegroundColor Green
} catch
{
    Write-Host "✗ System initialization error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test if Show-Menu is available (the critical test)
Write-Host "`nTesting Show-Menu availability..." -ForegroundColor Cyan
if (Get-Command Show-Menu -ErrorAction SilentlyContinue)
{
    Write-Host "✓ Show-Menu function is available" -ForegroundColor Green

    # Test if we can call it (but don't actually run the interactive loop)
    try
    {
        # Get the function info
        $func = Get-Command Show-Menu
        Write-Host "  Function type: $($func.CommandType)" -ForegroundColor Gray
        Write-Host "  Function source: $($func.Source)" -ForegroundColor Gray
        Write-Host "  Definition length: $($func.Definition.Length) characters" -ForegroundColor Gray

        # Test if Invoke-MenuOperation is also available (used in Main.ps1)
        if (Get-Command Invoke-MenuOperation -ErrorAction SilentlyContinue)
        {
            Write-Host "✓ Invoke-MenuOperation is also available" -ForegroundColor Green
        } else
        {
            Write-Host "⚠️ Invoke-MenuOperation is NOT available" -ForegroundColor Yellow
        }

        Write-Host "`n✅ INTERACTIVE MODE READY!" -ForegroundColor Green
        Write-Host "The system can successfully run in interactive mode." -ForegroundColor Green

    } catch
    {
        Write-Host "✗ Error testing Show-Menu function: $($_.Exception.Message)" -ForegroundColor Red
    }
} else
{
    Write-Host "✗ Show-Menu function is NOT available" -ForegroundColor Red

    # Debug what functions we do have
    Write-Host "`nAvailable functions containing 'Menu':" -ForegroundColor Yellow
    Get-Command | Where-Object { $_.Name -like "*Menu*" } | ForEach-Object {
        Write-Host "  $($_.Name) (from $($_.Source))" -ForegroundColor Gray
    }
}

# Test other critical functions from Main.ps1
Write-Host "`nTesting other critical functions..." -ForegroundColor Cyan
$criticalFunctions = @(
    'Register-Certificate',
    'Install-Certificate',
    'Set-AutomaticRenewal',
    'Show-CertificateManagementMenu',
    'Show-Options',
    'Show-CredentialManagementMenu',
    'Test-SystemHealth',
    'Show-Help'
)

$allAvailable = $true
foreach ($func in $criticalFunctions)
{
    if (Get-Command $func -ErrorAction SilentlyContinue)
    {
        Write-Host "✓ $func" -ForegroundColor Green
    } else
    {
        Write-Host "✗ $func" -ForegroundColor Red
        $allAvailable = $false
    }
}

if ($allAvailable)
{
    Write-Host "`n🎉 ALL CRITICAL FUNCTIONS AVAILABLE!" -ForegroundColor Green
    Write-Host "AutoCert is ready for interactive use." -ForegroundColor Green
    Write-Host "`nTo start the interactive interface, run:" -ForegroundColor Cyan
    Write-Host "  .\Main.ps1" -ForegroundColor White
    exit 0
} else
{
    Write-Host "`n❌ Some critical functions are missing" -ForegroundColor Red
    exit 1
}


