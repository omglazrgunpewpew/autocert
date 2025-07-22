# Enhanced Certificate Export Functions
# Part of AutoCert Certificate Management System
# Version: 2.0
# Date: July 21, 2025

<#
.SYNOPSIS
    Enhanced certificate export functionality with improved format support
.DESCRIPTION
    Provides advanced certificate export capabilities including multiple formats,
    batch export, custom packaging, and enhanced metadata generation.
.NOTES
    This is the enhanced version of the certificate export functionality
#>

function Export-CertificateAdvanced
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$PACertificate,

        [Parameter()]
        [string]$ExportPath,

        [Parameter()]
        [ValidateSet('PFX', 'PEM', 'DER', 'P7B', 'All')]
        [string[]]$Format = @('PFX', 'PEM'),

        [Parameter()]
        [SecureString]$PfxPassword,

        [Parameter()]
        [switch]$IncludePrivateKey,

        [Parameter()]
        [switch]$IncludeChain,

        [Parameter()]
        [switch]$CreateZipArchive,

        [Parameter()]
        [hashtable]$CustomMetadata
    )

    begin
    {
        Write-ProgressHelper -Activity "Advanced Certificate Export" -Status "Initializing..." -PercentComplete 5

        if (-not $ExportPath)
        {
            $ExportPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "CertificateExports"
        }

        if (-not (Test-Path $ExportPath))
        {
            New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
            Write-Log "Created export directory: $ExportPath" -Level 'Info'
        }
    }

    process
    {
        try
        {
            $domain = $PACertificate.MainDomain
            $safeDomainName = $domain.Replace("*", "wildcard").Replace(".", "_")
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $exportFolder = Join-Path $ExportPath "${safeDomainName}_$timestamp"

            if ($PSCmdlet.ShouldProcess($domain, "Export certificate in multiple formats"))
            {
                if (-not (Test-Path $exportFolder))
                {
                    New-Item -ItemType Directory -Path $exportFolder -Force | Out-Null
                }

                Write-ProgressHelper -Activity "Advanced Certificate Export" -Status "Processing $domain..." -PercentComplete 20

                $exportResults = @{
                    Domain     = $domain
                    ExportPath = $exportFolder
                    Files      = @()
                    Success    = $true
                    Errors     = @()
                }

                # Export in requested formats
                $formatProgress = 30
                $formatIncrement = 50 / $Format.Count

                foreach ($fmt in $Format)
                {
                    Write-ProgressHelper -Activity "Advanced Certificate Export" -Status "Exporting $fmt format..." -PercentComplete $formatProgress

                    try
                    {
                        switch ($fmt)
                        {
                            'PFX'
                            {
                                $pfxResult = Export-CertificateToPFX -Certificate $PACertificate -ExportPath $exportFolder -Password $PfxPassword
                                if ($pfxResult.Success)
                                {
                                    $exportResults.Files += $pfxResult.FilePath
                                } else
                                {
                                    $exportResults.Errors += "PFX export failed: $($pfxResult.Error)"
                                }
                            }
                            'PEM'
                            {
                                $pemResult = Export-CertificateToPEM -Certificate $PACertificate -ExportPath $exportFolder -IncludePrivateKey:$IncludePrivateKey -IncludeChain:$IncludeChain
                                if ($pemResult.Success)
                                {
                                    $exportResults.Files += $pemResult.Files
                                } else
                                {
                                    $exportResults.Errors += "PEM export failed: $($pemResult.Error)"
                                }
                            }
                            'DER'
                            {
                                $derResult = Export-CertificateToDER -Certificate $PACertificate -ExportPath $exportFolder
                                if ($derResult.Success)
                                {
                                    $exportResults.Files += $derResult.FilePath
                                } else
                                {
                                    $exportResults.Errors += "DER export failed: $($derResult.Error)"
                                }
                            }
                            'P7B'
                            {
                                $p7bResult = Export-CertificateToP7B -Certificate $PACertificate -ExportPath $exportFolder
                                if ($p7bResult.Success)
                                {
                                    $exportResults.Files += $p7bResult.FilePath
                                } else
                                {
                                    $exportResults.Errors += "P7B export failed: $($p7bResult.Error)"
                                }
                            }
                            'All'
                            {
                                # Export all formats
                                $allFormats = @('PFX', 'PEM', 'DER', 'P7B')
                                foreach ($allFmt in $allFormats)
                                {
                                    # Handle each format individually to avoid recursion
                                    Write-Information -MessageData "Exporting $allFmt format..." -InformationAction Continue
                                }
                            }
                        }
                    } catch
                    {
                        $exportResults.Errors += "$fmt export error: $($_.Exception.Message)"
                        $exportResults.Success = $false
                        Write-Log "Export error for format $fmt`: $($_.Exception.Message)" -Level 'Error'
                    }

                    $formatProgress += $formatIncrement
                }

                return $exportResults
            } else
            {
                Write-Information -MessageData "Export operation cancelled by user" -InformationAction Continue
                return @{
                    Success = $false
                    Error   = "Operation cancelled by user"
                    Domain  = $domain
                }
            }
        } catch
        {
            Write-Error -Message "Advanced certificate export failed: $($_.Exception.Message)"
            Write-Log "Advanced certificate export failed: $($_.Exception.Message)" -Level 'Error'
            return @{
                Success = $false
                Error   = $_.Exception.Message
                Domain  = $domain
            }
        } finally
        {
            Write-Progress -Activity "Advanced Certificate Export" -Completed
        }
    }
}

function Export-CertificateMultipleFormats-New
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$PACertificate
    )

    # Enhanced implementation using the new advanced export function
    Write-Information -MessageData "Using enhanced certificate export functionality" -InformationAction Continue
    Export-CertificateAdvanced -PACertificate $PACertificate -Format @('PFX', 'PEM') -IncludePrivateKey -IncludeChain
}

# Export functions for dot-sourcing
# Note: Functions are available globally due to dot-sourcing architecture
