function Test-AdministrativePrivileges {
    <#
    .SYNOPSIS
        Checks if the current PowerShell session has Administrator privileges.
    .DESCRIPTION
        Returns a boolean value ($true or $false) by analyzing the Windows token.
        Does not interrupt script execution.
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-AdministrativePrivileges {
    <#
    .SYNOPSIS
        Enforces Administrator privileges for the current execution context.
    .DESCRIPTION
        Invokes Test-AdministrativePrivileges. If the result is $false,
        it throws a critical exception and interrupts framework execution.
    #>
    if (-not (Test-AdministrativePrivileges)) {
               
        # Future integration with Logging subsystem:
        # Write-ITechLog -Message "Execution attempt denied: Missing administrative token." -Level "CRITICAL"
        
        throw "Execution aborted due to missing Administrator privileges."
    }
}

# Export module members to make them available across the framework
Export-ModuleMember -Function Test-AdministrativePrivileges, Assert-AdministrativePrivileges