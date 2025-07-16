#!/usr/bin/env pwsh
<#
    .SYNOPSIS
        Adds ShouldProcess support to functions that modify system state

    .DESCRIPTION
        Identifies functions with verbs that change system state and adds proper
        ShouldProcess support including CmdletBinding attribute and ShouldProcess calls

    .PARAMETER WhatIf
        Shows what changes would be made without applying them

    .PARAMETER TargetFiles
        Specific files to process
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$TargetFiles
)

$ErrorActionPreference = 'Stop'

# Functions that need ShouldProcess based on PSScriptAnalyzer results
$FunctionsNeedingShouldProcess = @{
    'New-CertificateBackup'    = 'BackupManager.ps1'
    'Remove-OldBackups'        = 'BackupManager.ps1'
    'Reset-CircuitBreaker'     = 'CircuitBreaker.ps1'
    'Set-SecureCredential'     = 'Helpers.ps1'
    'New-RenewalScheduledTask' = 'RenewalConfig.ps1'
    'Remove-StoredCredential'  = 'Manage-Credentials.ps1'
    'Set-StoredCredential'     = 'Manage-Credentials.ps1'
    'Set-ACMEServer'           = 'Show-Options.ps1'
    'Reset-ModuleState'        = 'ModuleManager.ps1'
}

[OutputType([object[]])]\n    function Add-ShouldProcessSupport {
    param(
        [string]$FilePath,
        [string]$FunctionName,
        [switch]$WhatIfPreferencePreference
    )

    $content = Get-Content -Path $FilePath -Raw

    # Check if function already has ShouldProcess
    if ($content -match "function\s+$FunctionName.*ShouldProcess") {
        Write-Information -MessageData " -InformationAction Continue
        return
    }

    # Pattern to find the function
    $functionPattern = " -InformationAction Continue(function\s+$FunctionName\s*\ { [^ }]*?)(\[CmdletBinding\([^\]]*\)\] | \[CmdletBinding\(\)\] | \[CmdletBinding\])?([^
        }]*param\s*\([^ }]*?\))"

    if ($content -match $functionPattern) {
        $existingCmdletBinding = $Matches[2]

        # Create new CmdletBinding with ShouldProcess
        if ($existingCmdletBinding) {
            # Update existing CmdletBinding
            if ($existingCmdletBinding -match 'SupportsShouldProcess') {
                Write-Information -MessageData " -InformationAction Continue
return
}

$newCmdletBinding = $existingCmdletBinding -replace '\)\]$', ', SupportsShouldProcess)]'
if ($existingCmdletBinding -eq '[CmdletBinding]' -or $existingCmdletBinding -eq '[CmdletBinding()]') {
    $newCmdletBinding = '[CmdletBinding(SupportsShouldProcess)]'
}
}
else {
    $newCmdletBinding = '    [CmdletBinding(SupportsShouldProcess)]'
}

if ($WhatIfPreference) {
    Write-Information -MessageData " -InformationAction ContinueWould add ShouldProcess support to $FunctionName in $FilePath" -InformationAction Continue
    Write-Information -MessageData " -InformationAction Continue
        }
        else {
            # This is a complex transformation that requires manual intervention
            Write-Warning -Message "
    Write-Warning -Message "Add this CmdletBinding: $newCmdletBinding"
    Write-Warning -Message "
        }
    }
    else {
        Write-Warning -Message "Could not find function $FunctionName in $FilePath"
    }
}

# Main execution
try {
    $rootPath = Split-Path -Parent $PSScriptRoot

    Write-Information -MessageData " -InformationAction Continue
    Write-Information -MessageData " -InformationAction Continue===================================" -InformationAction Continue

    if ($WhatIfPreference) {
        Write-Warning -Message "
    }

    $functionsProcessed = 0

    foreach ($functionName in $FunctionsNeedingShouldProcess.Keys) {
        $fileName = $FunctionsNeedingShouldProcess[$functionName]

        # Find the file
        $filePath = Get-ChildItem -Path $rootPath -Recurse -Name $fileName |
        Select-Object -First 1 |
        ForEach-Object { Join-Path $rootPath $_ }

        if (-not $filePath -or -not (Test-Path $filePath)) {
            Write-Warning -Message "File not found: $fileName"
            continue
        }

        Write-Information -MessageData " -InformationAction Continue
        Add-ShouldProcessSupport -FilePath $filePath -FunctionName $functionName -WhatIf:$WhatIfPreference
        $functionsProcessed++
    }

    Write-Information -MessageData " -InformationAction Continue`nSummary:" -InformationAction Continue
    Write-Information -MessageData " -InformationAction Continue

    if ($WhatIfPreference) {
        Write-Warning -Message "
}

Write-Warning -Message "`nNote: This tool identifies functions needing ShouldProcess support."
Write-Warning -Message "

}
catch {
    Write-Error -Message "Failed to process ShouldProcess support: $($_.Exception.Message)"
    exit 1
}






