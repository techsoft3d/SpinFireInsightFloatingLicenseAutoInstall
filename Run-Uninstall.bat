@echo off
setlocal
title SpinFire Insight - Floating License Manager Removal

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%Uninstall-FloatingLicenseServer.ps1"

if not exist "%PS_SCRIPT%" (
    echo.
    echo [ERROR] Uninstall-FloatingLicenseServer.ps1 was not found.
    echo Please make sure both files are in the same folder.
    echo.
    pause
    exit /b 1
)

:: If not running as admin, relaunch elevated
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting Administrator privileges - please approve the UAC prompt...
    powershell.exe -NoProfile -Command "Start-Process cmd.exe -ArgumentList '/c \"%~f0\"' -Verb RunAs -WorkingDirectory '%SCRIPT_DIR%'"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"

if %errorLevel% neq 0 (
    echo.
    echo ============================================================
    echo  Uninstall exited unexpectedly (exit code: %errorLevel%)
    echo  Check for FLM-Uninstall-*.log in this folder.
    echo ============================================================
    echo.
    pause
)

endlocal
