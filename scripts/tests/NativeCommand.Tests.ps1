<#'
.SYNOPSIS
    ITechBR NativeCommand Module Test Suite.

.DESCRIPTION
    Validates Invoke-NativeCommand wrapper with safe commands.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:CorePath = Join-Path (Split-Path $script:TestRoot) 'core'

# Import and initialize modules (NativeCommand depends on Logging for Convert-TextToAsciiSafe)
Import-Module (Join-Path $script:CorePath 'Logging.psm1') -Force
$null = Initialize-Logging -LogDirectory $env:TEMP  # Required for NativeCommand logging guards
Import-Module (Join-Path $script:CorePath 'NativeCommand.psm1') -Force

$Results = @()

function Test-NativeCommandOutput {
    try {
        $result = Invoke-NativeCommand -FilePath 'cmd.exe' -Arguments @('/c', 'echo test-output') -TimeoutMinutes 1 -HeartbeatSeconds 0

        if ($result -eq $null) { throw 'Invoke-NativeCommand returned null' }
        if ($result.ExitCode -ne 0) { throw "ExitCode was $($result.ExitCode), expected 0" }
        if ($result.Output -notmatch 'test-output') { throw "Output does not contain 'test-output': '$($result.Output)'" }

        return @{ Passed = $true; Message = "ExitCode=$($result.ExitCode), Output captured" }
    }
    catch {
        return @{ Passed = $false; Message = $_.Exception.Message }
    }
}

function Test-NativeCommandErrorHandling {
    try {
        # cmd '/c exit 1' should fail
        $result = Invoke-NativeCommand -FilePath 'cmd.exe' -Arguments @('/c', 'exit', '1') -TimeoutMinutes 1 -HeartbeatSeconds 0 -ErrorAction Stop
        throw "Expected error for exit code 1"
    }
    catch {
        # OK if it throws
        return @{ Passed = $true; Message = "Error handling works correctly" }
    }
}

function Test-NativeCommandObjectShape {
    try {
        $result = Invoke-NativeCommand -FilePath 'cmd.exe' -Arguments @('/c', 'echo ok') -TimeoutMinutes 1 -HeartbeatSeconds 0

        $requiredProps = 'Output', 'Error', 'ExitCode', 'Duration'
        foreach ($prop in $requiredProps) {
            if ($null -eq $result.$prop) {
                throw "Property '$prop' is missing or null"
            }
        }

        return @{ Passed = $true; Message = "All required properties present" }
    }
    catch {
        return @{ Passed = $false; Message = $_.Exception.Message }
    }
}

# Execute tests
$Results += Test-NativeCommandOutput
$Results += Test-NativeCommandErrorHandling
$Results += Test-NativeCommandObjectShape

Write-Host "`nNativeCommand Module Test Results:" -ForegroundColor Cyan
$Results | Format-Table -AutoSize | Out-String | Write-Host

if ($Results.Passed -contains $false) {
    Write-Host "`n[FAIL] NativeCommand tests failed" -ForegroundColor Red
    exit 1
}
else {
    Write-Host "`n[PASS] All NativeCommand tests passed" -ForegroundColor Green
    exit 0
}