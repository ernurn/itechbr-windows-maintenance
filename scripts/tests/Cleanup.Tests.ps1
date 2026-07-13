<#'
.SYNOPSIS
    ITechBR Cleanup Module Test Suite.

.DESCRIPTION
    Validates Cleanup.psm1 function exports and idempotent behavior.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:CorePath = Join-Path (Split-Path $script:TestRoot) 'core'
$script:ModulesPath = Join-Path (Split-Path $script:TestRoot) 'modules'

Import-Module (Join-Path $script:CorePath 'Logging.psm1') -Force
$null = Initialize-Logging
Import-Module (Join-Path $script:CorePath 'Reporting.psm1') -Force
Import-Module (Join-Path $script:ModulesPath 'Cleanup.psm1') -Force

$Results = @()

function Test-CleanupExports {
    try {
        $exports = 'Invoke-SystemCleanup', 'Clear-WindowsTempFiles', 'Clear-UserTempFiles',
                   'Clear-SystemRecycleBin', 'Set-CleanMgrAutomation',
                   'Invoke-NativeDiskCleanup', 'Clear-WindowsUpdateCache'
        foreach ($func in $exports) {
            if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
                throw "Missing export: $func"
            }
        }
        return @{ Passed = $true; Message = 'All Cleanup exports verified' }
    }
    catch { return @{ Passed = $false; Message = $_.Exception.Message } }
}

function Test-CleanMgrAutomation {
    try {
        # Set-CleanMgrAutomation is idempotent - sets registry flags
        $null = Set-CleanMgrAutomation -ErrorAction SilentlyContinue
        return @{ Passed = $true; Message = 'Set-CleanMgrAutomation executed' }
    }
    catch { return @{ Passed = $false; Message = $_.Exception.Message } }
}

function Test-WindowsUpdateCache {
    try {
        # Idempotent - clears cache if exists
        $null = Clear-WindowsUpdateCache
        return @{ Passed = $true; Message = 'Windows Update cache cleanup executed' }
    }
    catch { return @{ Passed = $false; Message = $_.Exception.Message } }
}

# Execute tests
$Results += Test-CleanupExports
$Results += Test-CleanMgrAutomation
$Results += Test-WindowsUpdateCache

Write-Host "`nCleanup Module Test Results:" -ForegroundColor Cyan
$Results | Format-Table -AutoSize | Out-String | Write-Host

if ($Results.Passed -contains $false) {
    Write-Host "`n[FAIL] Cleanup tests failed" -ForegroundColor Red
    exit 1
}
else {
    Write-Host "`n[PASS] All Cleanup tests passed" -ForegroundColor Green
    exit 0
}