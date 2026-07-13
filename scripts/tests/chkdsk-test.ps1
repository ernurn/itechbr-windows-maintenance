<#
.SYNOPSIS
    Standalone CHKDSK test script.
.DESCRIPTION
    Schedules CHKDSK /F /R and tests the post-reboot log collector.
    This script is for testing purposes only - it will schedule a restart.
.PARAMETER NoRestart
    Skip the restart (testing mode).
.EXAMPLE
    .\chkdsk-test.ps1
    .\chkdsk-test.ps1 -NoRestart
#>

[CmdletBinding()]
param(
    [switch]$NoRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Self-elevate if not running as admin
$scriptArgs = if ($NoRestart) { " -NoRestart" } else { "" }
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Elevating to Administrator..." -ForegroundColor Yellow
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`"$scriptArgs"
    $psi.Verb = "runas"
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    exit 0
}

# Import core modules
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$corePath = Join-Path (Split-Path $scriptRoot) "core"
$modulesPath = Join-Path (Split-Path $scriptRoot) "modules"

Import-Module (Join-Path $corePath "Logging.psm1") -Force
Import-Module (Join-Path $corePath "Security.psm1") -Force

# Initialize logging
$script:Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
Initialize-Logging

Write-Log "===== CHKDSK STANDALONE TEST =====" -Level "INFO"

function Register-ChkdskLogCollector {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetLogPath
    )

    $collectorPath = Join-Path $env:TEMP "ITech-ChkdskCollector-Test.ps1"
    $collectorScript = @'
param(
    [Parameter(Mandatory = $true)]
    [string]$LogPath,
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath
)

Write-Host "CHKDSK Collector starting at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "LogPath: $LogPath" -ForegroundColor Cyan

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

for ($attempt = 1; $attempt -le 15; $attempt++) {
    try {
        Write-Host "Attempt ${attempt}: Querying Application log for EventID 1001..." -ForegroundColor Gray
        $eventXml = wevtutil.exe qe Application /q:"*[System[(EventID=1001)]]" /rd:true /c:5 /f:text 2>&1 | Out-String
        Write-Host "Raw eventXml length: $($eventXml.Length) chars" -ForegroundColor Gray
        if ($eventXml -and $eventXml -match "CHKDSK|NTFS|chkdsk|sistema de arquivos|verificado|checked|concluído|concluido|Não há problemas") {
            Add-Line "CHKDSK event detected via wevtutil on attempt ${attempt}."
            Add-Line $eventXml
            Write-Host "CHKDSK result collected successfully!" -ForegroundColor Green
            break
        }
        Add-Line "CHKDSK event not found on attempt ${attempt}. Waiting before retry."
    }
    catch {
        Add-Line "Unable to read CHKDSK event on attempt ${attempt}: $($_.Exception.Message)"
        Write-Host "Error on attempt ${attempt}: $($_.Exception.Message)" -ForegroundColor Red
    }

    Start-Sleep -Seconds 60
}

# Cleanup HKCU Run key
try {
    $startupKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    Remove-ItemProperty -Path $startupKey -Name "ITechBR-ChkdskCollector-Test" -ErrorAction SilentlyContinue
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
        return $false
    }

    # Register as Scheduled Task with SYSTEM privileges for auto-execution at boot
    try {
        $taskName = "ITechBR-ChkdskLogCollector-Test"
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$collectorPath`" -LogPath `"$TargetLogPath`" -ScriptPath `"$collectorPath`""
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 20)
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        Write-Log "CHKDSK collector registered as scheduled task: $taskName (SYSTEM account)" -Level "OK"
    }
    catch {
        Write-Log "Failed to register scheduled task: $($_.Exception.Message)" -Level "WARN"
    }

    # Fallback: HKCU Run registry
    try {
        $startupKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        $cmdValue = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$collectorPath`" -LogPath `"$TargetLogPath`" -ScriptPath `"$collectorPath`""
        Set-ItemProperty -Path $startupKey -Name "ITechBR-ChkdskCollector-Test" -Value $cmdValue -ErrorAction Stop
        Write-Log "CHKDSK collector also registered via HKCU startup registry (fallback)" -Level "OK"
    }
    catch {
        Write-Log "Failed to register HKCU fallback: $($_.Exception.Message)" -Level "WARN"
    }

    return $true
}

# Register collector
$collectorRegistered = Register-ChkdskLogCollector -TargetLogPath $script:LogPath
if (-not $collectorRegistered) {
    Write-Log "Failed to register CHKDSK collector" -Level "ERROR"
    exit 1
}

# Schedule CHKDSK with answer piping
$yesAnswer = if ([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq "en") { "Y" } else { "S" }
$inputAnswers = "$yesAnswer`r`n"
Write-Log "Scheduling CHKDSK /F /R on $env:SystemDrive..." -Level "INFO"

# Use echo with pipe for chkdsk input (equivalent to Invoke-NativeCommand behavior)
$chkdskOutput = echo $inputAnswers | & chkdsk.exe $env:SystemDrive "/F" "/R" 2>&1
# Normalize output for ASCII-safe logging
$normalizedOutput = Convert-TextToAsciiSafe -Text $chkdskOutput
$normalizedOutput | Out-File -FilePath $script:LogPath -Append -Encoding ASCII

Write-Log "CHKDSK output received." -Level "INFO"

$chkdskScheduled = $false
if ($chkdskOutput -match "verificado|agendado|will be checked|next time|check.*restart|scheduled.*restart") {
    $chkdskScheduled = $true
    Write-Log "CHKDSK /F /R scheduled; system restart required." -Level "OK"
}
else {
    Write-Log "CHKDSK output unexpected - may not have been scheduled" -Level "WARN"
}

Write-Log "===== CHKDSK TEST COMPLETE =====" -Level "INFO"
Write-Log "Restart required: $chkdskScheduled" -Level "INFO"

if ($chkdskScheduled -and -not $NoRestart) {
    Write-Log "System will restart in 60 seconds..." -Level "WARN"
    shutdown.exe /r /t 60 /c "CHKDSK Test - Restarting to complete CHKDSK scan"
}
elseif ($chkdskScheduled -and $NoRestart) {
    Write-Log "Restart skipped by -NoRestart parameter" -Level "WARN"
    Write-Host "Restart required but skipped. Run without -NoRestart to trigger restart." -ForegroundColor Yellow
}