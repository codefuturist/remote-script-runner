#!/usr/bin/env pwsh
<#
.SYNOPSIS
    RSR - Remote Script Runner entry point for Windows (PowerShell)

.DESCRIPTION
    Universal entry point for Remote Script Runner on Windows.
    Provides the same command syntax as the Unix version.

.PARAMETER Script
    Script name to execute (usermgmt, health, etc.)

.PARAMETER Arguments
    Arguments to pass to the script

.EXAMPLE
    .\rsr.ps1 usermgmt create -u john -c "John Doe"

.EXAMPLE
    .\rsr.ps1 usermgmt password reset -u john

.EXAMPLE
    .\rsr.ps1 usermgmt ssh add -u john -f key.pub

.NOTES
    Version: 1.0.0
    Platform: Windows (PowerShell 5.1+)
#>

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Script,

    [Parameter(Position=1, ValueFromRemainingArguments)]
    [string[]]$Arguments
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = $PSScriptRoot
$ScriptsPath = Join-Path $ScriptRoot "scripts\powershell"

function Show-RSRHelp {
    Write-Host @"
RSR - Remote Script Runner for Windows

Usage:
    rsr <script> [arguments]

Available scripts:
    usermgmt    User management (create, delete, password, group, ssh, session)
    health      System health check (coming soon)

Examples:
    rsr usermgmt create -u john -c "John Doe"
    rsr usermgmt list --admin
    rsr usermgmt password reset -u john
    rsr usermgmt ssh generate -u john -t ed25519
    rsr usermgmt session list

Documentation:
    https://github.com/codefuturist/remote-script-runner

"@
}

# Main routing
switch ($Script) {
    'usermgmt' {
        & "$ScriptsPath\UserManagement.ps1" @Arguments
    }
    'health' {
        Write-Host "System health check coming soon for Windows" -ForegroundColor Yellow
    }
    { $_ -in '-h', '--help', 'help', $null, '' } {
        Show-RSRHelp
    }
    default {
        Write-Host "Unknown script: $Script" -ForegroundColor Red
        Write-Host ""
        Show-RSRHelp
        exit 1
    }
}

