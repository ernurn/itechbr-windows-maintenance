<#'
.SYNOPSIS
    ITechBR Reporting Module Test Suite.

.DESCRIPTION
    Validates Reporting.psm1 in-memory result collection.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:CorePath = Join-Path (Split-Path $script:TestRoot) 'core'

# Import module first
Import-Module (Join-Path $script:CorePath 'Reporting.psm1') -Force

$Results = @()

function Test-ReportingBasics {
    try {
        # Initialize fresh state
        Initialize-Reporting

        Add-Result -Task 'Test Task' -Status 'OK' -Detail 'Test detail'
        $all = @(Get-Results)
        if ($all.Count -ne 1) { throw "Expected 1 result, got $($all.Count)" }
        if ($all[0].Task -ne 'Test Task') { throw "Task name mismatch" }

        return @{ Passed = $true; Message = "Found $($all.Count) result(s)" }
    }
    catch {
        return @{ Passed = $false; Message = $_.Exception.Message }
    }
}

function Test-StatusValidation {
    try {
        Initialize-Reporting

        # Test valid statuses
        $validStatuses = 'OK', 'WARN', 'ERROR', 'SKIPPED'
        foreach ($status in $validStatuses) {
            Add-Result -Task "Status-$status" -Status $status -Detail "Detail for $status"
        }

        $all = @(Get-Results)
        if ($all.Count -ne 4) { throw "Expected 4 results, got $($all.Count)" }

        return @{ Passed = $true; Message = "All status values validated" }
    }
    catch {
        return @{ Passed = $false; Message = $_.Exception.Message }
    }
}

# Execute tests
$Results += Test-ReportingBasics
$Results += Test-StatusValidation

Write-Host "`nReporting Module Test Results:" -ForegroundColor Cyan
$Results | Format-Table -AutoSize | Out-String | Write-Host

if ($Results.Passed -contains $false) {
    Write-Host "`n[FAIL] Reporting tests failed" -ForegroundColor Red
    exit 1
}
else {
    Write-Host "`n[PASS] All Reporting tests passed" -ForegroundColor Green
    exit 0
}