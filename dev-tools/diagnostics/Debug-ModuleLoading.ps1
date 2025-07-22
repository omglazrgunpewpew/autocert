# Debug-ModuleLoading.ps1
# Debug version to see what's happening with module loading

# Set testing environment variables
$env:AUTOCERT_TESTING_MODE = $true
$env:POSHACME_SKIP_UPGRADE_CHECK = $true

$script:ScriptVersion = "2.0.0-DEBUG"
$script:LoadedModules = @()
$script:InitializationErrors = @()

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

Write-Host "Debugging AutoCert module loading..." -ForegroundColor Cyan

try
{
    # Load core modules first
    Write-Host "`n1. Loading basic core modules..." -ForegroundColor Yellow
    . "$PSScriptRoot\Core\Logging.ps1"
    Write-Host "✓ Logging loaded" -ForegroundColor Green

    . "$PSScriptRoot\Utilities\ErrorHandling.ps1"
    Write-Host "✓ ErrorHandling loaded" -ForegroundColor Green

    . "$PSScriptRoot\Core\SystemInitialization.ps1"
    Write-Host "✓ SystemInitialization loaded" -ForegroundColor Green

    # Test if basic functions are available
    Write-Host "`n2. Testing basic functions..." -ForegroundColor Yellow
    if (Get-Command Write-AutoCertLog -ErrorAction SilentlyContinue)
    {
        Write-Host "✓ Write-AutoCertLog available" -ForegroundColor Green
    } else
    {
        Write-Host "✗ Write-AutoCertLog NOT available" -ForegroundColor Red
    }

    if (Get-Command Invoke-MenuOperation -ErrorAction SilentlyContinue)
    {
        Write-Host "✓ Invoke-MenuOperation available" -ForegroundColor Green
    } else
    {
        Write-Host "✗ Invoke-MenuOperation NOT available" -ForegroundColor Red
    }

    # Now try to load individual modules manually
    Write-Host "`n3. Loading Public modules manually..." -ForegroundColor Yellow
    $publicModules = Get-ChildItem "$PSScriptRoot\Public\*.ps1"
    foreach ($module in $publicModules)
    {
        try
        {
            Write-Host "Loading $($module.Name)..." -ForegroundColor Cyan
            . $module.FullName
            Write-Host "✓ $($module.Name) loaded successfully" -ForegroundColor Green
        } catch
        {
            Write-Host "✗ Failed to load $($module.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # Test if Public functions are now available
    Write-Host "`n4. Testing Public functions..." -ForegroundColor Yellow
    $publicFunctions = @('Register-Certificate', 'Install-Certificate', 'Get-ExistingCertificates')
    foreach ($func in $publicFunctions)
    {
        if (Get-Command $func -ErrorAction SilentlyContinue)
        {
            Write-Host "✓ $func available" -ForegroundColor Green
        } else
        {
            Write-Host "✗ $func NOT available" -ForegroundColor Red
        }
    }

    # Load UI modules manually
    Write-Host "`n5. Loading UI modules manually..." -ForegroundColor Yellow
    $uiModules = Get-ChildItem "$PSScriptRoot\UI\*.ps1"
    foreach ($module in $uiModules)
    {
        try
        {
            Write-Host "Loading $($module.Name)..." -ForegroundColor Cyan
            . $module.FullName
            Write-Host "✓ $($module.Name) loaded successfully" -ForegroundColor Green
        } catch
        {
            Write-Host "✗ Failed to load $($module.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # Test if UI functions are now available
    Write-Host "`n6. Testing UI functions..." -ForegroundColor Yellow
    $uiFunctions = @('Show-Menu', 'Show-CertificateManagementMenu', 'Show-Help')
    foreach ($func in $uiFunctions)
    {
        if (Get-Command $func -ErrorAction SilentlyContinue)
        {
            Write-Host "✓ $func available" -ForegroundColor Green
        } else
        {
            Write-Host "✗ $func NOT available" -ForegroundColor Red
        }
    }

    Write-Host "`n7. Trying Initialize-ScriptModule..." -ForegroundColor Yellow
    $result = Initialize-ScriptModule -NonInteractive
    Write-Host "Initialize-ScriptModule result: $result" -ForegroundColor $(if ($result) { 'Green' } else { 'Red' })

    Write-Host "`nFinal function check..." -ForegroundColor Yellow
    $allFunctions = @('Write-AutoCertLog', 'Register-Certificate', 'Show-Menu', 'Invoke-MenuOperation')
    foreach ($func in $allFunctions)
    {
        if (Get-Command $func -ErrorAction SilentlyContinue)
        {
            Write-Host "✓ $func available" -ForegroundColor Green
        } else
        {
            Write-Host "✗ $func NOT available" -ForegroundColor Red
        }
    }

} catch
{
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Location: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
}



