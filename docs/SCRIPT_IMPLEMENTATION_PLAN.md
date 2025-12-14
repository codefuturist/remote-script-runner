# Script Implementation Plan

This document contains the detailed implementation plan for 10 high-priority sysadmin scripts.

## Implementation Order

1. `cleanup` - Disk Cleanup
2. `ssl` - SSL Certificate Checker
3. `users` - User Audit
4. `update` - System Update
5. `audit` - Security Audit
6. `netdiag` - Network Diagnostics
7. `ssh-harden` - SSH Hardening
8. `firewall` - Firewall Setup
9. `backup` - Configuration Backup
10. `db-backup` - Database Backup

---

## 1. Disk Cleanup (`cleanup`)

### Metadata

```bash
# @id           cleanup
# @name         disk-cleanup
# @displayName  Disk Cleanup
# @description  Free disk space by removing temp files, old logs, package cache, and old kernels
# @category     maintenance
# @version      1.0.0
# @author       codefuturist
# @tags         disk,cleanup,temp,logs,cache,kernels,maintenance,storage
```

### CLI Options

| Short | Long | Argument | Description |
|-------|------|----------|-------------|
| `-h` | `--help` | | Display help message |
| `-v` | `--verbose` | | Enable verbose output |
| `-a` | `--all` | | Run all cleanup tasks |
| `-d` | `--dry-run` | | Show what would be deleted (default) |
| `-x` | `--execute` | | Actually perform deletions |
| `-s` | `--section` | `SECTION` | Run specific section (repeatable) |
| `-k` | `--keep-kernels` | `N` | Keep N most recent kernels (default: 2) |
| | `--older-than` | `DAYS` | Only remove files older than N days (default: 7) |
| | `--aggressive` | | Include user caches and deeper cleaning |

### Sections

- `tmp` - Temporary files (/tmp, /var/tmp)
- `cache` - Package manager cache
- `logs` - Old/rotated log files
- `kernels` - Old kernel versions
- `journal` - Systemd journal logs
- `thumbnails` - Thumbnail caches
- `coredumps` - Core dump files

### Features

- [x] Auto-detect package manager (apt, yum, dnf, pacman, zypper)
- [x] Dry-run mode by default (safe)
- [x] Show disk space before/after with savings
- [x] Color-coded output with progress
- [x] Never delete files newer than threshold
- [x] Protect running kernel from removal
- [x] Summary table at end

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Permission denied (need root for some operations) |
| 4 | Partial cleanup (some tasks failed) |

### Example Usage

```bash
rsr cleanup -d -a                    # Dry run all cleanup tasks
rsr cleanup -x -s cache -s logs      # Execute cache and log cleanup
rsr cleanup -x -a --older-than 14    # Clean files older than 14 days
sudo rsr cleanup -x -s kernels -k 2  # Remove old kernels, keep 2
```

---

## 2. SSL Certificate Checker (`ssl`)

### Metadata

```bash
# @id           ssl
# @name         ssl-checker
# @displayName  SSL Certificate Checker
# @description  Check SSL certificate expiry, chain validity, and cipher suites
# @category     security
# @version      1.0.0
# @author       codefuturist
# @tags         ssl,tls,certificate,security,expiry,https,cipher
```

### CLI Options

| Short | Long | Argument | Description |
|-------|------|----------|-------------|
| `-h` | `--help` | | Display help message |
| `-v` | `--verbose` | | Enable verbose output |
| `-d` | `--domain` | `DOMAIN` | Check domain(s) (repeatable) |
| `-f` | `--file` | `FILE` | Read domains from file |
| `-l` | `--local` | `FILE` | Check local certificate file |
| `-p` | `--port` | `PORT` | Port to connect (default: 443) |
| `-w` | `--warn` | `DAYS` | Warning threshold (default: 30) |
| `-c` | `--critical` | `DAYS` | Critical threshold (default: 7) |
| `-a` | `--all-checks` | | Run all checks (chain, ciphers, HSTS) |
| | `--chain` | | Validate certificate chain |
| | `--ciphers` | | Check for weak ciphers |
| | `--json` | | Output in JSON format |

### Features

- [x] Check certificate expiry with days remaining
- [x] Color-coded status (green >30d, yellow 7-30d, red <7d)
- [x] Validate certificate chain
- [x] Check for weak ciphers (RC4, DES, 3DES, MD5)
- [x] Verify hostname matches certificate
- [x] Show SAN (Subject Alternative Names)
- [x] Check TLS version support (warn on TLS 1.0/1.1)
- [x] Support local certificate file checking
- [x] Batch check from file
- [x] JSON output for monitoring

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All certificates valid (> warn days) |
| 1 | General error / connection failed |
| 2 | Invalid arguments |
| 3 | Certificate expiring soon (within warn days) |
| 4 | Certificate critical (within critical days) |
| 5 | Certificate expired |
| 6 | Chain validation failed |

### Example Usage

```bash
rsr ssl -d example.com                      # Check single domain
rsr ssl -d example.com -d api.example.com   # Check multiple domains
rsr ssl -f domains.txt -w 60                # Check from file, warn at 60 days
rsr ssl -d example.com -a                   # All checks including chain/ciphers
rsr ssl -l /etc/ssl/cert.pem                # Check local certificate
rsr ssl -d example.com --json               # JSON output for scripting
```

---

## 3. User Audit (`users`)

### Metadata

```bash
# @id           users
# @name         user-audit
# @displayName  User Audit
# @description  Audit user accounts, sudo access, login history, and orphaned files
# @category     security
# @version      1.0.0
# @author       codefuturist
# @tags         users,accounts,sudo,security,audit,login,permissions
```

### CLI Options

| Short | Long | Argument | Description |
|-------|------|----------|-------------|
| `-h` | `--help` | | Display help message |
| `-v` | `--verbose` | | Enable verbose output |
| `-a` | `--all` | | Run all audit checks |
| `-s` | `--section` | `SECTION` | Run specific section (repeatable) |
| `-u` | `--user` | `USER` | Audit specific user only |
| | `--sudo-only` | | Show only users with sudo access |
| | `--expired` | | Show only expired/expiring accounts |
| | `--no-login` | | Show accounts that should be nologin |
| | `--orphans` | | Find files with no owner |
| | `--ssh-keys` | | Audit SSH authorized keys |
| | `--failed-logins` | | Show failed login attempts |
| `-w` | `--warn-days` | `DAYS` | Warn if password expires within N days |
| | `--json` | | Output in JSON format |

### Sections

- `accounts` - List all user accounts with details
- `sudo` - Sudo/wheel group membership
- `passwords` - Password status and expiry
- `logins` - Login history and failed attempts
- `ssh` - SSH key audit
- `orphans` - Orphaned files scan

### Features

- [x] List all users with UID, GID, shell, home
- [x] Identify sudo/wheel group users
- [x] Find users with UID 0 (root equivalents)
- [x] Check password status (locked, expired, never set)
- [x] Show last login time per user
- [x] Count failed login attempts
- [x] Find users with empty passwords
- [x] List SSH authorized keys per user
- [x] Find orphaned files (no owner)
- [x] Color-coded security warnings

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Audit complete, no critical issues |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Permission denied (need root for full audit) |
| 4 | Critical security issues found |
| 5 | Warnings found (non-critical) |

### Example Usage

```bash
rsr users -a                    # Full user audit
rsr users -s sudo -s passwords  # Check sudo and password status
rsr users --sudo-only           # List only sudo users
rsr users --orphans             # Find orphaned files
rsr users -u admin -v           # Detailed audit of specific user
sudo rsr users -a --json        # Full audit with JSON output
```

---

## 4. System Update (`update`)

### Metadata

```bash
# @id           update
# @name         system-update
# @displayName  System Update
# @description  Update system packages, security patches, and kernel
# @category     maintenance
# @version      1.0.0
# @author       codefuturist
# @tags         update,packages,security,patches,kernel,upgrade,maintenance
```

### CLI Options

| Short | Long | Argument | Description |
|-------|------|----------|-------------|
| `-h` | `--help` | | Display help message |
| `-v` | `--verbose` | | Enable verbose output |
| `-c` | `--check` | | Check for available updates only |
| `-l` | `--list` | | List available updates with details |
| `-a` | `--all` | | Install all available updates |
| | `--security` | | Install security updates only |
| `-e` | `--exclude` | `PKG` | Exclude package(s) from update |
| | `--changelog` | | Show changelog for updates |
| `-y` | `--yes` | | Automatic yes to prompts |
| | `--reboot-required` | | Check if reboot is needed |
| | `--reboot-if-needed` | | Auto reboot if needed (requires --yes) |
| `-d` | `--dry-run` | | Show what would be updated |
| | `--json` | | Output in JSON format |

### Features

- [x] Auto-detect package manager (apt, yum, dnf, pacman, zypper, apk)
- [x] List available updates with current/new version
- [x] Show security updates separately
- [x] Check if reboot is required
- [x] Exclude specific packages
- [x] Show changelog for updates
- [x] Interactive confirmation (default)
- [x] Non-interactive mode with --yes
- [x] Show download size and disk space needed

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Updates completed successfully |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Permission denied (need root) |
| 4 | Package manager locked |
| 5 | Insufficient disk space |
| 6 | Update failed |
| 7 | Reboot required (after successful update) |
| 100 | No updates available |

### Example Usage

```bash
rsr update -c                       # Check for updates
rsr update -l                       # List available updates
rsr update -a -d                    # Dry run full update
sudo rsr update -a -y               # Install all updates non-interactive
sudo rsr update --security -y       # Security updates only
rsr update --reboot-required        # Check if reboot needed
sudo rsr update -a -e nginx         # Update all except nginx
```

---

## 5. Security Audit (`audit`)

### Metadata

```bash
# @id           audit
# @name         security-audit
# @displayName  Security Audit
# @description  Audit system security: open ports, logins, SUID files, permissions
# @category     security
# @version      1.0.0
# @author       codefuturist
# @tags         security,audit,ports,suid,permissions,logins,hardening
```

### CLI Options

| Short | Long | Argument | Description |
|-------|------|----------|-------------|
| `-h` | `--help` | | Display help message |
| `-v` | `--verbose` | | Enable verbose output |
| `-a` | `--all` | | Run all security checks |
| `-s` | `--section` | `SECTION` | Run specific section (repeatable) |
| | `--severity` | `LEVEL` | Show only issues at level (critical, high, medium, low) |
| | `--quick` | | Quick scan (skip slow checks) |
| | `--deep` | | Deep scan (more thorough) |
| `-r` | `--report` | `FILE` | Generate report to file |
| | `--format` | `FMT` | Report format (text, json, html) |
| | `--cis` | | Include CIS benchmark references |

### Sections

- `ports` - Open ports and listening services
- `auth` - Authentication failures and brute force
- `files` - File permissions, world-writable, SUID/SGID
- `users` - User account security
- `network` - Firewall, IP forwarding, connections
- `ssh` - SSH configuration security
- `updates` - Pending security updates
- `processes` - Running processes analysis
- `kernel` - Kernel security settings

### Features

- [x] Scan open ports and identify processes
- [x] Check failed login attempts
- [x] Find world-writable files/directories
- [x] List SUID/SGID binaries
- [x] Check for UID 0 accounts
- [x] Verify SSH configuration security
- [x] Check firewall status
- [x] Analyze running processes
- [x] Severity scoring (Critical/High/Medium/Low)
- [x] Summary with total issues by severity

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | No security issues found |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Permission denied (need root) |
| 4 | Critical issues found |
| 5 | High severity issues found |
| 6 | Medium severity issues found |
| 7 | Low severity issues found |

### Example Usage

```bash
rsr audit -a                        # Full security audit
rsr audit -s ports -s auth          # Check ports and authentication
rsr audit --quick                   # Quick scan
sudo rsr audit -a --deep            # Deep thorough scan
rsr audit -a --format json          # JSON output
rsr audit -a -r /tmp/audit.html --format html  # HTML report
```

---

## 6. Network Diagnostics (`netdiag`)

### Metadata

```bash
# @id           netdiag
# @name         network-diagnostics
# @displayName  Network Diagnostics
# @description  Diagnose network: connectivity, DNS, latency, port checks
# @category     network
# @version      1.0.0
# @author       codefuturist
# @tags         network,diagnostics,ping,dns,trace,ports,connectivity
```

### CLI Options

| Short | Long | Argument | Description |
|-------|------|----------|-------------|
| `-h` | `--help` | | Display help message |
| `-v` | `--verbose` | | Enable verbose output |
| `-a` | `--all` | | Run all diagnostics |
| `-s` | `--section` | `SECTION` | Run specific section (repeatable) |
| | `--ping` | `HOSTS` | Ping specific hosts (comma-separated) |
| | `--dns` | | Test DNS resolution |
| | `--trace` | `HOST` | Traceroute to host |
| | `--port` | `HOST:PORT` | Test port connectivity |
| | `--ports` | `PORTS` | Test multiple ports (comma-separated) |
| | `--bandwidth` | | Run bandwidth test |
| | `--interfaces` | | Show network interfaces |
| | `--public-ip` | | Show public IP address |
| | `--mtu` | `HOST` | Discover MTU to host |
| | `--listen` | | Show listening services |
| `-c` | `--count` | `N` | Ping count (default: 4) |
| `-t` | `--timeout` | `SEC` | Timeout in seconds (default: 5) |
| | `--json` | | Output in JSON format |

### Sections

- `connectivity` - Basic internet connectivity
- `dns` - DNS resolution tests
- `gateway` - Default gateway check
- `interfaces` - Network interface info
- `ports` - Port connectivity tests
- `services` - Listening services
- `routing` - Routing table

### Features

- [x] Ping multiple hosts with latency stats
- [x] DNS resolution test (multiple resolvers)
- [x] Check default gateway
- [x] Traceroute to destination
- [x] TCP port connectivity test
- [x] Show network interfaces and IPs
- [x] Detect public IP
- [x] MTU discovery
- [x] Show listening services
- [x] Color-coded status output

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All tests passed |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Connectivity issues detected |
| 4 | DNS issues detected |
| 5 | Port connectivity failed |

### Example Usage

```bash
rsr netdiag -a                              # Full diagnostics
rsr netdiag --ping google.com,cloudflare.com  # Ping specific hosts
rsr netdiag --dns                           # Test DNS resolution
rsr netdiag --port example.com:443          # Test port connectivity
rsr netdiag --trace google.com              # Traceroute
rsr netdiag --interfaces --public-ip        # Show interface and public IP
rsr netdiag -a --json                       # JSON output
```

---

## 7. SSH Hardening (`ssh-harden`)

### Metadata

```bash
# @id           ssh-harden
# @name         ssh-hardening
# @displayName  SSH Hardening
# @description  Harden SSH: disable root login, enforce keys, configure fail2ban
# @category     security
# @version      1.0.0
# @author       codefuturist
# @tags         ssh,security,hardening,fail2ban,keys,authentication
```

### CLI Options

| Short | Long | Argument | Description |
|-------|------|----------|-------------|
| `-h` | `--help` | | Display help message |
| `-v` | `--verbose` | | Enable verbose output |
| `-a` | `--all` | | Apply all hardening measures |
| `-d` | `--dry-run` | | Show changes without applying |
| | `--status` | | Show current SSH configuration status |
| | `--no-root` | | Disable root login |
| | `--key-only` | | Disable password authentication |
| `-p` | `--port` | `PORT` | Change SSH port |
| | `--timeout` | `SEC` | Set idle timeout (default: 300) |
| | `--max-auth` | `N` | Max authentication attempts (default: 3) |
| | `--allow-users` | `USERS` | Restrict to users (comma-separated) |
| | `--allow-groups` | `GROUPS` | Restrict to groups (comma-separated) |
| | `--fail2ban` | | Install and configure fail2ban |
| | `--strong-crypto` | | Apply strong cipher/MAC/Kex settings |
| | `--generate-key` | `USER` | Generate SSH key for user |
| | `--backup` | | Backup config before changes (default) |
| | `--no-backup` | | Skip config backup |
| | `--rollback` | | Rollback to previous configuration |

### Features

- [x] Show current SSH configuration status
- [x] Disable root login (PermitRootLogin no)
- [x] Disable password authentication
- [x] Change SSH port
- [x] Set idle timeout (ClientAliveInterval)
- [x] Limit authentication attempts
- [x] Restrict to specific users/groups
- [x] Configure strong ciphers, MACs, KexAlgorithms
- [x] Install and configure fail2ban
- [x] Backup config before changes
- [x] Validate config before applying (sshd -t)
- [x] Warn if changes would lock out current user

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Hardening applied successfully |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Permission denied (need root) |
| 4 | SSH config syntax error |
| 5 | Failed to restart SSH |
| 6 | Would lock out user (aborted) |
| 7 | Rollback required |

### Example Usage

```bash
rsr ssh-harden --status                 # Show current config status
rsr ssh-harden -a -d                    # Dry run all hardening
sudo rsr ssh-harden --no-root --key-only  # Disable root and passwords
sudo rsr ssh-harden -p 2222             # Change SSH port
sudo rsr ssh-harden --fail2ban          # Install fail2ban
sudo rsr ssh-harden --allow-users admin,deploy  # Restrict users
sudo rsr ssh-harden --rollback          # Rollback changes
```

---

## 8. Firewall Setup (`firewall`)

### Metadata

```bash
# @id           firewall
# @name         firewall-setup
# @displayName  Firewall Setup
# @description  Configure firewall with ufw/iptables/firewalld presets
# @category     security
# @version      1.0.0
# @author       codefuturist
# @tags         firewall,ufw,iptables,firewalld,security,network,ports
```

### CLI Options

| Short | Long | Argument | Description |
|-------|------|----------|-------------|
| `-h` | `--help` | | Display help message |
| `-v` | `--verbose` | | Enable verbose output |
| `-d` | `--dry-run` | | Show what would be configured |
| `-p` | `--preset` | `PRESET` | Apply preset profile |
| `-a` | `--allow` | `PORT[/PROTO]` | Allow port (e.g., 3000/tcp) |
| `-D` | `--deny` | `PORT[/PROTO]` | Deny port |
| | `--allow-from` | `IP` | Allow from IP/CIDR |
| | `--deny-from` | `IP` | Deny from IP/CIDR |
| | `--rate-limit` | `PORT` | Enable rate limiting on port |
| | `--enable` | | Enable firewall |
| | `--disable` | | Disable firewall |
| | `--status` | | Show current status and rules |
| | `--reset` | | Reset to defaults |
| | `--backup` | `FILE` | Backup current rules |
| | `--restore` | `FILE` | Restore rules from backup |
| | `--ipv6` | | Include IPv6 rules (default) |
| | `--no-ipv6` | | Disable IPv6 |

### Presets

- `minimal` - SSH only (port 22)
- `web` - SSH, HTTP, HTTPS (22, 80, 443)
- `database` - SSH + MySQL/PostgreSQL (localhost only)
- `docker` - SSH, HTTP, HTTPS + Docker ports
- `mail` - SSH + SMTP, IMAP, POP3 with SSL

### Features

- [x] Auto-detect firewall (ufw, firewalld, iptables, nftables)
- [x] Apply preset profiles
- [x] Allow/deny specific ports
- [x] Source IP restrictions
- [x] Rate limiting for SSH
- [x] Enable/disable firewall
- [x] Show current status and rules
- [x] Backup and restore rules
- [x] Protect SSH (never lock out)
- [x] IPv6 support

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Firewall configured successfully |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Permission denied (need root) |
| 4 | No supported firewall found |
| 5 | Rule syntax error |
| 6 | Would lock out SSH (aborted) |

### Example Usage

```bash
rsr firewall --status                   # Show current status
rsr firewall -p web -d                  # Dry run web preset
sudo rsr firewall -p minimal            # Apply minimal preset
sudo rsr firewall -a 8080/tcp           # Allow port 8080
sudo rsr firewall -a 3306/tcp --allow-from 10.0.0.0/8  # Allow MySQL from internal
sudo rsr firewall --rate-limit 22       # Rate limit SSH
sudo rsr firewall --backup /tmp/fw.bak  # Backup rules
```

---

## 9. Configuration Backup (`backup`)

### Metadata

```bash
# @id           backup
# @name         config-backup
# @displayName  Configuration Backup
# @description  Backup system configs: /etc, crontabs, packages, databases
# @category     maintenance
# @version      1.0.0
# @author       codefuturist
# @tags         backup,config,etc,crontab,packages,restore,maintenance
```

### CLI Options

| Short | Long | Argument | Description |
|-------|------|----------|-------------|
| `-h` | `--help` | | Display help message |
| `-v` | `--verbose` | | Enable verbose output |
| `-a` | `--all` | | Backup everything |
| `-s` | `--section` | `SECTION` | Backup specific section (repeatable) |
| `-o` | `--output` | `DIR` | Output directory (default: /var/backups/rsr) |
| | `--compress` | `METHOD` | Compression: gzip, xz, none (default: gzip) |
| | `--encrypt` | | Encrypt with GPG |
| | `--gpg-key` | `KEY` | GPG key ID for encryption |
| | `--upload` | `DEST` | Upload to remote (s3://, rsync://, scp://) |
| | `--retention` | `N` | Keep N most recent backups (default: 7) |
| | `--exclude` | `PATTERN` | Exclude files matching pattern |
| | `--verify` | | Verify backup after creation |
| | `--list` | | List existing backups |
| | `--restore` | `FILE` | Restore from backup file |
| `-d` | `--dry-run` | | Show what would be backed up |

### Sections

- `etc` - /etc directory (system configuration)
- `packages` - Installed package list with versions
- `crontabs` - All user and system crontabs
- `systemd` - Custom systemd units
- `ssh` - SSH keys and authorized_keys
- `nginx` - Nginx configuration
- `apache` - Apache configuration
- `database` - Database configs (not data)

### Features

- [x] Backup /etc with configurable excludes
- [x] Export installed package list
- [x] Backup all crontabs
- [x] Backup systemd custom units
- [x] SSH keys and authorized_keys
- [x] Compress with gzip/xz
- [x] GPG encryption
- [x] Upload to S3/rsync/scp
- [x] Retention policy
- [x] SHA256 checksums
- [x] Manifest with backup contents
- [x] Verify backup integrity

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Backup completed successfully |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Permission denied (need root) |
| 4 | Insufficient disk space |
| 5 | Compression failed |
| 6 | Encryption failed |
| 7 | Upload failed |
| 8 | Restore failed |

### Example Usage

```bash
rsr backup -a -d                        # Dry run full backup
sudo rsr backup -a                      # Full backup
sudo rsr backup -s etc -s packages      # Backup etc and packages
sudo rsr backup -a --encrypt --gpg-key admin@example.com
sudo rsr backup -a --upload s3://mybucket/backups/
rsr backup --list                       # List existing backups
sudo rsr backup --restore /var/backups/rsr/backup-20240120.tar.gz
```

---

## 10. Database Backup (`db-backup`)

### Metadata

```bash
# @id           db-backup
# @name         database-backup
# @displayName  Database Backup
# @description  Backup MySQL/PostgreSQL databases with compression and encryption
# @category     maintenance
# @version      1.0.0
# @author       codefuturist
# @tags         database,backup,mysql,mariadb,postgresql,dump,maintenance
```

### CLI Options

| Short | Long | Argument | Description |
|-------|------|----------|-------------|
| `-h` | `--help` | | Display help message |
| `-v` | `--verbose` | | Enable verbose output |
| | `--mysql` | | Backup MySQL/MariaDB |
| | `--postgresql` | | Backup PostgreSQL |
| | `--mongodb` | | Backup MongoDB |
| | `--auto` | | Auto-detect databases |
| `-d` | `--database` | `DB` | Backup specific database |
| `-A` | `--all-databases` | | Backup all databases |
| | `--schema-only` | | Dump schema only |
| | `--data-only` | | Dump data only |
| `-o` | `--output` | `DIR` | Output directory |
| | `--compress` | `METHOD` | Compression: gzip, xz, lz4 (default: gzip) |
| | `--encrypt` | | Encrypt with GPG |
| | `--gpg-key` | `KEY` | GPG key ID |
| | `--parallel` | `N` | Parallel threads (where supported) |
| | `--upload` | `DEST` | Upload to remote storage |
| | `--retention` | `N` | Keep N most recent backups |
| | `--verify` | | Verify backup after creation |
| | `--pitr` | | Include point-in-time recovery info |
| | `--list` | | List existing backups |
| | `--restore` | `FILE` | Restore from backup |
| | `--dry-run` | | Show what would be done |

### Features

- [x] Auto-detect database type
- [x] MySQL/MariaDB dump (mysqldump)
- [x] PostgreSQL dump (pg_dump)
- [x] MongoDB dump (mongodump)
- [x] Single or all databases
- [x] Schema-only / data-only options
- [x] Compress with gzip/xz/lz4
- [x] GPG encryption
- [x] Parallel dump (PostgreSQL)
- [x] Upload to S3/GCS/rsync
- [x] Retention management
- [x] Point-in-time recovery info
- [x] Verify backup integrity

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Backup completed successfully |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Permission denied |
| 4 | Database not found |
| 5 | Dump failed |
| 6 | Compression failed |
| 7 | Encryption failed |
| 8 | Upload failed |
| 9 | Restore failed |

### Example Usage

```bash
rsr db-backup --mysql -A                # Backup all MySQL databases
rsr db-backup --postgresql -d myapp     # Backup specific PostgreSQL DB
rsr db-backup --auto -A                 # Auto-detect and backup all
rsr db-backup --mysql -A --compress xz --encrypt
rsr db-backup --mysql -A --upload s3://bucket/db-backups/
rsr db-backup --list                    # List existing backups
rsr db-backup --restore /backups/db-20240120.sql.gz --mysql
```

---

## Registry.json Entries

When implementing, add each script to `scripts/registry.json`:

```json
{
  "id": "cleanup",
  "name": "disk-cleanup",
  "displayName": "Disk Cleanup",
  "description": "Free disk space by removing temp files, old logs, package cache, and old kernels",
  "category": "maintenance",
  "version": "1.0.0",
  "author": "codefuturist",
  "shells": {
    "bash": "scripts/bash/disk-cleanup.sh"
  },
  "defaultShell": "bash",
  "options": [
    { "short": "-a", "long": "--all", "description": "Run all cleanup tasks" },
    { "short": "-d", "long": "--dry-run", "description": "Show what would be deleted" },
    { "short": "-x", "long": "--execute", "description": "Actually perform deletions" },
    { "short": "-s", "long": "--section", "argument": "SECTION", "description": "Run specific section" },
    { "short": "-v", "long": "--verbose", "description": "Verbose output" }
  ],
  "examples": [
    { "command": "rsr cleanup -d -a", "description": "Dry run all cleanup tasks" },
    { "command": "rsr cleanup -x -s cache", "description": "Clean package cache" }
  ],
  "tags": ["disk", "cleanup", "temp", "logs", "cache", "maintenance"]
}
```

---

## Implementation Checklist

- [ ] 1. `cleanup` (disk-cleanup.sh)
- [ ] 2. `ssl` (ssl-checker.sh)
- [ ] 3. `users` (user-audit.sh)
- [ ] 4. `update` (system-update.sh)
- [ ] 5. `audit` (security-audit.sh)
- [ ] 6. `netdiag` (network-diagnostics.sh)
- [ ] 7. `ssh-harden` (ssh-hardening.sh)
- [ ] 8. `firewall` (firewall-setup.sh)
- [ ] 9. `backup` (config-backup.sh)
- [ ] 10. `db-backup` (database-backup.sh)

After each script:

- [ ] Add to `scripts/registry.json`
- [ ] Run `./tools/validate.sh`
- [ ] Run `./tools/build-registry.sh`
- [ ] Test locally with `./rsr <command> --help`
- [ ] Test dry-run mode

---

## Common Patterns

All scripts should follow these patterns from existing scripts:

### Script Header

```bash
#!/usr/bin/env bash
# @id           <id>
# @name         <name>
# @displayName  <Display Name>
# @description  <description>
# @category     <category>
# @version      1.0.0
# @author       codefuturist
# @tags         <comma,separated,tags>

set -euo pipefail
```

### Color Setup

```bash
setup_colors() {
    if [[ -t 1 ]]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        CYAN='\033[0;36m'
        BOLD='\033[1m'
        DIM='\033[2m'
        NC='\033[0m'
    else
        RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' NC=''
    fi
}
```

### Logging Functions

```bash
log_info()  { printf "${BLUE}▸${NC} %s\n" "$1"; }
log_ok()    { printf "${GREEN}✓${NC} %s\n" "$1"; }
log_warn()  { printf "${YELLOW}⚠${NC} %s\n" "$1"; }
log_error() { printf "${RED}✗${NC} %s\n" "$1" >&2; }
log_debug() { [[ "${VERBOSE:-0}" == "1" ]] && printf "${DIM}  %s${NC}\n" "$1"; }
```

### Help Function

```bash
show_help() {
    cat << EOF
${BOLD}<Display Name>${NC} v${VERSION}

${YELLOW}Usage:${NC}
  rsr <id> [options]

${BOLD}Options:${NC}
  -h, --help      Show this help message
  ...

${BOLD}Examples:${NC}
  rsr <id> -a
  ...

EOF
}
```

### Main Function Pattern

```bash
main() {
    setup_colors
    parse_args "$@"

    # Show help if requested
    [[ "${SHOW_HELP:-0}" == "1" ]] && show_help && exit 0

    # Main logic here
    ...
}

main "$@"
```
