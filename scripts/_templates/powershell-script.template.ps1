<#
.SYNOPSIS
    {{SCRIPT_NAME}} - {{DESCRIPTION}}

.DESCRIPTION
    {{DETAILED_DESCRIPTION}}

.PARAMETER Help
    Show help message

.PARAMETER Verbose
    Enable verbose output

.PARAMETER DryRun
    Show what would be done without executing

.EXAMPLE
    .\{{SCRIPT_NAME}}.ps1 -Help

.EXAMPLE
    .\{{SCRIPT_NAME}}.ps1 -Verbose

.NOTES
    Version: 1.0.0
    Author:  {{AUTHOR}}
    License: MIT
#>

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Help,
    [switch]$Version
)

# =============================================================================
# Configuration
# =============================================================================

$ErrorActionPreference = 'Stop'
$Script:Name = '{{SCRIPT_NAME}}'
$Script:Version = '1.0.0'

# =============================================================================
# RSR Library
# =============================================================================

$RSRModulePath = Join-Path $PSScriptRoot '../../lib/powershell/RSR.psd1'

if (Test-Path $RSRModulePath) {
    Import-Module $RSRModulePath -Force -ErrorAction Stop
} else {
    Write-Error "RSR library not found at $RSRModulePath"
    exit 1
}

# =============================================================================
# Functions
# =============================================================================

function Show-Help {
    Get-Help $PSCommandPath -Detailed
}

function Show-Version {
    Write-Output "$($Script:Name) v$($Script:Version)"
}

# =============================================================================
# Main Logic
# =============================================================================

function Main {
    if ($Help) {
        Show-Help
        return
    }

    if ($Version) {
        Show-Version
        return
    }

    Write-RSRInfo "Starting $($Script:Name)..."

    if ($WhatIfPreference) {
        Write-RSRWarn "Dry run mode - no changes will be made"
    }

    # TODO: Implement main logic here

    Write-RSROk "Done!"
}

# =============================================================================
# Entry Point
# =============================================================================

Main

