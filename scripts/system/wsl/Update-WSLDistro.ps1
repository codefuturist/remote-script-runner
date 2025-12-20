#!/usr/bin/env pwsh
#Requires -Version 5.1

<#
.SYNOPSIS
    Update and maintain WSL distributions
.DESCRIPTION
    Manages WSL distribution lifecycle:
    - Updates packages in WSL distros
    - Cleans up unused packages and cache
    - Checks for WSL updates
    - Manages distro lifecycle (start, stop, restart)
.PARAMETER Distro
    Target distribution (default: all installed)
.PARAMETER Update
    Update packages in the distribution
.PARAMETER Upgrade
    Perform full system upgrade
.PARAMETER Clean
    Clean package cache and unused packages
.PARAMETER Restart
    Restart the distribution (terminate and relaunch)
.PARAMETER Shutdown
    Shutdown all WSL distributions
.PARAMETER UpdateWSL
    Update WSL itself to the latest version
.PARAMETER ShowStatus
    Display status of all distributions
.EXAMPLE
    .\Update-WSLDistro.ps1 -Update
.EXAMPLE
    .\Update-WSLDistro.ps1 -Distro Ubuntu -Upgrade -Clean
.EXAMPLE
    .\Update-WSLDistro.ps1 -UpdateWSL
#>

[CmdletBinding(DefaultParameterSetName = 'Maintain')]
param(
    [string]$Distro,

    [Parameter(ParameterSetName = 'Maintain')]
    [switch]$Update,

    [Parameter(ParameterSetName = 'Maintain')]
    [switch]$Upgrade,

    [Parameter(ParameterSetName = 'Maintain')]
    [switch]$Clean,

    [Parameter(ParameterSetName = 'Lifecycle')]
    [switch]$Restart,

    [Parameter(ParameterSetName = 'Lifecycle')]
    [switch]$Shutdown,

    [Parameter(ParameterSetName = 'WSLUpdate')]
    [switch]$UpdateWSL,

    [Parameter(ParameterSetName = 'Status')]
    [switch]$ShowStatus
)

$ErrorActionPreference = 'Stop'

# =============================================================================
# UI Helpers
# =============================================================================

$Script:Colors = @{
    Success   = 'Green'
    Warning   = 'Yellow'
    Error     = 'Red'
    Info      = 'White'
    Muted     = 'DarkGray'
    Highlight = 'Cyan'
}

function Write-Status {
    param(
        [string]$Message,
        [ValidateSet('success', 'warning', 'error', 'info', 'pending')]
        [string]$Type = 'info'
    )
    $icons = @{ success = '✓'; warning = '⚠'; error = '✗'; info = 'ℹ'; pending = '○' }
    $colors = @{ success = 'Green'; warning = 'Yellow'; error = 'Red'; info = 'Cyan'; pending = 'DarkGray' }
    Write-Host "  $($icons[$Type]) " -ForegroundColor $colors[$Type] -NoNewline
    Write-Host $Message
}

function Write-Banner {
    param([string]$Text)
    Write-Host ""
    Write-Host "  $Text" -ForegroundColor $Script:Colors.Highlight
    Write-Host "  $('─' * $Text.Length)" -ForegroundColor $Script:Colors.Muted
}

# =============================================================================
# Detection Functions
# =============================================================================

function Get-InstalledDistros {
    try {
        $output = wsl.exe --list --verbose 2>&1 | Out-String
        $lines = $output -split "`r?`n" | Where-Object { $_ -match '\S' }

        $distros = @()
        $headerSkipped = $false

        foreach ($line in $lines) {
            if (-not $headerSkipped -and $line -match '^\s*NAME\s+STATE\s+VERSION') {
                $headerSkipped = $true
                continue
            }

            if ($line -match '^\s*(\*)?\s*(\S+)\s+(Running|Stopped)\s+(\d)') {
                $distros += [PSCustomObject]@{
                    Name      = $Matches[2]
                    IsDefault = [bool]$Matches[1]
                    State     = $Matches[3]
                    Version   = [int]$Matches[4]
                }
            }
        }

        return $distros
    }
    catch {
        return @()
    }
}

function Get-DistroPackageManager {
    param([string]$DistroName)

    # Detect package manager by checking for commands
    $checks = @(
        @{ Cmd = 'command -v apt-get'; PM = 'apt' }
        @{ Cmd = 'command -v dnf'; PM = 'dnf' }
        @{ Cmd = 'command -v yum'; PM = 'yum' }
        @{ Cmd = 'command -v pacman'; PM = 'pacman' }
        @{ Cmd = 'command -v apk'; PM = 'apk' }
        @{ Cmd = 'command -v zypper'; PM = 'zypper' }
    )

    foreach ($check in $checks) {
        $result = wsl.exe -d $DistroName -- bash -c $check.Cmd 2>&1
        if ($LASTEXITCODE -eq 0 -and $result) {
            return $check.PM
        }
    }

    return 'unknown'
}

# =============================================================================
# Package Management Commands
# =============================================================================

function Get-UpdateCommand {
    param([string]$PackageManager)

    $commands = @{
        apt     = 'sudo apt-get update'
        dnf     = 'sudo dnf check-update || true'  # dnf returns 100 if updates available
        yum     = 'sudo yum check-update || true'
        pacman  = 'sudo pacman -Sy'
        apk     = 'sudo apk update'
        zypper  = 'sudo zypper refresh'
    }

    return $commands[$PackageManager]
}

function Get-UpgradeCommand {
    param([string]$PackageManager)

    $commands = @{
        apt     = 'sudo apt-get upgrade -y && sudo apt-get dist-upgrade -y'
        dnf     = 'sudo dnf upgrade -y'
        yum     = 'sudo yum upgrade -y'
        pacman  = 'sudo pacman -Syu --noconfirm'
        apk     = 'sudo apk upgrade'
        zypper  = 'sudo zypper update -y'
    }

    return $commands[$PackageManager]
}

function Get-CleanCommand {
    param([string]$PackageManager)

    $commands = @{
        apt     = 'sudo apt-get autoremove -y && sudo apt-get autoclean && sudo apt-get clean'
        dnf     = 'sudo dnf autoremove -y && sudo dnf clean all'
        yum     = 'sudo yum autoremove -y && sudo yum clean all'
        pacman  = 'sudo pacman -Sc --noconfirm && sudo pacman -Rns $(pacman -Qtdq) 2>/dev/null || true'
        apk     = 'sudo apk cache clean'
        zypper  = 'sudo zypper clean -a'
    }

    return $commands[$PackageManager]
}

# =============================================================================
# Core Functions
# =============================================================================

function Update-DistroPackages {
    param([string]$DistroName)

    $pm = Get-DistroPackageManager $DistroName

    if ($pm -eq 'unknown') {
        Write-Status "Unknown package manager in $DistroName" -Type warning
        return $false
    }

    Write-Status "Updating package lists ($pm)..." -Type pending

    $cmd = Get-UpdateCommand $pm
    $result = wsl.exe -d $DistroName -- bash -c $cmd 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Status "Package lists updated" -Type success
        return $true
    }
    else {
        Write-Status "Update failed" -Type error
        Write-Host "    $result" -ForegroundColor $Script:Colors.Muted
        return $false
    }
}

function Upgrade-DistroPackages {
    param([string]$DistroName)

    $pm = Get-DistroPackageManager $DistroName

    if ($pm -eq 'unknown') {
        Write-Status "Unknown package manager in $DistroName" -Type warning
        return $false
    }

    Write-Status "Upgrading packages ($pm)..." -Type pending
    Write-Host "    This may take a while..." -ForegroundColor $Script:Colors.Muted

    $cmd = Get-UpgradeCommand $pm
    $result = wsl.exe -d $DistroName -- bash -c $cmd 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Status "Packages upgraded" -Type success
        return $true
    }
    else {
        Write-Status "Upgrade completed with warnings" -Type warning
        return $true
    }
}

function Clear-DistroCache {
    param([string]$DistroName)

    $pm = Get-DistroPackageManager $DistroName

    if ($pm -eq 'unknown') {
        Write-Status "Unknown package manager in $DistroName" -Type warning
        return $false
    }

    Write-Status "Cleaning package cache..." -Type pending

    $cmd = Get-CleanCommand $pm
    wsl.exe -d $DistroName -- bash -c $cmd 2>&1 | Out-Null

    Write-Status "Cache cleaned" -Type success

    # Also clean common temp locations
    Write-Status "Cleaning temp files..." -Type pending
    $tempCmd = 'sudo rm -rf /tmp/* /var/tmp/* 2>/dev/null || true'
    wsl.exe -d $DistroName -- bash -c $tempCmd 2>&1 | Out-Null

    Write-Status "Temp files cleaned" -Type success

    return $true
}

function Restart-Distro {
    param([string]$DistroName)

    Write-Status "Restarting $DistroName..." -Type pending

    # Terminate the distro
    wsl.exe --terminate $DistroName 2>&1 | Out-Null
    Start-Sleep -Seconds 2

    # Start it again with a simple command
    wsl.exe -d $DistroName -- echo "Restarted" 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Status "$DistroName restarted" -Type success
        return $true
    }
    else {
        Write-Status "Failed to restart $DistroName" -Type error
        return $false
    }
}

function Update-WSLKernel {
    Write-Status "Checking for WSL updates..." -Type pending

    $result = wsl.exe --update 2>&1 | Out-String

    if ($result -match 'No updates') {
        Write-Status "WSL is up to date" -Type success
    }
    elseif ($result -match 'Downloading|Installing') {
        Write-Status "WSL updated" -Type success
    }
    else {
        Write-Status "WSL update check complete" -Type info
    }

    # Show version
    $version = wsl.exe --version 2>&1 | Out-String
    if ($version -match 'WSL.Version:\s*(\S+)' -or $version -match 'WSL version:\s*(\S+)') {
        Write-Status "WSL Version: $($Matches[1])" -Type info
    }

    return $true
}

# =============================================================================
# Status Display
# =============================================================================

function Show-DistroStatus {
    Write-Host ""
    Write-Host "  WSL Distributions:" -ForegroundColor $Script:Colors.Highlight
    Write-Host ""

    $distros = Get-InstalledDistros

    if ($distros.Count -eq 0) {
        Write-Status "No WSL distributions found" -Type warning
        return
    }

    foreach ($d in $distros) {
        $marker = if ($d.IsDefault) { '*' } else { ' ' }
        $stateColor = switch ($d.State) {
            'Running' { 'Green' }
            'Stopped' { 'DarkGray' }
            default { 'Yellow' }
        }

        Write-Host "  $marker " -NoNewline
        Write-Host "$($d.Name)" -ForegroundColor White -NoNewline
        Write-Host " (WSL $($d.Version), $($d.State))" -ForegroundColor $stateColor

        # Get package manager
        if ($d.State -eq 'Running') {
            $pm = Get-DistroPackageManager $d.Name
            Write-Host "      Package Manager: $pm" -ForegroundColor $Script:Colors.Muted
        }
    }

    Write-Host ""
    Write-Host "  * = default distribution" -ForegroundColor $Script:Colors.Muted

    # WSL version
    Write-Host ""
    $version = wsl.exe --version 2>&1 | Out-String
    if ($version -match 'WSL.Version:\s*(\S+)' -or $version -match 'WSL version:\s*(\S+)') {
        Write-Status "WSL Version: $($Matches[1])" -Type info
    }
}

# =============================================================================
# Main
# =============================================================================

Write-Banner "WSL Distribution Maintenance"

# Check WSL availability
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-Status "WSL is not installed" -Type error
    exit 1
}

# Status mode
if ($ShowStatus) {
    Show-DistroStatus
    exit 0
}

# Shutdown mode
if ($Shutdown) {
    Write-Host ""
    Write-Status "Shutting down all WSL distributions..." -Type pending
    wsl.exe --shutdown 2>&1 | Out-Null
    Write-Status "All distributions stopped" -Type success
    exit 0
}

# Update WSL mode
if ($UpdateWSL) {
    Write-Host ""
    Update-WSLKernel
    exit 0
}

# Get target distros
$distros = Get-InstalledDistros

if ($Distro) {
    $targetDistros = $distros | Where-Object { $_.Name -eq $Distro }
    if (-not $targetDistros) {
        Write-Status "Distribution '$Distro' not found" -Type error
        exit 1
    }
}
else {
    $targetDistros = $distros
}

if ($targetDistros.Count -eq 0) {
    Write-Status "No WSL distributions found" -Type warning
    exit 0
}

$changes = @()

# Process each distro
foreach ($d in $targetDistros) {
    Write-Host ""
    Write-Host "  ─── $($d.Name) ───" -ForegroundColor $Script:Colors.Highlight
    Write-Host ""

    # Restart mode
    if ($Restart) {
        if (Restart-Distro $d.Name) {
            $changes += "Restarted $($d.Name)"
        }
        continue
    }

    # Update
    if ($Update -or $Upgrade) {
        if (Update-DistroPackages $d.Name) {
            $changes += "Updated $($d.Name)"
        }
    }

    # Upgrade
    if ($Upgrade) {
        if (Upgrade-DistroPackages $d.Name) {
            $changes += "Upgraded $($d.Name)"
        }
    }

    # Clean
    if ($Clean) {
        if (Clear-DistroCache $d.Name) {
            $changes += "Cleaned $($d.Name)"
        }
    }
}

# Summary
if ($changes.Count -gt 0) {
    Write-Host ""
    Write-Status "Maintenance complete ($($changes.Count) operations)" -Type success
}
elseif (-not $Restart) {
    Write-Host ""
    Write-Status "No operations specified" -Type info
    Write-Host ""
    Write-Host "  Options:" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -Update       Update package lists" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -Upgrade      Upgrade all packages" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -Clean        Clean package cache" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -Restart      Restart distribution" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -Shutdown     Shutdown all distributions" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -UpdateWSL    Update WSL itself" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -ShowStatus   Show distribution status" -ForegroundColor $Script:Colors.Muted
}

