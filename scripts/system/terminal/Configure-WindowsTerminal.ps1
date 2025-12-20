#!/usr/bin/env pwsh
#Requires -Version 5.1

<#
.SYNOPSIS
    Configure Windows Terminal for optimal WSL/development experience
.DESCRIPTION
    Configures Windows Terminal settings including:
    - WSL distro profiles with proper icons and colors
    - Font settings (Cascadia Code, Nerd Fonts)
    - Color schemes for development
    - Keyboard shortcuts
    - Default profile selection
.PARAMETER SetDefaultProfile
    Set the default profile (WSL distro name or 'PowerShell')
.PARAMETER InstallFont
    Install recommended fonts (CascadiaCode, FiraCode, JetBrainsMono)
.PARAMETER ColorScheme
    Apply color scheme to all profiles (One Half Dark, Dracula, Nord, Solarized)
.PARAMETER ConfigureWSLProfiles
    Auto-configure profiles for installed WSL distributions
.PARAMETER BackupSettings
    Backup current settings before making changes
.PARAMETER RestoreSettings
    Restore settings from backup
.PARAMETER ShowConfig
    Display current configuration
.EXAMPLE
    .\Configure-WindowsTerminal.ps1 -ConfigureWSLProfiles
.EXAMPLE
    .\Configure-WindowsTerminal.ps1 -SetDefaultProfile Ubuntu -ColorScheme "One Half Dark"
.EXAMPLE
    .\Configure-WindowsTerminal.ps1 -InstallFont CascadiaCode
#>

[CmdletBinding(DefaultParameterSetName = 'Configure')]
param(
    [Parameter(ParameterSetName = 'Configure')]
    [string]$SetDefaultProfile,

    [Parameter(ParameterSetName = 'Font')]
    [ValidateSet('CascadiaCode', 'CascadiaCodeNF', 'FiraCode', 'JetBrainsMono')]
    [string]$InstallFont,

    [Parameter(ParameterSetName = 'Configure')]
    [ValidateSet('One Half Dark', 'One Half Light', 'Dracula', 'Nord', 'Solarized Dark', 'Solarized Light', 'Campbell')]
    [string]$ColorScheme,

    [Parameter(ParameterSetName = 'Configure')]
    [switch]$ConfigureWSLProfiles,

    [Parameter(ParameterSetName = 'Backup')]
    [switch]$BackupSettings,

    [Parameter(ParameterSetName = 'Restore')]
    [switch]$RestoreSettings,

    [Parameter(ParameterSetName = 'Show')]
    [switch]$ShowConfig
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
# Path Detection
# =============================================================================

function Get-WindowsTerminalSettingsPath {
    <#
    .SYNOPSIS
        Find Windows Terminal settings.json location
    #>
    $possiblePaths = @(
        # Stable release
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        # Preview release
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
        # Scoop installation
        "$env:USERPROFILE\scoop\apps\windows-terminal\current\settings\settings.json"
        # Chocolatey/manual
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    return $null
}

function Test-WindowsTerminalInstalled {
    $settingsPath = Get-WindowsTerminalSettingsPath
    return $null -ne $settingsPath
}

# =============================================================================
# Settings Management
# =============================================================================

function Get-TerminalSettings {
    $path = Get-WindowsTerminalSettingsPath
    if (-not $path) { return $null }

    $content = Get-Content $path -Raw
    # Remove comments (Windows Terminal uses JSON with comments)
    $content = $content -replace '//.*$', '' -replace '/\*[\s\S]*?\*/', ''

    try {
        return $content | ConvertFrom-Json -AsHashtable
    }
    catch {
        # Try without -AsHashtable for PS 5.1
        return $content | ConvertFrom-Json
    }
}

function Save-TerminalSettings {
    param($Settings)

    $path = Get-WindowsTerminalSettingsPath
    if (-not $path) { return $false }

    $json = $Settings | ConvertTo-Json -Depth 10
    $json | Set-Content $path -Encoding UTF8

    return $true
}

function Backup-TerminalSettings {
    $path = Get-WindowsTerminalSettingsPath
    if (-not $path) { return $null }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = [System.IO.Path]::ChangeExtension($path, ".backup-$timestamp.json")

    Copy-Item $path $backupPath
    return $backupPath
}

function Get-LatestBackup {
    $path = Get-WindowsTerminalSettingsPath
    if (-not $path) { return $null }

    $dir = Split-Path $path -Parent
    $backups = Get-ChildItem $dir -Filter "*.backup-*.json" | Sort-Object LastWriteTime -Descending

    return $backups | Select-Object -First 1
}

# =============================================================================
# WSL Integration
# =============================================================================

function Get-InstalledWSLDistros {
    try {
        $output = wsl.exe --list --quiet 2>&1
        return $output | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() -replace '\x00', '' }
    }
    catch {
        return @()
    }
}

function Get-DistroIcon {
    param([string]$DistroName)

    # Map distro names to icons (using emoji as fallback, Terminal supports these)
    $iconMap = @{
        'Ubuntu'        = '🐧'
        'Debian'        = '🌀'
        'kali-linux'    = '🐉'
        'openSUSE'      = '🦎'
        'Alpine'        = '🏔️'
        'Fedora'        = '🎩'
        'Arch'          = '💠'
    }

    foreach ($key in $iconMap.Keys) {
        if ($DistroName -match $key) {
            return $iconMap[$key]
        }
    }

    return '🐧'  # Default Linux icon
}

function Get-DistroColor {
    param([string]$DistroName)

    # Map distro names to theme colors
    $colorMap = @{
        'Ubuntu'        = '#E95420'  # Ubuntu orange
        'Debian'        = '#D70A53'  # Debian red
        'kali-linux'    = '#557C94'  # Kali blue
        'openSUSE'      = '#73BA25'  # openSUSE green
        'Alpine'        = '#0D597F'  # Alpine blue
        'Fedora'        = '#294172'  # Fedora blue
        'Arch'          = '#1793D1'  # Arch blue
    }

    foreach ($key in $colorMap.Keys) {
        if ($DistroName -match $key) {
            return $colorMap[$key]
        }
    }

    return '#4E9A06'  # Default green
}

# =============================================================================
# Font Installation
# =============================================================================

function Install-NerdFont {
    param(
        [ValidateSet('CascadiaCode', 'CascadiaCodeNF', 'FiraCode', 'JetBrainsMono')]
        [string]$FontName
    )

    $fontUrls = @{
        'CascadiaCode'   = 'https://github.com/microsoft/cascadia-code/releases/latest/download/CascadiaCode-2404.23.zip'
        'CascadiaCodeNF' = 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip'
        'FiraCode'       = 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip'
        'JetBrainsMono'  = 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip'
    }

    Write-Status "Downloading $FontName..." -Type pending

    $tempDir = Join-Path $env:TEMP "font-install-$FontName"
    $zipPath = "$tempDir.zip"

    try {
        # Download
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $fontUrls[$FontName] -OutFile $zipPath

        # Extract
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
        Expand-Archive $zipPath -DestinationPath $tempDir

        # Install fonts
        $fonts = Get-ChildItem $tempDir -Filter "*.ttf" -Recurse
        $fonts += Get-ChildItem $tempDir -Filter "*.otf" -Recurse

        $shell = New-Object -ComObject Shell.Application
        $fontsFolder = $shell.Namespace(0x14)  # Windows Fonts folder

        $installed = 0
        foreach ($font in $fonts) {
            # Skip variable fonts and windows-compatible versions for cleaner install
            if ($font.Name -match 'Variable|Windows') { continue }

            $fontsFolder.CopyHere($font.FullName, 0x10)  # 0x10 = overwrite
            $installed++
        }

        Write-Status "Installed $installed font files" -Type success

        # Cleanup
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

        return $true
    }
    catch {
        Write-Status "Font installation failed: $_" -Type error
        return $false
    }
}

# =============================================================================
# Profile Configuration
# =============================================================================

function Update-WSLProfiles {
    param($Settings)

    $distros = Get-InstalledWSLDistros

    if ($distros.Count -eq 0) {
        Write-Status "No WSL distributions found" -Type warning
        return $Settings
    }

    # Get existing profiles
    $profiles = $Settings.profiles.list

    foreach ($distro in $distros) {
        # Find existing profile for this distro
        $existingProfile = $profiles | Where-Object {
            $_.name -eq $distro -or $_.source -match $distro
        }

        if ($existingProfile) {
            # Update existing profile
            $existingProfile | Add-Member -NotePropertyName 'tabTitle' -NotePropertyValue $distro -Force
            $existingProfile | Add-Member -NotePropertyName 'tabColor' -NotePropertyValue (Get-DistroColor $distro) -Force
            $existingProfile | Add-Member -NotePropertyName 'font' -NotePropertyValue @{
                face = 'Cascadia Code NF'
                size = 11
            } -Force

            Write-Status "Updated profile: $distro" -Type success
        }
        else {
            Write-Status "Profile for $distro will be auto-created by Terminal" -Type info
        }
    }

    return $Settings
}

function Set-DefaultProfileByName {
    param(
        $Settings,
        [string]$ProfileName
    )

    $profiles = $Settings.profiles.list

    # Find matching profile
    $profile = $profiles | Where-Object {
        $_.name -eq $ProfileName -or
        $_.name -match $ProfileName -or
        $_.source -match $ProfileName
    } | Select-Object -First 1

    if ($profile -and $profile.guid) {
        $Settings.defaultProfile = $profile.guid
        return $true
    }

    return $false
}

# =============================================================================
# Main
# =============================================================================

Write-Banner "Windows Terminal Configuration"

# Check if Terminal is installed
if (-not (Test-WindowsTerminalInstalled)) {
    Write-Status "Windows Terminal not found" -Type error
    Write-Host ""
    Write-Host "  Install with:" -ForegroundColor $Script:Colors.Muted
    Write-Host "    winget install Microsoft.WindowsTerminal" -ForegroundColor $Script:Colors.Muted
    exit 1
}

$settingsPath = Get-WindowsTerminalSettingsPath
Write-Host ""
Write-Status "Settings: $settingsPath" -Type info

# Font installation mode
if ($InstallFont) {
    Write-Host ""
    Install-NerdFont -FontName $InstallFont
    Write-Host ""
    Write-Status "Restart Windows Terminal to use the new font" -Type warning
    exit 0
}

# Backup mode
if ($BackupSettings) {
    Write-Host ""
    $backupPath = Backup-TerminalSettings
    if ($backupPath) {
        Write-Status "Backed up to: $backupPath" -Type success
    }
    else {
        Write-Status "Backup failed" -Type error
    }
    exit 0
}

# Restore mode
if ($RestoreSettings) {
    Write-Host ""
    $backup = Get-LatestBackup
    if ($backup) {
        Copy-Item $backup.FullName $settingsPath -Force
        Write-Status "Restored from: $($backup.Name)" -Type success
    }
    else {
        Write-Status "No backup found" -Type warning
    }
    exit 0
}

# Show config mode
if ($ShowConfig) {
    $settings = Get-TerminalSettings
    Write-Host ""

    # Default profile
    $defaultGuid = $settings.defaultProfile
    $defaultProfile = $settings.profiles.list | Where-Object { $_.guid -eq $defaultGuid }
    Write-Status "Default profile: $($defaultProfile.name)" -Type info

    # Font
    $font = $settings.profiles.defaults.font.face
    if (-not $font) { $font = "Cascadia Mono (default)" }
    Write-Status "Font: $font" -Type info

    # Color scheme
    $scheme = $settings.profiles.defaults.colorScheme
    if (-not $scheme) { $scheme = "Campbell (default)" }
    Write-Status "Color scheme: $scheme" -Type info

    # WSL profiles
    Write-Host ""
    Write-Host "  WSL Profiles:" -ForegroundColor $Script:Colors.Highlight
    $wslProfiles = $settings.profiles.list | Where-Object { $_.source -match 'WSL' -or $_.commandline -match 'wsl' }
    foreach ($p in $wslProfiles) {
        Write-Host "    • $($p.name)" -ForegroundColor $Script:Colors.Muted
    }

    exit 0
}

# Configure mode
$settings = Get-TerminalSettings
$changes = @()

# Create backup before making changes
if ($ConfigureWSLProfiles -or $SetDefaultProfile -or $ColorScheme) {
    $backupPath = Backup-TerminalSettings
    Write-Status "Backup created: $([System.IO.Path]::GetFileName($backupPath))" -Type info
}

# Configure WSL profiles
if ($ConfigureWSLProfiles) {
    Write-Host ""
    $settings = Update-WSLProfiles $settings
    $changes += "Configured WSL profiles"
}

# Set default profile
if ($SetDefaultProfile) {
    Write-Host ""
    if (Set-DefaultProfileByName $settings $SetDefaultProfile) {
        Write-Status "Default profile set to: $SetDefaultProfile" -Type success
        $changes += "Set default profile"
    }
    else {
        Write-Status "Profile '$SetDefaultProfile' not found" -Type warning
    }
}

# Apply color scheme
if ($ColorScheme) {
    Write-Host ""

    # Ensure defaults section exists
    if (-not $settings.profiles.defaults) {
        $settings.profiles | Add-Member -NotePropertyName 'defaults' -NotePropertyValue @{} -Force
    }

    $settings.profiles.defaults | Add-Member -NotePropertyName 'colorScheme' -NotePropertyValue $ColorScheme -Force

    Write-Status "Applied color scheme: $ColorScheme" -Type success
    $changes += "Applied color scheme"
}

# Save changes
if ($changes.Count -gt 0) {
    if (Save-TerminalSettings $settings) {
        Write-Host ""
        Write-Status "Configuration saved" -Type success
        Write-Status "Changes will apply when Terminal restarts" -Type info
    }
    else {
        Write-Status "Failed to save configuration" -Type error
        exit 1
    }
}
else {
    Write-Host ""
    Write-Status "No changes specified" -Type info
    Write-Host ""
    Write-Host "  Options:" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -ConfigureWSLProfiles    Configure WSL distro profiles" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -SetDefaultProfile NAME  Set default profile" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -ColorScheme SCHEME      Apply color scheme" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -InstallFont FONT        Install development font" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -ShowConfig              Show current configuration" -ForegroundColor $Script:Colors.Muted
}

