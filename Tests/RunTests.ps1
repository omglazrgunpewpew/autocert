# Tests/RunTests.ps1
<#
    .SYNOPSIS
        Test runner script for AutoCert test suites.
#>

Param()
Import-Module Pester -ErrorAction Stop
Invoke-Pester -Script "$PSScriptRoot/Autocert.Tests.ps1" -EnableExit

