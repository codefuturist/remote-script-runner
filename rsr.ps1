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
$ScriptsPath = Join-Path $ScriptRoot "scripts"
$ScriptsPwshPath = Join-Path $ScriptsPath "powershell"
$ScriptsPkgPath = Join-Path $ScriptsPath "packages"
$ScriptsSecurityPath = Join-Path $ScriptsPath "security"
$ScriptsSystemPath = Join-Path $ScriptsPath "system"

function Show-RSRHelp {
    Write-Host @"
RSR - Remote Script Runner for Windows

Usage:
    rsr <script> [arguments]

Available scripts:
    bootstrap   Host bootstrap wizard (essential tools, SSH, security)
    usermgmt    User management (create, delete, password, group, ssh, session)
    pkg         Package management (install, list, info)
    policy      Configure PowerShell execution policy (interactive wizard)
    wsl         WSL2 setup wizard (install, configure, manage Linux)
    setup       Windows development environment setup (WSL, tools, presets)
    devenv      Development environment diagnostics (proxy, Defender, network)
    health      System health check (coming soon)

Examples:
    rsr bootstrap                                # Interactive bootstrap wizard
    rsr bootstrap -Profile server                # Server setup profile
    rsr bootstrap -Profile dev -DryRun           # Dev setup (dry run)
    rsr usermgmt create -u john -c "John Doe"
    rsr usermgmt list --admin
    rsr pkg                                      # Interactive wizard
    rsr pkg -List                                # List profiles
    rsr pkg -Profile core                        # Install profile
    rsr pkg -Profile development.languages.python # Install group
    rsr pkg -Interactive                         # Launch wizard
    rsr pkg -Profile core -Force                 # No prompts
    rsr policy                                   # Interactive policy wizard
    rsr policy -Status                           # Show current policies
    rsr policy -Scope CurrentUser -Policy RemoteSigned  # Set policy
    rsr wsl                                      # WSL setup wizard
    rsr wsl -ListDistros                         # List available Linux distros
    rsr wsl -Distro Debian                       # Install specific distro
    rsr setup                                    # Windows environment setup wizard
    rsr setup -Component wsl                     # Install WSL only
    rsr setup -Preset devops                     # DevOps tools preset
    rsr devenv                                   # Run all diagnostics
    rsr devenv -ConfigureDefender                # Add Defender exclusions
    rsr devenv -EnableDevMode                    # Enable Developer Mode

Documentation:
    https://github.com/codefuturist/remote-script-runner

"@
}

# Main routing
switch ($Script) {
    'bootstrap' {
        # Host bootstrap wizard
        $bootstrapScript = Join-Path $ScriptsSystemPath "bootstrap\Initialize-HostBootstrap.ps1"
        if (Test-Path $bootstrapScript) {
            if ($Arguments.Count -eq 0) {
                & $bootstrapScript
            } else {
                & $bootstrapScript @Arguments
            }
        } else {
            Write-Host "Bootstrap script not found at: $bootstrapScript" -ForegroundColor Red
            exit 1
        }
    }
    'usermgmt' {
        & "$ScriptsPwshPath\UserManagement.ps1" @Arguments
    }
    'pkg' {
        # If no arguments, launch interactive wizard
        if ($Arguments.Count -eq 0) {
            & "$ScriptsPkgPath\Install-PackageProfile.ps1" -Interactive
        } else {
            & "$ScriptsPkgPath\Install-PackageProfile.ps1" @Arguments
        }
    }
    'policy' {
        # Execution policy configuration
        $policyScript = Join-Path $ScriptsSecurityPath "hardening\Set-RSRExecutionPolicy.ps1"
        if ($Arguments.Count -eq 0) {
            & $policyScript -Interactive
        } else {
            & $policyScript @Arguments
        }
    }
    'wsl' {
        # WSL2 setup wizard
        $wslScript = Join-Path $ScriptsSystemPath "Install-WSL.ps1"
        if ($Arguments.Count -eq 0) {
            & $wslScript
        } else {
            & $wslScript @Arguments
        }
    }
    'setup' {
        # Windows development environment setup
        $setupScript = Join-Path $ScriptsSystemPath "Setup-WindowsEnvironment.ps1"
        if ($Arguments.Count -eq 0) {
            & $setupScript
        } else {
            & $setupScript @Arguments
        }
    }
    'devenv' {
        # Development environment diagnostics
        $devenvScript = Join-Path $ScriptsSystemPath "Configure-DevEnvironment.ps1"
        if ($Arguments.Count -eq 0) {
            & $devenvScript -CheckAll
        } else {
            & $devenvScript @Arguments
        }
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

