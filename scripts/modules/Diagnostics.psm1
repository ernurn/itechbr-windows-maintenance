<#
    .SYNOPSIS
        Itech Pure Diagnostics and System Inspection Module.
    .DESCRIPTION
        This module performs read-only system inspection and metric gathering.
        It does not alter, repair, or optimize any system configuration.
#>

function Get-OperatingSystemInfo {
    [CmdletBinding()]
    param()
    process {
        try {
            Write-Log "Collecting operating system information..." -Level "INFO"
            $OS = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            $Computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            $Bios = Get-CimInstance -ClassName Win32_Bios -ErrorAction Stop

            [PSCustomObject]@{
                OSName        = $OS.Caption
                Version       = $OS.Version
                Architecture  = $OS.OSArchitecture
                SerialNumber  = $Bios.SerialNumber
                HostName      = $Computer.Name
                Manufacturer  = $Computer.Manufacturer
                Model         = $Computer.Model
            }
        }
        catch {
            if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
                Write-Log "Failed to retrieve operating system information: $($_.Exception.Message)" -Level "ERROR"
            }
            return $null
        }
    }
}

function Get-MemoryInfo {
    [CmdletBinding()]
    param()

    process {
        try {
            Write-Log "Collecting memory statistics..." -Level "INFO"
            $OS = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            $PhysicalMemory = Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction SilentlyContinue

            $TotalRam = [Math]::Round(($OS.TotalVisibleMemorySize / 1MB), 2)
            $FreeRam  = [Math]::Round(($OS.FreePhysicalMemory / 1MB), 2)
            $UsedRam  = [Math]::Round(($TotalRam - $FreeRam), 2)

            $MemoryUsagePct = if ($TotalRam -gt 0) {
                [Math]::Round(($UsedRam / $TotalRam) * 100, 2)
            }
            else {
                0
            }

            $SlotsFilled = ($PhysicalMemory | Measure-Object).Count

            $Speed = if ($PhysicalMemory) {
                ($PhysicalMemory | Select-Object -First 1).Speed
            }
            else {
                $null
            }

            [PSCustomObject]@{
                TotalMemoryGB     = $TotalRam
                UsedMemoryGB      = $UsedRam
                FreeMemoryGB      = $FreeRam
                MemoryUsagePct    = $MemoryUsagePct
                PhysicalSlotsUsed = $SlotsFilled
                ClockSpeedMHz     = $Speed
            }
        }
        catch {
            if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
                Write-Log "Failed to retrieve Memory metrics: $($_.Exception.Message)" -Level "ERROR"
            }

            return $null
        }
    }
}

function Get-DiskUsageInfo {
    [CmdletBinding()]
    param()

    process {
        try {
            Write-Log "Collecting logical disk utilization metrics..." -Level "INFO"
            $Volumes = Get-CimInstance `
                -ClassName Win32_LogicalDisk `
                -Filter "DriveType=3" `
                -ErrorAction Stop

            $Result = foreach ($Volume in $Volumes) {

                $TotalSize = [Math]::Round(($Volume.Size / 1GB), 2)
                $FreeSpace = [Math]::Round(($Volume.FreeSpace / 1GB), 2)
                $UsedSpace = [Math]::Round(($TotalSize - $FreeSpace), 2)

                $FreeSpacePct = if ($TotalSize -gt 0) {
                    [Math]::Round(($FreeSpace / $TotalSize) * 100, 2)
                }
                else {
                    0
                }

                [PSCustomObject]@{
                    DriveLetter = $Volume.DeviceID
                    VolumeName = if ([string]::IsNullOrWhiteSpace($Volume.VolumeName)) {
                        "Unnamed"
                    }
                    else {
                        $Volume.VolumeName
                    }
                    FileSystem   = $Volume.FileSystem
                    TotalSizeGB  = $TotalSize
                    UsedSpaceGB  = $UsedSpace
                    FreeSpaceGB  = $FreeSpace
                    FreeSpacePct = $FreeSpacePct
                }
            }

            return $Result
        }
        catch {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log "Failed to gather volume capacity info: $($_.Exception.Message)" -Level "ERROR"
            }

            return $null
        }
    }
}

function Get-SystemUptime {
    [CmdletBinding()]
    param()
    process {
        try {
            Write-Log "Collecting system uptime information..." -Level "INFO"
            $OS = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            $LastBoot = $OS.LastBootUpTime
            $UptimeSpan = (Get-Date) - $LastBoot

            [PSCustomObject]@{
                LastBootUpTime = $LastBoot
                UptimeDays     = $UptimeSpan.Days
                UptimeHours    = $UptimeSpan.Hours
                UptimeMinutes  = $UptimeSpan.Minutes
                Formatted      = "$($UptimeSpan.Days)d, $($UptimeSpan.Hours)h, $($UptimeSpan.Minutes)m"
            }
        }
        catch {
            if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
                 Write-Log "Failed to calculate system uptime: $($_.Exception.Message)" -Level "ERROR"
            }
            return $null
        }
    }
}

function Get-DiskHealthInfo {
    [CmdletBinding()]
    param()

    process {
        try {
            Write-Log "Collecting physical disk health information..." -Level "INFO"
            $PhysicalDisks = Get-CimInstance `
                -ClassName MSFT_PhysicalDisk `
                -Namespace root\Microsoft\Windows\Storage `
                -ErrorAction Stop

            foreach ($Disk in $PhysicalDisks) {

                $MediaTypeString = switch ($Disk.MediaType) {
                    3 { "SSD" }
                    4 { "HDD" }
                    5 { "SCM" }
                    default { "Unknown" }
                }

                [PSCustomObject]@{
                    DeviceID = $Disk.DeviceId

                    FriendlyName = if ([string]::IsNullOrWhiteSpace($Disk.FriendlyName)) {
                        "Unknown"
                    }
                    else {
                        $Disk.FriendlyName.Trim()
                    }

                    MediaType    = $MediaTypeString
                    HealthStatus = $Disk.HealthStatus
                    Operational  = ($Disk.OperationalStatus -join ", ")
                }
            }
        }
        catch {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log "Storage API failed to return physical health metrics: $($_.Exception.Message)" -Level "WARN"
            }

            return $null
        }
    }
}

function Get-CriticalEvents {
    [CmdletBinding()]
    param([int]$MaxEvents = 5)
    process {
        try {
            Write-Log "Collecting critical system events..." -Level "INFO"
            # Filter for unclean shutdowns (Event ID 41) and BugChecks/BSODs (Event ID 1001)
            $FilterHash = @{
                LogName   = 'System'
                Id        = 41, 1001
                StartTime = (Get-Date).AddDays(-30)
            }

            $Events = Get-WinEvent -FilterHashtable $FilterHash -MaxEvents $MaxEvents -ErrorAction SilentlyContinue

            if (-not $Events) {
                return @()
            }

            $Result = foreach ($Event in $Events) {
                [PSCustomObject]@{
                    Timestamp = $Event.TimeCreated
                    EventID   = $Event.Id
                    Provider  = $Event.ProviderName
                    Summary   = $Event.Message.Split([environment]::NewLine)[0]
                }
            }
            return $Result
        }
        catch {
            if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
                Write-Log "Failed to query critical system events: $($_.Exception.Message)" -Level "WARN"
            }
            return $null
        }
    }
}

function Get-NetworkInfo {
    [CmdletBinding()]
    param()

    process {
        try {
            Write-Log "Collecting network adapter information..." -Level "INFO"
            $Adapters = Get-CimInstance `
                -ClassName Win32_NetworkAdapterConfiguration `
                -Filter "IPEnabled = True" `
                -ErrorAction Stop

            foreach ($Adapter in $Adapters) {

                [PSCustomObject]@{
                    Description = $Adapter.Description

                    IPAddress = if ($Adapter.IPAddress) {
                        ($Adapter.IPAddress -join ", ")
                    }
                    else {
                        "Unavailable"
                    }

                    SubnetMask = if ($Adapter.IPSubnet) {
                        ($Adapter.IPSubnet -join ", ")
                    }
                    else {
                        "Unavailable"
                    }

                    DefaultGateway = if ($Adapter.DefaultIPGateway) {
                        ($Adapter.DefaultIPGateway -join ", ")
                    }
                    else {
                        "Unavailable"
                    }

                    DNSServers = if ($Adapter.DNSServerSearchOrder) {
                        ($Adapter.DNSServerSearchOrder -join ", ")
                    }
                    else {
                        "Unavailable"
                    }

                    DHCPEnabled = $Adapter.DHCPEnabled

                    MACAddress = if ($Adapter.MACAddress) {
                        $Adapter.MACAddress
                    }
                    else {
                        "Unavailable"
                    }
                }
            }
        }
        catch {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log "Failed to retrieve network adapter information: $($_.Exception.Message)" -Level "ERROR"
            }

            return $null
        }
    }
}

function Get-WindowsUpdateStatus {
    [CmdletBinding()]
    param()

    process {
        try {
            Write-Log "Collecting Windows Update status..." -Level "INFO"

            $LastHotfix = Get-HotFix |
                Sort-Object InstalledOn -Descending |
                Select-Object -First 1

            if (-not $LastHotfix) {
                return [PSCustomObject]@{
                    LastInstalledUpdate = "Unknown"
                    InstalledOn         = $null
                    Description         = "No update information available"
                }
            }

            return [PSCustomObject]@{
                LastInstalledUpdate = $LastHotfix.HotFixID
                InstalledOn         = $LastHotfix.InstalledOn
                Description         = $LastHotfix.Description
            }
        }
        catch {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log "Failed to retrieve Windows Update status: $($_.Exception.Message)" -Level "ERROR"
            }

            return $null
        }
    }
}

Export-ModuleMember -Function `
    Get-OperatingSystemInfo, 
    Get-MemoryInfo, 
    Get-DiskUsageInfo, 
    Get-SystemUptime, 
    Get-DiskHealthInfo, 
    Get-CriticalEvents,
    Get-NetworkInfo, 
    Get-WindowsUpdateStatus