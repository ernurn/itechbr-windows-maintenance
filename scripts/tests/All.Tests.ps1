<#'
.SYNOPSIS
    ITechBR All Modules Test Orchestrator.

.DESCRIPTION
    Runs all test suites for core and functional modules.
#>

[CmdletBinding()]
param(
    [switch]$ContinueOnError
)

$script:TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$AllTests = @(
    'Core.Tests.ps1',      # Logging, Security, Reporting, NativeCommand, TextNormalization
    'Diagnostics.Tests.ps1',
    'Inventory.Tests.ps1',
    'Cleanup.Tests.ps1'
    # Note: CHKDSK, Repair, WindowsUpdate require admin or reboot - see individual test files
)

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "    RUNNING ALL MODULE TESTS                " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$AllPassed = $true
foreach ($test in $AllTests) {
    $testPath = Join-Path $script:TestRoot $test
    if (-not (Test-Path $testPath)) {
        Write-Host "Missing test: $test" -ForegroundColor Yellow
        continue
    }

    Write-Host "`n>>> Running $test" -ForegroundColor Yellow
    $output = & $testPath *>&1
    $output | Write-Host
    if ($LASTEXITCODE -ne 0) {
        $AllPassed = $false
        if (-not $ContinueOnError) {
            Write-Host "[FAIL] Stopping due to error in $test" -ForegroundColor Red
            exit 1
        }
    }
}

Write-Host "`n=============================================" -ForegroundColor Cyan
if ($AllPassed) {
    Write-Host "         ALL TESTS PASSED                   " -ForegroundColor Green
    exit 0
}
else {
    Write-Host "         SOME TESTS FAILED                   " -ForegroundColor Red
    exit 1
}