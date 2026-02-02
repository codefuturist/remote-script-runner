#!/usr/bin/env pwsh
#Requires -Version 5.1

<#
.SYNOPSIS
    Host Bootstrap - User-friendly wizard for bootstrapping Windows systems
    
.DESCRIPTION
    Interactive wizard to bootstrap a new Windows host with:
    - Essential system tools and utilities
    - Package managers (winget, Chocolatey, Scoop)
    - SSH configuration (OpenSSH client/server)
    - Security settings (Windows Firewall, Windows Defender)
    - Development tools (optional)
    - WSL2 (optional)
    - Docker Desktop (optional)
    
    IMPORTANT: Nothing is changed unless you explicitly request it via a profile
    or individual switches. Use -DryRun to preview changes before applying.
    
    Equivalent to the Unix host-bootstrap.sh script for Windows systems.

.PARAMETER Profile
    Bootstrap profile: minimal, server, workstation, dev
    Each profile enables specific features explicitly.
    
.PARAMETER Hostname
    Set computer hostname
    
.PARAMETER DryRun
    Show what would be done without making any changes
    
.PARAMETER Force
    Auto-confirm all prompts (equivalent to -y in Unix)
    
.PARAMETER Quick
    Quick mode with sensible defaults
    
.PARAMETER SkipPackages
    Skip package installation
    
.PARAMETER SkipSecurity
    Skip security configuration
    
.PARAMETER SkipSSH
    Skip SSH configuration
    
.PARAMETER Essentials
    Install essential packages (must be explicitly enabled)
    
.PARAMETER DevTools
    Install development tools
    
.PARAMETER Docker
    Install Docker Desktop
    
.PARAMETER WSL
    Install WSL2
    
.PARAMETER Firewall
    Configure Windows Firewall

.EXAMPLE
    .\Initialize-HostBootstrap.ps1
    # Interactive wizard
    
.EXAMPLE
    .\Initialize-HostBootstrap.ps1 -Profile server -DryRun
    # Preview what server profile would do (no changes made)
    
.EXAMPLE
    .\Initialize-HostBootstrap.ps1 -Profile dev -Force
    # Full dev setup without prompts
    
.EXAMPLE
    .\Initialize-HostBootstrap.ps1 -Essentials -Force
    # Only install essential packages
    
.EXAMPLE
    irm https://scripts.pandia.io/rsr | iex; rsr bootstrap
    # Remote execution

.NOTES
    Version: 1.0.0
    Author: codefuturist
    Platform: Windows (PowerShell 5.1+)
    
    SAFETY: This script will NOT make any changes unless you:
    1. Select a profile (-Profile server/dev/etc)
    2. Use individual feature switches (-Essentials, -Docker, etc)
    3. Run the interactive wizard and make selections
#>

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(ParameterSetName = 'Profile')]
    [ValidateSet('minimal', 'server', 'workstation', 'dev')]
    [string]$Profile,
    
    [Parameter()]
    [string]$Hostname,
    
    [Parameter()]
    [string]$Timezone,
    
    [Parameter()]
    [switch]$DryRun,
    
    [Parameter()]
    [switch]$Force,
    
    [Parameter()]
    [Alias('y')]
    [switch]$Yes,
    
    [Parameter()]
    [switch]$Quick,
    
    [Parameter()]
    [switch]$SkipPackages,
    
    [Parameter()]
    [switch]$SkipSecurity,
    
    [Parameter()]
    [switch]$SkipSSH,
    
    [Parameter()]
    [switch]$Essentials,
    
    [Parameter()]
    [switch]$DevTools,
    
    [Parameter()]
    [switch]$Docker,
    
    [Parameter()]
    [switch]$WSL,
    
    [Parameter()]
    [switch]$Firewall,
    
    [Parameter()]
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = $PSScriptRoot
$ScriptVersion = "1.0.0"

# =============================================================================
# Configuration
# =============================================================================

# IMPORTANT: All changes default to FALSE - only do what user explicitly requests
$Script:Config = @{
    InstallEssentials = $false
    InstallDevTools = $false
    InstallDocker = $false
    InstallWSL = $false
    ConfigureSSH = $false
    ConfigureFirewall = $false
    NewHostname = $Hostname
    NewTimezone = $Timezone
    DryRun = $DryRun.IsPresent
    Force = $Force.IsPresent -or $Yes.IsPresent
    Verbose = $Verbose.IsPresent
    Profile = $Profile
}

# Profile definitions
$Script:Profiles = @{
    minimal = @{
        InstallEssentials = $true
        InstallDevTools = $false
        InstallDocker = $false
        InstallWSL = $false
        ConfigureSSH = $false
        ConfigureFirewall = $false
    }
    server = @{
        InstallEssentials = $true
        InstallDevTools = $false
        InstallDocker = $false
        InstallWSL = $false
        ConfigureSSH = $true
        ConfigureFirewall = $true
    }
    workstation = @{
        InstallEssentials = $true
        InstallDevTools = $true
        InstallDocker = $false
        InstallWSL = $false
        ConfigureSSH = $true
        ConfigureFirewall = $false
    }
    dev = @{
        InstallEssentials = $true
        InstallDevTools = $true
        InstallDocker = $true
        InstallWSL = $true
        ConfigureSSH = $true
        ConfigureFirewall = $false
    }
}

# Essential packages (winget IDs)
$Script:EssentialPackages = @(
    @{ Name = "7-Zip"; Id = "7zip.7zip" }
    @{ Name = "Notepad++"; Id = "Notepad++.Notepad++" }
    @{ Name = "Git"; Id = "Git.Git" }
    @{ Name = "cURL"; Id = "cURL.cURL" }
    @{ Name = "wget"; Id = "JernejSimoncic.Wget" }
    @{ Name = "jq"; Id = "jqlang.jq" }
)

# Development packages
$Script:DevPackages = @(
    @{ Name = "Visual Studio Code"; Id = "Microsoft.VisualStudioCode" }
    @{ Name = "Python"; Id = "Python.Python.3.12" }
    @{ Name = "Node.js LTS"; Id = "OpenJS.NodeJS.LTS" }
    @{ Name = "PowerShell 7"; Id = "Microsoft.PowerShell" }
    @{ Name = "Windows Terminal"; Id = "Microsoft.WindowsTerminal" }
)

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
    $border = "=" * $width
    Write-Host ""
    Write-Host $border -ForegroundColor $Script:Colors.Title
    $padding = [math]::Max(0, ($width - $Text.Length) / 2)
    $paddedText = (" " * [math]::Floor($padding)) + $Text + (" " * [math]::Ceiling($padding))
    Write-Host $paddedText -ForegroundColor $Script:Colors.Title
    Write-Host $border -ForegroundColor $Script:Colors.Title
    Write-Host ""
}

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host ">> $Text" -ForegroundColor $Script:Colors.Highlight
}

function Write-Step {
    param([string]$Text)
    Write-Host "  > $Text" -ForegroundColor $Script:Colors.Info
}

function Write-LogInfo {
    param([string]$Text)
    Write-Host "  [i] $Text" -ForegroundColor $Script:Colors.Muted
}

function Write-LogSuccess {
    param([string]$Text)
    Write-Host "  [+] $Text" -ForegroundColor $Script:Colors.Success
}

function Write-LogWarning {
    param([string]$Text)
    Write-Host "  [!] $Text" -ForegroundColor $Script:Colors.Warning
}

function Write-LogError {
    param([string]$Text)
    Write-Host "  [x] $Text" -ForegroundColor $Script:Colors.Error
}

function Write-DryRun {
    param([string]$Text)
    Write-Host "  [DRY RUN] $Text" -ForegroundColor $Script:Colors.Warning
}

function Confirm-Action {
    param(
        [string]$Message,
        [bool]$Default = $true
    )
    
    if ($Script:Config.Force) { return $true }
    
    $defaultHint = if ($Default) { "Y/n" } else { "y/N" }
    $response = Read-Host "  $Message [$defaultHint]"
    
    if ([string]::IsNullOrWhiteSpace($response)) {
        return $Default
    }
    return $response -match '^[Yy]'
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
        $marker = if ($i -eq $Default) { ">" } else { " " }
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

# =============================================================================
# System Detection
# =============================================================================

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-IsWindows11 {
    $build = [System.Environment]::OSVersion.Version.Build
    return $build -ge 22000
}

function Get-WindowsVersion {
    $os = Get-CimInstance Win32_OperatingSystem
    $build = [System.Environment]::OSVersion.Version.Build
    
    $versionName = switch ($true) {
        ($build -ge 22000) { "Windows 11" }
        ($build -ge 19041) { "Windows 10" }
        ($build -ge 17763) { "Windows Server 2019" }
        default { "Windows" }
    }
    
    return @{
        Name = $versionName
        Build = $build
        Edition = $os.Caption
    }
}

function Test-WingetAvailable {
    try {
        $null = Get-Command winget -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Test-ChocolateyAvailable {
    try {
        $null = Get-Command choco -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# =============================================================================
# Package Management
# =============================================================================

function Install-Winget {
    Write-Step "Installing winget..."
    
    if ($Script:Config.DryRun) {
        Write-DryRun "Would install winget (App Installer)"
        return $true
    }
    
    if (Test-WingetAvailable) {
        Write-LogSuccess "winget is already installed"
        return $true
    }
    
    try {
        # Try to install via Microsoft Store App Installer
        $progressPreference = 'SilentlyContinue'
        
        # Download the latest release
        $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        $msixBundle = $releases.assets | Where-Object { $_.name -match '\.msixbundle$' } | Select-Object -First 1
        
        if ($msixBundle) {
            $downloadPath = Join-Path $env:TEMP $msixBundle.name
            Invoke-WebRequest -Uri $msixBundle.browser_download_url -OutFile $downloadPath
            Add-AppxPackage -Path $downloadPath
            Remove-Item $downloadPath -Force
            Write-LogSuccess "winget installed successfully"
            return $true
        }
    } catch {
        Write-LogWarning "Failed to install winget: $_"
        Write-LogInfo "Please install 'App Installer' from the Microsoft Store"
    }
    
    return $false
}

function Install-Chocolatey {
    Write-Step "Installing Chocolatey..."
    
    if ($Script:Config.DryRun) {
        Write-DryRun "Would install Chocolatey"
        return $true
    }
    
    if (Test-ChocolateyAvailable) {
        Write-LogSuccess "Chocolatey is already installed"
        return $true
    }
    
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Write-LogSuccess "Chocolatey installed successfully"
        return $true
    } catch {
        Write-LogWarning "Failed to install Chocolatey: $_"
        return $false
    }
}

function Install-WingetPackage {
    param(
        [string]$Name,
        [string]$Id
    )
    
    Write-Step "Installing $Name..."
    
    if ($Script:Config.DryRun) {
        Write-DryRun "Would install: $Name ($Id)"
        return $true
    }
    
    try {
        # Check if already installed
        $installed = winget list --id $Id --exact 2>$null
        if ($LASTEXITCODE -eq 0 -and $installed -match $Id) {
            Write-LogSuccess "$Name is already installed"
            return $true
        }
        
        # Install
        winget install --id $Id --silent --accept-source-agreements --accept-package-agreements
        
        if ($LASTEXITCODE -eq 0) {
            Write-LogSuccess "$Name installed successfully"
            return $true
        } else {
            Write-LogWarning "Failed to install $Name"
            return $false
        }
    } catch {
        Write-LogWarning "Error installing $Name : $_"
        return $false
    }
}

function Install-EssentialPackages {
    Write-Section "Installing Essential Packages"
    
    if (-not (Test-WingetAvailable)) {
        if (-not (Install-Winget)) {
            Write-LogWarning "winget not available, skipping package installation"
            return
        }
    }
    
    foreach ($pkg in $Script:EssentialPackages) {
        Install-WingetPackage -Name $pkg.Name -Id $pkg.Id
    }
}

function Install-DevPackages {
    Write-Section "Installing Development Tools"
    
    if (-not (Test-WingetAvailable)) {
        Write-LogWarning "winget not available, skipping dev tools"
        return
    }
    
    foreach ($pkg in $Script:DevPackages) {
        Install-WingetPackage -Name $pkg.Name -Id $pkg.Id
    }
}

# =============================================================================
# Docker Installation
# =============================================================================

function Install-Docker {
    Write-Section "Installing Docker"
    
    if ($Script:Config.DryRun) {
        Write-DryRun "Would install Docker Desktop"
        return
    }
    
    # Check if already installed
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        Write-LogSuccess "Docker is already installed"
        return
    }
    
    Write-Step "Installing Docker Desktop..."
    
    if (Test-WingetAvailable) {
        winget install --id Docker.DockerDesktop --silent --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -eq 0) {
            Write-LogSuccess "Docker Desktop installed"
            Write-LogInfo "Please restart your computer to complete Docker installation"
        }
    } else {
        Write-LogWarning "Please install Docker Desktop manually from https://docker.com/products/docker-desktop"
    }
}

# =============================================================================
# WSL Installation
# =============================================================================

function Install-WSL {
    Write-Section "Installing WSL2"
    
    if ($Script:Config.DryRun) {
        Write-DryRun "Would install WSL2 with Ubuntu"
        return
    }
    
    # Check if WSL is already installed
    try {
        $wslStatus = wsl --status 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-LogSuccess "WSL is already installed"
            return
        }
    } catch { }
    
    Write-Step "Installing WSL..."
    
    try {
        wsl --install --no-launch
        Write-LogSuccess "WSL installed"
        Write-LogInfo "Please restart your computer to complete WSL installation"
        Write-LogInfo "After restart, run 'wsl --install -d Ubuntu' to install Ubuntu"
    } catch {
        Write-LogWarning "Failed to install WSL: $_"
        Write-LogInfo "Try running: wsl --install"
    }
}

# =============================================================================
# SSH Configuration
# =============================================================================

function Install-OpenSSH {
    Write-Section "Configuring OpenSSH"
    
    if ($Script:Config.DryRun) {
        Write-DryRun "Would install and configure OpenSSH"
        return
    }
    
    # Check for OpenSSH Client
    Write-Step "Installing OpenSSH Client..."
    $sshClient = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Client*'
    if ($sshClient.State -ne 'Installed') {
        try {
            Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
            Write-LogSuccess "OpenSSH Client installed"
        } catch {
            Write-LogWarning "Failed to install OpenSSH Client: $_"
        }
    } else {
        Write-LogSuccess "OpenSSH Client is already installed"
    }
    
    # Check for OpenSSH Server (optional)
    $installServer = $Script:Config.Profile -eq 'server' -or $Script:Config.Force
    
    if ($installServer) {
        Write-Step "Installing OpenSSH Server..."
        $sshServer = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
        if ($sshServer.State -ne 'Installed') {
            try {
                Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
                Write-LogSuccess "OpenSSH Server installed"
                
                # Configure SSH Server
                Start-Service sshd
                Set-Service -Name sshd -StartupType 'Automatic'
                Write-LogSuccess "SSH Server configured to start automatically"
            } catch {
                Write-LogWarning "Failed to install OpenSSH Server: $_"
            }
        } else {
            Write-LogSuccess "OpenSSH Server is already installed"
        }
    }
}

# =============================================================================
# Firewall Configuration
# =============================================================================

function Configure-Firewall {
    Write-Section "Configuring Windows Firewall"
    
    if ($Script:Config.DryRun) {
        Write-DryRun "Would configure Windows Firewall rules"
        return
    }
    
    # Enable Windows Firewall
    Write-Step "Enabling Windows Firewall..."
    try {
        Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
        Write-LogSuccess "Windows Firewall enabled"
    } catch {
        Write-LogWarning "Failed to enable firewall: $_"
    }
    
    # Create SSH rule if OpenSSH Server is installed
    $sshServer = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
    if ($sshServer.State -eq 'Installed') {
        Write-Step "Configuring SSH firewall rule..."
        try {
            $existingRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
            if (-not $existingRule) {
                New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
                Write-LogSuccess "SSH firewall rule created"
            } else {
                Write-LogSuccess "SSH firewall rule already exists"
            }
        } catch {
            Write-LogWarning "Failed to create SSH firewall rule: $_"
        }
    }
}

# =============================================================================
# System Configuration
# =============================================================================

function Set-ComputerHostname {
    param([string]$NewName)
    
    if ([string]::IsNullOrWhiteSpace($NewName)) { return }
    
    Write-Section "Setting Hostname"
    
    if ($Script:Config.DryRun) {
        Write-DryRun "Would set hostname to: $NewName"
        return
    }
    
    $currentName = $env:COMPUTERNAME
    if ($currentName -eq $NewName) {
        Write-LogSuccess "Hostname is already set to $NewName"
        return
    }
    
    Write-Step "Changing hostname from $currentName to $NewName..."
    try {
        Rename-Computer -NewName $NewName -Force
        Write-LogSuccess "Hostname will be changed to $NewName after restart"
    } catch {
        Write-LogWarning "Failed to change hostname: $_"
    }
}

function Set-SystemTimezone {
    param([string]$TimezoneId)
    
    if ([string]::IsNullOrWhiteSpace($TimezoneId)) { return }
    
    Write-Section "Setting Timezone"
    
    if ($Script:Config.DryRun) {
        Write-DryRun "Would set timezone to: $TimezoneId"
        return
    }
    
    Write-Step "Setting timezone to $TimezoneId..."
    try {
        Set-TimeZone -Id $TimezoneId
        Write-LogSuccess "Timezone set to $TimezoneId"
    } catch {
        Write-LogWarning "Failed to set timezone: $_"
        Write-LogInfo "Use 'Get-TimeZone -ListAvailable' to see available timezones"
    }
}

# =============================================================================
# Interactive Wizard
# =============================================================================

function Show-Wizard {
    Write-Banner "Windows Host Bootstrap Wizard"
    
    $winVer = Get-WindowsVersion
    Write-LogInfo "System: $($winVer.Name) (Build $($winVer.Build))"
    Write-LogInfo "Edition: $($winVer.Edition)"
    Write-Host ""
    
    # Profile selection
    $profileOptions = @(
        "Minimal - Essential tools only",
        "Server - Essentials + SSH + Firewall",
        "Workstation - Essentials + Dev tools",
        "Dev - Full development environment (all tools + Docker + WSL)"
    )
    
    $profileChoice = Show-Menu -Title "Select bootstrap profile:" -Options $profileOptions -Default 2
    $selectedProfile = @('minimal', 'server', 'workstation', 'dev')[$profileChoice]
    
    # Apply profile
    $Script:Config.Profile = $selectedProfile
    $profileConfig = $Script:Profiles[$selectedProfile]
    foreach ($key in $profileConfig.Keys) {
        $Script:Config[$key] = $profileConfig[$key]
    }
    
    Write-Host ""
    Write-LogSuccess "Selected profile: $selectedProfile"
    
    # Optional: Custom hostname
    Write-Host ""
    $setHostname = Confirm-Action -Message "Set a custom hostname?" -Default $false
    if ($setHostname) {
        $Script:Config.NewHostname = Read-Host "  Enter new hostname"
    }
    
    # Additional options for dev profile
    if ($selectedProfile -eq 'workstation') {
        Write-Host ""
        if (Confirm-Action -Message "Also install Docker?" -Default $false) {
            $Script:Config.InstallDocker = $true
        }
        if (Confirm-Action -Message "Also install WSL2?" -Default $false) {
            $Script:Config.InstallWSL = $true
        }
    }
}

# =============================================================================
# Summary Display
# =============================================================================

function Show-Summary {
    Write-Banner "Bootstrap Configuration"
    
    $winVer = Get-WindowsVersion
    Write-Host "  System:            $($winVer.Name) (Build $($winVer.Build))"
    if ($Script:Config.Profile) {
        Write-Host "  Profile:           $($Script:Config.Profile)"
    }
    Write-Host ""
    
    Write-Host "  Configuration:" -ForegroundColor $Script:Colors.Highlight
    if ($Script:Config.NewHostname) {
        Write-Host "    Hostname:        $($Script:Config.NewHostname)"
    }
    if ($Script:Config.NewTimezone) {
        Write-Host "    Timezone:        $($Script:Config.NewTimezone)"
    }
    Write-Host ""
    
    Write-Host "  Packages:" -ForegroundColor $Script:Colors.Highlight
    $essCheck = if ($Script:Config.InstallEssentials) { "[x]" } else { "[ ]" }
    $devCheck = if ($Script:Config.InstallDevTools) { "[x]" } else { "[ ]" }
    $dockerCheck = if ($Script:Config.InstallDocker) { "[x]" } else { "[ ]" }
    $wslCheck = if ($Script:Config.InstallWSL) { "[x]" } else { "[ ]" }
    
    Write-Host "    $essCheck Essential tools (Git, 7-Zip, curl, etc.)"
    Write-Host "    $devCheck Development tools (VS Code, Python, Node.js)"
    Write-Host "    $dockerCheck Docker Desktop"
    Write-Host "    $wslCheck WSL2"
    Write-Host ""
    
    Write-Host "  Security:" -ForegroundColor $Script:Colors.Highlight
    $sshCheck = if ($Script:Config.ConfigureSSH) { "[x]" } else { "[ ]" }
    $fwCheck = if ($Script:Config.ConfigureFirewall) { "[x]" } else { "[ ]" }
    
    Write-Host "    $sshCheck OpenSSH configuration"
    Write-Host "    $fwCheck Windows Firewall"
    Write-Host ""
    
    if ($Script:Config.DryRun) {
        Write-Host "  Mode: DRY RUN - No changes will be made" -ForegroundColor $Script:Colors.Warning
        Write-Host ""
    }
    
    Write-Host ("=" * 60) -ForegroundColor $Script:Colors.Title
}

function Show-Completion {
    Write-Host ""
    Write-Banner "Bootstrap Complete!"
    
    if ($Script:Config.DryRun) {
        Write-Host "  This was a dry run. Run without -DryRun to apply changes."
        Write-Host ""
        Write-Host "  Example: .\Initialize-HostBootstrap.ps1 -Profile $($Script:Config.Profile)"
    } else {
        $needsRestart = $Script:Config.NewHostname -or $Script:Config.InstallWSL -or $Script:Config.InstallDocker
        
        if ($needsRestart) {
            Write-Host "  Some changes require a restart to take effect." -ForegroundColor $Script:Colors.Warning
            Write-Host ""
        }
        
        Write-Host "  Next steps:"
        if ($Script:Config.InstallWSL) {
            Write-Host "    - Restart and run 'wsl --install -d Ubuntu'"
        }
        if ($Script:Config.InstallDocker) {
            Write-Host "    - Start Docker Desktop from the Start menu"
        }
        Write-Host "    - Run 'rsr health' to verify system health"
    }
    
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor $Script:Colors.Title
}

# =============================================================================
# Main Entry Point
# =============================================================================

function Main {
    # Check for admin rights
    if (-not (Test-IsAdmin)) {
        Write-LogWarning "This script should be run as Administrator for full functionality"
        Write-LogInfo "Some features may be unavailable"
        Write-Host ""
    }
    
    # Apply command-line switches
    if ($Essentials) { $Script:Config.InstallEssentials = $true }
    if ($DevTools) { $Script:Config.InstallDevTools = $true }
    if ($Docker) { $Script:Config.InstallDocker = $true }
    if ($WSL) { $Script:Config.InstallWSL = $true }
    if ($Firewall) { $Script:Config.ConfigureFirewall = $true }
    if ($SkipPackages) { 
        $Script:Config.InstallEssentials = $false 
        $Script:Config.InstallDevTools = $false
    }
    if ($SkipSecurity) { 
        $Script:Config.ConfigureSSH = $false 
        $Script:Config.ConfigureFirewall = $false
    }
    if ($SkipSSH) { $Script:Config.ConfigureSSH = $false }
    
    # Apply profile if specified
    if ($Profile) {
        $profileConfig = $Script:Profiles[$Profile]
        foreach ($key in $profileConfig.Keys) {
            $Script:Config[$key] = $profileConfig[$key]
        }
    }
    
    # Quick mode defaults
    if ($Quick -and -not $Profile) {
        $Script:Config.Profile = 'server'
        $profileConfig = $Script:Profiles['server']
        foreach ($key in $profileConfig.Keys) {
            $Script:Config[$key] = $profileConfig[$key]
        }
    }
    
    # Interactive mode
    $isInteractive = -not $Profile -and -not $Quick -and [Environment]::UserInteractive -and -not $Force
    if ($isInteractive) {
        Show-Wizard
    }
    
    # Show summary
    Show-Summary
    
    # Confirm
    if (-not $Script:Config.DryRun -and -not $Script:Config.Force) {
        if (-not (Confirm-Action -Message "Proceed with bootstrap?" -Default $true)) {
            Write-LogInfo "Bootstrap cancelled"
            return
        }
    }
    
    Write-Section "Starting Bootstrap Process"
    
    # System configuration
    Set-ComputerHostname -NewName $Script:Config.NewHostname
    Set-SystemTimezone -TimezoneId $Script:Config.NewTimezone
    
    # Package installation
    if (-not $SkipPackages) {
        if ($Script:Config.InstallEssentials) {
            Install-EssentialPackages
        }
        if ($Script:Config.InstallDevTools) {
            Install-DevPackages
        }
        if ($Script:Config.InstallDocker) {
            Install-Docker
        }
        if ($Script:Config.InstallWSL) {
            Install-WSL
        }
    }
    
    # Security configuration
    if (-not $SkipSecurity) {
        if ($Script:Config.ConfigureSSH) {
            Install-OpenSSH
        }
        if ($Script:Config.ConfigureFirewall) {
            Configure-Firewall
        }
    }
    
    # Completion
    Show-Completion
}

# Run main
Main
