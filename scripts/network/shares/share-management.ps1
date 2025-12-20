<#
.SYNOPSIS
    Network Share Management - Manage network shares (SMB/CIFS) on Windows

.DESCRIPTION
    A comprehensive tool for managing network file shares on Windows.
    Supports mapping drives, credential management, share discovery,
    and persistent configurations.

.PARAMETER Command
    The command to execute: mount, unmount, add, remove, list, discover, scan, test, creds, status

.PARAMETER Source
    Network share path (e.g., \\server\share)

.PARAMETER Target
    Drive letter for mounting (e.g., Z)

.PARAMETER Name
    Share name for saved configurations

.PARAMETER Username
    Username for authentication

.PARAMETER Password
    Password for authentication (prefer prompts for security)

.PARAMETER Force
    Force operation

.PARAMETER Persistent
    Make mount persistent across reboots

.PARAMETER Interactive
    Run in interactive mode

.PARAMETER Json
    Output in JSON format

.EXAMPLE
    .\share-management.ps1 mount \\server\share Z

.EXAMPLE
    .\share-management.ps1 discover server.local

.EXAMPLE
    .\share-management.ps1 add -Name work -Source \\server\share -Target Z -Persistent

.EXAMPLE
    .\share-management.ps1 list

.NOTES
    Version: 1.0.0
    Author:  codefuturist
    License: MIT
#>

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [ValidateSet('mount', 'unmount', 'umount', 'add', 'remove', 'list', 'discover', 'scan', 'test', 'creds', 'status', 'health', 'help')]
    [string]$Command = 'list',

    [Parameter(Position = 1)]
    [string]$Source,

    [Parameter(Position = 2)]
    [string]$Target,

    [Alias('n')]
    [string]$Name,

    [Alias('u')]
    [string]$Username,

    [Alias('p')]
    [string]$Password,

    [Alias('f')]
    [switch]$Force,

    [switch]$Persistent,

    [Alias('i')]
    [switch]$Interactive,

    [switch]$Json,

    [switch]$Mounted,

    [switch]$Saved,

    # Open in Windows Explorer (like Finder on macOS)
    [Alias('Open')]
    [switch]$Explorer,

    # Subcommand for creds
    [string]$SubCommand,

    [switch]$Help,

    [switch]$Version
)

# =============================================================================
# Configuration
# =============================================================================

$ErrorActionPreference = 'Stop'
$Script:ScriptName = 'Network Share Management'
$Script:ScriptVersion = '1.0.0'

# =============================================================================
# Load RSR Module
# =============================================================================

$ModulePath = Join-Path $PSScriptRoot '../../lib/powershell/Modules/Shares.psm1'

if (Test-Path $ModulePath) {
    Import-Module $ModulePath -Force
}
else {
    Write-Error "RSR Shares module not found at $ModulePath"
    exit 1
}

# =============================================================================
# Help Functions
# =============================================================================

function Show-Help {
    $helpText = @"
$Script:ScriptName v$Script:ScriptVersion

Manage network file shares on Windows.

USAGE:
    .\share-management.ps1 <command> [options]

COMMANDS:
    mount               Mount a network share
    unmount, umount     Unmount a network share
    add                 Add and save a share configuration
    remove              Remove a saved share configuration
    list                List mounted and/or saved shares
    discover            Discover shares on a server
    scan                Scan network for file servers
    test                Test connectivity to a share
    creds               Manage credentials (set, get, delete, list)
    status              Show status of all shares
    health              Health check for mounted shares
    help                Show this help message

GLOBAL OPTIONS:
    -Name, -n           Share name for saved configurations
    -Source             Network share path (\\server\share)
    -Target             Drive letter (e.g., Z)
    -Username, -u       Username for authentication
    -Password, -p       Password (prefer prompts)
    -Force, -f          Force operation
    -Persistent         Make mount persistent
    -Explorer, -Open    Open share in Windows Explorer (native experience)
    -Interactive, -i    Interactive mode
    -Json               Output in JSON format
    -WhatIf             Show what would happen
    -Version            Show version

EXAMPLES:
    # Mount a share
    .\share-management.ps1 mount \\server\share Z

    # Open in Windows Explorer (like Finder on macOS)
    .\share-management.ps1 mount \\server\share -Explorer

    # Mount with credentials
    .\share-management.ps1 mount \\server\share Z -Username admin

    # Add a saved share
    .\share-management.ps1 add -Name work -Source \\server\share -Target Z -Persistent

    # Discover shares on a server
    .\share-management.ps1 discover fileserver.local

    # List all shares
    .\share-management.ps1 list

    # Store credentials
    .\share-management.ps1 creds set -Name work -Username admin
"@
    Write-Host $helpText
}

function Show-Version {
    Write-Host "$Script:ScriptName v$Script:ScriptVersion"
}

# =============================================================================
# Interactive Mode
# =============================================================================

function Start-InteractiveMount {
    Write-Host ""
    Write-Host "=== Mount Network Share ===" -ForegroundColor Cyan
    Write-Host ""

    # Get share path
    $source = Read-Host "Enter share path (e.g., \\server\share)"
    if (-not $source) {
        Write-Host "Cancelled" -ForegroundColor Yellow
        return
    }

    # Offer mount options
    Write-Host ""
    Write-Host "How would you like to access this share?" -ForegroundColor Cyan
    Write-Host "  1) Map to drive letter (e.g., Z:)" -ForegroundColor White
    Write-Host "  2) Open in Windows Explorer" -ForegroundColor White
    Write-Host "  3) Access via UNC path only (no mapping)" -ForegroundColor DarkGray
    Write-Host ""

    $mountChoice = Read-Host "Select option [1]"
    if (-not $mountChoice) { $mountChoice = "1" }

    switch ($mountChoice) {
        "2" {
            # Open in Explorer
            Write-Host ""
            Write-Host "Opening share in Windows Explorer..." -ForegroundColor Green
            Start-Process explorer.exe -ArgumentList $source
            Write-Host "Share opened. Windows will prompt for credentials if needed." -ForegroundColor DarkGray
            return
        }
        "3" {
            # Just test access
            Write-Host ""
            Write-Host "Testing UNC path access..." -ForegroundColor Cyan
            if (Test-Path $source) {
                Write-Host "Share is accessible at: $source" -ForegroundColor Green
            } else {
                Write-Host "Cannot access share. Check path and credentials." -ForegroundColor Red
            }
            return
        }
    }

    # Get drive letter
    $usedLetters = (Get-PSDrive -PSProvider FileSystem).Name
    $availableLetters = 'Z','Y','X','W','V','U','T','S','R','Q','P','O','N','M','L','K' | Where-Object { $_ -notin $usedLetters }

    Write-Host ""
    Write-Host "Available drive letters:" -ForegroundColor Cyan
    for ($i = 0; $i -lt [Math]::Min(5, $availableLetters.Count); $i++) {
        $letter = $availableLetters[$i]
        if ($i -eq 0) {
            Write-Host "  $($i + 1)) ${letter}: (recommended)" -ForegroundColor White
        } else {
            Write-Host "  $($i + 1)) ${letter}:" -ForegroundColor DarkGray
        }
    }
    Write-Host "  Or enter a specific letter (A-Z)" -ForegroundColor DarkGray
    Write-Host ""

    $targetInput = Read-Host "Drive letter [$($availableLetters[0])]"
    if (-not $targetInput) {
        $target = $availableLetters[0]
    } elseif ($targetInput -match '^[1-5]$') {
        $idx = [int]$targetInput - 1
        $target = $availableLetters[$idx]
    } else {
        $target = $targetInput.ToUpper().TrimEnd(':')
    }

    # Credentials
    Write-Host ""
    $useCreds = Read-Host "Authenticate with username/password? [y/N]"
    $cred = $null
    if ($useCreds -match '^[Yy]') {
        $cred = Get-Credential -Message "Enter credentials for $source"
    }

    # Persistent
    $makePersistent = Read-Host "Make persistent across reboots? [Y/n]"
    $persistent = -not ($makePersistent -match '^[Nn]')

    # Save configuration
    $saveName = Read-Host "Save configuration as (leave empty to skip)"

    Write-Host ""
    Write-Host "Configuration:" -ForegroundColor Cyan
    Write-Host "  Source:     $source"
    Write-Host "  Target:     ${target}:"
    Write-Host "  Persistent: $persistent"
    if ($saveName) {
        Write-Host "  Save as:    $saveName"
    }
    Write-Host ""

    $confirm = Read-Host "Proceed? [Y/n]"
    if ($confirm -match '^[Nn]') {
        Write-Host "Cancelled" -ForegroundColor Yellow
        return
    }

    # Execute mount
    $params = @{
        Source = $source
        DriveLetter = $target
        Persistent = $persistent
    }

    if ($cred) {
        $params['Credential'] = $cred
    }

    if ($saveName) {
        $params['Name'] = $saveName
    }

    Mount-RSRShare @params
}

function Start-InteractiveAdd {
    Write-Host ""
    Write-Host "=== Add Network Share Configuration ===" -ForegroundColor Cyan
    Write-Host ""

    $name = Read-Host "Configuration name"
    if (-not $name) {
        Write-Host "Name is required" -ForegroundColor Red
        return
    }

    $source = Read-Host "Share path (e.g., \\server\share)"
    if (-not $source) {
        Write-Host "Share path is required" -ForegroundColor Red
        return
    }

    $target = Read-Host "Drive letter"
    if ($target) {
        $target = $target.ToUpper().TrimEnd(':')
    }

    $makePersistent = Read-Host "Enable automount? [Y/n]"
    $automount = -not ($makePersistent -match '^[Nn]')

    $storeCreds = Read-Host "Store credentials? [y/N]"
    if ($storeCreds -match '^[Yy]') {
        $cred = Get-Credential -Message "Enter credentials for $source"
        Set-RSRShareCredential -Name $name -Credential $cred
    }

    Save-RSRShare -Name $name -Source $source -Target "${target}:" -Automount $automount
}

# =============================================================================
# Command Implementations
# =============================================================================

function Invoke-MountCommand {
    # Handle -Explorer option (open in Windows Explorer)
    if ($Explorer) {
        if (-not $Source) {
            Write-Host "Share source is required" -ForegroundColor Red
            Write-Host "Usage: .\share-management.ps1 mount \\server\share -Explorer"
            return
        }

        # Convert to UNC path if needed
        $uncPath = $Source
        if ($Source -match '^smb://') {
            $uncPath = $Source -replace '^smb://', '\\' -replace '/', '\'
        }

        Write-Host "Opening share in Windows Explorer..." -ForegroundColor Green
        Start-Process explorer.exe -ArgumentList $uncPath
        Write-Host "Share opened. Windows will prompt for credentials if needed." -ForegroundColor DarkGray
        Write-Host "Tip: Right-click and 'Map network drive' to create a permanent drive letter." -ForegroundColor DarkGray
        return
    }

    if ($Interactive -or (-not $Source)) {
        Start-InteractiveMount
        return
    }

    if (-not $Source) {
        Write-Host "Share source is required" -ForegroundColor Red
        Write-Host "Usage: .\share-management.ps1 mount <source> [drive-letter]"
        return
    }

    $params = @{
        Source = $Source
        Persistent = $Persistent
    }

    if ($Target) {
        $params['DriveLetter'] = $Target.ToUpper().TrimEnd(':')
    }

    if ($Name) {
        $params['Name'] = $Name
    }

    # Handle credentials
    if ($Username) {
        if ($Password) {
            $secPass = ConvertTo-SecureString $Password -AsPlainText -Force
            $cred = New-Object PSCredential($Username, $secPass)
        }
        else {
            $cred = Get-Credential -UserName $Username -Message "Enter password for $Username"
        }
        $params['Credential'] = $cred
    }
    elseif ($Name) {
        # Try to load saved credentials
        $cred = Get-RSRShareCredential -Name $Name
        if ($cred) {
            $params['Credential'] = $cred
        }
    }

    Mount-RSRShare @params
}

function Invoke-UnmountCommand {
    $targetDrive = if ($Source) { $Source } else { $Target }

    if (-not $targetDrive -and $Name) {
        # Look up from saved shares
        $saved = Get-RSRSavedShares -Name $Name
        if ($saved) {
            $targetDrive = $saved.target
        }
    }

    if (-not $targetDrive) {
        Write-Host "Drive letter or share name required" -ForegroundColor Red
        return
    }

    Dismount-RSRShare -DriveLetter $targetDrive -Force:$Force
}

function Invoke-AddCommand {
    if ($Interactive -or (-not $Name)) {
        Start-InteractiveAdd
        return
    }

    if (-not $Name) {
        Write-Host "Share name is required (-Name)" -ForegroundColor Red
        return
    }

    if (-not $Source) {
        Write-Host "Share source is required (-Source)" -ForegroundColor Red
        return
    }

    # Store credentials if provided
    if ($Username) {
        if ($Password) {
            $secPass = ConvertTo-SecureString $Password -AsPlainText -Force
            $cred = New-Object PSCredential($Username, $secPass)
        }
        else {
            $cred = Get-Credential -UserName $Username -Message "Enter password for $Username"
        }
        Set-RSRShareCredential -Name $Name -Credential $cred
    }

    Save-RSRShare -Name $Name -Source $Source -Target $Target -Automount $Persistent
}

function Invoke-RemoveCommand {
    if (-not $Name -and $Source) {
        $Name = $Source
    }

    if (-not $Name) {
        Write-Host "Share name is required" -ForegroundColor Red
        return
    }

    Remove-RSRSavedShare -Name $Name
}

function Invoke-ListCommand {
    $showMounted = $Mounted -or (-not $Mounted -and -not $Saved)
    $showSaved = $Saved -or (-not $Mounted -and -not $Saved)

    if ($Json) {
        $result = @{
            mounted = @()
            saved = @()
        }

        if ($showMounted) {
            $result.mounted = @(Get-RSRMountedShares)
        }

        if ($showSaved) {
            $result.saved = @(Get-RSRSavedShares)
        }

        $result | ConvertTo-Json -Depth 10
        return
    }

    if ($showMounted) {
        Write-Host ""
        Write-Host "=== Mounted Network Shares ===" -ForegroundColor Cyan
        Write-Host ""

        $mounted = Get-RSRMountedShares
        if ($mounted) {
            $mounted | Format-Table -Property @(
                @{ Label = 'Drive'; Expression = { $_.LocalPath } }
                @{ Label = 'Remote Path'; Expression = { $_.RemotePath } }
            ) -AutoSize
        }
        else {
            Write-Host "  No network shares currently mounted" -ForegroundColor DarkGray
        }
    }

    if ($showSaved) {
        Write-Host ""
        Write-Host "=== Saved Share Configurations ===" -ForegroundColor Cyan
        Write-Host ""

        $saved = Get-RSRSavedShares
        if ($saved) {
            $saved | ForEach-Object {
                $status = if (Test-Path "$($_.target)") { "●" } else { "○" }
                $statusColor = if (Test-Path "$($_.target)") { "Green" } else { "DarkGray" }

                Write-Host "  $status " -ForegroundColor $statusColor -NoNewline
                Write-Host "$($_.name)" -ForegroundColor White -NoNewline
                Write-Host " -> $($_.source)" -ForegroundColor DarkGray
                Write-Host "    Target: $($_.target), Automount: $($_.automount)" -ForegroundColor DarkGray
            }
        }
        else {
            Write-Host "  No saved shares. Use 'add' to save a share configuration." -ForegroundColor DarkGray
        }
        Write-Host ""
    }
}

function Invoke-DiscoverCommand {
    $server = if ($Source) { $Source } elseif ($Target) { $Target } else { $null }

    if (-not $server) {
        if ($Interactive) {
            $server = Read-Host "Enter server hostname or IP"
        }
        else {
            Write-Host "Server hostname or IP is required" -ForegroundColor Red
            return
        }
    }

    Write-Host ""
    Write-Host "=== Discovering shares on: $server ===" -ForegroundColor Cyan
    Write-Host ""

    $cred = $null
    if ($Username) {
        if ($Password) {
            $secPass = ConvertTo-SecureString $Password -AsPlainText -Force
            $cred = New-Object PSCredential($Username, $secPass)
        }
        else {
            $cred = Get-Credential -UserName $Username
        }
    }

    $shares = Find-RSRNetworkShares -Server $server -Credential $cred

    if ($shares) {
        if ($Json) {
            $shares | ConvertTo-Json -Depth 10
        }
        else {
            $shares | Format-Table -Property Name, Path, Description -AutoSize
        }
    }
    else {
        Write-Host "  No shares found (or access denied)" -ForegroundColor DarkGray
    }
}

function Invoke-ScanCommand {
    Write-Host ""
    Write-Host "=== Scanning Network for File Servers ===" -ForegroundColor Cyan
    Write-Host ""

    $servers = Search-RSRNetworkServers

    if ($servers) {
        Write-Host "Found servers:" -ForegroundColor Green
        $servers | ForEach-Object {
            Write-Host "  $_"
        }
        Write-Host ""
        Write-Host "Use '.\share-management.ps1 discover <server>' to list available shares" -ForegroundColor DarkGray
    }
    else {
        Write-Host "  No file servers found" -ForegroundColor DarkGray
    }
}

function Invoke-TestCommand {
    $sharePath = if ($Source) { $Source } else { $Target }

    if (-not $sharePath) {
        Write-Host "Share path is required" -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "=== Testing Share: $sharePath ===" -ForegroundColor Cyan
    Write-Host ""

    Test-RSRShareConnectivity -Source $sharePath
}

function Invoke-CredsCommand {
    $sub = if ($SubCommand) { $SubCommand } elseif ($Source) { $Source } else { 'list' }

    switch ($sub) {
        { $_ -in 'set', 'add', 'store' } {
            $credName = if ($Name) { $Name } elseif ($Target) { $Target } else { $null }

            if (-not $credName) {
                $credName = Read-Host "Share name"
            }

            if (-not $credName) {
                Write-Host "Share name is required" -ForegroundColor Red
                return
            }

            if ($Username) {
                if ($Password) {
                    $secPass = ConvertTo-SecureString $Password -AsPlainText -Force
                    $cred = New-Object PSCredential($Username, $secPass)
                }
                else {
                    $cred = Get-Credential -UserName $Username
                }
            }
            else {
                $cred = Get-Credential -Message "Enter credentials for '$credName'"
            }

            Set-RSRShareCredential -Name $credName -Credential $cred
        }

        { $_ -in 'get', 'show' } {
            $credName = if ($Name) { $Name } elseif ($Target) { $Target } else { $null }

            if (-not $credName) {
                Write-Host "Share name is required" -ForegroundColor Red
                return
            }

            $cred = Get-RSRShareCredential -Name $credName
            if ($cred) {
                Write-Host "Username: $($cred.UserName)"
                Write-Host "Password: ********"
            }
            else {
                Write-Host "No credentials stored for '$credName'" -ForegroundColor Yellow
            }
        }

        { $_ -in 'delete', 'remove', 'rm' } {
            $credName = if ($Name) { $Name } elseif ($Target) { $Target } else { $null }

            if (-not $credName) {
                Write-Host "Share name is required" -ForegroundColor Red
                return
            }

            Remove-RSRShareCredential -Name $credName
        }

        { $_ -in 'list', 'ls' } {
            Write-Host ""
            Write-Host "=== Stored Credentials ===" -ForegroundColor Cyan
            Write-Host ""

            $creds = Get-RSRShareCredentialList
            if ($creds) {
                $creds | Format-Table -Property Name, Username, Stored -AutoSize
            }
            else {
                Write-Host "  No credentials stored" -ForegroundColor DarkGray
            }
        }

        default {
            Write-Host "Unknown creds command: $sub" -ForegroundColor Red
            Write-Host "Available: set, get, delete, list"
        }
    }
}

function Invoke-StatusCommand {
    Invoke-ListCommand
}

function Invoke-HealthCommand {
    Write-Host ""
    Write-Host "=== Share Health Check ===" -ForegroundColor Cyan
    Write-Host ""

    $saved = Get-RSRSavedShares

    if (-not $saved) {
        Write-Host "  No saved shares to check" -ForegroundColor DarkGray
        return
    }

    foreach ($share in $saved) {
        Write-Host "  Checking $($share.name)... " -NoNewline

        $target = $share.target
        $source = $share.source

        if (Test-Path $target) {
            try {
                $null = Get-ChildItem $target -ErrorAction Stop | Select-Object -First 1
                Write-Host "● Healthy" -ForegroundColor Green
            }
            catch {
                Write-Host "⚠ Mounted but not accessible" -ForegroundColor Yellow
            }
        }
        else {
            # Check if server is reachable
            $parsed = Split-RSRSharePath -Path $source
            if ($parsed) {
                $ping = Test-Connection -ComputerName $parsed.Server -Count 1 -Quiet
                if ($ping) {
                    Write-Host "○ Not mounted (server reachable)" -ForegroundColor DarkGray
                }
                else {
                    Write-Host "✗ Not mounted (server unreachable)" -ForegroundColor Red
                }
            }
            else {
                Write-Host "○ Not mounted" -ForegroundColor DarkGray
            }
        }
    }
    Write-Host ""
}

# =============================================================================
# Main Entry Point
# =============================================================================

if ($Help -or $Command -eq 'help') {
    Show-Help
    exit 0
}

if ($Version) {
    Show-Version
    exit 0
}

switch ($Command) {
    'mount' { Invoke-MountCommand }
    { $_ -in 'unmount', 'umount' } { Invoke-UnmountCommand }
    'add' { Invoke-AddCommand }
    'remove' { Invoke-RemoveCommand }
    'list' { Invoke-ListCommand }
    'discover' { Invoke-DiscoverCommand }
    'scan' { Invoke-ScanCommand }
    'test' { Invoke-TestCommand }
    'creds' { Invoke-CredsCommand }
    'status' { Invoke-StatusCommand }
    'health' { Invoke-HealthCommand }
    default {
        Write-Host "Unknown command: $Command" -ForegroundColor Red
        Write-Host "Use --Help for usage information."
        exit 1
    }
}

