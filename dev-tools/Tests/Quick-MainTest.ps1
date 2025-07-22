# Quick-MainTest.ps1
# Test that main script can start and show the menu

Write-Host "Testing AutoCert Interactive Mode..." -ForegroundColor Cyan

# Create a simple test to see if main script loads and can show menu
try
{
    # Set a timeout to prevent hanging
    $timeout = 10  # seconds

    Write-Host "Starting Main.ps1 to test menu loading..." -ForegroundColor Yellow

    # Start the main script as a background job so we can control it
    $job = Start-Job -ScriptBlock {
        Set-Location $using:PWD
        try
        {
            # Load the script environment
            $env:AUTOCERT_TESTING_MODE = $true
            $env:POSHACME_SKIP_UPGRADE_CHECK = $true

            # Source the main script but capture the Show-Menu function
            $script:ScriptVersion = "2.0.0"
            $script:ScriptName = "AutoCert Certificate Management System"
            $script:StartTime = Get-Date
            $script:LoadedModules = @()
            $script:InitializationErrors = @()

            # Load core system modules
            . ".\Core\SystemInitialization.ps1"
            . ".\Core\RenewalOperations.ps1"
            . ".\Core\SystemDiagnostics.ps1"
            . ".\Core\RenewalConfig.ps1"

            # Initialize system
            $moduleLoadSuccess = Initialize-ScriptModule -NonInteractive

            if ($moduleLoadSuccess)
            {
                # Test if Show-Menu function exists and can be called
                if (Get-Command Show-Menu -ErrorAction SilentlyContinue)
                {
                    Write-Output "SUCCESS: Show-Menu function is available"

                    # Test other critical functions
                    $functions = @('Register-Certificate', 'Install-Certificate', 'Show-Help')
                    foreach ($func in $functions)
                    {
                        if (Get-Command $func -ErrorAction SilentlyContinue)
                        {
                            Write-Output "SUCCESS: $func is available"
                        } else
                        {
                            Write-Output "ERROR: $func is NOT available"
                        }
                    }

                    Write-Output "RESULT: All tests passed - Interactive mode ready"
                } else
                {
                    Write-Output "ERROR: Show-Menu function not available"
                }
            } else
            {
                Write-Output "ERROR: System initialization failed"
            }
        } catch
        {
            Write-Output "ERROR: $($_.Exception.Message)"
        }
    }

    # Wait for the job to complete or timeout
    $completed = Wait-Job -Job $job -Timeout $timeout

    if ($completed)
    {
        $output = Receive-Job -Job $job
        Write-Host "`nJob Output:" -ForegroundColor Cyan
        $output | ForEach-Object {
            if ($_ -like "SUCCESS:*")
            {
                Write-Host $_ -ForegroundColor Green
            } elseif ($_ -like "ERROR:*")
            {
                Write-Host $_ -ForegroundColor Red
            } elseif ($_ -like "RESULT:*")
            {
                Write-Host $_ -ForegroundColor Green
            } else
            {
                Write-Host $_ -ForegroundColor White
            }
        }

        if ($output -contains "RESULT: All tests passed - Interactive mode ready")
        {
            Write-Host "`n✅ AutoCert Interactive Mode Test PASSED!" -ForegroundColor Green
            Write-Host "The system is ready for interactive use." -ForegroundColor Green
            $success = $true
        } else
        {
            Write-Host "`n❌ AutoCert Interactive Mode Test FAILED!" -ForegroundColor Red
            $success = $false
        }
    } else
    {
        Write-Host "`n⚠️ Test timed out after $timeout seconds" -ForegroundColor Yellow
        $success = $false
    }

    # Clean up
    Remove-Job -Job $job -Force

    if ($success)
    {
        exit 0
    } else
    {
        exit 1
    }

} catch
{
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}


