<#
    .SYNOPSIS
        Renews all existing certificates via scheduled task or manual trigger.
#>

function Update-Certificates {
    Import-Module Posh-ACME -Force
    Initialize-ACMEServer
    $orders = Get-PAOrder
    foreach ($order in $orders) {
        try {
            # Instead of a non-existent Submit-Renewal command, use New-PACertificate -Renew
            New-PACertificate -MainDomain $order.MainDomain -Renew -Verbose

            Write-Host "`nRenewed certificate for $($order.MainDomain)" -ForegroundColor Green
            Write-Log "Renewed certificate for $($order.MainDomain)"

            # Automatically install the renewed certificate
            $cert = Get-PACertificate -MainDomain $order.MainDomain
            Install-Certificate -PACertificate $cert
        } catch {
            Write-Host "`nFailed to renew certificate for $($order.MainDomain): $($_)" -ForegroundColor Red
            Write-Log "Failed to renew certificate for $($order.MainDomain): $($_)" -Level 'Error'
        }
    }
}
