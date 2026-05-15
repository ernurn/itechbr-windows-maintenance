# 📈 Changelog

All notable changes to this project are documented in this file.

This project follows a simple versioning style focused on practical maintenance releases.

---

## Unreleased

### 🧯 Improved

- Added heartbeat logging for long-running native commands
- Added timeout handling for DISM, SFC and CHKDSK scheduling commands
- Set SFC timeout to 90 minutes with progress messages every 2 minutes
- Prevented log messages from polluting internal task result summaries
- Added `-SelfTest` mode for safe validation before full maintenance
- Added `powercfg.exe` access validation to self-test mode
- Implemented stable command execution through `cmd.exe` with temporary output files
- Improved command output decoding for localized Windows command output
- Added automatic UTF-16 command output detection for SFC logs
- Improved SFC result detection for localized Windows output
- Improved CHKDSK scheduled-answer handling for localized systems
- Improved CHKDSK post-restart event collection with broader Wininit event lookup
- Added fatal error protection to restore power settings when possible

---

## v1.0.0

Initial public release of **ITechBR Windows Maintenance**.

### 🚀 Added

- Project structure for GitHub publication
- Professional README documentation
- MIT license
- `.gitignore` for logs and local editor files
- Example maintenance log
- Technical workflow documentation

---

### 🧰 Maintenance Automation

- Added unattended Windows maintenance script
- Added batch launcher for simplified execution
- Added administrator privilege detection
- Added automatic elevation when required
- Added structured step execution wrapper
- Added execution result tracking

---

### 🧾 Logging

- Added timestamped log generation in `C:\Logs`
- Added `itechbr-YYYYMMDD_HHMMSS.log` naming format
- Added command output logging
- Added warning and error logging
- Added final task summary
- Added support for post-restart CHKDSK result logging

---

### 🧼 Cleanup

- Added Windows temporary files cleanup
- Added user temporary files cleanup
- Added Prefetch cleanup
- Added recycle bin cleanup
- Added Windows Update download cache cleanup
- Added Windows catalog cache cleanup
- Added Windows Update service stop/start handling during cache cleanup

---

### 🔄 Windows Update

- Added native Windows Update API integration
- Added automatic update search
- Added automatic update download
- Added automatic update installation
- Added EULA acceptance when required
- Added restart requirement detection
- Added per-update result logging
- Added `-SkipWindowsUpdate` parameter

---

### 🛠 Windows Repair

- Added DISM RestoreHealth execution
- Added DISM StartComponentCleanup execution
- Added SFC verification using `sfc /scannow`
- Added multi-language SFC result detection
- Added command exit code handling

---

### 💽 Disk Maintenance

- Added system volume scan using `Repair-Volume`
- Added deep CHKDSK scheduling for next boot
- Added `chkdsk /F /R` automation
- Added temporary scheduled task for CHKDSK result collection
- Added automatic cleanup of the temporary scheduled task
- Added `-SkipChkdsk` parameter

---

### ⚡ Power Configuration

- Added temporary hibernation disablement during maintenance
- Added temporary Fast Startup disablement during maintenance
- Added hibernation restoration before finishing
- Added Fast Startup restoration before finishing
- Added power configuration status logging

---

### 🔁 Restart Handling

- Added automatic restart when required
- Added 60-second restart delay
- Added restart cancellation note in the log
- Added `-NoRestart` parameter

---

## Planned

Future improvements may include:

- HTML maintenance report generation
- Configurable maintenance profiles
- Optional driver update workflow
- Remote execution support
- Asset inventory integration
- Centralized log collection
