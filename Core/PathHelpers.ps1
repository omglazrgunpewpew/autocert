# PathHelpers.ps1 - Robust repository path resolution utilities for AutoCert
# Provides consistent absolute path resolution across execution contexts (CLI, Scheduled Task, IDE, Pester tests)

# Cache for repo root to avoid repeated traversal
if (-not (Get-Variable -Name 'AutoCertRepoRoot' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:AutoCertRepoRoot = $null
}

function Get-AutoCertRepoRoot {
    <#
    .SYNOPSIS
        Determines the absolute path to the AutoCert repository root.
    .DESCRIPTION
        Traverses upward from a starting path until it finds a directory containing
        characteristic markers (Main.ps1 and Core folder) or a Modules\Posh-ACME folder.
        Caches result for reuse.
    .PARAMETER StartPath
        Optional starting path (defaults to calling script directory or current location).
    #>
    [CmdletBinding()]
    param(
        [string]$StartPath
    )

    if ($script:AutoCertRepoRoot -and (Test-Path $script:AutoCertRepoRoot)) {
        return $script:AutoCertRepoRoot
    }

    if (-not $StartPath) {
        if ($PSScriptRoot) { $StartPath = $PSScriptRoot } else { $StartPath = (Get-Location).Path }
    }

    $current = (Resolve-Path -LiteralPath $StartPath).Path

    while ($current) {
        $mainScript = Join-Path $current 'Main.ps1'
        $coreDir = Join-Path $current 'Core'
        $modulesDir = Join-Path $current 'Modules'
        $poshAcme = Join-Path $modulesDir 'Posh-ACME'

        if ((Test-Path $mainScript) -and (Test-Path $coreDir)) {
            # primary markers
            $script:AutoCertRepoRoot = $current
            return $script:AutoCertRepoRoot
        }
        elseif (Test-Path $poshAcme) {
            # fallback marker
            $script:AutoCertRepoRoot = $current
            return $script:AutoCertRepoRoot
        }

        $parent = Split-Path $current -Parent
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }

    throw "Unable to locate AutoCert repository root starting from '$StartPath'"
}

function Resolve-AutoCertPath {
    <#
    .SYNOPSIS
        Resolves a relative repository path to an absolute path.
    .PARAMETER RelativePath
        Path relative to repo root.
    .PARAMETER EnsureExists
        If set, throws if the resolved path does not exist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [switch]$EnsureExists
    )

    $root = Get-AutoCertRepoRoot
    $full = Join-Path $root $RelativePath

    if ($EnsureExists -and -not (Test-Path $full)) {
        throw "Resolved path does not exist: $full"
    }
    return $full
}

Export-ModuleMember -Function Get-AutoCertRepoRoot, Resolve-AutoCertPath -ErrorAction SilentlyContinue
