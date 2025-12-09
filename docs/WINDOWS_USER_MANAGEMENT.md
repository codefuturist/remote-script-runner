# Windows User Management Guide

Complete guide for using RSR user management on Windows with PowerShell.

## Quick Start

### Installation

1. **Clone or download** the Remote Script Runner repository
2. **Open PowerShell as Administrator** (required for user management)
3. **Navigate** to the RSR directory

### Basic Usage

```powershell
# Using rsr.cmd (from Command Prompt or PowerShell)
rsr usermgmt create -u john -c "John Doe"

# Using rsr.ps1 (PowerShell)
.\rsr.ps1 usermgmt create -u john -c "John Doe"

# Direct PowerShell script
.\scripts\powershell\UserManagement.ps1 create -u john -c "John Doe"
```

## Platform Differences

### Command Syntax (Identical)

These commands work the same on Linux, macOS, and Windows:

```bash
rsr usermgmt create -u john -c "John Doe"
rsr usermgmt delete -u john --remove-home
rsr usermgmt password reset -u john
rsr usermgmt group add -u john -g Administrators  # "sudo" on Unix
rsr usermgmt ssh add -u john -f key.pub
rsr usermgmt session list
```

### Implementation Differences

| Feature | Unix | Windows PowerShell |
|---------|------|-------------------|
| User Creation | `useradd` / `dscl` | `New-LocalUser` |
| User Deletion | `userdel` | `Remove-LocalUser` |
| Lock Account | `usermod -L` | `Disable-LocalUser` |
| Password Set | `chpasswd` | `Set-LocalUser -Password` |
| Groups | `usermod -aG` | `Add-LocalGroupMember` |
| Admin Group | `sudo` / `wheel` | `Administrators` |
| Home Directory | `/home/user` | `C:\Users\user` |
| SSH Keys | `~/.ssh/` | `.ssh\` or `ProgramData\ssh\` |

## Windows-Specific Features

### Local vs Domain Users

```powershell
# Local users (default)
rsr usermgmt create -u john

# Domain users (requires AD module and domain-joined PC)
# Automatically detected - uses New-ADUser if available
```

### Administrator Privileges

Most operations require running PowerShell as Administrator:

```powershell
# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Please run PowerShell as Administrator"
}
```

### SSH Keys on Windows

Windows OpenSSH has special handling for administrators:

**Regular Users:**
- Keys: `C:\Users\username\.ssh\authorized_keys`

**Administrators:**
- Keys: `C:\ProgramData\ssh\administrators_authorized_keys`
- Requires special ACL permissions

```powershell
# Generate and add SSH key
rsr usermgmt ssh generate -u john -t ed25519
rsr usermgmt ssh add -u john -f C:\path\to\key.pub

# Fix permissions (important on Windows)
rsr usermgmt ssh fix -u john
```

## Complete Command Examples

### User Creation

```powershell
# Create basic user
rsr usermgmt create -u john -c "John Doe"

# Create with generated password
rsr usermgmt create -u jane --generate

# Create and add to groups
rsr usermgmt create -u admin -c "Admin User" -g Administrators,Users

# Create with specific password
rsr usermgmt create -u service -p "MyP@ssw0rd"
```

### User Management

```powershell
# List all users
rsr usermgmt list

# List only administrators
rsr usermgmt list --admin

# Lock user account (disable)
rsr usermgmt lock -u john

# Unlock user account
rsr usermgmt unlock -u john

# Delete user
rsr usermgmt delete -u john

# Delete user and remove home directory
rsr usermgmt delete -u john --remove-home
```

### Password Management

```powershell
# Reset password (interactive)
rsr usermgmt password reset -u john

# Generate random password
rsr usermgmt password generate

# Generate 20-character password
rsr usermgmt password generate --length 20

# Generate and set for user
rsr usermgmt password generate -u john --set

# Force password change on next login
rsr usermgmt password expire -u john

# View password policy
rsr usermgmt password policy
```

### Group Management

```powershell
# Add user to Administrators group
rsr usermgmt group add -u john -g Administrators

# Add to multiple groups (via separate commands)
rsr usermgmt group add -u john -g "Remote Desktop Users"
rsr usermgmt group add -u john -g Developers

# List group members
rsr usermgmt group list -g Administrators

# Show user's groups
rsr usermgmt group show -u john

# Remove from group
rsr usermgmt group remove -u john -g Developers
```

### SSH Key Management

```powershell
# Generate Ed25519 key (recommended)
rsr usermgmt ssh generate -u john -t ed25519

# Generate RSA 4096 key (traditional)
rsr usermgmt ssh generate -u john -t rsa -b 4096

# Add key from file
rsr usermgmt ssh add -u john -f C:\Users\Admin\.ssh\id_rsa.pub

# Add key from string
$key = Get-Content C:\keys\john.pub -Raw
rsr usermgmt ssh add -u john -k $key

# List keys
rsr usermgmt ssh list -u john

# Remove key (by comment or fingerprint)
rsr usermgmt ssh remove -u john -i "john@laptop"

# Fix SSH permissions (important!)
rsr usermgmt ssh fix -u john
```

### Session Monitoring

```powershell
# List active sessions
rsr usermgmt session list

# View login history (requires Event Log access)
rsr usermgmt session history

# View specific user's history
rsr usermgmt session history -u john -n 50
```

## Common Windows Scenarios

### Setup New Developer

```powershell
# Create developer account
rsr usermgmt create -u developer -c "Development User" -g Developers

# Generate SSH key
rsr usermgmt ssh generate -u developer -t ed25519

# Add to Docker group (if Docker Desktop installed)
rsr usermgmt group add -u developer -g "docker-users"

# Show summary
rsr usermgmt list | Where-Object { $_ -match "developer" }
```

### Setup Service Account

```powershell
# Create service account (no password expiration)
rsr usermgmt create -u svc_app -c "Application Service"

# Set specific password
rsr usermgmt password reset -u svc_app -p "S3rv1c3P@ss"

# Add to required groups
rsr usermgmt group add -u svc_app -g "IIS_IUSRS"

# Grant Log on as a service right (via Local Security Policy)
# This requires additional configuration outside RSR
```

### Contractor Access

```powershell
# Create temporary contractor account
rsr usermgmt create -u contractor -c "John Contractor" --generate

# Add to Remote Desktop Users
rsr usermgmt group add -u contractor -g "Remote Desktop Users"

# Add SSH key
rsr usermgmt ssh add -u contractor -f C:\temp\contractor_key.pub

# Later: Revoke access
rsr usermgmt lock -u contractor

# After project: Delete
rsr usermgmt delete -u contractor --remove-home
```

### Audit User Access

```powershell
# List all admin users
rsr usermgmt list --admin

# Check active sessions
rsr usermgmt session list

# Review login history
rsr usermgmt session history -n 100

# Check SSH keys for all users
Get-LocalUser | ForEach-Object {
    Write-Host "`n$($_.Name):"
    rsr usermgmt ssh list -u $_.Name
}
```

## PowerShell Module Usage

You can also use the PowerShell module directly in your scripts:

```powershell
# Import the module
. .\lib\users.ps1

# Use functions directly
if (Test-RSRUserExists "john") {
    Write-Host "User exists"
}

# Create user programmatically
$securePass = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
New-RSRUser -Username "testuser" -FullName "Test User" -Password $securePass

# Add to group
Add-RSRGroupMember -GroupName "Administrators" -Username "testuser"

# Generate and set SSH key
$keyFile = New-RSRSshKey -Username "testuser" -Type "ed25519"
Write-Host "Key generated: $keyFile"

# Clean up
Remove-RSRUser -Username "testuser" -RemoveHome
```

## Troubleshooting

### Execution Policy Error

**Problem:** "Cannot be loaded because running scripts is disabled"

**Solution:**
```powershell
# Set execution policy for current user
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Or run with bypass
powershell -ExecutionPolicy Bypass -File .\rsr.ps1 usermgmt list
```

### Permission Denied

**Problem:** "Access is denied"

**Solution:**
- Right-click PowerShell and select "Run as Administrator"
- Or use `Start-Process powershell -Verb RunAs`

### User Already Exists

**Problem:** "User 'john' already exists"

**Solution:**
```powershell
# Check if user exists
rsr usermgmt list | Select-String "john"

# Delete existing user
rsr usermgmt delete -u john --remove-home

# Recreate
rsr usermgmt create -u john
```

### SSH Keys Not Working

**Problem:** SSH authentication fails

**Solution:**
```powershell
# Fix permissions
rsr usermgmt ssh fix -u john

# Verify key location
# For regular users: C:\Users\john\.ssh\authorized_keys
# For administrators: C:\ProgramData\ssh\administrators_authorized_keys

# Check OpenSSH service
Get-Service sshd
Start-Service sshd  # If not running

# Verify key format
rsr usermgmt ssh list -u john
```

### Domain vs Local Users

**Problem:** Need to manage domain users

**Solution:**
```powershell
# Check if domain-joined
(Get-WmiObject Win32_ComputerSystem).PartOfDomain

# Install AD module (if not present)
Install-WindowsFeature RSAT-AD-PowerShell

# RSR automatically uses AD cmdlets if available
rsr usermgmt create -u domainuser  # Creates AD user if domain-joined
```

## Integration Examples

### PowerShell Script

```powershell
# Import RSR module
. .\lib\users.ps1

# Create multiple users from CSV
Import-Csv users.csv | ForEach-Object {
    Write-Host "Creating user: $($_.Username)"
    
    $params = @{
        Username = $_.Username
        FullName = $_.FullName
    }
    
    New-RSRUser @params
    
    # Add to groups
    if ($_.Groups) {
        $_.Groups -split ';' | ForEach-Object {
            Add-RSRGroupMember -GroupName $_ -Username $_.Username
        }
    }
}
```

### Scheduled Task

```powershell
# Create scheduled task to audit users weekly
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-File C:\rsr\rsr.ps1 usermgmt audit > C:\logs\user-audit.log"

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 9am

Register-ScheduledTask -TaskName "RSR User Audit" `
    -Action $action -Trigger $trigger -RunLevel Highest
```

### Configuration Management (DSC)

```powershell
Configuration RSRUserSetup {
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    
    Node localhost {
        Script CreateUsers {
            GetScript = { @{ Result = "" } }
            TestScript = { Test-RSRUserExists "appuser" }
            SetScript = {
                . C:\rsr\lib\users.ps1
                New-RSRUser -Username "appuser" -FullName "Application User"
            }
        }
    }
}
```

## Best Practices for Windows

1. **Always run as Administrator** for user management operations
2. **Use Ed25519 keys** for SSH (faster, more secure than RSA)
3. **Fix SSH permissions** after manual file edits: `rsr usermgmt ssh fix -u user`
4. **Use secure passwords** or generate random: `rsr usermgmt password generate`
5. **Regular audits**: Schedule `rsr usermgmt list --admin` to review access
6. **Group-based access**: Use groups instead of individual permissions
7. **Service accounts**: Create dedicated accounts for applications/services
8. **Document changes**: Log user creations/deletions for compliance

## See Also

- [User Management Guide](USER_MANAGEMENT.md) - Cross-platform guide
- [SSH Key Management](SSH_KEY_MANAGEMENT.md) - Detailed SSH guide
- [Quick Reference](USER_MANAGEMENT_QUICK_REFERENCE.md) - Command cheat sheet
- [Windows Architecture](WINDOWS_ARCHITECTURE.md) - Technical details

## Support

For Windows-specific issues:
- GitHub Issues: https://github.com/codefuturist/remote-script-runner/issues
- Tag issues with `windows` label
- Provide PowerShell version: `$PSVersionTable.PSVersion`
- Specify Windows version: `[System.Environment]::OSVersion.Version`

