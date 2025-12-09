@echo off
REM rsr.cmd - Windows batch wrapper for RSR
REM Allows running RSR from Command Prompt with: rsr usermgmt create -u john

setlocal enabledelayedexpansion

REM Get script directory
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

REM Run PowerShell script with all arguments
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%SCRIPT_DIR%\rsr.ps1" %*

endlocal

