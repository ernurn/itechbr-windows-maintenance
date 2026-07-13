# ========================================
# LEGACY ENTRY POINT
#
# Deprecated since v2.0.0
#
# Replaced by:
# scripts/main.ps1
#
# Kept only for rollback purposes.
# ========================================
# ITechBR - Automated Windows Maintenance
# Author: Ernesto Nurnberg / ITechBR
# Purpose: Maintain, repair, and update Windows with minimal technician interaction
# Version: 1.1.1
# ========================================

[CmdletBinding()]
param(
    [switch]$NoRestart,
    [switch]$SkipWindowsUpdate,
    [switch]$SkipChkdsk,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

$LogDir = "C:\Logs"
if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogPath = Join-Path $LogDir "itechbr-$Timestamp.log"
$Results = New-Object System.Collections.Generic.List[object]
$script:RestartRequired = $false
$script:ChkdskScheduled = $false
$script:PowerRestored = $false
$script:PowerConfigChanged = $false

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "OK", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$time [$Level] $Message"
    $line | Out-File -FilePath $LogPath -Append -Encoding UTF8
    Write-Host $line
}

function Add-Result {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Task,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [string]$Detail = ""
    )

    $Results.Add([pscustomobject]@{
        Task   = $Task
        Status = $Status
        Detail = $Detail
    }) | Out-Null
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Join-CommandArguments {
    param([string[]]$Arguments)

    $escaped = foreach ($argument in $Arguments) {
        if ($argument -match '[\s"]') {
            '"' + ($argument -replace '"', '""') + '"'
        }
        else {
            $argument
        }
    }

    return ($escaped -join " ")
}

function Read-CommandOutputFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Count -eq 0) {
        return ""
    }

    if ($bytes.Count -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes)
    }

    $sampleLength = [Math]::Min($bytes.Count, 200)
    $nullOddBytes = 0
    for ($i = 1; $i -lt $sampleLength; $i += 2) {
        if ($bytes[$i] -eq 0) {
            $nullOddBytes++
        }
    }

    if ($sampleLength -gt 20 -and $nullOddBytes -gt ($sampleLength / 4)) {
        return [System.Text.Encoding]::Unicode.GetString($bytes)
    }

    $oemEncoding = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
    return $oemEncoding.GetString($bytes)
}

function Convert-TextForMatch {
    param([string]$Text)

    if ($null -eq $Text) {
        return ""
    }

    $normalized = $Text.Normalize([System.Text.NormalizationForm]::FormD)
    $builder = New-Object System.Text.StringBuilder

    foreach ($char in $normalized.ToCharArray()) {
        $category = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($char)
        if ($category -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($char)
        }
    }

    return $builder.ToString().ToLowerInvariant()
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [int[]]$SuccessExitCodes = @(0),

        [string]$InputText = $null,

        [int]$TimeoutMinutes = 0,

        [int]$HeartbeatSeconds = 300
    )

    $argumentString = Join-CommandArguments -Arguments $Arguments
    $commandId = [guid]::NewGuid().ToString("N")
    $stdoutPath = Join-Path $env:TEMP "itechbr-$commandId.out"
    $stderrPath = Join-Path $env:TEMP "itechbr-$commandId.err"
    $started = Get-Date
    $lastHeartbeat = $started

    $targetCommand = if ([string]::IsNullOrWhiteSpace($argumentString)) {
        "`"$FilePath`""
    }
    else {
        "`"$FilePath`" $argumentString"
    }

    if (-not [string]::IsNullOrEmpty($InputText)) {
        $inputLines = $InputText -split "(`r`n|`n|`r)" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $echoBlock = (($inputLines | ForEach-Object { "echo $_" }) -join " & ")
        $targetCommand = "($echoBlock) | $targetCommand"
    }

    $commandLine = "$targetCommand > `"$stdoutPath`" 2> `"$stderrPath`""
    $process = Start-Process -FilePath "cmd.exe" -ArgumentList @("/d", "/s", "/c", "`"$commandLine`"") -PassThru -WindowStyle Hidden

    while (-not $process.WaitForExit(1000)) {
        $elapsed = (Get-Date) - $started

        if ($HeartbeatSeconds -gt 0 -and ((Get-Date) - $lastHeartbeat).TotalSeconds -ge $HeartbeatSeconds) {
            Write-Log "$FilePath is still running after $([math]::Round($elapsed.TotalMinutes, 1)) minutes"
            $lastHeartbeat = Get-Date
        }

        if ($TimeoutMinutes -gt 0 -and $elapsed.TotalMinutes -ge $TimeoutMinutes) {
            try {
                $process.Kill()
            }
            catch {}

            throw "$FilePath timed out after $TimeoutMinutes minutes"
        }
    }

    $process.WaitForExit()
    $process.Refresh()

    $stdout = Read-CommandOutputFile -Path $stdoutPath
    $stderr = Read-CommandOutputFile -Path $stderrPath
    if ($null -eq $stdout) { $stdout = "" }
    if ($null -eq $stderr) { $stderr = "" }

    if ($stdout.Trim()) {
        Write-Log "$FilePath output:`n$($stdout.Trim())"
    }
    if ($stderr.Trim()) {
        Write-Log "$FilePath error output:`n$($stderr.Trim())" "WARN"
    }

    if ($process.ExitCode -notin $SuccessExitCodes) {
        throw "$FilePath finished with exit code $($process.ExitCode)"
    }

    Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Output   = $stdout
        Error    = $stderr
    }
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [switch]$ContinueOnError
    )

    Write-Log "START: $Name"
    $started = Get-Date

    try {
        $detail = & $ScriptBlock
        $elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        $detailText = if ($detail) { [string]$detail } else { "Completed in $elapsed seconds" }
        Write-Log "OK: $Name - $detailText" "OK"
        Add-Result -Task $Name -Status "OK" -Detail $detailText
    }
    catch {
        $elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        $message = "$($_.Exception.Message) (after $elapsed seconds)"
        Write-Log "ERROR: $Name - $message" "ERROR"
        Add-Result -Task $Name -Status "ERROR" -Detail $message

        if (-not $ContinueOnError) {
            throw
        }
    }
}

function Register-ChkdskLogCollector {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetLogPath
    )

    $collectorPath = Join-Path $env:TEMP "ITech-ChkdskCollector.ps1"
    $collectorScript = @'
param(
    [Parameter(Mandatory = $true)]
    [string]$LogPath
)

function Add-Line {
    param([string]$Text)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$time [INFO] $Text"
    try {
        $line | Out-File -FilePath $LogPath -Append -Encoding ASCII -ErrorAction Stop
    }
    catch {
        # Fallback 1: ensure log directory exists
        $logDir = Split-Path -Parent $LogPath
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        try {
            $line | Out-File -FilePath $LogPath -Append -Encoding ASCII
        }
        catch {
            # Fallback 2: write to alternative location if main log is inaccessible
            $altLog = Join-Path $env:TEMP "ITech-ChkdskResults-$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            try {
                $line | Out-File -FilePath $altLog -Append -Encoding ASCII -ErrorAction Stop
                Write-Host "Wrote to alternative log: $altLog" -ForegroundColor Yellow
            }
            catch {
                Write-Host "FAILED to write to any log: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    # Also write to console for visibility
    Write-Host $line
}

Start-Sleep -Seconds 90
Add-Line "===== CHKDSK RESULT AFTER RESTART ====="

for ($attempt = 1; $attempt -le 10; $attempt++) {
    try {
        # Expand time window for later attempts
        $minutesToSearch = if ($attempt -le 5) { 30 } else { 60 }
        $events = Get-WinEvent -FilterHashtable @{ LogName = "Application"; Id = 1001; StartTime = (Get-Date).AddMinutes(-$minutesToSearch) } -MaxEvents 50 -ErrorAction Stop
        $event = $events | Where-Object {
            ($_.ProviderName -eq "Microsoft-Windows-Wininit" -or $_.ProviderName -eq "Wininit") -and
            ($_.Message -match "CHKDSK|NTFS|file system|sistema de arquivos|sistema de archivos")
        } | Select-Object -First 1

        if ($event) {
            Add-Line "CHKDSK completed at: $($event.TimeCreated)"
            Add-Line "Log: $($event.LogName), Event ID: $($event.Id), Provider: $($event.ProviderName)"

            # Extract and format the CHKDSK output
            $lines = $event.Message -split "`r?`n"
            $outputLines = $lines | Where-Object {
                $_ -match "\d+ bytes|cross|mapping|clusters|sectors|correction|repaired|fixed|Windows|NTFS" -or
                $_ -match "verificado|agendado|repaired|fixed|concluído|concluido|concluído"
            }
            if ($outputLines) {
                foreach ($line in $outputLines) { Add-Line $line }
            } else {
                Add-Line ($event.Message.Trim())
            }
            break
        }

        Add-Line "CHKDSK event not found on attempt $attempt. Waiting before retry."
    }
    catch {
        Add-Line "Unable to read CHKDSK event on attempt $attempt: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds 60
}

try {
    Unregister-ScheduledTask -TaskName "ITechBR-ChkdskLogCollector" -Confirm:$false -ErrorAction SilentlyContinue
    # Self-delete the collector script - use $MyInvocation.MyCommand.Path for correct path resolution
    $scriptPath = $MyInvocation.MyCommand.Path
    if ($scriptPath -and (Test-Path $scriptPath)) {
        Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
    }
}
catch {}
'@

    Set-Content -LiteralPath $collectorPath -Value $collectorScript -Encoding ASCII -Force

    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$collectorPath`" -LogPath `"$TargetLogPath`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 15)

    Register-ScheduledTask -TaskName "ITechBR-ChkdskLogCollector" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
}

function Get-HibernationState {
    $hiberFile = Get-Item -LiteralPath "$env:SystemDrive\hiberfil.sys" -Force -ErrorAction SilentlyContinue
    return [bool]$hiberFile
}

function Set-FastStartup {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )

    $powerKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
    $value = if ($Enabled) { 1 } else { 0 }
    Set-ItemProperty -Path $powerKey -Name HiberbootEnabled -Value $value -Force
}

function Restore-OriginalPowerSettings {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$InitialHibernationEnabled,

        [Parameter(Mandatory = $true)]
        [int]$InitialFastStartupValue = 1
    )

    if ($InitialHibernationEnabled) {
        Invoke-NativeCommand -FilePath "powercfg.exe" -Arguments @("/h", "on") | Out-Null
    }
    else {
        Invoke-NativeCommand -FilePath "powercfg.exe" -Arguments @("/h", "off") | Out-Null
    }

    Set-FastStartup -Enabled ([bool]$InitialFastStartupValue)
}

function Install-WindowsUpdates {
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $searchResult = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")

    if ($searchResult.Updates.Count -eq 0) {
        return "No pending updates found"
    }

    $updates = New-Object -ComObject Microsoft.Update.UpdateColl
    $titles = New-Object System.Collections.Generic.List[string]

    for ($i = 0; $i -lt $searchResult.Updates.Count; $i++) {
        $update = $searchResult.Updates.Item($i)
        if (-not $update.EulaAccepted) {
            $update.AcceptEula()
        }
        [void]$updates.Add($update)
        $titles.Add($update.Title) | Out-Null
    }

    Write-Log "Updates found ($($updates.Count)):"
    foreach ($title in $titles) {
        Write-Log " - $title"
    }

    $downloader = $session.CreateUpdateDownloader()
    $downloader.Updates = $updates
    $downloadResult = $downloader.Download()
    Write-Log "Windows Update download result: ResultCode=$($downloadResult.ResultCode)"

    $installableUpdates = New-Object -ComObject Microsoft.Update.UpdateColl
    for ($i = 0; $i -lt $updates.Count; $i++) {
        $update = $updates.Item($i)
        if ($update.IsDownloaded) {
            [void]$installableUpdates.Add($update)
        }
        else {
            Write-Log "Update was not downloaded: $($update.Title)" "WARN"
        }
    }

    if ($installableUpdates.Count -eq 0) {
        return "Updates were found, but none were ready to install"
    }

    $installer = $session.CreateUpdateInstaller()
    $installer.Updates = $installableUpdates
    $installResult = $installer.Install()
    Write-Log "Windows Update installation result: ResultCode=$($installResult.ResultCode), RebootRequired=$($installResult.RebootRequired)"

    for ($i = 0; $i -lt $installableUpdates.Count; $i++) {
        $itemResult = $installResult.GetUpdateResult($i)
        Write-Log "Update [$($itemResult.ResultCode)] $($installableUpdates.Item($i).Title)"
    }

    if ($installResult.RebootRequired) {
        $script:RestartRequired = $true
    }

    return "Installed/processed: $($installableUpdates.Count). Restart required: $($installResult.RebootRequired)"
}

trap {
    try {
        Write-Log "FATAL: $($_.Exception.Message)" "ERROR"

        if ($script:PowerConfigChanged) {
            Write-Log "Attempting to restore hibernation and Fast Startup after fatal error" "WARN"
            Restore-OriginalPowerSettings -InitialHibernationEnabled $InitialHibernationEnabled -InitialFastStartupValue $InitialFastStartupValue
            $script:PowerConfigChanged = $false
            Write-Log "Power configuration restored after fatal error" "OK"
        }
    }
    catch {}

    exit 1
}

if ($SelfTest) {
    Write-Log "===== ITECHBR MAINTENANCE SELF-TEST STARTED ====="
    Write-Log "Log: $LogPath"

    Invoke-Step "Self-test native command runner" {
        $result = Invoke-NativeCommand -FilePath "whoami.exe" -TimeoutMinutes 1 -HeartbeatSeconds 5
        if ([string]::IsNullOrWhiteSpace($result.Output)) {
            throw "Expected whoami.exe output was not captured"
        }

        "Native command execution and output capture OK"
    }

    Invoke-Step "Self-test command input piping" {
        $result = Invoke-NativeCommand -FilePath "findstr.exe" -Arguments @(".") -InputText "SELFTEST_INPUT`r`n" -TimeoutMinutes 1 -HeartbeatSeconds 5
        if ($result.Output -notmatch "SELFTEST_INPUT") {
            throw "Expected SELFTEST_INPUT output was not captured"
        }

        "Command input piping OK"
    }

    Invoke-Step "Self-test powercfg command access" {
        $result = Invoke-NativeCommand -FilePath "powercfg.exe" -Arguments @("/a") -TimeoutMinutes 1 -HeartbeatSeconds 5
        if ([string]::IsNullOrWhiteSpace($result.Output)) {
            throw "Expected powercfg.exe output was not captured"
        }

        "powercfg.exe command access OK"
    } -ContinueOnError

    Invoke-Step "Generate self-test summary" {
        Write-Log "===== SELF-TEST SUMMARY ====="
        foreach ($result in $Results) {
            Write-Log "$($result.Status) | $($result.Task) | $($result.Detail)"
        }
        "Self-test summary written to $LogPath"
    }

    Write-Log "===== ITECHBR MAINTENANCE SELF-TEST FINISHED ====="
    Write-Host ""
    Write-Host "ITechBR self-test finished." -ForegroundColor Green
    Write-Host "Log generated: $LogPath" -ForegroundColor Cyan
    exit 0
}

if (-not (Test-IsAdministrator)) {
    $argsList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")

    if ($NoRestart) { $argsList += "-NoRestart" }
    if ($SkipWindowsUpdate) { $argsList += "-SkipWindowsUpdate" }
    if ($SkipChkdsk) { $argsList += "-SkipChkdsk" }
    if ($SelfTest) { $argsList += "-SelfTest" }

    Start-Process -FilePath "powershell.exe" -ArgumentList $argsList -Verb RunAs

    return
}

Write-Log "===== ITECHBR MAINTENANCE STARTED ====="
Write-Log "Computer: $env:COMPUTERNAME"
Write-Log "User: $env:USERNAME"
Write-Log "Operating system: $((Get-CimInstance Win32_OperatingSystem).Caption) $((Get-CimInstance Win32_OperatingSystem).Version)"
Write-Log "Log: $LogPath"

$InitialHibernationEnabled = Get-HibernationState
$InitialFastStartupValue = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled

if ($null -eq $InitialFastStartupValue) {
    $InitialFastStartupValue = 1
}
Write-Log "Initial power state: Hibernation=$InitialHibernationEnabled, FastStartup=$InitialFastStartupValue"

Invoke-Step "Temporarily disable power settings for maintenance" {
    Invoke-NativeCommand -FilePath "powercfg.exe" -Arguments @("/h", "off") | Out-Null
    Set-FastStartup -Enabled $false
    $script:PowerConfigChanged = $true
    "Hibernation and Fast Startup temporarily disabled"
} -ContinueOnError

Invoke-Step "Configure and run Windows Disk Cleanup" {
    $base = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"

    Get-ChildItem $base | ForEach-Object {
        try {
            New-ItemProperty -Path $_.PSPath -Name "StateFlags0001" -Value 2 -PropertyType DWord -Force | Out-Null
        }
        catch {}
    }

    Invoke-NativeCommand -FilePath "cleanmgr.exe" -Arguments @("/sagerun:1") -TimeoutMinutes 60 -HeartbeatSeconds 120 | Out-Null

    "CleanMgr automated cleanup completed"
} -ContinueOnError

Invoke-Step "Clean residual temporary files" {
    $paths = @(
        "C:\Windows\Temp\*",
        "$env:TEMP\*",
        "C:\Windows\SoftwareDistribution\DeliveryOptimization\*"
    )

    foreach ($path in $paths) {
        if (Test-Path $path) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    try {
        Clear-RecycleBin -Force -Confirm:$false -ErrorAction Stop
    }
    catch {
        Write-Log "Recycle Bin cleanup skipped: $($_.Exception.Message)" "WARN"
    }

    "Residual temporary files and recycle bin processed"
} -ContinueOnError

Invoke-Step "Clean Windows Update cache" {
    $services = @("bits", "wuauserv", "cryptsvc")
    foreach ($service in $services) {
        Get-Service -Name $service -ErrorAction SilentlyContinue | Where-Object {$_.Status -eq 'Running'} | Stop-Service -Force
    }

    Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\Windows\System32\catroot2\*" -Recurse -Force -ErrorAction SilentlyContinue

    foreach ($service in $services) {
        Start-Service -Name $service -ErrorAction SilentlyContinue
    }

    "Download cache and catalog cache processed"
} -ContinueOnError

if (-not $SkipWindowsUpdate) {
    Invoke-Step "Search, download, and install Windows updates" {
        Install-WindowsUpdates
    } -ContinueOnError
}
else {
    Write-Log "Windows Update skipped by -SkipWindowsUpdate parameter" "WARN"
    Add-Result -Task "Search, download, and install Windows updates" -Status "SKIPPED" -Detail "-SkipWindowsUpdate parameter"
}

Invoke-Step "Repair Windows image with DISM RestoreHealth" {
    Invoke-NativeCommand -FilePath "dism.exe" -Arguments @("/Online", "/Cleanup-Image", "/RestoreHealth") -TimeoutMinutes 180 -HeartbeatSeconds 300 | Out-Null
    "DISM RestoreHealth completed"
} -ContinueOnError

Invoke-Step "Clean Windows components with DISM StartComponentCleanup" {
    Invoke-NativeCommand -FilePath "dism.exe" -Arguments @("/Online", "/Cleanup-Image", "/StartComponentCleanup") -TimeoutMinutes 120 -HeartbeatSeconds 300 | Out-Null
    "DISM StartComponentCleanup completed"
} -ContinueOnError

Invoke-Step "Verify system files with SFC" {
    $result = Invoke-NativeCommand -FilePath "sfc.exe" -Arguments @("/scannow") -SuccessExitCodes @(0, 1, 2, 3) -TimeoutMinutes 90 -HeartbeatSeconds 120
    $output = $result.Output
    $matchOutput = Convert-TextForMatch -Text $output

    if ($matchOutput -match "found corrupt files and successfully repaired|encontro archivos danados y los reparo|encontrou arquivos corrompidos e os reparou") {
        return "SFC repaired system files"
    }
    if ($matchOutput -match "did not find any integrity violations|no encontro ninguna infraccion de integridad|nao encontrou nenhuma violacao de integridade") {
        return "SFC did not find integrity violations"
    }
    if ($matchOutput -match "could not perform|no pudo realizar|nao pode executar") {
        throw "SFC could not complete verification"
    }

    "SFC finished with exit code $($result.ExitCode). Review command output in the log"
} -ContinueOnError

Invoke-Step "Scan system volume" {
    $driveLetter = $env:SystemDrive.TrimEnd(":")
    $scanResult = Repair-Volume -DriveLetter $driveLetter -Scan -ErrorAction Continue 4>&1 | Out-String
    if ($scanResult.Trim()) {
        Write-Log $scanResult.Trim()
    }
    "Repair-Volume -Scan executed on $env:SystemDrive"
} -ContinueOnError

if (-not $SkipChkdsk) {
    Invoke-Step "Schedule deep CHKDSK for next boot" {
        Register-ChkdskLogCollector -TargetLogPath $LogPath
        $yesAnswer = if ([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq "en") { "Y" } else { "S" }
        $inputAnswers = "$yesAnswer`r`n"
        Invoke-NativeCommand -FilePath "chkdsk.exe" -Arguments @($env:SystemDrive, "/F", "/R") -SuccessExitCodes @(0, 1, 2, 3) -InputText $inputAnswers -TimeoutMinutes 10 -HeartbeatSeconds 60 | Out-Null
        $script:ChkdskScheduled = $true
        $script:RestartRequired = $true
        "CHKDSK /F /R scheduled; result will be appended to the log after restart"
    } -ContinueOnError
}
else {
    Write-Log "CHKDSK skipped by -SkipChkdsk parameter" "WARN"
    Add-Result -Task "Schedule deep CHKDSK for next boot" -Status "SKIPPED" -Detail "-SkipChkdsk parameter"
}


Invoke-Step "Restore original power settings" {
    Restore-OriginalPowerSettings -InitialHibernationEnabled $InitialHibernationEnabled -InitialFastStartupValue $InitialFastStartupValue
    $script:PowerConfigChanged = $false
    $script:PowerRestored = $true
    "Original power configuration restored"
} -ContinueOnError

Invoke-Step "Generate final summary" {
    Write-Log "===== SUMMARY ====="
    foreach ($result in $Results) {
        Write-Log "$($result.Status) | $($result.Task) | $($result.Detail)"
    }
    Write-Log "Restart required: $($script:RestartRequired)"
    Write-Log "CHKDSK scheduled: $($script:ChkdskScheduled)"
    $powerState = -not $script:PowerConfigChanged
    Write-Log "Power configuration restored: $($script:PowerRestored)"
    "Summary written to $LogPath"
}

Write-Log "===== ITECHBR MAINTENANCE FINISHED ====="
Write-Host ""
Write-Host "ITechBR maintenance finished." -ForegroundColor Green
Write-Host "Log generated: $LogPath" -ForegroundColor Cyan

if ($script:RestartRequired -and -not $NoRestart) {
    Write-Log "Automatic restart in 60 seconds. Use shutdown /a to cancel if needed." "WARN"
    shutdown.exe /r /t 60 /c "ITechBR: maintenance finished. Automatic restart to complete Windows Update/CHKDSK."
}
elseif ($script:RestartRequired -and $NoRestart) {
    Write-Log "Restart required, but skipped by -NoRestart parameter" "WARN"
    Write-Host "Restart required, but skipped by -NoRestart." -ForegroundColor Yellow
}
