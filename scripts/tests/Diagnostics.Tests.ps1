<#'
.SYNOPSIS
    ITechBR Diagnostics Module Test Suite.

.DESCRIPTION
    Validates Diagnostics.psm1 read-only system inspection functions.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:CorePath = Join-Path (Split-Path $script:TestRoot) 'core'
$script:ModulesPath = Join-Path (Split-Path $script:TestRoot) 'modules'

# Load core modules (required by Diagnostics)
Import-Module (Join-Path $script:CorePath 'Logging.psm1') -Force
$null = Initialize-Logging # Required for module guards
Import-Module (Join-Path $script:CorePath 'Reporting.psm1') -Force
Import-Module (Join-Path $script:ModulesPath 'Diagnostics.psm1') -Force

$Results = @()

function Test-OperatingSystemInfo {
    try {
        $info = Get-OperatingSystemInfo
        if ($null -eq $info) { throw 'Get-OperatingSystemInfo returned null' }
        $props = 'OSName', 'Version', 'Architecture', 'HostName', 'Model'
        foreach ($p in $props) {
            if ($null -eq $info.$p) { throw "Missing property: $p" }
        }
        return @{ Passed = $true; Message = "OS: $($info.OSName)" }
    }
    catch { return @{ Passed = $false; Message = $_.Exception.Message } }
}

function Test-MemoryInfo {
    try {
        $info = Get-MemoryInfo
        if ($null -eq $info) { throw 'Get-MemoryInfo returned null' }
        $props = 'TotalMemoryGB', 'MemoryUsagePct'
        foreach ($p in $props) {
            if ($null -eq $info.$p) { throw "Missing property: $p" }
        }
        return @{ Passed = $true; Message = "Memory: $($info.TotalMemoryGB) GB ($($info.MemoryUsagePct)%)" }
    }
    catch { return @{ Passed = $false; Message = $_.Exception.Message } }
}

function Test-DiskUsageInfo {
    try {
        $info = @(Get-DiskUsageInfo)
        if ($info.Count -eq 0) { throw 'Get-DiskUsageInfo returned empty' }
        $props = 'DriveLetter', 'TotalSizeGB', 'FreeSpacePct'
        foreach ($p in $props) {
            if ($null -eq $info[0].$p) { throw "Missing property: $p" }
        }
        return @{ Passed = $true; Message = "Disk: $($info.Count) volume(s) found" }
    }
    catch { return @{ Passed = $false; Message = $_.Exception.Message } }
}

function Test-SystemUptime {
    try {
        $info = Get-SystemUptime
        if ($null -eq $info) { throw 'Get-SystemUptime returned null' }
        return @{ Passed = $true; Message = "Uptime: $($info.Formatted)" }
    }
    catch { return @{ Passed = $false; Message = $_.Exception.Message } }
}

function Test-EventLog {
    try {
        $events = @(Get-CriticalEvents)
        return @{ Passed = $true; Message = "Events: $($events.Count) found" }
    }
    catch { return @{ Passed = $false; Message = $_.Exception.Message } }
}

# Execute tests
$Results += Test-OperatingSystemInfo
$Results += Test-MemoryInfo
$Results += Test-DiskUsageInfo
$Results += Test-SystemUptime
$Results += Test-EventLog

Write-Host "`nDiagnostics Module Test Results:" -ForegroundColor Cyan
$Results | Format-Table -AutoSize | Out-String | Write-Host

if ($Results.Passed -contains $false) {
    Write-Host "`n[FAIL] Diagnostics tests failed" -ForegroundColor Red
    exit 1
}
else {
    Write-Host "`n[PASS] All Diagnostics tests passed" -ForegroundColor Green
    exit 0
}