#!/usr/bin/env pwsh
#Requires -Version 5.1

<#
.SYNOPSIS
    Configure Docker Desktop for WSL 2 integration
.DESCRIPTION
    Sets up Docker Desktop with optimal WSL 2 backend configuration:
    - Installs Docker Desktop if not present
    - Enables WSL 2 backend
    - Configures WSL distro integration
    - Sets resource limits in .wslconfig
    - Configures Docker CLI in WSL
.PARAMETER Install
    Install Docker Desktop
.PARAMETER EnableWSLIntegration
    Enable Docker integration with WSL distros
.PARAMETER Distro
    Specific WSL distro to enable (default: all installed)
.PARAMETER ConfigureResources
    Configure Docker resource limits
.PARAMETER MemoryGB
    Memory limit for Docker in GB (default: 4)
.PARAMETER CPUs
    CPU limit for Docker (default: 2)
.PARAMETER ShowStatus
    Display current Docker/WSL integration status
.EXAMPLE
    .\Configure-DockerWSL.ps1 -Install
.EXAMPLE
    .\Configure-DockerWSL.ps1 -EnableWSLIntegration
.EXAMPLE
    .\Configure-DockerWSL.ps1 -ConfigureResources -MemoryGB 8 -CPUs 4
#>

[CmdletBinding(DefaultParameterSetName = 'Configure')]
param(
    [switch]$Install,

    [switch]$EnableWSLIntegration,

    [string]$Distro,

    [switch]$ConfigureResources,

    [int]$MemoryGB = 4,

    [int]$CPUs = 2,

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

function Test-DockerDesktopInstalled {
    $dockerPaths = @(
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
        "$env:LOCALAPPDATA\Docker\Docker Desktop.exe"
    )

    foreach ($path in $dockerPaths) {
        if (Test-Path $path) { return $true }
    }

    return $false
}

function Test-DockerRunning {
    try {
        $result = docker info 2>&1
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Get-DockerDesktopSettingsPath {
    return "$env:APPDATA\Docker\settings.json"
}

function Get-DockerDesktopSettings {
    $path = Get-DockerDesktopSettingsPath
    if (Test-Path $path) {
        return Get-Content $path -Raw | ConvertFrom-Json
    }
    return $null
}

function Save-DockerDesktopSettings {
    param($Settings)

    $path = Get-DockerDesktopSettingsPath
    $Settings | ConvertTo-Json -Depth 10 | Set-Content $path -Encoding UTF8
}

function Get-InstalledWSLDistros {
    try {
        $output = wsl.exe --list --quiet 2>&1
        return $output | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() -replace '\x00', '' }
    }
    catch {
        return @()
    }
}

function Get-WSLConfigPath {
    return Join-Path $env:USERPROFILE ".wslconfig"
}

# =============================================================================
# Installation
# =============================================================================

function Install-DockerDesktop {
    Write-Status "Installing Docker Desktop..." -Type pending

    if (Test-DockerDesktopInstalled) {
        Write-Status "Docker Desktop already installed" -Type success
        return $true
    }

    # Check system requirements
    $os = Get-CimInstance Win32_OperatingSystem
    if ([int]$os.BuildNumber -lt 19041) {
        Write-Status "Windows build 19041+ required for Docker WSL 2 backend" -Type error
        return $false
    }

    # Try winget first
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Status "Installing via winget..." -Type pending

        $result = winget install --id Docker.DockerDesktop --accept-source-agreements --accept-package-agreements -e 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Status "Docker Desktop installed" -Type success
            Write-Status "Please restart your computer to complete installation" -Type warning
            return $true
        }
    }

    # Try Chocolatey
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Status "Installing via Chocolatey..." -Type pending
        choco install docker-desktop -y 2>&1 | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Status "Docker Desktop installed" -Type success
            Write-Status "Please restart your computer to complete installation" -Type warning
            return $true
        }
    }

    # Manual download instructions
    Write-Status "Automatic installation failed" -Type warning
    Write-Host ""
    Write-Host "  Download Docker Desktop from:" -ForegroundColor $Script:Colors.Highlight
    Write-Host "    https://www.docker.com/products/docker-desktop" -ForegroundColor $Script:Colors.Muted

    return $false
}

# =============================================================================
# Configuration
# =============================================================================

function Enable-DockerWSLIntegration {
    param([string[]]$Distros)

    Write-Status "Configuring Docker WSL integration..." -Type pending

    if (-not (Test-DockerDesktopInstalled)) {
        Write-Status "Docker Desktop not installed" -Type error
        return $false
    }

    $settings = Get-DockerDesktopSettings

    if (-not $settings) {
        Write-Status "Docker settings not found. Start Docker Desktop first." -Type warning
        return $false
    }

    try {
        # Enable WSL 2 backend
        $settings.wslEngineEnabled = $true

        # Enable integration with specified distros
        if (-not $settings.PSObject.Properties['integratedWslDistros']) {
            $settings | Add-Member -NotePropertyName 'integratedWslDistros' -NotePropertyValue @() -Force
        }

        foreach ($distro in $Distros) {
            if ($distro -notin $settings.integratedWslDistros) {
                $settings.integratedWslDistros += $distro
            }
        }

        Save-DockerDesktopSettings $settings

        Write-Status "WSL 2 backend: Enabled" -Type success
        Write-Status "Integrated distros: $($Distros -join ', ')" -Type success

        Write-Host ""
        Write-Status "Restart Docker Desktop to apply changes" -Type warning

        return $true
    }
    catch {
        Write-Status "Configuration failed: $_" -Type error
        return $false
    }
}

function Set-DockerResourceLimits {
    param(
        [int]$Memory,
        [int]$Processors
    )

    Write-Status "Configuring Docker resource limits..." -Type pending

    $wslConfigPath = Get-WSLConfigPath
    $config = @{}

    # Read existing config
    if (Test-Path $wslConfigPath) {
        $content = Get-Content $wslConfigPath -Raw
        $currentSection = $null

        foreach ($line in ($content -split "`r?`n")) {
            if ($line -match '^\[(.+)\]$') {
                $currentSection = $Matches[1]
                if (-not $config.ContainsKey($currentSection)) {
                    $config[$currentSection] = @{}
                }
            }
            elseif ($currentSection -and $line -match '^([^=]+)=(.*)$') {
                $config[$currentSection][$Matches[1].Trim()] = $Matches[2].Trim()
            }
        }
    }

    # Ensure wsl2 section exists
    if (-not $config.ContainsKey('wsl2')) {
        $config['wsl2'] = @{}
    }

    # Set Docker-friendly limits
    $config['wsl2']['memory'] = "${Memory}GB"
    $config['wsl2']['processors'] = $Processors

    # Docker-specific optimizations
    $config['wsl2']['swap'] = "$([math]::Max(1, $Memory / 2))GB"
    $config['wsl2']['localhostForwarding'] = 'true'

    # Build config content
    $lines = @()
    $lines += "# WSL Configuration for Docker - Generated $(Get-Date -Format 'yyyy-MM-dd')"
    $lines += ""

    foreach ($section in $config.Keys | Sort-Object) {
        $lines += "[$section]"
        foreach ($key in $config[$section].Keys | Sort-Object) {
            $lines += "$key=$($config[$section][$key])"
        }
        $lines += ""
    }

    $configContent = $lines -join "`n"
    $configContent | Set-Content $wslConfigPath -Encoding UTF8

    Write-Status "Memory limit: ${Memory}GB" -Type success
    Write-Status "CPU limit: $Processors cores" -Type success
    Write-Status "Swap: $([math]::Max(1, $Memory / 2))GB" -Type success

    Write-Host ""
    Write-Status "Run 'wsl --shutdown' to apply changes" -Type warning

    return $true
}

function Install-DockerCLIInWSL {
    param([string]$DistroName)

    Write-Status "Configuring Docker CLI in $DistroName..." -Type pending

    # Check if docker command works (via Docker Desktop integration)
    $testCmd = 'command -v docker'
    $result = wsl.exe -d $DistroName -- bash -c $testCmd 2>&1

    if ($LASTEXITCODE -eq 0 -and $result) {
        Write-Status "Docker CLI available via Docker Desktop integration" -Type success

        # Add user to docker group if needed
        $groupCmd = 'getent group docker > /dev/null && sudo usermod -aG docker $USER 2>/dev/null || true'
        wsl.exe -d $DistroName -- bash -c $groupCmd 2>&1 | Out-Null

        return $true
    }

    # Docker Desktop not integrated, show instructions
    Write-Status "Docker CLI not available in WSL" -Type warning
    Write-Host ""
    Write-Host "  Enable Docker Desktop WSL integration:" -ForegroundColor $Script:Colors.Muted
    Write-Host "    1. Open Docker Desktop Settings" -ForegroundColor $Script:Colors.Muted
    Write-Host "    2. Go to Resources > WSL Integration" -ForegroundColor $Script:Colors.Muted
    Write-Host "    3. Enable integration for $DistroName" -ForegroundColor $Script:Colors.Muted

    return $false
}

# =============================================================================
# Status Display
# =============================================================================

function Show-DockerWSLStatus {
    Write-Host ""
    Write-Host "  Docker Desktop:" -ForegroundColor $Script:Colors.Highlight

    if (Test-DockerDesktopInstalled) {
        Write-Status "Installed" -Type success

        if (Test-DockerRunning) {
            Write-Status "Running" -Type success

            # Get Docker version
            $version = docker version --format '{{.Server.Version}}' 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Status "Version: $version" -Type info
            }
        }
        else {
            Write-Status "Not running" -Type warning
        }

        # Check settings
        $settings = Get-DockerDesktopSettings
        if ($settings) {
            $wslEnabled = $settings.wslEngineEnabled -eq $true
            Write-Status "WSL 2 backend: $(if ($wslEnabled) { 'Enabled' } else { 'Disabled' })" -Type $(if ($wslEnabled) { 'success' } else { 'warning' })

            if ($settings.integratedWslDistros) {
                Write-Status "Integrated distros: $($settings.integratedWslDistros -join ', ')" -Type info
            }
        }
    }
    else {
        Write-Status "Not installed" -Type warning
    }

    # WSL status
    Write-Host ""
    Write-Host "  WSL Distros:" -ForegroundColor $Script:Colors.Highlight

    $distros = Get-InstalledWSLDistros
    if ($distros.Count -eq 0) {
        Write-Status "No WSL distributions found" -Type warning
    }
    else {
        foreach ($distro in $distros) {
            # Check if docker works in this distro
            $dockerWorks = wsl.exe -d $distro -- command -v docker 2>&1
            if ($LASTEXITCODE -eq 0 -and $dockerWorks) {
                Write-Status "$distro`: Docker available" -Type success
            }
            else {
                Write-Status "$distro`: Docker not configured" -Type warning
            }
        }
    }

    # Resource config
    Write-Host ""
    Write-Host "  Resource Configuration:" -ForegroundColor $Script:Colors.Highlight

    $wslConfigPath = Get-WSLConfigPath
    if (Test-Path $wslConfigPath) {
        $config = Get-Content $wslConfigPath -Raw

        if ($config -match 'memory=(\S+)') {
            Write-Status "Memory limit: $($Matches[1])" -Type info
        }
        if ($config -match 'processors=(\d+)') {
            Write-Status "CPU limit: $($Matches[1]) cores" -Type info
        }
    }
    else {
        Write-Status "Using WSL defaults (no .wslconfig)" -Type info
    }
}

# =============================================================================
# Main
# =============================================================================

Write-Banner "Docker Desktop WSL Integration"

# Status mode
if ($ShowStatus) {
    Show-DockerWSLStatus
    exit 0
}

$changes = @()

# Install Docker Desktop
if ($Install) {
    Write-Host ""
    if (Install-DockerDesktop) {
        $changes += "Installed Docker Desktop"
    }
}

# Enable WSL integration
if ($EnableWSLIntegration) {
    Write-Host ""

    $distros = if ($Distro) { @($Distro) } else { Get-InstalledWSLDistros }

    if ($distros.Count -eq 0) {
        Write-Status "No WSL distributions found" -Type warning
    }
    else {
        if (Enable-DockerWSLIntegration -Distros $distros) {
            $changes += "Enabled WSL integration"
        }

        # Configure Docker CLI in each distro
        foreach ($d in $distros) {
            Install-DockerCLIInWSL -DistroName $d
        }
    }
}

# Configure resources
if ($ConfigureResources) {
    Write-Host ""
    if (Set-DockerResourceLimits -Memory $MemoryGB -Processors $CPUs) {
        $changes += "Configured resource limits"
    }
}

# Summary
if ($changes.Count -gt 0) {
    Write-Host ""
    Write-Status "Configuration complete" -Type success
}
elseif (-not $ShowStatus) {
    Write-Host ""
    Write-Status "No changes specified" -Type info
    Write-Host ""
    Write-Host "  Options:" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -Install               Install Docker Desktop" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -EnableWSLIntegration  Enable Docker in WSL distros" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -ConfigureResources    Set resource limits" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -ShowStatus            Show current status" -ForegroundColor $Script:Colors.Muted
}

