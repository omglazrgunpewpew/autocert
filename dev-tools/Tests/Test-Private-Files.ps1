# Test Private files individually
$files = Get-ChildItem -Path ".\Private\*.ps1" -File
Write-Host "Testing $($files.Count) Private files:" -ForegroundColor Cyan

foreach ($file in $files)
{
    try
    {
        . $file.FullName
        Write-Host "✓ $($file.Name)" -ForegroundColor Green
    } catch
    {
        Write-Host "✗ $($file.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}


