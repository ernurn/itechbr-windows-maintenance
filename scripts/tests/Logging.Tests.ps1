<#'
.SYNOPSIS
    ITechBR Logging Module Test Suite.

.DESCRIPTION
    Validates Logging.psm1 functionality including ASCII log creation,
    multi-level logging, and text sanitization.

.USAGE
    .\scripts\tests\Logging.Tests.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:CorePath = Join-Path (Split-Path $script:TestRoot) 'core'

# Use temp directory for test logs to avoid mixing with framework logs
$script:TestLogDir = Join-Path $env:TEMP 'ITech-Tests'
$script:OriginalLogDir = $null

# Load module
Import-Module (Join-Path $script:CorePath 'Logging.psm1') -Force

$Results = @()

function Test-LoggingBasics {
    try {
        if (-not (Test-Path $script:TestLogDir)) {
            New-Item -Path $script:TestLogDir -ItemType Directory -Force | Out-Null
        }
        $LogPath = Initialize-Logging -LogDirectory $script:TestLogDir

        Write-Log 'Test info message' -Level 'INFO'
        Write-Log 'Test ok message' -Level 'OK'
        Write-Log 'Test warn message' -Level 'WARN'
        Write-Log 'Test error message' -Level 'ERROR'

        if (-not (Test-Path $LogPath -PathType Leaf)) {
            throw "Log file not created at: $LogPath"
        }

        # Read from the specific log file we just wrote
        $content = Get-Content -Path $LogPath -Encoding ASCII
        $expectedLevels = 'INFO', 'OK', 'WARN', 'ERROR'
        foreach ($level in $expectedLevels) {
            $found = $content | Where-Object { $_ -match "\[$level\]" }
            if (-not $found) {
                throw "Expected level [$level] not found in log output"
            }
        }

        return @{ Passed = $true; Message = 'Logging basics verified' }
    }
    catch {
        return @{ Passed = $false; Message = $_.Exception.Message }
    }
}

function Test-ConvertTextToAsciiSafe {
    try {
        # Test ASCII-safe conversion (no diacritics expected in test environment)
        $result = Convert-TextToAsciiSafe -Text 'test string'
        if ($result -ne 'test string') {
            throw "Convert-TextToAsciiSafe: 'test string' -> '$result'"
        }

        return @{ Passed = $true; Message = 'Text sanitization verified' }
    }
    catch {
        return @{ Passed = $false; Message = $_.Exception.Message }
    }
}

# Execute tests
$Results += Test-LoggingBasics
$Results += Test-ConvertTextToAsciiSafe

# Report
Write-Host "`nLogging Module Test Results:" -ForegroundColor Cyan
$Results | Format-Table -AutoSize | Out-String | Write-Host

if ($Results.Passed -contains $false) {
    Write-Host "`n[FAIL] Logging tests failed" -ForegroundColor Red
    exit 1
}
else {
    Write-Host "`n[PASS] All Logging tests passed" -ForegroundColor Green
    exit 0
}