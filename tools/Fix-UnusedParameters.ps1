#!/usr/bin/env pwsh
<#
    .SYNOPSIS
        Identifies and optionally removes unused parameters from PowerShell functions

    .DESCRIPTION
        Scans PowerShell files for unused parameters and can automatically remove them
        or add suppress messages for parameters that are intentionally unused (like
        plugin framework parameters)

    .PARAMETER WhatIf
        Shows what changes would be made without applying them

    .PARAMETER TargetFiles
        Specific files to process. If not specified, processes non-module files

    .PARAMETER AddSuppressionComments
        Adds PSScriptAnalyzer suppression comments instead of removing parameters
#>

[CmdletBinding()]
param(
    [CmdletBinding(SupportsShouldProcess)] param(),
    [string[]]$TargetFiles,
    [switch]$AddSuppressionComments
)

$ErrorActionPreference = 'Stop'

# Parameters that are commonly unused but required by frameworks
$FrameworkParameters = @(
    'ExtraParams',      # DNS plugin framework
    'ExtraConnectParams', # DNS plugin framework
    'Body',             # HTTP plugin framework
    'RecordName',       # DNS plugin framework (some plugins)
    'TxtValue',         # DNS plugin framework (some plugins)
    'Domain'            # HTTP plugin framework
)

[OutputType([object[]])]\n    function Get-UnusedParameters {
    param(
        [string]$FilePath
    )

    try {
        $content = Get-Content -Path $FilePath -Raw
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$null, [ref]$null)
        $unusedParams = @()

        # Find all function definitions
        $functions = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

        foreach ($function in $functions) {
            if ($function.Parameters) {
                foreach ($param in $function.Parameters) {
                    $paramName = $param.Name.VariablePath.UserPath

                    # Check if parameter is used in function body
                    $paramPattern = "\`$$paramName\b"
                    $functionBody = $function.Body.ToString()

                    if ($functionBody -notmatch $paramPattern) {
                        $unusedParams += @{
                            FunctionName     = $function.Name
                            ParameterName    = $paramName
                            LineNumber       = $param.Extent.StartLineNumber
                            IsFrameworkParam = $paramName -in $FrameworkParameters
                            ParameterAst     = $param
                        }
                    }
                }
            }
        }

        return $unusedParams
    }
    catch {
        Write-Warning -Message "
        return @()
    }
}

[OutputType([object[]])]\n    function Add-SuppressionComment {
    param(
        [string]$FilePath,
        [object]$UnusedParam,
        [CmdletBinding(SupportsShouldProcess)] param()
    )

    $content = Get-Content -Path $FilePath
    $lineIndex = $UnusedParam.LineNumber - 1

    # Add suppression comment above the parameter
    $suppressionComment = "        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '$($UnusedParam.ParameterName)', Justification = 'Framework parameter')]"

    if ($WhatIf) {
        Write-Warning -Message "
    }
    else {
        # Insert the suppression comment
        $newContent = @()
        $newContent += $content[0..($lineIndex - 1)]
        $newContent += $suppressionComment
        $newContent += $content[$lineIndex..($content.Length - 1)]

        Set-Content -Path $FilePath -Value $newContent -Encoding UTF8
        Write-Information -MessageData " -InformationAction Continue
    }
}

[OutputType([object[]])]\n    function Remove-UnusedParameter {
    param(
        [string]$FilePath,
        [object]$UnusedParam,
        [CmdletBinding(SupportsShouldProcess)] param()
    )

    if ($WhatIf) {
        Write-Error -Message " -InformationAction Continue
    }
    else {
        # This is complex - for now just report
        Write-Warning -Message "
    }
}

# Main execution
try {
    $rootPath = Split-Path -Parent $PSScriptRoot

    # Determine files to process
    if ($TargetFiles) {
        $filesToProcess = $TargetFiles | ForEach-Object {
            if (Test-Path $_) { $_ } else { Join-Path $rootPath $_ }
        }
    }
    else {
        # Process AutoCert files, exclude Modules directory
        $filesToProcess = Get-ChildItem -Path $rootPath -Recurse -Include "*.ps1" |
        Where-Object {
            $_.FullName -notlike "*\Modules\*" -and
            $_.Name -ne "Build-Validation.ps1"  # Skip build script with intentionally unused params
        } |
        Select-Object -ExpandProperty FullName
    }

    Write-Information -MessageData " -InformationAction Continue
    Write-Information -MessageData " -InformationAction Continue======================================" -InformationAction Continue

    if ($WhatIf) {
        Write-Warning -Message "
    }

    $totalUnusedParams = 0
    $frameworkParams = 0
    $filesProcessed = 0

    foreach ($file in $filesToProcess) {
        Write-Progress -Activity "Processing Files" -Status "Checking $file" -PercentComplete (($filesProcessed / $filesToProcess.Count) * 100)

        $unusedParams = Get-UnusedParameters -FilePath $file

        if ($unusedParams.Count -gt 0) {
            Write-Information -MessageData " -InformationAction Continue

            foreach ($param in $unusedParams) {
                $totalUnusedParams++

                if ($param.IsFrameworkParam) {
                    $frameworkParams++
                    Write-Warning -Message "

                    if ($AddSuppressionComments) {
                        Add-SuppressionComment -FilePath $file -UnusedParam $param -WhatIf:$WhatIf
                    }
                }
                else {
                    Write-Error -Message "
                    Remove-UnusedParameter -FilePath $file -UnusedParam $param -WhatIf:$WhatIf
                }
            }
        }

        $filesProcessed++
    }

    Write-Progress -Activity "Processing Files" -Completed

    Write-Information -MessageData " -InformationAction Continue
    Write-Information -MessageData " -InformationAction ContinueFiles processed: $filesProcessed" -InformationAction Continue
    Write-Information -MessageData " -InformationAction Continue
    Write-Information -MessageData " -InformationAction ContinueFramework parameters: $frameworkParams" -InformationAction Continue
    Write-Information -MessageData " -InformationAction Continue

    if ($WhatIf) {
        Write-Warning -Message "
        Write-Warning -Message "Consider using -AddSuppressionComments for framework parameters"
    }

}
catch {
    Write-Error -Message "Failed to process unused parameters: $($_.Exception.Message)"
    exit 1
}






