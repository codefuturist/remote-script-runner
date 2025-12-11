<#
.SYNOPSIS
    SSH Client Configuration Management for Windows

.DESCRIPTION
    Manage SSH client configuration, hosts, tunnels, and best practices on Windows.
    Provides feature parity with the Bash ssh-config.sh implementation.

.PARAMETER Command
    Management command (init, hosts, templates, tunnel, permissions, backup, restore)

.PARAMETER Arguments
    Arguments for the command

.EXAMPLE
    .\ssh-config.ps1 init

.EXAMPLE
    .\ssh-config.ps1 hosts add myserver

.EXAMPLE
    .\ssh-config.ps1 templates apply github

.EXAMPLE
    .\ssh-config.ps1 tunnel local 8080 myserver 80

.NOTES
    Version: 1.0.0
    Requires: PowerShell 5.1+, OpenSSH Client
    Author: RSR Team
#>

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Command,

    [Parameter(Position=1, ValueFromRemainingArguments)]
    [string[]]$Arguments
)

#Requires -Version 5.1

# =============================================================================
# Script Configuration
# =============================================================================

$ErrorActionPreference = 'Stop'
$Script:ScriptVersion = "1.0.0"
$Script:ScriptName = "SSH Client Configuration"
$Script:DryRun = $false
$Script:Verbose = $false
$Script:Force = $false

# SSH Paths (Windows-specific)
$Script:SSHUserDir = Join-Path $env:USERPROFILE ".ssh"
$Script:SSHConfig = Join-Path $Script:SSHUserDir "config"
$Script:SSHConfigD = Join-Path $Script:SSHUserDir "config.d"
$Script:SSHKeysDir = Join-Path $Script:SSHUserDir "keys"
$Script:SSHSocketsDir = Join-Path $Script:SSHUserDir "sockets"

# Templates directory
$Script:TemplatesDir = Join-Path $PSScriptRoot "templates"

# =============================================================================
# Import RSR Library
# =============================================================================

$rsrModulePath = Join-Path $PSScriptRoot "..\..\..\lib\powershell\RSR.psd1"
if (Test-Path $rsrModulePath) {
    Import-Module $rsrModulePath -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Logging Functions
# =============================================================================

function Write-SSHLog {
    param(
        [string]$Message,
        [ValidateSet('Info','Success','Warning','Error','Debug')]
        [string]$Level = 'Info'
    )

    if ($Level -eq 'Debug' -and -not $Script:Verbose) { return }

    # Use RSR logging if available
    if (Get-Command Write-RSRInfo -ErrorAction SilentlyContinue) {
        switch ($Level) {
            'Info'    { Write-RSRInfo $Message }
            'Success' { Write-RSROk $Message }
            'Warning' { Write-RSRWarn $Message }
            'Error'   { Write-RSRError $Message }
            'Debug'   { Write-RSRDebug $Message }
        }
        return
    }

    # Fallback to basic Write-Host
    $colors = @{
        'Info' = 'Cyan'
        'Success' = 'Green'
        'Warning' = 'Yellow'
        'Error' = 'Red'
        'Debug' = 'Gray'
    }

    Write-Host $Message -ForegroundColor $colors[$Level]
}

function Write-SSHHeader {
    param([string]$Title)
    
    if (Get-Command Write-RSRHeader -ErrorAction SilentlyContinue) {
        Write-RSRHeader $Title
    } else {
        Write-Host "`n═══ $Title ═══`n" -ForegroundColor Cyan
    }
}

# =============================================================================
# Helper Functions
# =============================================================================

function Test-SSHClientInstalled {
    $sshExe = Get-Command ssh.exe -ErrorAction SilentlyContinue
    return $null -ne $sshExe
}

function Ensure-SSHDirectory {
    if (-not (Test-Path $Script:SSHUserDir)) {
        Write-SSHLog "Creating SSH directory: $Script:SSHUserDir" -Level Info
        New-Item -ItemType Directory -Path $Script:SSHUserDir -Force | Out-Null
        
        # Set restrictive permissions (owner only)
        $acl = Get-Acl $Script:SSHUserDir
        $acl.SetAccessRuleProtection($true, $false)
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $identity.Name, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.SetAccessRule($rule)
        Set-Acl -Path $Script:SSHUserDir -AclObject $acl
    }
}

function Get-SSHHosts {
    $hosts = @()
    
    # Parse main config
    if (Test-Path $Script:SSHConfig) {
        Get-Content $Script:SSHConfig | ForEach-Object {
            if ($_ -match '^\s*Host\s+([^\*\s]+)') {
                $hosts += $matches[1]
            }
        }
    }
    
    # Parse config.d files
    if (Test-Path $Script:SSHConfigD) {
        Get-ChildItem -Path $Script:SSHConfigD -Filter "*.conf" | ForEach-Object {
            Get-Content $_.FullName | ForEach-Object {
                if ($_ -match '^\s*Host\s+([^\*\s]+)') {
                    $hosts += $matches[1]
                }
            }
        }
    }
    
    return $hosts | Sort-Object -Unique
}

function Get-SSHHostInfo {
    param([string]$HostName)
    
    $info = @{}
    
    try {
        # Use ssh -G to get configuration
        $output = & ssh.exe -G $HostName 2>$null
        if ($LASTEXITCODE -eq 0) {
            $output | ForEach-Object {
                if ($_ -match '^\s*(\S+)\s+(.+)$') {
                    $info[$matches[1]] = $matches[2]
                }
            }
        }
    } catch {
        Write-SSHLog "Failed to get host info: $_" -Level Debug
    }
    
    return $info
}

# =============================================================================
# Init Command
# =============================================================================

function Invoke-InitCommand {
    param(
        [switch]$Force,
        [switch]$Defaults,
        [switch]$Preview,
        [switch]$Minimal,
        [switch]$Secure
    )
    
    Write-SSHHeader "Initialize SSH Configuration"
    
    # Check if already initialized
    if ((Test-Path $Script:SSHConfig) -and -not $Force) {
        Write-SSHLog "SSH config already exists: $Script:SSHConfig" -Level Warning
        if (-not $Defaults) {
            $response = Read-Host "Overwrite existing configuration? [y/N]"
            if ($response -ne 'y' -and $response -ne 'Y') {
                Write-SSHLog "Cancelled" -Level Info
                return
            }
        } else {
            Write-SSHLog "Use -Force to overwrite" -Level Info
            return
        }
    }
    
    # Backup existing config
    if (Test-Path $Script:SSHConfig) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backup = "$Script:SSHConfig.backup.$timestamp"
        Write-SSHLog "Backing up existing config to: $backup" -Level Info
        Copy-Item $Script:SSHConfig $backup
    }
    
    # Create directory structure
    Ensure-SSHDirectory
    New-Item -ItemType Directory -Path $Script:SSHConfigD -Force | Out-Null
    New-Item -ItemType Directory -Path $Script:SSHKeysDir -Force | Out-Null
    New-Item -ItemType Directory -Path $Script:SSHSocketsDir -Force | Out-Null
    
    # Generate config content
    $configContent = @"
# RSR SSH Configuration - Best Practices
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# Managed by: rsr ssh-config

"@
    
    if (-not $Minimal) {
        $configContent += @"
# Global SSH Client Configuration
Host *
    # Security
    AddKeysToAgent yes
    IdentitiesOnly yes
    
"@
        
        if ($Secure) {
            $configContent += @"
    HashKnownHosts yes
    
    # Modern cryptography
    KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
    Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
    MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

"@
        }
        
        $configContent += @"
    # Connection stability
    ServerAliveInterval 60
    ServerAliveCountMax 3
    TCPKeepAlive yes
    
    # Convenience
    Compression yes

"@
    }
    
    $configContent += @"
# Include modular host configurations
Include config.d/*

"@
    
    if ($Preview) {
        Write-Host "`nPreview of ${Script:SSHConfig}:" -ForegroundColor Cyan
        Write-Host "────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host $configContent
        Write-Host "────────────────────────────────────────" -ForegroundColor DarkGray
        return
    }
    
    # Write config
    if (-not $Script:DryRun) {
        Set-Content -Path $Script:SSHConfig -Value $configContent -Force
        
        Write-SSHLog "SSH configuration initialized" -Level Success
        Write-Host "`nCreated:" -ForegroundColor White
        Write-Host "  ✓ $Script:SSHConfig" -ForegroundColor Green
        Write-Host "  ✓ $Script:SSHConfigD\" -ForegroundColor Green
        Write-Host "  ✓ $Script:SSHKeysDir\" -ForegroundColor Green
        Write-Host "  ✓ $Script:SSHSocketsDir\" -ForegroundColor Green
        
        if (-not $Minimal) {
            Write-Host "`nFeatures enabled:" -ForegroundColor White
            Write-Host "  ✓ SSH agent key caching" -ForegroundColor Green
            Write-Host "  ✓ Server keep-alive" -ForegroundColor Green
            if ($Secure) {
                Write-Host "  ✓ Modern cryptography" -ForegroundColor Green
            }
        }
        
        Write-Host "`nNext steps:" -ForegroundColor DarkGray
        Write-Host "  • Add hosts: ssh-config hosts add" -ForegroundColor Cyan
        Write-Host "  • Apply templates: ssh-config templates list" -ForegroundColor Cyan
        Write-Host "  • Check permissions: ssh-config permissions" -ForegroundColor Cyan
    } else {
        Write-SSHLog "[DRY RUN] Would create SSH configuration" -Level Info
    }
}

# =============================================================================
# Hosts Command
# =============================================================================

function Invoke-HostsCommand {
    param(
        [string]$Action,
        [string[]]$Args
    )
    
    switch ($Action) {
        { $_ -in 'list', 'ls', '' } { Invoke-HostsList }
        { $_ -in 'add', 'new' } { Invoke-HostsAdd -Args $Args }
        'edit' { Invoke-HostsEdit -Args $Args }
        { $_ -in 'remove', 'rm', 'delete' } { Invoke-HostsRemove -Args $Args }
        'show' { Invoke-HostsShow -Args $Args }
        'test' { Invoke-HostsTest -Args $Args }
        default {
            Write-SSHLog "Unknown action: $Action" -Level Error
            Write-SSHLog "Use 'ssh-config hosts --help' for usage" -Level Info
        }
    }
}

function Invoke-HostsList {
    Write-SSHHeader "Configured SSH Hosts"
    
    $hosts = Get-SSHHosts
    
    if ($hosts.Count -eq 0) {
        Write-Host "No hosts configured yet" -ForegroundColor DarkGray
        Write-Host "`nAdd hosts with: ssh-config hosts add" -ForegroundColor Cyan
        return
    }
    
    # Table header
    $format = "{0,-20} {1,-15} {2,-25} {3,-6} {4}"
    Write-Host ($format -f "HOST", "USER", "HOSTNAME", "PORT", "KEY") -ForegroundColor White
    Write-Host ("─" * 80) -ForegroundColor DarkGray
    
    foreach ($host in $hosts) {
        $info = Get-SSHHostInfo $host
        
        $hostname = if ($info['hostname']) { $info['hostname'] } else { '-' }
        $user = if ($info['user']) { $info['user'] } else { '-' }
        $port = if ($info['port']) { $info['port'] } else { '22' }
        $identity = if ($info['identityfile']) { 
            Split-Path -Leaf $info['identityfile'] 
        } else { 
            '-' 
        }
        
        Write-Host ($format -f $host, $user, $hostname, $port, $identity)
    }
    
    Write-Host "`n$($hosts.Count) host(s) configured" -ForegroundColor DarkGray
}

function Invoke-HostsAdd {
    param([string[]]$Args)
    
    # Parse arguments
    $hostAlias = $Args[0]
    $hostname = $null
    $user = $null
    $port = '22'
    $identity = $null
    $jumpHost = $null
    $interactive = $true
    
    for ($i = 1; $i -lt $Args.Count; $i += 2) {
        switch ($Args[$i]) {
            '--hostname' { $hostname = $Args[$i+1] }
            '--user' { $user = $Args[$i+1] }
            '--port' { $port = $Args[$i+1] }
            '--key' { $identity = $Args[$i+1] }
            '--jump' { $jumpHost = $Args[$i+1] }
            '--non-interactive' { $interactive = $false; $i-- }
        }
    }
    
    if (-not $hostAlias) {
        Write-SSHLog "Host alias is required" -Level Error
        Write-SSHLog "Usage: ssh-config hosts add HOST [OPTIONS]" -Level Info
        return
    }
    
    Write-SSHHeader "Add SSH Host"
    
    # Check if host already exists
    $existingHosts = Get-SSHHosts
    if ($existingHosts -contains $hostAlias) {
        Write-SSHLog "Host '$hostAlias' already exists" -Level Error
        Write-SSHLog "Use 'ssh-config hosts edit $hostAlias' to modify" -Level Info
        return
    }
    
    # Interactive wizard
    if ($interactive -and -not $hostname) {
        Write-Host "Host alias: " -NoNewline -ForegroundColor White
        Write-Host $hostAlias -ForegroundColor Green
        Write-Host ""
        
        $hostname = Read-Host "Hostname (IP or domain)"
        if (-not $hostname) { $hostname = $hostAlias }
        
        $user = Read-Host "Username [$env:USERNAME]"
        if (-not $user) { $user = $env:USERNAME }
        
        $portInput = Read-Host "Port [22]"
        if ($portInput) { $port = $portInput }
        
        $identity = Read-Host "Identity file [auto-detect]"
        $jumpHost = Read-Host "Jump host (optional)"
        Write-Host ""
    }
    
    # Validate required fields
    if (-not $hostname) { $hostname = $hostAlias }
    if (-not $user) { $user = $env:USERNAME }
    
    # Generate config
    Ensure-SSHDirectory
    New-Item -ItemType Directory -Path $Script:SSHConfigD -Force | Out-Null
    
    $configFile = Join-Path $Script:SSHConfigD "$hostAlias.conf"
    $configContent = @"
# Host: $hostAlias
# Added: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

Host $hostAlias
    HostName $hostname
    User $user
    Port $port

"@
    
    if ($identity) {
        $configContent += "    IdentityFile $identity`n"
    }
    
    if ($jumpHost) {
        $configContent += "    ProxyJump $jumpHost`n"
    }
    
    if (-not $Script:DryRun) {
        Set-Content -Path $configFile -Value $configContent -Force
        Write-SSHLog "Host '$hostAlias' added to $configFile" -Level Success
        
        # Test connection
        if ($interactive) {
            Write-Host ""
            $response = Read-Host "Test connection now? [Y/n]"
            if ($response -ne 'n' -and $response -ne 'N') {
                Invoke-HostsTest -Args @($hostAlias)
            }
        }
    } else {
        Write-SSHLog "[DRY RUN] Would add host '$hostAlias'" -Level Info
        Write-Host $configContent
    }
}

function Invoke-HostsRemove {
    param([string[]]$Args)
    
    $hostAlias = $Args[0]
    
    if (-not $hostAlias) {
        Write-SSHLog "Host is required" -Level Error
        Write-SSHLog "Usage: ssh-config hosts remove HOST" -Level Info
        return
    }
    
    Write-SSHHeader "Remove SSH Host"
    
    $configFile = Join-Path $Script:SSHConfigD "$hostAlias.conf"
    
    if (-not (Test-Path $configFile)) {
        Write-SSHLog "Host '$hostAlias' not found" -Level Error
        return
    }
    
    Write-Host "Removing host: " -NoNewline
    Write-Host $hostAlias -ForegroundColor White
    Write-Host "File: " -NoNewline -ForegroundColor DarkGray
    Write-Host $configFile -ForegroundColor DarkGray
    Write-Host ""
    
    if (-not $Script:DryRun) {
        $response = Read-Host "Are you sure? [y/N]"
        if ($response -eq 'y' -or $response -eq 'Y') {
            Remove-Item $configFile -Force
            Write-SSHLog "Host '$hostAlias' removed" -Level Success
        } else {
            Write-SSHLog "Cancelled" -Level Info
        }
    } else {
        Write-SSHLog "[DRY RUN] Would remove host '$hostAlias'" -Level Info
    }
}

function Invoke-HostsShow {
    param([string[]]$Args)
    
    $hostAlias = $Args[0]
    
    if (-not $hostAlias) {
        Write-SSHLog "Host is required" -Level Error
        Write-SSHLog "Usage: ssh-config hosts show HOST" -Level Info
        return
    }
    
    Write-SSHHeader "SSH Host Configuration: $hostAlias"
    
    $info = Get-SSHHostInfo $hostAlias
    
    if ($info.Count -eq 0) {
        Write-SSHLog "Host '$hostAlias' not found or SSH error" -Level Error
        return
    }
    
    $info.GetEnumerator() | Sort-Object Name | Select-Object -First 20 | ForEach-Object {
        Write-Host "$($_.Key) $($_.Value)"
    }
}

function Invoke-HostsTest {
    param([string[]]$Args)
    
    $hostAlias = $Args[0]
    
    if (-not $hostAlias) {
        Write-SSHLog "Host is required" -Level Error
        Write-SSHLog "Usage: ssh-config hosts test HOST" -Level Info
        return
    }
    
    Write-SSHHeader "Test SSH Connection: $hostAlias"
    
    $info = Get-SSHHostInfo $hostAlias
    
    $hostname = if ($info['hostname']) { $info['hostname'] } else { $hostAlias }
    $user = if ($info['user']) { $info['user'] } else { $env:USERNAME }
    $port = if ($info['port']) { $info['port'] } else { '22' }
    
    Write-Host "Testing connection to: " -NoNewline
    Write-Host "${user}@${hostname}:${port}" -ForegroundColor White
    Write-Host ""
    
    try {
        $result = & ssh.exe -o BatchMode=yes -o ConnectTimeout=5 $hostAlias exit 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-SSHLog "Connection successful" -Level Success
        } else {
            Write-SSHLog "Connection failed" -Level Error
            Write-Host "`nTroubleshooting:" -ForegroundColor DarkGray
            Write-Host "  • Check that the host is reachable" -ForegroundColor White
            Write-Host "  • Verify SSH keys are set up: ssh-config hosts show $hostAlias" -ForegroundColor Cyan
            Write-Host "  • Test manually: ssh -v $hostAlias" -ForegroundColor Cyan
        }
    } catch {
        Write-SSHLog "Connection failed: $_" -Level Error
    }
}

function Invoke-HostsEdit {
    param([string[]]$Args)
    
    $hostAlias = $Args[0]
    
    if (-not $hostAlias) {
        Write-SSHLog "Host is required" -Level Error
        Write-SSHLog "Usage: ssh-config hosts edit HOST" -Level Info
        return
    }
    
    $configFile = Join-Path $Script:SSHConfigD "$hostAlias.conf"
    
    if (-not (Test-Path $configFile)) {
        Write-SSHLog "Host '$hostAlias' not found" -Level Error
        return
    }
    
    Write-SSHHeader "Edit SSH Host: $hostAlias"
    Write-Host "Opening in editor: notepad" -ForegroundColor White
    Write-Host ""
    
    & notepad.exe $configFile
    
    Write-SSHLog "Host configuration updated" -Level Success
}

# =============================================================================
# Templates Command
# =============================================================================

function Invoke-TemplatesCommand {
    param(
        [string]$Action,
        [string[]]$Args
    )
    
    switch ($Action) {
        { $_ -in 'list', 'ls', '' } { Invoke-TemplatesList }
        'apply' { Invoke-TemplatesApply -Args $Args }
        default {
            Write-SSHLog "Unknown action: $Action" -Level Error
            Write-SSHLog "Use 'ssh-config templates --help' for usage" -Level Info
        }
    }
}

function Invoke-TemplatesList {
    Write-SSHHeader "Available SSH Templates"
    
    if (-not (Test-Path $Script:TemplatesDir)) {
        Write-Host "No templates available yet" -ForegroundColor DarkGray
        return
    }
    
    $format = "{0,-15} {1}"
    Write-Host ($format -f "TEMPLATE", "DESCRIPTION") -ForegroundColor White
    Write-Host ("─" * 60) -ForegroundColor DarkGray
    
    Get-ChildItem -Path $Script:TemplatesDir -Filter "*.conf" | ForEach-Object {
        $name = $_.BaseName
        $desc = Get-Content $_.FullName | Where-Object { $_ -match '^#' } | Select-Object -First 1
        $desc = if ($desc) { $desc -replace '^#\s*', '' } else { "SSH configuration for $name" }
        
        Write-Host ($format -f $name, $desc)
    }
}

function Invoke-TemplatesApply {
    param([string[]]$Args)
    
    $templateName = $Args[0]
    
    if (-not $templateName) {
        Write-SSHLog "Template name is required" -Level Error
        Write-SSHLog "Usage: ssh-config templates apply TEMPLATE" -Level Info
        return
    }
    
    $templateFile = Join-Path $Script:TemplatesDir "$templateName.conf"
    
    if (-not (Test-Path $templateFile)) {
        Write-SSHLog "Template '$templateName' not found" -Level Error
        Write-SSHLog "Available templates: ssh-config templates list" -Level Info
        return
    }
    
    Write-SSHHeader "Apply Template: $templateName"
    
    Ensure-SSHDirectory
    New-Item -ItemType Directory -Path $Script:SSHConfigD -Force | Out-Null
    
    $outputFile = Join-Path $Script:SSHConfigD "$templateName.conf"
    
    if (Test-Path $outputFile) {
        Write-SSHLog "Template '$templateName' already applied" -Level Warning
        $response = Read-Host "Overwrite? [y/N]"
        if ($response -ne 'y' -and $response -ne 'Y') {
            return
        }
    }
    
    if (-not $Script:DryRun) {
        Copy-Item $templateFile $outputFile -Force
        Write-SSHLog "Template applied to $outputFile" -Level Success
        Write-Host "`nReview and customize:" -ForegroundColor DarkGray
        Write-Host "  ssh-config hosts edit $templateName" -ForegroundColor Cyan
    } else {
        Write-SSHLog "[DRY RUN] Would apply template '$templateName'" -Level Info
    }
}

# =============================================================================
# Permissions Command
# =============================================================================

function Invoke-PermissionsCommand {
    param(
        [switch]$Fix,
        [switch]$Strict
    )
    
    Write-SSHHeader "SSH Permissions Audit"
    
    $issues = 0
    $checks = 0
    
    function Check-Permission {
        param(
            [string]$Path,
            [string]$Name,
            [string]$Why
        )
        
        $Script:checks++
        
        if (-not (Test-Path $Path)) {
            Write-Host "⊘ " -NoNewline -ForegroundColor DarkGray
            Write-Host "$Name (not found)" -ForegroundColor DarkGray
            return
        }
        
        # Windows permissions check - ensure only owner has access
        $acl = Get-Acl $Path
        $owner = $acl.Owner
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        
        $hasCorrectPerms = $true
        
        # Check if only owner has permissions
        foreach ($access in $acl.Access) {
            if ($access.IdentityReference.Value -ne $owner -and 
                $access.IdentityReference.Value -notmatch 'SYSTEM|Administrators') {
                $hasCorrectPerms = $false
                break
            }
        }
        
        if ($hasCorrectPerms) {
            Write-Host "✓ " -NoNewline -ForegroundColor Green
            Write-Host $Name
        } else {
            Write-Host "✗ " -NoNewline -ForegroundColor Red
            Write-Host "$Name " -NoNewline -ForegroundColor Yellow
            Write-Host "→ should be owner-only" -ForegroundColor Green
            if ($Why) {
                Write-Host "  $Why" -ForegroundColor DarkGray
            }
            $Script:issues++
            
            if ($Fix) {
                try {
                    $acl = Get-Acl $Path
                    $acl.SetAccessRuleProtection($true, $false)
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        $currentUser, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
                    )
                    $acl.SetAccessRule($rule)
                    Set-Acl -Path $Path -AclObject $acl
                    Write-SSHLog "  Fixed: $Path" -Level Success
                } catch {
                    Write-SSHLog "  Failed to fix: $_" -Level Error
                }
            }
        }
    }
    
    # Check main directory
    Check-Permission $Script:SSHUserDir ".ssh\" "Directory must not be accessible by others"
    
    # Check config files
    Check-Permission $Script:SSHConfig ".ssh\config" "Config file must not be readable by others"
    
    $knownHosts = Join-Path $Script:SSHUserDir "known_hosts"
    if (Test-Path $knownHosts) {
        Check-Permission $knownHosts ".ssh\known_hosts" "Known hosts file"
    }
    
    # Check config.d
    if (Test-Path $Script:SSHConfigD) {
        Check-Permission $Script:SSHConfigD ".ssh\config.d\" "Config directory must not be accessible by others"
        
        Get-ChildItem -Path $Script:SSHConfigD -Filter "*.conf" | ForEach-Object {
            Check-Permission $_.FullName ".ssh\config.d\$($_.Name)" "Config files must not be readable by others"
        }
    }
    
    # Check private keys
    Get-ChildItem -Path $Script:SSHUserDir -Filter "id_*" -ErrorAction SilentlyContinue | Where-Object {
        $_.Extension -ne '.pub'
    } | ForEach-Object {
        Check-Permission $_.FullName ".ssh\$($_.Name)" "Private keys must not be readable by others"
    }
    
    # Summary
    Write-Host ""
    if ($issues -eq 0) {
        Write-SSHLog "All permissions are correct ($checks checks)" -Level Success
    } else {
        Write-SSHLog "$issues issue(s) found in $checks checks" -Level Warning
        if (-not $Fix) {
            Write-Host "`nFix with: ssh-config permissions -Fix" -ForegroundColor Cyan
        }
    }
}

# =============================================================================
# Backup/Restore Commands
# =============================================================================

function Invoke-BackupCommand {
    param(
        [switch]$Encrypt,
        [string]$Output
    )
    
    Write-SSHHeader "Backup SSH Configuration"
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    if (-not $Output) {
        $Output = Join-Path $env:USERPROFILE "Documents\ssh-backup-$timestamp.zip"
    }
    
    Write-SSHLog "Creating backup of $Script:SSHUserDir" -Level Info
    
    if (-not $Script:DryRun) {
        # Create zip archive
        Compress-Archive -Path $Script:SSHUserDir -DestinationPath $Output -Force
        
        $size = (Get-Item $Output).Length
        $sizeKB = [math]::Round($size / 1KB, 1)
        
        Write-SSHLog "Backup created: $Output" -Level Success
        Write-Host "  Size: $sizeKB KB" -ForegroundColor White
        
        if ($Encrypt) {
            Write-SSHLog "Note: Encryption requires manual GPG setup on Windows" -Level Warning
            Write-Host "  Consider using Windows EFS or BitLocker for encryption" -ForegroundColor Yellow
        }
    } else {
        Write-SSHLog "[DRY RUN] Would create backup at $Output" -Level Info
    }
}

function Invoke-RestoreCommand {
    param([string]$BackupFile)
    
    if (-not $BackupFile) {
        Write-SSHLog "Backup file is required" -Level Error
        Write-SSHLog "Usage: ssh-config restore FILE" -Level Info
        return
    }
    
    if (-not (Test-Path $BackupFile)) {
        Write-SSHLog "Backup file not found: $BackupFile" -Level Error
        return
    }
    
    Write-SSHHeader "Restore SSH Configuration"
    
    Write-SSHLog "This will overwrite your current SSH configuration!" -Level Warning
    Write-Host ""
    $response = Read-Host "Continue? [y/N]"
    
    if ($response -ne 'y' -and $response -ne 'Y') {
        Write-SSHLog "Cancelled" -Level Info
        return
    }
    
    # Backup current config
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $currentBackup = "$Script:SSHUserDir.backup.$timestamp"
    Write-SSHLog "Backing up current config to: $currentBackup" -Level Info
    
    if (Test-Path $Script:SSHUserDir) {
        Move-Item $Script:SSHUserDir $currentBackup -Force
    }
    
    # Restore
    if (-not $Script:DryRun) {
        Expand-Archive -Path $BackupFile -DestinationPath (Split-Path $Script:SSHUserDir) -Force
        Write-SSHLog "SSH configuration restored" -Level Success
        
        # Fix permissions
        Invoke-PermissionsCommand -Fix
    } else {
        Write-SSHLog "[DRY RUN] Would restore from $BackupFile" -Level Info
    }
}

# =============================================================================
# Tunnel Command (Windows-specific)
# =============================================================================

function Invoke-TunnelCommand {
    param(
        [string]$Action,
        [string[]]$Args
    )
    
    switch ($Action) {
        { $_ -in 'local', 'l' } { Invoke-TunnelLocal -Args $Args }
        { $_ -in 'dynamic', 'd' } { Invoke-TunnelDynamic -Args $Args }
        { $_ -in 'list', 'ls', '' } { Invoke-TunnelList }
        'stop' { Invoke-TunnelStop -Args $Args }
        default {
            Write-SSHLog "Unknown action: $Action" -Level Error
            Write-SSHLog "Note: Remote forwarding requires SSH server on Windows" -Level Info
        }
    }
}

function Invoke-TunnelLocal {
    param([string[]]$Args)
    
    if ($Args.Count -lt 3) {
        Write-SSHLog "Usage: ssh-config tunnel local PORT HOST REMOTE_PORT" -Level Error
        return
    }
    
    $localPort = $Args[0]
    $host = $Args[1]
    $remotePort = $Args[2]
    
    Write-SSHHeader "Local Port Forward"
    
    Write-Host "Creating tunnel: " -NoNewline
    Write-Host "localhost:$localPort" -ForegroundColor White -NoNewline
    Write-Host " → " -NoNewline
    Write-Host "${host}:${remotePort}" -ForegroundColor White
    
    if (-not $Script:DryRun) {
        Start-Process ssh.exe -ArgumentList "-f -N -L ${localPort}:localhost:${remotePort} $host" -WindowStyle Hidden
        
        Write-SSHLog "Tunnel established" -Level Success
        Write-Host "`nAccess at: http://localhost:$localPort" -ForegroundColor Cyan
        Write-Host "Stop with: ssh-config tunnel stop all" -ForegroundColor Cyan
    } else {
        Write-SSHLog "[DRY RUN] Would create tunnel" -Level Info
    }
}

function Invoke-TunnelDynamic {
    param([string[]]$Args)
    
    if ($Args.Count -lt 2) {
        Write-SSHLog "Usage: ssh-config tunnel dynamic PORT HOST" -Level Error
        return
    }
    
    $localPort = $Args[0]
    $host = $Args[1]
    
    Write-SSHHeader "Dynamic SOCKS Proxy"
    
    Write-Host "Creating SOCKS5 proxy on: " -NoNewline
    Write-Host "localhost:$localPort" -ForegroundColor White
    
    if (-not $Script:DryRun) {
        Start-Process ssh.exe -ArgumentList "-f -N -D $localPort $host" -WindowStyle Hidden
        
        Write-SSHLog "SOCKS proxy established" -Level Success
        Write-Host "`nConfigure applications to use:" -ForegroundColor White
        Write-Host "  SOCKS5 proxy: localhost:$localPort" -ForegroundColor Cyan
    } else {
        Write-SSHLog "[DRY RUN] Would create SOCKS proxy" -Level Info
    }
}

function Invoke-TunnelList {
    Write-SSHHeader "Active SSH Tunnels"
    
    $sshProcesses = Get-Process -Name ssh -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -match '-[fN]'
    }
    
    if ($sshProcesses.Count -eq 0) {
        Write-Host "No active tunnels" -ForegroundColor DarkGray
        return
    }
    
    $format = "{0,-8} {1}"
    Write-Host ($format -f "PID", "COMMAND") -ForegroundColor White
    Write-Host ("─" * 60) -ForegroundColor DarkGray
    
    $sshProcesses | ForEach-Object {
        Write-Host ($format -f $_.Id, $_.CommandLine)
    }
}

function Invoke-TunnelStop {
    param([string[]]$Args)
    
    $target = if ($Args.Count -gt 0) { $Args[0] } else { 'all' }
    
    if ($target -eq 'all') {
        Write-SSHHeader "Stop All SSH Tunnels"
        
        $sshProcesses = Get-Process -Name ssh -ErrorAction SilentlyContinue | Where-Object {
            $_.CommandLine -match '-[fN]'
        }
        
        if ($sshProcesses.Count -eq 0) {
            Write-SSHLog "No active tunnels" -Level Info
            return
        }
        
        if (-not $Script:DryRun) {
            $sshProcesses | ForEach-Object {
                Write-SSHLog "Stopping tunnel $($_.Id)" -Level Info
                Stop-Process -Id $_.Id -Force
                Write-SSHLog "Stopped" -Level Success
            }
        } else {
            Write-SSHLog "[DRY RUN] Would stop all tunnels" -Level Info
        }
    } else {
        Write-SSHHeader "Stop SSH Tunnel"
        
        if (-not $Script:DryRun) {
            try {
                Stop-Process -Id $target -Force
                Write-SSHLog "Tunnel $target stopped" -Level Success
            } catch {
                Write-SSHLog "Failed to stop tunnel: $_" -Level Error
            }
        } else {
            Write-SSHLog "[DRY RUN] Would stop tunnel $target" -Level Info
        }
    }
}

# =============================================================================
# Help Function
# =============================================================================

function Show-Help {
    Write-Host @"

$Script:ScriptName v$Script:ScriptVersion

Manage SSH client configuration, hosts, tunnels, and best practices.

Usage:
    .\ssh-config.ps1 <subcommand> [OPTIONS]

Subcommands:

  Setup & Configuration:
    init, setup           Initialize SSH config with best practices
    permissions, perms    Audit and fix SSH directory permissions

  Host Management:
    hosts, host           Manage SSH host configurations
      list, ls            List configured hosts
      add HOST            Add new host configuration
      edit HOST           Edit existing host configuration
      remove HOST         Remove host configuration
      show HOST           Show full config for a host
      test HOST           Test connection to configured host

  Templates:
    templates, template   Pre-built SSH configurations
      list                List available templates
      apply TEMPLATE      Apply a template configuration

  Tunnel Management:
    tunnel, tun           SSH tunneling and port forwarding
      local PORT HOST REMOTE_PORT    Local port forward
      dynamic PORT HOST              SOCKS proxy
      list                List active tunnels
      stop [ID|all]       Stop tunnel(s)

  Backup & Restore:
    backup                Backup entire .ssh\ directory
    restore FILE          Restore from backup

Global Options:
    -Verbose              Enable verbose output
    -DryRun               Show what would be done
    -Force                Force operation (skip confirmations)

Examples:
    # Initialize SSH with best practices
    .\ssh-config.ps1 init

    # Add a new host
    .\ssh-config.ps1 hosts add myserver

    # Apply GitHub template
    .\ssh-config.ps1 templates apply github

    # Create local port forward
    .\ssh-config.ps1 tunnel local 8080 myserver 80

    # Fix permissions
    .\ssh-config.ps1 permissions -Fix

"@ -ForegroundColor Cyan
}

# =============================================================================
# Main Entry Point
# =============================================================================

function Main {
    # Parse global flags from Arguments
    $i = 0
    while ($i -lt $Arguments.Count) {
        switch ($Arguments[$i]) {
            '-v' { $Script:Verbose = $true; $i++ }
            '--verbose' { $Script:Verbose = $true; $i++ }
            '-d' { $Script:DryRun = $true; $i++ }
            '--dry-run' { $Script:DryRun = $true; $i++ }
            '--force' { $Script:Force = $true; $i++ }
            '-h' { Show-Help; return }
            '--help' { Show-Help; return }
            default { break }
        }
        if ($Arguments[$i] -notmatch '^-') { break }
    }
    
    # Remove processed flags
    if ($i -gt 0) {
        $Arguments = $Arguments[$i..($Arguments.Count-1)]
    }
    
    # Check SSH client
    if (-not (Test-SSHClientInstalled)) {
        Write-SSHLog "OpenSSH client not found" -Level Error
        Write-SSHLog "Install with: Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0" -Level Info
        return
    }
    
    if (-not $Command) {
        Show-Help
        return
    }
    
    # Route to subcommand
    switch ($Command) {
        { $_ -in 'init', 'setup' } {
            $params = @{}
            for ($i = 0; $i -lt $Arguments.Count; $i++) {
                switch ($Arguments[$i]) {
                    '--force' { $params['Force'] = $true }
                    '--defaults' { $params['Defaults'] = $true }
                    '--preview' { $params['Preview'] = $true }
                    '--minimal' { $params['Minimal'] = $true }
                    '--secure' { $params['Secure'] = $true }
                }
            }
            Invoke-InitCommand @params
        }
        { $_ -in 'hosts', 'host', 'h' } {
            $action = if ($Arguments.Count -gt 0) { $Arguments[0] } else { '' }
            $args = if ($Arguments.Count -gt 1) { $Arguments[1..($Arguments.Count-1)] } else { @() }
            Invoke-HostsCommand -Action $action -Args $args
        }
        { $_ -in 'templates', 'template', 't' } {
            $action = if ($Arguments.Count -gt 0) { $Arguments[0] } else { '' }
            $args = if ($Arguments.Count -gt 1) { $Arguments[1..($Arguments.Count-1)] } else { @() }
            Invoke-TemplatesCommand -Action $action -Args $args
        }
        { $_ -in 'tunnel', 'tun' } {
            $action = if ($Arguments.Count -gt 0) { $Arguments[0] } else { '' }
            $args = if ($Arguments.Count -gt 1) { $Arguments[1..($Arguments.Count-1)] } else { @() }
            Invoke-TunnelCommand -Action $action -Args $args
        }
        { $_ -in 'permissions', 'perms', 'p' } {
            $params = @{}
            for ($i = 0; $i -lt $Arguments.Count; $i++) {
                switch ($Arguments[$i]) {
                    '--fix' { $params['Fix'] = $true }
                    '-Fix' { $params['Fix'] = $true }
                    '--strict' { $params['Strict'] = $true }
                }
            }
            Invoke-PermissionsCommand @params
        }
        'backup' {
            $params = @{}
            for ($i = 0; $i -lt $Arguments.Count; $i++) {
                switch ($Arguments[$i]) {
                    '--encrypt' { $params['Encrypt'] = $true }
                    { $_ -in '--output', '-o' } { $params['Output'] = $Arguments[++$i] }
                }
            }
            Invoke-BackupCommand @params
        }
        'restore' {
            Invoke-RestoreCommand -BackupFile $Arguments[0]
        }
        default {
            Write-SSHLog "Unknown subcommand: $Command" -Level Error
            Write-Host ""
            Show-Help
        }
    }
}

# Run main
Main
