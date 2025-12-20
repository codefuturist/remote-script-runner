#!/usr/bin/env pwsh
#Requires -Version 5.1

<#
.SYNOPSIS
    Configure VS Code for optimal WSL development experience
.DESCRIPTION
    Sets up VS Code with WSL Remote extension and recommended settings:
    - Installs VS Code WSL extension
    - Installs recommended extension packs for development
    - Configures VS Code settings for WSL
    - Sets up settings sync (optional)
.PARAMETER InstallExtension
    Install specific extension by ID
.PARAMETER InstallWSLExtension
    Install the WSL Remote extension
.PARAMETER InstallExtensionPack
    Install a curated extension pack (webdev, python, devops)
.PARAMETER ConfigureSettings
    Apply recommended VS Code settings for WSL development
.PARAMETER EnableSettingsSync
    Enable Settings Sync with Microsoft account
.PARAMETER ShowExtensions
    List installed extensions
.PARAMETER Distro
    Configure VS Code for specific WSL distro
.EXAMPLE
    .\Configure-VSCodeWSL.ps1 -InstallWSLExtension
.EXAMPLE
    .\Configure-VSCodeWSL.ps1 -InstallExtensionPack webdev
.EXAMPLE
    .\Configure-VSCodeWSL.ps1 -ConfigureSettings
#>

[CmdletBinding(DefaultParameterSetName = 'Configure')]
param(
    [Parameter(ParameterSetName = 'Extension')]
    [string]$InstallExtension,

    [Parameter(ParameterSetName = 'Configure')]
    [switch]$InstallWSLExtension,

    [Parameter(ParameterSetName = 'Pack')]
    [ValidateSet('webdev', 'python', 'devops', 'general')]
    [string]$InstallExtensionPack,

    [Parameter(ParameterSetName = 'Configure')]
    [switch]$ConfigureSettings,

    [switch]$EnableSettingsSync,

    [Parameter(ParameterSetName = 'Show')]
    [switch]$ShowExtensions,

    [string]$Distro
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

function Test-VSCodeInstalled {
    return $null -ne (Get-Command code -ErrorAction SilentlyContinue)
}

function Get-VSCodePath {
    $codePath = Get-Command code -ErrorAction SilentlyContinue
    if ($codePath) { return $codePath.Source }

    # Check common locations
    $paths = @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe"
        "$env:ProgramFiles\Microsoft VS Code\Code.exe"
        "$env:USERPROFILE\scoop\apps\vscode\current\Code.exe"
    )

    foreach ($path in $paths) {
        if (Test-Path $path) { return $path }
    }

    return $null
}

function Get-VSCodeSettingsPath {
    return "$env:APPDATA\Code\User\settings.json"
}

function Get-InstalledExtensions {
    $output = code --list-extensions 2>&1
    if ($LASTEXITCODE -eq 0) {
        return $output | Where-Object { $_ -and $_.Trim() }
    }
    return @()
}

function Test-ExtensionInstalled {
    param([string]$ExtensionId)

    $installed = Get-InstalledExtensions
    return $ExtensionId -in $installed
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

# =============================================================================
# Extension Management
# =============================================================================

function Install-VSCodeExtension {
    param(
        [string]$ExtensionId,
        [string]$DisplayName
    )

    if (-not $DisplayName) { $DisplayName = $ExtensionId }

    if (Test-ExtensionInstalled $ExtensionId) {
        Write-Status "$DisplayName already installed" -Type success
        return $true
    }

    Write-Status "Installing $DisplayName..." -Type pending

    $result = code --install-extension $ExtensionId --force 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Status "$DisplayName installed" -Type success
        return $true
    }
    else {
        Write-Status "Failed to install $DisplayName" -Type error
        return $false
    }
}

function Get-ExtensionPack {
    param([string]$PackName)

    $packs = @{
        general = @(
            @{ Id = 'ms-vscode-remote.remote-wsl'; Name = 'WSL Remote' }
            @{ Id = 'ms-vscode-remote.remote-ssh'; Name = 'SSH Remote' }
            @{ Id = 'ms-vscode-remote.remote-containers'; Name = 'Dev Containers' }
            @{ Id = 'EditorConfig.EditorConfig'; Name = 'EditorConfig' }
            @{ Id = 'eamodio.gitlens'; Name = 'GitLens' }
            @{ Id = 'GitHub.copilot'; Name = 'GitHub Copilot' }
            @{ Id = 'streetsidesoftware.code-spell-checker'; Name = 'Code Spell Checker' }
        )

        webdev = @(
            @{ Id = 'ms-vscode-remote.remote-wsl'; Name = 'WSL Remote' }
            @{ Id = 'dbaeumer.vscode-eslint'; Name = 'ESLint' }
            @{ Id = 'esbenp.prettier-vscode'; Name = 'Prettier' }
            @{ Id = 'bradlc.vscode-tailwindcss'; Name = 'Tailwind CSS' }
            @{ Id = 'ms-vscode.vscode-typescript-next'; Name = 'TypeScript Nightly' }
            @{ Id = 'ritwickdey.LiveServer'; Name = 'Live Server' }
            @{ Id = 'formulahendry.auto-rename-tag'; Name = 'Auto Rename Tag' }
            @{ Id = 'christian-kohler.path-intellisense'; Name = 'Path Intellisense' }
        )

        python = @(
            @{ Id = 'ms-vscode-remote.remote-wsl'; Name = 'WSL Remote' }
            @{ Id = 'ms-python.python'; Name = 'Python' }
            @{ Id = 'ms-python.vscode-pylance'; Name = 'Pylance' }
            @{ Id = 'ms-python.black-formatter'; Name = 'Black Formatter' }
            @{ Id = 'ms-python.isort'; Name = 'isort' }
            @{ Id = 'ms-toolsai.jupyter'; Name = 'Jupyter' }
            @{ Id = 'njpwerner.autodocstring'; Name = 'Python Docstring' }
        )

        devops = @(
            @{ Id = 'ms-vscode-remote.remote-wsl'; Name = 'WSL Remote' }
            @{ Id = 'ms-vscode-remote.remote-ssh'; Name = 'SSH Remote' }
            @{ Id = 'ms-vscode-remote.remote-containers'; Name = 'Dev Containers' }
            @{ Id = 'ms-azuretools.vscode-docker'; Name = 'Docker' }
            @{ Id = 'hashicorp.terraform'; Name = 'Terraform' }
            @{ Id = 'redhat.vscode-yaml'; Name = 'YAML' }
            @{ Id = 'ms-kubernetes-tools.vscode-kubernetes-tools'; Name = 'Kubernetes' }
            @{ Id = 'redhat.ansible'; Name = 'Ansible' }
        )
    }

    return $packs[$PackName]
}

# =============================================================================
# Settings Configuration
# =============================================================================

function Get-RecommendedSettings {
    return @{
        # WSL-specific settings
        "remote.WSL.fileWatcher.polling" = $false
        "remote.WSL.useShellEnvironment" = $true

        # Editor settings
        "editor.fontSize" = 14
        "editor.fontFamily" = "Cascadia Code NF, Cascadia Code, Consolas, monospace"
        "editor.fontLigatures" = $true
        "editor.formatOnSave" = $true
        "editor.formatOnPaste" = $true
        "editor.minimap.enabled" = $true
        "editor.wordWrap" = "on"
        "editor.tabSize" = 2
        "editor.insertSpaces" = $true
        "editor.bracketPairColorization.enabled" = $true
        "editor.guides.bracketPairs" = $true
        "editor.stickyScroll.enabled" = $true

        # Terminal settings
        "terminal.integrated.defaultProfile.windows" = "Ubuntu (WSL)"
        "terminal.integrated.fontFamily" = "Cascadia Code NF, Cascadia Mono, Consolas"
        "terminal.integrated.fontSize" = 13

        # File settings
        "files.autoSave" = "onFocusChange"
        "files.trimTrailingWhitespace" = $true
        "files.insertFinalNewline" = $true
        "files.eol" = "`n"  # LF for Linux compatibility

        # Git settings
        "git.autofetch" = $true
        "git.enableSmartCommit" = $true
        "git.confirmSync" = $false

        # Workbench
        "workbench.startupEditor" = "none"
        "workbench.colorTheme" = "One Dark Pro"

        # Telemetry
        "telemetry.telemetryLevel" = "off"
    }
}

function Set-VSCodeSettings {
    param([hashtable]$NewSettings)

    $settingsPath = Get-VSCodeSettingsPath
    $settings = @{}

    # Read existing settings
    if (Test-Path $settingsPath) {
        try {
            $content = Get-Content $settingsPath -Raw
            # Remove comments
            $content = $content -replace '//.*$', '' -replace '/\*[\s\S]*?\*/', ''
            $existing = $content | ConvertFrom-Json -AsHashtable
            if ($existing) { $settings = $existing }
        }
        catch {
            Write-Status "Could not parse existing settings, creating new" -Type warning
        }
    }

    # Merge new settings
    foreach ($key in $NewSettings.Keys) {
        $settings[$key] = $NewSettings[$key]
    }

    # Ensure directory exists
    $dir = Split-Path $settingsPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # Write settings
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8

    return $true
}

# =============================================================================
# WSL Integration
# =============================================================================

function Install-VSCodeInWSL {
    param([string]$DistroName)

    Write-Status "Configuring VS Code server in $DistroName..." -Type pending

    # The VS Code server is installed automatically when you connect
    # We just need to ensure the WSL extension is installed on Windows

    if (-not (Test-ExtensionInstalled 'ms-vscode-remote.remote-wsl')) {
        Install-VSCodeExtension -ExtensionId 'ms-vscode-remote.remote-wsl' -DisplayName 'WSL Remote'
    }

    # Verify code command works in WSL
    $testCmd = 'which code 2>/dev/null || echo "not found"'
    $result = wsl.exe -d $DistroName -- bash -c $testCmd 2>&1

    if ($result -match 'not found') {
        Write-Status "VS Code CLI not available in WSL yet" -Type info
        Write-Host "    Run 'code .' from WSL to install VS Code server" -ForegroundColor $Script:Colors.Muted
    }
    else {
        Write-Status "VS Code CLI available in WSL" -Type success
    }

    return $true
}

# =============================================================================
# Display Functions
# =============================================================================

function Show-InstalledExtensions {
    Write-Host ""
    Write-Host "  Installed Extensions:" -ForegroundColor $Script:Colors.Highlight
    Write-Host ""

    $extensions = Get-InstalledExtensions | Sort-Object

    # Categorize extensions
    $remote = $extensions | Where-Object { $_ -match 'remote|wsl|ssh|container' }
    $other = $extensions | Where-Object { $_ -notmatch 'remote|wsl|ssh|container' }

    Write-Host "  Remote Development:" -ForegroundColor $Script:Colors.Info
    foreach ($ext in $remote) {
        Write-Host "    • $ext" -ForegroundColor $Script:Colors.Muted
    }

    Write-Host ""
    Write-Host "  Other Extensions:" -ForegroundColor $Script:Colors.Info
    foreach ($ext in $other) {
        Write-Host "    • $ext" -ForegroundColor $Script:Colors.Muted
    }

    Write-Host ""
    Write-Host "  Total: $($extensions.Count) extensions" -ForegroundColor $Script:Colors.Muted
}

# =============================================================================
# Main
# =============================================================================

Write-Banner "VS Code WSL Configuration"

# Check VS Code installation
if (-not (Test-VSCodeInstalled)) {
    Write-Host ""
    Write-Status "VS Code not found" -Type error
    Write-Host ""
    Write-Host "  Install with:" -ForegroundColor $Script:Colors.Muted
    Write-Host "    winget install Microsoft.VisualStudioCode" -ForegroundColor $Script:Colors.Muted
    exit 1
}

Write-Host ""
Write-Status "VS Code: $(Get-VSCodePath)" -Type info

# Show extensions mode
if ($ShowExtensions) {
    Show-InstalledExtensions
    exit 0
}

$changes = @()

# Install single extension
if ($InstallExtension) {
    Write-Host ""
    if (Install-VSCodeExtension -ExtensionId $InstallExtension) {
        $changes += "Installed $InstallExtension"
    }
}

# Install WSL extension
if ($InstallWSLExtension) {
    Write-Host ""

    $wslExtensions = @(
        @{ Id = 'ms-vscode-remote.remote-wsl'; Name = 'WSL Remote' }
        @{ Id = 'ms-vscode-remote.remote-ssh'; Name = 'SSH Remote' }
        @{ Id = 'ms-vscode-remote.remote-containers'; Name = 'Dev Containers' }
    )

    foreach ($ext in $wslExtensions) {
        if (Install-VSCodeExtension -ExtensionId $ext.Id -DisplayName $ext.Name) {
            $changes += "Installed $($ext.Name)"
        }
    }

    # Configure in WSL distros
    $distros = if ($Distro) { @($Distro) } else { Get-InstalledWSLDistros }
    foreach ($d in $distros) {
        Install-VSCodeInWSL -DistroName $d
    }
}

# Install extension pack
if ($InstallExtensionPack) {
    Write-Host ""
    Write-Status "Installing $InstallExtensionPack extension pack..." -Type info
    Write-Host ""

    $pack = Get-ExtensionPack $InstallExtensionPack

    foreach ($ext in $pack) {
        if (Install-VSCodeExtension -ExtensionId $ext.Id -DisplayName $ext.Name) {
            $changes += "Installed $($ext.Name)"
        }
    }
}

# Configure settings
if ($ConfigureSettings) {
    Write-Host ""
    Write-Status "Applying recommended settings..." -Type pending

    $recommendedSettings = Get-RecommendedSettings

    # Update terminal default profile based on installed distros
    $distros = Get-InstalledWSLDistros
    if ($distros.Count -gt 0) {
        $recommendedSettings["terminal.integrated.defaultProfile.windows"] = $distros[0]
    }

    if (Set-VSCodeSettings -NewSettings $recommendedSettings) {
        Write-Status "Settings applied" -Type success
        $changes += "Applied recommended settings"

        Write-Host ""
        Write-Host "  Configured:" -ForegroundColor $Script:Colors.Highlight
        Write-Host "    • Font: Cascadia Code with ligatures" -ForegroundColor $Script:Colors.Muted
        Write-Host "    • Format on save enabled" -ForegroundColor $Script:Colors.Muted
        Write-Host "    • LF line endings (Linux compatible)" -ForegroundColor $Script:Colors.Muted
        Write-Host "    • Terminal: WSL default" -ForegroundColor $Script:Colors.Muted
        Write-Host "    • Git autofetch enabled" -ForegroundColor $Script:Colors.Muted
    }
}

# Enable settings sync
if ($EnableSettingsSync) {
    Write-Host ""
    Write-Status "Settings Sync must be enabled from within VS Code" -Type info
    Write-Host ""
    Write-Host "  To enable:" -ForegroundColor $Script:Colors.Muted
    Write-Host "    1. Open VS Code" -ForegroundColor $Script:Colors.Muted
    Write-Host "    2. Click the gear icon (bottom left)" -ForegroundColor $Script:Colors.Muted
    Write-Host "    3. Select 'Turn on Settings Sync...'" -ForegroundColor $Script:Colors.Muted
    Write-Host "    4. Sign in with GitHub or Microsoft account" -ForegroundColor $Script:Colors.Muted
}

# Summary
if ($changes.Count -gt 0) {
    Write-Host ""
    Write-Status "Configuration complete ($($changes.Count) changes)" -Type success
    Write-Host ""
    Write-Host "  Next steps:" -ForegroundColor $Script:Colors.Highlight
    Write-Host "    • Open a WSL folder: code --remote wsl+Ubuntu /home/user/project" -ForegroundColor $Script:Colors.Muted
    Write-Host "    • Or from WSL: cd /project && code ." -ForegroundColor $Script:Colors.Muted
}
elseif (-not $ShowExtensions -and -not $EnableSettingsSync) {
    Write-Host ""
    Write-Status "No changes specified" -Type info
    Write-Host ""
    Write-Host "  Options:" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -InstallWSLExtension       Install WSL/Remote extensions" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -InstallExtensionPack NAME Install extension pack (webdev, python, devops)" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -ConfigureSettings         Apply recommended VS Code settings" -ForegroundColor $Script:Colors.Muted
    Write-Host "    -ShowExtensions            List installed extensions" -ForegroundColor $Script:Colors.Muted
}

