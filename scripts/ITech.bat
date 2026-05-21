@echo off
title ITechBR Windows Maintenance
color 0A
setlocal EnableExtensions

:: Base directory
set BASE_DIR=%~dp0

:: Main script
set PS_SCRIPT=%BASE_DIR%main.ps1

echo ============================================
echo        ITechBR Windows Maintenance
echo ============================================
echo.

:: Verify script exists
if not exist "%PS_SCRIPT%" (
    echo ERROR: PowerShell script not found:
    echo %PS_SCRIPT%
    echo.
    pause
    exit /b 1
)

:: Check administrator privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

echo Running maintenance workflow...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"

echo.

if %errorlevel% neq 0 (
    echo Maintenance finished with errors.
) else (
    echo Maintenance completed successfully.
)

echo.
pause
endlocal