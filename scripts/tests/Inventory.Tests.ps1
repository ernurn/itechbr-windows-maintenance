<#'
.SYNOPSIS
    ITechBR Inventory Module Test Suite.

.DESCRIPTION
    Validates Inventory.psm1 read-only hardware/software inventory functions.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:CorePath = Join-Path (Split-Path $script:TestRoot) 'core'
$script:ModulesPath = Join-Path (Split-Path $script:TestRoot) 'modules'

# Load core modules (required by Inventory)
Import-Module (Join-Path $script:CorePath 'Logging.psm1') -Force
$null = Initialize-Logging
Import-Module (Join-Path $script:CorePath 'Reporting.psm1') -Force
Import-Module (Join-Path $script:ModulesPath 'Inventory.psm1') -Force

$Results = @()

function Test-HardwareInventory {
    try {
        $info = Get-HardwareInventory
        if ($null -eq $info) { throw 'Get-HardwareInventory returned null' }
        return @{ Passed = $true; Message = "Hardware: CPU, BIOS, Motherboard collected" }
    }
    catch { return @{ Passed = $false; Message = $_.Exception.Message } }
}

function Test-OperatingSystemInventory {
    try {
        $info = Get-OperatingSystemInventory
        if ($null -eq $info) { throw 'Get-OperatingSystemInventory returned null' }
        return @{ Passed = $true; Message = "OS Inventory: $($info.WindowsBuild)" }
    }
    catch { return @{ Passed = $false; Message = $_.Exception.Message } }
}

function Test-SoftwareInventory {
    try {
        $info = Get-SoftwareInventory
        if ($null -eq $info) { throw 'Get-SoftwareInventory returned null' }
        return @{ Passed = $true; Message = "Software: $($info.Count) items found" }
    }
    catch { return @{ Passed = $false; Message = $_.Exception.Message } }
}

function Test-InvokeInventory {
    try {
        $result = Invoke-Inventory
        if ($null -eq $result) { throw 'Invoke-Inventory returned null' }
        return @{ Passed = $true; Message = "Inventory completed successfully" }
    }
    catch { return @{ Passed = $false; Message = $_.Exception.Message } }
}

# Execute tests
$Results += Test-HardwareInventory
$Results += Test-OperatingSystemInventory
$Results += Test-SoftwareInventory
$Results += Test-InvokeInventory

Write-Host "`nInventory Module Test Results:" -ForegroundColor Cyan
$Results | Format-Table -AutoSize | Out-String | Write-Host

if ($Results.Passed -contains $false) {
    Write-Host "`n[FAIL] Inventory tests failed" -ForegroundColor Red
    exit 1
}
else {
    Write-Host "`n[PASS] All Inventory tests passed" -ForegroundColor Green
    exit 0
}