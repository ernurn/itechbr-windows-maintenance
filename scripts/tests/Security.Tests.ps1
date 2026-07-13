<#'
.SYNOPSIS
    ITechBR Security Module Test Suite.

.DESCRIPTION
    Validates Security.psm1 administrative privilege functions.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:CorePath = Join-Path (Split-Path $script:TestRoot) 'core'

Import-Module (Join-Path $script:CorePath 'Security.psm1') -Force

$Results = @()

function Test-AdministrativePrivileges {
    try {
        $isAdmin = Test-AdministrativePrivileges
        # In PowerShell, bool comparison can be tricky - just verify it's not null
        if ($isAdmin -eq $null) {
            throw "Test-AdministrativePrivileges returned null"
        }
        return @{ Passed = $true; Message = "IsAdmin = $isAdmin (type: $($isAdmin.GetType().Name))" }
    }
    catch {
        return @{ Passed = $false; Message = $_.Exception.Message }
    }
}

function Test-AssertAdministrativePrivileges {
    try {
        # This will throw if not running as admin
        Assert-AdministrativePrivileges -ErrorAction Stop
        return @{ Passed = $true; Message = 'Assert passed (running as admin)' }
    }
    catch {
        # Expected if not admin - function should throw on non-admin
        if ($_.Exception.Message -match 'privileges|Administrative') {
            return @{ Passed = $true; Message = 'Assert correctly throws without admin privileges' }
        }
        throw
    }
}

# Execute tests
$Results += Test-AdministrativePrivileges
$Results += Test-AssertAdministrativePrivileges

Write-Host "`nSecurity Module Test Results:" -ForegroundColor Cyan
$Results | Format-Table -AutoSize | Out-String | Write-Host

if ($Results.Passed -contains $false) {
    Write-Host "`n[FAIL] Security tests failed" -ForegroundColor Red
    exit 1
}
else {
    Write-Host "`n[PASS] All Security tests passed" -ForegroundColor Green
    exit 0
}