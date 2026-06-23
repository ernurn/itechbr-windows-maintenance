<#
.SYNOPSIS
    System inventory subsystem for ITechBR framework.

.DESCRIPTION
    Provides complete workstation asset inventory collection.
    All operations are read-only with no system modifications.
    Supports hardware, operating system, software, and asset information.

    Public entry points:
    - Get-HardwareInventory
    - Get-OperatingSystemInventory
    - Get-SoftwareInventory
    - Get-AssetInventory
    - Export-InventoryReport
    - Invoke-Inventory
#>

Set-StrictMode -Version Latest

# ========================================
# LOGGING / REPORTING GUARDS
# ========================================

function script:Write-InventoryLog {
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

function script:Write-InventoryResult {
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

function script:Get-FirstCimValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClassName,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName,

        [string]$DefaultValue = "Unknown"
    )

    $instance = Get-CimInstance -ClassName $ClassName -ErrorAction SilentlyContinue
    if ($null -eq $instance -or $null -eq $instance.$PropertyName) {
        return $DefaultValue
    }

    return $instance.$PropertyName
}

function script:Get-AllCimInstances {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClassName,

        [string[]]$PropertyNames = @(),

        [string]$Namespace = $null
    )

    $cimParams = @{
        ClassName = $ClassName
        ErrorAction = "SilentlyContinue"
    }

    if ($Namespace) {
        $cimParams.Namespace = $Namespace
    }

    $instances = Get-CimInstance @cimParams

    if ($null -eq $instances) {
        return @()
    }

    if ($PropertyNames.Count -gt 0) {
        return $instances | Select-Object $PropertyNames
    }

    return $instances
}

# ========================================
# HARDWARE INVENTORY
# ========================================

function Get-HardwareInventory {
    [CmdletBinding()]
    param()

    Write-InventoryLog "Collecting hardware inventory..." -Level "INFO"

    try {
        $cpu = Get-AllCimInstances -ClassName "Win32_Processor" -PropertyNames @(
            "Name",
            "Manufacturer",
            "NumberOfCores",
            "NumberOfLogicalProcessors",
            "MaxClockSpeed"
        )

        $motherboard = Get-AllCimInstances -ClassName "Win32_BaseBoard" -PropertyNames @(
            "Manufacturer",
            "Model",
            "SerialNumber"
        )

        $physicalMemory = Get-AllCimInstances -ClassName "Win32_PhysicalMemory" -PropertyNames @(
            "Capacity",
            "Speed",
            "Manufacturer",
            "PartNumber"
        )

        $gpu = Get-AllCimInstances -ClassName "Win32_VideoController" -PropertyNames @(
            "Name",
            "AdapterRAM",
            "DriverVersion",
            "PNPDeviceID"
        )

        $bios = Get-AllCimInstances -ClassName "Win32_BIOS" -PropertyNames @(
            "SMBIOSBIOSVersion",
            "ReleaseDate",
            "SerialNumber"
        )

        $physicalDisks = Get-AllCimInstances `
            -ClassName "MSFT_PhysicalDisk" `
            -Namespace "root\Microsoft\Windows\Storage" `
            -PropertyNames @(
                "DeviceId",
                "FriendlyName",
                "MediaType",
                "Size",
                "HealthStatus"
            )

        $hardwareInventory = [PSCustomObject] @{
            Timestamp        = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            CPU              = $cpu
            Motherboard      = $motherboard
            RAM              = $physicalMemory
            GPU              = $gpu
            BIOS             = $bios
            PhysicalDisks    = $physicalDisks
        }

        Write-InventoryLog "Hardware inventory collection completed successfully." -Level "OK"
        Write-InventoryResult -Task "Hardware Inventory" -Status "OK" -Detail "Hardware inventory completed."

        return $hardwareInventory
    }
    catch {
        Write-InventoryLog "Hardware inventory collection failed: $($_.Exception.Message)" -Level "ERROR"
        Write-InventoryResult -Task "Hardware Inventory" -Status "ERROR" -Detail $_.Exception.Message
        return $null
    }
}

# ========================================
# OPERATING SYSTEM INVENTORY
# ========================================

function Get-OperatingSystemInventory {
    [CmdletBinding()]
    param()

    Write-InventoryLog "Collecting operating system information..." -Level "INFO"

    try {
        $osInstance = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        $processorInstance = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue
        $biosInstance = Get-CimInstance -ClassName Win32_Bios -ErrorAction SilentlyContinue

        $activationInstance = Get-CimInstance `
            -Namespace "root\cimv2\SoftwareLicensing" `
            -ClassName "SoftwareLicensingProduct" `
            -ErrorAction SilentlyContinue

        $architecture = if ($processorInstance) {
            switch ($processorInstance.Architecture) {
                0 { "x86" }
                1 { "MIPS" }
                2 { "Alpha" }
                3 { "PowerPC" }
                5 { "ARM" }
                6 { "ia64" }
                9 { "x64" }
                12 { "ARM64" }
                default { "Unknown" }
            }
        }
        else {
            "Unknown"
        }

        $activationStatus = if ($activationInstance) {
            $licensedProducts = $activationInstance | Where-Object {
                $_.PartialProductKey -and $_.LicenseStatus -eq 0
            }

            if ($licensedProducts) {
                "Licensed"
            }
            else {
                "Unlicensed"
            }
        }
        else {
            "Unknown"
        }

        $osInventory = [PSCustomObject] @{
            Timestamp          = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            WindowsEdition     = if ($osInstance) { $osInstance.Caption } else { "Unknown" }
            WindowsBuild       = if ($osInstance) { $osInstance.Version } else { "Unknown" }
            Architecture      = $architecture
            LastBootTime       = if ($osInstance) { $osInstance.LastBootUpTime } else { $null }
            ActivationStatus   = $activationStatus
            BIOSReleaseDate    = if ($biosInstance) { $biosInstance.ReleaseDate } else { $null }
            BIOSVersion        = if ($biosInstance) { $biosInstance.SMBIOSBIOSVersion } else { "Unknown" }
        }

        Write-InventoryLog "Operating system inventory collection completed successfully." -Level "OK"
        Write-InventoryResult -Task "Operating System Inventory" -Status "OK" -Detail "Operating system information collected."

        return $osInventory
    }
    catch {
        Write-InventoryLog "Operating system inventory collection failed: $($_.Exception.Message)" -Level "ERROR"
        Write-InventoryResult -Task "Operating System Inventory" -Status "ERROR" -Detail $_.Exception.Message
        return $null
    }
}

# ========================================
# SOFTWARE INVENTORY
# ========================================

function Get-SoftwareInventory {
    [CmdletBinding()]
    param()

    Write-InventoryLog "Collecting installed software inventory..." -Level "INFO"

    try {
        $softwareList = @()
        $uninstallPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
        )

        foreach ($path in $uninstallPaths) {
            if (Test-Path $path) {
                $entries = Get-ItemProperty -Path "$path\*" -ErrorAction SilentlyContinue

                foreach ($entry in $entries) {
                    # Validación segura bajo Set-StrictMode: mapear nombres de propiedades presentes
                    $availableProps = $entry.PSObject.Properties.Name

                    if ("DisplayName" -in $availableProps -and $entry.DisplayName) {
                        
                        $version = if ("DisplayVersion" -in $availableProps -and $entry.DisplayVersion) { $entry.DisplayVersion } else { "Unknown" }
                        $publisher = if ("Publisher" -in $availableProps -and $entry.Publisher) { $entry.Publisher } else { "Unknown" }
                        $installDate = if ("InstallDate" -in $availableProps -and $entry.InstallDate) { $entry.InstallDate } else { "Unknown" }
                        $sourcePath = if ("InstallLocation" -in $availableProps -and $entry.InstallLocation) { $entry.InstallLocation } else { "Unknown" }

                        $softwareList += [PSCustomObject] @{
                            DisplayName    = $entry.DisplayName
                            DisplayVersion = $version
                            Publisher      = $publisher
                            InstallDate    = $installDate
                            Version        = $version
                            SourcePath     = $sourcePath
                        }
                    }
                }
            }
        }

        Write-InventoryLog "Software inventory collection completed successfully with $($softwareList.Count) items." -Level "OK"
        Write-InventoryResult -Task "Software Inventory" -Status "OK" -Detail "Software inventory collected ($($softwareList.Count) items)."

        return $softwareList
    }
    catch {
        Write-InventoryLog "Software inventory collection failed: $($_.Exception.Message)" -Level "ERROR"
        Write-InventoryResult -Task "Software Inventory" -Status "ERROR" -Detail $_.Exception.Message
        return @()
    }
}

# ========================================
# ASSET INVENTORY
# ========================================

function Get-AssetInventory {
    [CmdletBinding()]
    param()

    Write-InventoryLog "Collecting asset inventory information..." -Level "INFO"

    try {
        $computerInfo = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $biosInfo = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop

        $assetInventory = [PSCustomObject] @{
            Timestamp             = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Hostname              = if ($computerInfo) { $computerInfo.Name } else { "Unknown" }
            Manufacturer          = if ($computerInfo) { $computerInfo.Manufacturer } else { "Unknown" }
            Model                 = if ($computerInfo) { $computerInfo.Model } else { "Unknown" }
            SerialNumber          = if ($biosInfo) { $biosInfo.SerialNumber } else { "Unknown" }
            SystemType            = if ($computerInfo) { $computerInfo.SystemType } else { "Unknown" }
            NumberOfProcessors    = if ($computerInfo) { $computerInfo.NumberOfProcessors } else { "Unknown" }
            TotalPhysicalMemory   = if ($computerInfo) { $computerInfo.TotalPhysicalMemory } else { "Unknown" }
            Domain                = if ($computerInfo) { $computerInfo.Domain } else { "Unknown" }
        }

        Write-InventoryLog "Asset inventory collection completed successfully." -Level "OK"
        Write-InventoryResult -Task "Asset Inventory" -Status "OK" -Detail "Asset information collected."

        return $assetInventory
    }
    catch {
        Write-InventoryLog "Asset inventory collection failed: $($_.Exception.Message)" -Level "ERROR"
        Write-InventoryResult -Task "Asset Inventory" -Status "ERROR" -Detail $_.Exception.Message
        return $null
    }
}

# ========================================
# EXPORT INVENTORY REPORT
# ========================================

function Export-InventoryReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [ValidateSet("JSON", "CSV")]
        [string]$Format = "JSON"
    )

    Write-InventoryLog "Exporting inventory report to $Path..." -Level "INFO"

    try {
        $inventoryData = [PSCustomObject] @{
            Hardware        = Get-HardwareInventory
            OperatingSystem = Get-OperatingSystemInventory
            Software        = Get-SoftwareInventory
            Asset          = Get-AssetInventory
        }

        if ($Format -eq "JSON") {
            $inventoryData | ConvertTo-Json -Depth 20 | Out-File -FilePath $Path -Encoding UTF8 -Force
        }
        else {
            $inventoryData | ConvertTo-Csv -Delimiter "," -NoTypeInformation | Out-File -FilePath $Path -Encoding UTF8 -Force
        }

        Write-InventoryLog "Inventory report exported successfully as $Format to: $Path" -Level "OK"
        Write-InventoryResult -Task "Inventory Report Export" -Status "OK" -Detail "Inventory report exported successfully as $Format to: $Path"

        return $Path
    }
    catch {
        Write-InventoryLog "Failed to export inventory report: $($_.Exception.Message)" -Level "ERROR"
        Write-InventoryResult -Task "Inventory Report Export" -Status "ERROR" -Detail $_.Exception.Message
        throw
    }
}

# ========================================
# MAIN INVENTORY ORCHESTRATOR
# ========================================

function Invoke-Inventory {
    [CmdletBinding()]
    param()

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $results = New-Object System.Collections.Generic.List[object]

    try {
        Write-InventoryLog "===== STARTING INVENTORY MODULE =====" -Level "INFO"

        $hardwareResult = Get-HardwareInventory
        if ($hardwareResult) { [void]$results.Add($hardwareResult) }

        $osResult = Get-OperatingSystemInventory
        if ($osResult) { [void]$results.Add($osResult) }

        $softwareResult = Get-SoftwareInventory
        if ($softwareResult) { [void]$results.Add($softwareResult) }

        $assetResult = Get-AssetInventory
        if ($assetResult) { [void]$results.Add($assetResult) }

        $stopwatch.Stop()

        $overallStatus = if ($results.Count -gt 0) { "OK" } else { "ERROR" }
        $detail = "Inventory module completed with status $overallStatus in $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s. Collected $($results.Count) inventory sections."

        Write-InventoryLog $detail -Level $overallStatus
        Write-InventoryResult -Task "System Inventory" -Status $overallStatus -Detail $detail

        $result = [PSCustomObject] @{
            Task           = "System Inventory"
            Status         = $overallStatus
            Detail         = $detail
            ElapsedSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
            Results        = $results
        }

        return $result
    }
    catch {
        if ($stopwatch.IsRunning) {
            $stopwatch.Stop()
        }

        $detail = $_.Exception.Message

        Write-InventoryLog "Inventory module failed: $detail" -Level "ERROR"
        Write-InventoryResult -Task "System Inventory" -Status "ERROR" -Detail $detail

        $result = [PSCustomObject] @{
            Task           = "System Inventory"
            Status         = "ERROR"
            Detail         = $detail
            ElapsedSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
            Results        = $results
        }

        return $result
    }
    finally {
        Write-InventoryLog "===== INVENTORY MODULE FINISHED =====" -Level "INFO"
    }
}

Export-ModuleMember -Function `
    Get-HardwareInventory,
    Get-OperatingSystemInventory,
    Get-SoftwareInventory,
    Get-AssetInventory,
    Export-InventoryReport,
    Invoke-Inventory