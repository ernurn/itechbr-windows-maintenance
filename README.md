# 🚀 ITechBR Windows Maintenance

![PowerShell](https://img.shields.io/badge/PowerShell-Automation-blue)
![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-blue)
![Status](https://img.shields.io/badge/Status-Active-success)
![License](https://img.shields.io/badge/License-MIT-green)

Automated Windows maintenance, repair and update workflow for technical service and enterprise infrastructure environments.

---

## 👨‍💻 Author

**Ernesto Nurnberg**  
IT Infrastructure & Technical Support Specialist  
Founder of ITechBR  
Windows Maintenance Automation  

---

## 🚀 Overview

This project provides a **real-world automation workflow** for Windows maintenance and repair.

Designed to:
- Reduce manual maintenance time
- Standardize technician workflows
- Improve system reliability
- Automate Windows repair and update routines
- Generate structured logs for traceability

---

## 🧠 Key Highlights

- **Enterprise Deployment Ready:** Designed to seamlessly integrate into corporate OS staging, provisioning pipelines, and reference machine engineering.
- **Headless Operation Flow:** Fully scriptable and policy-compliant automation that runs cleanly via administrative shells or remote deployment agents.
- **Multi-Language Parsing Resiliency:** Resolves OS language locale boundaries during runtime text audits, ensuring reliable diagnostic capture across localized Windows installations.
- **Telemetry-Ready Records:** Generates persistent, auditable execution logs optimized for compliance mapping and hardware degradation analysis.

---

## 🛠 Technologies Used

- PowerShell
- Batch scripting
- Windows Update API
- DISM
- SFC
- CHKDSK
- Windows 10 / 11

---

## ⚙️ Features

### 🧼 System Cleanup
- Temporary files cleanup
- User temp directory cleanup
- Prefetch cleanup
- Recycle bin cleanup
- Windows Update cache cleanup
- Windows catalog cache cleanup
- Structured logging with timestamps

---

### 🔄 Windows Update Automation
- Automatic update search
- Automatic update download
- Automatic update installation
- EULA acceptance when required
- Restart detection after update installation
- Fully unattended execution

---

### 🛠 Windows Repair
- DISM RestoreHealth execution
- DISM StartComponentCleanup execution
- System File Checker scan using `sfc /scannow`
- System volume scan using `Repair-Volume`
- Error handling and execution status reporting

---

### 💽 Disk Maintenance
- Deep CHKDSK scheduling for the next boot
- Automatic restart when required
- Post-restart CHKDSK result collection
- CHKDSK output appended to the same maintenance log

---

### ⚡ Power Configuration Handling
- Temporarily disables hibernation during maintenance
- Temporarily disables Fast Startup during maintenance
- Restores hibernation before finishing
- Restores Fast Startup before finishing
- Prevents clients from noticing slower boot behavior after service

---

## 🧾 Logging

A structured logging system is implemented across the workflow.

- Logs are stored in: `C:\Logs`
- Files are generated using timestamps
- Maintenance logs use the `itechbr` prefix
- CHKDSK results are appended after restart when available

Example:
```text
C:\Logs
└── itechbr-20260515_081500.log
```

This enables:
- Full execution traceability
- Easier troubleshooting
- Historical tracking of maintenance tasks
- Clear service reporting

---

## 🔁 Automated Workflow

The script executes a deterministic, sequential pipeline designed for unattended operations:

```text
[Init] ──> [Power Staging] ──> [Deep Clean] ──> [OS Patching] ──> [Image Repair] ──> [Disk Check] ──> [Rollback State]
```

1. **Privilege & Environment Initialization:** Validates administrative privileges, generates a timestamped execution log path (C:\Logs), and provisions background logging structures.
2. **Power Subsystem Staging:** Temporarily captures initial state and suspends Hibernation and Fast Startup (powercfg.exe) to isolate the OS from hybrid boot locks during maintenance tasks.
3. **Storage & Cache Purging:** Executes automated system volume cleanup (cleanmgr.exe /sagerun) and purges temporary files, system distribution caches, and update download folders.
4. **Automated OS Patching:** Interface orchestration with the Windows Update API to search, accept EULAs, download, and install pending security updates without manual prompts.
5. **Component Store Integrity Repair:** Sequential execution of DISM (/RestoreHealth and /StartComponentCleanup) to verify and fix the Windows component store metadata.
6. **System File Verification:** Runs sfc /scannow with automated localized output parsing (supporting multi-language responses) to identify and correct integrity violations.
7. **Post-Boot Disk Diagnostics:** Schedules deep file system diagnostics (CHKDSK) for the next boot sequence and registers a transient persistence script (Scheduled Task) to aggregate post-reboot disk results into the primary session log.
8. **Power Configuration Rollback:** Restores original machine hibernation and fast-startup states to preserve the native end-user boot experience.
9. **Automated Lifecycle Restart:** Flags and triggers a system reboot if updates or storage repairs require a post-execution state change.


---

## 🏭 Production Ready

This workflow is meticulously engineered for production-grade IT infrastructures:

- **Zero Prompt Intervention:** Completely unattended execution model, eliminating manual technician interaction and GUI blocking.
- **Deterministic Behavior:** Consistent execution profiles across heterogeneous hardware setups and different Windows 10/11 builds.
- **Observability Framework:** Built-in structured logging system that acts as a telemetry foundation for historical system tracking.
- **Fail-Safe State Containment:** Hardened error handling (`trap` blocks) that triggers automated environmental rollbacks (restoring power and subsystem states) if execution breaks unexpectedly.

---

## 📂 Project Structure

```text
itechbr-windows-maintenance/
│
├── README.md
├── LICENSE
├── .gitignore
│
├── scripts/
│   ├── ITech.bat
│   └── ITech-Maintenance.ps1
│
├── docs/
│   ├── changelog.md
│   └── how-it-works.md
│
└── examples/
    └── sample-log.txt
```

---

## ▶️ Usage

To execute the core automation wrapper using administrative privileges:

```bat
scripts\ITech.bat
```

Alternatively, invoke the core PowerShell execution script directly from an administrative console:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\ITech-Maintenance.ps1"
```

Script Execution Parameters
Customize execution paths via parameters:

```powershell
# Run validation self-test suite without modifying production flags
.\scripts\ITech-Maintenance.ps1 -SelfTest

# Block automatic reboots after patch orchestration finishes
.\scripts\ITech-Maintenance.ps1 -NoRestart

# Bypass patch management pipeline
.\scripts\ITech-Maintenance.ps1 -SkipWindowsUpdate

# Suppress volume sector diagnostic scheduling
.\scripts\ITech-Maintenance.ps1 -SkipChkdsk
```

Pre-Deployment Verification
It is recommended to validate execution capabilities before initiating a maintenance pipeline:

```powershell
.\scripts\ITech-Maintenance.ps1 -SelfTest
```

`-SelfTest` switch runs a synthetic test suite verifying active logging channels, native command subsystem piping capability, and administrative `powercfg.exe` visibility without invoking irreversible mutation processes (DISM, SFC, Updates, or reboots).

---

## 📌 Use Cases

### 🏢 Corporate Infrastructure & SysAdmin
- **Golden Image Staging:** Automated preparation, deep cleanup, and optimization of Windows reference machines before disk image capture (Sysprep/Clonezilla).
- **Post-Deployment Validation:** Unattended validation runner (`-SelfTest`) to ensure core OS integrity, logging access, and subsystem functionality immediately after mass provisioning.
- **Enterprise Patch Management:** Safe, unattended execution of critical Windows Updates across staged environments without requiring manual technician GUI interaction.
- **SysAdmin Staging Routines:** Automated compliance run for newly unboxed hardware units prior to enterprise enrollment.

### 🛠️ Technical Service & Field Operations
- **Preventive Maintenance Workflows:** Standardized routine for client devices to maximize operating system reliability and longevity.
- **Automated OS Recovery & Repair:** One-click deployment script to systematically isolate and repair corrupted system files (DISM/SFC) and volume errors.
- **Post-Service Optimization:** Deep system cache purging and power settings restoration to deliver a clean, fast, and stable OS to the end user.
- **Client Device Preparation:** Turnkey delivery preparation script guaranteeing optimized state delivery before client handoff.

---

## 📚 Documentation

Detailed documentation is available in the [docs](./docs) directory.

---

## ⚠️ Requirements

- Administrator privileges
- Windows 10 or Windows 11
- Windows PowerShell 5.1 or newer
- Internet connection for Windows Update

---

## 📈 Future Improvements

- Optional driver update workflow
- HTML maintenance report generation
- Remote execution support
- Asset inventory integration
- Configurable task profiles

---

## 📄 License

MIT License
