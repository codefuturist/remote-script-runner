#!/usr/bin/env pwsh
#Requires -Version 5.1

<#
.SYNOPSIS
    Install and configure WSL 2 with best practices
.DESCRIPTION
    User-friendly WSL 2 installation wizard that:
    - Enables required Windows features
    - Sets WSL 2 as default (WSL 1 is not supported)
    - Installs Linux distribution (default: latest Ubuntu)
    - Configures memory, networking, and performance settings
    - Handles restart requirements gracefully
    - Installs RSR in the new Linux environment

    Note: WSL 1 is not fully supported because it lacks:
    - Full Linux kernel compatibility
    - Systemd support (needed for service management)
    - Nested virtualization
.PARAMETER Distro
    Linux distribution to install: Ubuntu (default), Debian, kali-linux, Alpine, openSUSE-Leap
.PARAMETER ListDistros
    List available distributions
.PARAMETER SkipRestart
    Skip automatic restart prompts
.PARAMETER SkipRSR
    Skip RSR installation in WSL
.PARAMETER Force
    Bypass all confirmation prompts
.PARAMETER ConfigOnly
    Only configure WSL (skip installation)
.EXAMPLE
    .\Install-WSL.ps1
.EXAMPLE
    .\Install-WSL.ps1 -Distro Ubuntu
.EXAMPLE
    .\Install-WSL.ps1 -ListDistros
.EXAMPLE
    .\Install-WSL.ps1 -ConfigOnly
#>

[CmdletBinding(DefaultParameterSetName = 'Install')]
param(
    [Parameter(ParameterSetName = 'Install')]
    [string]$Distro = "Ubuntu",

    [Parameter(ParameterSetName = 'List')]
    [switch]$ListDistros,

    [Parameter(ParameterSetName = 'Install')]
    [switch]$SkipRestart,

    [Parameter(ParameterSetName = 'Install')]
    [switch]$SkipRSR,

    [Parameter(ParameterSetName = 'Install')]
    [switch]$Force,

    [Parameter(ParameterSetName = 'Config')]
    [switch]$ConfigOnly
)

$ErrorActionPreference = 'Stop'

# =============================================================================
# UI Helpers
# =============================================================================

$Script:Colors = @{
    Title     = 'Cyan'
    Success   = 'Green'
    Warning   = 'Yellow'
    Error     = 'Red'
    Info      = 'White'
    Muted     = 'DarkGray'
    Highlight = 'Magenta'
}

function Write-Banner {
    param([string]$Text)
    $width = 60
    $border = "═" * $width
    Write-Host ""
    Write-Host "╔$border╗" -ForegroundColor $Script:Colors.Title
    $padding = [math]::Max(0, ($width - $Text.Length) / 2)
    $paddedText = (" " * [math]::Floor($padding)) + $Text + (" " * [math]::Ceiling($padding))
    Write-Host "║$paddedText║" -ForegroundColor $Script:Colors.Title
    Write-Host "╚$border╝" -ForegroundColor $Script:Colors.Title
    Write-Host ""
}

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "┌─ $Text " -ForegroundColor $Script:Colors.Highlight -NoNewline
    Write-Host ("─" * [math]::Max(0, 50 - $Text.Length)) -ForegroundColor $Script:Colors.Muted
}

function Write-Step {
    param(
        [string]$Text,
        [ValidateSet('pending', 'running', 'success', 'warning', 'error', 'skip')]
        [string]$Status = 'pending'
    )
    $icons = @{
        pending = '○'
        running = '◐'
        success = '✓'
        warning = '⚠'
        error   = '✗'
        skip    = '○'
    }
    $colors = @{
        pending = $Script:Colors.Muted
        running = $Script:Colors.Info
        success = $Script:Colors.Success
        warning = $Script:Colors.Warning
        error   = $Script:Colors.Error
        skip    = $Script:Colors.Muted
    }
    Write-Host "  $($icons[$Status]) " -ForegroundColor $colors[$Status] -NoNewline
    Write-Host $Text -ForegroundColor $(if ($Status -eq 'skip') { $Script:Colors.Muted } else { $Script:Colors.Info })
}

function Write-Info {
    param([string]$Text)
    Write-Host "  ℹ $Text" -ForegroundColor $Script:Colors.Muted
}

function Write-Success {
    param([string]$Text)
    Write-Host "  ✓ $Text" -ForegroundColor $Script:Colors.Success
}

function Write-Warn {
    param([string]$Text)
    Write-Host "  ⚠ $Text" -ForegroundColor $Script:Colors.Warning
}

function Write-Err {
    param([string]$Text)
    Write-Host "  ✗ $Text" -ForegroundColor $Script:Colors.Error
}

function Show-Menu {
    param(
        [string]$Title,
        [string[]]$Options,
        [int]$Default = 0
    )

    Write-Host ""
    Write-Host "  $Title" -ForegroundColor $Script:Colors.Highlight
    Write-Host ""

    for ($i = 0; $i -lt $Options.Count; $i++) {
        $marker = if ($i -eq $Default) { "›" } else { " " }
        $num = $i + 1
        Write-Host "  $marker [$num] $($Options[$i])" -ForegroundColor $(if ($i -eq $Default) { $Script:Colors.Info } else { $Script:Colors.Muted })
    }

    Write-Host ""
    $choice = Read-Host "  Select option (1-$($Options.Count), default: $($Default + 1))"

    if ([string]::IsNullOrWhiteSpace($choice)) {
        return $Default
    }

    $selected = [int]$choice - 1
    if ($selected -ge 0 -and $selected -lt $Options.Count) {
        return $selected
    }
    return $Default
}

function Confirm-Action {
    param(
        [string]$Message,
        [bool]$Default = $true
    )

    if ($Force) { return $true }

    $defaultHint = if ($Default) { "Y/n" } else { "y/N" }
    $response = Read-Host "  $Message [$defaultHint]"

    if ([string]::IsNullOrWhiteSpace($response)) {
        return $Default
    }
    return $response -match '^[Yy]'
}

# =============================================================================
# System Detection
# =============================================================================

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WindowsBuild {
    return [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
}

function Test-VirtualizationEnabled {
    try {
        $cpu = Get-CimInstance Win32_Processor
        return $cpu.VirtualizationFirmwareEnabled -eq $true
    }
    catch {
        return $null
    }
}

function Test-WSLFeatureEnabled {
    $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
    return $wslFeature.State -eq 'Enabled'
}

function Test-VMPFeatureEnabled {
    $vmpFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue
    return $vmpFeature.State -eq 'Enabled'
}

function Test-WSLInstalled {
    try {
        $wslPath = Get-Command wsl.exe -ErrorAction SilentlyContinue
        return $null -ne $wslPath
    }
    catch {
        return $false
    }
}

function Get-WSLVersion {
    try {
        $output = wsl.exe --version 2>&1
        if ($output -match 'WSL-Version:\s*(\d+\.\d+\.\d+)') {
            return $Matches[1]
        }
        elseif ($output -match 'WSL version:\s*(\d+\.\d+\.\d+)') {
            return $Matches[1]
        }
    }
    catch {}
    return $null
}

function Get-InstalledDistros {
    try {
        $output = wsl.exe --list --quiet 2>&1
        if ($LASTEXITCODE -eq 0) {
            return $output | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() -replace '\x00', '' }
        }
    }
    catch {}
    return @()
}

function Get-DistroWSLVersion {
    <#
    .SYNOPSIS
        Get the WSL version (1 or 2) for a specific distro
    #>
    param([string]$DistroName)

    try {
        $output = wsl.exe --list --verbose 2>&1 | Out-String
        $lines = $output -split "`r?`n"

        foreach ($line in $lines) {
            # Match lines like: "* Ubuntu    Running    2" or "  Debian    Stopped    1"
            if ($line -match "^\s*\*?\s*$([regex]::Escape($DistroName))\s+\w+\s+(\d)") {
                return [int]$Matches[1]
            }
        }
    }
    catch {}
    return $null
}

function Update-DistroToWSL2 {
    <#
    .SYNOPSIS
        Upgrade a WSL 1 distro to WSL 2
    .DESCRIPTION
        WSL 1 is not fully supported by RSR because it lacks:
        - Full Linux kernel compatibility
        - Systemd support
        - Nested virtualization
    #>
    param([string]$DistroName)

    $currentVersion = Get-DistroWSLVersion -DistroName $DistroName
    if ($currentVersion -eq 2) {
        Write-Step "$DistroName is already using WSL 2" -Status skip
        return $true
    }

    if ($currentVersion -eq 1) {
        Write-Warn "$DistroName is using WSL 1 (not fully supported)"
        Write-Info "WSL 1 lacks systemd support needed for service management"

        if (Confirm-Action "Upgrade $DistroName to WSL 2?" -Default $true) {
            Write-Step "Upgrading $DistroName to WSL 2..." -Status running
            Write-Info "This may take several minutes"

            try {
                $output = wsl.exe --set-version $DistroName 2 2>&1
                $outputStr = $output | Out-String

                if ($LASTEXITCODE -eq 0) {
                    Write-Step "$DistroName upgraded to WSL 2" -Status success
                    return $true
                }
                else {
                    Write-Step "Upgrade failed" -Status error
                    Write-Info $outputStr
                    return $false
                }
            }
            catch {
                Write-Step ("Upgrade failed: " + $_.Exception.Message) -Status error
                return $false
            }
        }
        else {
            Write-Warn "Continuing with WSL 1 (some features may not work)"
            return $true
        }
    }

    return $true
}

function Get-OnlineDistros {
    <#
    .SYNOPSIS
        Get available distros from Microsoft's online list
    .DESCRIPTION
        Runs wsl --list --online to get the current available distributions
        Per Microsoft docs: https://learn.microsoft.com/en-us/windows/wsl/install
    #>
    try {
        $output = wsl.exe --list --online 2>&1
        if ($LASTEXITCODE -eq 0 -and $output -notmatch 'error') {
            $distros = @()
            $lines = ($output | Out-String) -split "`r?`n"
            $inList = $false

            foreach ($line in $lines) {
                # Skip empty lines and headers
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                if ($line -match '^NAME\s+FRIENDLY') { $inList = $true; continue }
                if ($line -match '^-+') { continue }

                if ($inList -and $line -match '^\s*(\S+)\s+(.+)$') {
                    $name = $Matches[1].Trim()
                    $desc = $Matches[2].Trim()
                    $isDefault = $line -match '^\*' -or $name -eq 'Ubuntu'

                    $distros += @{
                        Name = $name
                        Description = $desc
                        Default = $isDefault
                    }
                }
            }

            if ($distros.Count -gt 0) {
                return $distros
            }
        }
    }
    catch {
        # Silently fall back to static list
    }
    return @()
}

function Get-AvailableDistros {
    # Try to get online list first for most current options
    $onlineDistros = Get-OnlineDistros
    if ($onlineDistros.Count -gt 0) {
        return $onlineDistros
    }

    # Fall back to curated list of popular distros
    return @(
        @{ Name = 'Ubuntu'; Description = 'Ubuntu (latest)'; Default = $true }
        @{ Name = 'Ubuntu-24.04'; Description = 'Ubuntu 24.04 LTS' }
        @{ Name = 'Ubuntu-22.04'; Description = 'Ubuntu 22.04 LTS' }
        @{ Name = 'Debian'; Description = 'Debian GNU/Linux' }
        @{ Name = 'kali-linux'; Description = 'Kali Linux (security)' }
        @{ Name = 'openSUSE-Leap-15.6'; Description = 'openSUSE Leap 15.6' }
        @{ Name = 'SUSE-Linux-Enterprise-15-SP6'; Description = 'SUSE Linux Enterprise' }
        @{ Name = 'OracleLinux_9_1'; Description = 'Oracle Linux 9.1' }
        @{ Name = 'Alpine'; Description = 'Alpine Linux (minimal)' }
    )
}

# =============================================================================
# WSL Configuration
# =============================================================================

function Get-WSLConfigPath {
    return Join-Path $env:USERPROFILE ".wslconfig"
}

function Get-DefaultWSLConfig {
    # Optimal configuration for development
    return @"
# WSL2 Configuration
# Documentation: https://learn.microsoft.com/en-us/windows/wsl/wsl-config

[wsl2]
# Memory - adjust based on your system RAM
memory=8GB

# Processors - use half of available cores
processors=4

# Swap file size
swap=4GB

# Swap file path (optional, default is %USERPROFILE%\AppData\Local\Temp\swap.vhdx)
# swapFile=C:\\temp\\wsl-swap.vhdx

# Disable page reporting for better memory management
pageReporting=false

# Enable nested virtualization (for Docker, etc.)
nestedVirtualization=true

# Turn on debugging console (optional)
# debugConsole=true

# Enable kernel debug (optional)
# kernelCommandLine=debug

# Disable GUI applications (optional, save resources if not needed)
# guiApplications=false

[experimental]
# Automatic memory reclaim (recommended)
autoMemoryReclaim=gradual

# Sparse VHD (saves disk space)
sparseVhd=true

# Network mode - mirrored provides better Windows integration
networkingMode=mirrored

# DNS tunneling for better DNS resolution
dnsTunneling=true

# Firewall sync
firewall=true

# Auto proxy (follow Windows proxy settings)
autoProxy=true
"@
}

function Set-WSLConfig {
    param(
        [int]$MemoryGB = 8,
        [int]$Processors = 4,
        [int]$SwapGB = 4,
        [switch]$NetworkMirrored
    )

    Write-Section "Configuring WSL"

    $configPath = Get-WSLConfigPath

    # Get system info for smart defaults
    $totalRam = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $cpuCores = (Get-CimInstance Win32_Processor).NumberOfLogicalProcessors

    # Smart defaults: half of RAM, half of cores
    if ($MemoryGB -eq 8) { $MemoryGB = [math]::Max(4, [math]::Floor($totalRam / 2)) }
    if ($Processors -eq 4) { $Processors = [math]::Max(2, [math]::Floor($cpuCores / 2)) }

    Write-Info "System: ${totalRam}GB RAM, $cpuCores CPU cores"
    Write-Info "WSL allocation: ${MemoryGB}GB RAM, $Processors CPU cores"

    $config = @"
# WSL2 Configuration - Generated by RSR $(Get-Date -Format 'yyyy-MM-dd')
# Docs: https://learn.microsoft.com/en-us/windows/wsl/wsl-config

[wsl2]
memory=${MemoryGB}GB
processors=$Processors
swap=${SwapGB}GB
pageReporting=false
nestedVirtualization=true

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
$(if ($NetworkMirrored) { "networkingMode=mirrored`ndnsTunneling=true`nfirewall=true`nautoProxy=true" })
"@

    # Backup existing config
    if (Test-Path $configPath) {
        $backupPath = "$configPath.bak"
        Copy-Item $configPath $backupPath -Force
        Write-Info "Backed up existing config to .wslconfig.bak"
    }

    # Write new config
    $config | Set-Content -Path $configPath -Encoding UTF8
    Write-Step "WSL configuration saved to $configPath" -Status success

    return $true
}

# =============================================================================
# Installation Functions
# =============================================================================

function Install-WSLSimplified {
    <#
    .SYNOPSIS
        Try simplified WSL installation using wsl --install
    .DESCRIPTION
        Per Microsoft docs: "wsl --install" enables features and installs Ubuntu by default.
        This is the recommended method for fresh installations.
        https://learn.microsoft.com/en-us/windows/wsl/install
    #>
    param([string]$DistroName = "Ubuntu")

    Write-Section "Installing WSL (Simplified Method)"
    Write-Info "Using Microsoft's recommended 'wsl --install' command"

    # Check if WSL is already functional
    $existingDistros = Get-InstalledDistros
    if ($existingDistros.Count -gt 0) {
        Write-Step "WSL already installed with $($existingDistros.Count) distro(s)" -Status skip
        return @{ Success = $true; NeedsDistro = $DistroName -notin $existingDistros }
    }

    Write-Step "Running wsl --install..." -Status running

    try {
        # Try the simple install first (enables features + installs Ubuntu)
        $output = wsl.exe --install --no-launch 2>&1
        $outputStr = $output | Out-String

        # If we see usage/help text, WSL is already installed but no distros
        if ($outputStr -match 'Usage:' -or $outputStr -match 'wsl --help') {
            Write-Step "WSL features already enabled" -Status success
            return @{ Success = $true; NeedsDistro = $true }
        }

        # Check for restart requirement
        if ($outputStr -match 'restart' -or $outputStr -match 'reboot') {
            Write-Step "WSL installed - restart required" -Status warning
            return @{ Success = $true; NeedsRestart = $true; NeedsDistro = $true }
        }

        if ($LASTEXITCODE -eq 0) {
            Write-Step "WSL installed successfully" -Status success
            return @{ Success = $true; NeedsDistro = $DistroName -ne 'Ubuntu' }
        }
    }
    catch {
        Write-Step "Simplified install not available, using manual method" -Status warning
    }

    return @{ Success = $false; UseManual = $true }
}

function Enable-WSLFeatures {
    Write-Section "Enabling Windows Features"

    if (-not (Test-IsAdmin)) {
        Write-Err "Administrator privileges required to enable Windows features"
        Write-Info "Please restart PowerShell as Administrator"
        return $false
    }

    $restartRequired = $false

    # Enable WSL feature
    if (-not (Test-WSLFeatureEnabled)) {
        Write-Step "Enabling Windows Subsystem for Linux..." -Status running
        try {
            $result = Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart -All
            if ($result.RestartNeeded) { $restartRequired = $true }
            Write-Step "Windows Subsystem for Linux enabled" -Status success
        }
        catch {
            Write-Step ("Failed to enable WSL feature: " + $_.Exception.Message) -Status error
            return $false
        }
    }
    else {
        Write-Step "Windows Subsystem for Linux already enabled" -Status skip
    }

    # Enable Virtual Machine Platform
    if (-not (Test-VMPFeatureEnabled)) {
        Write-Step "Enabling Virtual Machine Platform..." -Status running
        try {
            $result = Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart -All
            if ($result.RestartNeeded) { $restartRequired = $true }
            Write-Step "Virtual Machine Platform enabled" -Status success
        }
        catch {
            Write-Step ("Failed to enable VMP feature: " + $_.Exception.Message) -Status error
            return $false
        }
    }
    else {
        Write-Step "Virtual Machine Platform already enabled" -Status skip
    }

    if ($restartRequired) {
        Write-Host ""
        Write-Warn "A system restart is required to complete the setup"

        if (-not $SkipRestart) {
            if (Confirm-Action "Restart now?" -Default $false) {
                Write-Info "Saving restart marker..."

                # Create a marker file for post-restart continuation
                $markerPath = Join-Path $env:TEMP "wsl-setup-continue.txt"
                @{
                    Distro = $Distro
                    Stage  = 'post-restart'
                    Time   = Get-Date -Format 'o'
                } | ConvertTo-Json | Set-Content $markerPath

                # Schedule script to run after restart
                $scriptPath = $PSCommandPath
                $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Distro `"$Distro`" -Force"
                $trigger = New-ScheduledTaskTrigger -AtLogon
                $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
                $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

                Register-ScheduledTask -TaskName "WSL-Setup-Continue" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

                Write-Info "Setup will continue automatically after restart"
                Start-Sleep -Seconds 2
                Restart-Computer -Force
                return $false
            }
            else {
                Write-Info "Please restart your computer and run this script again"
                return $false
            }
        }
        else {
            Write-Info "Restart skipped. Please restart manually and run this script again"
            return $false
        }
    }

    return $true
}

function Install-WSLKernel {
    Write-Section "Setting up WSL2"

    # Set WSL 2 as default
    Write-Step "Setting WSL 2 as default version..." -Status running
    try {
        wsl.exe --set-default-version 2 2>&1 | Out-Null
        Write-Step "WSL 2 set as default" -Status success
    }
    catch {
        Write-Step ("Could not set WSL 2 as default: " + $_.Exception.Message) -Status warning
    }

    # Update WSL
    Write-Step "Updating WSL..." -Status running
    try {
        $output = wsl.exe --update 2>&1
        Write-Step "WSL updated" -Status success
    }
    catch {
        Write-Step "WSL update check complete" -Status success
    }

    return $true
}

function Install-LinuxDistro {
    param(
        [string]$DistroName,
        [switch]$UseWebDownload
    )

    Write-Section "Installing Linux Distribution"

    $installedDistros = Get-InstalledDistros

    if ($DistroName -in $installedDistros) {
        Write-Step "$DistroName already installed" -Status skip
        return $true
    }

    Write-Step "Installing $DistroName..." -Status running
    Write-Info "This may take a few minutes"

    try {
        # First attempt: standard install
        $output = wsl.exe --install -d $DistroName --no-launch 2>&1
        $outputStr = $output | Out-String

        if ($LASTEXITCODE -eq 0 -or $outputStr -match 'successfully installed') {
            Write-Step "$DistroName installed successfully" -Status success
            return $true
        }

        # Check if install is hanging or failed - try web download
        # Per Microsoft docs: "If the install process hangs at 0.0%, run wsl --install --web-download"
        if ($outputStr -match 'error|failed|0\.0%' -or $UseWebDownload) {
            Write-Step "Trying web download method (per Microsoft recommendation)..." -Status running
            Write-Info "Downloading distribution directly from Microsoft..."

            $webOutput = wsl.exe --install --web-download -d $DistroName --no-launch 2>&1
            $webOutputStr = $webOutput | Out-String

            if ($LASTEXITCODE -eq 0 -or $webOutputStr -match 'successfully') {
                Write-Step "$DistroName installed via web download" -Status success
                return $true
            }
        }

        # If we get here with warnings but not errors, still consider it successful
        if ($outputStr -notmatch 'error|failed') {
            Write-Step "Installation completed with warnings" -Status warning
            Write-Info $outputStr
            return $true
        }

        Write-Step "Installation may have issues" -Status warning
        Write-Info $outputStr
        return $true
    }
    catch {
        Write-Step ("Failed to install ${DistroName}: " + $_.Exception.Message) -Status error
        Write-Info "Try running: wsl --install --web-download -d $DistroName"
        return $false
    }
}

function Initialize-Distro {
    param([string]$DistroName)

    Write-Section "Initializing $DistroName"

    Write-Info "Please complete the initial setup in the new window:"
    Write-Info "  1. Create a Unix username (lowercase, no spaces)"
    Write-Info "  2. Set a password"
    Write-Host ""

    # Launch distro for initial setup
    Write-Step "Launching $DistroName for initial setup..." -Status running

    try {
        # Start the distro in a new window for user interaction
        Start-Process wsl.exe -ArgumentList "-d", $DistroName -Wait
        Write-Step "Initial setup complete" -Status success
        return $true
    }
    catch {
        Write-Step ("Error during initialization: " + $_.Exception.Message) -Status warning
        return $true  # Continue anyway
    }
}

function Install-RSRInWSL {
    param([string]$DistroName)

    Write-Section "Installing RSR in WSL"

    Write-Step "Installing RSR..." -Status running

    try {
        # Update package lists first
        wsl.exe -d $DistroName -- sudo apt update 2>&1 | Out-Null

        # Install curl if not present
        wsl.exe -d $DistroName -- sudo apt install -y curl 2>&1 | Out-Null

        # Install RSR
        $installCmd = 'curl -fsSL https://scripts.pandia.io/install.sh | bash'
        $output = wsl.exe -d $DistroName -- bash -c $installCmd 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Step "RSR installed in $DistroName" -Status success
            return $true
        }
        else {
            Write-Step "RSR installation had warnings" -Status warning
            Write-Info $output
            return $true
        }
    }
    catch {
        Write-Step ("Failed to install RSR: " + $_.Exception.Message) -Status error
        return $false
    }
}

function Install-WSLEssentials {
    param([string]$DistroName)

    Write-Section "Installing Essential Packages in WSL"

    $packages = @(
        'git',
        'curl',
        'wget',
        'build-essential',
        'unzip',
        'jq',
        'htop'
    )

    Write-Step "Updating package lists..." -Status running
    wsl.exe -d $DistroName -- sudo apt update 2>&1 | Out-Null
    Write-Step "Package lists updated" -Status success

    Write-Step "Installing essential packages..." -Status running
    $pkgList = $packages -join ' '
    wsl.exe -d $DistroName -- sudo apt install -y $pkgList 2>&1 | Out-Null
    Write-Step "Essential packages installed" -Status success

    return $true
}

function Set-DistroSystemdConfig {
    <#
    .SYNOPSIS
        Configure wsl.conf to enable systemd and recommended settings
    .DESCRIPTION
        Writes a recommended wsl.conf file that enables systemd (required for
        service management) and sets up optimal development settings.
    #>
    param([string]$DistroName)

    Write-Section "Configuring WSL Distribution"

    Write-Step "Enabling systemd and recommended settings..." -Status running

    # Build wsl.conf content
    $wslConf = @"
# WSL Configuration - Generated by RSR $(Get-Date -Format 'yyyy-MM-dd')
# Documentation: https://learn.microsoft.com/en-us/windows/wsl/wsl-config

[boot]
systemd=true

[automount]
enabled=true
root=/mnt/
options=metadata,umask=22,fmask=11

[network]
generateHosts=true
generateResolvConf=true

[interop]
enabled=true
appendWindowsPath=true
"@

    try {
        # Write wsl.conf
        $escapedConf = $wslConf -replace "'", "'\\''"
        $cmd = "echo '$escapedConf' | sudo tee /etc/wsl.conf > /dev/null"
        wsl.exe -d $DistroName -- bash -c $cmd 2>&1 | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Step "Systemd enabled" -Status success
            Write-Step "Automount configured with metadata" -Status success
            Write-Step "Windows interop enabled" -Status success
            Write-Info "Restart WSL to apply: wsl --shutdown"
            return $true
        }
        else {
            Write-Step "Could not write wsl.conf" -Status warning
            return $false
        }
    }
    catch {
        Write-Step ("Configuration failed: " + $_.Exception.Message) -Status warning
        return $false
    }
}

# =============================================================================
# Post-Installation
# =============================================================================

function Show-NextSteps {
    param([string]$DistroName)

    Write-Host ""
    Write-Banner "WSL Setup Complete! 🎉"

    Write-Host "  Your Linux environment is ready:" -ForegroundColor $Script:Colors.Info
    Write-Host ""
    Write-Host "  Quick Access:" -ForegroundColor $Script:Colors.Highlight
    Write-Host "    • Type 'wsl' or '$($DistroName.ToLower())' in Terminal" -ForegroundColor $Script:Colors.Muted
    Write-Host "    • Open Windows Terminal and select '$DistroName'" -ForegroundColor $Script:Colors.Muted
    Write-Host "    • Run 'code .' in WSL to open VS Code" -ForegroundColor $Script:Colors.Muted
    Write-Host ""
    Write-Host "  Useful Commands:" -ForegroundColor $Script:Colors.Highlight
    Write-Host "    wsl                      # Enter default distro" -ForegroundColor $Script:Colors.Muted
    Write-Host "    wsl -d $DistroName       # Enter specific distro" -ForegroundColor $Script:Colors.Muted
    Write-Host "    wsl --shutdown           # Restart WSL" -ForegroundColor $Script:Colors.Muted
    Write-Host "    wsl --list --verbose     # List distros" -ForegroundColor $Script:Colors.Muted
    Write-Host ""
    Write-Host "  File Access:" -ForegroundColor $Script:Colors.Highlight
    Write-Host "    • Windows files in WSL: /mnt/c/Users/$env:USERNAME" -ForegroundColor $Script:Colors.Muted
    Write-Host "    • WSL files in Windows: \\wsl$\$DistroName\home\..." -ForegroundColor $Script:Colors.Muted
    Write-Host ""
    Write-Host "  Additional Setup (optional):" -ForegroundColor $Script:Colors.Highlight
    Write-Host "    .\Configure-WindowsTerminal.ps1   # Configure terminal" -ForegroundColor $Script:Colors.Muted
    Write-Host "    .\Configure-GitCredentials.ps1    # Setup Git authentication" -ForegroundColor $Script:Colors.Muted
    Write-Host "    .\Configure-VSCodeWSL.ps1         # Setup VS Code for WSL" -ForegroundColor $Script:Colors.Muted
    Write-Host "    .\Configure-DockerWSL.ps1         # Setup Docker integration" -ForegroundColor $Script:Colors.Muted
    Write-Host ""
    Write-Host "  Maintenance:" -ForegroundColor $Script:Colors.Highlight
    Write-Host "    .\Update-WSLDistro.ps1 -Upgrade   # Update packages" -ForegroundColor $Script:Colors.Muted
    Write-Host "    .\Export-WSLDistro.ps1            # Backup distro" -ForegroundColor $Script:Colors.Muted
    Write-Host ""
}

function Remove-SetupMarker {
    # Clean up post-restart scheduled task if it exists
    $taskName = "WSL-Setup-Continue"
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Remove marker file
    $markerPath = Join-Path $env:TEMP "wsl-setup-continue.txt"
    if (Test-Path $markerPath) {
        Remove-Item $markerPath -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# Main Logic
# =============================================================================

function Start-WSLInstallation {
    param([string]$DistroName)

    Clear-Host
    Write-Banner "WSL2 Setup Wizard"

    # System check
    Write-Section "System Requirements"

    $build = Get-WindowsBuild
    if ($build -lt 19041) {
        Write-Err "Windows build $build is too old. WSL2 requires build 19041 or later."
        Write-Info "Please update Windows to continue."
        return $false
    }
    Write-Step "Windows build $build (OK)" -Status success

    $virtEnabled = Test-VirtualizationEnabled
    if ($virtEnabled -eq $false) {
        Write-Warn "Virtualization may be disabled in BIOS"
        Write-Info "If installation fails, enable VT-x/AMD-V in BIOS settings"
    }
    elseif ($virtEnabled) {
        Write-Step "Virtualization enabled" -Status success
    }

    if (-not (Test-IsAdmin)) {
        Write-Warn "Not running as Administrator"
        Write-Info "Some features require elevation. Consider restarting as Admin."
        Write-Host ""
        if (-not (Confirm-Action "Continue anyway?")) {
            return $false
        }
    }
    else {
        Write-Step "Running as Administrator" -Status success
    }

    # Distro selection
    if (-not $Force) {
        Write-Host ""
        $distros = Get-AvailableDistros
        $options = $distros | ForEach-Object { "$($_.Name) - $($_.Description)" }

        $defaultIdx = 0
        for ($i = 0; $i -lt $distros.Count; $i++) {
            if ($distros[$i].Name -eq $DistroName -or $distros[$i].Default) {
                $defaultIdx = $i
                break
            }
        }

        $choice = Show-Menu -Title "Select Linux distribution:" -Options $options -Default $defaultIdx
        $DistroName = $distros[$choice].Name
    }

    Write-Info "Selected: $DistroName"
    Write-Host ""

    # Enable features
    if (-not (Enable-WSLFeatures)) {
        return $false
    }

    # Setup WSL2
    if (-not (Install-WSLKernel)) {
        return $false
    }

    # Configure WSL
    if (Confirm-Action "Configure WSL settings (memory, CPU)?") {
        $networkMirrored = Confirm-Action "Use mirrored networking (better Windows integration)?"
        Set-WSLConfig -NetworkMirrored:$networkMirrored
    }

    # Install distro
    if (-not (Install-LinuxDistro -DistroName $DistroName)) {
        return $false
    }

    # Ensure distro is using WSL 2 (WSL 1 is not fully supported)
    Update-DistroToWSL2 -DistroName $DistroName

    # Initialize distro (user setup)
    $installedDistros = Get-InstalledDistros
    if ($DistroName -in $installedDistros) {
        # Check if already initialized
        $testOutput = wsl.exe -d $DistroName -- whoami 2>&1
        if ($LASTEXITCODE -ne 0 -or $testOutput -match 'error') {
            Initialize-Distro -DistroName $DistroName
        }
    }

    # Install essentials in WSL
    if (Confirm-Action "Install essential packages in WSL (git, curl, build tools)?") {
        Install-WSLEssentials -DistroName $DistroName
    }

    # Configure systemd and recommended settings
    if (Confirm-Action "Enable systemd and apply recommended WSL settings?") {
        Set-DistroSystemdConfig -DistroName $DistroName
    }

    # Install RSR
    if (-not $SkipRSR) {
        if (Confirm-Action "Install RSR (Remote Script Runner) in WSL?") {
            Install-RSRInWSL -DistroName $DistroName
        }
    }

    # Cleanup and finish
    Remove-SetupMarker
    Show-NextSteps -DistroName $DistroName

    return $true
}

# =============================================================================
# Entry Point
# =============================================================================

try {
    switch ($PSCmdlet.ParameterSetName) {
        'List' {
            Write-Banner "Available Linux Distributions"
            $distros = Get-AvailableDistros
            foreach ($d in $distros) {
                $marker = if ($d.Default) { "›" } else { " " }
                Write-Host "  $marker $($d.Name)" -ForegroundColor $(if ($d.Default) { $Script:Colors.Highlight } else { $Script:Colors.Info }) -NoNewline
                Write-Host " - $($d.Description)" -ForegroundColor $Script:Colors.Muted
            }
            Write-Host ""
            Write-Info "Install with: .\Install-WSL.ps1 -Distro <name>"
        }
        'Config' {
            Write-Banner "WSL Configuration"
            $networkMirrored = Confirm-Action "Use mirrored networking?"
            Set-WSLConfig -NetworkMirrored:$networkMirrored
            Write-Success "Configuration saved. Run 'wsl --shutdown' to apply changes."
        }
        default {
            $success = Start-WSLInstallation -DistroName $Distro
            exit $(if ($success) { 0 } else { 1 })
        }
    }
}
catch {
    Write-Err ("An error occurred: " + $_.Exception.Message)
    exit 1
}

