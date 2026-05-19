# 🔁 Architecture & Subsystem Deep Dive

Technical overview of the internal execution engines and sub-architectures driving the ITechBR Windows Maintenance workflow.

This document serves as an architectural blueprint outlining the underlying Windows API interactions, transient states, and error-containment structures driving this automation framework.

---

## 🚀 Deterministic Execution Pipeline

The orchestration engine sequences tasks through a rigid linear pipeline designed to ensure environmental isolation and predictability:

```text
[Launch] ──> [Elevation] ──> [Telemetry Init] ──> [State Staging] ──> [Cache Purge] ──> [Patching API] ──> [Component Repair] ──> [Sector Diagnostics] ──> [State Rollback] ──> [Lifecycle Boot]
```

1. **Launcher Ingestion:** Initial initialization phase driven by the low-overhead Batch wrapper or direct administrative PowerShell instantiation.
2. **Security Token Evaluation:** Validation of administrative security contexts (Elevated Token Validation).
3. **Telemetry Session Provisioning:** Generation of unique ISO-timestamped transaction records inside the targeted logging node.
4. **Subsystem State Staging:** Transient capture and suspension of native kernel boot states (`powercfg.exe`).
5. **Storage Minimization & Cache Purging:** State teardown of Windows Update transactional repositories and temporary staging structures.
6. **Programmatic Update Orchestration:** Downstream interaction with the native Windows Update Agent (WUA) engine.
7. **Component Store Integrity Recovery:** Deep metadata servicing via Deployment Image Servicing and Management (DISM) pipelines.
8. **Protected System File Verification:** Structural auditing of OS protected boundaries via the System File Checker (SFC).
9. **Online/Offline Storage Sector Diagnostics:** Sequential cluster mapping and next-boot diagnostic registration.
10. **Environmental State Rollback:** Re-enforcement of baseline system-wide power configuration matrix states.
11. **Automated Lifecycle Reboot Execution:** Safe, non-blocking hardware restart orchestration if a post-execution state change is requested by the underlying engines.
12. **Asynchronous Event Harvesting:** Post-reboot extraction of kernel diagnostic streams for unified record aggregation.

---

## 🧪 Synthetic Validation Suite (`-SelfTest`)

Before committing targeting nodes to destructive or high-latency maintenance tasks, the automation engine exposes a synthetic dry-run capability:

```powershell
.\scripts\ITech-Maintenance.ps1 -SelfTest
```

The `-SelfTest` framework explicitly asserts the validity of the following logical constraints without mutating the operating system state:
- **I/O Subsystem Health:** Validates read/write stream execution over the logging target path.
- **Native Command Routing:** Exercises terminal output redirection, background pipeline parsing, and explicit input-piping capability.
- **API Boundary Accessibility:** Audits programmatic token access to underlying utilities including `powercfg.exe`.
- **Telemetry Compilation:** Tests final session report matrix building logic under mock parameters.

Bypassed layers during self-test routines include the WUA Engine, DISM servicing, SFC routines, Next-Boot CHKDSK staging, and automatic lifecycle reboots.

---

## 👮 Privileged Access Token Enforcement

The infrastructure engine interfaces deeply with protected kernel boundaries, requiring an elevated security context (**High Mandatory Level Token**).

If invoked from a non-privileged context, the execution core utilizes a self-bootstrapping routine to request explicit elevation:

```powershell
Start-Process powershell.exe -ArgumentList "..." -Verb RunAs
```

Administrative enforcement is strictly required to satisfy downstream dependencies:
- **Service Control Manager Interface:** Explicitly required to mutate states on critical infrastructure nodes (`wuauserv`, `bits`, `cryptsvc`).
- **WUA COM Interface Interop:** High-level system interaction boundaries for local patch configuration.
- **Protected File System Access:** Permissions to write and scan within `%SystemRoot%` parameters and manage system hive registry trees.
- **Transient Task Provisioning:** High-privilege access needed to register context-independent jobs inside the Windows Task Scheduler.

---

## 🧾 Telemetry Structure & Log Strategy

The framework implements a fully non-interactive logging model, generating granular execution data optimized for operational auditing.

Upon execution, the script guarantees the existence of a centralized repository:

```text
C:\Logs
```

Transaction records enforce an ISO-compliant, collision-resistant identifier footprint:

```text
itechbr-YYYYMMDD_HHMMSS.log
```

The runtime reporting engine maps the following metrics continuously:
- **Host Telemetry Matrix:** Tracks Execution Timestamps, NetBIOS Hostnames, Security Security Identifiers (SIDs), and exact Windows NT Kernel builds.
- **Substream Interception:** Redirects and encodes `STDOUT` and `STDERR` pipelines from external native executables into text payloads.
- **Error Propagation Data:** Logs detailed runtime exceptions, command exit-codes, and structural execution warnings.
- **Aggregated Event Logs:** Integrates asynchronous post-reboot disk health reports into a unified terminal file.

---

## ⚡ Power Subsystem Staging & Kernel Locks

To ensure high-throughput operation, prevent unexpected power state transitions during high-latency servicing, and insulate tasks from file-system lockups, the script executes transient system modifications.

The core utilizes the Windows Power Configuration manager (`powercfg.exe`) to capture existing baselines and temporarily disable:
- **ACPI Hibernation States (`S4` Sleep Lifecycle)**
- **Windows Fast Startup Engine (Hybrid Boot Framework)**

```text
[Baseline State Engine] ──> Capture ──> Pause Locks ──> [Run Main Pipeline] ──> Rollback State ──> [Native Experience]
```

By ensuring these mechanisms are restored during the environmental rollback phase prior to script termination, the workflow guarantees zero persistent degradation of the native end-user boot experience once delivery operations finish.

---

## 🧼 Transactional Storage Purging

The cleanup engine follows a destructive maintenance pattern to free volume space and remediate corrupted Windows Update download loops.

### Targets for Purging
- **System Transient Cache Directories:** Structural metadata purges over `%SystemRoot%\Temp` and `%TEMP%` parameters.
- **OS Layout Staging Caches:** Cleaning of Windows Prefetch nodes.
- **WUA Distribution Stores:** Total payload evacuation of `%SystemRoot%\SoftwareDistribution\Download` and `%SystemRoot%\System32\catroot2`.

### State Dependency Model
To clear locked handles within the Windows Update cache targets, the script interfaces with the Service Control Manager to programmatically stall target infrastructure nodes, executing clean operations only when services report an absolute stopped status:

```text
[Stop Services: bits, wuauserv, cryptsvc] ──> Purge Target Storage Arrays ──> [Restart Services to Active Baselines]
```

---

## 🔄 Automated Patch Management Engine (WUA API)

The updating subsystem orchestrates patch management via high-level COM Interop mappings targeting the native Microsoft Update Architecture interfaces.

```text
[Microsoft.Update.Session] ──> CreateUpdateSearcher() ──> CreateUpdateDownloader() ──> CreateUpdateInstaller()
```

The programmatic loop executes automated pipeline steps completely headless:
1. **Target Querying:** Polls configured Windows Update servers for pending applicable payloads.
2. **Licensing Evaluation:** Programmatically analyzes and flags EULA acceptance requirements without prompting for GUI confirmation.
3. **Asynchronous Download:** Ingests payloads into the local storage layer via background transaction handling.
4. **Synchronous Installation:** Commits updates sequentially and parses underlying HRESULT returns for tracking summaries.
5. **Reboot Requirement Trapping:** Evaluates immediate post-update environmental statuses to trigger down-stream reboot sequences.

---

## 🛠 System Core Servicing (DISM & SFC Integration)

The operating system repair pipeline uses a layered approach to target both metadata store issues and individual file system anomalies.

### Tier 1: Windows Component Store Servicing (DISM)
The automation core triggers the deployment servicing model to resolve component metadata mismatch vulnerabilities:

```powershell
DISM /Online /Cleanup-Image /RestoreHealth
```

Following health restoration, the store executes payload optimization routines to compress, isolate, and remove obsolete packages:

```powershell
DISM /Online /Cleanup-Image /StartComponentCleanup
```

### Tier 2: Protected File System Verification (SFC)
Once the underlying component store baseline is healthy, the engine executes system file validation:

```powershell
sfc /scannow
```

The execution block incorporates specialized regex parsers to trap and evaluate terminal output codes, handling multi-language localized responses cleanly to register accurate integrity flags inside the primary logs.

---

## 💽 Storage Subsystem Diagnostics & CHKDSK Harvesting

Volume evaluation operates on a split-horizon pipeline model that handles diagnostics both online (live session) and offline (pre-boot sequence).

### Phase 1: High-Throughput Online Scanning
The engine executes a non-blocking diagnostic pass using storage API abstraction:

```powershell
Repair-Volume -DriveLetter C -Scan
```

### Phase 2: Offline Next-Boot Diagnostic Registration
To perform deep sector checking and physical cluster remediation, the script registers an offline volume repair operation:

```powershell
chkdsk C: /F /R
```

Since the logical volume `C:` maintains active system runtime handles, the script programmatically pipes automated affirmative answers to the OS input capture line, scheduling deep sector analysis for the immediate subsequent boot cycle.

---

## 🧩 Asynchronous Post-Reboot Log Harvesting

A core engineering highlight of this framework is its ability to centralize data across system reboots, preventing fragmented reports.

```text
[System Reboot] ──> [Boot CHKDSK Execution] ──> [Wininit Event Registry] ──> [ITechBR Scheduled Task Execution] ──> Log Aggregation
```

To harvest the outputs of the pre-boot CHKDSK execution, the script injects a high-privilege transient engine task prior to reboot:

```text
Task Name: ITechBR-ChkdskLogCollector
```

### Operational Lifecycle Post-Reboot:
1. **Delayed Ingestion Initialization:** The task triggers at user-session initialization, waiting for structural Windows event log layers to settle into stable run states.
2. **Event Database Extraction:** Programmatically queries the local Application log channel, querying for deep Wininit event signatures corresponding to the latest storage diagnostic execution.
3. **Data Serialization:** Extracts the raw textual report array and appends it directly back into the primary historical maintenance log file (`itechbr-*.log`).
4. **Self-Destruct Optimization Sequence:** The task automatically unregisters itself from the system Task Scheduler, purging its footprint from the system state cleanly.

---

## 🧯 Fault-Tolerant Exception Containment

The automation layer operates under defensive programming paradigms, implementing structured boundary wrappers to protect nodes from unstable halfway states.

```text
[Pipeline Failure] ──> Execution Exception Caught ──> [Global Trap Handler] ──> Restore Power Subsystem ──> Close File Handles ──> Graceful Exit
```

- **Isolated Step Wrapping:** Independent sub-tasks run inside enclosed execution evaluation blocks. Non-fatal system failures in auxiliary cleanup routines will not stall core update or repair tasks.
- **Global Abort State Trap:** Implements active `trap` and scope-wide exception containment strategies. If a critical script crash occurs while power configuration locks are suspended, the core catches the failure signal, triggers immediate state restoration for ACPI states (`powercfg`), flushes open file I/O locks, and exits gracefully to preserve host integrity.

---

## 🧠 Structural Analytics Report

Upon pipeline completion, the engine renders an analytical breakdown of operational task metrics. This telemetry object translates into actionable data points indicating pipeline success levels, pending update state tracking, filesystem integrity outcomes, and system reboot signals, driving standard compliance logging across IT infrastructure models.