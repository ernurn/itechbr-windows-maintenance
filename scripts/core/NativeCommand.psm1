<#
.SYNOPSIS
    Generic wrapper for executing native Windows commands within the ITechBR framework.

.DESCRIPTION
    Provides a consistent pattern for invoking external executables, capturing stdout/stderr,
    handling timeouts, heartbeat logging, and returning deterministic result objects.
    The function is safe to call from other modules and respects the framework's logging
    and reporting guards, allowing it to be used in isolated test contexts.

    Public entry point: Invoke-NativeCommand
#>

Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot "TextNormalization.psm1") -Force

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
# PUBLIC FUNCTIONS
# ========================================

function Read-CommandOutputFile {
    <#
    .SYNOPSIS
        Reads a command output file with automatic encoding detection.
    .DESCRIPTION
        Handles UTF-8 (with/without BOM), UTF-16 LE/BE BOM, UTF-16 LE without BOM (via sampling),
        and falls back to the system's OEM code page for legacy console output.
    .PARAMETER Path
        Full path to the file to read.
    .OUTPUTS
        [string] File contents decoded as text, or empty string if file missing/empty.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($null -eq $bytes -or $bytes.Count -eq 0) {
        return ""
    }

    # Check for UTF-16 LE BOM (0xFF, 0xFE)
    if ($bytes.Count -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes)
    }

    # Check for UTF-16 BE BOM (0xFE, 0xFF)
    if ($bytes.Count -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return [System.Text.Encoding]::BigEndianUnicode.GetString($bytes)
    }

    # Check for UTF-8 BOM (0xEF, 0xBB, 0xBF)
    if ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    }

    # Detect UTF-8 without BOM: valid UTF-8 byte sequences
    if (Test-ValidUtf8 -Bytes $bytes) {
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    }

    # Detect UTF-16 LE by looking for null bytes in odd positions (sampling first 200 bytes)
    $sampleLength = [Math]::Min($bytes.Count, 200)
    $nullOddBytes = 0
    for ($i = 1; $i -lt $sampleLength; $i += 2) {
        if ($bytes[$i] -eq 0) { $nullOddBytes++ }
    }
    if ($sampleLength -gt 20 -and $nullOddBytes -gt ($sampleLength / 4)) {
        return [System.Text.Encoding]::Unicode.GetString($bytes)
    }

    # Default to OEM encoding for console output
    $oemEncoding = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
    return $oemEncoding.GetString($bytes)
}

function script:Test-ValidUtf8 {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    $i = 0
    while ($i -lt $Bytes.Count) {
        $b = $Bytes[$i]
        if ($b -lt 0x80) {
            # ASCII (1 byte)
            $i++
        }
        elseif ($b -ge 0xC2 -and $b -le 0xDF) {
            # 2-byte sequence: 110xxxxx 10xxxxxx
            if ($i + 1 -ge $Bytes.Count) { return $false }
            if ($Bytes[$i + 1] -lt 0x80 -or $Bytes[$i + 1] -gt 0xBF) { return $false }
            $i += 2
        }
        elseif ($b -ge 0xE0 -and $b -le 0xEF) {
            # 3-byte sequence: 1110xxxx 10xxxxxx 10xxxxxx
            if ($i + 2 -ge $Bytes.Count) { return $false }
            if ($b -eq 0xE0 -and $Bytes[$i + 1] -lt 0xA0) { return $false }  # overlong
            if ($b -eq 0xED -and $Bytes[$i + 1] -ge 0xA0) { return $false }  # surrogate
            if ($Bytes[$i + 1] -lt 0x80 -or $Bytes[$i + 1] -gt 0xBF) { return $false }
            if ($Bytes[$i + 2] -lt 0x80 -or $Bytes[$i + 2] -gt 0xBF) { return $false }
            $i += 3
        }
        elseif ($b -ge 0xF0 -and $b -le 0xF4) {
            # 4-byte sequence: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
            if ($i + 3 -ge $Bytes.Count) { return $false }
            if ($b -eq 0xF0 -and $Bytes[$i + 1] -lt 0x90) { return $false }  # overlong
            if ($b -eq 0xF4 -and $Bytes[$i + 1] -gt 0x8F) { return $false }  # > U+10FFFF
            if ($Bytes[$i + 1] -lt 0x80 -or $Bytes[$i + 1] -gt 0xBF) { return $false }
            if ($Bytes[$i + 2] -lt 0x80 -or $Bytes[$i + 2] -gt 0xBF) { return $false }
            if ($Bytes[$i + 3] -lt 0x80 -or $Bytes[$i + 3] -gt 0xBF) { return $false }
            $i += 4
        }
        else {
            # Invalid leading byte
            return $false
        }
    }
    return $true
}

function Invoke-NativeCommand {
    <#
    .SYNOPSIS
        Executes a native Windows executable with optional arguments, timeout, and heartbeat.
    .DESCRIPTION
        The wrapper creates temporary stdout/stderr files, streams progress via the framework's
        logging guard, and throws on non-successful exit codes. It returns a PSCustomObject
        containing Output, Error, ExitCode, and Duration for deterministic downstream consumption.
    .PARAMETER FilePath
        Full path to the executable to run.
    .PARAMETER Arguments
        Array of argument strings - will be escaped according to PowerShell rules.
    .PARAMETER SuccessExitCodes
        Array of exit codes considered successful (default: 0).
    .PARAMETER InputText
        Optional multiline string that will be piped into the process STDIN.
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

    # Helper: Escape command arguments (inline to avoid script: scope issues)
    $JoinArguments = {
        param([string[]]$ArgList)
        if ($null -eq $ArgList -or $ArgList.Count -eq 0) { return "" }
        ($ArgList | ForEach-Object {
            if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '""') + '"' } else { $_ }
        }) -join ' '
    }

    # Build command line safely
    $argumentString = & $JoinArguments $Arguments
    $commandId = [guid]::NewGuid().ToString("N")
    $stdoutPath = Join-Path $env:TEMP "itechbr-native-$commandId.out"
    $stderrPath = Join-Path $env:TEMP "itechbr-native-$commandId.err"
    $started = Get-Date
    $lastHeartbeat = $started

    $targetCommand = if ([string]::IsNullOrWhiteSpace($argumentString)) {
        "`"$FilePath`""
    } else {
        "`"$FilePath`" $argumentString"
    }

    if (-not [string]::IsNullOrEmpty($InputText)) {
        $inputLines = $InputText -split "(`r`n|`n|`r)" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $echoBlock = ($inputLines | ForEach-Object { "echo $_" }) -join " & "
        $targetCommand = "($echoBlock) | $targetCommand"
    }

    $commandLine = "$targetCommand > `"$stdoutPath`" 2> `"$stderrPath`""
    $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/d", "/s", "/c", "`"$commandLine`"" -PassThru -WindowStyle Hidden

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

    # Small delay to ensure file handles are released before reading
    Start-Sleep -Milliseconds 100

    $stdout = Read-CommandOutputFile -OutPath $stdoutPath
    $stderr = Read-CommandOutputFile -OutPath $stderrPath

    # Normalize and filter output for ASCII-safe logging (removes diacritics, suppresses progress bars)
    $safeStdout = if ($stdout -and $stdout.Trim()) { Convert-TextToAsciiSafe -Text $stdout }
    $safeStderr = if ($stderr -and $stderr.Trim()) { Convert-TextToAsciiSafe -Text $stderr }

    # Filter out progress bar lines before logging (after ASCII conversion, accents are removed)
    if ($safeStdout) {
        $filteredStdout = ($safeStdout -split "`r`n" | Where-Object {
            $line = $_.Trim()
            # Match percentage lines in en, pt-br, es (after ASCII conversion)
            $isProgress = $line -match '(Se completo|se completo).*[0-9]+\.?[0-9]*%|[0-9]+\.?[0-9]*%\s*(complet[ao]?[a-z]*|conclui[a-z]+|completed|done|comprobacion|comprobando)'
            $line -and ($line -notmatch '^\[.*[=%]+.*%.*\]$' -and -not $isProgress)
        }) -join "`r`n"
        if ($filteredStdout) {
            Write-NativeLog "$FilePath stdout:`n$($filteredStdout.Trim())" -Level "INFO"
        }
    }
    if ($safeStderr) {
        $filteredStderr = ($safeStderr -split "`r`n" | Where-Object {
            $line = $_.Trim()
            # Match percentage lines in en, pt-br, es (after ASCII conversion)
            $isProgress = $line -match '(Se completo|se completo).*[0-9]+\.?[0-9]*%|[0-9]+\.?[0-9]*%\s*(complet[ao]?[a-z]*|conclui[a-z]+|completed|done|comprobacion|comprobando)'
            $line -and ($line -notmatch '^\[.*[=%]+.*%.*\]$' -and -not $isProgress)
        }) -join "`r`n"
        if ($filteredStderr) {
            Write-NativeLog "$FilePath stderr:`n$($filteredStderr.Trim())" -Level "WARN"
        }
    }

    if ($process.ExitCode -notin $SuccessExitCodes) {
        throw "$FilePath exited with code $($process.ExitCode)"
    }

    $duration = (Get-Date) - $started
    return [pscustomobject]@{
        Output   = $stdout
        Error    = $stderr
        ExitCode = $process.ExitCode
        Duration = $duration
    }
}

Export-ModuleMember -Function Invoke-NativeCommand, Read-CommandOutputFile