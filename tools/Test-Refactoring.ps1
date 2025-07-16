# Test-Refactoring.ps1
# This script validates that all refactored modules are working correctly

Write-Host -Object "Testing AutoCert Refactoring..." -ForegroundColor Cyan
Write-Host -Object "----------------------------------" -ForegroundColor Cyan

# Define paths to test
$parentPath = Split-Path $PSScriptRoot -Parent
$corePaths = @(
    "$parentPath\Core\Logging.ps1",
    "$parentPath\Core\Helpers.ps1"
)

$uiPaths = @(
    "$parentPath\UI\MainMenu.ps1",
    "$parentPath\UI\CertificateMenu.ps1",
    "$parentPath\UI\CredentialMenu.ps1",
    "$parentPath\UI\HelpSystem.ps1"
)

$utilityPaths = @(
    "$parentPath\Utilities\ErrorHandling.ps1",
    "$parentPath\Utilities\HealthCheck.ps1",
    "$parentPath\Utilities\Configuration.ps1",
    "$parentPath\Utilities\RenewalManager.ps1",
    "$parentPath\Utilities\ModuleManager.ps1"
)

# Test function to verify paths and function availability
function Test-ModuleFiles {
    param(
        [string[]]$Paths,
        [string]$Category
    )

    Write-Warning -Message "`nTesting $Category Files:"

    foreach ($path in $Paths) {
        $fileName = Split-Path -Path $path -Leaf

        if (Test-Path $path) {
            Write-Information -MessageData "  ✓ $fileName exists" -InformationAction Continue

            # Load the file to test for functions
            try {
                . $path
                Write-Information -MessageData "  ✓ $fileName loaded successfully" -InformationAction Continue
            } catch {
                Write-Error -Message "  ✗ $fileName failed to load: $($_.Exception.Message)"
            }

        } else {
            Write-Error -Message "  ✗ $fileName does not exist at path: $path"
        }
    }
}

# Run tests
Test-ModuleFiles -Paths $corePaths -Category "Core"
Test-ModuleFiles -Paths $uiPaths -Category "UI"
Test-ModuleFiles -Paths $utilityPaths -Category "Utility"

# Test if critical functions are available after loading
Write-Warning -Message "`nTesting Critical Functions:"

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
        Write-Information -MessageData "  ✓ $function is available" -InformationAction Continue
    } else {
        Write-Error -Message "  ✗ $function is NOT available"
    }
}

Write-Host -Object "`nTesting Complete" -ForegroundColor Cyan



