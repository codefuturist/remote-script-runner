#!/usr/bin/env pwsh
#Requires -Version 5.1

<#
.SYNOPSIS
    Configure Git Credential Manager for Windows and WSL integration
.DESCRIPTION
    Sets up Git Credential Manager (GCM) for seamless authentication:
    - Installs GCM if not present
    - Configures Windows Git with GCM
    - Configures WSL to use Windows GCM (single sign-on)
    - Sets up recommended Git configuration
.PARAMETER Install
    Install Git Credential Manager
.PARAMETER ConfigureWindows
    Configure Git on Windows to use GCM
.PARAMETER ConfigureWSL
    Configure Git in WSL to use Windows GCM
.PARAMETER Distro
    WSL distribution to configure (default: all installed)
.PARAMETER SetGlobalConfig
    Apply recommended global Git configuration
.PARAMETER ShowConfig
    Display current Git credential configuration
.EXAMPLE
    .\Configure-GitCredentials.ps1 -Install -ConfigureWindows
.EXAMPLE
    .\Configure-GitCredentials.ps1 -ConfigureWSL -Distro Ubuntu
.EXAMPLE
    .\Configure-GitCredentials.ps1 -SetGlobalConfig
#>

[CmdletBinding(DefaultParameterSetName = 'Configure')]
param(
    [switch]$Install,

    [switch]$ConfigureWindows,

    [switch]$ConfigureWSL,

    [string]$Distro,

    [switch]$SetGlobalConfig,

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
# Detection Functions
# =============================================================================

function Test-GitInstalled {
    return $null -ne (Get-Command git.exe -ErrorAction SilentlyContinue)
}

function Test-GCMInstalled {
    # Check for GCM in common locations
    $gcmPaths = @(
        "$env:ProgramFiles\Git\mingw64\bin\git-credential-manager.exe"
        "$env:ProgramFiles\Git\mingw64\libexec\git-core\git-credential-manager.exe"
        "$env:LOCALAPPDATA\Programs\Git\mingw64\bin\git-credential-manager.exe"
    )

    foreach ($path in $gcmPaths) {
        if (Test-Path $path) { return $true }
    }

    # Check if it's in PATH
    $gcm = Get-Command git-credential-manager -ErrorAction SilentlyContinue
    return $null -ne $gcm
}

function Get-GCMPath {
    # Find GCM executable path for WSL configuration
    $gcmPaths = @(
        "$env:ProgramFiles\Git\mingw64\bin\git-credential-manager.exe"
        "$env:ProgramFiles\Git\mingw64\libexec\git-core\git-credential-manager.exe"
        "$env:LOCALAPPDATA\Programs\Git\mingw64\bin\git-credential-manager.exe"
        (Get-Command git-credential-manager -ErrorAction SilentlyContinue).Source
    ) | Where-Object { $_ -and (Test-Path $_) }

    return $gcmPaths | Select-Object -First 1
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

function ConvertTo-WSLPath {
    param([string]$WindowsPath)

    # Convert Windows path to WSL path
    # C:\Program Files\Git -> /mnt/c/Program Files/Git
    $wslPath = $WindowsPath -replace '\\', '/'
    $wslPath = $wslPath -replace '^([A-Za-z]):', '/mnt/$1'
    $wslPath = $wslPath.ToLower() -replace '/mnt/([a-z])', '/mnt/$1'

    # Escape spaces for shell
    $wslPath = $wslPath -replace ' ', '\ '

    return $wslPath
}

# =============================================================================
# Installation
# =============================================================================

function Install-GitCredentialManager {
    Write-Status "Installing Git Credential Manager..." -Type pending

    # GCM is now bundled with Git for Windows
    # Check if Git is installed with GCM
    if (Test-GCMInstalled) {
        Write-Status "GCM already installed (bundled with Git)" -Type success
        return $true
    }

    # Try to install via winget
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Status "Installing via winget..." -Type pending

        $result = winget install --id Git.Git --accept-source-agreements --accept-package-agreements -e 2>&1

        if ($LASTEXITCODE -eq 0 -or $result -match 'already installed') {
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

            Write-Status "Git with GCM installed" -Type success
            return $true
        }
    }

    # Try Chocolatey
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Status "Installing via Chocolatey..." -Type pending
        choco install git -y 2>&1 | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Status "Git with GCM installed" -Type success
            return $true
        }
    }

    Write-Status "Please install Git for Windows manually" -Type error
    Write-Host "  https://git-scm.com/download/win" -ForegroundColor $Script:Colors.Muted
    return $false
}

# =============================================================================
# Configuration
# =============================================================================

function Set-WindowsGitCredentials {
    Write-Status "Configuring Windows Git..." -Type pending

    if (-not (Test-GitInstalled)) {
        Write-Status "Git is not installed" -Type error
        return $false
    }

    try {
        # Set credential helper to GCM
        git config --global credential.helper manager
        Write-Status "Credential helper: manager" -Type success

        # Enable credential caching
        git config --global credential.useHttpPath true
        Write-Status "Use HTTP path: enabled" -Type success

        # Configure for common hosts
        git config --global credential.https://github.com.provider github
        git config --global credential.https://gitlab.com.provider gitlab
        git config --global credential.https://dev.azure.com.provider azure-repos
        Write-Status "Configured providers for GitHub, GitLab, Azure DevOps" -Type success

        return $true
    }
    catch {
        Write-Status "Configuration failed: $_" -Type error
        return $false
    }
}

function Set-WSLGitCredentials {
    param([string]$DistroName)

    Write-Status "Configuring WSL ($DistroName)..." -Type pending

    $gcmPath = Get-GCMPath
    if (-not $gcmPath) {
        Write-Status "GCM not found on Windows" -Type error
        return $false
    }

    # Convert to WSL path
    $wslGcmPath = ConvertTo-WSLPath $gcmPath

    try {
        # Set credential helper to Windows GCM
        # The path needs to be properly escaped
        $configCmd = "git config --global credential.helper '$wslGcmPath'"
        wsl.exe -d $DistroName -- bash -c $configCmd 2>&1 | Out-Null

        if ($LASTEXITCODE -ne 0) {
            # Try alternative approach - using the helper script
            $helperCmd = @"
git config --global credential.helper "/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe"
"@
            wsl.exe -d $DistroName -- bash -c $helperCmd 2>&1 | Out-Null
        }

        Write-Status "Credential helper configured for WSL" -Type success

        # Also configure the core.autocrlf for cross-platform
        wsl.exe -d $DistroName -- git config --global core.autocrlf input 2>&1 | Out-Null
        Write-Status "Line endings: input (LF in repo)" -Type success

        return $true
    }
    catch {
        Write-Status "WSL configuration failed: $_" -Type error
        return $false
    }
}

function Set-RecommendedGitConfig {
    Write-Status "Applying recommended Git configuration..." -Type pending

    if (-not (Test-GitInstalled)) {
        Write-Status "Git is not installed" -Type error
        return $false
    }

    try {
        # Core settings
        git config --global init.defaultBranch main
        git config --global core.autocrlf true  # Windows: convert LF to CRLF on checkout
        git config --global core.safecrlf warn
        git config --global core.editor "code --wait"

        # Better diff/merge
        git config --global diff.colorMoved zebra
        git config --global merge.conflictstyle diff3

        # Useful aliases
        git config --global alias.st status
        git config --global alias.co checkout
        git config --global alias.br branch
        git config --global alias.ci commit
        git config --global alias.lg "log --oneline --graph --decorate"
        git config --global alias.last "log -1 HEAD --stat"
        git config --global alias.unstage "reset HEAD --"

        # Push behavior
        git config --global push.default current
        git config --global push.autoSetupRemote true

        # Pull behavior
        git config --global pull.rebase false

        # Performance
        git config --global core.preloadindex true
        git config --global core.fscache true

        Write-Status "Applied recommended configuration" -Type success

        Write-Host ""
        Write-Host "  Configured:" -ForegroundColor $Script:Colors.Highlight
        Write-Host "    • Default branch: main" -ForegroundColor $Script:Colors.Muted
        Write-Host "    • Editor: VS Code" -ForegroundColor $Script:Colors.Muted
        Write-Host "    • Useful aliases (st, co, br, ci, lg)" -ForegroundColor $Script:Colors.Muted
        Write-Host "    • Performance optimizations" -ForegroundColor $Script:Colors.Muted

        return $true
    }
    catch {
        Write-Status "Configuration failed: $_" -Type error
        return $false
    }
}

# =============================================================================
# Display Functions
# =============================================================================

function Show-GitCredentialConfig {
    Write-Host ""
    Write-Host "  Windows Git Configuration:" -ForegroundColor $Script:Colors.Highlight

    if (Test-GitInstalled) {
        $helper = git config --global credential.helper 2>&1
        Write-Status "Credential helper: $(if ($helper) { $helper } else { '(not set)' })" -Type info

        $editor = git config --global core.editor 2>&1
        Write-Status "Editor: $(if ($editor) { $editor } else { '(not set)' })" -Type info

        $defaultBranch = git config --global init.defaultBranch 2>&1
        Write-Status "Default branch: $(if ($defaultBranch) { $defaultBranch } else { 'master' })" -Type info
    }
    else {
        Write-Status "Git is not installed" -Type warning
    }

    # WSL configuration
    $distros = Get-InstalledWSLDistros
    if ($distros.Count -gt 0) {
        Write-Host ""
        Write-Host "  WSL Git Configuration:" -ForegroundColor $Script:Colors.Highlight

        foreach ($distro in $distros) {
            $wslHelper = wsl.exe -d $distro -- git config --global credential.helper 2>&1
            if ($LASTEXITCODE -eq 0 -and $wslHelper) {
                Write-Status "$distro`: $wslHelper" -Type info
            }
            else {
                Write-Status "$distro`: (not configured)" -Type warning
            }
        }
    }
}

# =============================================================================
# Main
# =============================================================================

Write-Banner "Git Credential Manager Configuration"

# Show config mode
if ($ShowConfig) {
    Show-GitCredentialConfig
    exit 0
}

# Ensure Git is installed
if (-not (Test-GitInstalled) -and -not $Install) {
    Write-Host ""
    Write-Status "Git is not installed" -Type warning
    Write-Host ""
    Write-Host "  Use -Install to install Git with GCM" -ForegroundColor $Script:Colors.Muted
    exit 1
}

$changes = @()

# Install GCM
if ($Install) {
    Write-Host ""
    if (Install-GitCredentialManager) {
        $changes += "Installed GCM"
    }
}

# Configure Windows
if ($ConfigureWindows) {
    Write-Host ""
    if (Set-WindowsGitCredentials) {
        $changes += "Configured Windows Git"
    }
}

# Configure WSL
if ($ConfigureWSL) {
    Write-Host ""
    $distros = if ($Distro) { @($Distro) } else { Get-InstalledWSLDistros }

    if ($distros.Count -eq 0) {
        Write-Status "No WSL distributions found" -Type warning
    }
    else {
        foreach ($d in $distros) {
            if (Set-WSLGitCredentials $d) {
                $changes += "Configured WSL ($d)"
            }
        }
    }
}

# Apply recommended config
if ($SetGlobalConfig) {
    Write-Host ""
    if (Set-RecommendedGitConfig) {
        $changes += "Applied recommended config"
    }
}

# Summary
if ($changes.Count -gt 0) {
    Write-Host ""
    Write-Status "Configuration complete" -Type success
    Write-Host ""
    Write-Host "  Next steps:" -ForegroundColor $Script:Colors.Highlight
    Write-Host "    • Run 'git push' to authenticate with your Git host" -ForegroundColor $Script:Colors.Muted
    Write-Host "    • Credentials will be securely stored in Windows Credential Manager" -ForegroundColor $Script:Colors.Muted
}
elseif (-not $ShowConfig) {
    Write-Host ""
    Write-Status "No changes specified" -Type info
    Write-Host ""
    Write-Host "  Options:" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -Install            Install Git Credential Manager" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -ConfigureWindows   Configure Windows Git with GCM" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -ConfigureWSL       Configure WSL to use Windows GCM" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -SetGlobalConfig    Apply recommended Git settings" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -ShowConfig         Show current configuration" -ForegroundColor $Script:Colors.Muted
}

