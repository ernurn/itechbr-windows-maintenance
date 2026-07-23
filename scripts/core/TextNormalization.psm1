<#
.SYNOPSIS
    Text normalization utilities for ITechBR framework.

.DESCRIPTION
    Provides functions for converting text to ASCII-safe representations
    and normalizing text for case-insensitive pattern matching.
#>

Set-StrictMode -Version Latest

function Convert-TextToAsciiSafe {
    param(
        [string]$Text
    )
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    # Remove diacritics by normalizing and stripping non-spacing marks
    $normalized = $Text.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($char in $normalized.ToCharArray()) {
        $category = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($char)
        if ($category -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($char)
        }
    }
    return $sb.ToString()
}

function Convert-TextForMatch {
    param(
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

Export-ModuleMember -Function Convert-TextToAsciiSafe, Convert-TextForMatch