<#
.SYNOPSIS
    ITechBR Windows Repair subsystem.

.DESCRIPTION
    Provides DISM, SFC, and online volume scan routines used by the
    modular Windows maintenance framework.

    Public entry point: Invoke-SystemRepair
#>

Set-StrictMode -Version Latest

# ========================================
# LOGGING / REPORTING GUARDS
# ========================================

function script:Write-RepairLog {
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

function script:Write-RepairResult {
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

function script:Join-RepairCommandArguments {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

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

function script:Read-RepairOutputFile {
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

function script:Convert-TextForMatch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $normalized = $Text.Normalize([System.Text.NormalizationForm]::FormD)
    $builder = New-Object System.Text.StringBuilder($normalized.Length)

    foreach ($char in $normalized.ToCharArray()) {
        $category = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($char)
        if ($category -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($char)
        }
    }

    return $builder.ToString().ToLowerInvariant()
}

function script:Invoke-RepairNativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [int[]]$SuccessExitCodes = @(0),

        [int]$TimeoutMinutes = 0,

        [int]$HeartbeatSeconds = 300
    )

    $argumentString = Join-RepairCommandArguments -Arguments $Arguments
    $commandId = [guid]::NewGuid().ToString("N")
    $stdoutPath = Join-Path $env:TEMP "itechbr-repair-$commandId.out"
    $stderrPath = Join-Path $env:TEMP "itechbr-repair-$commandId.err"
    $started = Get-Date
    $lastHeartbeat = $started

    try {
        $targetCommand = if ([string]::IsNullOrWhiteSpace($argumentString)) {
            "`"$FilePath`""
        }
        else {
            "`"$FilePath`" $argumentString"
        }

        $commandLine = "$targetCommand > `"$stdoutPath`" 2> `"$stderrPath`""
        $process = Start-Process `
            -FilePath "cmd.exe" `
            -ArgumentList @("/d", "/s", "/c", "`"$commandLine`"") `
            -PassThru `
            -WindowStyle Hidden

        while (-not $process.WaitForExit(1000)) {
            $elapsed = (Get-Date) - $started

            if ($HeartbeatSeconds -gt 0 -and ((Get-Date) - $lastHeartbeat).TotalSeconds -ge $HeartbeatSeconds) {
                Write-RepairLog "$FilePath is still running after $([math]::Round($elapsed.TotalMinutes, 1)) minutes" -Level "INFO"
                $lastHeartbeat = Get-Date
            }

            if ($TimeoutMinutes -gt 0 -and $elapsed.TotalMinutes -ge $TimeoutMinutes) {
                try {
                    $process.Kill() | Out-Null
                }
                catch {}

                throw "$FilePath timed out after $TimeoutMinutes minutes"
            }
        }

        $process.WaitForExit()
        $process.Refresh()

        $stdout = Read-RepairOutputFile -Path $stdoutPath
        $stderr = Read-RepairOutputFile -Path $stderrPath
        if ($null -eq $stdout) { $stdout = "" }
        if ($null -eq $stderr) { $stderr = "" }

        if ($stdout.Trim()) {
            Write-RepairLog "$FilePath output:`n$($stdout.Trim())" -Level "INFO"
        }
        if ($stderr.Trim()) {
            Write-RepairLog "$FilePath error output:`n$($stderr.Trim())" -Level "WARN"
        }

        if ($process.ExitCode -notin $SuccessExitCodes) {
            throw "$FilePath finished with exit code $($process.ExitCode)"
        }

        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output   = $stdout
            Error    = $stderr
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function script:Get-SystemDriveLetter {
    param()

    if ([string]::IsNullOrWhiteSpace($env:SystemDrive)) {
        throw "Unable to determine %SystemDrive% for Repair-Volume scan."
    }

    return $env:SystemDrive.TrimEnd(":")
}

function script:New-RepairResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Task,

        [Parameter(Mandatory = $true)]
        [ValidateSet("INFO", "OK", "WARN", "ERROR", "SKIPPED")]
        [string]$Status,

        [string]$Detail = "",

        [int]$ExitCode = 0,

        [string]$Output = "",

        [string]$Error = "",

        [double]$ElapsedSeconds = 0,

        [bool]$RestartRequired = $false
    )

    return [pscustomobject]@{
        Task             = $Task
        Status           = $Status
        Detail           = $Detail
        ExitCode         = $ExitCode
        Output           = $Output
        Error            = $Error
        ElapsedSeconds   = $ElapsedSeconds
        RestartRequired  = $RestartRequired
    }
}

# ========================================
# DISM REPAIR
# ========================================

function Invoke-DismRestoreHealth {
    [CmdletBinding()]
    param()

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        Write-RepairLog "Starting DISM RestoreHealth..." -Level "INFO"

        $commandResult = Invoke-RepairNativeCommand `
            -FilePath "dism.exe" `
            -Arguments @("/Online", "/Cleanup-Image", "/RestoreHealth") `
            -TimeoutMinutes 180 `
            -HeartbeatSeconds 300

        if ($stopwatch.IsRunning) {
            $stopwatch.Stop()
        }

        $detail = "DISM RestoreHealth completed with exit code $($commandResult.ExitCode) in $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s."

        Write-RepairLog $detail -Level "OK"
        Write-RepairResult -Task "DISM RestoreHealth" -Status "OK" -Detail $detail

        return New-RepairResult `
            -Task "DISM RestoreHealth" `
            -Status "OK" `
            -Detail $detail `
            -ExitCode $commandResult.ExitCode `
            -Output $commandResult.Output `
            -Error $commandResult.Error `
            -ElapsedSeconds ([math]::Round($stopwatch.Elapsed.TotalSeconds, 3))
    }
    catch {
        if ($stopwatch.IsRunning) {
            $stopwatch.Stop()
        }
        $detail = $_.Exception.Message

        Write-RepairLog "DISM RestoreHealth failed: $detail" -Level "ERROR"
        Write-RepairResult -Task "DISM RestoreHealth" -Status "ERROR" -Detail $detail

        return New-RepairResult `
            -Task "DISM RestoreHealth" `
            -Status "ERROR" `
            -Detail $detail `
            -ElapsedSeconds ([math]::Round($stopwatch.Elapsed.TotalSeconds, 3))
    }
}

function Invoke-DismStartComponentCleanup {
    [CmdletBinding()]
    param()

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        Write-RepairLog "Starting DISM StartComponentCleanup..." -Level "INFO"

        $commandResult = Invoke-RepairNativeCommand `
            -FilePath "dism.exe" `
            -Arguments @("/Online", "/Cleanup-Image", "/StartComponentCleanup") `
            -TimeoutMinutes 120 `
            -HeartbeatSeconds 300

        if ($stopwatch.IsRunning) {
            $stopwatch.Stop()
        }

        $detail = "DISM StartComponentCleanup completed with exit code $($commandResult.ExitCode) in $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s."

        Write-RepairLog $detail -Level "OK"
        Write-RepairResult -Task "DISM StartComponentCleanup" -Status "OK" -Detail $detail

        return New-RepairResult `
            -Task "DISM StartComponentCleanup" `
            -Status "OK" `
            -Detail $detail `
            -ExitCode $commandResult.ExitCode `
            -Output $commandResult.Output `
            -Error $commandResult.Error `
            -ElapsedSeconds ([math]::Round($stopwatch.Elapsed.TotalSeconds, 3))
    }
    catch {
        if ($stopwatch.IsRunning) {
            $stopwatch.Stop()
        }
        $detail = $_.Exception.Message

        Write-RepairLog "DISM StartComponentCleanup failed: $detail" -Level "ERROR"
        Write-RepairResult -Task "DISM StartComponentCleanup" -Status "ERROR" -Detail $detail

        return New-RepairResult `
            -Task "DISM StartComponentCleanup" `
            -Status "ERROR" `
            -Detail $detail `
            -ElapsedSeconds ([math]::Round($stopwatch.Elapsed.TotalSeconds, 3))
    }
}

# ========================================
# SFC REPAIR
# ========================================

function Invoke-SfcScan {
    [CmdletBinding()]
    param()

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        Write-RepairLog "Starting SFC system file verification..." -Level "INFO"

        $commandResult = Invoke-RepairNativeCommand `
            -FilePath "sfc.exe" `
            -Arguments @("/scannow") `
            -SuccessExitCodes @(0, 1, 2, 3) `
            -TimeoutMinutes 90 `
            -HeartbeatSeconds 120

        if ($stopwatch.IsRunning) {
            $stopwatch.Stop()
        }
        $normalizedOutput = Convert-TextForMatch -Text $commandResult.Output
        $status = "OK"
        $detail = "SFC finished with exit code $($commandResult.ExitCode) in $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s."

        if ($normalizedOutput -match "found corrupt files and successfully repaired|encontro archivos danados y los reparo|encontrou arquivos corrompidos e os reparou") {
            $status = "OK"
            $detail = "SFC repaired corrupt system files in $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s."
        }
        elseif ($normalizedOutput -match "did not find any integrity violations|no encontro ninguna infraccion de integridad|nao encontrou nenhuma violacao de integridad") {
            $status = "OK"
            $detail = "SFC did not find integrity violations in $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s."
        }
        elseif ($normalizedOutput -match "could not perform|no pudo realizar|nao pode executar") {
            $status = "WARN"
            $detail = "SFC could not complete verification in $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s. Exit code: $($commandResult.ExitCode)."
        }
        elseif ($commandResult.ExitCode -ne 0) {
            $status = "WARN"
            $detail = "SFC finished with non-zero exit code $($commandResult.ExitCode) in $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s."
        }

        $logLevel = if ($status -eq "OK") { "OK" } else { "WARN" }
        Write-RepairLog $detail -Level $logLevel
        Write-RepairResult -Task "SFC Scan" -Status $status -Detail $detail

        return New-RepairResult `
            -Task "SFC Scan" `
            -Status $status `
            -Detail $detail `
            -ExitCode $commandResult.ExitCode `
            -Output $commandResult.Output `
            -Error $commandResult.Error `
            -ElapsedSeconds ([math]::Round($stopwatch.Elapsed.TotalSeconds, 3))
    }
    catch {
        if ($stopwatch.IsRunning) {
            $stopwatch.Stop()
        }
        $detail = $_.Exception.Message

        Write-RepairLog "SFC system file verification failed: $detail" -Level "ERROR"
        Write-RepairResult -Task "SFC Scan" -Status "ERROR" -Detail $detail

        return New-RepairResult `
            -Task "SFC Scan" `
            -Status "ERROR" `
            -Detail $detail `
            -ElapsedSeconds ([math]::Round($stopwatch.Elapsed.TotalSeconds, 3))
    }
}

# ========================================
# VOLUME SCAN
# ========================================

function Invoke-VolumeScan {
    [CmdletBinding()]
    param()

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        if (-not (Get-Command -Name Repair-Volume -ErrorAction SilentlyContinue)) {
            if ($stopwatch.IsRunning) {
                $stopwatch.Stop()
            }
            $detail = "Repair-Volume cmdlet is not available on this Windows installation."

            Write-RepairLog $detail -Level "SKIPPED"
            Write-RepairResult -Task "Volume Scan" -Status "SKIPPED" -Detail $detail

            return New-RepairResult `
                -Task "Volume Scan" `
                -Status "SKIPPED" `
                -Detail $detail `
                -ElapsedSeconds ([math]::Round($stopwatch.Elapsed.TotalSeconds, 3))
        }

        $driveLetter = Get-SystemDriveLetter
        Write-RepairLog "Starting Repair-Volume scan on $driveLetter`:..." -Level "INFO"

        $scanOutput = Repair-Volume -DriveLetter $driveLetter -Scan -ErrorAction Stop 4>&1 | Out-String
        if ($stopwatch.IsRunning) {
            $stopwatch.Stop()
        }

        if ($scanOutput.Trim()) {
            Write-RepairLog $scanOutput.Trim() -Level "INFO"
        }

        $detail = "Repair-Volume -Scan completed on $driveLetter`: in $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s."

        Write-RepairLog $detail -Level "OK"
        Write-RepairResult -Task "Volume Scan" -Status "OK" -Detail $detail

        return New-RepairResult `
            -Task "Volume Scan" `
            -Status "OK" `
            -Detail $detail `
            -Output $scanOutput `
            -ElapsedSeconds ([math]::Round($stopwatch.Elapsed.TotalSeconds, 3))
    }
    catch {
        if ($stopwatch.IsRunning) {
            $stopwatch.Stop()
        }
        $detail = $_.Exception.Message

        Write-RepairLog "Volume scan failed: $detail" -Level "ERROR"
        Write-RepairResult -Task "Volume Scan" -Status "ERROR" -Detail $detail

        return New-RepairResult `
            -Task "Volume Scan" `
            -Status "ERROR" `
            -Detail $detail `
            -ElapsedSeconds ([math]::Round($stopwatch.Elapsed.TotalSeconds, 3))
    }
}

# ========================================
# MAIN REPAIR ORCHESTRATOR
# ========================================

function Invoke-SystemRepair {
    [CmdletBinding()]
    param()

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $results = New-Object System.Collections.Generic.List[object]
    $hasError = $false
    $hasWarning = $false

    try {
        Write-RepairLog "===== STARTING SYSTEM REPAIR MODULE =====" -Level "INFO"

        $repairSteps = @(
            @{ Task = "DISM RestoreHealth"; Command = { Invoke-DismRestoreHealth } },
            @{ Task = "DISM StartComponentCleanup"; Command = { Invoke-DismStartComponentCleanup } },
            @{ Task = "SFC Scan"; Command = { Invoke-SfcScan } },
            @{ Task = "Volume Scan"; Command = { Invoke-VolumeScan } }
        )

        foreach ($step in $repairSteps) {
            Write-RepairLog "START: $($step.Task)" -Level "INFO"

            $stepResult = & $step.Command

            if ($null -ne $stepResult) {
                [void]$results.Add($stepResult)
            }

            $stepStatus = if ($null -ne $stepResult -and $null -ne $stepResult.Status) {
                $stepResult.Status
            }
            else {
                "ERROR"
            }

            if ($stepStatus -eq "ERROR") {
                $hasError = $true
            }
            elseif ($stepStatus -eq "WARN" -or $stepStatus -eq "SKIPPED") {
                $hasWarning = $true
            }

            $logLevel = switch ($stepStatus) {
                "OK"      { "OK" }
                "WARN"    { "WARN" }
                "ERROR"   { "ERROR" }
                "SKIPPED" { "SKIPPED" }
                default   { "INFO" }
            }

            Write-RepairLog "END: $($step.Task) [$stepStatus]" -Level $logLevel
        }

        if ($stopwatch.IsRunning) {
            $stopwatch.Stop()
        }
        $overallStatus = if ($hasError) { "ERROR" } elseif ($hasWarning) { "WARN" } else { "OK" }
        $detail = "System repair pipeline completed with status $overallStatus in $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s. Phases executed: $($results.Count)."

        Write-RepairLog $detail -Level $overallStatus
        Write-RepairResult -Task "System Repair" -Status $overallStatus -Detail $detail

        $result = New-RepairResult `
            -Task "System Repair" `
            -Status $overallStatus `
            -Detail $detail `
            -ElapsedSeconds ([math]::Round($stopwatch.Elapsed.TotalSeconds, 3))
        
        $result | Add-Member `
            -MemberType NoteProperty `
            -Name Results `
            -Value $results
            -Force
        
        return $result
    }
    catch {
        if ($stopwatch.IsRunning) {
            $stopwatch.Stop()
        }
        $detail = $_.Exception.Message

        Write-RepairLog "System repair module failed: $detail" -Level "ERROR"
        Write-RepairResult -Task "System Repair" -Status "ERROR" -Detail $detail

        $result = New-RepairResult `
            -Task "System Repair" `
            -Status "ERROR" `
            -Detail $detail `
            -ElapsedSeconds ([math]::Round($stopwatch.Elapsed.TotalSeconds, 3))

    
        $result | Add-Member `
            -MemberType NoteProperty `
            -Name Results `
            -Value $results

        return $result
    }
    finally {
        Write-RepairLog "===== SYSTEM REPAIR MODULE FINISHED =====" -Level "INFO"
    }
}

Export-ModuleMember -Function `
    Invoke-DismRestoreHealth,
    Invoke-DismStartComponentCleanup,
    Invoke-SfcScan,
    Invoke-VolumeScan,
    Invoke-SystemRepair