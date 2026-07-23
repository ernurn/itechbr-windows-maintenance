# 📈 Changelog

All notable changes to this project are documented in this file.

This project adheres to a standard semantic-inspired versioning model (`MAJOR.MINOR.PATCH`) tailored for infrastructure automation lifecycles.

---

## [v2.2.0] - 2026-07-23

### 🏗 Refactor
- **Extracted power management to dedicated core module** - Created `scripts/core/PowerManagement.psm1` consolidating all power configuration logic
- **Removed duplicate implementations** - Eliminated `Get-HibernationState`, `Set-FastStartup`, `Disable-HibernationAndFastStartup`, `Restore-OriginalPowerSettings` from `main.ps1` and `ITech-Maintenance.ps1`
- **Centralized state capture and restoration** - Single source of truth for hibernation/FastStartup state via `Initialize-PowerStateCapture` and `Restore-OriginalPowerSettings`

### 🛡 Safety Improvements
- **Added restoration validation** - `Restore-OriginalPowerSettings` now verifies hibernation and Fast Startup values match expected state after restoration
- **Warning on mismatch** - Logs WARN if actual state differs from expected after restoration, without aborting maintenance

### 🔧 Internal
- **New helper functions** - `Get-HibernationState`, `Get-FastStartupState`, `Set-FastStartup`, `Initialize-PowerStateCapture` exported for reusability
- **Module scope isolation** - PowerManagement guards `Write-Log`/`Invoke-NativeCommand` calls with `Get-Command` checks for standalone loading support

### ✅ Tests
- All core and module test suites pass (except pre-existing TextNormalization failures)
- Self-test mode functional for both `main.ps1` and `ITech-Maintenance.ps1`

---

## [v2.1.0] - 2026-07-23

### 🏗 Refactor
- **Consolidated native command output handling** - Single `Read-CommandOutputFile` implementation in `NativeCommand.psm1`
- **Encoding detection unified** - UTF-8 (BOM/no-BOM), UTF-16 LE/BE (BOM/no-BOM), OEM fallback in one place
- **Removed duplicate implementations** - Eliminated `Read-RepairOutputFile` (Repair.psm1) and legacy `Read-CommandOutputFile` (ITech-Maintenance.ps1)

### ✅ Tests
- **8 encoding test cases** added to `NativeCommand.Tests.ps1` covering ASCII, UTF-8, UTF-16 LE (with/without BOM), UTF-8 with BOM, OEM, missing/empty files
- All core and module test suites pass

### 🔧 Internal
- Added `Test-ValidUtf8` helper for robust UTF-8 without BOM detection
- NativeCommand now exports `Read-CommandOutputFile` publicly

---

## [v2.0.1] - 2026-07-23

### Fixed
- Hardened CHKDSK post-reboot log collector.
- Added Wininit provider filtering to avoid EventID 1001 false positives.
- Added structured CHKDSK JSON/TXT reports.
- Improved SYSTEM execution compatibility.
- Improved collector self-deletion reliability.

### Validation
- Tested Scheduled Task execution as SYSTEM.
- Verified CHKDSK EventID 1001 XPath filtering.
- Verified PT-BR event parsing.

---

## [v2.0.0] - 2026-07-03

### 🏗 Architecture
- **Modular architecture completed** - Full migration from monolithic to modular structure
- **Legacy pipeline fully migrated** - `scripts/main.ps1` is now the functional orchestrator
- **Core modules decoupled** - Logging, Reporting, Security, NativeCommand as independent units
- **Functional modules isolated** - CleanUp, Diagnostics, WindowsUpdate, Repair, Inventory with private helpers

### 🚀 Added
- **Inventory subsystem** - Hardware, OS, software, and asset collection via `Invoke-Inventory`
- **Clear-WindowsUpdateCache** - Automated cache purging for SoftwareDistribution and catroot2
- **Standardized NativeCommand API** - Returns PSCustomObject with .Output, .Error, .ExitCode, .Duration properties

### 🧯 Robustness & Core Engineering
- **Inline helper functions** - Resolved scope issues in NativeCommand.psm1 for reliable module loading
- **Enhanced error containment** - Global try/catch/finally with guaranteed power state restoration
- **Multi-session compatibility** - Modules can be loaded independently without initialization order issues

---

## [v1.1.0] - 2026-05-19

### 🚀 Added
- **Synthetic Validation Suite (`-SelfTest`):** Implemented a non-destructive runtime validation mode to audit environmental access, logging channels, and core administrative privileges (`powercfg.exe`) before initiating state mutation.
- **Heartbeat Logging Mechanism:** Added active background telemetry loops providing millisecond-precision execution heartbeats during long-running native Windows commands.
- **Fault-Tolerant State Rollback:** Hardened execution boundaries with global exception containment (`trap` blocks) to guarantee structural power state reversion (`powercfg`) in the event of fatal pipeline crashes.

### 🧯 Robustness & Core Engineering
- **Asynchronous Execution Timeouts:** Integrated strict lifecycle timeouts across high-latency diagnostics (DISM, SFC, and CHKDSK subsystems). Set a 90-minute operational ceiling for SFC accompanied by telemetry pulses every 2 minutes.
- **Isolated Pipeline Reporting:** Sanitized internal logging logic to prevent sub-task console pollution from breaking structural result data summaries.
- **Decoupled Command Execution Wrapper:** Stabilized legacy native command translation utilizing transient `cmd.exe` processing pipes and deterministic intermediate tracking files.

### 🌐 Localization & Subsystem Resiliency
- **Multi-Language Buffer Decoding:** Advanced output parsing algorithm to automatically detect and decode multi-language, localized Windows terminal streams.
- **UTF-16 Adaptive Encoding Check:** Implemented localized byte-order-mark (BOM) sniffing to reliably parse automated Windows SFC system logs.
- **Dynamic CHKDSK Prompt Orchestration:** Hardened automated interaction loops for next-boot disk schedules across systems utilizing non-English locales.
- **Advanced Wininit Telemetry Harvesting:** Expanded post-reboot event monitoring algorithms to deeply query and aggregate fragmented Wininit cluster health states back into the centralized execution log.

---

## [v1.0.0] - 2026-04-15

Initial production release of **ITechBR Windows Maintenance**.

### 🚀 Added
- Comprehensive infrastructure automation engine core.
- Production-grade architectural `README.md` documentation.
- Project structure layout designed for open-source GitHub distribution.
- MIT License compliance framework and standardized `.gitignore` templates.

### ⚙️ Automation & Pipeline Core
- Unattended headless execution pipeline wrapper.
- Low-level Batch abstraction layer to enforce administrative token elevation.
- Deterministic step runner with independent result tracking.

### 🧼 Purge & Telemetry Operations
- ISO-standardized logging engine targeting `C:\Logs` with unique timestamp session isolation.
- Automatic service orchestration (Stop/Start lifecycles) for native update delivery nodes during deeply-nested cache purges.
- Automated system storage minimization routines spanning Temp, Prefetch, and cleanmgr profiles.

### 🔄 Patch & Repair Management
- Programmatic COM Interop mapping targeting the native Windows Update API.
- Non-interactive EULA evaluation, batch update injection, and post-installation lifecycle analysis.
- Multi-tier OS core recovery utilizing sequential DISM component store payload minimization and SFC boundaries.

### 💽 Storage Layer & Power Management
- Next-boot volume validation architecture using high-privilege `Repair-Volume` and scheduled automated CHKDSK injection hooks.
- Transient Scheduled Task provisioning designed to harvest standalone event streams post-boot with self-cleaning logic.
- Isolation workflows to mitigate Fast Startup and Hybrid Sleep kernel locks during deployment sequences.

---

## 🔮 Planned Roadmap

Future improvements targeted for subsequent minor/major release milestones:

- **Observability:** Rich-text HTML interactive maintenance analytics and status report generation.
- **Scalability:** WinRM integration for multi-node remote orchestration and configuration scaling.
- **Logging format:** Enhanced JSON output for SIEM integration.