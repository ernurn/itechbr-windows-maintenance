<#'
.SYNOPSIS
    ITechBR TextNormalization Module Test Suite.

.DESCRIPTION
    Validates TextNormalization.psm1 functionality including ASCII-safe conversion
    and text normalization for case-insensitive pattern matching.

.USAGE
    .\scripts\tests\TextNormalization.Tests.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:CorePath = Join-Path (Split-Path $script:TestRoot) 'core'

# Load module
Import-Module (Join-Path $script:CorePath 'TextNormalization.psm1') -Force

$Results = @()

function Test-ConvertTextToAsciiSafe_Basic {
    try {
        $result = Convert-TextToAsciiSafe -Text 'test string'
        if ($result -ne 'test string') {
            throw "Convert-TextToAsciiSafe: 'test string' -> '$result'"
        }
        return @{ Passed = $true; Message = 'Basic ASCII input unchanged' }
    }
    catch {
        return @{ Passed = $false; Message = $_.Exception.Message }
    }
}

function Test-ConvertTextToAsciiSafe_DiacriticsRemoval {
    try {
        # Test common diacritics
        $tests = @(
            @{ Input = 'café'; Expected = 'cafe' },
            @{ Input = 'naïve'; Expected = 'naive' },
            @{ Input = 'résumé'; Expected = 'resume' },
            @{ Input = 'São Paulo'; Expected = 'Sao Paulo' },
            @{ Input = 'ção'; Expected = 'cao' }
        )
        foreach ($test in $tests) {
            $result = Convert-TextToAsciiSafe -Text $test.Input
            if ($result -ne $test.Expected) {
                throw "Convert-TextToAsciiSafe: '$($test.Input)' -> '$result' (expected '$($test.Expected)')"
            }
        }
        return @{ Passed = $true; Message = 'Diacritics removed correctly' }
    }
    catch {
        return @{ Passed = $false; Message = $_.Exception.Message }
    }
}

function Test-ConvertTextToAsciiSafe_EmptyString {
    try {
        $result = Convert-TextToAsciiSafe -Text ''
        if ($result -ne '') {
            throw "Convert-TextToAsciiSafe: empty string -> '$result'"
        }
        return @{ Passed = $true; Message = 'Empty string handled' }
    }
    catch {
        return @{ Passed = $false; Message = $_.Exception.Message }
    }
}

function Test-ConvertTextToAsciiSafe_NullInput {
    try {
        $result = Convert-TextToAsciiSafe -Text $null
        if ($result -ne '') {
            throw "Convert-TextToAsciiSafe: null input -> '$result'"
        }
        return @{ Passed = $true; Message = 'Null input handled' }
    }
    catch {
        return @{ Passed = $false; Message = $_.Exception.Message }
    }
}

function Test-ConvertTextForMatch_Basic {
    try {
        $result = Convert-TextForMatch -Text 'Test String'
        if ($result -ne 'test string') {
            throw "Convert-TextForMatch: 'Test String' -> '$result'"
        }
        return @{ Passed = $true; Message = 'Basic lowercase conversion works' }
    }
    catch {
        return @{ Passed = $false; Message = $_.Exception.Message }
    }
}

function Test-ConvertTextForMatch_DiacriticsAndLowercase {
    try {
        $tests = @(
            @{ Input = 'Café'; Expected = 'cafe' },
            @{ Input = 'São Paulo'; Expected = 'sao paulo' },
            @{ Input = 'RÉSUMÉ'; Expected = 'resume' },
            @{ Input = 'ação'; Expected = 'acao' }
        )
        foreach ($test in $tests) {
            $result = Convert-TextForMatch -Text $test.Input
            if ($result -ne $test.Expected) {
                throw "Convert-TextForMatch: '$($test.Input)' -> '$result' (expected '$($test.Expected)')"
            }
        }
        return @{ Passed = $true; Message = 'Diacritics removed and lowercase applied' }
    }
    catch {
        return @{ Passed = $false; Message = $_.Exception.Message }
    }
}

function Test-ConvertTextForMatch_EmptyString {
    try {
        $result = Convert-TextForMatch -Text ''
        if ($result -ne '') {
            throw "Convert-TextForMatch: empty string -> '$result'"
        }
        return @{ Passed = $true; Message = 'Empty string handled' }
    }
    catch {
        return @{ Passed = $false; Message = $_.Exception.Message }
    }
}

function Test-ConvertTextForMatch_WhitespaceOnly {
    try {
        $result = Convert-TextForMatch -Text '   '
        if ($result -ne '') {
            throw "Convert-TextForMatch: whitespace only -> '$result'"
        }
        return @{ Passed = $true; Message = 'Whitespace only handled' }
    }
    catch {
        return @{ Passed = $false; Message = $_.Exception.Message }
    }
}

function Test-ConvertTextForMatch_NullInput {
    try {
        $result = Convert-TextForMatch -Text $null
        if ($result -ne '') {
            throw "Convert-TextForMatch: null input -> '$result'"
        }
        return @{ Passed = $true; Message = 'Null input handled' }
    }
    catch {
        return @{ Passed = $false; Message = $_.Exception.Message }
    }
}

# Execute tests
$Results += Test-ConvertTextToAsciiSafe_Basic
$Results += Test-ConvertTextToAsciiSafe_DiacriticsRemoval
$Results += Test-ConvertTextToAsciiSafe_EmptyString
$Results += Test-ConvertTextToAsciiSafe_NullInput
$Results += Test-ConvertTextForMatch_Basic
$Results += Test-ConvertTextForMatch_DiacriticsAndLowercase
$Results += Test-ConvertTextForMatch_EmptyString
$Results += Test-ConvertTextForMatch_WhitespaceOnly
$Results += Test-ConvertTextForMatch_NullInput

# Report
Write-Host "`nTextNormalization Module Test Results:" -ForegroundColor Cyan
$Results | Format-Table -AutoSize | Out-String | Write-Host

if ($Results.Passed -contains $false) {
    Write-Host "`n[FAIL] TextNormalization tests failed" -ForegroundColor Red
    exit 1
}
else {
    Write-Host "`n[PASS] All TextNormalization tests passed" -ForegroundColor Green
    exit 0
}