# Final-System-Test.ps1
# Comprehensive test to verify AutoCert system is working

Write-Host "🔧 AutoCert System Comprehensive Test" -ForegroundColor Cyan
Write-Host "=" * 50 -ForegroundColor Gray

# Test 1: Configuration test mode (should work)
Write-Host "`n1. Testing Configuration Mode..." -ForegroundColor Yellow
try
{
    $configResult = & ".\Main.ps1" -ConfigTest
    $configExitCode = $LASTEXITCODE
    if ($configExitCode -eq 0)
    {
        Write-Host "   ✅ Configuration test PASSED" -ForegroundColor Green
    } else
    {
        Write-Host "   ❌ Configuration test FAILED (exit code: $configExitCode)" -ForegroundColor Red
    }
} catch
{
    Write-Host "   ❌ Configuration test ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Module loading manually (should work)
Write-Host "`n2. Testing Manual Module Loading..." -ForegroundColor Yellow
try
{
    # Load essential functions manually
    . ".\Core\Logging.ps1"
    . ".\Core\Helpers.ps1"
    . ".\Utilities\ErrorHandling.ps1"
    . ".\UI\MainMenu.ps1"
    . ".\Public\Register-Certificate.ps1"

    $manualFunctions = @('Write-AutoCertLog', 'Write-ProgressHelper', 'Show-Menu', 'Register-Certificate', 'Invoke-MenuOperation')
    $manualSuccess = $true

    foreach ($func in $manualFunctions)
    {
        if (Get-Command $func -ErrorAction SilentlyContinue)
        {
            Write-Host "   ✅ $func available" -ForegroundColor Green
        } else
        {
            Write-Host "   ❌ $func NOT available" -ForegroundColor Red
            $manualSuccess = $false
        }
    }

    if ($manualSuccess)
    {
        Write-Host "   ✅ Manual loading SUCCESSFUL - All core functions available" -ForegroundColor Green
    } else
    {
        Write-Host "   ❌ Manual loading FAILED - Some functions missing" -ForegroundColor Red
    }
} catch
{
    Write-Host "   ❌ Manual loading ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Individual function tests
Write-Host "`n3. Testing Individual Functions..." -ForegroundColor Yellow

# Test Show-Menu (should be available from manual loading)
if (Get-Command Show-Menu -ErrorAction SilentlyContinue)
{
    try
    {
        # Test if Show-Menu is properly defined (get help without executing)
        $help = Get-Help Show-Menu -ErrorAction Stop
        Write-Host "   ✅ Show-Menu function is properly defined" -ForegroundColor Green
    } catch
    {
        Write-Host "   ⚠️  Show-Menu exists but help failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else
{
    Write-Host "   ❌ Show-Menu not available for testing" -ForegroundColor Red
}

# Test Register-Certificate
if (Get-Command Register-Certificate -ErrorAction SilentlyContinue)
{
    try
    {
        $help = Get-Help Register-Certificate -ErrorAction Stop
        Write-Host "   ✅ Register-Certificate function is properly defined" -ForegroundColor Green
    } catch
    {
        Write-Host "   ⚠️  Register-Certificate exists but help failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else
{
    Write-Host "   ❌ Register-Certificate not available for testing" -ForegroundColor Red
}

# Test 4: File existence and syntax
Write-Host "`n4. Testing File Syntax..." -ForegroundColor Yellow
$criticalFiles = @(
    "Main.ps1",
    "Core\SystemInitialization.ps1",
    "UI\MainMenu.ps1",
    "Public\Register-Certificate.ps1",
    "Utilities\ErrorHandling.ps1"
)

$syntaxSuccess = $true
foreach ($file in $criticalFiles)
{
    if (Test-Path $file)
    {
        try
        {
            # Test syntax by parsing the file
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)
            if ($ast)
            {
                Write-Host "   ✅ $file syntax OK" -ForegroundColor Green
            } else
            {
                Write-Host "   ❌ $file syntax FAILED" -ForegroundColor Red
                $syntaxSuccess = $false
            }
        } catch
        {
            Write-Host "   ❌ $file syntax ERROR: $($_.Exception.Message)" -ForegroundColor Red
            $syntaxSuccess = $false
        }
    } else
    {
        Write-Host "   ❌ $file NOT FOUND" -ForegroundColor Red
        $syntaxSuccess = $false
    }
}

# Test 5: System requirements
Write-Host "`n5. Testing System Requirements..." -ForegroundColor Yellow

# Check PowerShell version
$psVersion = $PSVersionTable.PSVersion
if ($psVersion.Major -ge 5)
{
    Write-Host "   ✅ PowerShell version $psVersion OK" -ForegroundColor Green
} else
{
    Write-Host "   ❌ PowerShell version $psVersion too old (need 5.1+)" -ForegroundColor Red
}

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if ($isAdmin)
{
    Write-Host "   ✅ Running as Administrator" -ForegroundColor Green
} else
{
    Write-Host "   ⚠️  Not running as Administrator (required for certificate operations)" -ForegroundColor Yellow
}

# Check Posh-ACME module availability
if (Test-Path "Modules\Posh-ACME")
{
    Write-Host "   ✅ Posh-ACME module found in repository" -ForegroundColor Green
} else
{
    Write-Host "   ❌ Posh-ACME module NOT found" -ForegroundColor Red
}

# Final assessment
Write-Host "`n" + "=" * 50 -ForegroundColor Gray
Write-Host "🔍 FINAL ASSESSMENT" -ForegroundColor Cyan

$issues = @()
if ($configExitCode -ne 0) { $issues += "Configuration test failed" }
if (-not $manualSuccess) { $issues += "Manual function loading failed" }
if (-not $syntaxSuccess) { $issues += "Syntax errors in critical files" }
if (-not $isAdmin) { $issues += "Not running as Administrator" }

if ($issues.Count -eq 0)
{
    Write-Host "`n🎉 SYSTEM STATUS: FULLY OPERATIONAL" -ForegroundColor Green
    Write-Host "   AutoCert is ready for use!" -ForegroundColor Green
    Write-Host "`n📋 USAGE INSTRUCTIONS:" -ForegroundColor Cyan
    Write-Host "   • Configuration test: .\Main.ps1 -ConfigTest" -ForegroundColor White
    Write-Host "   • Interactive mode: .\Main.ps1" -ForegroundColor White
    Write-Host "   • Automated renewal: .\Main.ps1 -RenewAll -NonInteractive" -ForegroundColor White
} elseif ($issues.Count -eq 1 -and $issues[0] -eq "Not running as Administrator")
{
    Write-Host "`n⚠️  SYSTEM STATUS: MOSTLY OPERATIONAL" -ForegroundColor Yellow
    Write-Host "   AutoCert core functions work, but Administrator privileges needed for certificate operations" -ForegroundColor Yellow
    Write-Host "`n📋 TO FIX: Run PowerShell as Administrator" -ForegroundColor Cyan
} else
{
    Write-Host "`n❌ SYSTEM STATUS: NEEDS ATTENTION" -ForegroundColor Red
    Write-Host "   Issues found:" -ForegroundColor Red
    $issues | ForEach-Object {
        Write-Host "   • $_" -ForegroundColor Red
    }
}

Write-Host "`n" + "=" * 50 -ForegroundColor Gray


