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
    "TextNormalization.psm1",
    "Logging.psm1",
    "Reporting.psm1",
    "Security.psm1",
    "NativeCommand.psm1",
    "PowerManagement.psm1"
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

function Format-Duration {
    param([TimeSpan]$TimeSpan)
    # TODO: Handle OEM Code Pages for localized Windows systems (es, pt-br)
    # Characters like 'Í' in 'Índice' appear as '?' in wevtutil output
    $ts = $TimeSpan
    if ($ts.TotalHours -ge 1) {
        $hours = [int]($ts.TotalHours)
        $mins = [int]($ts.TotalMinutes) - ($hours * 60)
        $secs = [int]$ts.Seconds
        if ($secs -gt 0) {
            return "${hours}h ${mins}m ${secs}s"
        }
        return "${hours}h ${mins}m"
    } elseif ($ts.TotalMinutes -ge 1) {
        $mins = [int]($ts.TotalMinutes)
        $secs = [int]$ts.Seconds
        if ($secs -gt 0) {
            return "${mins}m ${secs}s"
        }
        return "${mins}m"
    } else {
        return "$([int]($ts.TotalSeconds))s"
    }
}

try {
    Assert-AdministrativePrivileges

    $script:StartTime = Get-Date
    Write-Log "===== ITECHBR MAINTENANCE STARTED ====="
    Write-Log "Framework version: 2.0.0"
    Write-Log "Administrative privileges validated successfully." -Level "OK"
}
catch {
    Write-Error $_.Exception.Message
    Exit 1
}

# ========================================
# POWER STATE CAPTURE (via module)
# ========================================

Initialize-PowerStateCapture

$script:PowerConfigChanged = $false
$script:RestartRequired = $false
$script:ChkdskScheduled = $false

# ========================================
# CHECKDISK LOG COLLECTOR REGISTRATION
# ========================================

function Get-ChkdskCompletionEvent {
    <#
    .SYNOPSIS
        Retrieves the most recent CHKDSK completion event from the Windows Event Log.
    .DESCRIPTION
        Queries the Application log for Event ID 1001 from the Microsoft-Windows-Wininit provider,
        which indicates a CHKDSK completion after reboot. Returns structured data for JSON/Text logging.
    .OUTPUTS
        PSCustomObject with ComputerName, Timestamp, Volume, Result, ExitCode, Duration, Message
    #>
    [CmdletBinding()]
    param()

    $xPath = "*[System[(EventID=1001) and Provider[@Name='Microsoft-Windows-Wininit']]]"

    try {
        $eventXml = & wevtutil.exe qe Application /q:$xPath /rd:true /c:1 /f:text 2>&1 | Out-String
        if (-not $eventXml -or -not $eventXml.Trim()) {
            return $null
        }

        # Parse the event text to extract key fields
        $timestamp = $null
        $volume = $null
        $result = "Unknown"
        $exitCode = $null
        $duration = $null
        $message = $eventXml.Trim()

        # Extract timestamp
        if ($eventXml -match 'Date:\s+(.+)') {
            $timestamp = $matches[1].Trim()
        }

        # Extract volume from message - supports EN and PT-BR
        # EN: "Checking file system on C:"
        # PT-BR: "Verificando o sistema de arquivos em C:"
        if ($eventXml -match '(?:Checking file system on|Verificando o sistema de arquivos em)\s+([A-Z]:)') {
            $volume = $matches[1]
        }

        # Determine result based on message content - supports EN and PT-BR
        if ($eventXml -match '(?:Windows has checked the file system and found no problems|Nao h[aá] problemas no sistema de arquivos|Não há problemas no sistema de arquivos|No problems were found)') {
            $result = "Success - No errors"
        }
        elseif ($eventXml -match '(?:Windows has made corrections to the file system|Windows fez correções no sistema de arquivos|Windows fez correções ao sistema de arquivos)') {
            $result = "Success - Errors corrected"
        }
        elseif ($eventXml -match '(?:Windows has found errors|Windows encontrou erros|CHKDSK discovered free space marked as allocated|CHKDSK descobriu espaço livre marcado como alocado)') {
            $result = "Errors found - Not corrected"
        }

        # Extract duration if present - supports EN and PT-BR (handles different accent encodings)
        # EN: "Duration: 00:00:15" or "Total duration: 6.29 minutes"
        # PT-BR: "Duração total: 6.29 minutos (377840 ms)" or "Duração da fase (...): 7.50 segundos"
        if ($eventXml -match '(?:Dura[cç][aã]o total|Total duration|Duration):\s*([0-9.]+(?:\s*(?:minutes?|minutos?|segundos?|seconds?|ms|:\d+:\d+)))') {
            $duration = $matches[1].Trim()
        }
        elseif ($eventXml -match 'Dura[cç][aã]o da fase\s*\([^)]+\):\s*([0-9.]+\s*(?:segundos?|minutes?|milissegundos?))') {
            $duration = $matches[1].Trim()
        }

        return [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            Timestamp    = $timestamp
            Volume       = $volume
            Result       = $result
            ExitCode     = $exitCode
            Duration     = $duration
            Message      = $message
        }
    }
    catch {
        Write-Log "Get-ChkdskCompletionEvent error: $($_.Exception.Message)" -Level "WARN"
        return $null
    }
}

function Export-ChkdskResult {
    <#
    .SYNOPSIS
        Exports CHKDSK result to both JSON and text formats in the dedicated CHKDSK log directory.
    .DESCRIPTION
        Creates C:\ITechBR\Logs\CHKDSK\ directory if needed, ensures SYSTEM write access,
        and writes both structured JSON and human-readable text output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ChkdskResult,

        [Parameter(Mandatory = $true)]
        [string]$MainLogPath
    )

    $chkdskLogDir = "C:\ITechBR\Logs\CHKDSK"
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $jsonPath = Join-Path $chkdskLogDir "chkdsk-result-$timestamp.json"
    $txtPath  = Join-Path $chkdskLogDir "chkdsk-result-$timestamp.txt"

    try {
        # Ensure directory exists with proper permissions for SYSTEM
        if (-not (Test-Path $chkdskLogDir)) {
            New-Item -Path $chkdskLogDir -ItemType Directory -Force | Out-Null
            # Grant SYSTEM full control (icacls may not be available in all contexts)
            try {
                icacls.exe $chkdskLogDir /grant "SYSTEM:(OI)(CI)F" /T /C /Q 2>&1 | Out-Null
            }
            catch { }
        }

        # Export JSON
        $ChkdskResult | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonPath -Encoding UTF8 -Force

        # Export formatted text
        $txtContent = @"
CHKDSK Post-Reboot Result
=========================
Computer: $($ChkdskResult.ComputerName)
Timestamp: $($ChkdskResult.Timestamp)
Volume: $($ChkdskResult.Volume)
Result: $($ChkdskResult.Result)
Duration: $($ChkdskResult.Duration)
ExitCode: $($ChkdskResult.ExitCode)

Full Event Message:
$($ChkdskResult.Message)
"@
        $txtContent | Out-File -FilePath $txtPath -Encoding ASCII -Force

        # Also append summary to main log
        $summary = "CHKDSK Result: $($ChkdskResult.Result) on $($ChkdskResult.Volume) at $($ChkdskResult.Timestamp)"
        Write-Log $summary -Level "OK"
        Add-Content -Path $MainLogPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [OK] $summary" -Encoding ASCII

        return @{ JsonPath = $jsonPath; TxtPath = $txtPath }
    }
    catch {
        Write-Log "Export-ChkdskResult error: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

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

# Use the main script's Get-ChkdskCompletionEvent logic (replicated for standalone collector)
# Normalize and filter wevtutil output for clean logging
function Convert-ToAsciiSafe {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    $normalized = $Text.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($char in $normalized.ToCharArray()) {
        $category = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($char)
        if ($category -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($char)
        }
    }
    return $sb.ToString()
}

function Get-ChkdskCompletionEventCollector {
    <#
    .SYNOPSIS
        Collector-internal version of Get-ChkdskCompletionEvent for post-reboot CHKDSK log harvesting.
    .OUTPUTS
        PSCustomObject with ComputerName, Timestamp, Volume, Result, ExitCode, Duration, Message
    #>
    $xPath = "*[System[(EventID=1001) and Provider[@Name='Microsoft-Windows-Wininit']]]"

    try {
        $eventXml = & wevtutil.exe qe Application /q:$xPath /rd:true /c:1 /f:text 2>&1 | Out-String
        if (-not $eventXml -or -not $eventXml.Trim()) {
            return $null
        }

        $timestamp = $null
        $volume = $null
        $result = "Unknown"
        $exitCode = $null
        $duration = $null
        $message = $eventXml.Trim()

        if ($eventXml -match 'Date:\s+(.+)') {
            $timestamp = $matches[1].Trim()
        }
        # Extract volume from message - supports EN and PT-BR
        # EN: "Checking file system on C:"
        # PT-BR: "Verificando o sistema de arquivos em C:"
        if ($eventXml -match '(?:Checking file system on|Verificando o sistema de arquivos em)\s+([A-Z]:)') {
            $volume = $matches[1]
        }
        # Determine result based on message content - supports EN and PT-BR
        if ($eventXml -match '(?:Windows has checked the file system and found no problems|Nao h[aá] problemas no sistema de arquivos|Não há problemas no sistema de arquivos|No problems were found)') {
            $result = "Success - No errors"
        }
        elseif ($eventXml -match '(?:Windows has made corrections to the file system|Windows fez correções no sistema de arquivos|Windows fez correções ao sistema de arquivos)') {
            $result = "Success - Errors corrected"
        }
        elseif ($eventXml -match '(?:Windows has found errors|Windows encontrou erros|CHKDSK discovered free space marked as allocated|CHKDSK descobriu espaço livre marcado como alocado)') {
            $result = "Errors found - Not corrected"
        }
        # Extract duration if present - supports EN and PT-BR (handles different accent encodings)
        # EN: "Duration: 00:00:15" or "Total duration: 6.29 minutes"
        # PT-BR: "Duração total: 6.29 minutos (377840 ms)" or "Duração da fase (...): 7.50 segundos"
        if ($eventXml -match '(?:Dura[cç][aã]o total|Total duration|Duration):\s*([0-9.]+(?:\s*(?:minutes?|minutos?|segundos?|seconds?|ms|:\d+:\d+)))') {
            $duration = $matches[1].Trim()
        }
        elseif ($eventXml -match 'Dura[cç][aã]o da fase\s*\([^)]+\):\s*([0-9.]+\s*(?:segundos?|minutes?|milissegundos?))') {
            $duration = $matches[1].Trim()
        }

        return [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            Timestamp    = $timestamp
            Volume       = $volume
            Result       = $result
            ExitCode     = $exitCode
            Duration     = $duration
            Message      = $message
        }
    }
    catch {
        Add-Line "Get-ChkdskCompletionEventCollector error: $($_.Exception.Message)"
        return $null
    }
}

function Export-ChkdskResultCollector {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ChkdskResult,
        [Parameter(Mandatory = $true)]
        [string]$MainLogPath
    )

    $chkdskLogDir = "C:\ITechBR\Logs\CHKDSK"
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $jsonPath = Join-Path $chkdskLogDir "chkdsk-result-$timestamp.json"
    $txtPath  = Join-Path $chkdskLogDir "chkdsk-result-$timestamp.txt"

    try {
        if (-not (Test-Path $chkdskLogDir)) {
            New-Item -Path $chkdskLogDir -ItemType Directory -Force | Out-Null
            try {
                icacls.exe $chkdskLogDir /grant "SYSTEM:(OI)(CI)F" /T /C /Q 2>&1 | Out-Null
            }
            catch { }
        }

        $ChkdskResult | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonPath -Encoding UTF8 -Force

        $txtContent = @"
CHKDSK Post-Reboot Result
=========================
Computer: $($ChkdskResult.ComputerName)
Timestamp: $($ChkdskResult.Timestamp)
Volume: $($ChkdskResult.Volume)
Result: $($ChkdskResult.Result)
Duration: $($ChkdskResult.Duration)
ExitCode: $($ChkdskResult.ExitCode)

Full Event Message:
$($ChkdskResult.Message)
"@
        $txtContent | Out-File -FilePath $txtPath -Encoding ASCII -Force

        $summary = "CHKDSK Result: $($ChkdskResult.Result) on $($ChkdskResult.Volume) at $($ChkdskResult.Timestamp)"
        Add-Line $summary
        Add-Content -Path $MainLogPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [OK] $summary" -Encoding ASCII

        return @{ JsonPath = $jsonPath; TxtPath = $txtPath }
    }
    catch {
        Add-Line "Export-ChkdskResultCollector error: $($_.Exception.Message)"
        return $null
    }
}

Start-Sleep -Seconds 90
Add-Line "===== CHKDSK RESULT AFTER RESTART ====="

# Use wevtutil with Wininit provider filter for CHKDSK events
for ($attempt = 1; $attempt -le 15; $attempt++) {
    try {
        $chkdskEvent = Get-ChkdskCompletionEventCollector
        if ($chkdskEvent) {
            Add-Line "CHKDSK completion event detected (Provider: Microsoft-Windows-Wininit)."
            Add-Line "Results summary:"
            Export-ChkdskResultCollector -ChkdskResult $chkdskEvent -MainLogPath $LogPath
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

# Self-delete the collector script - use absolute path
try {
    $absolutePath = $null
    if ($ScriptPath -and (Test-Path -LiteralPath $ScriptPath)) {
        $absolutePath = Resolve-Path -LiteralPath $ScriptPath | Select-Object -ExpandProperty Path
    }
    elseif ($MyInvocation.MyCommand.Path -and (Test-Path -LiteralPath $MyInvocation.MyCommand.Path)) {
        $absolutePath = Resolve-Path -LiteralPath $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty Path
    }

    if ($absolutePath -and (Test-Path -LiteralPath $absolutePath)) {
        Remove-Item -LiteralPath $absolutePath -Force -ErrorAction SilentlyContinue
        Add-Line "Collector script self-deleted: $absolutePath"
    }
    else {
        Add-Line "WARNING: Could not resolve collector script path for self-deletion"
    }
}
catch {
    Add-Line "WARNING: Collector self-deletion failed: $($_.Exception.Message)"
}
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

        $elapsed = $stopwatch.Elapsed.TotalSeconds

        if ($detail -is [System.Management.Automation.PSObject]) {
            # Extract detail from module return object if it has a Detail property
            $detailText = if ($detail.Detail) { $detail.Detail } else { "Completed" }
        } else {
            $detailText = if ($detail) { [string]$detail } else { "Completed" }
        }

        Add-Result -Task $Task -Status "OK" -Detail $detailText
        Write-Log "Completed: $Task" -Level "OK"
        Write-Log ("Duration: {0}" -f (Format-Duration -TimeSpan $stopwatch.Elapsed)) -Level "INFO"
    }
    catch {
        $stopwatch.Stop()
        $detailText = $_.Exception.Message

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
            # PT: "sera verificado", "da proxima vez", "agendado"
            # ES: "sera comprobado", "la proxima vez", "comprobado" (works with corrupted encoding)
            $schedMatch = $result.Output.ToLowerInvariant()
            if ($schedMatch -match "verificado|agendado|comprobado|sera|proxima vez|will be checked|next time|check.*restart|scheduled.*restart") {
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

    # Write executive summary using Format-Duration
    $endTime = Get-Date
    $durationText = Format-Duration -TimeSpan ($endTime - $script:StartTime)

    Write-Log "========================="
    Write-Log "Maintenance Summary"
    Write-Log "========================="

    $results = Get-Results
    $summaryTasks = @(
        @{ Name = "Inventory";      Pattern = "Inventory" },
        @{ Name = "Cleanup";        Pattern = "Cleanup|Temp|Recycle|CleanMgr|Update Cache" },
        @{ Name = "Repair";         Pattern = "Repair|DISM|SFC|Volume" },
        @{ Name = "Windows Update"; Pattern = "Windows Update" },
        @{ Name = "CHKDSK";         Pattern = "CHKDSK" }
    )

    foreach ($taskInfo in $summaryTasks) {
        $matched = $results | Where-Object { $_.Task -match $taskInfo.Pattern } | Select-Object -Last 1
        if ($matched) {
            if ($matched.Task -match "CHKDSK") {
                $status = if ($script:ChkdskScheduled) { "Scheduled" } else { $matched.Status }
            } else {
                # Priority: ERROR > WARN > OK > SKIPPED
                $hasError = $results | Where-Object { ($_.Task -match $taskInfo.Pattern) -and ($_.Status -eq "ERROR") }
                $hasWarn = $results | Where-Object { ($_.Task -match $taskInfo.Pattern) -and ($_.Status -eq "WARN") }
                if ($hasError) { $status = "ERROR" }
                elseif ($hasWarn) { $status = "WARN" }
                else { $status = $matched.Status }
            }
        } else {
            $status = if ($taskInfo.Name -eq "CHKDSK" -and $script:SkipChkdsk) { "Skipped" } else { "N/A" }
        }
        Write-Log ("{0,-20} {1}" -f $taskInfo.Name, $status)
    }

    Write-Log "----------------------------------------"
    Write-Log "Total duration: $durationText"
    $restartText = if ($script:RestartRequired) { "YES" } else { "NO" }
    Write-Log "Restart required: $restartText"

    Write-Log "===== ITECHBR MAINTENANCE COMPLETED ====="
    Write-Log "Results saved to: $resultsOutput"
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