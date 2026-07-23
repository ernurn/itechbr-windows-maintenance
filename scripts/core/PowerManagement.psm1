# ========================================
# PowerManagement.psm1
# Core module for power configuration management
# Compatible: Windows PowerShell 5.1, Windows 10/11
# ========================================

Set-StrictMode -Version Latest

# Do NOT import core dependencies here - let the caller (main.ps1) import them
# This avoids module scope nesting issues where imported commands aren't visible globally.
# Functions guard Write-Log/Invoke-NativeCommand calls with Get-Command checks.

# ========================================
# INTERNAL HELPERS (guarded for standalone loading)
# ========================================

function _Write-Log {
    <#
    .SYNOPSIS
        Internal logging helper - uses Logging.psm1 if available, falls back to console.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "OK", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Message $Message -Level $Level
    }
    else {
        $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "$time [$Level] $Message"
    }
}

function _Invoke-NativeCommand {
    <#
    .SYNOPSIS
        Internal native command helper - uses NativeCommand.psm1 if available.
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

    if (Get-Command Invoke-NativeCommand -ErrorAction SilentlyContinue) {
        return Invoke-NativeCommand -FilePath $FilePath -Arguments $Arguments -SuccessExitCodes $SuccessExitCodes -InputText $InputText -TimeoutMinutes $TimeoutMinutes -HeartbeatSeconds $HeartbeatSeconds
    }
    else {
        throw "Invoke-NativeCommand not available. Import NativeCommand.psm1 first."
    }
}

# ========================================
# PUBLIC FUNCTIONS
# ========================================

function Get-HibernationState {
    <#
    .SYNOPSIS
        Checks if hibernation is currently enabled on the system.
    .OUTPUTS
        [bool] True if hiberfil.sys exists (hibernation enabled), false otherwise.
    #>
    $hiberFile = Get-Item -LiteralPath "$env:SystemDrive\hiberfil.sys" -Force -ErrorAction SilentlyContinue
    return [bool]$hiberFile
}

function Get-FastStartupState {
    <#
    .SYNOPSIS
        Reads the current Fast Startup (HiberbootEnabled) registry value.
    .OUTPUTS
        [int] Current value of HiberbootEnabled (0 = disabled, 1 = enabled). Returns 1 if not found.
    #>
    $powerKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
    $hiberbootValue = (Get-ItemProperty -Path $powerKey -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
    if ($null -eq $hiberbootValue) {
        return 1
    }
    return $hiberbootValue
}

function Set-FastStartup {
    <#
    .SYNOPSIS
        Enables or disables Fast Startup by modifying the HiberbootEnabled registry value.
    .PARAMETER Enabled
        $true to enable Fast Startup, $false to disable.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )

    $powerKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
    $value = if ($Enabled) { 1 } else { 0 }
    Set-ItemProperty -Path $powerKey -Name HiberbootEnabled -Value $value -Force -ErrorAction Stop
}

function Disable-HibernationAndFastStartup {
    <#
    .SYNOPSIS
        Disables hibernation and Fast Startup for maintenance operations.
    .DESCRIPTION
        Uses powercfg.exe to disable hibernation and sets HiberbootEnabled registry value to 0.
        Sets the script-scoped $script:PowerConfigChanged flag to $true.
    .OUTPUTS
        None. Logs actions via Write-Log.
    #>
    _Write-Log "Disabling hibernation and Fast Startup for maintenance..." -Level "INFO"

    try {
        _Invoke-NativeCommand -FilePath "powercfg.exe" -Arguments @("/h", "off") | Out-Null
        $script:PowerConfigChanged = $true
        _Write-Log "Hibernation disabled." -Level "OK"
    }
    catch {
        _Write-Log "Could not disable hibernation: $($_.Exception.Message)" -Level "WARN"
    }

    try {
        $powerKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
        Set-ItemProperty -Path $powerKey -Name HiberbootEnabled -Value 0 -Force -ErrorAction Stop
        _Write-Log "Fast Startup disabled." -Level "OK"
    }
    catch {
        _Write-Log "Could not disable Fast Startup: $($_.Exception.Message)" -Level "WARN"
    }
}

function Restore-OriginalPowerSettings {
    <#
    .SYNOPSIS
        Restores hibernation and Fast Startup to their original captured states.
    .DESCRIPTION
        Uses script-scoped variables $script:InitialHibernationEnabled and $script:InitialFastStartupValue
        to restore the original power configuration. Validates that restoration was applied.
    .OUTPUTS
        None. Sets $script:PowerConfigChanged = $false and $script:PowerRestored = $true on completion.
    #>
    _Write-Log "Restoring original power settings..." -Level "INFO"

    # Restore hibernation
    try {
        if ($script:InitialHibernationEnabled) {
            _Invoke-NativeCommand -FilePath "powercfg.exe" -Arguments @("/h", "on") | Out-Null
        }
        else {
            _Invoke-NativeCommand -FilePath "powercfg.exe" -Arguments @("/h", "off") | Out-Null
        }

        # Validate restoration
        $currentHibernation = Get-HibernationState
        if ($currentHibernation -eq $script:InitialHibernationEnabled) {
            _Write-Log "Hibernation restored to initial state." -Level "OK"
        }
        else {
            _Write-Log "WARNING: Hibernation state mismatch after restoration. Expected: $($script:InitialHibernationEnabled), Actual: $currentHibernation" -Level "WARN"
        }
    }
    catch {
        _Write-Log "Could not restore hibernation settings: $($_.Exception.Message)" -Level "WARN"
    }

    # Restore Fast Startup
    try {
        $powerKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
        Set-ItemProperty -Path $powerKey -Name HiberbootEnabled -Value $script:InitialFastStartupValue -Force -ErrorAction Stop

        # Validate restoration
        $currentFastStartup = Get-FastStartupState
        if ($currentFastStartup -eq $script:InitialFastStartupValue) {
            _Write-Log "Fast Startup restored to initial value ($($script:InitialFastStartupValue))." -Level "OK"
        }
        else {
            _Write-Log "WARNING: Fast Startup value mismatch after restoration. Expected: $($script:InitialFastStartupValue), Actual: $currentFastStartup" -Level "WARN"
        }
    }
    catch {
        _Write-Log "Could not restore Fast Startup: $($_.Exception.Message)" -Level "WARN"
    }

    $script:PowerConfigChanged = $false
    $script:PowerRestored = $true
}

# ========================================
# INITIALIZATION (for main.ps1 integration)
# ========================================

function Initialize-PowerStateCapture {
    <#
    .SYNOPSIS
        Captures the initial power state (hibernation and Fast Startup) into script-scoped variables.
    .DESCRIPTION
        Must be called early in main.ps1 before Disable-HibernationAndFastStartup.
        Sets $script:InitialHibernationEnabled, $script:InitialFastStartupValue, $script:PowerConfigChanged, $script:PowerRestored.
    #>
    $script:InitialHibernationEnabled = $false
    $script:InitialFastStartupValue = 1
    $script:PowerConfigChanged = $false
    $script:PowerRestored = $false

    try {
        $hiberFile = Get-Item -LiteralPath "$env:SystemDrive\hiberfil.sys" -Force -ErrorAction SilentlyContinue
        $script:InitialHibernationEnabled = [bool]$hiberFile
    }
    catch {
        _Write-Log "Could not determine initial hibernation state: $($_.Exception.Message)" -Level "WARN"
    }

    try {
        $powerKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
        $hiberbootValue = (Get-ItemProperty -Path $powerKey -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
        if ($null -ne $hiberbootValue) {
            $script:InitialFastStartupValue = $hiberbootValue
        }
    }
    catch {
        _Write-Log "Could not capture initial Fast Startup value: $($_.Exception.Message)" -Level "WARN"
    }

    _Write-Log "Initial power state captured: Hibernation=$($script:InitialHibernationEnabled), FastStartup=$($script:InitialFastStartupValue)" -Level "INFO"
}

# ========================================
# EXPORTS
# ========================================

Export-ModuleMember -Function @(
    'Get-HibernationState',
    'Get-FastStartupState',
    'Set-FastStartup',
    'Disable-HibernationAndFastStartup',
    'Restore-OriginalPowerSettings',
    'Initialize-PowerStateCapture'
)