<#
.SYNOPSIS
    ITechBR Windows Maintenance Framework - Core Orchestrator.

.DESCRIPTION
    Main script responsible for loading the modular framework
    infrastructure and executing the unattended Windows
    maintenance and recovery pipeline.

    The framework performs automated maintenance routines such as:
    - Windows Update orchestration
    - DISM and SFC repair workflows
    - Temporary files and cache cleanup
    - CHKDSK scheduling and log consolidation
    - Power configuration handling
    - Centralized logging and reporting

.AUTHOR
    Ernesto Nurnberg / ITechBR

.VERSION
    2.0.0-modular

.REPOSITORY
    https://github.com/ernurn/itechbr-windows-maintenance
#>

# ========================================
# PARAMETERS
# ========================================

[CmdletBinding()]
param(
    [switch]$NoRestart,
    [switch]$SkipWindowsUpdate,
    [switch]$SkipChkdsk,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

# ========================================
# PATH CONFIGURATION
# ========================================

$ScriptsFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$CorePath      = Join-Path $ScriptsFolder "core"
$ModulesPath   = Join-Path $ScriptsFolder "modules"

# ========================================
# FRAMEWORK LOADING
# ========================================

# 1. Load System Infrastructure Modules (Core)
if (Test-Path $CorePath) {
    Get-ChildItem -Path (Join-Path $CorePath "*.psm1") | ForEach-Object { 
        Import-Module $_.FullName -Force 
    }
} else {
    Write-Error "Critical core directory missing: $CorePath"
    Exit 1
}

# 2. Load Operational Logic Modules (Modules)
if (Test-Path $ModulesPath) {
    Get-ChildItem -Path (Join-Path $ModulesPath "*.psm1") | ForEach-Object { 
        Import-Module $_.FullName -Force 
    }
}


# ========================================
# INITIALIZATION
# ========================================
try {

    Assert-AdministrativePrivileges

    Initialize-Logging
    Initialize-Reporting

    Write-Log "===== ITECHBR MAINTENANCE STARTED ====="
    Write-Log "Framework version: 2.0.0-modular"
    Write-Log "Administrative privileges validated successfully." -Level "OK"

}
catch {

    Write-Error $_.Message
    Exit 1
}