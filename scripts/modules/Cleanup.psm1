<#
.SYNOPSIS
    System cleanup subsystem for ITechBR framework.

.DESCRIPTION
    Provides automated maintenance and storage cleanup
    routines across Windows system areas and user profiles.
#>

# ========================================
# INTERNAL CONFIGURATION
# ========================================

$script:ExcludedProfiles = @(
    "All Users",
    "Default",
    "Default User",
    "Public",
    "desktop.ini"
)

# ========================================
# WINDOWS TEMP CLEANUP
# ========================================

function Clear-WindowsTempFiles {
    Write-Log "Starting Windows temporary directory cleanup..." -Level "INFO"

    try {
        $WindowsTempPath = "C:\Windows\Temp"

        if (Test-Path $WindowsTempPath) {
            # Optimized direct deletion using wildcard targeting
            Remove-Item -Path (Join-Path $WindowsTempPath "*") -Recurse -Force -ErrorAction SilentlyContinue

            Write-Log "Windows temporary directory cleaned successfully." -Level "OK"

            Add-Result `
                -Task "Windows Temp Cleanup" `
                -Status "OK" `
                -Detail "System temporary files removed successfully."
        }
        else {
            Write-Log "Windows Temp directory not found." -Level "WARN"

            Add-Result `
                -Task "Windows Temp Cleanup" `
                -Status "WARN" `
                -Detail "Windows Temp directory was not found."
        }
    }
    catch {
        Write-Log "Windows Temp cleanup failed: $($_.Exception.Message)" -Level "ERROR"

        Add-Result `
            -Task "Windows Temp Cleanup" `
            -Status "ERROR" `
            -Detail $_.Exception.Message
    }
}

# ========================================
# USER PROFILE TEMP CLEANUP
# ========================================

function Clear-UserTempFiles {
    Write-Log "Starting multi-user temporary directory cleanup..." -Level "INFO"

    try {
        $ProfilesProcessed = 0
        $UserProfiles = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue

        foreach ($Profile in $UserProfiles) {
            if ($script:ExcludedProfiles -contains $Profile.Name) {
                continue
            }

            $UserTempPath = Join-Path $Profile.FullName "AppData\Local\Temp"

            if (Test-Path $UserTempPath) {
                Write-Log "Cleaning temporary files for profile: $($Profile.Name)" -Level "INFO"

                # Optimized direct deletion targeting contents inside the user's temp directory
                Remove-Item -Path (Join-Path $UserTempPath "*") -Recurse -Force -ErrorAction SilentlyContinue

                $ProfilesProcessed++
            }
        }

        Write-Log "User profile cleanup completed. Profiles processed: $ProfilesProcessed" -Level "OK"

        Add-Result `
            -Task "User Temp Cleanup" `
            -Status "OK" `
            -Detail "$ProfilesProcessed user profiles cleaned successfully."
    }
    catch {
        Write-Log "User Temp cleanup failed: $($_.Exception.Message)" -Level "ERROR"

        Add-Result `
            -Task "User Temp Cleanup" `
            -Status "ERROR" `
            -Detail $_.Exception.Message
    }
}

# ========================================
# RECYCLE BIN CLEANUP
# ========================================

function Clear-SystemRecycleBin {
    Write-Log "Starting system-wide Recycle Bin cleanup..." -Level "INFO"

    try {
        Clear-RecycleBin -Force -ErrorAction Stop

        Write-Log "Recycle Bin cleanup completed successfully." -Level "OK"

        Add-Result `
            -Task "Recycle Bin Cleanup" `
            -Status "OK" `
            -Detail "System recycle bin emptied successfully."
    }
    catch {
        Write-Log "Recycle Bin cleanup failed: $($_.Exception.Message)" -Level "WARN"

        Add-Result `
            -Task "Recycle Bin Cleanup" `
            -Status "WARN" `
            -Detail $_.Exception.Message
    }
}

# ========================================
# CLEANMGR REGISTRY CONFIGURATION
# ========================================

function Set-CleanMgrAutomation {
    Write-Log "Configuring CleanMgr automation flags..." -Level "INFO"

    try {
        if (-not (Get-Command "cleanmgr.exe" -ErrorAction SilentlyContinue)) {
            Write-Log "CleanMgr automation skipped because cleanmgr.exe is unavailable." -Level "SKIPPED"
            Add-Result `
                -Task "CleanMgr Configuration" `
                -Status "SKIPPED" `
                -Detail "cleanmgr.exe not present on this Windows installation."
                
            return
        }
        
        $BaseRegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
        $StateNumber = "0001"

        Get-ChildItem -Path $BaseRegistryPath -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Set-ItemProperty `
                    -Path $_.PSPath `
                    -Name "StateFlags$StateNumber" `
                    -Value 2 `
                    -ErrorAction SilentlyContinue
            }
            catch {
                # Handle edge-case locked registry keys gracefully
            }
        }

        Write-Log "CleanMgr automation flags configured successfully." -Level "OK"

        Add-Result `
            -Task "CleanMgr Configuration" `
            -Status "OK" `
            -Detail "Registry automation flags applied successfully."
    }
    catch {
        Write-Log "CleanMgr configuration failed: $($_.Exception.Message)" -Level "ERROR"

        Add-Result `
            -Task "CleanMgr Configuration" `
            -Status "ERROR" `
            -Detail $_.Exception.Message
    }
}

# ========================================
# CLEANMGR EXECUTION
# ========================================

function Invoke-NativeDiskCleanup {

    Write-Log "Launching native Windows Disk Cleanup..." -Level "INFO"

    try {
        if (-not (Get-Command "cleanmgr.exe" -ErrorAction SilentlyContinue)) {
            Write-Log "Native Disk Cleanup skipped because cleanmgr.exe is unavailable." -Level "SKIPPED"
            Add-Result `
                -Task "Native Disk Cleanup" `
                -Status "SKIPPED" `
                -Detail "cleanmgr.exe not present on this Windows installation."
            
            return
        }
                
        $CleanProcess = Start-Process `
            -FilePath "cleanmgr.exe" `
            -ArgumentList "/sagerun:1" `
            -NoNewWindow `
            -PassThru `
            -Wait

        if ($CleanProcess.ExitCode -eq 0) {

            Write-Log "Native Windows Disk Cleanup completed successfully." -Level "OK"

            Add-Result `
                -Task "Native Disk Cleanup" `
                -Status "OK" `
                -Detail "cleanmgr.exe completed successfully."
        }
        else {

            throw "cleanmgr.exe exited with code $($CleanProcess.ExitCode)"
        }
    }
    catch {

        Write-Log "Native Disk Cleanup failed: $($_.Exception.Message)" -Level "ERROR"

        Add-Result `
            -Task "Native Disk Cleanup" `
            -Status "ERROR" `
            -Detail $_.Exception.Message
    }
}

# ========================================
# MAIN CLEANUP ORCHESTRATOR
# ========================================

function Invoke-SystemCleanup {
    Write-Log "===== STARTING SYSTEM CLEANUP MODULE =====" -Level "INFO"

    Clear-WindowsTempFiles
    Clear-UserTempFiles
    Clear-SystemRecycleBin
    Set-CleanMgrAutomation
    Invoke-NativeDiskCleanup

    Write-Log "===== SYSTEM CLEANUP MODULE COMPLETED =====" -Level "OK"
}

Export-ModuleMember -Function `
    Invoke-SystemCleanup,
    Clear-WindowsTempFiles,
    Clear-UserTempFiles,
    Clear-SystemRecycleBin,
    Set-CleanMgrAutomation,
    Invoke-NativeDiskCleanup