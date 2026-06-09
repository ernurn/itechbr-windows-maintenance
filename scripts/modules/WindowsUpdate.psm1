<#
.SYNOPSIS
    Windows Update subsystem for ITechBR framework.

.DESCRIPTION
    Handles Windows Update discovery, EULA acceptance, download,
    installation, and reboot-requirement detection through the
    Microsoft.Update.Session COM interface.

    Public entry point: Install-WindowsUpdates
    Returns $true when a system restart is required to finalize
    the installation, $false otherwise.
#>

# ========================================
# INTERNAL CONFIGURATION
# ========================================

$script:WUASearchCriteria = "IsInstalled=0 and IsHidden=0 and Type='Software'"
$script:WUARetryDelaySeconds = 5
$script:WUAMaxAttempts = 2

# ========================================
# LOGGING / REPORTING GUARDS
# ========================================
# Helpers below call Write-Log and Add-Result directly. Both are
# framework-level cmdlets (Logging.psm1 / Reporting.psm1) and may be
# absent in standalone test contexts. The guards mirror the pattern
# used across the rest of the framework so the module loads cleanly
# without forcing a logging/reporting initialization order.

function script:Write-WUALog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "OK", "WARN", "ERROR", "SKIPPED")]
        [string]$Level = "INFO"
    )

    if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Message $Message -Level $Level
    }
}

function script:Write-WUAResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Task,

        [Parameter(Mandatory = $true)]
        [ValidateSet("INFO", "OK", "WARN", "ERROR", "SKIPPED")]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [string]$Detail = ""
    )

    if (Get-Command -Name Add-Result -ErrorAction SilentlyContinue) {
        Add-Result -Task $Task -Status $Status -Detail $Detail
    }
}

# ========================================
# SEARCH PHASE
# ========================================

function script:Get-PendingWindowsUpdates {
    [CmdletBinding()]
    param()

    Write-WUALog "Searching for pending Windows updates..." -Level "INFO"

    $Session = New-Object -ComObject Microsoft.Update.Session
    $Searcher = $Session.CreateUpdateSearcher()
    $SearchResult = $Searcher.Search($script:WUASearchCriteria)

    # WUA ResultCode: 0=No error, 1=SearchInProgress, 2=Failed
    if ($SearchResult.ResultCode -ne 0) {
        throw "Windows Update search failed with ResultCode=$($SearchResult.ResultCode)."
    }

    return [pscustomobject]@{
        Session  = $Session
        Updates  = $SearchResult.Updates
        Count    = $SearchResult.Updates.Count
    }
}

# ========================================
# EULA ACCEPTANCE PHASE
# ========================================

function script:Register-UpdateEulas {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $SourceUpdates,

        [Parameter(Mandatory = $true)]
        $TargetCollection
    )

    for ($i = 0; $i -lt $SourceUpdates.Count; $i++) {
        $Update = $SourceUpdates.Item($i)

        if (-not $Update.EulaAccepted) {
            $Update.AcceptEula() | Out-Null
        }

        [void]$TargetCollection.Add($Update)

        Write-WUALog "Found update: $($Update.Title)" -Level "INFO"
    }
}

# ========================================
# DOWNLOAD PHASE
# ========================================

function script:Invoke-UpdateDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Session,

        [Parameter(Mandatory = $true)]
        $Updates
    )

    Write-WUALog "Downloading updates..." -Level "INFO"

    $Downloader = $Session.CreateUpdateDownloader()
    $Downloader.Updates = $Updates

    $Attempt = 0
    $DownloadResult = $null

    while ($Attempt -lt $script:WUAMaxAttempts) {
        $Attempt++
        $DownloadResult = $Downloader.Download()

        # HResult 0 == success. Non-zero indicates a transient or
        # permanent COM-level error; retry once to absorb flakiness.
        if ($DownloadResult.HResult -eq 0) {
            break
        }

        if ($Attempt -lt $script:WUAMaxAttempts) {
            Write-WUALog "Download attempt $Attempt failed (HResult=$($DownloadResult.HResult)). Retrying in $script:WUARetryDelaySeconds s..." -Level "WARN"
            Start-Sleep -Seconds $script:WUARetryDelaySeconds
        }
    }

    Write-WUALog "Windows Update download result: ResultCode=$($DownloadResult.ResultCode), HResult=$($DownloadResult.HResult)" -Level "INFO"
    Write-WUALog "Download phase completed." -Level "OK"

    return $DownloadResult
}

# ========================================
# INSTALL PHASE
# ========================================

function script:Invoke-UpdateInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Session,

        [Parameter(Mandatory = $true)]
        $Updates
    )

    Write-WUALog "Installing $($Updates.Count) downloaded updates..." -Level "INFO"

    $Installer = $Session.CreateUpdateInstaller()
    $Installer.Updates = $Updates

    $Attempt = 0
    $InstallResult = $null

    while ($Attempt -lt $script:WUAMaxAttempts) {
        $Attempt++
        $InstallResult = $Installer.Install()

        if ($InstallResult.HResult -eq 0) {
            break
        }

        if ($Attempt -lt $script:WUAMaxAttempts) {
            Write-WUALog "Install attempt $Attempt failed (HResult=$($InstallResult.HResult)). Retrying in $script:WUARetryDelaySeconds s..." -Level "WARN"
            Start-Sleep -Seconds $script:WUARetryDelaySeconds
        }
    }

    Write-WUALog "Installation phase completed. ResultCode=$($InstallResult.ResultCode), HResult=$($InstallResult.HResult)" -Level "OK"

    return $InstallResult
}

# ========================================
# REBOOT DETECTION
# ========================================

function script:Test-RebootRequired {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InstallResult
    )

    if ($InstallResult.RebootRequired) {
        Write-WUALog "System restart required to complete update installation." -Level "WARN"
        return $true
    }

    Write-WUALog "Windows Update completed successfully. No reboot required." -Level "OK"
    return $false
}

# ========================================
# MAIN ORCHESTRATOR
# ========================================

function Install-WindowsUpdates {
    [CmdletBinding()]
    param()

    $PhaseStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        # ----- SEARCH ----------------------------------------------------
        $Search = Get-PendingWindowsUpdates

        if ($Search.Count -eq 0) {
            Write-WUALog "No pending Windows updates found." -Level "OK"
            Write-WUAResult -Task "Windows Update" -Status "OK" -Detail "System already up to date"

            $PhaseStopwatch.Stop()
            return $false
        }

        # ----- EULA ACCEPTANCE -------------------------------------------
        $ApprovedUpdates = New-Object -ComObject Microsoft.Update.UpdateColl
        Register-UpdateEulas -SourceUpdates $Search.Updates -TargetCollection $ApprovedUpdates

        # ----- DOWNLOAD --------------------------------------------------
        $DownloadResult = Invoke-UpdateDownload -Session $Search.Session -Updates $ApprovedUpdates

        if ($DownloadResult.HResult -ne 0) {
            Write-WUALog "Updates were found but the download phase failed after $script:WUAMaxAttempts attempts." -Level "WARN"
            Write-WUAResult -Task "Windows Update" -Status "WARN" -Detail "Download phase failed (HResult=$($DownloadResult.HResult))"

            $PhaseStopwatch.Stop()
            return $false
        }

        # ----- INSTALLATION PREP -----------------------------------------
        $InstallableUpdates = New-Object -ComObject Microsoft.Update.UpdateColl

        for ($i = 0; $i -lt $ApprovedUpdates.Count; $i++) {
            $Update = $ApprovedUpdates.Item($i)
            if ($Update.IsDownloaded) {
                [void]$InstallableUpdates.Add($Update)
            }
        }

        Write-WUALog "Total updates found: $($ApprovedUpdates.Count)" -Level "INFO"
        Write-WUALog "Updates ready for installation: $($InstallableUpdates.Count)" -Level "INFO"

        if ($InstallableUpdates.Count -eq 0) {
            Write-WUALog "Updates were found but none were successfully downloaded." -Level "WARN"
            Write-WUAResult -Task "Windows Update" -Status "WARN" -Detail "No updates transitioned to the IsDownloaded state."

            $PhaseStopwatch.Stop()
            return $false
        }

        # ----- INSTALLATION ----------------------------------------------
        $InstallResult = Invoke-UpdateInstall -Session $Search.Session -Updates $InstallableUpdates

        $InstalledCount = $InstallableUpdates.Count
        $RebootRequired = Test-RebootRequired -InstallResult $InstallResult

        if ($RebootRequired) {
            Write-WUAResult -Task "Windows Update" -Status "WARN" -Detail "$InstalledCount updates installed; reboot required to finalize."
        }
        else {
            Write-WUAResult -Task "Windows Update" -Status "OK" -Detail "$InstalledCount updates installed successfully."
        }

        $PhaseStopwatch.Stop()
        Write-WUALog "Windows Update pipeline finished in $([math]::Round($PhaseStopwatch.Elapsed.TotalSeconds, 2))s." -Level "INFO"

        return $RebootRequired
    }
    catch {
        $PhaseStopwatch.Stop()

        Write-WUALog "Windows Update subsystem failure: $($_.Exception.Message)" -Level "ERROR"
        Write-WUAResult -Task "Windows Update" -Status "ERROR" -Detail $_.Exception.Message

        return $false
    }
}

Export-ModuleMember -Function Install-WindowsUpdates
