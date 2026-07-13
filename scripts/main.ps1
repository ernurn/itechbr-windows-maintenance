<#
.SYNOPSIS
    ITechBR Windows Maintenance Framework - Core Orchestrator.

.DESCRIPTION
    Main script responsible for loading the modular framework
    infrastructure and executing the unattended Windows
    maintenance and recovery pipeline.

    The framework performs automated maintenance routines such as:
    - System inventory collection
    - Temporary files and cache cleanup
    - DISM and SFC repair workflows
    - Windows Update orchestration
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
    [switch]$SelfTest,
    [bool]$ContinueOnError = $true
)

$ErrorActionPreference = "Stop"

# ========================================
# PATH CONFIGURATION
# ========================================

$ScriptsFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$CorePath      = Join-Path $ScriptsFolder "core"
$ModulesPath   = Join-Path $ScriptsFolder "modules"

# ========================================
# FRAMEWORK LOADING - CORE LAYER FIRST
# ========================================

# Import Core modules BEFORE initialization (they provide the logging/reporting infrastructure)
$CoreModules = @(
    "Logging.psm1",
    "Reporting.psm1",
    "Security.psm1",
    "NativeCommand.psm1"
)

foreach ($module in $CoreModules) {
    $modulePath = Join-Path $CorePath $module
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force
    } else {
        throw "Critical core module missing: $modulePath"
    }
}

# NOW initialize logging and reporting (modules can now safely call Write-Log/Add-Result)
$script:LogPath = Initialize-Logging
Initialize-Reporting

# ========================================
# INITIALIZATION
# ========================================

try {
    Assert-AdministrativePrivileges

    Write-Log "===== ITECHBR MAINTENANCE STARTED ====="
    Write-Log "Framework version: 2.0.0-modular"
    Write-Log "Administrative privileges validated successfully." -Level "OK"
}
catch {
    Write-Error $_.Exception.Message
    Exit 1
}

# ========================================
# POWER STATE CAPTURE (for later restoration)
# ========================================

$script:InitialHibernationEnabled = $false
$script:InitialFastStartupValue = 1

try {
    # Check if hiberfil.sys exists to determine initial hibernation state
    $hiberFile = Get-Item -LiteralPath "$env:SystemDrive\hiberfil.sys" -Force -ErrorAction SilentlyContinue
    $script:InitialHibernationEnabled = [bool]$hiberFile
}
catch {
    Write-Log "Could not determine initial hibernation state: $($_.Exception.Message)" -Level "WARN"
}

try {
    $powerKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
    $hiberbootValue = (Get-ItemProperty -Path $powerKey -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
    if ($null -ne $hiberbootValue) {
        $script:InitialFastStartupValue = $hiberbootValue
    }
}
catch {
    Write-Log "Could not capture initial Fast Startup value: $($_.Exception.Message)" -Level "WARN"
}

$script:PowerConfigChanged = $false
$script:RestartRequired = $false
$script:ChkdskScheduled = $false

# ========================================
# POWER CONFIGURATION MANAGEMENT
# ========================================

function Disable-HibernationAndFastStartup {
    Write-Log "Disabling hibernation and Fast Startup for maintenance..." -Level "INFO"

    try {
        Invoke-NativeCommand -FilePath "powercfg.exe" -Arguments @("/h", "off") | Out-Null
        $script:PowerConfigChanged = $true
        Write-Log "Hibernation disabled." -Level "OK"
    }
    catch {
        Write-Log "Could not disable hibernation: $($_.Exception.Message)" -Level "WARN"
    }

    try {
        $powerKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
        Set-ItemProperty -Path $powerKey -Name HiberbootEnabled -Value 0 -Force -ErrorAction Stop
        Write-Log "Fast Startup disabled." -Level "OK"
    }
    catch {
        Write-Log "Could not disable Fast Startup: $($_.Exception.Message)" -Level "WARN"
    }
}

function Restore-OriginalPowerSettings {
    Write-Log "Restoring original power settings..." -Level "INFO"

    try {
        if ($script:InitialHibernationEnabled) {
            Invoke-NativeCommand -FilePath "powercfg.exe" -Arguments @("/h", "on") | Out-Null
        }
        else {
            Invoke-NativeCommand -FilePath "powercfg.exe" -Arguments @("/h", "off") | Out-Null
        }
        Write-Log "Hibernation restored to initial state." -Level "OK"
    }
    catch {
        Write-Log "Could not restore hibernation settings: $($_.Exception.Message)" -Level "WARN"
    }

    try {
        $powerKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
        Set-ItemProperty -Path $powerKey -Name HiberbootEnabled -Value $script:InitialFastStartupValue -Force -ErrorAction Stop
        Write-Log "Fast Startup restored to initial value ($($script:InitialFastStartupValue))." -Level "OK"
    }
    catch {
        Write-Log "Could not restore Fast Startup: $($_.Exception.Message)" -Level "WARN"
    }

    $script:PowerConfigChanged = $false
    $script:PowerRestored = $true
}

# ========================================
# CHECKDISK LOG COLLECTOR REGISTRATION
# ========================================

function Register-ChkdskLogCollector {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetLogPath
    )

    $collectorPath = Join-Path $env:TEMP "ITech-ChkdskCollector.ps1"
    $statePath = Join-Path $env:TEMP "ITech-MainLogPath.txt"
    $TargetLogPath | Out-File -FilePath $statePath -Encoding ASCII -Force

    $collectorScript = @'
param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,
    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Fallback: read from state file if LogPath not passed as parameter
if (-not $LogPath) {
    $statePath = Join-Path $env:TEMP "ITech-MainLogPath.txt"
    $LogPath = Get-Content -Path $statePath -Encoding ASCII -ErrorAction SilentlyContinue
}

# Validate LogPath
if (-not $LogPath) {
    Write-Host "CRITICAL: LogPath not provided and state file not found. Cannot continue." -ForegroundColor Red
    exit 1
}

function Add-Line {
    param([string]$Text)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$time [INFO] $Text"
    try {
        $line | Out-File -FilePath $LogPath -Append -Encoding ASCII -ErrorAction Stop
    }
    catch {
        $altLog = Join-Path $env:TEMP "ITech-ChkdsResults-$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        try {
            $line | Out-File -FilePath $altLog -Append -Encoding ASCII -ErrorAction Stop
            Write-Host "Wrote to alternative log: $altLog" -ForegroundColor Yellow
        }
        catch {
            Write-Host "FAILED to write to any log: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host $line
}

Start-Sleep -Seconds 90
Add-Line "===== CHKDSK RESULT AFTER RESTART ====="

# Use wevtutil instead of Get-WinEvent for non-admin compatibility
$xPath = "*[System[(EventID=1001)]]"
for ($attempt = 1; $attempt -le 15; $attempt++) {
    try {
        $eventXml = & wevtutil.exe qe Application /q:$xPath /rd:true /c:5 /f:text 2>&1 | Out-String
        if ($eventXml -and $eventXml -match "CHKDSK|NTFS|chkdsk|sistema de arquivos|checked|verificado|concluído|Não há problemas") {
            Add-Line "CHKDSK event detected via wevtutil (system language)."
            Add-Line "Raw event output follows:"
            Add-Line $eventXml
            break
        }
        Add-Line "CHKDSK event not found on attempt $($attempt). Waiting before retry."
    }
    catch {
        Add-Line "Unable to read CHKDSK event on attempt $($attempt): $($_.Exception.Message)"
    }

    Start-Sleep -Seconds 60
}

# Cleanup HKCU Run key
try {
    $startupKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    Remove-ItemProperty -Path $startupKey -Name "ITechBR-ChkdskCollector" -ErrorAction SilentlyContinue
}
catch {}

# Self-delete the collector script
try {
    if ($ScriptPath -and (Test-Path -LiteralPath $ScriptPath)) {
        Remove-Item -LiteralPath $ScriptPath -Force -ErrorAction SilentlyContinue
    }
}
catch {}
'@

    try {
        Set-Content -LiteralPath $collectorPath -Value $collectorScript -Encoding ASCII -Force
        Write-Log "CHKDSK collector script written to: $collectorPath" -Level "INFO"
    }
    catch {
        Write-Log "Failed to write CHKDSK collector script: $($_.Exception.Message)" -Level "ERROR"
        return
    }

    # Register as Scheduled Task with highest privileges (requires admin)
    try {
        $taskName = "ITechBR-ChkdskLogCollector"
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$collectorPath`" -LogPath `"$script:LogPath`" -ScriptPath `"$collectorPath`""
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
        Write-Log "CHKDSK collector registered as scheduled task: $taskName" -Level "OK"
        return
    }
    catch {
        Write-Log "Failed to register scheduled task: $($_.Exception.Message)" -Level "WARN"
    }

    # Fallback: HKCU Run registry (works without admin, but no elevation guarantee)
    try {
        $startupKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        $cmdValue = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$collectorPath`" -LogPath `"$script:LogPath`" -ScriptPath `"$collectorPath`""
        Set-ItemProperty -Path $startupKey -Name "ITechBR-ChkdskCollector" -Value $cmdValue -ErrorAction Stop
        Write-Log "CHKDSK collector registered via HKCU startup registry." -Level "OK"
    }
    catch {
        Write-Log "Failed to register CHKDSK collector fallback: $($_.Exception.Message)" -Level "WARN"
    }
}

# ========================================
# SELF-TEST MODE
# ========================================

function Invoke-SelfTest {
    Write-Log "===== ITECHBR MAINTENANCE SELF-TEST STARTED ====="

    # Test 1: Native command runner (whoami)
    Invoke-Step -Task "Self-test native command runner" -ScriptBlock {
        $result = Invoke-NativeCommand -FilePath "whoami.exe" -TimeoutMinutes 1 -HeartbeatSeconds 5
        if ([string]::IsNullOrWhiteSpace($result.Output)) {
            throw "Expected whoami.exe output was not captured"
        }
        "Native command execution and output capture OK"
    }

    # Test 2: powercfg access
    Invoke-Step -Task "Self-test powercfg command access" -ScriptBlock {
        $result = Invoke-NativeCommand -FilePath "powercfg.exe" -Arguments @("/a") -TimeoutMinutes 1 -HeartbeatSeconds 5
        if ([string]::IsNullOrWhiteSpace($result.Output)) {
            throw "Expected powercfg.exe output was not captured"
        }
        "powercfg.exe command access OK"
    } -ContinueOnError

    # Test 3: cleanmgr access (optional)
    Invoke-Step -Task "Self-test cleanmgr command access" -ScriptBlock {
        $cleanmgrPath = Join-Path $env:SystemRoot "System32\cleanmgr.exe"
        if (Test-Path $cleanmgrPath) {
            $result = Invoke-NativeCommand -FilePath $cleanmgrPath -Arguments @("/?") -TimeoutMinutes 1 -HeartbeatSeconds 5
            "cleanmgr.exe accessible"
        }
        else {
            "cleanmgr.exe not present on this Windows installation (SKIPPED)"
            Add-Result -Task "Self-test cleanmgr command access" -Status "SKIPPED" -Detail "cleanmgr.exe not found"
        }
    } -ContinueOnError

    Invoke-Step -Task "Generate self-test summary" -ScriptBlock {
        Write-Log "===== SELF-TEST SUMMARY ====="
        foreach ($result in (Get-Results)) {
            Write-Log "$($result.Status) | $($result.Task) | $($result.Detail)"
        }
        "Self-test summary written to log"
    }

    Write-Log "===== ITECHBR MAINTENANCE SELF-TEST FINISHED ====="
    Write-Host ""
    Write-Host "ITechBR self-test finished." -ForegroundColor Green
    Get-Results | Format-Table -AutoSize | Out-String | Write-Host
    Exit 0
}

# ========================================
# IMPROVED INVOKE-STEP WRAPPER
# ========================================

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Task,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [int]$TimeoutMinutes = 0,

        [bool]$ContinueOnError = $true
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        Write-Log "Starting: $Task" -Level "INFO"
        $detail = & $ScriptBlock
        $stopwatch.Stop()

        $elapsed = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
        $detailText = if ($detail) { [string]$detail } else { "Completed in $elapsed seconds" }

        Add-Result -Task $Task -Status "OK" -Detail $detailText
        Write-Log "Completed: $Task - $detailText" -Level "OK"
    }
    catch {
        $stopwatch.Stop()
        $elapsed = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
        $detailText = "$($_.Exception.Message) (after $elapsed seconds)"

        Add-Result -Task $Task -Status "ERROR" -Detail $detailText
        Write-Log "Failed: $Task - $detailText" -Level "ERROR"

        if (-not $ContinueOnError) {
            throw
        }
    }
}

# ========================================
# SELF-TEST ENTRY POINT
# ========================================

if ($SelfTest) {
    Invoke-SelfTest
}

# ========================================
# IMPORT FUNCTIONAL MODULES (after core/init)
# ========================================

Get-ChildItem -Path (Join-Path $ModulesPath "*.psm1") | ForEach-Object {
    Import-Module $_.FullName -Force
}

# ========================================
# MAIN EXECUTION PIPELINE
# ========================================

try {
    # Capture system info for logging
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    Write-Log "Computer: $env:COMPUTERNAME"
    Write-Log "User: $env:USERNAME"
    if ($osInfo) {
        Write-Log "Operating system: $($osInfo.Caption) $($osInfo.Version)"
    }

    Write-Log "Initial power state: Hibernation=$($script:InitialHibernationEnabled), FastStartup=$($script:InitialFastStartupValue)"

    # Disable power features that interfere with maintenance
    Disable-HibernationAndFastStartup

    # ========================================
    # PIPELINE PHASE 1: SYSTEM INVENTORY (initial state)
    # ========================================

    Invoke-Step -Task "System Inventory" -ScriptBlock {
        Invoke-Inventory | Out-Null
    }

    # ========================================
    # PIPELINE PHASE 2: SYSTEM CLEANUP
    # ========================================

    Invoke-Step -Task "Cleanup" -ScriptBlock {
        Invoke-SystemCleanup
    }

    # ========================================
    # PIPELINE PHASE 3: SYSTEM REPAIR (DISM/SFC/Volume)
    # ========================================

    Invoke-Step -Task "Repair" -ScriptBlock {
        Invoke-SystemRepair
    }

    # ========================================
    # PIPELINE PHASE 4: WINDOWS UPDATE
    # ========================================

    if (-not $SkipWindowsUpdate) {
        Invoke-Step -Task "Windows Update" -ScriptBlock {
            $needsRestart = Install-WindowsUpdates
            if ($needsRestart) {
                $script:RestartRequired = $true
            }
            "Windows Update phase completed. Restart required: $needsRestart"
        }
    }
    else {
        Write-Log "Windows Update skipped by -SkipWindowsUpdate parameter" -Level "WARN"
        Add-Result -Task "Windows Update" -Status "SKIPPED" -Detail "-SkipWindowsUpdate parameter"
    }

    # ========================================
    # PIPELINE PHASE 5: CHKDSK SCHEDULING
    # ========================================

    if (-not $SkipChkdsk) {
        Invoke-Step -Task "CHKDSK Scheduling" -ScriptBlock {
            Register-ChkdskLogCollector -TargetLogPath $script:LogPath

            # Schedule CHKDSK with answer piping
            $yesAnswer = if ([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq "en") { "Y" } else { "S" }
            $inputAnswers = "$yesAnswer`r`n"

            $result = Invoke-NativeCommand -FilePath "chkdsk.exe" -Arguments @($env:SystemDrive, "/F", "/R") -SuccessExitCodes @(0, 1, 2, 3) -InputText $inputAnswers -TimeoutMinutes 10 -HeartbeatSeconds 60

            # Check if CHKDSK was scheduled (look for scheduling confirmation in output)
            # EN: "will be checked", "next time", "scheduled on restart"
            # PT: "será verificado", "da próxima vez", "agendado"
            $schedMatch = $result.Output.ToLowerInvariant()
            if ($schedMatch -match "verificado|agendado|will be checked|next time|check.*restart|scheduled.*restart") {
                $script:ChkdskScheduled = $true
                $script:RestartRequired = $true
                "CHKDSK /F /R scheduled; system restart will be triggered to complete."
            }
            else {
                $script:ChkdskScheduled = $true
                "CHKDSK /F /R scheduled; result will be appended to the log after restart."
            }

            $script:ChkdskResultCollected = $false
            try {
                $collectedOutput = wevtutil.exe qe Application /q:"*[System[EventID=1001]]" /rd:true /c:1 /f:text 2>&1
                if ($collectedOutput) {
                    Write-Log "Found recent CHKDSK event in Application log." -Level "INFO"
                    $script:ChkdskResultCollected = $true
                }
            }
            catch {
                Write-Log "Could not pre-check for CHKDSK event: $($_.Exception.Message)" -Level "WARN"
            }
        }
    }
    else {
        Write-Log "CHKDSK skipped by -SkipChkdsk parameter" -Level "WARN"
        Add-Result -Task "CHKDSK Scheduling" -Status "SKIPPED" -Detail "-SkipChkdsk parameter"
    }

    # ========================================
    # SESSION CLEANUP AND SUMMARY
    # ========================================

    $resultsOutput = Join-Path $env:TEMP "itechbr-results-$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    Get-Results | Format-Table -AutoSize | Out-String | Out-File -FilePath $resultsOutput -Encoding ASCII

    Write-Log "===== ITECHBR MAINTENANCE COMPLETED ====="
    Write-Log "Results saved to: $resultsOutput"
    Write-Log "Restart required: $($script:RestartRequired)"
    Write-Log "CHKDSK scheduled: $($script:ChkdskScheduled)"
}
catch {
    Write-Log "Pipeline error: $($_.Exception.Message)" -Level "ERROR"
}
finally {
    # ========================================
    # ALWAYS RESTORE POWER SETTINGS
    # ========================================

    Restore-OriginalPowerSettings

    # ========================================
    # REBOOT HANDLING
    # ========================================

    if ($script:RestartRequired -and -not $NoRestart) {
        Write-Log "System will restart in 60 seconds to complete maintenance..." -Level "WARN"
        shutdown.exe /r /t 60 /c "ITechBR Maintenance - Restarting to complete updates"
    }
    elseif ($script:RestartRequired -and $NoRestart) {
        Write-Log "Restart required, but skipped by -NoRestart parameter" -Level "WARN"
        Write-Host "Restart required, but skipped by -NoRestart." -ForegroundColor Yellow
    }
}