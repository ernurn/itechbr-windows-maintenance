# <#
.SYNOPSIS
    Generic wrapper for executing native Windows commands within the ITechBR framework.

.DESCRIPTION
    Provides a consistent pattern for invoking external executables, capturing stdout/stderr,
    handling timeouts, heartbeat logging, and returning deterministic result objects.
    The function is safe to call from other modules and respects the framework's logging
    and reporting guards, allowing it to be used in isolated test contexts.

    Public entry point: `Invoke-NativeCommand`
#>

Set-StrictMode -Version Latest

# ========================================
# LOGGING / REPORTING GUARDS
# ========================================

function script:Write-NativeLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet("INFO", "OK", "WARN", "ERROR", "SKIPPED")]
        [string]$Level = "INFO"
    )
    if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Message $Message -Level $Level
    }
}

function script:Write-NativeResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Task,
        [Parameter(Mandatory = $true)]
        [ValidateSet("INFO", "OK", "WARN", "ERROR", "SKIPPED")]
        [string]$Status,
        [string]$Detail = ""
    )
    if (Get-Command -Name Add-Result -ErrorAction SilentlyContinue) {
        Add-Result -Task $Task -Status $Status -Detail $Detail
    }
}

# ========================================
# INTERNAL HELPERS
# ========================================

function script:Join-CommandArguments {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )
    $escaped = foreach ($argument in $Arguments) {
        if ($argument -match '[\s"]') {
            '"' + ($argument -replace '"', '""') + '"'
        } else {
            $argument
        }
    }
    return ($escaped -join ' ')
}

function script:Read-CommandOutputFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) { return "" }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Count -eq 0) { return "" }
    if ($bytes.Count -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes)
    }
    $sampleLength = [Math]::Min($bytes.Count, 200)
    $nullOddBytes = 0
    for ($i = 1; $i -lt $sampleLength; $i += 2) {
        if ($bytes[$i] -eq 0) { $nullOddBytes++ }
    }
    if ($sampleLength -gt 20 -and $nullOddBytes -gt ($sampleLength / 4)) {
        return [System.Text.Encoding]::Unicode.GetString($bytes)
    }
    $oemEncoding = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
    return $oemEncoding.GetString($bytes)
}

# ========================================
# PUBLIC FUNCTION
# ========================================

function Invoke-NativeCommand {
    <#
    .SYNOPSIS
        Executes a native Windows executable with optional arguments, timeout, and heartbeat.
    .DESCRIPTION
        The wrapper creates temporary stdout/stderr files, streams progress via the framework's
        logging guard, and throws on non‑successful exit codes. It returns a hashtable containing
        `StdOut`, `StdErr`, `ExitCode`, and `Duration` for deterministic downstream consumption.
    .PARAMETER FilePath
        Full path to the executable to run.
    .PARAMETER Arguments
        Array of argument strings – will be escaped according to PowerShell rules.
    .PARAMETER SuccessExitCodes
        Array of exit codes considered successful (default: 0).
    .PARAMETER InputText
        Optional multiline string that will be piped into the process' STDIN.
    .PARAMETER TimeoutMinutes
        If >0, the process will be terminated after the given number of minutes.
    .PARAMETER HeartbeatSeconds
        Interval in seconds for periodic INFO log entries while the process runs.
    .EXAMPLE
        $result = Invoke-NativeCommand -FilePath "C:\Windows\System32\ping.exe" -Arguments @("-n", "4", "8.8.8.8") -TimeoutMinutes 1
        if ($result.ExitCode -eq 0) { Write-Host "Ping succeeded" }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [int[]]$SuccessExitCodes = @(0),
        [string]$InputText = $null,
        [int]$TimeoutMinutes = 0,
        [int]$HeartbeatSeconds = 300
    )

    # Build command line safely
    $argumentString = Join-CommandArguments -Arguments $Arguments
    $commandId = [guid]::NewGuid().ToString('N')
    $stdoutPath = Join-Path $env:TEMP "itechbr-native-$commandId.out"
    $stderrPath = Join-Path $env:TEMP "itechbr-native-$commandId.err"
    $started = Get-Date
    $lastHeartbeat = $started

    $targetCommand = if ([string]::IsNullOrWhiteSpace($argumentString)) {
        "\"$FilePath\""
    } else {
        "\"$FilePath\" $argumentString"
    }

    if (-not [string]::IsNullOrEmpty($InputText)) {
        $inputLines = $InputText -split "(`r`n|`n|`r)" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $echoBlock = ($inputLines | ForEach-Object { "echo $_" }) -join " & "
        $targetCommand = "($echoBlock) | $targetCommand"
    }

    $commandLine = "$targetCommand > `"$stdoutPath`" 2> `"$stderrPath`""
    $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/d /s /c `"$commandLine`"" -PassThru -WindowStyle Hidden

    while (-not $process.WaitForExit(1000)) {
        $elapsed = (Get-Date) - $started
        if ($HeartbeatSeconds -gt 0 -and ((Get-Date) - $lastHeartbeat).TotalSeconds -ge $HeartbeatSeconds) {
            Write-NativeLog "[Heartbeat] $FilePath still running after $([math]::Round($elapsed.TotalMinutes,1)) minutes" -Level "INFO"
            $lastHeartbeat = Get-Date
        }
        if ($TimeoutMinutes -gt 0 -and $elapsed.TotalMinutes -ge $TimeoutMinutes) {
            try { $process.Kill() } catch {}
            throw "$FilePath timed out after $TimeoutMinutes minute(s)"
        }
    }
    $process.WaitForExit()
    $process.Refresh()

    $stdout = Read-CommandOutputFile -Path $stdoutPath
    $stderr = Read-CommandOutputFile -Path $stderrPath

    if ($stdout.Trim()) { Write-NativeLog "$FilePath stdout:`n$($stdout.Trim())" -Level "INFO" }
    if ($stderr.Trim()) { Write-NativeLog "$FilePath stderr:`n$($stderr.Trim())" -Level "WARN" }

    if ($process.ExitCode -notin $SuccessExitCodes) {
        throw "$FilePath exited with code $($process.ExitCode)"
    }

    $duration = (Get-Date) - $started
    return @{ StdOut = $stdout; StdErr = $stderr; ExitCode = $process.ExitCode; Duration = $duration }
}

Export-ModuleMember -Function Invoke-NativeCommand
