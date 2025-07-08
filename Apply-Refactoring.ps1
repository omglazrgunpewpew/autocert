# Apply-Refactoring.ps1
# This script applies the refactoring changes to the Main.ps1 file

[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Revert
)

$scriptPath = $PSScriptRoot
$originalFile = Join-Path $scriptPath "Main.ps1"
$newFile = Join-Path $scriptPath "Main.ps1.new"
$backupFile = Join-Path $scriptPath "Main.ps1.original"

function Set-RefactoringChanges {
    if (-not (Test-Path $newFile)) {
        Write-Error "New file $newFile not found. Cannot apply changes."
        return
    }
    
    # Backup original if not already done
    if (-not (Test-Path $backupFile)) {
        Write-Host "Backing up original file to $backupFile" -ForegroundColor Cyan
        Copy-Item -Path $originalFile -Destination $backupFile -Force
    } else {
        Write-Host "Backup already exists at $backupFile" -ForegroundColor Yellow
    }
    
    # Apply the new file
    Write-Host "Applying refactored Main.ps1..." -ForegroundColor Cyan
    Copy-Item -Path $newFile -Destination $originalFile -Force
    
    Write-Host "Changes applied successfully. The original file is backed up at $backupFile" -ForegroundColor Green
    Write-Host "You can test the refactored code by running Main.ps1" -ForegroundColor Green
    Write-Host "If you need to revert changes, run this script with -Revert" -ForegroundColor Yellow
}

function Restore-OriginalCode {
    if (-not (Test-Path $backupFile)) {
        Write-Error "Backup file $backupFile not found. Cannot revert changes."
        return
    }
    
    # Save the current file if it's not the backup
    if ((Get-FileHash $originalFile).Hash -ne (Get-FileHash $backupFile).Hash) {
        Write-Host "Saving current Main.ps1 to $newFile" -ForegroundColor Cyan
        Copy-Item -Path $originalFile -Destination $newFile -Force
    }
    
    # Restore from backup
    Write-Host "Restoring original Main.ps1 from backup..." -ForegroundColor Cyan
    Copy-Item -Path $backupFile -Destination $originalFile -Force
    
    Write-Host "Original file has been restored. The refactored version is saved at $newFile" -ForegroundColor Green
}

# Main execution
if ($Apply -and $Revert) {
    Write-Error "Cannot specify both -Apply and -Revert. Choose one."
    return
}

if ($Apply) {
    Set-RefactoringChanges
} elseif ($Revert) {
    Restore-OriginalCode
} else {
    Write-Host "AutoCert Refactoring Tool" -ForegroundColor Cyan
    Write-Host "----------------------------------" -ForegroundColor Cyan
    Write-Host "This script helps apply or revert the refactoring changes." -ForegroundColor White
    Write-Host ""
    Write-Host "To apply changes:  .\Apply-Refactoring.ps1 -Apply" -ForegroundColor Yellow
    Write-Host "To revert changes: .\Apply-Refactoring.ps1 -Revert" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "It is recommended to run Test-Refactoring.ps1 before applying changes." -ForegroundColor White
}
