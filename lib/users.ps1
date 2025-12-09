# lib/users.ps1 - Windows user management module for RSR
# PowerShell implementation mirroring lib/users.sh API
#
# Usage: Import-Module .\lib\users.ps1
# Or dot-source: . .\lib\users.ps1

#Requires -Version 5.1
#Requires -RunAsAdministrator

# =============================================================================
# Module Metadata
# =============================================================================

$Script:ModuleVersion = "1.0.0"
$Script:ModuleName = "RSR.Users"

# =============================================================================
# Logging Functions
# =============================================================================

function Write-RSRLog {
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

function Write-RSRHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host "═══ $Title ═══" -ForegroundColor Cyan
    Write-Host ""
}

# =============================================================================
# OS & Environment Detection
# =============================================================================

function Get-RSREnvironment {
    $info = @{
        IsWorkgroup = $true
        IsDomain = $false
        HasAD = $false
        ComputerName = $env:COMPUTERNAME
    }

    try {
        $cs = Get-WmiObject Win32_ComputerSystem
        $info.IsDomain = $cs.PartOfDomain
        $info.IsWorkgroup = -not $cs.PartOfDomain

        # Check for AD module
        $info.HasAD = $null -ne (Get-Module -ListAvailable ActiveDirectory)
    } catch {
        # Ignore errors
    }

    return $info
}

# =============================================================================
# User Existence & Info
# =============================================================================

function Test-RSRUserExists {
    <#
    .SYNOPSIS
        Check if user exists (cross-compatible with user_exists)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Username
    )

    try {
        $null = Get-LocalUser -Name $Username -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Get-RSRUserInfo {
    <#
    .SYNOPSIS
        Get user information (cross-compatible with user_get_info)
        Returns: PSCustomObject with UID, GID, Home, Shell equivalents
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Username
    )

    try {
        $user = Get-LocalUser -Name $Username -ErrorAction Stop

        return [PSCustomObject]@{
            Username = $user.Name
            SID = $user.SID.Value
            FullName = $user.FullName
            Description = $user.Description
            Enabled = $user.Enabled
            Home = "C:\Users\$($user.Name)"
            LastLogon = $user.LastLogon
            PasswordExpires = $user.PasswordExpires
            PasswordLastSet = $user.PasswordLastSet
        }
    } catch {
        return $null
    }
}

function Get-RSRAllUsers {
    <#
    .SYNOPSIS
        List all local users
    #>
    Get-LocalUser | Select-Object Name, FullName, Enabled, SID
}

function Get-RSRHumanUsers {
    <#
    .SYNOPSIS
        List human (non-system) users
    #>
    Get-LocalUser | Where-Object {
        $_.Name -notmatch '^(Administrator|Guest|DefaultAccount|WDAGUtilityAccount)$' -and
        $_.Enabled
    } | Select-Object Name, FullName, Enabled
}

# =============================================================================
# User Creation
# =============================================================================

function New-RSRUser {
    <#
    .SYNOPSIS
        Create new user account (cross-compatible with user_create)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [string]$FullName,
        [string]$Description,
        [SecureString]$Password,
        [switch]$NoPassword,
        [switch]$PasswordNeverExpires,
        [switch]$UserCannotChangePassword,
        [switch]$AccountNeverExpires
    )

    if (Test-RSRUserExists $Username) {
        throw "User '$Username' already exists"
    }

    $params = @{
        Name = $Username
    }

    if ($FullName) { $params.FullName = $FullName }
    if ($Description) { $params.Description = $Description }

    if ($Password) {
        $params.Password = $Password
    } elseif ($NoPassword) {
        $params.NoPassword = $true
    } else {
        # Generate random password if none provided
        $randomPass = New-RSRRandomPassword
        $params.Password = ConvertTo-SecureString $randomPass -AsPlainText -Force
        Write-RSRLog "Generated password: $randomPass" -Level Info
    }

    if ($PasswordNeverExpires) { $params.PasswordNeverExpires = $true }
    if ($UserCannotChangePassword) { $params.UserMayNotChangePassword = $true }
    if ($AccountNeverExpires) { $params.AccountNeverExpires = $true }

    New-LocalUser @params
}

# =============================================================================
# User Deletion
# =============================================================================

function Remove-RSRUser {
    <#
    .SYNOPSIS
        Delete user account (cross-compatible with user_delete)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [switch]$RemoveHome
    )

    if (-not (Test-RSRUserExists $Username)) {
        throw "User '$Username' does not exist"
    }

    # Safety check
    if ($Username -eq 'Administrator') {
        throw "Cannot delete Administrator account"
    }

    # Get home directory before deletion
    $homeDir = "C:\Users\$Username"

    # Delete user
    Remove-LocalUser -Name $Username

    # Remove home directory if requested
    if ($RemoveHome -and (Test-Path $homeDir)) {
        Remove-Item -Path $homeDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# User Modification
# =============================================================================

function Lock-RSRUser {
    <#
    .SYNOPSIS
        Lock/disable user account (cross-compatible with user_lock)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Username
    )

    if (-not (Test-RSRUserExists $Username)) {
        throw "User '$Username' does not exist"
    }

    Disable-LocalUser -Name $Username
}

function Unlock-RSRUser {
    <#
    .SYNOPSIS
        Unlock/enable user account (cross-compatible with user_unlock)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Username
    )

    if (-not (Test-RSRUserExists $Username)) {
        throw "User '$Username' does not exist"
    }

    Enable-LocalUser -Name $Username
}

function Set-RSRUserFullName {
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$FullName
    )

    Set-LocalUser -Name $Username -FullName $FullName
}

function Set-RSRUserDescription {
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$Description
    )

    Set-LocalUser -Name $Username -Description $Description
}

# =============================================================================
# Password Management
# =============================================================================

function Set-RSRUserPassword {
    <#
    .SYNOPSIS
        Set user password (cross-compatible with password_set_string)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [SecureString]$Password
    )

    if (-not (Test-RSRUserExists $Username)) {
        throw "User '$Username' does not exist"
    }

    Set-LocalUser -Name $Username -Password $Password
}

function New-RSRRandomPassword {
    <#
    .SYNOPSIS
        Generate random password (cross-compatible with password_generate)
    #>
    param(
        [int]$Length = 16
    )

    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*'
    $password = -join ((1..$Length) | ForEach-Object {
        $chars[(Get-Random -Maximum $chars.Length)]
    })

    return $password
}

function Set-RSRPasswordExpiry {
    <#
    .SYNOPSIS
        Force password change on next login
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Username
    )

    if (-not (Test-RSRUserExists $Username)) {
        throw "User '$Username' does not exist"
    }

    # Set password to expired (user must change on next login)
    $user = Get-LocalUser -Name $Username
    $user.PasswordExpires = (Get-Date).AddDays(-1)
    $user | Set-LocalUser
}

function Get-RSRPasswordPolicy {
    <#
    .SYNOPSIS
        Get password policy information
    #>

    $policy = net accounts | Select-String "Password" -Context 0,0
    return $policy
}

# =============================================================================
# Group Management
# =============================================================================

function Test-RSRGroupExists {
    param(
        [Parameter(Mandatory)]
        [string]$GroupName
    )

    try {
        $null = Get-LocalGroup -Name $GroupName -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function New-RSRGroup {
    <#
    .SYNOPSIS
        Create new group (cross-compatible with group_create)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$GroupName,

        [string]$Description
    )

    if (Test-RSRGroupExists $GroupName) {
        throw "Group '$GroupName' already exists"
    }

    $params = @{ Name = $GroupName }
    if ($Description) { $params.Description = $Description }

    New-LocalGroup @params
}

function Add-RSRGroupMember {
    <#
    .SYNOPSIS
        Add user to group (cross-compatible with group_add_member)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$GroupName,

        [Parameter(Mandatory)]
        [string]$Username
    )

    if (-not (Test-RSRGroupExists $GroupName)) {
        throw "Group '$GroupName' does not exist"
    }

    if (-not (Test-RSRUserExists $Username)) {
        throw "User '$Username' does not exist"
    }

    Add-LocalGroupMember -Group $GroupName -Member $Username
}

function Remove-RSRGroupMember {
    <#
    .SYNOPSIS
        Remove user from group (cross-compatible with group_remove_member)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$GroupName,

        [Parameter(Mandatory)]
        [string]$Username
    )

    if (-not (Test-RSRGroupExists $GroupName)) {
        throw "Group '$GroupName' does not exist"
    }

    Remove-LocalGroupMember -Group $GroupName -Member $Username
}

function Get-RSRGroupMembers {
    <#
    .SYNOPSIS
        List group members (cross-compatible with group_list_members)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$GroupName
    )

    if (-not (Test-RSRGroupExists $GroupName)) {
        throw "Group '$GroupName' does not exist"
    }

    Get-LocalGroupMember -Group $GroupName | Select-Object -ExpandProperty Name
}

function Test-RSRUserHasAdmin {
    <#
    .SYNOPSIS
        Check if user has administrator privileges
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Username
    )

    try {
        $members = Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop
        return ($members.Name -contains $Username -or $members.Name -contains "$env:COMPUTERNAME\$Username")
    } catch {
        return $false
    }
}

# =============================================================================
# SSH Key Management
# =============================================================================

function Get-RSRSshDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$Username
    )

    $userHome = "C:\Users\$Username"
    return Join-Path $userHome ".ssh"
}

function Get-RSRSshAuthorizedKeysPath {
    <#
    .SYNOPSIS
        Get path to authorized_keys (handles admin special case)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Username
    )

    # Check if user is administrator
    if (Test-RSRUserHasAdmin $Username) {
        # Administrators use ProgramData location
        return "$env:ProgramData\ssh\administrators_authorized_keys"
    } else {
        # Regular users use home directory
        $sshDir = Get-RSRSshDirectory $Username
        return Join-Path $sshDir "authorized_keys"
    }
}

function New-RSRSshKey {
    <#
    .SYNOPSIS
        Generate SSH key pair for user with optional passphrase
    .DESCRIPTION
        Generates SSH key pairs using ssh-keygen with security best practices:
        - Ed25519 (default, recommended) with 100 rounds for stronger key derivation
        - Purpose-based naming: id_ed25519_purpose
        - Descriptive comment: user@hostname purpose (hostname)
        - Optional passphrase generation and SOPS encryption

        Reference: https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement
    .PARAMETER Username
        User to generate key for
    .PARAMETER Type
        Key algorithm: ed25519 (default, recommended), ecdsa, or rsa
    .PARAMETER Purpose
        Purpose/label for the key (e.g., 'github', 'work', 'backup').
        Used in filename and comment. Default: 'default'
    .PARAMETER Bits
        Key size for RSA keys (default: 4096). Not used for ed25519.
    .PARAMETER Rounds
        Key derivation rounds for ed25519/ecdsa (default: 100). Higher = more secure but slower.
    .PARAMETER Comment
        Custom comment. If not provided, auto-generates: "user@hostname purpose (hostname)"
    .PARAMETER Passphrase
        Passphrase to encrypt the private key. If not provided, key will be unencrypted.
    .PARAMETER GeneratePassphrase
        Auto-generate a strong random passphrase (24 chars, alphanumeric + symbols)
    .PARAMETER PassphraseLength
        Length of auto-generated passphrase (default: 24, min: 12)
    .PARAMETER EncryptWithSops
        Encrypt the passphrase using SOPS and save to .passphrase.enc file
    .PARAMETER SopsAge
        Use age encryption with SOPS (requires age public key)
    .PARAMETER OutputPassphrase
        Display the generated passphrase (if GeneratePassphrase is used)
    .PARAMETER KeyFile
        Override key file path (useful for non-standard locations)
    .PARAMETER HostnameOverride
        Override hostname in comment (useful for generating keys on behalf of other systems)
    .EXAMPLE
        New-RSRSshKey -Username "john" -Purpose "github"
        # Creates: ~/.ssh/id_ed25519_github with comment "john@MYPC github (MYPC)"
    .EXAMPLE
        New-RSRSshKey -Username "john" -Type "rsa" -Purpose "legacy" -Bits 4096
        # Creates: ~/.ssh/id_rsa_legacy
    .EXAMPLE
        New-RSRSshKey -Username "john" -Purpose "prod" -GeneratePassphrase -EncryptWithSops
        # Generates key with random passphrase, encrypts with SOPS
    .EXAMPLE
        New-RSRSshKey -Username "john" -Purpose "github" -GeneratePassphrase -OutputPassphrase
        # Generates key with passphrase and displays it
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [ValidateSet('ed25519','ecdsa','rsa')]
        [string]$Type = 'ed25519',

        [string]$Purpose = 'default',

        [int]$Bits = 4096,

        [int]$Rounds = 100,

        [string]$Comment,

        [string]$Passphrase,

        [switch]$GeneratePassphrase,

        [ValidateRange(12, 128)]
        [int]$PassphraseLength = 24,

        [switch]$EncryptWithSops,

        [string]$SopsAge,

        [switch]$OutputPassphrase,

        [string]$KeyFile,

        [string]$HostnameOverride
    )

    if (-not (Test-RSRUserExists $Username)) {
        throw "User '$Username' does not exist"
    }

    $sshDir = Get-RSRSshDirectory $Username
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    # Sanitize purpose for filename (lowercase, alphanumeric and hyphens only)
    $safePurpose = ($Purpose -replace '[^a-zA-Z0-9-]', '-').ToLower()

    # Determine key file name with purpose
    # Format: id_<type>_<purpose> (e.g., id_ed25519_github)
    if ($KeyFile) {
        $keyFile = $KeyFile
    } else {
        $keyFile = Join-Path $sshDir "id_${Type}_${safePurpose}"
    }

    if (Test-Path $keyFile) {
        throw "Key already exists: $keyFile. Use a different purpose or remove existing key."
    }

    # Get short hostname dynamically (not FQDN)
    # Use hostname command to get actual short hostname, fallback to env var
    if ($HostnameOverride) {
        $hostname = $HostnameOverride
    } else {
        try {
            $hostname = (hostname).Split('.')[0]
        } catch {
            $hostname = $env:COMPUTERNAME
        }
    }

    # Build descriptive comment: "user@hostname purpose (hostname)"
    # Example: "john@laptop github (laptop)"
    if (-not $Comment) {
        $Comment = "${Username}@${hostname} ${Purpose} (${hostname})"
    }

    # Handle passphrase generation
    $actualPassphrase = ''
    $passphraseFile = "${keyFile}.passphrase"
    $passphraseEncFile = "${keyFile}.passphrase.enc"

    if ($GeneratePassphrase) {
        # Generate strong random passphrase
        # Use mix of alphanumeric + symbols for strong entropy
        $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+[]{}|;:,.<>?'
        $random = New-Object System.Random
        $actualPassphrase = -join (1..$PassphraseLength | ForEach-Object { $chars[$random.Next($chars.Length)] })

        Write-RSRLog "Generated random passphrase ($PassphraseLength characters)" -Level Success
    } elseif ($Passphrase) {
        $actualPassphrase = $Passphrase
    }

    # Handle SOPS encryption if requested
    if ($actualPassphrase -and $EncryptWithSops) {
        # Check if sops is available
        if (-not (Get-Command sops -ErrorAction SilentlyContinue)) {
            Write-RSRLog "SOPS not found. Install from: https://github.com/mozilla/sops" -Level Warning
            Write-RSRLog "Saving passphrase to: $passphraseFile" -Level Warning
            $actualPassphrase | Out-File -FilePath $passphraseFile -NoNewline -Encoding UTF8
        } else {
            # Save passphrase to temp file
            $tempPassFile = [System.IO.Path]::GetTempFileName()
            $actualPassphrase | Out-File -FilePath $tempPassFile -NoNewline -Encoding UTF8

            try {
                # Encrypt with SOPS
                $sopsArgs = @('--encrypt')

                if ($SopsAge) {
                    $sopsArgs += @('--age', $SopsAge)
                }

                $sopsArgs += @('--output', $passphraseEncFile, $tempPassFile)

                & sops @sopsArgs

                if ($LASTEXITCODE -eq 0) {
                    Write-RSRLog "Passphrase encrypted with SOPS: $passphraseEncFile" -Level Success
                    # Remove temp file
                    Remove-Item $tempPassFile -Force -ErrorAction SilentlyContinue
                } else {
                    throw "SOPS encryption failed with exit code $LASTEXITCODE"
                }
            } catch {
                Write-RSRLog "SOPS encryption failed: $_" -Level Error
                Write-RSRLog "Saving unencrypted passphrase to: $passphraseFile" -Level Warning
                $actualPassphrase | Out-File -FilePath $passphraseFile -NoNewline -Encoding UTF8
                Remove-Item $tempPassFile -Force -ErrorAction SilentlyContinue
            }
        }
    } elseif ($actualPassphrase -and -not $EncryptWithSops) {
        # Save passphrase unencrypted if not using SOPS
        Write-RSRLog "Saving passphrase to: $passphraseFile" -Level Info
        $actualPassphrase | Out-File -FilePath $passphraseFile -NoNewline -Encoding UTF8

        # Warn about unencrypted passphrase
        Write-RSRLog "WARNING: Passphrase saved unencrypted. Use -EncryptWithSops for better security." -Level Warning
    }

    # Build ssh-keygen arguments
    # -t: key type
    # -f: output file
    # -C: comment
    # -N: passphrase (empty string for no passphrase)
    $sshKeygenArgs = @('-t', $Type, '-f', $keyFile, '-C', $Comment, '-N', $actualPassphrase)

    # Add key-specific options
    switch ($Type) {
        'ed25519' {
            # -a: KDF rounds (higher = more secure, slower to crack)
            $sshKeygenArgs = @('-a', $Rounds) + $sshKeygenArgs
        }
        'ecdsa' {
            # -a: KDF rounds for ECDSA as well
            $sshKeygenArgs = @('-a', $Rounds) + $sshKeygenArgs
        }
        'rsa' {
            # -b: bit size for RSA
            $sshKeygenArgs = @('-b', $Bits) + $sshKeygenArgs
        }
    }

    # Generate the key
    & ssh-keygen @sshKeygenArgs

    if ($LASTEXITCODE -ne 0) {
        throw "ssh-keygen failed with exit code $LASTEXITCODE"
    }

    # Fix permissions (handles both standard and admin users)
    Set-RSRSshPermissions -Username $Username

    # Output passphrase if requested
    if ($OutputPassphrase -and $actualPassphrase) {
        Write-Host ""
        Write-Host "Generated Passphrase:" -ForegroundColor Yellow
        Write-Host $actualPassphrase -ForegroundColor White
        Write-Host ""
        Write-Host "⚠ WARNING: Store this passphrase securely!" -ForegroundColor Red
        Write-Host ""
    }

    # Return result object
    return [PSCustomObject]@{
        KeyFile = $keyFile
        PublicKey = "${keyFile}.pub"
        PassphraseFile = if (Test-Path $passphraseFile) { $passphraseFile } else { $null }
        PassphraseEncFile = if (Test-Path $passphraseEncFile) { $passphraseEncFile } else { $null }
        HasPassphrase = [bool]$actualPassphrase
    }
}

function Add-RSRSshKey {
    <#
    .SYNOPSIS
        Add SSH public key to authorized_keys
    .DESCRIPTION
        Adds a public key to the appropriate authorized_keys location:
        - Standard users: ~/.ssh/authorized_keys
        - Administrators: C:\ProgramData\ssh\administrators_authorized_keys
        Reference: https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$PublicKey
    )

    if (-not (Test-RSRUserExists $Username)) {
        throw "User '$Username' does not exist"
    }

    # Validate key format (supports RSA, Ed25519, DSA, and ECDSA)
    if ($PublicKey -notmatch '^(ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-sha2-)') {
        throw "Invalid SSH public key format"
    }

    $sshDir = Get-RSRSshDirectory $Username
    $authKeys = Get-RSRSshAuthorizedKeysPath $Username
    $isAdmin = Test-RSRUserHasAdmin $Username

    # Create .ssh directory in user's home (always needed for private keys)
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    # For administrators, also ensure ProgramData\ssh directory exists
    if ($isAdmin) {
        $sshProgramData = "$env:ProgramData\ssh"
        if (-not (Test-Path $sshProgramData)) {
            New-Item -ItemType Directory -Path $sshProgramData -Force | Out-Null
        }
    }

    # Check for duplicate
    if (Test-Path $authKeys) {
        $existing = Get-Content $authKeys -ErrorAction SilentlyContinue
        if ($existing) {
            $keyFingerprint = ($PublicKey -split '\s+')[1]
            if ($existing -match [regex]::Escape($keyFingerprint)) {
                throw "Key already exists in authorized_keys"
            }
        }
    }

    # Add key
    Add-Content -Path $authKeys -Value $PublicKey -Force

    # Fix permissions (handles administrator vs standard user cases)
    Set-RSRSshPermissions -Username $Username
}

function Remove-RSRSshKey {
    <#
    .SYNOPSIS
        Remove SSH key from authorized_keys
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$Identifier
    )

    $authKeys = Get-RSRSshAuthorizedKeysPath $Username

    if (-not (Test-Path $authKeys)) {
        throw "No authorized_keys file found"
    }

    # Create backup
    Copy-Item $authKeys "$authKeys.backup"

    # Remove matching lines
    $content = Get-Content $authKeys
    $newContent = $content | Where-Object { $_ -notmatch [regex]::Escape($Identifier) }

    if ($content.Count -eq $newContent.Count) {
        throw "No matching key found"
    }

    $newContent | Set-Content $authKeys
}

function Get-RSRSshKeys {
    <#
    .SYNOPSIS
        List SSH authorized keys
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Username
    )

    $authKeys = Get-RSRSshAuthorizedKeysPath $Username

    if (Test-Path $authKeys) {
        Get-Content $authKeys
    }
}

function Set-RSRSshPermissions {
    <#
    .SYNOPSIS
        Fix SSH directory and file permissions
    .DESCRIPTION
        Sets proper ACLs for SSH files according to Windows OpenSSH requirements:
        - Standard users: ~/.ssh/authorized_keys owned by user
        - Administrators: C:\ProgramData\ssh\administrators_authorized_keys
          with ACL for Administrators and SYSTEM only
        Reference: https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Username
    )

    $sshDir = Get-RSRSshDirectory $Username
    $isAdmin = Test-RSRUserHasAdmin $Username

    # Create .ssh directory if needed
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    # Get user SID
    $user = Get-LocalUser -Name $Username
    $userSid = $user.SID

    # Fix .ssh directory (equivalent to chmod 700)
    $acl = Get-Acl $sshDir
    $acl.SetAccessRuleProtection($true, $false)
    $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }

    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $userSid, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $acl.AddAccessRule($rule)
    Set-Acl -Path $sshDir -AclObject $acl

    # Handle authorized_keys based on user type
    if ($isAdmin) {
        # Administrators use ProgramData location with special ACL
        # Reference: https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement
        $adminAuthKeys = "$env:ProgramData\ssh\administrators_authorized_keys"

        # Create ProgramData\ssh directory if needed
        $sshProgramData = "$env:ProgramData\ssh"
        if (-not (Test-Path $sshProgramData)) {
            New-Item -ItemType Directory -Path $sshProgramData -Force | Out-Null
        }

        if (Test-Path $adminAuthKeys) {
            # Set ACL: Only Administrators and SYSTEM should have access
            # Using icacls as recommended by Microsoft documentation
            # /inheritance:r = Remove inherited permissions
            # /grant "Administrators:F" = Full control for Administrators group
            # /grant "SYSTEM:F" = Full control for SYSTEM
            # Using SIDs for localization compatibility:
            # S-1-5-32-544 = Administrators
            # S-1-5-18 = SYSTEM
            & icacls.exe $adminAuthKeys /inheritance:r /grant "*S-1-5-32-544:F" /grant "*S-1-5-18:F" | Out-Null
        }
    } else {
        # Standard users use home directory authorized_keys
        $authKeys = Join-Path $sshDir "authorized_keys"
        if (Test-Path $authKeys) {
            $acl = Get-Acl $authKeys
            $acl.SetAccessRuleProtection($true, $false)
            $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }

            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $userSid, "FullControl", "Allow"
            )
            $acl.AddAccessRule($rule)
            Set-Acl -Path $authKeys -AclObject $acl
        }
    }

    # Fix private keys (same for all users)
    Get-ChildItem $sshDir -Filter "id_*" -Exclude "*.pub" -ErrorAction SilentlyContinue | ForEach-Object {
        $acl = Get-Acl $_.FullName
        $acl.SetAccessRuleProtection($true, $false)
        $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }

        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $userSid, "FullControl", "Allow"
        )
        $acl.AddAccessRule($rule)
        Set-Acl -Path $_.FullName -AclObject $acl
    }
}

# =============================================================================
# Session Management
# =============================================================================

function Get-RSRUserSessions {
    <#
    .SYNOPSIS
        List active user sessions
    #>

    query user 2>$null | Select-Object -Skip 1 | ForEach-Object {
        if ($_ -match '^\s*(\S+)\s+(\S+)?\s+(\d+)\s+(\w+)\s+(.+)$') {
            [PSCustomObject]@{
                Username = $Matches[1]
                SessionName = $Matches[2]
                ID = $Matches[3]
                State = $Matches[4]
                IdleTime = $Matches[5]
            }
        }
    }
}

function Get-RSRLoginHistory {
    <#
    .SYNOPSIS
        Get login history from Event Log
    #>
    param(
        [string]$Username,
        [int]$MaxEvents = 20
    )

    $filter = @{
        LogName = 'Security'
        ID = 4624  # Successful logon
    }

    if ($Username) {
        $filter.ProviderName = 'Microsoft-Windows-Security-Auditing'
    }

    try {
        Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEvents -ErrorAction Stop |
            Select-Object TimeCreated,
                @{Name='Username';Expression={$_.Properties[5].Value}},
                @{Name='LogonType';Expression={$_.Properties[8].Value}}
    } catch {
        Write-RSRLog "Login history not available" -Level Warning
    }
}

# =============================================================================
# Permission Management
# =============================================================================

function Set-RSRPermission {
    <#
    .SYNOPSIS
        Set file/folder permissions (Windows ACL equivalent)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Owner,

        [ValidateSet('FullControl','Modify','ReadAndExecute','Read','Write')]
        [string]$Permission = 'Read'
    )

    if (-not (Test-Path $Path)) {
        throw "Path '$Path' does not exist"
    }

    $acl = Get-Acl $Path

    # Set owner
    $user = New-Object System.Security.Principal.NTAccount($Owner)
    $acl.SetOwner($user)

    # Set permissions
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $user, $Permission, "Allow"
    )
    $acl.AddAccessRule($rule)

    Set-Acl -Path $Path -AclObject $acl
}

# =============================================================================
# Module Initialization
# =============================================================================

# Check for Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Warning "Most RSR user management operations require Administrator privileges"
    Write-Warning "Run PowerShell as Administrator for full functionality"
}

# Export functions
Export-ModuleMember -Function *-RSR*

# =============================================================================
# Secret Generation Functions
# =============================================================================

function New-RSRSecret {
    <#
    .SYNOPSIS
        Generate secure random secrets (passwords, API keys, tokens, etc.)
    .DESCRIPTION
        Generates cryptographically secure random secrets with various character sets and formats.
        Supports passwords, API keys, hex tokens, base64 tokens, and custom character sets.
    .PARAMETER Type
        Secret type: password (default), apikey, hex, base64, alphanumeric, numeric, custom
    .PARAMETER Length
        Length of the secret (default: 32)
    .PARAMETER IncludeSymbols
        Include symbols in password/apikey generation (default: true)
    .PARAMETER ExcludeAmbiguous
        Exclude ambiguous characters like 0/O, 1/l/I (default: false)
    .PARAMETER CustomCharset
        Custom character set for type 'custom'
    .PARAMETER Prefix
        Add a prefix to the secret (useful for API keys)
    .PARAMETER Separator
        Add separators every N characters (e.g., "xxxx-xxxx-xxxx")
    .PARAMETER SeparatorChar
        Character to use as separator (default: "-")
    .PARAMETER SeparatorInterval
        Interval for separators (default: 4)
    .PARAMETER EncryptWithSops
        Encrypt the secret with SOPS
    .PARAMETER SopsAge
        Age public key for SOPS encryption
    .PARAMETER OutputToFile
        Save secret to file
    .EXAMPLE
        New-RSRSecret -Type password -Length 24
        # Generates: xK9mP2nQ8vR4!jL7@tA5yB3c
    .EXAMPLE
        New-RSRSecret -Type apikey -Prefix "sk_live_" -Length 32
        # Generates: sk_live_mP2nQ8vR4jL7tA5yB3cW1zX6fD9h
    .EXAMPLE
        New-RSRSecret -Type hex -Length 64
        # Generates: 3a5f7c9e2b4d6f8a1c3e5f7b9d2e4f6a...
    .EXAMPLE
        New-RSRSecret -Type apikey -Length 32 -Separator -SeparatorInterval 8
        # Generates: xK9mP2nQ-8vR4jL7t-A5yB3cW1-zX6fD9h
    #>
    param(
        [ValidateSet('password','apikey','hex','base64','alphanumeric','numeric','custom')]
        [string]$Type = 'password',

        [ValidateRange(8, 256)]
        [int]$Length = 32,

        [bool]$IncludeSymbols = $true,

        [switch]$ExcludeAmbiguous,

        [string]$CustomCharset,

        [string]$Prefix,

        [switch]$Separator,

        [string]$SeparatorChar = '-',

        [int]$SeparatorInterval = 4,

        [switch]$EncryptWithSops,

        [string]$SopsAge,

        [string]$OutputToFile
    )

    # Define character sets
    $charsets = @{
        lowercase = 'abcdefghijklmnopqrstuvwxyz'
        uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        numbers = '0123456789'
        symbols = '!@#$%^&*()-_=+[]{}|;:,.<>?'
        hex = '0123456789abcdef'
        base64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
        alphanumeric = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    }

    # Ambiguous characters to exclude
    $ambiguous = '0O1lI'

    # Build character set based on type
    $charset = ''
    switch ($Type) {
        'password' {
            $charset = $charsets.lowercase + $charsets.uppercase + $charsets.numbers
            if ($IncludeSymbols) {
                $charset += $charsets.symbols
            }
        }
        'apikey' {
            $charset = $charsets.alphanumeric
        }
        'hex' {
            $charset = $charsets.hex
        }
        'base64' {
            # For base64, generate random bytes and encode
            $bytes = New-Object byte[] $Length
            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            $rng.GetBytes($bytes)
            $secret = [Convert]::ToBase64String($bytes).Substring(0, $Length)

            if ($Prefix) {
                $secret = $Prefix + $secret
            }

            return $secret
        }
        'alphanumeric' {
            $charset = $charsets.alphanumeric
        }
        'numeric' {
            $charset = $charsets.numbers
        }
        'custom' {
            if (-not $CustomCharset) {
                throw "CustomCharset is required when Type is 'custom'"
            }
            $charset = $CustomCharset
        }
    }

    # Remove ambiguous characters if requested
    if ($ExcludeAmbiguous) {
        foreach ($char in $ambiguous.ToCharArray()) {
            $charset = $charset -replace [regex]::Escape($char), ''
        }
    }

    # Generate cryptographically secure random secret
    $random = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $bytes = New-Object byte[] 1
    $secret = ''

    for ($i = 0; $i -lt $Length; $i++) {
        do {
            $random.GetBytes($bytes)
            $index = $bytes[0] % $charset.Length
        } while ($index -ge $charset.Length)  # Ensure uniform distribution

        $secret += $charset[$index]
    }

    # Add prefix if specified
    if ($Prefix) {
        $secret = $Prefix + $secret
    }

    # Add separators if requested
    if ($Separator) {
        $parts = @()
        $secretLength = $secret.Length
        for ($i = 0; $i -lt $secretLength; $i += $SeparatorInterval) {
            $end = [Math]::Min($i + $SeparatorInterval, $secretLength)
            $parts += $secret.Substring($i, $end - $i)
        }
        $secret = $parts -join $SeparatorChar
    }

    # Handle SOPS encryption if requested
    if ($EncryptWithSops) {
        if (-not (Get-Command sops -ErrorAction SilentlyContinue)) {
            Write-RSRLog "SOPS not found. Install from: https://github.com/mozilla/sops" -Level Warning

            if ($OutputToFile) {
                $secret | Out-File -FilePath $OutputToFile -NoNewline -Encoding UTF8
                Write-RSRLog "Secret saved unencrypted to: $OutputToFile" -Level Warning
            }
        } else {
            # Create temp file
            $tempFile = [System.IO.Path]::GetTempFileName()
            $secret | Out-File -FilePath $tempFile -NoNewline -Encoding UTF8

            try {
                $outputFile = if ($OutputToFile) { $OutputToFile } else { "$tempFile.enc" }

                $sopsArgs = @('--encrypt')
                if ($SopsAge) {
                    $sopsArgs += @('--age', $SopsAge)
                }
                $sopsArgs += @('--output', $outputFile, $tempFile)

                & sops @sopsArgs

                if ($LASTEXITCODE -eq 0) {
                    Write-RSRLog "Secret encrypted with SOPS: $outputFile" -Level Success
                    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                    return [PSCustomObject]@{
                        Secret = '[ENCRYPTED]'
                        EncryptedFile = $outputFile
                        Type = $Type
                        Length = $Length
                    }
                } else {
                    throw "SOPS encryption failed"
                }
            } catch {
                Write-RSRLog "SOPS encryption failed: $_" -Level Error
                Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

                if ($OutputToFile) {
                    $secret | Out-File -FilePath $OutputToFile -NoNewline -Encoding UTF8
                    Write-RSRLog "Secret saved unencrypted to: $OutputToFile" -Level Warning
                }
            }
        }
    } elseif ($OutputToFile) {
        # Save to file without encryption
        $secret | Out-File -FilePath $OutputToFile -NoNewline -Encoding UTF8
        Write-RSRLog "Secret saved to: $OutputToFile" -Level Info
        Write-RSRLog "WARNING: Secret file is unencrypted!" -Level Warning
    }

    return $secret
}

function New-RSRPassword {
    <#
    .SYNOPSIS
        Generate a secure password (convenience wrapper for New-RSRSecret)
    .EXAMPLE
        New-RSRPassword -Length 24 -ExcludeAmbiguous
    #>
    param(
        [int]$Length = 16,
        [switch]$ExcludeAmbiguous,
        [bool]$IncludeSymbols = $true
    )

    New-RSRSecret -Type password -Length $Length -IncludeSymbols $IncludeSymbols -ExcludeAmbiguous:$ExcludeAmbiguous
}

function New-RSRApiKey {
    <#
    .SYNOPSIS
        Generate an API key (convenience wrapper for New-RSRSecret)
    .EXAMPLE
        New-RSRApiKey -Prefix "sk_live_" -Length 32
    #>
    param(
        [string]$Prefix,
        [int]$Length = 32,
        [switch]$Separator
    )

    $params = @{
        Type = 'apikey'
        Length = $Length
    }
    if ($Prefix) { $params.Prefix = $Prefix }
    if ($Separator) { $params.Separator = $true }

    New-RSRSecret @params
}

function New-RSRToken {
    <#
    .SYNOPSIS
        Generate a hex or base64 token (convenience wrapper for New-RSRSecret)
    .EXAMPLE
        New-RSRToken -Type hex -Length 64
    #>
    param(
        [ValidateSet('hex','base64')]
        [string]$Type = 'hex',
        [int]$Length = 32
    )

    New-RSRSecret -Type $Type -Length $Length
}

# =============================================================================
# End Secret Generation Functions
# =============================================================================
