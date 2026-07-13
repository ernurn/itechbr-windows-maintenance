<#'
.SYNOPSIS
    ITechBR Core Modules Test Orchestrator.

.DESCRIPTION
    Runs all individual core module tests (Logging, Security, Reporting, NativeCommand).
#>

[CmdletBinding()]
param(
    [switch]$ContinueOnError
)

$ErrorActionPreference = 'Stop'

$script:TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$CoreTests = @(
    'Logging.Tests.ps1',
    'Security.Tests.ps1',
    'Reporting.Tests.ps1',
    'NativeCommand.Tests.ps1'
)

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "    RUNNING CORE MODULE TESTS               " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$AllPassed = $true
foreach ($test in $CoreTests) {
    $testPath = Join-Path $script:TestRoot $test
    if (-not (Test-Path $testPath)) {
        Write-Host "Missing test: $test" -ForegroundColor Red
        $AllPassed = $false
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
    Write-Host "         ALL CORE TESTS PASSED              " -ForegroundColor Green
    exit 0
}
else {
    Write-Host "         SOME CORE TESTS FAILED             " -ForegroundColor Red
    exit 1
}