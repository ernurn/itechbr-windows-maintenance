<#
.SYNOPSIS
    Centralized reporting subsystem for ITechBR framework.

.DESCRIPTION
    Provides centralized execution result tracking,
    task status collection, and reporting data
    management for maintenance workflows.
#>

$script:Results = New-Object System.Collections.Generic.List[object]

function Initialize-Reporting {   
    if ($null -eq $script:Results) {
        $script:Results = New-Object System.Collections.Generic.List[object]
    } else {
        $script:Results.Clear()
    }
}

function Add-Result {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Task,

        [Parameter(Mandatory = $true)]
        [ValidateSet("INFO", "OK", "WARN", "ERROR", "SKIPPED")]
        [string]$Status,

        [string]$Detail = ""
    )

    if ($null -eq $script:Results) {
        throw "Reporting system not initialized. Run Initialize-Reporting first."
    }

    $script:Results.Add([pscustomobject]@{
        Task   = $Task
        Status = $Status
        Detail = $Detail
    })
}

function Get-Results {
    if ($null -eq $script:Results) {
        throw "Reporting system not initialized. Run Initialize-Reporting first."
    }

    return $script:Results
}

Export-ModuleMember -Function Initialize-Reporting, Add-Result, Get-Results