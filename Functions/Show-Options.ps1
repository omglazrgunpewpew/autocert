<#
    .SYNOPSIS
        A small sub-menu for options (e.g., changing ACME servers).
#>

function Show-Options {
    while ($true) {
        Clear-Host
        $currentServer = (Get-PAServer).Name
        Write-Host "=== Options ===`n"
        Write-Host "1) Change ACME server (current: $currentServer)"
        Write-Host "0) Back"

        $choice = Read-Host "`nEnter your choice (0-1)"
        switch ($choice) {
            '0' { return }
            '1' { Set-ACMEServer }
            default {
                Write-Host "`nInvalid selection. Please choose 0-1." -ForegroundColor Yellow
            }
        }
        Read-Host "`nPress Enter to return to options"
    }
}

function Set-ACMEServer {
    while ($true) {
        Write-Host "`nSelect the ACME server to use:"
        Write-Host "1) Let's Encrypt Production"
        Write-Host "2) Let's Encrypt Staging"
        Write-Host "0) Back"

        $serverChoice = Get-ValidatedInput -Prompt "`nEnter your choice (0-2)" -ValidOptions 1,2
        switch ($serverChoice) {
            0 { return }
            1 {
                Set-PAServer LE_PROD
                Write-Host "`nACME server set to Let's Encrypt Production."
                Write-Log "ACME server set to Let's Encrypt Production."
                break
            }
            2 {
                Set-PAServer LE_STAGING
                Write-Host "`nACME server set to Let's Encrypt Staging."
                Write-Log "ACME server set to Let's Encrypt Staging."
                break
            }
            default {
                Write-Host "`nInvalid selection. Please choose 0-2." -ForegroundColor Yellow
            }
        }
    }
    Read-Host "`nPress Enter to return to options"
}
