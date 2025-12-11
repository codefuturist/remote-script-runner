<#
.SYNOPSIS
    SSH Key Management and Agent Control for Windows

.DESCRIPTION
    Complete SSH key management including generation, distribution, testing,
    and SSH agent control. Provides feature parity with the Bash ssh-keys.sh implementation.

.PARAMETER Command
    Management command (generate, list, copy, distribute, test, revoke, agent)

.PARAMETER Arguments
    Arguments for the command

.EXAMPLE
    .\ssh-keys.ps1 generate

.EXAMPLE
    .\ssh-keys.ps1 list

.EXAMPLE
    .\ssh-keys.ps1 agent status

.EXAMPLE
    .\ssh-keys.ps1 copy user@host

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
$Script:ScriptName = "SSH Key Management"
$Script:DryRun = $false
$Script:Verbose = $false

# SSH Paths
$Script:SSHUserDir = Join-Path $env:USERPROFILE ".ssh"
$Script:SSHKeysDir = Join-Path $Script:SSHUserDir "keys"

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
    $sshKeygenExe = Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue
    return ($null -ne $sshExe) -and ($null -ne $sshKeygenExe)
}

function Ensure-SSHDirectory {
    if (-not (Test-Path $Script:SSHUserDir)) {
        New-Item -ItemType Directory -Path $Script:SSHUserDir -Force | Out-Null
        
        # Set restrictive permissions
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

function Get-SSHKeys {
    $keys = @()
    
    if (-not (Test-Path $Script:SSHUserDir)) {
        return $keys
    }
    
    # Look for private keys
    Get-ChildItem -Path $Script:SSHUserDir -Filter "id_*" -ErrorAction SilentlyContinue | Where-Object {
        $_.Extension -ne '.pub'
    } | ForEach-Object {
        $pubKeyPath = "$($_.FullName).pub"
        
        $keyInfo = @{
            Name = $_.Name
            Path = $_.FullName
            PublicKeyPath = $pubKeyPath
            HasPublicKey = Test-Path $pubKeyPath
            Size = $_.Length
            Created = $_.CreationTime
            Modified = $_.LastWriteTime
        }
        
        # Try to get key type and fingerprint
        if ($keyInfo.HasPublicKey) {
            try {
                $fingerprint = & ssh-keygen.exe -lf $pubKeyPath 2>$null
                if ($fingerprint -match '(\d+)\s+([A-Za-z0-9:]+)\s+.*\(([A-Z0-9]+)\)') {
                    $keyInfo.Bits = $matches[1]
                    $keyInfo.Fingerprint = $matches[2]
                    $keyInfo.Type = $matches[3]
                }
            } catch {
                Write-SSHLog "Failed to get fingerprint for $($_.Name): $_" -Level Debug
            }
        }
        
        $keys += [PSCustomObject]$keyInfo
    }
    
    return $keys
}

# =============================================================================
# Generate Command
# =============================================================================

function Invoke-GenerateCommand {
    param(
        [string]$KeyType = 'ed25519',
        [string]$Comment,
        [string]$OutputFile,
        [int]$Bits,
        [switch]$NoPassphrase
    )
    
    Write-SSHHeader "Generate SSH Key"
    
    # Validate key type
    $validTypes = @('rsa', 'ed25519', 'ecdsa')
    if ($KeyType -notin $validTypes) {
        Write-SSHLog "Invalid key type: $KeyType" -Level Error
        Write-SSHLog "Valid types: $($validTypes -join ', ')" -Level Info
        return
    }
    
    # Set default bits based on type
    if (-not $Bits) {
        $Bits = switch ($KeyType) {
            'rsa' { 4096 }
            'ed25519' { 256 }
            'ecdsa' { 521 }
        }
    }
    
    # Set default output file
    if (-not $OutputFile) {
        Ensure-SSHDirectory
        $OutputFile = Join-Path $Script:SSHUserDir "id_$KeyType"
    }
    
    # Set default comment
    if (-not $Comment) {
        $Comment = "$env:USERNAME@$env:COMPUTERNAME"
    }
    
    Write-Host "Key type: " -NoNewline
    Write-Host $KeyType -ForegroundColor White
    Write-Host "Bits: " -NoNewline
    Write-Host $Bits -ForegroundColor White
    Write-Host "Comment: " -NoNewline
    Write-Host $Comment -ForegroundColor White
    Write-Host "Output: " -NoNewline
    Write-Host $OutputFile -ForegroundColor White
    Write-Host ""
    
    if (Test-Path $OutputFile) {
        Write-SSHLog "Key file already exists: $OutputFile" -Level Warning
        $response = Read-Host "Overwrite? [y/N]"
        if ($response -ne 'y' -and $response -ne 'Y') {
            Write-SSHLog "Cancelled" -Level Info
            return
        }
    }
    
    if (-not $Script:DryRun) {
        $args = @(
            '-t', $KeyType,
            '-b', $Bits,
            '-C', $Comment,
            '-f', $OutputFile
        )
        
        if ($NoPassphrase) {
            $args += @('-N', '""')
        }
        
        Write-SSHLog "Generating $KeyType key..." -Level Info
        
        & ssh-keygen.exe @args
        
        if ($LASTEXITCODE -eq 0) {
            Write-SSHLog "Key generated successfully" -Level Success
            Write-Host "`nPrivate key: " -NoNewline -ForegroundColor White
            Write-Host $OutputFile -ForegroundColor Cyan
            Write-Host "Public key: " -NoNewline -ForegroundColor White
            Write-Host "$OutputFile.pub" -ForegroundColor Cyan
            
            # Show fingerprint
            Write-Host "`nFingerprint:" -ForegroundColor White
            & ssh-keygen.exe -lf "$OutputFile.pub"
            
            Write-Host "`nNext steps:" -ForegroundColor DarkGray
            Write-Host "  • Copy to server: ssh-keys copy user@host" -ForegroundColor Cyan
            Write-Host "  • Add to agent: ssh-keys agent add $OutputFile" -ForegroundColor Cyan
        } else {
            Write-SSHLog "Key generation failed" -Level Error
        }
    } else {
        Write-SSHLog "[DRY RUN] Would generate key" -Level Info
    }
}

# =============================================================================
# List Command
# =============================================================================

function Invoke-ListCommand {
    Write-SSHHeader "SSH Keys"
    
    $keys = Get-SSHKeys
    
    if ($keys.Count -eq 0) {
        Write-Host "No SSH keys found in $Script:SSHUserDir" -ForegroundColor DarkGray
        Write-Host "`nGenerate a key with: ssh-keys generate" -ForegroundColor Cyan
        return
    }
    
    $format = "{0,-20} {1,-10} {2,-6} {3}"
    Write-Host ($format -f "NAME", "TYPE", "BITS", "FINGERPRINT") -ForegroundColor White
    Write-Host ("─" * 80) -ForegroundColor DarkGray
    
    foreach ($key in $keys) {
        $type = if ($key.Type) { $key.Type } else { '-' }
        $bits = if ($key.Bits) { $key.Bits } else { '-' }
        $fp = if ($key.Fingerprint) { $key.Fingerprint.Substring(0, [Math]::Min(40, $key.Fingerprint.Length)) } else { '-' }
        
        $color = if ($key.HasPublicKey) { 'Green' } else { 'Yellow' }
        $icon = if ($key.HasPublicKey) { '✓' } else { '⚠' }
        
        Write-Host "$icon " -NoNewline -ForegroundColor $color
        Write-Host ($format -f $key.Name, $type, $bits, $fp)
    }
    
    Write-Host "`n$($keys.Count) key(s) found" -ForegroundColor DarkGray
}

# =============================================================================
# Copy Command (ssh-copy-id equivalent)
# =============================================================================

function Invoke-CopyCommand {
    param(
        [string]$Target,
        [string]$Identity
    )
    
    if (-not $Target) {
        Write-SSHLog "Target is required" -Level Error
        Write-SSHLog "Usage: ssh-keys copy user@host [-Identity path/to/key]" -Level Info
        return
    }
    
    Write-SSHHeader "Copy SSH Key"
    
    # Determine which key to use
    if (-not $Identity) {
        # Auto-detect: prefer ed25519, then rsa
        $keys = Get-SSHKeys | Where-Object { $_.HasPublicKey }
        $key = $keys | Where-Object { $_.Type -eq 'ED25519' } | Select-Object -First 1
        if (-not $key) {
            $key = $keys | Where-Object { $_.Type -eq 'RSA' } | Select-Object -First 1
        }
        if (-not $key) {
            $key = $keys | Select-Object -First 1
        }
        
        if (-not $key) {
            Write-SSHLog "No SSH keys found" -Level Error
            Write-SSHLog "Generate a key first: ssh-keys generate" -Level Info
            return
        }
        
        $Identity = $key.Path
    }
    
    $pubKeyPath = "$Identity.pub"
    
    if (-not (Test-Path $pubKeyPath)) {
        Write-SSHLog "Public key not found: $pubKeyPath" -Level Error
        return
    }
    
    Write-Host "Copying key: " -NoNewline
    Write-Host (Split-Path -Leaf $pubKeyPath) -ForegroundColor White
    Write-Host "To: " -NoNewline
    Write-Host $Target -ForegroundColor White
    Write-Host ""
    
    if (-not $Script:DryRun) {
        $pubKeyContent = Get-Content $pubKeyPath -Raw
        
        # Use ssh to append the key to authorized_keys
        $command = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pubKeyContent' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
        
        Write-SSHLog "Connecting to $Target..." -Level Info
        
        try {
            $result = & ssh.exe $Target $command 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-SSHLog "Key copied successfully" -Level Success
                Write-Host "`nTest the connection with: ssh $Target" -ForegroundColor Cyan
            } else {
                Write-SSHLog "Failed to copy key" -Level Error
                Write-Host $result
            }
        } catch {
            Write-SSHLog "Error: $_" -Level Error
        }
    } else {
        Write-SSHLog "[DRY RUN] Would copy key to $Target" -Level Info
    }
}

# =============================================================================
# Distribute Command
# =============================================================================

function Invoke-DistributeCommand {
    param(
        [string[]]$Targets,
        [string]$Identity
    )
    
    if ($Targets.Count -eq 0) {
        Write-SSHLog "At least one target is required" -Level Error
        Write-SSHLog "Usage: ssh-keys distribute user@host1 user@host2 ..." -Level Info
        return
    }
    
    Write-SSHHeader "Distribute SSH Key"
    
    Write-Host "Distributing to $($Targets.Count) host(s)`n" -ForegroundColor White
    
    $success = 0
    $failed = 0
    
    foreach ($target in $Targets) {
        Write-Host "► $target" -ForegroundColor Cyan
        
        $params = @{ Target = $target }
        if ($Identity) { $params.Identity = $Identity }
        
        try {
            Invoke-CopyCommand @params
            $success++
        } catch {
            Write-SSHLog "  Failed: $_" -Level Error
            $failed++
        }
        
        Write-Host ""
    }
    
    Write-Host "Summary:" -ForegroundColor White
    Write-Host "  ✓ Success: $success" -ForegroundColor Green
    if ($failed -gt 0) {
        Write-Host "  ✗ Failed: $failed" -ForegroundColor Red
    }
}

# =============================================================================
# Test Command
# =============================================================================

function Invoke-TestCommand {
    param(
        [string]$Target,
        [string]$Identity
    )
    
    if (-not $Target) {
        Write-SSHLog "Target is required" -Level Error
        Write-SSHLog "Usage: ssh-keys test user@host [-Identity path/to/key]" -Level Info
        return
    }
    
    Write-SSHHeader "Test SSH Key Authentication"
    
    $args = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5')
    
    if ($Identity) {
        $args += @('-i', $Identity)
    }
    
    $args += @($Target, 'exit')
    
    Write-Host "Testing connection to: " -NoNewline
    Write-Host $Target -ForegroundColor White
    if ($Identity) {
        Write-Host "Using key: " -NoNewline
        Write-Host $Identity -ForegroundColor White
    }
    Write-Host ""
    
    try {
        $result = & ssh.exe @args 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-SSHLog "✓ Key authentication successful" -Level Success
        } else {
            Write-SSHLog "✗ Key authentication failed" -Level Error
            Write-Host "`nTroubleshooting:" -ForegroundColor DarkGray
            Write-Host "  • Verify key is copied: ssh-keys copy $Target" -ForegroundColor White
            Write-Host "  • Check permissions on server: chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys" -ForegroundColor White
            Write-Host "  • Test manually: ssh -v $Target" -ForegroundColor White
        }
    } catch {
        Write-SSHLog "Error: $_" -Level Error
    }
}

# =============================================================================
# Revoke Command
# =============================================================================

function Invoke-RevokeCommand {
    param(
        [string]$Target,
        [string]$Identity
    )
    
    if (-not $Target) {
        Write-SSHLog "Target is required" -Level Error
        Write-SSHLog "Usage: ssh-keys revoke user@host [-Identity path/to/key]" -Level Info
        return
    }
    
    Write-SSHHeader "Revoke SSH Key"
    
    if (-not $Identity) {
        $keys = Get-SSHKeys | Where-Object { $_.HasPublicKey }
        if ($keys.Count -eq 0) {
            Write-SSHLog "No SSH keys found" -Level Error
            return
        }
        
        # Show menu
        Write-Host "Select key to revoke:" -ForegroundColor White
        for ($i = 0; $i -lt $keys.Count; $i++) {
            Write-Host "  $($i+1). $($keys[$i].Name)" -ForegroundColor Cyan
        }
        
        $selection = Read-Host "`nChoice [1-$($keys.Count)]"
        $index = [int]$selection - 1
        
        if ($index -ge 0 -and $index -lt $keys.Count) {
            $Identity = $keys[$index].Path
        } else {
            Write-SSHLog "Invalid selection" -Level Error
            return
        }
    }
    
    $pubKeyPath = "$Identity.pub"
    
    if (-not (Test-Path $pubKeyPath)) {
        Write-SSHLog "Public key not found: $pubKeyPath" -Level Error
        return
    }
    
    Write-Host "Revoking key: " -NoNewline
    Write-Host (Split-Path -Leaf $pubKeyPath) -ForegroundColor White
    Write-Host "From: " -NoNewline
    Write-Host $Target -ForegroundColor White
    Write-Host ""
    
    $response = Read-Host "Are you sure? [y/N]"
    if ($response -ne 'y' -and $response -ne 'Y') {
        Write-SSHLog "Cancelled" -Level Info
        return
    }
    
    if (-not $Script:DryRun) {
        $pubKeyContent = Get-Content $pubKeyPath -Raw
        
        # Remove the key from authorized_keys
        $command = "sed -i '\|$pubKeyContent|d' ~/.ssh/authorized_keys 2>/dev/null || grep -v '$pubKeyContent' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp && mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys"
        
        Write-SSHLog "Connecting to $Target..." -Level Info
        
        try {
            & ssh.exe $Target $command 2>&1 | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-SSHLog "Key revoked successfully" -Level Success
            } else {
                Write-SSHLog "Failed to revoke key (check if key exists on server)" -Level Warning
            }
        } catch {
            Write-SSHLog "Error: $_" -Level Error
        }
    } else {
        Write-SSHLog "[DRY RUN] Would revoke key from $Target" -Level Info
    }
}

# =============================================================================
# Agent Commands
# =============================================================================

function Invoke-AgentCommand {
    param(
        [string]$Action,
        [string[]]$Args
    )
    
    switch ($Action) {
        { $_ -in 'status', '' } { Invoke-AgentStatus }
        'start' { Invoke-AgentStart }
        'add' { Invoke-AgentAdd -Args $Args }
        { $_ -in 'remove', 'rm' } { Invoke-AgentRemove -Args $Args }
        { $_ -in 'list', 'ls' } { Invoke-AgentStatus }
        'lock' { Invoke-AgentLock }
        'unlock' { Invoke-AgentUnlock }
        default {
            Write-SSHLog "Unknown action: $Action" -Level Error
            Write-SSHLog "Use 'ssh-keys agent --help' for usage" -Level Info
        }
    }
}

function Invoke-AgentStatus {
    Write-SSHHeader "SSH Agent Status"
    
    # Check if ssh-agent service is running
    $service = Get-Service -Name ssh-agent -ErrorAction SilentlyContinue
    
    if (-not $service) {
        Write-Host "✗ SSH Agent service not found" -ForegroundColor Red
        Write-Host "`nInstall OpenSSH Client feature to use SSH Agent" -ForegroundColor Yellow
        return
    }
    
    if ($service.Status -ne 'Running') {
        Write-Host "✗ Agent not running" -ForegroundColor Red
        Write-Host "`nStart with: ssh-keys agent start" -ForegroundColor Cyan
        return
    }
    
    Write-Host "✓ Agent running" -ForegroundColor Green
    Write-Host "Status: " -NoNewline
    Write-Host $service.Status -ForegroundColor White
    Write-Host ""
    
    # List loaded keys
    try {
        $output = & ssh-add.exe -l 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $lines = $output -split "`n" | Where-Object { $_ -match '\S' }
            Write-Host "Loaded keys: " -NoNewline
            Write-Host $lines.Count -ForegroundColor White
            Write-Host ""
            Write-Host "Keys:" -ForegroundColor White
            
            foreach ($line in $lines) {
                if ($line -match '(\d+)\s+([A-Za-z0-9:/]+)\s+(.+)\s+\(([A-Z0-9]+)\)') {
                    Write-Host "  ✓ $($matches[2])" -ForegroundColor Green
                    Write-Host "    Type: $($matches[4]), Bits: $($matches[1]), Path: $($matches[3])" -ForegroundColor DarkGray
                }
            }
        } else {
            Write-Host "No keys loaded" -ForegroundColor DarkGray
            Write-Host "`nAdd keys with: ssh-keys agent add" -ForegroundColor Cyan
        }
    } catch {
        Write-SSHLog "Failed to list keys: $_" -Level Error
    }
}

function Invoke-AgentStart {
    Write-SSHHeader "Start SSH Agent"
    
    $service = Get-Service -Name ssh-agent -ErrorAction SilentlyContinue
    
    if (-not $service) {
        Write-SSHLog "SSH Agent service not found" -Level Error
        Write-SSHLog "Install OpenSSH Client feature first" -Level Info
        return
    }
    
    if ($service.Status -eq 'Running') {
        Write-SSHLog "Agent is already running" -Level Info
        return
    }
    
    if (-not $Script:DryRun) {
        try {
            # Set service to start automatically
            Set-Service -Name ssh-agent -StartupType Automatic
            Start-Service -Name ssh-agent
            
            Write-SSHLog "SSH Agent started successfully" -Level Success
            Write-Host "`nAdd keys with: ssh-keys agent add" -ForegroundColor Cyan
        } catch {
            Write-SSHLog "Failed to start agent: $_" -Level Error
        }
    } else {
        Write-SSHLog "[DRY RUN] Would start SSH Agent" -Level Info
    }
}

function Invoke-AgentAdd {
    param([string[]]$Args)
    
    $addAll = $false
    $lifetime = $null
    $keyPath = $null
    
    # Parse arguments
    for ($i = 0; $i -lt $Args.Count; $i++) {
        switch ($Args[$i]) {
            '--all' { $addAll = $true }
            '-t' { $lifetime = $Args[++$i] }
            default { $keyPath = $Args[$i] }
        }
    }
    
    Write-SSHHeader "Add Key to Agent"
    
    # Ensure agent is running
    $service = Get-Service -Name ssh-agent -ErrorAction SilentlyContinue
    if (-not $service -or $service.Status -ne 'Running') {
        Write-SSHLog "SSH Agent not running" -Level Warning
        Invoke-AgentStart
    }
    
    if ($addAll) {
        $keys = Get-SSHKeys
        
        if ($keys.Count -eq 0) {
            Write-SSHLog "No keys found" -Level Warning
            return
        }
        
        Write-Host "Adding all keys to agent...`n" -ForegroundColor White
        
        foreach ($key in $keys) {
            if (-not $Script:DryRun) {
                Write-Host "Adding: $($key.Name)" -ForegroundColor Cyan
                & ssh-add.exe $key.Path 2>&1 | Out-Null
                
                if ($LASTEXITCODE -eq 0) {
                    Write-SSHLog "  ✓ Added" -Level Success
                } else {
                    Write-SSHLog "  ✗ Failed or already loaded" -Level Warning
                }
            }
        }
    } elseif ($keyPath) {
        if (-not (Test-Path $keyPath)) {
            Write-SSHLog "Key not found: $keyPath" -Level Error
            return
        }
        
        if (-not $Script:DryRun) {
            $addArgs = @($keyPath)
            if ($lifetime) {
                $addArgs = @('-t', $lifetime) + $addArgs
            }
            
            & ssh-add.exe @addArgs
            
            if ($LASTEXITCODE -eq 0) {
                Write-SSHLog "Key added to agent" -Level Success
                if ($lifetime) {
                    Write-Host "Lifetime: $lifetime" -ForegroundColor White
                }
            } else {
                Write-SSHLog "Failed to add key" -Level Error
            }
        } else {
            Write-SSHLog "[DRY RUN] Would add key $keyPath" -Level Info
        }
    } else {
        # Auto-detect and add default key
        $keys = Get-SSHKeys
        $key = $keys | Where-Object { $_.Type -eq 'ED25519' } | Select-Object -First 1
        if (-not $key) {
            $key = $keys | Where-Object { $_.Type -eq 'RSA' } | Select-Object -First 1
        }
        
        if (-not $key) {
            Write-SSHLog "No keys found" -Level Warning
            Write-SSHLog "Generate a key first: ssh-keys generate" -Level Info
            return
        }
        
        Invoke-AgentAdd -Args @($key.Path)
    }
}

function Invoke-AgentRemove {
    param([string[]]$Args)
    
    $target = if ($Args.Count -gt 0) { $Args[0] } else { 'all' }
    
    Write-SSHHeader "Remove Key from Agent"
    
    if ($target -eq 'all') {
        if (-not $Script:DryRun) {
            & ssh-add.exe -D
            
            if ($LASTEXITCODE -eq 0) {
                Write-SSHLog "All keys removed from agent" -Level Success
            } else {
                Write-SSHLog "Failed to remove keys" -Level Error
            }
        } else {
            Write-SSHLog "[DRY RUN] Would remove all keys" -Level Info
        }
    } else {
        if (-not (Test-Path $target)) {
            Write-SSHLog "Key not found: $target" -Level Error
            return
        }
        
        if (-not $Script:DryRun) {
            & ssh-add.exe -d $target
            
            if ($LASTEXITCODE -eq 0) {
                Write-SSHLog "Key removed from agent" -Level Success
            } else {
                Write-SSHLog "Failed to remove key" -Level Error
            }
        } else {
            Write-SSHLog "[DRY RUN] Would remove key $target" -Level Info
        }
    }
}

function Invoke-AgentLock {
    Write-SSHHeader "Lock SSH Agent"
    
    Write-SSHLog "Note: Windows SSH Agent does not support locking" -Level Warning
    Write-Host "Alternative: Stop the agent service with: Stop-Service ssh-agent" -ForegroundColor Yellow
}

function Invoke-AgentUnlock {
    Write-SSHHeader "Unlock SSH Agent"
    
    Write-SSHLog "Note: Windows SSH Agent does not support locking" -Level Warning
    Write-Host "Alternative: Start the agent service with: ssh-keys agent start" -ForegroundColor Yellow
}

# =============================================================================
# Help Function
# =============================================================================

function Show-Help {
    Write-Host @"

$Script:ScriptName v$Script:ScriptVersion

Complete SSH key management including generation, distribution, and agent control.

Usage:
    .\ssh-keys.ps1 <command> [OPTIONS]

Commands:

  Key Management:
    generate              Generate new SSH key pair
      -KeyType TYPE       Key type (rsa, ed25519, ecdsa) [default: ed25519]
      -Bits N             Key size in bits [default: 4096 for RSA]
      -Comment TEXT       Key comment [default: user@host]
      -OutputFile PATH    Output file path
      -NoPassphrase       Generate without passphrase

    list, ls              List all SSH keys
    copy TARGET           Copy public key to remote host (ssh-copy-id)
      -Identity PATH      Specific key to copy
    distribute TARGET...  Distribute key to multiple hosts
    test TARGET           Test key authentication
      -Identity PATH      Specific key to test
    revoke TARGET         Revoke key from remote host
      -Identity PATH      Specific key to revoke

  SSH Agent:
    agent status          Show agent status and loaded keys
    agent start           Start SSH agent service
    agent add [KEY]       Add key to agent
      --all               Add all keys
      -t TIME             Key lifetime (Windows: limited support)
    agent remove [KEY]    Remove key from agent
      all                 Remove all keys
    agent list            List loaded keys (alias for status)

Global Options:
    -Verbose              Enable verbose output
    -DryRun               Show what would be done

Examples:
    # Generate Ed25519 key (recommended)
    .\ssh-keys.ps1 generate

    # Generate RSA key with custom size
    .\ssh-keys.ps1 generate -KeyType rsa -Bits 4096

    # List all keys
    .\ssh-keys.ps1 list

    # Copy key to server
    .\ssh-keys.ps1 copy user@server.com

    # Distribute to multiple servers
    .\ssh-keys.ps1 distribute user@server1.com user@server2.com

    # Agent management
    .\ssh-keys.ps1 agent start
    .\ssh-keys.ps1 agent add --all
    .\ssh-keys.ps1 agent status

"@ -ForegroundColor Cyan
}

# =============================================================================
# Main Entry Point
# =============================================================================

function Main {
    # Parse global flags
    $i = 0
    while ($i -lt $Arguments.Count) {
        switch ($Arguments[$i]) {
            '-v' { $Script:Verbose = $true; $i++ }
            '--verbose' { $Script:Verbose = $true; $i++ }
            '-d' { $Script:DryRun = $true; $i++ }
            '--dry-run' { $Script:DryRun = $true; $i++ }
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
    
    # Route to command
    switch ($Command) {
        'generate' {
            $params = @{}
            for ($i = 0; $i -lt $Arguments.Count; $i++) {
                switch ($Arguments[$i]) {
                    '-KeyType' { $params['KeyType'] = $Arguments[++$i] }
                    '-Bits' { $params['Bits'] = [int]$Arguments[++$i] }
                    '-Comment' { $params['Comment'] = $Arguments[++$i] }
                    '-OutputFile' { $params['OutputFile'] = $Arguments[++$i] }
                    '-NoPassphrase' { $params['NoPassphrase'] = $true }
                }
            }
            Invoke-GenerateCommand @params
        }
        { $_ -in 'list', 'ls' } {
            Invoke-ListCommand
        }
        'copy' {
            $params = @{ Target = $Arguments[0] }
            for ($i = 1; $i -lt $Arguments.Count; $i++) {
                if ($Arguments[$i] -eq '-Identity') {
                    $params['Identity'] = $Arguments[++$i]
                }
            }
            Invoke-CopyCommand @params
        }
        'distribute' {
            $targets = @()
            $identity = $null
            for ($i = 0; $i -lt $Arguments.Count; $i++) {
                if ($Arguments[$i] -eq '-Identity') {
                    $identity = $Arguments[++$i]
                } else {
                    $targets += $Arguments[$i]
                }
            }
            $params = @{ Targets = $targets }
            if ($identity) { $params['Identity'] = $identity }
            Invoke-DistributeCommand @params
        }
        'test' {
            $params = @{ Target = $Arguments[0] }
            for ($i = 1; $i -lt $Arguments.Count; $i++) {
                if ($Arguments[$i] -eq '-Identity') {
                    $params['Identity'] = $Arguments[++$i]
                }
            }
            Invoke-TestCommand @params
        }
        'revoke' {
            $params = @{ Target = $Arguments[0] }
            for ($i = 1; $i -lt $Arguments.Count; $i++) {
                if ($Arguments[$i] -eq '-Identity') {
                    $params['Identity'] = $Arguments[++$i]
                }
            }
            Invoke-RevokeCommand @params
        }
        'agent' {
            $action = if ($Arguments.Count -gt 0) { $Arguments[0] } else { 'status' }
            $args = if ($Arguments.Count -gt 1) { $Arguments[1..($Arguments.Count-1)] } else { @() }
            Invoke-AgentCommand -Action $action -Args $args
        }
        default {
            Write-SSHLog "Unknown command: $Command" -Level Error
            Write-Host ""
            Show-Help
        }
    }
}

# Run main
Main
