<#
.SYNOPSIS
    SSH Server Management for Windows - Remote Script Runner

.DESCRIPTION
    Complete SSH server management for Windows including installation,
    configuration, security hardening, and monitoring. Extends and integrates
    with the existing Install-OpenSSH.ps1 functionality.

.PARAMETER Command
    Management command (install, start, stop, restart, status, config, harden, etc.)

.PARAMETER Arguments
    Arguments for the command

.EXAMPLE
    .\SSHServer.ps1 install

.EXAMPLE
    .\SSHServer.ps1 status

.EXAMPLE
    .\SSHServer.ps1 config set DenyGroups administrators

.EXAMPLE
    .\SSHServer.ps1 harden

.NOTES
    Version: 1.0.0
    Requires: PowerShell 5.1+, Administrator privileges
    Integrates with: Install-OpenSSH.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Command,

    [Parameter(Position=1, ValueFromRemainingArguments)]
    [string[]]$Arguments
)

#Requires -Version 5.1
#Requires -RunAsAdministrator

# =============================================================================
# Script Configuration
# =============================================================================

$ErrorActionPreference = 'Stop'
$Script:ScriptVersion = "1.0.0"
$Script:ScriptName = "SSH Server Management"
$Script:DryRun = $false
$Script:Verbose = $false

$Script:SSHDConfigPath = "$env:ProgramData\ssh\sshd_config"
$Script:BackupDir = "$env:ProgramData\ssh\backups"

# =============================================================================
# Import Install-OpenSSH if available
# =============================================================================

$installScript = Join-Path $PSScriptRoot "Install-OpenSSH.ps1"
if (Test-Path $installScript) {
    # Dot-source to import functions
    . $installScript -ClientOnly -ErrorAction SilentlyContinue
}

# =============================================================================
# Logging Functions
# =============================================================================

function Write-SSHLog {
    param(
        [string]$Message,
        [ValidateSet('Info','Success','Warning','Error')]
        [string]$Level = 'Info'
    )

    $colors = @{
        'Info' = 'Cyan'
        'Success' = 'Green'
        'Warning' = 'Yellow'
        'Error' = 'Red'
    }

    $symbols = @{
        'Info' = '▸'
        'Success' = '✓'
        'Warning' = '⚠'
        'Error' = '✗'
    }

    Write-Host "$($symbols[$Level]) " -ForegroundColor $colors[$Level] -NoNewline
    Write-Host $Message
}

function Write-SSHHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host "═══ $Title ═══" -ForegroundColor Cyan
    Write-Host ""
}

# =============================================================================
# SSH Server Status Functions
# =============================================================================

function Test-SSHServerInstalled {
    $capability = Get-WindowsCapability -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'OpenSSH.Server*' }

    return ($capability -and $capability.State -eq 'Installed')
}

function Test-SSHServerRunning {
    try {
        $service = Get-Service -Name sshd -ErrorAction Stop
        return ($service.Status -eq 'Running')
    } catch {
        return $false
    }
}

function Test-SSHServerEnabled {
    try {
        $service = Get-Service -Name sshd -ErrorAction Stop
        return ($service.StartType -eq 'Automatic')
    } catch {
        return $false
    }
}

function Get-SSHServerVersion {
    $sshd = "$env:SystemRoot\System32\OpenSSH\sshd.exe"
    if (Test-Path $sshd) {
        $version = & $sshd -V 2>&1
        return $version
    }
    return "Unknown"
}

# =============================================================================
# Configuration Management
# =============================================================================

function Get-SSHConfig {
    param([string]$Key, [string]$Default = "")

    if (-not (Test-Path $Script:SSHDConfigPath)) {
        return $Default
    }

    $content = Get-Content $Script:SSHDConfigPath
    $line = $content | Where-Object { $_ -match "^\s*$Key\s+" } | Select-Object -Last 1

    if ($line) {
        return ($line -split '\s+')[1]
    }

    return $Default
}

function Set-SSHConfig {
    param(
        [string]$Key,
        [string]$Value
    )

    if (-not (Test-Path $Script:SSHDConfigPath)) {
        throw "SSH configuration file not found at $Script:SSHDConfigPath"
    }

    # Backup first
    Backup-SSHConfig

    $content = Get-Content $Script:SSHDConfigPath
    $found = $false

    $newContent = $content | ForEach-Object {
        if ($_ -match "^\s*#?\s*$Key\s") {
            $found = $true
            "$Key $Value"
        } else {
            $_
        }
    }

    if (-not $found) {
        $newContent += "$Key $Value"
    }

    $newContent | Set-Content $Script:SSHDConfigPath
}

function Backup-SSHConfig {
    if (-not (Test-Path $Script:SSHDConfigPath)) {
        return
    }

    if (-not (Test-Path $Script:BackupDir)) {
        New-Item -ItemType Directory -Path $Script:BackupDir -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupFile = Join-Path $Script:BackupDir "sshd_config.$timestamp"

    Copy-Item -Path $Script:SSHDConfigPath -Destination $backupFile

    # Keep only last 10 backups
    Get-ChildItem $Script:BackupDir -Filter "sshd_config.*" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip 10 |
        Remove-Item -Force

    return $backupFile
}

function Test-SSHConfig {
    $sshd = "$env:SystemRoot\System32\OpenSSH\sshd.exe"
    if (Test-Path $sshd) {
        $result = & $sshd -t 2>&1
        return $?
    }
    return $false
}

# =============================================================================
# Security Functions
# =============================================================================

function Get-SSHSecurityScore {
    $score = 100

    # Windows: Check DenyGroups for administrators (PermitRootLogin not applicable)
    # Reference: https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh-server-configuration
    $denyGroups = Get-SSHConfig "DenyGroups" ""
    $allowGroups = Get-SSHConfig "AllowGroups" ""
    # If administrators can still login (not denied and not restricted by AllowGroups)
    if ($denyGroups -notmatch 'administrators' -and -not $allowGroups) {
        $score -= 15
    }

    # Password authentication
    $passAuth = Get-SSHConfig "PasswordAuthentication" "yes"
    if ($passAuth -eq "yes") { $score -= 15 }

    # Empty passwords
    $emptyPass = Get-SSHConfig "PermitEmptyPasswords" "no"
    if ($emptyPass -eq "yes") { $score -= 30 }

    # Default port
    $port = Get-SSHConfig "Port" "22"
    if ($port -eq "22") { $score -= 10 }

    # Idle timeout
    $timeout = Get-SSHConfig "ClientAliveInterval" "0"
    if ($timeout -eq "0") { $score -= 10 }

    # Max auth tries
    $maxTries = Get-SSHConfig "MaxAuthTries" "6"
    if ([int]$maxTries -gt 3) { $score -= 5 }

    # Access restrictions (AllowUsers or AllowGroups)
    $allowUsers = Get-SSHConfig "AllowUsers" ""
    if (-not $allowUsers -and -not $allowGroups) { $score -= 5 }

    # Public key authentication should be enabled
    $pubkeyAuth = Get-SSHConfig "PubkeyAuthentication" "yes"
    if ($pubkeyAuth -ne "yes") { $score -= 10 }

    if ($score -lt 0) { $score = 0 }

    return $score
}

function Get-SSHFailedLogins {
    param([int]$Count = 10)

    try {
        Get-WinEvent -FilterHashtable @{
            LogName='Security'
            ID=4625  # Failed logon
        } -MaxEvents $Count -ErrorAction SilentlyContinue |
            Select-Object TimeCreated,
                @{Name='Username';Expression={$_.Properties[5].Value}},
                @{Name='IPAddress';Expression={$_.Properties[19].Value}}
    } catch {
        Write-SSHLog "Failed login history not available" -Level Warning
    }
}

# =============================================================================
# Interactive Configuration Functions
# =============================================================================

function Invoke-ConfigureCommand {
    Write-SSHHeader "SSH Server Configuration Wizard"

    # Backup config first
    Write-SSHLog "Creating configuration backup..." -Level Info
    Backup-SSHConfig | Out-Null

    # Show current status
    Write-Host "Current Configuration:" -ForegroundColor White
    Write-Host ""
    Write-Host ("  {0,-25} {1}" -f "Port:", (Get-SSHConfig "Port" "22")) -ForegroundColor Cyan
    Write-Host ("  {0,-25} {1}" -f "PermitRootLogin:", (Get-SSHConfig "PermitRootLogin" "yes")) -ForegroundColor Cyan
    Write-Host ("  {0,-25} {1}" -f "PasswordAuthentication:", (Get-SSHConfig "PasswordAuthentication" "yes")) -ForegroundColor Cyan
    Write-Host ("  {0,-25} {1}" -f "PubkeyAuthentication:", (Get-SSHConfig "PubkeyAuthentication" "yes")) -ForegroundColor Cyan
    Write-Host ("  {0,-25} {1}" -f "PermitEmptyPasswords:", (Get-SSHConfig "PermitEmptyPasswords" "no")) -ForegroundColor Cyan
    Write-Host ("  {0,-25} {1}" -f "MaxAuthTries:", (Get-SSHConfig "MaxAuthTries" "6")) -ForegroundColor Cyan
    Write-Host ("  {0,-25} {1}s" -f "ClientAliveInterval:", (Get-SSHConfig "ClientAliveInterval" "0")) -ForegroundColor Cyan
    Write-Host ("  {0,-25} {1}" -f "AllowUsers:", (Get-SSHConfig "AllowUsers" "(not set)")) -ForegroundColor Cyan
    Write-Host ("  {0,-25} {1}" -f "AllowGroups:", (Get-SSHConfig "AllowGroups" "(not set)")) -ForegroundColor Cyan
    Write-Host ""

    $score = Get-SSHSecurityScore
    $scoreColor = "Green"
    if ($score -lt 80) { $scoreColor = "Yellow" }
    if ($score -lt 60) { $scoreColor = "Red" }
    Write-Host "Security Score: " -NoNewline
    Write-Host "$score/100" -ForegroundColor $scoreColor
    Write-Host ""

    # Main menu
    $options = @(
        "🔒 Change SSH Port",
        "👤 Configure Root Login",
        "🔑 Configure Password Authentication",
        "🔐 Configure Public Key Authentication",
        "⏰ Configure Idle Timeout",
        "🔢 Configure Max Auth Attempts",
        "👥 Configure Allowed Users",
        "📋 Configure Allowed Groups",
        "⚡ Apply Quick Hardening (Recommended)",
        "📄 Show All Settings",
        "🚪 Exit"
    )

    Write-Host "What would you like to configure?" -ForegroundColor Cyan
    for ($i = 0; $i -lt $options.Count; $i++) {
        Write-Host "  $($i + 1). $($options[$i])"
    }
    Write-Host ""

    $choice = Read-Host "Enter choice (1-$($options.Count))"

    switch ($choice) {
        "1" { Configure-Port }
        "2" { Configure-RootLogin }
        "3" { Configure-PasswordAuth }
        "4" { Configure-PubkeyAuth }
        "5" { Configure-IdleTimeout }
        "6" { Configure-MaxAuth }
        "7" { Configure-AllowedUsers }
        "8" { Configure-AllowedGroups }
        "9" { Configure-QuickHarden }
        "10" {
            if (Test-Path $Script:SSHDConfigPath) {
                Get-Content $Script:SSHDConfigPath | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\S' }
            }
        }
        "11" { return }
        default {
            Write-SSHLog "Invalid choice" -Level Error
            return
        }
    }

    # Ask if user wants to configure more
    Write-Host ""
    $continue = Read-Host "Configure another setting? (y/n)"
    if ($continue -eq "y") {
        Invoke-ConfigureCommand
    } else {
        # Validate and offer restart
        if (Test-SSHConfig) {
            Write-Host ""
            $restart = Read-Host "Restart SSH server to apply changes? (y/n)"
            if ($restart -eq "y") {
                Restart-Service sshd
                Write-SSHLog "SSH server restarted - changes applied" -Level Success
            } else {
                Write-SSHLog "Remember to restart SSH: .\SSHServer.ps1 restart" -Level Info
            }
        } else {
            Write-SSHLog "Configuration has errors - please fix before restarting" -Level Error
        }
    }
}

function Configure-Port {
    $current = Get-SSHConfig "Port" "22"

    Write-Host ""
    Write-SSHLog "Current SSH port: $current" -Level Info
    Write-Host ""

    $newPort = Read-Host "Enter new SSH port (1-65535) [$current]"
    if ([string]::IsNullOrWhiteSpace($newPort)) {
        $newPort = $current
    }

    # Validate
    if (-not ($newPort -match '^\d+$') -or [int]$newPort -lt 1 -or [int]$newPort -gt 65535) {
        Write-SSHLog "Invalid port number: $newPort" -Level Error
        return
    }

    if ($newPort -eq $current) {
        Write-SSHLog "Port unchanged" -Level Info
        return
    }

    Write-SSHLog "Setting SSH port to $newPort..." -Level Info
    Set-SSHConfig "Port" $newPort
    Write-SSHLog "Port changed to $newPort" -Level Success

    if ($newPort -ne "22") {
        Write-Host ""
        Write-SSHLog "Remember to update firewall rules for port $newPort" -Level Warning
        Write-Host "  Example: New-NetFirewallRule -DisplayName 'SSH $newPort' -Direction Inbound -LocalPort $newPort -Protocol TCP -Action Allow"
    }
}

function Configure-RootLogin {
    # NOTE: PermitRootLogin is NOT applicable in Windows OpenSSH
    # To prevent administrators from signing in, use DenyGroups directive
    # Reference: https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh-server-configuration

    Write-Host ""
    Write-SSHLog "Windows Note: PermitRootLogin is not applicable in Windows OpenSSH" -Level Warning
    Write-SSHLog "To restrict Administrator access, use DenyGroups or AllowGroups instead" -Level Info
    Write-Host ""

    $currentDeny = Get-SSHConfig "DenyGroups" ""
    $currentAllow = Get-SSHConfig "AllowGroups" ""

    if ($currentDeny) {
        Write-SSHLog "Current DenyGroups: $currentDeny" -Level Info
    }
    if ($currentAllow) {
        Write-SSHLog "Current AllowGroups: $currentAllow" -Level Info
    }
    Write-Host ""

    Write-Host "Restrict Administrator login?" -ForegroundColor Cyan
    Write-Host "  1. Deny Administrators group (blocks admin login)"
    Write-Host "  2. Allow specific groups only (recommended)"
    Write-Host "  3. No restrictions (allow all)"
    Write-Host ""

    $choice = Read-Host "Enter choice (1-3)"

    switch ($choice) {
        "1" {
            # Deny administrators - note: must be lowercase per Windows OpenSSH docs
            Set-SSHConfig "DenyGroups" "administrators"
            Write-SSHLog "DenyGroups set to: administrators" -Level Success
            Write-SSHLog "Administrator accounts are now blocked from SSH" -Level Info
        }
        "2" {
            Write-Host ""
            Write-SSHLog "Enter groups to allow (lowercase, space-separated)" -Level Info
            Write-SSHLog "Example: sshusers domain?users" -Level Info
            $groups = Read-Host "Groups"
            if ($groups) {
                # Convert to lowercase per Windows OpenSSH requirements
                $groups = $groups.ToLower()
                Set-SSHConfig "AllowGroups" $groups
                Write-SSHLog "AllowGroups set to: $groups" -Level Success
            }
        }
        "3" {
            # Remove restrictions
            if (Test-Path $Script:SSHDConfigPath) {
                $content = Get-Content $Script:SSHDConfigPath
                $content = $content -replace '^DenyGroups', '#DenyGroups'
                $content = $content -replace '^AllowGroups', '#AllowGroups'
                $content | Set-Content $Script:SSHDConfigPath
                Write-SSHLog "Group restrictions removed" -Level Success
            }
        }
        default { return }
    }
}

function Configure-PasswordAuth {
    $current = Get-SSHConfig "PasswordAuthentication" "yes"

    Write-Host ""
    Write-SSHLog "Current PasswordAuthentication: $current" -Level Info
    Write-Host ""

    Write-Host "⚠ WARNING: Disabling password authentication requires SSH keys to be set up" -ForegroundColor Yellow
    Write-Host "  Make sure you have key-based access before disabling passwords!" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "Allow password authentication?" -ForegroundColor Cyan
    Write-Host "  1. no - Key-only authentication (MORE SECURE)"
    Write-Host "  2. yes - Allow password authentication"
    Write-Host ""

    $choice = Read-Host "Enter choice (1-2)"

    $value = switch ($choice) {
        "1" { "no" }
        "2" { "yes" }
        default { return }
    }

    if ($value -eq $current) {
        Write-SSHLog "Setting unchanged" -Level Info
        return
    }

    if ($value -eq "no") {
        Write-Host ""
        $confirm = Read-Host "Are you SURE you have SSH key access configured? (yes/no)"
        if ($confirm -ne "yes") {
            Write-SSHLog "Cancelled - set up SSH keys first" -Level Info
            return
        }
    }

    Write-SSHLog "Setting PasswordAuthentication to $value..." -Level Info
    Set-SSHConfig "PasswordAuthentication" $value
    Write-SSHLog "PasswordAuthentication set to $value" -Level Success
}

function Configure-PubkeyAuth {
    $current = Get-SSHConfig "PubkeyAuthentication" "yes"

    Write-Host ""
    Write-SSHLog "Current PubkeyAuthentication: $current" -Level Info
    Write-Host ""

    Write-Host "Allow public key authentication?" -ForegroundColor Cyan
    Write-Host "  1. yes - Allow public key authentication (RECOMMENDED)"
    Write-Host "  2. no - Disallow public key authentication"
    Write-Host ""

    $choice = Read-Host "Enter choice (1-2)"

    $value = switch ($choice) {
        "1" { "yes" }
        "2" { "no" }
        default { return }
    }

    if ($value -eq $current) {
        Write-SSHLog "Setting unchanged" -Level Info
        return
    }

    Write-SSHLog "Setting PubkeyAuthentication to $value..." -Level Info
    Set-SSHConfig "PubkeyAuthentication" $value
    Write-SSHLog "PubkeyAuthentication set to $value" -Level Success
}

function Configure-IdleTimeout {
    $current = Get-SSHConfig "ClientAliveInterval" "0"

    Write-Host ""
    Write-SSHLog "Current idle timeout: ${current}s (0 = disabled)" -Level Info
    Write-Host ""

    Write-Host "Set idle timeout?" -ForegroundColor Cyan
    Write-Host "  1. 300 - 5 minutes (RECOMMENDED)"
    Write-Host "  2. 600 - 10 minutes"
    Write-Host "  3. 900 - 15 minutes"
    Write-Host "  4. 1800 - 30 minutes"
    Write-Host "  5. 0 - Disabled (no timeout)"
    Write-Host "  6. Custom - Enter custom value"
    Write-Host ""

    $choice = Read-Host "Enter choice (1-6)"

    $value = switch ($choice) {
        "1" { "300" }
        "2" { "600" }
        "3" { "900" }
        "4" { "1800" }
        "5" { "0" }
        "6" { Read-Host "Enter timeout in seconds" }
        default { return }
    }

    if ($value -eq $current) {
        Write-SSHLog "Setting unchanged" -Level Info
        return
    }

    Write-SSHLog "Setting ClientAliveInterval to $value..." -Level Info
    Set-SSHConfig "ClientAliveInterval" $value
    Set-SSHConfig "ClientAliveCountMax" "2"
    Write-SSHLog "Idle timeout set to ${value}s" -Level Success
}

function Configure-MaxAuth {
    $current = Get-SSHConfig "MaxAuthTries" "6"

    Write-Host ""
    Write-SSHLog "Current MaxAuthTries: $current" -Level Info
    Write-Host ""

    Write-Host "Maximum authentication attempts?" -ForegroundColor Cyan
    Write-Host "  1. 3 - Strict (RECOMMENDED)"
    Write-Host "  2. 4 - Moderate"
    Write-Host "  3. 6 - Default"
    Write-Host "  4. Custom - Enter custom value"
    Write-Host ""

    $choice = Read-Host "Enter choice (1-4)"

    $value = switch ($choice) {
        "1" { "3" }
        "2" { "4" }
        "3" { "6" }
        "4" { Read-Host "Enter max attempts (1-10)" }
        default { return }
    }

    if ($value -eq $current) {
        Write-SSHLog "Setting unchanged" -Level Info
        return
    }

    Write-SSHLog "Setting MaxAuthTries to $value..." -Level Info
    Set-SSHConfig "MaxAuthTries" $value
    Write-SSHLog "MaxAuthTries set to $value" -Level Success
}

function Configure-AllowedUsers {
    $current = Get-SSHConfig "AllowUsers" ""

    Write-Host ""
    if ($current) {
        Write-SSHLog "Current AllowUsers: $current" -Level Info
    } else {
        Write-SSHLog "AllowUsers: Not set (all users allowed)" -Level Info
    }
    Write-Host ""

    Write-Host "Configure allowed users?" -ForegroundColor Cyan
    Write-Host "  1. Set allowed users"
    Write-Host "  2. Clear restriction (allow all users)"
    Write-Host "  3. Keep current setting"
    Write-Host ""

    $choice = Read-Host "Enter choice (1-3)"

    switch ($choice) {
        "1" {
            $users = Read-Host "Enter usernames (space-separated) [$current]"
            if ([string]::IsNullOrWhiteSpace($users)) {
                $users = $current
            }
            if ($users) {
                Set-SSHConfig "AllowUsers" $users
                Write-SSHLog "AllowUsers set to: $users" -Level Success
            }
        }
        "2" {
            if (Test-Path $Script:SSHDConfigPath) {
                $content = Get-Content $Script:SSHDConfigPath
                $content = $content -replace '^AllowUsers', '#AllowUsers'
                $content | Set-Content $Script:SSHDConfigPath
                Write-SSHLog "AllowUsers restriction removed" -Level Success
            }
        }
        default { return }
    }
}

function Configure-AllowedGroups {
    $current = Get-SSHConfig "AllowGroups" ""

    Write-Host ""
    if ($current) {
        Write-SSHLog "Current AllowGroups: $current" -Level Info
    } else {
        Write-SSHLog "AllowGroups: Not set (all groups allowed)" -Level Info
    }
    Write-Host ""

    Write-Host "Configure allowed groups?" -ForegroundColor Cyan
    Write-Host "  1. Set allowed groups"
    Write-Host "  2. Clear restriction (allow all groups)"
    Write-Host "  3. Keep current setting"
    Write-Host ""

    $choice = Read-Host "Enter choice (1-3)"

    switch ($choice) {
        "1" {
            $groups = Read-Host "Enter group names (space-separated) [$current]"
            if ([string]::IsNullOrWhiteSpace($groups)) {
                $groups = $current
            }
            if ($groups) {
                Set-SSHConfig "AllowGroups" $groups
                Write-SSHLog "AllowGroups set to: $groups" -Level Success
            }
        }
        "2" {
            if (Test-Path $Script:SSHDConfigPath) {
                $content = Get-Content $Script:SSHDConfigPath
                $content = $content -replace '^AllowGroups', '#AllowGroups'
                $content | Set-Content $Script:SSHDConfigPath
                Write-SSHLog "AllowGroups restriction removed" -Level Success
            }
        }
        default { return }
    }
}

function Configure-QuickHarden {
    Write-Host ""
    Write-Host "Quick Hardening will apply these security settings:" -ForegroundColor White
    Write-Host ""
    Write-Host "  • DenyGroups: administrators (Windows-specific, blocks admin SSH)"
    Write-Host "  • PasswordAuthentication: no (key-only)"
    Write-Host "  • PubkeyAuthentication: yes"
    Write-Host "  • PermitEmptyPasswords: no"
    Write-Host "  • MaxAuthTries: 3"
    Write-Host "  • ClientAliveInterval: 300 (5 min timeout)"
    Write-Host "  • ClientAliveCountMax: 2"
    Write-Host ""
    Write-Host "Note: PermitRootLogin is not applicable on Windows OpenSSH" -ForegroundColor Gray
    Write-Host ""

    Write-Host "⚠ IMPORTANT WARNING" -ForegroundColor Red
    Write-Host "Make sure you have SSH key access configured before applying!" -ForegroundColor Yellow
    Write-Host "You could lock yourself out if password auth is disabled without keys." -ForegroundColor Yellow
    Write-Host ""

    $apply = Read-Host "Apply quick hardening? (yes/no)"
    if ($apply -ne "yes") {
        Write-SSHLog "Cancelled" -Level Info
        return
    }

    Write-Host ""
    $confirm = Read-Host "Confirm: You have SSH key access already set up? (yes/no)"
    if ($confirm -ne "yes") {
        Write-SSHLog "Set up SSH keys first" -Level Info
        return
    }

    Write-SSHLog "Applying quick hardening..." -Level Info

    # Windows: Use DenyGroups instead of PermitRootLogin (not applicable on Windows)
    # All account names must be lowercase per Windows OpenSSH documentation
    Set-SSHConfig "DenyGroups" "administrators"
    Write-SSHLog "Denied administrators group SSH access" -Level Success

    Set-SSHConfig "PasswordAuthentication" "no"
    Write-SSHLog "Disabled password authentication" -Level Success

    Set-SSHConfig "PubkeyAuthentication" "yes"
    Write-SSHLog "Enabled public key authentication" -Level Success

    Set-SSHConfig "PermitEmptyPasswords" "no"
    Write-SSHLog "Disabled empty passwords" -Level Success

    Set-SSHConfig "MaxAuthTries" "3"
    Write-SSHLog "Limited auth attempts to 3" -Level Success

    Set-SSHConfig "ClientAliveInterval" "300"
    Set-SSHConfig "ClientAliveCountMax" "2"
    Write-SSHLog "Set idle timeout to 5 minutes" -Level Success

    Write-Host ""

    if (Test-SSHConfig) {
        Write-SSHLog "Configuration is valid" -Level Success

        $score = Get-SSHSecurityScore
        Write-Host ""
        Write-Host "New Security Score: " -NoNewline
        Write-Host "$score/100" -ForegroundColor Green
    } else {
        Write-SSHLog "Configuration validation failed" -Level Error
        Write-SSHLog "Rolling back changes..." -Level Warning
        # Restore from most recent backup
        $latestBackup = Get-ChildItem "$Script:BackupDir\sshd_config.*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latestBackup) {
            Copy-Item $latestBackup.FullName -Destination $Script:SSHDConfigPath -Force
        }
    }
}

# =============================================================================
# Command Implementations
# =============================================================================

function Invoke-InstallCommand {
    Write-SSHHeader "Install SSH Server"

    if (Test-SSHServerInstalled) {
        Write-SSHLog "SSH server is already installed" -Level Success
        $version = Get-SSHServerVersion
        Write-SSHLog "Version: $version" -Level Info
        return
    }

    if ($Script:DryRun) {
        Write-SSHLog "[DRY RUN] Would install SSH server" -Level Info
        return
    }

    Write-SSHLog "Installing SSH server..." -Level Info

    try {
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
        Write-SSHLog "SSH server installed successfully" -Level Success

        Write-Host ""
        Write-SSHLog "Next steps:" -Level Info
        Write-Host "  1. Enable at boot: .\SSHServer.ps1 enable"
        Write-Host "  2. Start service:   .\SSHServer.ps1 start"
        Write-Host "  3. Check status:    .\SSHServer.ps1 status"
        Write-Host "  4. Harden security: .\SSHServer.ps1 harden"
    } catch {
        Write-SSHLog "Failed to install SSH server: $_" -Level Error
        exit 1
    }
}

function Invoke-StartCommand {
    Write-SSHHeader "Start SSH Server"

    if (Test-SSHServerRunning) {
        Write-SSHLog "SSH server is already running" -Level Success
        return
    }

    if ($Script:DryRun) {
        Write-SSHLog "[DRY RUN] Would start SSH server" -Level Info
        return
    }

    try {
        Start-Service sshd
        Write-SSHLog "SSH server started successfully" -Level Success
    } catch {
        Write-SSHLog "Failed to start SSH server: $_" -Level Error
        exit 1
    }
}

function Invoke-StopCommand {
    Write-SSHHeader "Stop SSH Server"

    if (-not (Test-SSHServerRunning)) {
        Write-SSHLog "SSH server is not running" -Level Info
        return
    }

    Write-Host "WARNING: Stopping SSH server will terminate all SSH connections" -ForegroundColor Yellow
    $confirm = Read-Host "Are you sure? (yes/no)"
    if ($confirm -ne "yes") {
        Write-SSHLog "Cancelled" -Level Info
        return
    }

    if ($Script:DryRun) {
        Write-SSHLog "[DRY RUN] Would stop SSH server" -Level Info
        return
    }

    try {
        Stop-Service sshd
        Write-SSHLog "SSH server stopped" -Level Success
    } catch {
        Write-SSHLog "Failed to stop SSH server: $_" -Level Error
        exit 1
    }
}

function Invoke-RestartCommand {
    Write-SSHHeader "Restart SSH Server"

    if ($Script:DryRun) {
        Write-SSHLog "[DRY RUN] Would restart SSH server" -Level Info
        return
    }

    try {
        Restart-Service sshd
        Write-SSHLog "SSH server restarted successfully" -Level Success
    } catch {
        Write-SSHLog "Failed to restart SSH server: $_" -Level Error
        exit 1
    }
}

function Invoke-EnableCommand {
    Write-SSHHeader "Enable SSH Server"

    if (Test-SSHServerEnabled) {
        Write-SSHLog "SSH server is already enabled at boot" -Level Success
        return
    }

    if ($Script:DryRun) {
        Write-SSHLog "[DRY RUN] Would enable SSH server at boot" -Level Info
        return
    }

    try {
        Set-Service -Name sshd -StartupType Automatic
        Write-SSHLog "SSH server enabled at boot" -Level Success
    } catch {
        Write-SSHLog "Failed to enable SSH server: $_" -Level Error
        exit 1
    }
}

function Invoke-StatusCommand {
    Write-SSHHeader "SSH Server Status"

    # Installation
    if (Test-SSHServerInstalled) {
        Write-SSHLog "SSH server is installed" -Level Success
        $version = Get-SSHServerVersion
        Write-Host "  Version: $version"
    } else {
        Write-SSHLog "SSH server is NOT installed" -Level Error
        Write-Host ""
        Write-SSHLog "Install with: .\SSHServer.ps1 install" -Level Info
        return
    }

    Write-Host ""

    # Running
    if (Test-SSHServerRunning) {
        Write-SSHLog "SSH server is running" -Level Success
    } else {
        Write-SSHLog "SSH server is NOT running" -Level Warning
        Write-Host "  Start with: .\SSHServer.ps1 start"
    }

    Write-Host ""

    # Boot status
    if (Test-SSHServerEnabled) {
        Write-SSHLog "SSH server is enabled at boot" -Level Success
    } else {
        Write-SSHLog "SSH server is NOT enabled at boot" -Level Warning
        Write-Host "  Enable with: .\SSHServer.ps1 enable"
    }

    Write-Host ""

    # Port
    $port = Get-SSHConfig "Port" "22"
    Write-Host "Port: $port" -ForegroundColor Cyan

    # Connections
    $connections = (netstat -an | Select-String ":$port\s" | Measure-Object).Count
    Write-Host "Active connections: $connections" -ForegroundColor Cyan

    Write-Host ""

    # Security score
    $score = Get-SSHSecurityScore
    $color = "Green"
    if ($score -lt 80) { $color = "Yellow" }
    if ($score -lt 60) { $color = "Red" }

    Write-Host "Security score: " -NoNewline
    Write-Host "$score/100" -ForegroundColor $color

    if ($score -lt 80) {
        Write-Host "  Improve with: .\SSHServer.ps1 harden"
    }
}

function Invoke-ConfigCommand {
    param([string[]]$Args)

    if ($Args.Count -eq 0) {
        Write-SSHLog "Usage: config {get|set|backup|validate|show}" -Level Error
        exit 2
    }

    $action = $Args[0]

    switch ($action) {
        'get' {
            $key = $Args[1]
            $value = Get-SSHConfig $key
            Write-Host $value
        }
        'set' {
            $key = $Args[1]
            $value = $Args[2]
            Write-SSHHeader "Set Configuration: $key = $value"

            if ($Script:DryRun) {
                Write-SSHLog "[DRY RUN] Would set $key to $value" -Level Info
                return
            }

            Set-SSHConfig -Key $key -Value $value
            Write-SSHLog "Configuration updated" -Level Success

            if (Test-SSHConfig) {
                Write-SSHLog "Configuration is valid" -Level Success
                Write-SSHLog "Restart SSH to apply: .\SSHServer.ps1 restart" -Level Info
            } else {
                Write-SSHLog "Configuration is invalid!" -Level Error
                exit 1
            }
        }
        'backup' {
            Write-SSHHeader "Backup Configuration"
            $backup = Backup-SSHConfig
            Write-SSHLog "Configuration backed up to: $backup" -Level Success
        }
        'validate' {
            Write-SSHHeader "Validate Configuration"
            if (Test-SSHConfig) {
                Write-SSHLog "Configuration is valid" -Level Success
            } else {
                Write-SSHLog "Configuration has errors" -Level Error
                exit 1
            }
        }
        'show' {
            Write-SSHHeader "SSH Configuration"
            if (Test-Path $Script:SSHDConfigPath) {
                Get-Content $Script:SSHDConfigPath | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\S' }
            }
        }
        default {
            Write-SSHLog "Unknown config action: $action" -Level Error
            exit 2
        }
    }
}

function Invoke-HardenCommand {
    Write-SSHHeader "SSH Security Hardening"

    Write-SSHLog "Applying security hardening..." -Level Info

    if ($Script:DryRun) {
        Write-SSHLog "[DRY RUN] Would apply hardening" -Level Info
        return
    }

    # Apply hardening settings (Windows-specific)
    # Note: PermitRootLogin is NOT applicable on Windows OpenSSH
    # Use DenyGroups to restrict administrator access instead
    # Reference: https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh-server-configuration

    # All account names must be lowercase per Windows OpenSSH documentation
    Set-SSHConfig "DenyGroups" "administrators"
    Set-SSHConfig "PasswordAuthentication" "no"
    Set-SSHConfig "PubkeyAuthentication" "yes"
    Set-SSHConfig "PermitEmptyPasswords" "no"
    Set-SSHConfig "MaxAuthTries" "3"
    Set-SSHConfig "ClientAliveInterval" "300"
    Set-SSHConfig "ClientAliveCountMax" "2"
    Set-SSHConfig "MaxSessions" "10"

    if (Test-SSHConfig) {
        Write-SSHLog "Security hardening applied" -Level Success
        Write-SSHLog "Restart SSH to apply: .\SSHServer.ps1 restart" -Level Info
    } else {
        Write-SSHLog "Configuration validation failed" -Level Error
        exit 1
    }
}

function Invoke-ScoreCommand {
    $score = Get-SSHSecurityScore

    $color = "Green"
    $grade = "A"

    if ($score -lt 90) { $color = "Green"; $grade = "A" }
    if ($score -lt 80) { $color = "Yellow"; $grade = "B" }
    if ($score -lt 70) { $color = "Yellow"; $grade = "C" }
    if ($score -lt 60) { $color = "Red"; $grade = "D" }
    if ($score -lt 50) { $color = "Red"; $grade = "F" }

    Write-Host ""
    Write-Host "SSH Security Score: " -NoNewline
    Write-Host "$score/100 (Grade: $grade)" -ForegroundColor $color
    Write-Host ""

    if ($score -lt 80) {
        Write-SSHLog "Recommendations:" -Level Info
        Write-Host "  Run: .\SSHServer.ps1 harden"
    }
}

function Invoke-FailedCommand {
    Write-SSHHeader "Failed Login Attempts"

    $failed = Get-SSHFailedLogins -Count 10

    if ($failed) {
        $failed | Format-Table -AutoSize
    } else {
        Write-SSHLog "No failed login attempts found" -Level Success
    }
}

function Show-Usage {
    Write-Host @"
$Script:ScriptName v$Script:ScriptVersion

Complete SSH server management for Windows.

Usage:
    SSHServer.ps1 <command> [OPTIONS]

Commands:

  Installation & Setup:
    install             Install SSH server

  Service Control:
    start               Start SSH server
    stop                Stop SSH server
    restart             Restart SSH server
    enable              Enable at boot
    disable             Disable at boot
    status              Show status

  Configuration:
    configure           Interactive configuration wizard ✨
    config get KEY      Get config value
    config set KEY VAL  Set config value
    config backup       Backup configuration
    config validate     Validate configuration
    config show         Show configuration

  Security:
    harden              Apply security hardening
    score               Show security score
    failed              Show failed logins

Global Options:
    -h, --help          Show help
    -v, --verbose       Verbose output
    -d, --dry-run       Show what would be done

Examples:

    .\SSHServer.ps1 install
    .\SSHServer.ps1 status
    .\SSHServer.ps1 harden
    .\SSHServer.ps1 config set Port 2222

"@
}

# =============================================================================
# Main Entry Point
# =============================================================================

function Main {
    # Parse global args
    $filteredArgs = @()
    foreach ($arg in $Arguments) {
        switch ($arg) {
            { $_ -in '-h','--help' } {
                Show-Usage
                exit 0
            }
            { $_ -in '-v','--verbose' } {
                $Script:Verbose = $true
            }
            { $_ -in '-d','--dry-run' } {
                $Script:DryRun = $true
            }
            default {
                $filteredArgs += $arg
            }
        }
    }

    if (-not $Command) {
        Show-Usage
        exit 0
    }

    # Route to commands
    switch ($Command) {
        'install' { Invoke-InstallCommand }
        'start' { Invoke-StartCommand }
        'stop' { Invoke-StopCommand }
        'restart' { Invoke-RestartCommand }
        'enable' { Invoke-EnableCommand }
        'disable' { Invoke-DisableCommand }
        'status' { Invoke-StatusCommand }
        'configure' { Invoke-ConfigureCommand }
        'config' { Invoke-ConfigCommand $filteredArgs }
        'harden' { Invoke-HardenCommand }
        'score' { Invoke-ScoreCommand }
        'failed' { Invoke-FailedCommand }
        default {
            Write-SSHLog "Unknown command: $Command" -Level Error
            Write-Host "Run '.\SSHServer.ps1 --help' for usage"
            exit 2
        }
    }
}

# Run main
try {
    Main
} catch {
    Write-SSHLog "Fatal error: $_" -Level Error
    exit 1
}
