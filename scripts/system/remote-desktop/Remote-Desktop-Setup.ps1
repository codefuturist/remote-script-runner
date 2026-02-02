<#
.SYNOPSIS
    Remote Desktop Setup - Configure Remote Desktop on Windows

.DESCRIPTION
    Enables and configures Remote Desktop (RDP) on Windows with best practices
    for security and usability. Supports Windows 10/11 Pro, Enterprise, and Server.

.PARAMETER Action
    The action to perform: Enable, Disable, Status, Security, Configure, Firewall

.PARAMETER Help
    Show help message

.PARAMETER DryRun
    Show what would be done without executing

.PARAMETER Force
    Force operation without confirmations

.EXAMPLE
    .\Remote-Desktop-Setup.ps1 -Action Enable

.EXAMPLE
    .\Remote-Desktop-Setup.ps1 -Action Status

.EXAMPLE
    .\Remote-Desktop-Setup.ps1 -Action Security

.NOTES
    Version: 1.0.0
    Author:  RSR Team
    License: MIT
    Requires: Windows 10/11 Pro or higher, Administrator privileges
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Enable', 'Disable', 'Status', 'Security', 'Configure', 'Firewall', 'Users', 'Menu', 'Help', '')]
    [string]$Action = '',

    [switch]$Force,

    [Alias('h')]
    [switch]$Help
)

# =============================================================================
# Configuration
# =============================================================================

$ErrorActionPreference = 'Stop'
$Script:Name = 'Remote-Desktop-Setup'
$Script:Version = '1.0.0'
$Script:RDPPort = 3389

# =============================================================================
# RSR Library (Optional)
# =============================================================================

$RSRModulePath = Join-Path $PSScriptRoot '../../../lib/powershell/RSR.psd1'
$Script:UseRSR = $false

if (Test-Path $RSRModulePath) {
    try {
        Import-Module $RSRModulePath -Force -ErrorAction Stop
        $Script:UseRSR = $true
    } catch {
        # Continue without RSR library
    }
}

# =============================================================================
# Logging Functions (Standalone fallback)
# =============================================================================

function Write-Info {
    param([string]$Message)
    if ($Script:UseRSR) {
        Write-RSRInfo $Message
    } else {
        Write-Host "[INFO] $Message" -ForegroundColor Cyan
    }
}

function Write-Ok {
    param([string]$Message)
    if ($Script:UseRSR) {
        Write-RSROk $Message
    } else {
        Write-Host "[OK] $Message" -ForegroundColor Green
    }
}

function Write-Warn {
    param([string]$Message)
    if ($Script:UseRSR) {
        Write-RSRWarn $Message
    } else {
        Write-Host "[WARN] $Message" -ForegroundColor Yellow
    }
}

function Write-Err {
    param([string]$Message)
    if ($Script:UseRSR) {
        Write-RSRError $Message
    } else {
        Write-Host "[ERROR] $Message" -ForegroundColor Red
    }
}

# =============================================================================
# Helper Functions
# =============================================================================

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Blue
    Write-Host "  $Title" -ForegroundColor Blue
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Blue
    Write-Host ""
}

function Write-Step {
    param([string]$Message)
    Write-Host "▶ $Message" -ForegroundColor Cyan
}

function Test-WindowsEdition {
    # Check if Windows edition supports RDP server
    $edition = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption
    
    $supportedEditions = @(
        'Pro', 'Professional', 'Enterprise', 'Education', 
        'Server', 'Business', 'Ultimate'
    )
    
    $isSupported = $false
    foreach ($ed in $supportedEditions) {
        if ($edition -match $ed) {
            $isSupported = $true
            break
        }
    }
    
    return @{
        Edition = $edition
        Supported = $isSupported
    }
}

function Get-LocalIPAddress {
    try {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | 
               Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and $_.PrefixOrigin -ne 'WellKnown' } | 
               Select-Object -First 1).IPAddress
        return $ip
    } catch {
        return "localhost"
    }
}

# =============================================================================
# RDP Functions
# =============================================================================

function Enable-RemoteDesktop {
    Write-Header "Enabling Remote Desktop"
    
    # Check Windows edition
    $editionCheck = Test-WindowsEdition
    if (-not $editionCheck.Supported) {
        Write-Err "Remote Desktop Server requires Windows Pro, Enterprise, or Server"
        Write-Err "Current edition: $($editionCheck.Edition)"
        Write-Host ""
        Write-Host "Windows Home edition only supports Remote Desktop Client, not Server."
        Write-Host "Consider upgrading to Windows Pro or using alternatives like:"
        Write-Host "  - Chrome Remote Desktop (free)"
        Write-Host "  - TeamViewer"
        Write-Host "  - AnyDesk"
        return
    }
    
    Write-Ok "Windows edition supported: $($editionCheck.Edition)"
    
    # Enable Remote Desktop
    Write-Step "Enabling Remote Desktop..."
    
    if ($WhatIfPreference) {
        Write-Host "[DRY-RUN] Would enable Remote Desktop via registry"
    } else {
        # Enable via registry
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0 -Force
        
        # Enable Network Level Authentication (NLA) - more secure
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1 -Force
        
        # Enable Remote Desktop service
        Set-Service -Name TermService -StartupType Automatic
        Start-Service -Name TermService -ErrorAction SilentlyContinue
    }
    
    Write-Ok "Remote Desktop enabled"
    
    # Configure firewall
    Enable-RDPFirewall
    
    # Show connection info
    $ip = Get-LocalIPAddress
    Write-Host ""
    Write-Header "Setup Complete!"
    Write-Host "Connect using Remote Desktop Client:"
    Write-Host "  Computer: $ip" -ForegroundColor Green
    Write-Host "  Port: $($Script:RDPPort)" -ForegroundColor Green
    Write-Host ""
    Write-Host "On Windows: Press Win+R, type 'mstsc', enter the computer address"
    Write-Host ""
    Write-Host "For improved security, run:"
    Write-Host "  .\$($Script:Name).ps1 -Action Security"
}

function Disable-RemoteDesktop {
    Write-Header "Disabling Remote Desktop"
    
    if (-not $Force) {
        $confirm = Read-Host "Are you sure you want to disable Remote Desktop? [y/N]"
        if ($confirm -notmatch '^[Yy]') {
            Write-Host "Cancelled"
            return
        }
    }
    
    Write-Step "Disabling Remote Desktop..."
    
    if ($WhatIfPreference) {
        Write-Host "[DRY-RUN] Would disable Remote Desktop via registry"
    } else {
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 1 -Force
        Stop-Service -Name TermService -Force -ErrorAction SilentlyContinue
    }
    
    Write-Ok "Remote Desktop disabled"
}

function Get-RDPStatus {
    Write-Header "Remote Desktop Status"
    
    # Check Windows edition
    $editionCheck = Test-WindowsEdition
    Write-Host "Windows Edition: $($editionCheck.Edition)"
    Write-Host "RDP Server Support: $(if ($editionCheck.Supported) { 'Yes' } else { 'No (requires Pro/Enterprise)' })"
    Write-Host ""
    
    # Check if RDP is enabled
    $rdpEnabled = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -ErrorAction SilentlyContinue).fDenyTSConnections -eq 0
    
    Write-Host "Remote Desktop: $(if ($rdpEnabled) { 'Enabled' } else { 'Disabled' })" -ForegroundColor $(if ($rdpEnabled) { 'Green' } else { 'Yellow' })
    
    # Check NLA status
    $nlaEnabled = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -ErrorAction SilentlyContinue).UserAuthentication -eq 1
    Write-Host "Network Level Authentication (NLA): $(if ($nlaEnabled) { 'Enabled' } else { 'Disabled' })" -ForegroundColor $(if ($nlaEnabled) { 'Green' } else { 'Yellow' })
    
    # Check service status
    $service = Get-Service -Name TermService -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "Service Status: $($service.Status)"
        Write-Host "Service Startup: $($service.StartType)"
    }
    
    # Check firewall rule
    Write-Host ""
    Write-Host "Firewall Rules:"
    $rules = Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    if ($rules) {
        foreach ($rule in $rules) {
            $enabled = if ($rule.Enabled) { "Enabled" } else { "Disabled" }
            Write-Host "  $($rule.DisplayName): $enabled"
        }
    } else {
        Write-Host "  No Remote Desktop firewall rules found"
    }
    
    # Check listening port
    Write-Host ""
    Write-Host "Listening Ports:"
    $listening = Get-NetTCPConnection -LocalPort $Script:RDPPort -State Listen -ErrorAction SilentlyContinue
    if ($listening) {
        Write-Host "  Port $($Script:RDPPort): Listening" -ForegroundColor Green
    } else {
        Write-Host "  Port $($Script:RDPPort): Not listening" -ForegroundColor Yellow
    }
    
    # Show connection info
    if ($rdpEnabled) {
        $ip = Get-LocalIPAddress
        Write-Host ""
        Write-Host "Connection Info:" -ForegroundColor Cyan
        Write-Host "  Connect to: $ip`:$($Script:RDPPort)"
    }
    
    # Current sessions
    Write-Host ""
    Write-Host "Active Sessions:"
    try {
        $sessions = quser 2>&1
        if ($sessions -notmatch 'No User exists') {
            $sessions | ForEach-Object { Write-Host "  $_" }
        } else {
            Write-Host "  No active sessions"
        }
    } catch {
        Write-Host "  Unable to query sessions"
    }
    
    # Allowed users
    Write-Host ""
    Write-Host "Allowed Users (Remote Desktop Users group):"
    try {
        $members = Get-LocalGroupMember -Group "Remote Desktop Users" -ErrorAction SilentlyContinue
        if ($members) {
            foreach ($member in $members) {
                Write-Host "  $($member.Name)"
            }
        } else {
            Write-Host "  No members (only Administrators can connect)"
        }
    } catch {
        Write-Host "  Unable to query group members"
    }
}

function Enable-RDPFirewall {
    Write-Step "Configuring Windows Firewall..."
    
    if ($WhatIfPreference) {
        Write-Host "[DRY-RUN] Would enable Remote Desktop firewall rules"
        return
    }
    
    # Enable built-in Remote Desktop rules
    try {
        Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
        Write-Ok "Firewall rules enabled for Remote Desktop"
    } catch {
        Write-Warn "Could not enable built-in firewall rules, creating custom rule..."
        
        # Create custom rule if built-in doesn't exist
        New-NetFirewallRule -DisplayName "Remote Desktop (TCP-In)" `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort $Script:RDPPort `
            -Action Allow `
            -Profile Any `
            -ErrorAction SilentlyContinue
    }
}

function Set-RDPSecurity {
    Write-Header "Applying Security Hardening"
    
    Write-Step "Configuring security settings..."
    
    if ($WhatIfPreference) {
        Write-Host "[DRY-RUN] Would apply security hardening"
        return
    }
    
    # 1. Enable Network Level Authentication (NLA)
    Write-Step "Enabling Network Level Authentication (NLA)..."
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1 -Force
    Write-Ok "NLA enabled - requires authentication before session starts"
    
    # 2. Set minimum encryption level
    Write-Step "Setting encryption to High level..."
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "MinEncryptionLevel" -Value 3 -Force
    Write-Ok "Encryption level set to High"
    
    # 3. Set security layer to SSL/TLS
    Write-Step "Configuring SSL/TLS security layer..."
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "SecurityLayer" -Value 2 -Force
    Write-Ok "Security layer set to SSL/TLS"
    
    # 4. Disable clipboard redirection (optional but more secure)
    Write-Step "Reviewing clipboard redirection..."
    Write-Host "  Clipboard redirection is currently: $(if ((Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'fDisableClip' -ErrorAction SilentlyContinue).fDisableClip -eq 1) { 'Disabled' } else { 'Enabled' })"
    
    # 5. Configure session timeout
    Write-Step "Configuring session timeouts..."
    # Set idle session limit (in milliseconds, 0 = never)
    # This example sets 30 minutes = 1800000 ms
    # Uncomment to enable:
    # Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "MaxIdleTime" -Value 1800000 -Force
    Write-Host "  Session timeout: Not configured (modify script to enable)"
    
    # 6. Check account lockout policy
    Write-Step "Checking account lockout policy..."
    $lockoutThreshold = (net accounts | Select-String "Lockout threshold").ToString().Split(':')[1].Trim()
    if ($lockoutThreshold -eq 'Never') {
        Write-Warn "Account lockout is not configured!"
        Write-Host "  Recommend: net accounts /lockoutthreshold:5"
    } else {
        Write-Ok "Account lockout threshold: $lockoutThreshold"
    }
    
    Write-Host ""
    Write-Header "Security Recommendations"
    Write-Host ""
    Write-Host "1. Use strong passwords for all user accounts"
    Write-Host "2. Limit users who can connect via RDP:"
    Write-Host "   - Add users to 'Remote Desktop Users' group"
    Write-Host "   - Run: .\$($Script:Name).ps1 -Action Users"
    Write-Host ""
    Write-Host "3. Consider changing the default RDP port (3389) for obscurity:"
    Write-Host "   - Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'PortNumber' -Value <new_port>"
    Write-Host "   - Update firewall rules accordingly"
    Write-Host ""
    Write-Host "4. Use Windows Firewall to restrict access by IP:"
    Write-Host "   - New-NetFirewallRule -DisplayName 'RDP-Restricted' -Direction Inbound -Protocol TCP -LocalPort 3389 -RemoteAddress <trusted_ip> -Action Allow"
    Write-Host ""
    Write-Host "5. Enable audit logging for RDP connections:"
    Write-Host "   - auditpol /set /subcategory:'Logon' /success:enable /failure:enable"
    Write-Host ""
    Write-Host "6. Keep Windows updated with latest security patches"
    Write-Host ""
    
    Write-Ok "Security hardening complete"
}

function Set-RDPUsers {
    Write-Header "Remote Desktop Users Management"
    
    Write-Host "Current members of 'Remote Desktop Users' group:"
    Write-Host ""
    
    try {
        $members = Get-LocalGroupMember -Group "Remote Desktop Users" -ErrorAction SilentlyContinue
        if ($members) {
            foreach ($member in $members) {
                Write-Host "  $($member.Name) ($($member.ObjectClass))"
            }
        } else {
            Write-Host "  (No members - only Administrators can connect)"
        }
    } catch {
        Write-Err "Unable to query group members"
    }
    
    Write-Host ""
    Write-Host "To add a user to Remote Desktop Users:"
    Write-Host "  Add-LocalGroupMember -Group 'Remote Desktop Users' -Member 'username'"
    Write-Host ""
    Write-Host "To remove a user:"
    Write-Host "  Remove-LocalGroupMember -Group 'Remote Desktop Users' -Member 'username'"
    Write-Host ""
    Write-Host "Note: Administrators can always connect via RDP regardless of this group."
}

# =============================================================================
# Interactive Menu
# =============================================================================

function Show-InteractiveMenu {
    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Blue
        Write-Host "║         Remote Desktop Setup - Interactive Mode               ║" -ForegroundColor Blue
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Blue
        Write-Host ""
        
        # Show current status
        $rdpEnabled = $false
        try {
            $rdpEnabled = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -ErrorAction SilentlyContinue).fDenyTSConnections -eq 0
        } catch {}
        
        $statusText = if ($rdpEnabled) { "Enabled" } else { "Disabled" }
        $statusColor = if ($rdpEnabled) { "Green" } else { "Yellow" }
        Write-Host "  Current Status: " -NoNewline
        Write-Host $statusText -ForegroundColor $statusColor
        Write-Host ""
        
        Write-Host "  Setup & Configuration" -ForegroundColor White
        Write-Host "    1) Enable Remote Desktop"
        Write-Host "    2) Disable Remote Desktop"
        Write-Host ""
        Write-Host "  Security & Firewall" -ForegroundColor White
        Write-Host "    3) Apply security hardening"
        Write-Host "    4) Configure firewall"
        Write-Host ""
        Write-Host "  User Management" -ForegroundColor White
        Write-Host "    5) Manage Remote Desktop Users"
        Write-Host ""
        Write-Host "  Information" -ForegroundColor White
        Write-Host "    s) Show detailed status"
        Write-Host "    h) Show help"
        Write-Host ""
        Write-Host "    q) Quit"
        Write-Host ""
        $choice = Read-Host "  Select an option"
        
        switch ($choice) {
            '1' {
                Write-Host ""
                Enable-RemoteDesktop
                Write-Host ""
                Read-Host "Press Enter to continue..."
            }
            '2' {
                Write-Host ""
                Disable-RemoteDesktop
                Write-Host ""
                Read-Host "Press Enter to continue..."
            }
            '3' {
                Write-Host ""
                Set-RDPSecurity
                Write-Host ""
                Read-Host "Press Enter to continue..."
            }
            '4' {
                Write-Host ""
                Enable-RDPFirewall
                Write-Host ""
                Read-Host "Press Enter to continue..."
            }
            '5' {
                Write-Host ""
                Set-RDPUsers
                Write-Host ""
                Read-Host "Press Enter to continue..."
            }
            's' {
                Write-Host ""
                Get-RDPStatus
                Write-Host ""
                Read-Host "Press Enter to continue..."
            }
            'S' {
                Write-Host ""
                Get-RDPStatus
                Write-Host ""
                Read-Host "Press Enter to continue..."
            }
            'h' {
                Write-Host ""
                Show-Help
                Read-Host "Press Enter to continue..."
            }
            'H' {
                Write-Host ""
                Show-Help
                Read-Host "Press Enter to continue..."
            }
            'q' {
                Write-Host ""
                Write-Host "Goodbye!"
                return
            }
            'Q' {
                Write-Host ""
                Write-Host "Goodbye!"
                return
            }
            default {
                Write-Host ""
                Write-Err "Invalid option: $choice"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# =============================================================================
# Help
# =============================================================================

function Show-Help {
    Write-Host ""
    Write-Host "$($Script:Name) v$($Script:Version)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Configure Remote Desktop (RDP) on Windows with best practices."
    Write-Host ""
    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "    .\$($Script:Name).ps1                    # Launch interactive menu"
    Write-Host "    .\$($Script:Name).ps1 -Action <action>   # Run specific action"
    Write-Host ""
    Write-Host "ACTIONS:" -ForegroundColor Yellow
    Write-Host "    Enable      Enable Remote Desktop and configure firewall"
    Write-Host "    Disable     Disable Remote Desktop"
    Write-Host "    Status      Show current Remote Desktop configuration"
    Write-Host "    Security    Apply security hardening"
    Write-Host "    Firewall    Configure firewall rules only"
    Write-Host "    Users       Manage Remote Desktop Users group"
    Write-Host "    Menu        Launch interactive menu"
    Write-Host "    Help        Show this help message"
    Write-Host ""
    Write-Host "OPTIONS:" -ForegroundColor Yellow
    Write-Host "    -Force      Skip confirmation prompts"
    Write-Host "    -WhatIf     Show what would be done without executing"
    Write-Host ""
    Write-Host "INTERACTIVE MODE:" -ForegroundColor Yellow
    Write-Host "    Run without arguments to launch the interactive menu."
    Write-Host "    The menu provides a user-friendly interface to all features."
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host "    .\$($Script:Name).ps1                    # Interactive menu"
    Write-Host "    .\$($Script:Name).ps1 -Action Enable"
    Write-Host "    .\$($Script:Name).ps1 -Action Status"
    Write-Host "    .\$($Script:Name).ps1 -Action Security"
    Write-Host "    .\$($Script:Name).ps1 -Action Enable -WhatIf"
    Write-Host ""
    Write-Host "REQUIREMENTS:" -ForegroundColor Yellow
    Write-Host "    - Windows 10/11 Pro, Enterprise, or Server"
    Write-Host "    - Administrator privileges"
    Write-Host ""
    Write-Host "CONNECTING:" -ForegroundColor Yellow
    Write-Host "    After enabling, connect using Remote Desktop Client:"
    Write-Host "    - Windows: Press Win+R, type 'mstsc'"
    Write-Host "    - macOS: Microsoft Remote Desktop from App Store"
    Write-Host "    - Linux: Remmina, xfreerdp, or rdesktop"
    Write-Host ""
}

# =============================================================================
# Main
# =============================================================================

function Main {
    if ($Help) {
        Show-Help
        return
    }
    
    # Launch interactive menu if no action specified
    if ([string]::IsNullOrEmpty($Action)) {
        # Check if running interactively
        if ([Environment]::UserInteractive -and $Host.Name -eq 'ConsoleHost') {
            Show-InteractiveMenu
            return
        } else {
            Show-Help
            return
        }
    }
    
    switch ($Action) {
        'Enable' {
            Enable-RemoteDesktop
        }
        'Disable' {
            Disable-RemoteDesktop
        }
        'Status' {
            Get-RDPStatus
        }
        'Security' {
            Set-RDPSecurity
        }
        'Firewall' {
            Enable-RDPFirewall
        }
        'Users' {
            Set-RDPUsers
        }
        'Menu' {
            Show-InteractiveMenu
        }
        'Help' {
            Show-Help
        }
        default {
            Show-Help
        }
    }
}

# =============================================================================
# Entry Point
# =============================================================================

Main
