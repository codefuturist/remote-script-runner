<#
.SYNOPSIS
    User Management for Windows - Remote Script Runner

.DESCRIPTION
    Cross-platform user management script for Windows that mirrors the
    bash version functionality with identical command syntax.

.PARAMETER Command
    Subcommand to execute (create, delete, password, group, ssh, session, audit)

.PARAMETER Arguments
    Arguments passed to the subcommand

.EXAMPLE
    .\UserManagement.ps1 create -u john -c "John Doe"

.EXAMPLE
    .\UserManagement.ps1 password reset -u john

.EXAMPLE
    .\UserManagement.ps1 ssh add -u john -f key.pub

.NOTES
    Version: 1.0.0
    Requires: PowerShell 5.1+, Administrator privileges
#>

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Command,

    [Parameter(Position=1, ValueFromRemainingArguments)]
    [string[]]$Arguments
)

# =============================================================================
# Script Configuration
# =============================================================================

$ErrorActionPreference = 'Stop'
$Script:ScriptVersion = "1.0.0"
$Script:ScriptName = "User Management"
$Script:DryRun = $false
$Script:Verbose = $false

# =============================================================================
# Import Library
# =============================================================================

$libPath = Join-Path $PSScriptRoot "..\..\lib\users.ps1"
if (Test-Path $libPath) {
    . $libPath
} else {
    Write-Error "Required library not found: $libPath"
    exit 1
}

# =============================================================================
# Helper Functions
# =============================================================================

function Show-Usage {
    Write-Host @"
$Script:ScriptName v$Script:ScriptVersion

Comprehensive cross-platform user management for Windows.

Usage:
    UserManagement.ps1 <subcommand> [OPTIONS]

Subcommands:

  Account Management:
    create              Create new user account
    delete              Delete user account
    lock                Lock user account (disable login)
    unlock              Unlock user account
    list                List user accounts

  Password Management:
    password reset      Reset user password
    password expire     Force password change on next login
    password generate   Generate random password
    password policy     Show password policy settings

  Group Management:
    group create        Create new group
    group add           Add user to group
    group remove        Remove user from group
    group list          List group members
    group show          Show user's groups

  SSH Key Management:
    ssh generate        Generate SSH key pair for user
    ssh add             Add public key to authorized_keys
    ssh remove          Remove key from authorized_keys
    ssh list            List authorized SSH keys
    ssh fix             Fix SSH directory permissions

  Session & Monitoring:
    session list        List active user sessions
    session history     Show login history

Global Options:
    -h, --help          Display this help message
    -v, --verbose       Enable verbose output
    -d, --dry-run       Show what would be done
    -y, --yes           Auto-confirm all prompts

Examples:

    # Create user with full name
    UserManagement.ps1 create -u john -c "John Doe"

    # Generate SSH key
    UserManagement.ps1 ssh generate -u john -t ed25519

    # Add user to Administrators group
    UserManagement.ps1 group add -u john -g Administrators

    # List active sessions
    UserManagement.ps1 session list

Documentation:
    https://github.com/codefuturist/remote-script-runner

"@
}

function Parse-GlobalArgs {
    param([string[]]$Args)

    $filtered = @()

    for ($i = 0; $i < $Args.Count; $i++) {
        switch ($Args[$i]) {
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
                $filtered += $Args[$i]
            }
        }
    }

    return $filtered
}

# =============================================================================
# Subcommand: Create User
# =============================================================================

function Invoke-CreateUser {
    param([string[]]$Args)

    $username = $null
    $fullName = $null
    $description = $null
    $password = $null
    $generatePassword = $false
    $groups = @()

    for ($i = 0; $i < $Args.Count; $i++) {
        switch ($Args[$i]) {
            { $_ -in '-u','--username' } {
                $username = $Args[++$i]
            }
            { $_ -in '-c','--comment' } {
                $fullName = $Args[++$i]
            }
            { $_ -in '-d','--description' } {
                $description = $Args[++$i]
            }
            { $_ -in '-p','--password' } {
                $password = $Args[++$i]
            }
            '--generate' {
                $generatePassword = $true
            }
            { $_ -in '-g','--groups' } {
                $groups = $Args[++$i] -split ','
            }
        }
    }

    if (-not $username) {
        Write-RSRLog "Username is required" -Level Error
        Write-Host "Use: UserManagement.ps1 create -u USERNAME"
        exit 2
    }

    Write-RSRHeader "Create User: $username"

    if (Test-RSRUserExists $username) {
        Write-RSRLog "User '$username' already exists" -Level Error
        exit 1
    }

    if ($Script:DryRun) {
        Write-RSRLog "[DRY RUN] Would create user: $username" -Level Info
        if ($fullName) { Write-RSRLog "  Full Name: $fullName" -Level Info }
        if ($groups) { Write-RSRLog "  Groups: $($groups -join ', ')" -Level Info }
        return
    }

    try {
        Write-RSRLog "Creating user '$username'..." -Level Info

        $params = @{
            Username = $username
        }

        if ($fullName) { $params.FullName = $fullName }
        if ($description) { $params.Description = $description }

        if ($password) {
            $securePass = ConvertTo-SecureString $password -AsPlainText -Force
            $params.Password = $securePass
        } elseif ($generatePassword) {
            $genPass = New-RSRRandomPassword
            $securePass = ConvertTo-SecureString $genPass -AsPlainText -Force
            $params.Password = $securePass
            Write-RSRLog "Generated password: $genPass" -Level Info
        }

        New-RSRUser @params | Out-Null
        Write-RSRLog "User '$username' created successfully" -Level Success

        # Add to groups
        if ($groups) {
            Write-RSRLog "Adding user to groups..." -Level Info
            foreach ($group in $groups) {
                try {
                    Add-RSRGroupMember -GroupName $group -Username $username
                    Write-RSRLog "Added to group: $group" -Level Success
                } catch {
                    Write-RSRLog "Failed to add to group '$group': $_" -Level Warning
                }
            }
        }

        # Show summary
        Write-Host ""
        Write-RSRLog "User creation complete!" -Level Success

        $info = Get-RSRUserInfo $username
        Write-Host ""
        Write-Host "User Details:" -ForegroundColor Cyan
        Write-Host "  Username: $($info.Username)"
        Write-Host "  Full Name: $($info.FullName)"
        Write-Host "  Home: $($info.Home)"
        Write-Host "  Enabled: $($info.Enabled)"
        if ($groups) {
            Write-Host "  Groups: $($groups -join ', ')"
        }

    } catch {
        Write-RSRLog "Failed to create user: $_" -Level Error
        exit 1
    }
}

# =============================================================================
# Subcommand: Delete User
# =============================================================================

function Invoke-DeleteUser {
    param([string[]]$Args)

    $username = $null
    $removeHome = $false

    for ($i = 0; $i < $Args.Count; $i++) {
        switch ($Args[$i]) {
            { $_ -in '-u','--username' } {
                $username = $Args[++$i]
            }
            '--remove-home' {
                $removeHome = $true
            }
        }
    }

    if (-not $username) {
        Write-RSRLog "Username is required" -Level Error
        exit 2
    }

    Write-RSRHeader "Delete User: $username"

    if (-not (Test-RSRUserExists $username)) {
        Write-RSRLog "User '$username' does not exist" -Level Error
        exit 1
    }

    if ($Script:DryRun) {
        Write-RSRLog "[DRY RUN] Would delete user: $username" -Level Info
        if ($removeHome) { Write-RSRLog "  Would remove home directory" -Level Info }
        return
    }

    # Confirmation
    Write-Host "WARNING: This will delete user '$username'" -ForegroundColor Yellow
    if ($removeHome) {
        Write-Host "  Home directory will also be removed" -ForegroundColor Yellow
    }
    $confirm = Read-Host "Are you sure? (yes/no)"
    if ($confirm -ne "yes") {
        Write-RSRLog "Cancelled" -Level Info
        exit 0
    }

    try {
        Write-RSRLog "Deleting user '$username'..." -Level Info
        Remove-RSRUser -Username $username -RemoveHome:$removeHome
        Write-RSRLog "User '$username' deleted successfully" -Level Success
    } catch {
        Write-RSRLog "Failed to delete user: $_" -Level Error
        exit 1
    }
}

# =============================================================================
# Subcommand: Lock/Unlock User
# =============================================================================

function Invoke-LockUser {
    param([string[]]$Args)

    $username = $null
    for ($i = 0; $i < $Args.Count; $i++) {
        if ($Args[$i] -in '-u','--username') {
            $username = $Args[++$i]
        }
    }

    if (-not $username) {
        Write-RSRLog "Username is required" -Level Error
        exit 2
    }

    Write-RSRHeader "Lock User: $username"

    if ($Script:DryRun) {
        Write-RSRLog "[DRY RUN] Would lock user: $username" -Level Info
        return
    }

    try {
        Lock-RSRUser -Username $username
        Write-RSRLog "User '$username' locked successfully" -Level Success
    } catch {
        Write-RSRLog "Failed to lock user: $_" -Level Error
        exit 1
    }
}

function Invoke-UnlockUser {
    param([string[]]$Args)

    $username = $null
    for ($i = 0; $i < $Args.Count; $i++) {
        if ($Args[$i] -in '-u','--username') {
            $username = $Args[++$i]
        }
    }

    if (-not $username) {
        Write-RSRLog "Username is required" -Level Error
        exit 2
    }

    Write-RSRHeader "Unlock User: $username"

    if ($Script:DryRun) {
        Write-RSRLog "[DRY RUN] Would unlock user: $username" -Level Info
        return
    }

    try {
        Unlock-RSRUser -Username $username
        Write-RSRLog "User '$username' unlocked successfully" -Level Success
    } catch {
        Write-RSRLog "Failed to unlock user: $_" -Level Error
        exit 1
    }
}

# =============================================================================
# Subcommand: List Users
# =============================================================================

function Invoke-ListUsers {
    param([string[]]$Args)

    $showAll = $false
    $showAdmin = $false

    foreach ($arg in $Args) {
        switch ($arg) {
            { $_ -in '-a','--all' } { $showAll = $true }
            '--admin' { $showAdmin = $true }
        }
    }

    Write-RSRHeader "User Accounts"

    Write-Host ("{0,-20} {1,-30} {2,-10} {3}" -f "USERNAME", "FULL NAME", "ENABLED", "ADMIN") -ForegroundColor Cyan
    Write-Host ("{0,-20} {1,-30} {2,-10} {3}" -f "--------", "---------", "-------", "-----")

    $users = if ($showAll) { Get-RSRAllUsers } else { Get-RSRHumanUsers }

    foreach ($user in $users) {
        $isAdmin = Test-RSRUserHasAdmin $user.Name

        if ($showAdmin -and -not $isAdmin) { continue }

        $adminMark = if ($isAdmin) { "✓" } else { "" }
        $enabled = if ($user.Enabled) { "Yes" } else { "No" }

        Write-Host ("{0,-20} {1,-30} {2,-10} {3}" -f $user.Name, $user.FullName, $enabled, $adminMark)
    }
}

# =============================================================================
# Subcommand: Password Management
# =============================================================================

function Invoke-PasswordCommand {
    param([string[]]$Args)

    if ($Args.Count -eq 0) {
        Show-Usage
        exit 0
    }

    $subcmd = $Args[0]
    $remaining = $Args[1..($Args.Count-1)]

    switch ($subcmd) {
        'reset' { Invoke-PasswordReset $remaining }
        'expire' { Invoke-PasswordExpire $remaining }
        'generate' { Invoke-PasswordGenerate $remaining }
        'policy' { Invoke-PasswordPolicy $remaining }
        default {
            Write-RSRLog "Unknown password subcommand: $subcmd" -Level Error
            exit 2
        }
    }
}

function Invoke-PasswordReset {
    param([string[]]$Args)

    $username = $null
    $password = $null

    for ($i = 0; $i < $Args.Count; $i++) {
        switch ($Args[$i]) {
            { $_ -in '-u','--username' } { $username = $Args[++$i] }
            { $_ -in '-p','--password' } { $password = $Args[++$i] }
        }
    }

    if (-not $username) {
        Write-RSRLog "Username is required" -Level Error
        exit 2
    }

    Write-RSRHeader "Reset Password: $username"

    if ($Script:DryRun) {
        Write-RSRLog "[DRY RUN] Would reset password for: $username" -Level Info
        return
    }

    try {
        if ($password) {
            $securePass = ConvertTo-SecureString $password -AsPlainText -Force
        } else {
            $securePass = Read-Host "Enter new password for '$username'" -AsSecureString
        }

        Set-RSRUserPassword -Username $username -Password $securePass
        Write-RSRLog "Password reset successfully" -Level Success
    } catch {
        Write-RSRLog "Failed to reset password: $_" -Level Error
        exit 1
    }
}

function Invoke-PasswordGenerate {
    param([string[]]$Args)

    $length = 16
    $username = $null
    $setGenerated = $false

    for ($i = 0; $i < $Args.Count; $i++) {
        switch ($Args[$i]) {
            { $_ -in '-l','--length' } { $length = [int]$Args[++$i] }
            { $_ -in '-u','--username' } { $username = $Args[++$i] }
            '--set' { $setGenerated = $true }
        }
    }

    Write-RSRHeader "Generate Password"

    $password = New-RSRRandomPassword -Length $length
    Write-Host "Generated Password: " -NoNewline
    Write-Host $password -ForegroundColor Green

    if ($setGenerated -and $username) {
        if ($Script:DryRun) {
            Write-RSRLog "[DRY RUN] Would set password for: $username" -Level Info
            return
        }

        try {
            $securePass = ConvertTo-SecureString $password -AsPlainText -Force
            Set-RSRUserPassword -Username $username -Password $securePass
            Write-RSRLog "Password set for user '$username'" -Level Success
        } catch {
            Write-RSRLog "Failed to set password: $_" -Level Error
        }
    }
}

function Invoke-PasswordPolicy {
    Write-RSRHeader "Password Policy"
    Get-RSRPasswordPolicy
}

function Invoke-PasswordExpire {
    param([string[]]$Args)

    $username = $null
    for ($i = 0; $i < $Args.Count; $i++) {
        if ($Args[$i] -in '-u','--username') {
            $username = $Args[++$i]
        }
    }

    if (-not $username) {
        Write-RSRLog "Username is required" -Level Error
        exit 2
    }

    Write-RSRHeader "Expire Password: $username"

    if ($Script:DryRun) {
        Write-RSRLog "[DRY RUN] Would expire password for: $username" -Level Info
        return
    }

    try {
        Set-RSRPasswordExpiry -Username $username
        Write-RSRLog "Password expired - user must change on next login" -Level Success
    } catch {
        Write-RSRLog "Failed to expire password: $_" -Level Error
        exit 1
    }
}

# =============================================================================
# Subcommand: Group Management
# =============================================================================

function Invoke-GroupCommand {
    param([string[]]$Args)

    if ($Args.Count -eq 0) {
        Show-Usage
        exit 0
    }

    $subcmd = $Args[0]
    $remaining = $Args[1..($Args.Count-1)]

    switch ($subcmd) {
        'create' { Invoke-GroupCreate $remaining }
        'add' { Invoke-GroupAdd $remaining }
        'remove' { Invoke-GroupRemove $remaining }
        'list' { Invoke-GroupList $remaining }
        'show' { Invoke-GroupShow $remaining }
        default {
            Write-RSRLog "Unknown group subcommand: $subcmd" -Level Error
            exit 2
        }
    }
}

function Invoke-GroupAdd {
    param([string[]]$Args)

    $username = $null
    $groupName = $null

    for ($i = 0; $i < $Args.Count; $i++) {
        switch ($Args[$i]) {
            { $_ -in '-u','--username' } { $username = $Args[++$i] }
            { $_ -in '-g','--group' } { $groupName = $Args[++$i] }
        }
    }

    if (-not $username -or -not $groupName) {
        Write-RSRLog "Username and group name are required" -Level Error
        exit 2
    }

    Write-RSRHeader "Add User to Group"

    if ($Script:DryRun) {
        Write-RSRLog "[DRY RUN] Would add '$username' to group '$groupName'" -Level Info
        return
    }

    try {
        Add-RSRGroupMember -GroupName $groupName -Username $username
        Write-RSRLog "User '$username' added to group '$groupName'" -Level Success
    } catch {
        Write-RSRLog "Failed to add user to group: $_" -Level Error
        exit 1
    }
}

function Invoke-GroupList {
    param([string[]]$Args)

    $groupName = $null
    for ($i = 0; $i < $Args.Count; $i++) {
        if ($Args[$i] -in '-g','--group') {
            $groupName = $Args[++$i]
        }
    }

    if (-not $groupName) {
        Write-RSRLog "Group name is required" -Level Error
        exit 2
    }

    Write-RSRHeader "Group Members: $groupName"

    try {
        $members = Get-RSRGroupMembers -GroupName $groupName
        if ($members) {
            $members | ForEach-Object { Write-Host "  • $_" }
        } else {
            Write-RSRLog "No members in group '$groupName'" -Level Info
        }
    } catch {
        Write-RSRLog "Failed to list group members: $_" -Level Error
        exit 1
    }
}

# =============================================================================
# Subcommand: SSH Management
# =============================================================================

function Invoke-SshCommand {
    param([string[]]$Args)

    if ($Args.Count -eq 0) {
        Show-Usage
        exit 0
    }

    $subcmd = $Args[0]
    $remaining = $Args[1..($Args.Count-1)]

    switch ($subcmd) {
        'generate' { Invoke-SshGenerate $remaining }
        'add' { Invoke-SshAdd $remaining }
        'remove' { Invoke-SshRemove $remaining }
        'list' { Invoke-SshList $remaining }
        'fix' { Invoke-SshFix $remaining }
        default {
            Write-RSRLog "Unknown ssh subcommand: $subcmd" -Level Error
            exit 2
        }
    }
}

function Invoke-SshGenerate {
    param([string[]]$Args)

    $username = $null
    $keyType = 'ed25519'      # Default to ed25519 (recommended)
    $purpose = 'default'      # Purpose/label for the key
    $bits = 4096              # Only used for RSA keys
    $rounds = 100             # KDF rounds for ed25519/ecdsa
    $comment = $null          # Custom comment (auto-generated if not provided)
    $passphrase = $null       # Manual passphrase
    $generatePassphrase = $false  # Auto-generate passphrase
    $passphraseLength = 24    # Length of auto-generated passphrase
    $encryptWithSops = $false # Encrypt passphrase with SOPS
    $sopsAge = $null          # Age public key for SOPS
    $outputPassphrase = $false # Display generated passphrase
    $keyFile = $null          # Override key file path
    $hostnameOverride = $null # Override hostname in comment

    for ($i = 0; $i < $Args.Count; $i++) {
        switch ($Args[$i]) {
            { $_ -in '-u','--username' } { $username = $Args[++$i] }
            { $_ -in '-t','--type' } { $keyType = $Args[++$i] }
            { $_ -in '-p','--purpose' } { $purpose = $Args[++$i] }
            { $_ -in '-b','--bits' } { $bits = [int]$Args[++$i] }
            { $_ -in '-a','--rounds' } { $rounds = [int]$Args[++$i] }
            { $_ -in '-c','--comment' } { $comment = $Args[++$i] }
            { $_ -in '-P','--passphrase' } { $passphrase = $Args[++$i] }
            { $_ -in '-G','--generate-passphrase' } { $generatePassphrase = $true; $i++ }
            { $_ -in '-L','--passphrase-length' } { $passphraseLength = [int]$Args[++$i] }
            { $_ -in '-S','--sops' } { $encryptWithSops = $true; $i++ }
            { $_ -in '--sops-age' } { $sopsAge = $Args[++$i] }
            { $_ -in '-O','--output-passphrase' } { $outputPassphrase = $true; $i++ }
            { $_ -in '-f','--file' } { $keyFile = $Args[++$i] }
            { $_ -in '-H','--hostname' } { $hostnameOverride = $Args[++$i] }
        }
    }

    if (-not $username) {
        Write-RSRLog "Username is required" -Level Error
        Write-Host ""
        Write-Host "Usage: ssh generate -u USERNAME [OPTIONS]"
        Write-Host ""
        Write-Host "Key Options:"
        Write-Host "  -u, --username              Username (required)"
        Write-Host "  -t, --type TYPE             Key type: ed25519 (default), ecdsa, rsa"
        Write-Host "  -p, --purpose PURPOSE       Key purpose/label (default: 'default')"
        Write-Host "                              Creates: id_<type>_<purpose>"
        Write-Host "  -a, --rounds NUM            KDF rounds for ed25519/ecdsa (default: 100)"
        Write-Host "  -b, --bits NUM              Bit size for RSA keys (default: 4096)"
        Write-Host "  -c, --comment TEXT          Custom comment (auto-generated if not set)"
        Write-Host ""
        Write-Host "Passphrase Options:"
        Write-Host "  -P, --passphrase TEXT       Manual passphrase"
        Write-Host "  -G, --generate-passphrase   Auto-generate random passphrase"
        Write-Host "  -L, --passphrase-length NUM Length of generated passphrase (default: 24)"
        Write-Host "  -S, --sops                  Encrypt passphrase with SOPS"
        Write-Host "  --sops-age KEY              Age public key for SOPS encryption"
        Write-Host "  -O, --output-passphrase     Display generated passphrase"
        Write-Host ""
        Write-Host "Override Options:"
        Write-Host "  -f, --file PATH             Override key file path"
        Write-Host "  -H, --hostname NAME         Override hostname in comment"
        Write-Host ""
        Write-Host "Examples:"
        Write-Host "  ssh generate -u john -p github"
        Write-Host "  ssh generate -u john -t rsa -p legacy -b 4096"
        Write-Host "  ssh generate -u john -p prod -G -S"
        Write-Host "  ssh generate -u john -p work -G -O"
        Write-Host "  ssh generate -u john -p github -H webserver01"
        exit 2
    }

    Write-RSRHeader "Generate SSH Key: $username"

    if ($Script:DryRun) {
        Write-RSRLog "[DRY RUN] Would generate $keyType SSH key for: $username (purpose: $purpose)" -Level Info
        if ($generatePassphrase) {
            Write-RSRLog "[DRY RUN] Would generate passphrase ($passphraseLength chars)" -Level Info
        }
        if ($encryptWithSops) {
            Write-RSRLog "[DRY RUN] Would encrypt passphrase with SOPS" -Level Info
        }
        return
    }

    try {
        Write-RSRLog "Generating $keyType SSH key pair..." -Level Info
        Write-Host "  Purpose: $purpose" -ForegroundColor Gray
        if ($keyType -in @('ed25519', 'ecdsa')) {
            Write-Host "  KDF rounds: $rounds" -ForegroundColor Gray
        } elseif ($keyType -eq 'rsa') {
            Write-Host "  Key size: $bits bits" -ForegroundColor Gray
        }
        if ($generatePassphrase) {
            Write-Host "  Passphrase: Auto-generated ($passphraseLength chars)" -ForegroundColor Gray
        } elseif ($passphrase) {
            Write-Host "  Passphrase: Manual" -ForegroundColor Gray
        } else {
            Write-Host "  Passphrase: None (unencrypted key)" -ForegroundColor Yellow
        }
        if ($encryptWithSops) {
            Write-Host "  SOPS: Enabled" -ForegroundColor Gray
        }
        Write-Host ""

        $keyParams = @{
            Username = $username
            Type = $keyType
            Purpose = $purpose
            Rounds = $rounds
            Bits = $bits
        }
        if ($comment) { $keyParams.Comment = $comment }
        if ($passphrase) { $keyParams.Passphrase = $passphrase }
        if ($generatePassphrase) {
            $keyParams.GeneratePassphrase = $true
            $keyParams.PassphraseLength = $passphraseLength
        }
        if ($encryptWithSops) { $keyParams.EncryptWithSops = $true }
        if ($sopsAge) { $keyParams.SopsAge = $sopsAge }
        if ($outputPassphrase) { $keyParams.OutputPassphrase = $true }
        if ($keyFile) { $keyParams.KeyFile = $keyFile }
        if ($hostnameOverride) { $keyParams.HostnameOverride = $hostnameOverride }

        $result = New-RSRSshKey @keyParams

        Write-RSRLog "SSH key generated successfully" -Level Success
        Write-Host ""
        Write-Host "  Private key: $($result.KeyFile)" -ForegroundColor Cyan
        Write-Host "  Public key:  $($result.PublicKey)" -ForegroundColor Cyan

        if ($result.PassphraseEncFile) {
            Write-Host "  Passphrase (encrypted): $($result.PassphraseEncFile)" -ForegroundColor Green
            Write-Host ""
            Write-Host "  To decrypt passphrase: sops --decrypt $($result.PassphraseEncFile)" -ForegroundColor Gray
        } elseif ($result.PassphraseFile) {
            Write-Host "  Passphrase (unencrypted): $($result.PassphraseFile)" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  ⚠ WARNING: Passphrase file is unencrypted!" -ForegroundColor Red
        }

        Write-Host ""

        # Show public key content for easy copying
        $pubKeyContent = Get-Content $result.PublicKey
        Write-Host "Public key content (copy this to remote servers):" -ForegroundColor Yellow
        Write-Host $pubKeyContent -ForegroundColor White
    } catch {
        Write-RSRLog "Failed to generate SSH key: $_" -Level Error
        exit 1
    }
}

function Invoke-SshAdd {
    param([string[]]$Args)

    $username = $null
    $keyFile = $null
    $keyContent = $null

    for ($i = 0; $i < $Args.Count; $i++) {
        switch ($Args[$i]) {
            { $_ -in '-u','--username' } { $username = $Args[++$i] }
            { $_ -in '-f','--file' } { $keyFile = $Args[++$i] }
            { $_ -in '-k','--key' } { $keyContent = $Args[++$i] }
        }
    }

    if (-not $username) {
        Write-RSRLog "Username is required" -Level Error
        exit 2
    }

    if (-not $keyFile -and -not $keyContent) {
        Write-RSRLog "Either --file or --key is required" -Level Error
        exit 2
    }

    Write-RSRHeader "Add SSH Key: $username"

    if ($Script:DryRun) {
        Write-RSRLog "[DRY RUN] Would add SSH key for: $username" -Level Info
        return
    }

    try {
        if ($keyFile) {
            $keyContent = Get-Content $keyFile -Raw
        }

        Add-RSRSshKey -Username $username -PublicKey $keyContent
        Write-RSRLog "SSH key added successfully" -Level Success
    } catch {
        Write-RSRLog "Failed to add SSH key: $_" -Level Error
        exit 1
    }
}

function Invoke-SshList {
    param([string[]]$Args)

    $username = $null
    for ($i = 0; $i < $Args.Count; $i++) {
        if ($Args[$i] -in '-u','--username') {
            $username = $Args[++$i]
        }
    }

    if (-not $username) {
        Write-RSRLog "Username is required" -Level Error
        exit 2
    }

    Write-RSRHeader "SSH Keys: $username"

    try {
        $keys = Get-RSRSshKeys -Username $username
        if ($keys) {
            $keys | ForEach-Object { Write-Host $_ }
        } else {
            Write-RSRLog "No SSH keys found for user '$username'" -Level Info
        }
    } catch {
        Write-RSRLog "Failed to list SSH keys: $_" -Level Error
        exit 1
    }
}

function Invoke-SshFix {
    param([string[]]$Args)

    $username = $null
    for ($i = 0; $i < $Args.Count; $i++) {
        if ($Args[$i] -in '-u','--username') {
            $username = $Args[++$i]
        }
    }

    if (-not $username) {
        Write-RSRLog "Username is required" -Level Error
        exit 2
    }

    Write-RSRHeader "Fix SSH Permissions: $username"

    if ($Script:DryRun) {
        Write-RSRLog "[DRY RUN] Would fix SSH permissions for: $username" -Level Info
        return
    }

    try {
        Set-RSRSshPermissions -Username $username
        Write-RSRLog "SSH permissions fixed successfully" -Level Success
    } catch {
        Write-RSRLog "Failed to fix SSH permissions: $_" -Level Error
        exit 1
    }
}

# =============================================================================
# Subcommand: Session Management
# =============================================================================

function Invoke-SessionCommand {
    param([string[]]$Args)

    if ($Args.Count -eq 0) {
        $Args = @('list')
    }

    $subcmd = $Args[0]
    $remaining = if ($Args.Count -gt 1) { $Args[1..($Args.Count-1)] } else { @() }

    switch ($subcmd) {
        'list' { Invoke-SessionList $remaining }
        'history' { Invoke-SessionHistory $remaining }
        default {
            Write-RSRLog "Unknown session subcommand: $subcmd" -Level Error
            exit 2
        }
    }
}

function Invoke-SessionList {
    Write-RSRHeader "Active User Sessions"

    $sessions = Get-RSRUserSessions
    if ($sessions) {
        $sessions | Format-Table -AutoSize
    } else {
        Write-RSRLog "No active sessions found" -Level Info
    }
}

function Invoke-SessionHistory {
    param([string[]]$Args)

    $username = $null
    $maxEvents = 20

    for ($i = 0; $i < $Args.Count; $i++) {
        switch ($Args[$i]) {
            { $_ -in '-u','--username' } { $username = $Args[++$i] }
            { $_ -in '-n','--lines' } { $maxEvents = [int]$Args[++$i] }
        }
    }

    Write-RSRHeader "Login History"

    $history = Get-RSRLoginHistory -Username $username -MaxEvents $maxEvents
    if ($history) {
        $history | Format-Table -AutoSize
    } else {
        Write-RSRLog "No login history available" -Level Info
    }
}

# =============================================================================
# Main Entry Point
# =============================================================================

function Main {
    # Parse global arguments
    $filteredArgs = Parse-GlobalArgs $Arguments

    if (-not $Command) {
        Show-Usage
        exit 0
    }

    # Route to subcommands
    switch ($Command) {
        'create' { Invoke-CreateUser $filteredArgs }
        'delete' { Invoke-DeleteUser $filteredArgs }
        'lock' { Invoke-LockUser $filteredArgs }
        'unlock' { Invoke-UnlockUser $filteredArgs }
        'list' { Invoke-ListUsers $filteredArgs }
        'password' { Invoke-PasswordCommand $filteredArgs }
        'group' { Invoke-GroupCommand $filteredArgs }
        'ssh' { Invoke-SshCommand $filteredArgs }
        'session' { Invoke-SessionCommand $filteredArgs }
        default {
            Write-RSRLog "Unknown command: $Command" -Level Error
            Write-Host "Run 'UserManagement.ps1 --help' for usage"
            exit 2
        }
    }
}

# Run main
try {
    Main
} catch {
    Write-RSRLog "Fatal error: $_" -Level Error
    exit 1
}

