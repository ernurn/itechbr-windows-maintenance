# 🚀 ITechBR Windows Maintenance

![PowerShell](https://img.shields.io/badge/PowerShell-Automation-blue)
![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-blue)
![Status](https://img.shields.io/badge/Status-Active-success)
![License](https://img.shields.io/badge/License-MIT-green)

Automated Windows maintenance, repair and update workflow for technical service environments.

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

## 🔁 Workflow

```text
Launch → Clean → Update → Repair → Check Disk → Restore Settings → Restart → Log Results
```

```text
1. Run launcher or PowerShell script
2. Create timestamped maintenance log
3. Temporarily adjust power settings
4. Clean temporary and update cache files
5. Search, download and install Windows updates
6. Repair Windows image with DISM
7. Verify system files with SFC
8. Scan and schedule disk repair
9. Restore hibernation and Fast Startup
10. Restart automatically when required
11. Append CHKDSK results after reboot
```

---

## 🏭 Production Ready

This workflow is designed for real-world IT environments:

- No manual interaction required
- Consistent execution across multiple machines
- Structured logging for observability
- Safe technician-friendly defaults
- Designed for repair shops and field support

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

Run the launcher as administrator:

```bat
scripts\ITech.bat
```

Or run the PowerShell script directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\ITech-Maintenance.ps1"
```

Optional parameters:

```powershell
.\scripts\ITech-Maintenance.ps1 -SelfTest
.\scripts\ITech-Maintenance.ps1 -NoRestart
.\scripts\ITech-Maintenance.ps1 -SkipWindowsUpdate
.\scripts\ITech-Maintenance.ps1 -SkipChkdsk
```

Recommended validation before running full maintenance:

```powershell
.\scripts\ITech-Maintenance.ps1 -SelfTest
```

`-SelfTest` validates logging, native command execution, command input piping and `powercfg.exe` access without running Windows Update, DISM, SFC, CHKDSK or restart actions.

---

## 📌 Use Cases

- Preventive maintenance
- Repair shop workflows
- Post-service Windows optimization
- Windows Update repair routines
- System file integrity checks
- Client device preparation before delivery

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

## 🧠 Key Highlights

- Real-world implementation
- Fully unattended maintenance workflow
- Designed for IT technicians and support teams
- Focused on reliability, consistency and traceability
- Generates professional logs for service records

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
