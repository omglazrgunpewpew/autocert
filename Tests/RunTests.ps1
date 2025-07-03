Param()
Import-Module Pester -ErrorAction Stop
Invoke-Pester -Script "$PSScriptRoot/Autocert.Tests.ps1" -EnableExit

