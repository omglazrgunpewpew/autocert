# Test-Refactoring.ps1
# This script validates that all refactored modules are working correctly

Write-Host "Testing AutoCert Refactoring..." -ForegroundColor Cyan
Write-Host "----------------------------------" -ForegroundColor Cyan

# Define paths to test
$corePaths = @(
    "$PSScriptRoot\Core\Logging.ps1",
    "$PSScriptRoot\Core\Helpers.ps1"
)

$uiPaths = @(
    "$PSScriptRoot\UI\MainMenu.ps1",
    "$PSScriptRoot\UI\CertificateMenu.ps1",
    "$PSScriptRoot\UI\CredentialMenu.ps1",
    "$PSScriptRoot\UI\HelpSystem.ps1"
)

$utilityPaths = @(
    "$PSScriptRoot\Utilities\ErrorHandling.ps1",
    "$PSScriptRoot\Utilities\HealthCheck.ps1",
    "$PSScriptRoot\Utilities\Configuration.ps1",
    "$PSScriptRoot\Utilities\RenewalManager.ps1",
    "$PSScriptRoot\Utilities\ModuleManager.ps1"
)

# Test function to verify paths and function availability
function Test-ModuleFiles {
    param(
        [string[]]$Paths,
        [string]$Category
    )
    
    Write-Host "`nTesting $Category Files:" -ForegroundColor Yellow
    
    foreach ($path in $Paths) {
        $fileName = Split-Path -Path $path -Leaf
        
        if (Test-Path $path) {
            Write-Host "  ✓ $fileName exists" -ForegroundColor Green
            
            # Load the file to test for functions
            try {
                . $path
                Write-Host "  ✓ $fileName loaded successfully" -ForegroundColor Green
            } catch {
                Write-Host "  ✗ $fileName failed to load: $($_.Exception.Message)" -ForegroundColor Red
            }
            
        } else {
            Write-Host "  ✗ $fileName does not exist at path: $path" -ForegroundColor Red
        }
    }
}

# Run tests
Test-ModuleFiles -Paths $corePaths -Category "Core"
Test-ModuleFiles -Paths $uiPaths -Category "UI"
Test-ModuleFiles -Paths $utilityPaths -Category "Utility"

# Test if critical functions are available after loading
Write-Host "`nTesting Critical Functions:" -ForegroundColor Yellow

$criticalFunctions = @(
    "Show-Menu",
    "Show-CertificateManagementMenu",
    "Show-CredentialManagementMenu",
    "Invoke-MenuOperation",
    "Test-SystemHealth",
    "Show-Help",
    "Test-SystemConfiguration",
    "Invoke-AutomatedRenewal",
    "Initialize-AutoCertModules"
)

foreach ($function in $criticalFunctions) {
    if (Get-Command $function -ErrorAction SilentlyContinue) {
        Write-Host "  ✓ $function is available" -ForegroundColor Green
    } else {
        Write-Host "  ✗ $function is NOT available" -ForegroundColor Red
    }
}

Write-Host "`nTesting Complete" -ForegroundColor Cyan
