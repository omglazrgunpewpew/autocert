# Apply-Refactoring.ps1
# This script applies the refactoring changes to the Main.ps1 file

[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Revert
)

$scriptPath = $PSScriptRoot
$parentPath = Split-Path $scriptPath -Parent
$originalFile = Join-Path $parentPath "Main.ps1"
$newFile = Join-Path $scriptPath "Main.ps1.new"
$backupFile = Join-Path $scriptPath "Main.ps1.original"

function Set-RefactoringChanges {
    if (-not (Test-Path $newFile)) {
        Write-Error -Message "New file $newFile not found. Cannot apply changes."
        return
    }

    # Backup original if not already done
    if (-not (Test-Path $backupFile)) {
        Write-Host -Object "Backing up original file to $backupFile" -ForegroundColor Cyan
        Copy-Item -Path $originalFile -Destination $backupFile -Force
    } else {
        Write-Warning -Message "Backup already exists at $backupFile"
    }

    # Apply the new file
    Write-Host -Object "Applying refactored Main.ps1..." -ForegroundColor Cyan
    Copy-Item -Path $newFile -Destination $originalFile -Force

    Write-Information -MessageData "Changes applied successfully. The original file is backed up at $backupFile" -InformationAction Continue
    Write-Information -MessageData "You can test the refactored code by running Main.ps1" -InformationAction Continue
    Write-Host -Object "If you need to revert changes, run this script with -Revert" -ForegroundColor Yellow
}

function Restore-OriginalCode {
    if (-not (Test-Path $backupFile)) {
        Write-Error -Message "Backup file $backupFile not found. Cannot revert changes."
        return
    }

    # Save the current file if it's not the backup
    if ((Get-FileHash $originalFile).Hash -ne (Get-FileHash $backupFile).Hash) {
        Write-Host -Object "Saving current Main.ps1 to $newFile" -ForegroundColor Cyan
        Copy-Item -Path $originalFile -Destination $newFile -Force
    }

    # Restore from backup
    Write-Host -Object "Restoring original Main.ps1 from backup..." -ForegroundColor Cyan
    Copy-Item -Path $backupFile -Destination $originalFile -Force

    Write-Information -MessageData "Original file has been restored. The refactored version is saved at $newFile" -InformationAction Continue
}

# Main execution
if ($Apply -and $Revert) {
    Write-Error -Message "Cannot specify both -Apply and -Revert. Choose one."
    return
}

if ($Apply) {
    Set-RefactoringChanges
} elseif ($Revert) {
    Restore-OriginalCode
} else {
    Write-Host -Object "AutoCert Refactoring Tool" -ForegroundColor Cyan
    Write-Host -Object "----------------------------------" -ForegroundColor Cyan
    Write-Host -Object "This script helps apply or revert the refactoring changes." -ForegroundColor White
    Write-Information -MessageData "" -InformationAction Continue
    Write-Host -Object "To apply changes:  .\Apply-Refactoring.ps1 -Apply" -ForegroundColor Yellow
    Write-Host -Object "To revert changes: .\Apply-Refactoring.ps1 -Revert" -ForegroundColor Yellow
    Write-Information -MessageData "" -InformationAction Continue
    Write-Host -Object "It is recommended to run Test-Refactoring.ps1 before applying changes." -ForegroundColor White
}




