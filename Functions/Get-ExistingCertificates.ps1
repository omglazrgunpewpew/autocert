<#
    .SYNOPSIS
        Lists all existing Posh-ACME certificates and displays relevant details.
#>

function Get-ExistingCertificates {
    Initialize-ACMEServer
    $orders = Get-PAOrder
    if ($orders) {
        foreach ($order in $orders) {
            $cert = Get-PACertificate -MainDomain $order.MainDomain
            Write-Host "`nOrder Name: $($order.OrderName)"
            Write-Host "Main Domain: $($order.MainDomain)"
            Write-Host "Alternative Names: $($order.AllDnsNames -join ', ')"
            if ($cert.Certificate) {
                Write-Host "Expires: $($cert.Certificate.NotAfter)"
                Write-Host "Issuer: $($cert.Certificate.Issuer)"
                Write-Host "Thumbprint: $($cert.Certificate.Thumbprint)"
            } else {
                Write-Host "No local certificate file. Possibly revoked or incomplete."
            }
            Write-Host "----------------------------------------"
        }
    } else {
        Write-Host "No existing certificates found."
    }
}
