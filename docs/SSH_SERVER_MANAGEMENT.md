# SSH Server Management Guide

Complete guide for managing SSH servers with RSR across Linux, macOS, and Windows.

## Quick Start

### Check Server Status

```bash
# Linux/macOS
rsr ssh-server status

# Windows
.\rsr.ps1 ssh-server status
```

### Install and Enable SSH Server

```bash
# Linux/macOS
sudo rsr ssh-server install
sudo rsr ssh-server enable
sudo rsr ssh-server start

# Windows (PowerShell as Administrator)
.\rsr.ps1 ssh-server install
.\rsr.ps1 ssh-server enable
.\rsr.ps1 ssh-server start
```

### Interactive Configuration (Recommended) ✨

```bash
# Launch the interactive configuration wizard
sudo rsr ssh-server configure
```

The wizard guides you through configuring:

- SSH port
- Root login settings
- Password authentication
- **Public key authentication** ✨
- Idle timeout
- Max auth attempts
- Allowed users/groups
- X11 forwarding
- Quick hardening

### Apply Security Hardening

```bash
# Linux/macOS
sudo rsr ssh-server harden

# Windows
.\rsr.ps1 ssh-server harden
```

## Commands

### Installation & Setup

#### install

Install SSH server on the system.

```bash
# Linux/macOS
sudo rsr ssh-server install

# Windows
.\rsr.ps1 ssh-server install
```

**Platforms:**

- **Linux**: Installs `openssh-server` via package manager
- **macOS**: SSH is built-in, command ensures it's available
- **Windows**: Installs OpenSSH Server via Windows Capability

### Service Control

#### start

Start SSH server service.

```bash
sudo rsr ssh-server start
```

#### stop

Stop SSH server service (will disconnect all users).

```bash
sudo rsr ssh-server stop
```

**Safety:** Prompts for confirmation before stopping.

#### restart

Restart SSH server to apply configuration changes.

```bash
sudo rsr ssh-server restart
```

#### enable

Enable SSH server to start automatically at boot.

```bash
sudo rsr ssh-server enable
```

#### disable

Disable automatic start at boot.

```bash
sudo rsr ssh-server disable
```

#### status

Show comprehensive SSH server status.

```bash
rsr ssh-server status
```

**Output includes:**

- Installation status & version
- Running status
- Boot enabled status
- Listening port(s)
- Active connections count
- Security score (0-100)

### Configuration Management

#### config get

Get value of configuration setting.

```bash
rsr ssh-server config get Port
rsr ssh-server config get PermitRootLogin
rsr ssh-server config get PasswordAuthentication
```

#### config set

Set configuration value.

```bash
# Change SSH port
sudo rsr ssh-server config set Port 2222

# Disable root login
sudo rsr ssh-server config set PermitRootLogin no

# Disable password auth
sudo rsr ssh-server config set PasswordAuthentication no

# Set idle timeout (5 minutes)
sudo rsr ssh-server config set ClientAliveInterval 300
```

**Safety:**

- Automatically backs up configuration before changes
- Validates configuration syntax after changes
- Shows command to restart service

**Common Settings:**

| Setting | Values | Description |
|---------|--------|-------------|
| Port | 1-65535 | SSH listening port |
| PermitRootLogin | yes/no/prohibit-password | Allow root login |
| PasswordAuthentication | yes/no | Allow password auth |
| PubkeyAuthentication | yes/no | Allow public key auth |
| PermitEmptyPasswords | yes/no | Allow empty passwords |
| MaxAuthTries | number | Max auth attempts |
| ClientAliveInterval | seconds | Idle timeout |
| AllowUsers | usernames | Restrict to users |
| AllowGroups | groups | Restrict to groups |
| X11Forwarding | yes/no | Allow X11 forwarding |

#### config backup

Backup current SSH configuration.

```bash
sudo rsr ssh-server config backup
```

**Output:** Backup file path (keeps last 10 backups)

#### config restore

Restore SSH configuration from most recent backup.

```bash
sudo rsr ssh-server config restore
```

#### config validate

Validate SSH configuration syntax.

```bash
rsr ssh-server config validate
```

**Returns:** Exit code 0 if valid, 1 if errors found

#### config show

Show full SSH configuration (excluding comments/empty lines).

```bash
rsr ssh-server config show
```

### Security & Hardening

#### harden

Apply comprehensive security hardening.

```bash
sudo rsr ssh-server harden
```

**What it does:**

- Calls the dedicated `ssh-hardening.sh` script if available
- Otherwise applies basic hardening:
  - Disables root login
  - Disables password authentication
  - Enforces public key authentication only
  - Disables X11 forwarding
  - Limits authentication attempts to 3
  - Sets idle timeout to 5 minutes
  - Applies strong cryptographic settings

**See also:** `rsr ssh-harden` for advanced hardening options with fail2ban, port changes, etc.

#### audit

Run security audit showing current security configuration.

```bash
rsr ssh-server audit
```

**Output:**

- All security-relevant settings
- Failed login attempt count
- Security recommendations

#### score

Show security score (0-100) with grade.

```bash
rsr ssh-server score
```

**Scoring:**

- 90-100: Grade A (Excellent)
- 80-89: Grade B (Good)
- 70-79: Grade C (Fair)
- 60-69: Grade D (Poor)
- 0-59: Grade F (Failing)

**Deductions:**

- Root login enabled: -20
- Password auth enabled: -15
- Empty passwords allowed: -30
- Default port (22): -10
- X11 forwarding enabled: -5
- No idle timeout: -10
- High max auth tries: -5
- No user/group restrictions: -5

### Testing & Diagnostics

#### test

Test SSH connection to a host.

```bash
# Test localhost
rsr ssh-server test

# Test remote host
rsr ssh-server test myserver.com

# Test with custom port
rsr ssh-server test myserver.com 2222
```

**Tests:** Network connectivity to SSH port (does not test authentication)

#### connections

Show active SSH connections.

```bash
rsr ssh-server connections
```

**Output:** List of active TCP connections on SSH port

#### logs

Show SSH server logs.

```bash
# Show last 50 lines (default)
rsr ssh-server logs

# Show last 100 lines
rsr ssh-server logs 100
```

**Sources:**

- Linux: `/var/log/auth.log` or `/var/log/secure` or `journalctl`
- macOS: `/var/log/system.log`
- Windows: Event Log (Security)

#### failed

Show failed login attempts.

```bash
rsr ssh-server failed
```

**Output:**

- Total failed attempt count
- Last 10 failed login attempts with timestamp, username, IP

## Common Workflows

### Initial Server Setup

```bash
# 1. Install SSH server
sudo rsr ssh-server install

# 2. Check initial status
rsr ssh-server status

# 3. Enable at boot
sudo rsr ssh-server enable

# 4. Start service
sudo rsr ssh-server start

# 5. Apply security hardening
sudo rsr ssh-server harden

# 6. Verify security score
rsr ssh-server score
```

### Change SSH Port

```bash
# 1. Backup config
sudo rsr ssh-server config backup

# 2. Change port
sudo rsr ssh-server config set Port 2222

# 3. Update firewall (Linux)
sudo ufw allow 2222/tcp
sudo ufw delete allow 22/tcp

# 4. Restart SSH
sudo rsr ssh-server restart

# 5. Test new port
rsr ssh-server test localhost 2222
```

### Enable Key-Only Authentication

```bash
# 1. Ensure users have SSH keys set up
rsr usermgmt ssh list -u admin

# 2. If no keys, generate them
sudo rsr usermgmt ssh generate -u admin -t ed25519

# 3. Disable password auth
sudo rsr ssh-server config set PasswordAuthentication no

# 4. Restart SSH
sudo rsr ssh-server restart

# 5. Test (will fail without proper key)
ssh localhost
```

### Security Audit & Hardening

```bash
# 1. Check current security score
rsr ssh-server score

# 2. Run full audit
rsr ssh-server audit

# 3. Check failed logins
rsr ssh-server failed

# 4. Apply hardening
sudo rsr ssh-server harden

# 5. Verify improvement
rsr ssh-server score
```

### Troubleshooting Connection Issues

```bash
# 1. Check if server is running
rsr ssh-server status

# 2. Test local connection
rsr ssh-server test

# 3. Check active connections
rsr ssh-server connections

# 4. Review recent logs
rsr ssh-server logs 100

# 5. Validate configuration
rsr ssh-server config validate

# 6. Check failed login attempts
rsr ssh-server failed
```

### Restrict Access to Specific Users

```bash
# 1. Set allowed users
sudo rsr ssh-server config set AllowUsers "admin deploy"

# 2. Or set allowed groups
sudo rsr ssh-server config set AllowGroups "ssh-users admin"

# 3. Restart SSH
sudo rsr ssh-server restart

# 4. Verify configuration
rsr ssh-server config get AllowUsers
```

## Platform-Specific Notes

### Linux

**Package Managers:**

- Debian/Ubuntu: `apt-get install openssh-server`
- RHEL/Rocky/Alma: `yum/dnf install openssh-server`
- Arch: `pacman -S openssh`
- openSUSE: `zypper install openssh`

**Service Names:**

- Most: `sshd`
- Debian/Ubuntu: `ssh` or `sshd`

**Config Path:** `/etc/ssh/sshd_config`

**Log Paths:**

- Debian/Ubuntu: `/var/log/auth.log`
- RHEL/Rocky: `/var/log/secure`
- With systemd: `journalctl -u sshd`

### macOS

**Built-in:** SSH server is included in macOS

**Service Control:** Uses `launchd`

**Config Path:** `/etc/ssh/sshd_config`

**Log Path:** `/var/log/system.log`

**Enable via GUI:** System Preferences → Sharing → Remote Login

### Windows

**Installation:** Via Windows Capability (Windows 10+)

**Service Name:** `sshd`

**Config Path:** `C:\ProgramData\ssh\sshd_config`

**Log Access:** Event Viewer → Windows Logs → Security
