@echo off
REM Declutter - Windows Batch Launcher
REM Launches the PowerShell version of declutter

setlocal EnableDelayedExpansion

REM Get script directory
set "SCRIPT_DIR=%~dp0"

REM Check for PowerShell Core first, then Windows PowerShell
where pwsh >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    set "PS_EXE=pwsh"
) else (
    set "PS_EXE=powershell"
)

REM Run the PowerShell script with all arguments
%PS_EXE% -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%declutter.ps1" %*

exit /b %ERRORLEVEL%
