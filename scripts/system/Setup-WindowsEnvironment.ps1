#!/usr/bin/env pwsh
#Requires -Version 5.1

<#
.SYNOPSIS
    Interactive Windows Environment Setup Wizard
.DESCRIPTION
    User-friendly wizard to set up a complete Windows development environment including:
    - WSL2 (Windows Subsystem for Linux)
    - Windows Terminal
    - Package managers (winget, Chocolatey, Scoop)
    - Essential development tools
    - RSR (Remote Script Runner) integration
.PARAMETER Component
    Specific component to install: wsl, terminal, tools, all
.PARAMETER Preset
    Developer preset: webdev, devops, datascience
.PARAMETER SkipRestart
    Skip automatic restart prompts
.PARAMETER Force
    Bypass all confirmation prompts
.EXAMPLE
    .\Setup-WindowsEnvironment.ps1
.EXAMPLE
    .\Setup-WindowsEnvironment.ps1 -Component wsl
.EXAMPLE
    .\Setup-WindowsEnvironment.ps1 -Preset devops
#>

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(ParameterSetName = 'Component')]
    [ValidateSet('wsl', 'terminal', 'tools', 'packages', 'all')]
    [string]$Component,

    [Parameter(ParameterSetName = 'Preset')]
    [ValidateSet('webdev', 'devops', 'datascience', 'minimal')]
    [string]$Preset,

    [switch]$SkipRestart,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = $PSScriptRoot

# =============================================================================
# Module Import
# =============================================================================

$RSRModulePath = Join-Path (Split-Path -Parent (Split-Path -Parent $ScriptRoot)) "lib\powershell"
if (Test-Path (Join-Path $RSRModulePath "RSR.psd1")) {
    Import-Module (Join-Path $RSRModulePath "RSR.psd1") -Force -ErrorAction SilentlyContinue
}

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

function Test-IsWindows11 {
    $os = Get-CimInstance Win32_OperatingSystem
    return [int]$os.BuildNumber -ge 22000
}

function Get-WindowsVersion {
    $os = Get-CimInstance Win32_OperatingSystem
    return @{
        Version = $os.Version
        Build   = $os.BuildNumber
        Name    = $os.Caption
        Is11    = [int]$os.BuildNumber -ge 22000
    }
}

function Test-WSLInstalled {
    try {
        $wslPath = Get-Command wsl.exe -ErrorAction SilentlyContinue
        if (-not $wslPath) { return $false }
        $output = wsl.exe --status 2>&1
        return $LASTEXITCODE -eq 0 -or $output -match 'Default Distribution'
    }
    catch {
        return $false
    }
}

function Get-WSLDistros {
    try {
        $output = wsl.exe --list --quiet 2>&1
        if ($LASTEXITCODE -ne 0) { return @() }
        return $output | Where-Object { $_ -and $_ -notmatch 'Windows Subsystem' } | ForEach-Object { $_.Trim() }
    }
    catch {
        return @()
    }
}

function Test-WingetInstalled {
    return $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
}

function Test-ChocoInstalled {
    return $null -ne (Get-Command choco -ErrorAction SilentlyContinue)
}

function Test-ScoopInstalled {
    return $null -ne (Get-Command scoop -ErrorAction SilentlyContinue)
}

# =============================================================================
# Installation Functions
# =============================================================================

function Install-Winget {
    Write-Section "Installing winget"

    if (Test-WingetInstalled) {
        Write-Step "winget already installed" -Status success
        return $true
    }

    Write-Step "Installing winget..." -Status running

    try {
        # For Windows 11/10 with App Installer
        $progressPref = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'

        # Try to get from Microsoft Store via Add-AppxPackage
        $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        $msixBundle = $releases.assets | Where-Object { $_.name -match '\.msixbundle$' } | Select-Object -First 1

        if ($msixBundle) {
            $downloadPath = Join-Path $env:TEMP "Microsoft.DesktopAppInstaller.msixbundle"
            Invoke-WebRequest -Uri $msixBundle.browser_download_url -OutFile $downloadPath
            Add-AppxPackage -Path $downloadPath -ErrorAction Stop
            Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
        }

        $ProgressPreference = $progressPref

        if (Test-WingetInstalled) {
            Write-Step "winget installed successfully" -Status success
            return $true
        }
        else {
            Write-Step "winget installation may require restart" -Status warning
            return $false
        }
    }
    catch {
        Write-Step ("Failed to install winget: " + $_.Exception.Message) -Status error
        Write-Info "Try installing 'App Installer' from Microsoft Store"
        return $false
    }
}

function Install-Chocolatey {
    Write-Section "Installing Chocolatey"

    if (Test-ChocoInstalled) {
        Write-Step "Chocolatey already installed" -Status success
        return $true
    }

    if (-not (Test-IsAdmin)) {
        Write-Step "Chocolatey requires Administrator privileges" -Status warning
        return $false
    }

    Write-Step "Installing Chocolatey..." -Status running

    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

        if (Test-ChocoInstalled) {
            Write-Step "Chocolatey installed successfully" -Status success
            return $true
        }
    }
    catch {
        Write-Step ("Failed to install Chocolatey: " + $_.Exception.Message) -Status error
    }
    return $false
}

function Install-Scoop {
    Write-Section "Installing Scoop"

    if (Test-ScoopInstalled) {
        Write-Step "Scoop already installed" -Status success
        return $true
    }

    Write-Step "Installing Scoop..." -Status running

    try {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression

        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

        if (Test-ScoopInstalled) {
            Write-Step "Scoop installed successfully" -Status success
            # Add common buckets
            scoop bucket add extras 2>&1 | Out-Null
            scoop bucket add versions 2>&1 | Out-Null
            return $true
        }
    }
    catch {
        Write-Step ("Failed to install Scoop: " + $_.Exception.Message) -Status error
    }
    return $false
}

function Install-WindowsTerminal {
    Write-Section "Installing Windows Terminal"

    # Check if already installed
    $terminal = Get-AppxPackage -Name Microsoft.WindowsTerminal -ErrorAction SilentlyContinue
    if ($terminal) {
        Write-Step "Windows Terminal already installed" -Status success
        return $true
    }

    Write-Step "Installing Windows Terminal..." -Status running

    try {
        if (Test-WingetInstalled) {
            winget install --id Microsoft.WindowsTerminal --accept-source-agreements --accept-package-agreements -e 2>&1 | Out-Null
        }
        elseif (Test-ChocoInstalled) {
            choco install microsoft-windows-terminal -y 2>&1 | Out-Null
        }
        else {
            # Direct download
            $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/terminal/releases/latest"
            $msixBundle = $releases.assets | Where-Object { $_.name -match '\.msixbundle$' -and $_.name -notmatch 'Preview' } | Select-Object -First 1
            if ($msixBundle) {
                $downloadPath = Join-Path $env:TEMP "WindowsTerminal.msixbundle"
                Invoke-WebRequest -Uri $msixBundle.browser_download_url -OutFile $downloadPath
                Add-AppxPackage -Path $downloadPath
                Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
            }
        }

        $terminal = Get-AppxPackage -Name Microsoft.WindowsTerminal -ErrorAction SilentlyContinue
        if ($terminal) {
            Write-Step "Windows Terminal installed successfully" -Status success
            return $true
        }
    }
    catch {
        Write-Step ("Failed to install Windows Terminal: " + $_.Exception.Message) -Status error
    }
    return $false
}

function Install-EssentialTools {
    Write-Section "Installing Essential Development Tools"

    $tools = @(
        @{ Name = 'Git'; Winget = 'Git.Git'; Choco = 'git'; Scoop = 'git' }
        @{ Name = 'Visual Studio Code'; Winget = 'Microsoft.VisualStudioCode'; Choco = 'vscode'; Scoop = 'vscode' }
        @{ Name = 'PowerShell 7'; Winget = 'Microsoft.PowerShell'; Choco = 'powershell-core'; Scoop = 'pwsh' }
    )

    $installed = @()
    $failed = @()

    foreach ($tool in $tools) {
        Write-Step "Installing $($tool.Name)..." -Status running

        try {
            $success = $false

            if (Test-WingetInstalled) {
                $result = winget install --id $tool.Winget --accept-source-agreements --accept-package-agreements -e 2>&1
                $success = $LASTEXITCODE -eq 0 -or $result -match 'already installed'
            }

            if (-not $success -and (Test-ChocoInstalled)) {
                choco install $tool.Choco -y 2>&1 | Out-Null
                $success = $LASTEXITCODE -eq 0
            }

            if (-not $success -and (Test-ScoopInstalled)) {
                scoop install $tool.Scoop 2>&1 | Out-Null
                $success = $LASTEXITCODE -eq 0
            }

            if ($success) {
                Write-Step "$($tool.Name) installed" -Status success
                $installed += $tool.Name
            }
            else {
                Write-Step "$($tool.Name) installation failed" -Status warning
                $failed += $tool.Name
            }
        }
        catch {
            Write-Step ("$($tool.Name) error: " + $_.Exception.Message) -Status error
            $failed += $tool.Name
        }
    }

    Write-Host ""
    Write-Info "Installed: $($installed.Count)/$($tools.Count) tools"

    return $installed.Count -gt 0
}

function Install-RSRInWSL {
    param([string]$Distro = "Ubuntu")

    Write-Section "Installing RSR in WSL ($Distro)"

    $distros = Get-WSLDistros
    if ($Distro -notin $distros) {
        Write-Step "Distro '$Distro' not found" -Status warning
        return $false
    }

    Write-Step "Installing RSR in $Distro..." -Status running

    try {
        # Install RSR using the one-liner
        $installCmd = 'curl -fsSL https://scripts.pandia.io/install.sh | bash'
        wsl.exe -d $Distro -- bash -c $installCmd 2>&1 | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Step "RSR installed in WSL" -Status success
            return $true
        }
    }
    catch {
        Write-Step ("Failed to install RSR in WSL: " + $_.Exception.Message) -Status error
    }
    return $false
}

# =============================================================================
# Preset Configurations
# =============================================================================

function Get-PresetConfig {
    param([string]$PresetName)

    $presets = @{
        minimal = @{
            Name        = "Minimal"
            Description = "Essential tools only"
            Windows     = @('git', 'vscode')
            WSL         = @('git', 'curl', 'wget')
        }
        webdev = @{
            Name        = "Web Development"
            Description = "Full web development stack"
            Windows     = @('git', 'vscode', 'nodejs-lts', 'docker-desktop')
            WSL         = @('git', 'curl', 'wget', 'nodejs', 'npm', 'build-essential')
        }
        devops = @{
            Name        = "DevOps / Cloud"
            Description = "Infrastructure and cloud tools"
            Windows     = @('git', 'vscode', 'docker-desktop', 'azure-cli', 'terraform')
            WSL         = @('git', 'curl', 'wget', 'docker.io', 'ansible', 'terraform')
        }
        datascience = @{
            Name        = "Data Science"
            Description = "Python and data tools"
            Windows     = @('git', 'vscode', 'python3', 'anaconda3')
            WSL         = @('git', 'curl', 'wget', 'python3', 'python3-pip', 'python3-venv')
        }
    }

    return $presets[$PresetName]
}

# =============================================================================
# Environment Check
# =============================================================================

function Show-EnvironmentStatus {
    Write-Section "Current Environment"

    $winVer = Get-WindowsVersion
    Write-Host "  OS: $($winVer.Name)" -ForegroundColor $Script:Colors.Info
    Write-Host "  Build: $($winVer.Build)" -ForegroundColor $Script:Colors.Muted
    Write-Host ""

    # Admin status
    if (Test-IsAdmin) {
        Write-Step "Running as Administrator" -Status success
    }
    else {
        Write-Step "Not running as Administrator (some features limited)" -Status warning
    }

    # WSL
    if (Test-WSLInstalled) {
        $distros = Get-WSLDistros
        Write-Step "WSL installed ($($distros.Count) distro(s))" -Status success
        foreach ($d in $distros) {
            Write-Info "  └─ $d"
        }
    }
    else {
        Write-Step "WSL not installed" -Status pending
    }

    # Package Managers
    if (Test-WingetInstalled) { Write-Step "winget available" -Status success }
    else { Write-Step "winget not installed" -Status pending }

    if (Test-ChocoInstalled) { Write-Step "Chocolatey available" -Status success }
    else { Write-Step "Chocolatey not installed" -Status pending }

    if (Test-ScoopInstalled) { Write-Step "Scoop available" -Status success }
    else { Write-Step "Scoop not installed" -Status pending }

    # Windows Terminal
    $terminal = Get-AppxPackage -Name Microsoft.WindowsTerminal -ErrorAction SilentlyContinue
    if ($terminal) { Write-Step "Windows Terminal installed" -Status success }
    else { Write-Step "Windows Terminal not installed" -Status pending }

    Write-Host ""
}

# =============================================================================
# Interactive Wizard
# =============================================================================

function Start-InteractiveWizard {
    Clear-Host
    Write-Banner "Windows Development Environment Setup"

    Show-EnvironmentStatus

    $mainOptions = @(
        "🚀 Quick Setup (WSL + Terminal + Tools)"
        "🐧 Install WSL2 only"
        "📦 Install Package Managers"
        "🛠️  Install Development Tools"
        "🎯 Developer Preset (Web/DevOps/Data)"
        "⚙️  Configure Tools (Git, Terminal, VS Code, Docker)"
        "📊 Check Environment Status"
        "❌ Exit"
    )

    $choice = Show-Menu -Title "What would you like to do?" -Options $mainOptions -Default 0

    switch ($choice) {
        0 {
            # Quick Setup
            Write-Banner "Quick Setup"

            if (-not (Test-IsAdmin)) {
                Write-Warn "Some components require Administrator privileges"
                Write-Info "Consider restarting PowerShell as Administrator"
                Write-Host ""
            }

            # WSL
            if (-not (Test-WSLInstalled)) {
                if (Confirm-Action "Install WSL2 with Ubuntu?") {
                    & (Join-Path $ScriptRoot "Install-WSL.ps1") -Distro "Ubuntu" -SkipRestart:$SkipRestart -Force:$Force
                }
            }
            else {
                Write-Step "WSL already installed" -Status skip
            }

            # Package Managers
            Install-Winget | Out-Null
            if (Test-IsAdmin) {
                Install-Chocolatey | Out-Null
            }
            Install-Scoop | Out-Null

            # Windows Terminal
            Install-WindowsTerminal | Out-Null

            # Essential Tools
            Install-EssentialTools | Out-Null

            # RSR in WSL
            $distros = Get-WSLDistros
            if ($distros.Count -gt 0) {
                if (Confirm-Action "Install RSR in WSL ($($distros[0]))?") {
                    Install-RSRInWSL -Distro $distros[0]
                }
            }

            # Additional configuration
            if (Confirm-Action "Configure Windows Terminal profiles?") {
                $terminalScript = Join-Path $ScriptRoot "terminal\Configure-WindowsTerminal.ps1"
                if (Test-Path $terminalScript) {
                    & $terminalScript -ConfigureWSLProfiles
                }
            }

            if (Confirm-Action "Configure Git credentials for Windows/WSL?") {
                $gitScript = Join-Path $ScriptRoot "git\Configure-GitCredentials.ps1"
                if (Test-Path $gitScript) {
                    & $gitScript -ConfigureWindows -ConfigureWSL -SetGlobalConfig
                }
            }

            Write-Banner "Setup Complete!"
            Show-EnvironmentStatus
        }
        1 {
            # WSL Only
            & (Join-Path $ScriptRoot "Install-WSL.ps1") -SkipRestart:$SkipRestart -Force:$Force
        }
        2 {
            # Package Managers
            Write-Banner "Package Manager Setup"

            if (Confirm-Action "Install winget?") { Install-Winget }
            if (Confirm-Action "Install Chocolatey?") { Install-Chocolatey }
            if (Confirm-Action "Install Scoop?") { Install-Scoop }
        }
        3 {
            # Dev Tools
            Install-WindowsTerminal
            Install-EssentialTools
        }
        4 {
            # Presets
            $presetOptions = @(
                "🌐 Web Development (Node.js, Docker)"
                "☁️  DevOps / Cloud (Terraform, Ansible, Azure)"
                "📊 Data Science (Python, Anaconda)"
                "📦 Minimal (Git, VSCode)"
            )
            $presetChoice = Show-Menu -Title "Select a developer preset:" -Options $presetOptions -Default 0
            $presetNames = @('webdev', 'devops', 'datascience', 'minimal')
            $selectedPreset = $presetNames[$presetChoice]

            $config = Get-PresetConfig $selectedPreset
            Write-Banner "$($config.Name) Preset"
            Write-Info $config.Description
            Write-Host ""
            Write-Info "Windows packages: $($config.Windows -join ', ')"
            Write-Info "WSL packages: $($config.WSL -join ', ')"
            Write-Host ""

            if (Confirm-Action "Proceed with this preset?") {
                # Install Windows tools
                foreach ($pkg in $config.Windows) {
                    Write-Step "Installing $pkg..." -Status running
                    if (Test-WingetInstalled) {
                        winget install $pkg --accept-source-agreements --accept-package-agreements -e 2>&1 | Out-Null
                    }
                }

                # Install WSL tools
                $distros = Get-WSLDistros
                if ($distros.Count -gt 0) {
                    $pkgList = $config.WSL -join ' '
                    wsl.exe -d $distros[0] -- sudo apt update 2>&1 | Out-Null
                    wsl.exe -d $distros[0] -- sudo apt install -y $pkgList 2>&1 | Out-Null
                }

                Write-Success "Preset installation complete!"
            }
        }
        5 {
            # Configure Tools
            Write-Banner "Tool Configuration"

            $configOptions = @(
                "🔧 Configure Windows Terminal"
                "🔑 Configure Git Credentials"
                "💻 Configure VS Code for WSL"
                "🐳 Configure Docker WSL Integration"
                "📋 Configure All"
                "← Back"
            )

            $configChoice = Show-Menu -Title "Select configuration:" -Options $configOptions -Default 4

            switch ($configChoice) {
                0 {
                    $script = Join-Path $ScriptRoot "terminal\Configure-WindowsTerminal.ps1"
                    if (Test-Path $script) {
                        & $script -ConfigureWSLProfiles -ColorScheme "One Half Dark"
                    } else {
                        Write-Warn "Terminal configuration script not found"
                    }
                }
                1 {
                    $script = Join-Path $ScriptRoot "git\Configure-GitCredentials.ps1"
                    if (Test-Path $script) {
                        & $script -ConfigureWindows -ConfigureWSL -SetGlobalConfig
                    } else {
                        Write-Warn "Git configuration script not found"
                    }
                }
                2 {
                    $script = Join-Path $ScriptRoot "vscode\Configure-VSCodeWSL.ps1"
                    if (Test-Path $script) {
                        & $script -InstallWSLExtension -ConfigureSettings
                    } else {
                        Write-Warn "VS Code configuration script not found"
                    }
                }
                3 {
                    $script = Join-Path $ScriptRoot "docker\Configure-DockerWSL.ps1"
                    if (Test-Path $script) {
                        & $script -EnableWSLIntegration -ConfigureResources
                    } else {
                        Write-Warn "Docker configuration script not found"
                    }
                }
                4 {
                    # Configure All
                    $scripts = @(
                        @{ Path = "terminal\Configure-WindowsTerminal.ps1"; Args = @{ ConfigureWSLProfiles = $true } }
                        @{ Path = "git\Configure-GitCredentials.ps1"; Args = @{ ConfigureWindows = $true; ConfigureWSL = $true; SetGlobalConfig = $true } }
                        @{ Path = "vscode\Configure-VSCodeWSL.ps1"; Args = @{ InstallWSLExtension = $true; ConfigureSettings = $true } }
                    )

                    foreach ($s in $scripts) {
                        $scriptPath = Join-Path $ScriptRoot $s.Path
                        if (Test-Path $scriptPath) {
                            & $scriptPath @($s.Args)
                        }
                    }

                    Write-Success "All tools configured!"
                }
                5 {
                    # Back - do nothing, will return to main menu
                }
            }
        }
        6 {
            # Status only
            Show-EnvironmentStatus
        }
        7 {
            # Exit
            Write-Host "  Goodbye! 👋" -ForegroundColor $Script:Colors.Muted
            return
        }
    }

    Write-Host ""
    if (Confirm-Action "Return to main menu?") {
        Start-InteractiveWizard
    }
}

# =============================================================================
# Main Entry Point
# =============================================================================

try {
    switch ($PSCmdlet.ParameterSetName) {
        'Component' {
            switch ($Component) {
                'wsl' {
                    & (Join-Path $ScriptRoot "Install-WSL.ps1") -SkipRestart:$SkipRestart -Force:$Force
                }
                'terminal' {
                    Install-WindowsTerminal
                }
                'tools' {
                    Install-EssentialTools
                }
                'packages' {
                    Install-Winget
                    if (Test-IsAdmin) { Install-Chocolatey }
                    Install-Scoop
                }
                'all' {
                    & (Join-Path $ScriptRoot "Install-WSL.ps1") -SkipRestart:$SkipRestart -Force:$Force
                    Install-Winget
                    if (Test-IsAdmin) { Install-Chocolatey }
                    Install-Scoop
                    Install-WindowsTerminal
                    Install-EssentialTools
                }
            }
        }
        'Preset' {
            $config = Get-PresetConfig $Preset
            if ($config) {
                Write-Banner "$($config.Name) Preset"
                # Implementation similar to interactive preset
            }
        }
        default {
            Start-InteractiveWizard
        }
    }
}
catch {
    Write-Err ("An error occurred: " + $_.Exception.Message)
    exit 1
}

