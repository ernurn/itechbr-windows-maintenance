# 🔁 How It Works

Technical overview of the ITechBR Windows Maintenance workflow.

This document explains how the script works internally, what each stage does, and why each task is included in the maintenance process.

---

## 🚀 Execution Flow

```text
Launch → Elevate → Log → Prepare → Clean → Update → Repair → Disk Check → Restore → Restart
```

```text
1. Start the batch launcher or PowerShell script
2. Check administrator privileges
3. Create a timestamped log file
4. Temporarily adjust power settings
5. Clean temporary files and update cache
6. Search, download and install Windows updates
7. Repair the Windows component store
8. Verify protected system files
9. Scan and schedule disk repair
10. Restore power settings
11. Restart automatically when required
12. Collect CHKDSK results after reboot
```

---

## 🧪 Self-Test Mode

Before running full maintenance, the script can validate its internal execution engine:

```powershell
.\scripts\ITech-Maintenance.ps1 -SelfTest
```

Self-test mode checks:
- Log creation
- Native command execution
- Command output capture
- Command input piping
- `powercfg.exe` access
- Final summary generation

It does not run Windows Update, DISM, SFC, CHKDSK or restart actions.

---

## 👮 Administrator Check

The script requires administrator privileges because it modifies system-level settings and runs Windows repair tools.

If the script is not running as administrator, it relaunches itself with elevation using PowerShell.

This is required for:
- Windows Update automation
- DISM repair
- SFC verification
- CHKDSK scheduling
- Service control
- Registry changes
- Scheduled task creation

---

## 🧾 Log Creation

At startup, the script creates a log directory:

```text
C:\Logs
```

Each execution generates a timestamped log file:

```text
itechbr-YYYYMMDD_HHMMSS.log
```

Example:

```text
C:\Logs\itechbr-20260515_081500.log
```

The log stores:
- Start and finish time
- Computer name
- Current user
- Windows version
- Each executed task
- Command output
- Warnings
- Errors
- Final summary
- CHKDSK result after restart

---

## ⚡ Temporary Power Configuration

The script temporarily disables:

- Hibernation
- Windows Fast Startup

This is done before maintenance to make Windows updates, repairs and disk checks run in a cleaner state.

Before the script finishes, both settings are enabled again.

This prevents the client from noticing slower boot behavior after the service is completed.

---

## 🧼 System Cleanup

The cleanup stage removes common temporary files and stale update data.

Processed locations:

```text
C:\Windows\Temp
%TEMP%
C:\Windows\Prefetch
C:\Windows\SoftwareDistribution\Download
C:\Windows\System32\catroot2
```

It also attempts to empty the recycle bin.

Windows Update related services are stopped before cleaning update cache folders, then started again after cleanup.

Services handled:
- `bits`
- `wuauserv`
- `cryptsvc`

---

## 🔄 Windows Update Automation

The script uses the native Windows Update COM API.

It performs:
- Update search
- EULA acceptance when required
- Update download
- Update installation
- Per-update result logging
- Restart requirement detection

If Windows Update requires a restart, the script marks the system for automatic restart at the end of the workflow.

Windows Update can be skipped with:

```powershell
.\scripts\ITech-Maintenance.ps1 -SkipWindowsUpdate
```

---

## 🛠 Windows Repair

The script runs DISM and SFC to repair Windows system health.

DISM RestoreHealth:

```powershell
DISM /Online /Cleanup-Image /RestoreHealth
```

This checks and repairs the Windows component store.

DISM component cleanup:

```powershell
DISM /Online /Cleanup-Image /StartComponentCleanup
```

This removes superseded components from previous updates.

SFC verification:

```powershell
sfc /scannow
```

This scans protected system files and attempts to repair corrupted files.

---

## 💽 Disk Maintenance

The script first scans the system volume while Windows is running:

```powershell
Repair-Volume -DriveLetter C -Scan
```

Then it schedules a deep CHKDSK repair for the next boot:

```powershell
chkdsk C: /F /R
```

`/F` fixes file system errors.  
`/R` locates bad sectors and attempts to recover readable data.

Because the system drive is in use, CHKDSK runs during the next boot.

CHKDSK scheduling can be skipped with:

```powershell
.\scripts\ITech-Maintenance.ps1 -SkipChkdsk
```

---

## 🧩 CHKDSK Result Collection

When CHKDSK runs during boot, its result is stored in the Windows Event Log.

The script creates a temporary scheduled task named:

```text
ITechBR-ChkdskLogCollector
```

After restart, this task:
- Waits briefly for Windows services to load
- Reads the latest CHKDSK result from the Application event log
- Appends the result to the original maintenance log
- Removes itself automatically

This keeps the maintenance report complete even when CHKDSK runs outside the active Windows session.

---

## 🧯 Error Handling

Each task runs inside a controlled step wrapper.

For every step, the script records:
- Start status
- Success status
- Error status
- Execution details
- Command output when available

Most maintenance tasks continue even if one non-critical step fails. This allows the technician to get the maximum possible maintenance result without stopping the entire workflow too early.

If an unexpected fatal error happens after power settings were temporarily changed, the script attempts to restore hibernation and Fast Startup before exiting.

---

## 🧠 Final Summary

At the end, the script writes a summary with:

- Task name
- Status
- Details
- Restart requirement
- CHKDSK scheduling status
- Power configuration restoration status

If a restart is required, the script schedules an automatic restart unless `-NoRestart` is used.

```powershell
.\scripts\ITech-Maintenance.ps1 -NoRestart
```

---

## ✅ Output

The final result is a complete maintenance log that can be used for:

- Technician review
- Client service records
- Troubleshooting
- Historical maintenance tracking
- Quality control
