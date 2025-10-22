<#
    .SYNOPSIS
        Renews all existing certificates via scheduled task or manual trigger.
    .NOTES
        Function name uses plural noun intentionally as it operates on all certificates.
#>
function Update-AllCertificates {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Boolean])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Function updates all certificates by design')]
    param(
        [switch]$Force
    )
    Import-Module Posh-ACME -Force
    Initialize-ACMEServer
    $orders = Get-PAOrder
    if (-not $orders) {
        Write-Warning -Message "No certificates found to update."
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
            Write-Information -MessageData "`nRenewed certificate for $($order.MainDomain)" -InformationAction Continue
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
                        Write-Host -Object "Reinstalling renewed certificate..." -ForegroundColor Cyan
                        Install-PACertificate -PACertificate $renewed -StoreLocation LocalMachine
                        Write-Information -MessageData "Certificate reinstalled." -InformationAction Continue
                    }
                } catch {
                    Write-Warning -Message "Certificate renewed but reinstallation failed: $($_.Exception.Message)"
                }
            }
        } catch {
            Write-Error -Message "`nFailed to renew certificate for $($order.MainDomain): $($_)"
            Write-Log "Failed to renew certificate for $($order.MainDomain): $($_)" -Level 'Error'
        }
    }
}


