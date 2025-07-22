# Debug-UILoading.ps1
# Debug specifically the UI module loading

Write-Host "Debugging UI Module Loading..." -ForegroundColor Cyan

$env:AUTOCERT_TESTING_MODE = $true
$env:POSHACME_SKIP_UPGRADE_CHECK = $true

# Test each UI file individually
$uiFiles = @(
    "UI\MainMenu.ps1",
    "UI\CertificateMenu.ps1",
    "UI\CredentialMenu.ps1",
    "UI\HelpSystem.ps1"
)

foreach ($file in $uiFiles)
{
    try
    {
        if (Test-Path $file)
        {
            Write-Host "Loading $file..." -ForegroundColor Yellow
            . ".\$file"
            Write-Host "✓ $file loaded successfully" -ForegroundColor Green
        } else
        {
            Write-Host "✗ $file not found" -ForegroundColor Red
        }
    } catch
    {
        Write-Host "✗ Error loading $file`: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Test if Show-Menu function is available after loading
Write-Host "`nTesting Show-Menu function..." -ForegroundColor Cyan
if (Get-Command Show-Menu -ErrorAction SilentlyContinue)
{
    Write-Host "✓ Show-Menu function is available" -ForegroundColor Green

    # Get function definition to verify it's correct
    $function = Get-Command Show-Menu
    Write-Host "Function source: $($function.Source)" -ForegroundColor Gray
    Write-Host "Function definition length: $($function.Definition.Length) characters" -ForegroundColor Gray
} else
{
    Write-Host "✗ Show-Menu function NOT available" -ForegroundColor Red
}

# Check what functions are available from UI modules
Write-Host "`nAvailable functions from UI modules:" -ForegroundColor Cyan
Get-Command | Where-Object { $_.Source -like "*UI*" -or $_.Name -like "*Menu*" -or $_.Name -like "*Help*" } |
    Sort-Object Name | ForEach-Object {
        Write-Host "  $($_.Name) (from $($_.Source))" -ForegroundColor Gray
    }


