<#
    .SYNOPSIS
        Renews all existing certificates via scheduled task or manual trigger.
#>
function Update-AllCertificates {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Boolean])]
    param(
        [switch]$Force
    )
    Import-Module Posh-ACME -Force
    Initialize-ACMEServer
    $orders = Get-PAOrder
    if (-not $orders) {
        Write-Host "No certificates found to update." -ForegroundColor Yellow
        return
    }
    foreach ($order in $orders) {
        try {
            # Use New-PACertificate with -Force for renewal
            $renewParams = @{
                MainDomain = $order.MainDomain
                Verbose = $true
            }
            if ($Force) {
                $renewParams['Force'] = $true
            }
            $renewed = New-PACertificate @renewParams
            Write-Host "`nRenewed certificate for $($order.MainDomain)" -ForegroundColor Green
            Write-Log "Renewed certificate for $($order.MainDomain)"
            # Automatically install renewed certificate if it was previously installed
            if ($renewed) {
                try {
                    # Check if certificate exists in local machine store
                    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
                    $store.Open("ReadOnly")
                    $existingCert = $store.Certificates | Where-Object {
                        $_.Subject -like "*$($order.MainDomain)*" -or $_.Subject -like "*$($order.MainDomain.Replace('*.', ''))*"
                    }
                    $store.Close()
                    if ($existingCert) {
                        Write-Host "Reinstalling renewed certificate..." -ForegroundColor Cyan
                        Install-PACertificate -PACertificate $renewed -StoreLocation LocalMachine
                        Write-Host "Certificate reinstalled." -ForegroundColor Green
                    }
                } catch {
                    Write-Warning "Certificate renewed but reinstallation failed: $($_.Exception.Message)"
                }
            }
        } catch {
            Write-Host "`nFailed to renew certificate for $($order.MainDomain): $($_)" -ForegroundColor Red
            Write-Log "Failed to renew certificate for $($order.MainDomain): $($_)" -Level 'Error'
        }
    }
}