<#
.SYNOPSIS
    Centralized logging subsystem for ITechBR framework.

.DESCRIPTION
    Provides timestamped logging, log initialization,
    and centralized log file management.
#>
function Initialize-Logging {
    param(
        [string]$LogDirectory = "C:\Logs"
    )

    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }

    $script:Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:LogPath = Join-Path $LogDirectory "itechbr-$script:Timestamp.log"

    return $script:LogPath
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "OK", "WARN", "ERROR", "SKIPPED")]
        [string]$Level = "INFO"
    )

    if (-not $script:LogPath) {
        throw "Logging system not initialized. Run Initialize-Logging first."
    }

    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$time [$Level] $Message"

    $line | Out-File -FilePath $script:LogPath -Append -Encoding ascii

    switch ($Level) {
        "OK"      { Write-Host $line -ForegroundColor Green }
        "WARN"    { Write-Host $line -ForegroundColor Yellow }
        "ERROR"   { Write-Host $line -ForegroundColor Red }
        "SKIPPED" { Write-Host $line -ForegroundColor DarkGray }
        Default   { Write-Host $line -ForegroundColor Cyan }
    }
}

Export-ModuleMember -Function Initialize-Logging, Write-Log