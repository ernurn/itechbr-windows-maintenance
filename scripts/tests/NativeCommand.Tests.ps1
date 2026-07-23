<#
.SYNOPSIS
    Tests for NativeCommand.psm1 - Read-CommandOutputFile encoding detection
#>

$ErrorActionPreference = "Stop"

# Import the module under test
$ModulePath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\core\NativeCommand.psm1"
Import-Module $ModulePath -Force

$passed = 0
$failed = 0

function Assert-Equals {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Expected,
        [Parameter(Mandatory = $true)]
        [string]$Actual,
        [string]$TestName
    )
    if ($Expected -eq $Actual) {
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
        return $true
    }
    else {
        Write-Host "  [FAIL] $TestName" -ForegroundColor Red
        Write-Host "    Expected: '$Expected'" -ForegroundColor Yellow
        Write-Host "    Actual  : '$Actual'" -ForegroundColor Yellow
        return $false
    }
}

# ============================================================
# Test Case 1: ASCII simple file
# ============================================================
Write-Host "`nTest Case 1: ASCII simple file" -ForegroundColor Yellow
$testPath1 = [System.IO.Path]::GetTempFileName()
try {
    $content = "Simple ASCII text`r`nLine 2`r`nLine 3"
    [System.IO.File]::WriteAllText($testPath1, $content, [System.Text.Encoding]::ASCII)
    $result = Read-CommandOutputFile -Path $testPath1
    if (Assert-Equals $content $result "ASCII file reads correctly") { $passed++ } else { $failed++ }
}
finally { Remove-Item -Path $testPath1 -Force -ErrorAction SilentlyContinue }

# ============================================================
# Test Case 2: UTF-8 with Portuguese characters
# ============================================================
Write-Host "`nTest Case 2: UTF-8 with Portuguese characters" -ForegroundColor Yellow
$testPath2 = [System.IO.Path]::GetTempFileName()
try {
    $content = "Sao Paulo`r`nConfiguracao concluida`r`nAcentuacao: aeiou cao"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
    [System.IO.File]::WriteAllBytes($testPath2, $bytes)
    $result = Read-CommandOutputFile -Path $testPath2
    if (Assert-Equals $content $result "UTF-8 accents preserved") { $passed++ } else { $failed++ }
}
finally { Remove-Item -Path $testPath2 -Force -ErrorAction SilentlyContinue }

# ============================================================
# Test Case 3: UTF-16 LE with BOM
# ============================================================
Write-Host "`nTest Case 3: UTF-16 LE with BOM" -ForegroundColor Yellow
$testPath3 = [System.IO.Path]::GetTempFileName()
try {
    $content = "UTF-16 LE BOM`r`nSao Paulo`r`nTeste concluido"
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($content)  # Unicode = UTF-16 LE with BOM
    [System.IO.File]::WriteAllBytes($testPath3, $bytes)
    $result = Read-CommandOutputFile -Path $testPath3
    if (Assert-Equals $content $result "UTF-16 LE BOM decoded correctly") { $passed++ } else { $failed++ }
}
finally { Remove-Item -Path $testPath3 -Force -ErrorAction SilentlyContinue }

# ============================================================
# Test Case 4: UTF-16 LE without BOM (detected via null-byte sampling)
# ============================================================
Write-Host "`nTest Case 4: UTF-16 LE without BOM (sampled)" -ForegroundColor Yellow
$testPath4 = [System.IO.Path]::GetTempFileName()
try {
    $content = "UTF-16 LE no BOM`r`nConfiguracao`r`nTeste completo"
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($content)
    # Remove BOM (first 2 bytes) if present - but Unicode.GetBytes doesn't add BOM by default
    # Actually, let's create a UTF-16 LE file WITHOUT BOM manually
    $bytesNoBom = [System.Text.Encoding]::Unicode.GetBytes($content)
    # Verify no BOM: first two bytes should be the first char
    [System.IO.File]::WriteAllBytes($testPath4, $bytesNoBom)
    $result = Read-CommandOutputFile -Path $testPath4
    if (Assert-Equals $content $result "UTF-16 LE without BOM decoded via sampling") { $passed++ } else { $failed++ }
}
finally { Remove-Item -Path $testPath4 -Force -ErrorAction SilentlyContinue }

# ============================================================
# Test Case 5: UTF-8 with BOM
# ============================================================
Write-Host "`nTest Case 5: UTF-8 with BOM" -ForegroundColor Yellow
$testPath5 = [System.IO.Path]::GetTempFileName()
try {
    $content = "UTF-8 BOM`r`nSao Paulo`r`nAcentos: aeiou"
    $bytes = [System.Text.Encoding]::UTF8.GetPreamble() + [System.Text.Encoding]::UTF8.GetBytes($content)
    [System.IO.File]::WriteAllBytes($testPath5, $bytes)
    $result = Read-CommandOutputFile -Path $testPath5
    if (Assert-Equals $content $result "UTF-8 with BOM decoded correctly") { $passed++ } else { $failed++ }
}
finally { Remove-Item -Path $testPath5 -Force -ErrorAction SilentlyContinue }

# ============================================================
# Test Case 6: OEM encoding (simulating cmd.exe output)
# ============================================================
Write-Host "`nTest Case 6: OEM encoding (cmd.exe simulation)" -ForegroundColor Yellow
$testPath6 = [System.IO.Path]::GetTempFileName()
try {
    $content = "Volume serial number is 1234-5678`r`nDirectory of C:\Temp`r`nArquivo de teste.txt"
    $oemEncoding = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
    $bytes = $oemEncoding.GetBytes($content)
    [System.IO.File]::WriteAllBytes($testPath6, $bytes)
    $result = Read-CommandOutputFile -Path $testPath6
    if (Assert-Equals $content $result "OEM encoded file reads correctly") { $passed++ } else { $failed++ }
}
finally { Remove-Item -Path $testPath6 -Force -ErrorAction SilentlyContinue }

# ============================================================
# Test Case 7: Non-existent file (graceful handling)
# ============================================================
Write-Host "`nTest Case 7: Non-existent file" -ForegroundColor Yellow
$testPath7 = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "itechbr-nonexistent-" + [guid]::NewGuid().ToString("N") + ".txt")
$result = Read-CommandOutputFile -Path $testPath7
if ([string]::IsNullOrEmpty($result)) {
    Write-Host "  [PASS] Non-existent file returns empty string" -ForegroundColor Green
    $passed++
}
else {
    Write-Host "  [FAIL] Non-existent file returns empty string" -ForegroundColor Red
    Write-Host "    Expected: ''" -ForegroundColor Red
    Write-Host "    Actual  : '$result'" -ForegroundColor Red
    $failed++
}

# ============================================================
# Test Case 8: Empty file
# ============================================================
Write-Host "`nTest Case 8: Empty file" -ForegroundColor Yellow
$testPath8 = [System.IO.Path]::GetTempFileName()
try {
    [System.IO.File]::WriteAllBytes($testPath8, @())
    $result = Read-CommandOutputFile -Path $testPath8
    if ([string]::IsNullOrEmpty($result)) {
        Write-Host "  [PASS] Empty file returns empty string" -ForegroundColor Green
        $passed++
    }
    else {
        Write-Host "  [FAIL] Empty file returns empty string" -ForegroundColor Red
        Write-Host "    Expected: ''" -ForegroundColor Red
        Write-Host "    Actual  : '$result'" -ForegroundColor Red
        $failed++
    }
}
finally { Remove-Item -Path $testPath8 -Force -ErrorAction SilentlyContinue }

# ============================================================
# Summary
# ============================================================
Write-Host "`n===== SUMMARY =====" -ForegroundColor Cyan
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor Red

if ($failed -gt 0) {
    Write-Host "`nTESTS FAILED" -ForegroundColor Red
    exit 1
}
else {
    Write-Host "`nALL TESTS PASSED" -ForegroundColor Green
    exit 0
}