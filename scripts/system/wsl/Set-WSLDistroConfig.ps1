#!/usr/bin/env pwsh
#Requires -Version 5.1

<#
.SYNOPSIS
    Configure WSL distribution settings (/etc/wsl.conf)
.DESCRIPTION
    Manages per-distribution WSL configuration including:
    - Systemd enablement (required for service management)
    - Automount settings for Windows drives
    - Network configuration
    - Interop settings between Windows and Linux
    - Default user configuration
.PARAMETER Distro
    Name of the distribution to configure (default: current default distro)
.PARAMETER EnableSystemd
    Enable systemd init system (recommended for RSR)
.PARAMETER DisableSystemd
    Disable systemd init system
.PARAMETER DefaultUser
    Set the default login user
.PARAMETER AutomountEnabled
    Enable/disable automatic mounting of Windows drives
.PARAMETER AutomountRoot
    Mount point for Windows drives (default: /mnt/)
.PARAMETER AutomountOptions
    Mount options (e.g., "metadata,umask=22,fmask=11")
.PARAMETER GenerateHosts
    Enable/disable automatic /etc/hosts generation
.PARAMETER GenerateResolvConf
    Enable/disable automatic /etc/resolv.conf generation
.PARAMETER InteropEnabled
    Enable/disable Windows interop (running .exe from Linux)
.PARAMETER AppendWindowsPath
    Append Windows PATH to Linux PATH
.PARAMETER ShowConfig
    Display current configuration without making changes
.PARAMETER ApplyDefaults
    Apply recommended default configuration for development
.EXAMPLE
    .\Set-WSLDistroConfig.ps1 -Distro Ubuntu -EnableSystemd
.EXAMPLE
    .\Set-WSLDistroConfig.ps1 -ApplyDefaults
.EXAMPLE
    .\Set-WSLDistroConfig.ps1 -ShowConfig
#>

[CmdletBinding(DefaultParameterSetName = 'Configure')]
param(
    [string]$Distro,

    [Parameter(ParameterSetName = 'Configure')]
    [switch]$EnableSystemd,

    [Parameter(ParameterSetName = 'Configure')]
    [switch]$DisableSystemd,

    [Parameter(ParameterSetName = 'Configure')]
    [string]$DefaultUser,

    [Parameter(ParameterSetName = 'Configure')]
    [Nullable[bool]]$AutomountEnabled,

    [Parameter(ParameterSetName = 'Configure')]
    [string]$AutomountRoot,

    [Parameter(ParameterSetName = 'Configure')]
    [string]$AutomountOptions,

    [Parameter(ParameterSetName = 'Configure')]
    [Nullable[bool]]$GenerateHosts,

    [Parameter(ParameterSetName = 'Configure')]
    [Nullable[bool]]$GenerateResolvConf,

    [Parameter(ParameterSetName = 'Configure')]
    [Nullable[bool]]$InteropEnabled,

    [Parameter(ParameterSetName = 'Configure')]
    [Nullable[bool]]$AppendWindowsPath,

    [Parameter(ParameterSetName = 'Show')]
    [switch]$ShowConfig,

    [Parameter(ParameterSetName = 'Defaults')]
    [switch]$ApplyDefaults
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
# Core Functions
# =============================================================================

function Get-DefaultDistro {
    try {
        $output = wsl.exe --list --verbose 2>&1 | Out-String
        $lines = $output -split "`r?`n"

        foreach ($line in $lines) {
            if ($line -match '^\s*\*\s*(\S+)') {
                return $Matches[1]
            }
        }
    }
    catch {}
    return $null
}

function Test-DistroExists {
    param([string]$DistroName)

    $output = wsl.exe --list --quiet 2>&1
    $distros = $output | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() -replace '\x00', '' }
    return $DistroName -in $distros
}

function Get-WSLDistroConfig {
    <#
    .SYNOPSIS
        Read current wsl.conf from a distribution
    #>
    param([string]$DistroName)

    try {
        $content = wsl.exe -d $DistroName -- cat /etc/wsl.conf 2>&1
        if ($LASTEXITCODE -eq 0) {
            return $content | Out-String
        }
    }
    catch {}
    return $null
}

function Set-WSLDistroConfigFile {
    <#
    .SYNOPSIS
        Write wsl.conf to a distribution
    #>
    param(
        [string]$DistroName,
        [string]$Content
    )

    # Write config using a here-doc approach
    $escapedContent = $Content -replace "'", "'\\''"
    $cmd = "echo '$escapedContent' | sudo tee /etc/wsl.conf > /dev/null"

    wsl.exe -d $DistroName -- bash -c $cmd 2>&1 | Out-Null

    return $LASTEXITCODE -eq 0
}

function ConvertFrom-IniContent {
    <#
    .SYNOPSIS
        Parse INI-style content into a hashtable
    #>
    param([string]$Content)

    $result = @{}
    $currentSection = $null

    foreach ($line in ($Content -split "`r?`n")) {
        $line = $line.Trim()

        # Skip empty lines and comments
        if (-not $line -or $line.StartsWith('#') -or $line.StartsWith(';')) {
            continue
        }

        # Section header
        if ($line -match '^\[(.+)\]$') {
            $currentSection = $Matches[1]
            if (-not $result.ContainsKey($currentSection)) {
                $result[$currentSection] = @{}
            }
            continue
        }

        # Key-value pair
        if ($currentSection -and $line -match '^([^=]+)=(.*)$') {
            $key = $Matches[1].Trim()
            $value = $Matches[2].Trim()
            $result[$currentSection][$key] = $value
        }
    }

    return $result
}

function ConvertTo-IniContent {
    <#
    .SYNOPSIS
        Convert hashtable to INI-style content
    #>
    param([hashtable]$Config)

    $lines = @()
    $lines += "# WSL Configuration - Generated by RSR $(Get-Date -Format 'yyyy-MM-dd')"
    $lines += "# Documentation: https://learn.microsoft.com/en-us/windows/wsl/wsl-config"
    $lines += ""

    foreach ($section in $Config.Keys | Sort-Object) {
        $lines += "[$section]"
        foreach ($key in $Config[$section].Keys | Sort-Object) {
            $value = $Config[$section][$key]
            $lines += "$key=$value"
        }
        $lines += ""
    }

    return $lines -join "`n"
}

function Get-RecommendedConfig {
    <#
    .SYNOPSIS
        Get recommended wsl.conf settings for development
    #>
    return @{
        boot = @{
            systemd = 'true'  # Required for service management
        }
        automount = @{
            enabled = 'true'
            root = '/mnt/'
            options = 'metadata,umask=22,fmask=11'  # Better permission handling
        }
        network = @{
            generateHosts = 'true'
            generateResolvConf = 'true'
        }
        interop = @{
            enabled = 'true'
            appendWindowsPath = 'true'  # Access Windows commands from Linux
        }
    }
}

# =============================================================================
# Main
# =============================================================================

Write-Banner "WSL Distribution Configuration"

# Check WSL availability
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-Status "WSL is not installed" -Type error
    exit 1
}

# Determine target distro
if (-not $Distro) {
    $Distro = Get-DefaultDistro
    if (-not $Distro) {
        Write-Status "No default distribution found. Specify -Distro" -Type error
        exit 1
    }
}

if (-not (Test-DistroExists $Distro)) {
    Write-Status "Distribution '$Distro' not found" -Type error
    exit 1
}

Write-Host ""
Write-Status "Target: $Distro" -Type info

# Get current configuration
$currentContent = Get-WSLDistroConfig -DistroName $Distro
$config = if ($currentContent) { ConvertFrom-IniContent $currentContent } else { @{} }

# Show current config mode
if ($ShowConfig) {
    Write-Host ""
    if ($currentContent) {
        Write-Host "  Current /etc/wsl.conf:" -ForegroundColor $Script:Colors.Highlight
        Write-Host ""
        foreach ($line in ($currentContent -split "`r?`n")) {
            Write-Host "    $line" -ForegroundColor $Script:Colors.Muted
        }
    }
    else {
        Write-Status "No wsl.conf found (using WSL defaults)" -Type info
    }

    Write-Host ""
    Write-Host "  Effective settings:" -ForegroundColor $Script:Colors.Highlight

    # Determine effective systemd status
    $systemdEnabled = $config['boot']?['systemd'] -eq 'true'
    Write-Status "Systemd: $(if ($systemdEnabled) { 'Enabled' } else { 'Disabled' })" -Type $(if ($systemdEnabled) { 'success' } else { 'warning' })

    $interopEnabled = ($config['interop']?['enabled'] -ne 'false')
    Write-Status "Windows interop: $(if ($interopEnabled) { 'Enabled' } else { 'Disabled' })" -Type info

    $automountEnabled = ($config['automount']?['enabled'] -ne 'false')
    Write-Status "Automount: $(if ($automountEnabled) { 'Enabled' } else { 'Disabled' })" -Type info

    exit 0
}

# Apply defaults mode
if ($ApplyDefaults) {
    Write-Host ""
    Write-Status "Applying recommended configuration..." -Type pending

    $config = Get-RecommendedConfig
    $newContent = ConvertTo-IniContent $config

    if (Set-WSLDistroConfigFile -DistroName $Distro -Content $newContent) {
        Write-Status "Configuration applied" -Type success
        Write-Host ""
        Write-Host "  Applied settings:" -ForegroundColor $Script:Colors.Highlight
        Write-Status "Systemd: Enabled" -Type success
        Write-Status "Automount: Enabled with metadata" -Type success
        Write-Status "Network: Auto-generate hosts/resolv.conf" -Type success
        Write-Status "Interop: Enabled with Windows PATH" -Type success
    }
    else {
        Write-Status "Failed to write configuration" -Type error
        exit 1
    }

    Write-Host ""
    Write-Status "Restart WSL to apply: wsl --shutdown" -Type warning
    exit 0
}

# Configure mode - build changes
$changes = @()

# Ensure sections exist
if (-not $config.ContainsKey('boot')) { $config['boot'] = @{} }
if (-not $config.ContainsKey('automount')) { $config['automount'] = @{} }
if (-not $config.ContainsKey('network')) { $config['network'] = @{} }
if (-not $config.ContainsKey('interop')) { $config['interop'] = @{} }
if (-not $config.ContainsKey('user')) { $config['user'] = @{} }

# Apply changes
if ($EnableSystemd) {
    $config['boot']['systemd'] = 'true'
    $changes += "Enabled systemd"
}

if ($DisableSystemd) {
    $config['boot']['systemd'] = 'false'
    $changes += "Disabled systemd"
}

if ($DefaultUser) {
    $config['user']['default'] = $DefaultUser
    $changes += "Set default user to: $DefaultUser"
}

if ($null -ne $AutomountEnabled) {
    $config['automount']['enabled'] = $AutomountEnabled.ToString().ToLower()
    $changes += "Automount: $($AutomountEnabled.ToString().ToLower())"
}

if ($AutomountRoot) {
    $config['automount']['root'] = $AutomountRoot
    $changes += "Automount root: $AutomountRoot"
}

if ($AutomountOptions) {
    $config['automount']['options'] = $AutomountOptions
    $changes += "Automount options: $AutomountOptions"
}

if ($null -ne $GenerateHosts) {
    $config['network']['generateHosts'] = $GenerateHosts.ToString().ToLower()
    $changes += "Generate hosts: $($GenerateHosts.ToString().ToLower())"
}

if ($null -ne $GenerateResolvConf) {
    $config['network']['generateResolvConf'] = $GenerateResolvConf.ToString().ToLower()
    $changes += "Generate resolv.conf: $($GenerateResolvConf.ToString().ToLower())"
}

if ($null -ne $InteropEnabled) {
    $config['interop']['enabled'] = $InteropEnabled.ToString().ToLower()
    $changes += "Interop: $($InteropEnabled.ToString().ToLower())"
}

if ($null -ne $AppendWindowsPath) {
    $config['interop']['appendWindowsPath'] = $AppendWindowsPath.ToString().ToLower()
    $changes += "Append Windows PATH: $($AppendWindowsPath.ToString().ToLower())"
}

# Apply if there are changes
if ($changes.Count -gt 0) {
    Write-Host ""

    # Remove empty sections
    $config.Keys | Where-Object { $config[$_].Count -eq 0 } | ForEach-Object { $config.Remove($_) }

    $newContent = ConvertTo-IniContent $config

    if (Set-WSLDistroConfigFile -DistroName $Distro -Content $newContent) {
        foreach ($change in $changes) {
            Write-Status $change -Type success
        }

        Write-Host ""
        Write-Status "Configuration updated" -Type success
        Write-Status "Restart WSL to apply: wsl --shutdown" -Type warning
    }
    else {
        Write-Status "Failed to write configuration" -Type error
        exit 1
    }
}
else {
    Write-Host ""
    Write-Status "No changes specified. Use -ShowConfig to view current settings." -Type info
    Write-Host ""
    Write-Host "  Options:" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -EnableSystemd      Enable systemd (recommended)" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -DefaultUser NAME   Set default user" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -ApplyDefaults      Apply recommended settings" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -ShowConfig         Display current configuration" -ForegroundColor $Script:Colors.Muted
}

