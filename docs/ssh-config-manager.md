# SSH Configuration Manager

A comprehensive bash script for managing SSH configurations, keys, and security settings. This script provides a unified interface for common SSH management tasks while following security best practices.

## Features

- **SSH Directory Initialization**: Set up SSH directory with proper permissions
- **Key Generation**: Generate SSH key pairs (ED25519, RSA, etc.)
- **Host Management**: Add, remove, and list SSH host configurations
- **Security Hardening**: Apply security best practices to SSH configuration
- **Backup & Restore**: Backup and restore SSH configurations
- **Permission Management**: Check and fix SSH file permissions
- **Connection Testing**: Test SSH connections with detailed diagnostics
- **Known Hosts Cleanup**: Remove duplicate entries from known_hosts

## Remote Execution

Execute directly from GitHub:

```bash
# Initialize SSH configuration
curl -fsSL https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/ssh-config-manager.sh | bash -s -- init

# With verbose output
curl -fsSL https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/ssh-config-manager.sh | bash -s -- -v init

# Generate new SSH key
curl -fsSL https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/ssh-config-manager.sh | bash -s -- generate-key -t ed25519 -C "user@example.com"
```

## Local Installation

```bash
# Download the script
curl -o ssh-config-manager.sh https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/scripts/bash/ssh-config-manager.sh

# Make it executable
chmod +x ssh-config-manager.sh

# Run locally
./ssh-config-manager.sh --help
```

## Usage

```bash
ssh-config-manager.sh [OPTIONS] COMMAND [ARGS]
```

### Global Options

- `-h, --help` - Show help message
- `-v, --verbose` - Enable verbose output
- `-n, --dry-run` - Show what would be done without making changes
- `-f, --force` - Force operation without confirmation
- `-d, --ssh-dir DIR` - Specify SSH directory (default: ~/.ssh)
- `-b, --backup-dir DIR` - Specify backup directory (default: ~/.ssh/backups)

### Commands

#### init
Initialize SSH directory with secure permissions and basic configuration.

```bash
# Initialize SSH configuration
./ssh-config-manager.sh init

# Initialize with custom SSH directory
./ssh-config-manager.sh -d /path/to/ssh init
```

#### generate-key
Generate new SSH key pair with secure defaults.

```bash
# Generate ED25519 key (recommended)
./ssh-config-manager.sh generate-key -t ed25519 -C "user@example.com"

# Generate RSA key with 4096 bits
./ssh-config-manager.sh generate-key -t rsa -b 4096 -C "user@example.com"

# Generate key with custom filename
./ssh-config-manager.sh generate-key -t ed25519 -f id_work -C "work@company.com"

# Force overwrite existing key
./ssh-config-manager.sh -f generate-key -t ed25519
```

Options:
- `-t, --type` - Key type (ed25519, rsa, ecdsa, etc.) [default: ed25519]
- `-C, --comment` - Key comment [default: user@hostname]
- `-f, --file` - Key filename [default: id_<type>]
- `-b, --bits` - Key bits (for RSA) [default: 4096]

#### add-host
Add host configuration to SSH config file.

```bash
# Add basic host
./ssh-config-manager.sh add-host myserver -H example.com -u myuser

# Add host with custom port
./ssh-config-manager.sh add-host myserver -H example.com -u myuser -p 2222

# Add host with specific key
./ssh-config-manager.sh add-host myserver -H example.com -i ~/.ssh/id_work

# Add host with jump proxy
./ssh-config-manager.sh add-host internal -H 10.0.0.5 -J myserver

# Force overwrite existing host
./ssh-config-manager.sh -f add-host myserver -H example.com
```

Options:
- `-H, --hostname` - Hostname or IP address (required)
- `-u, --user` - Username for SSH connection
- `-p, --port` - SSH port [default: 22]
- `-i, --identity` - Path to identity file (private key)
- `-J, --jump` - Jump host (ProxyJump)

#### remove-host
Remove host configuration from SSH config.

```bash
# Remove host
./ssh-config-manager.sh remove-host myserver

# Force remove without confirmation
./ssh-config-manager.sh -f remove-host myserver
```

#### list-hosts
List all configured SSH hosts with their settings.

```bash
./ssh-config-manager.sh list-hosts
```

#### backup
Create backup of SSH configuration.

```bash
# Create manual backup
./ssh-config-manager.sh backup

# Create named backup
./ssh-config-manager.sh backup pre-migration
```

#### restore
Restore SSH configuration from backup.

```bash
# List available backups and choose interactively
./ssh-config-manager.sh restore

# Restore specific backup
./ssh-config-manager.sh restore backup_20240115_143022

# Force restore without confirmation
./ssh-config-manager.sh -f restore backup_20240115_143022
```

#### harden
Apply security hardening to SSH configuration.

```bash
# Apply security hardening
./ssh-config-manager.sh harden

# Dry-run to see what would change
./ssh-config-manager.sh -n harden
```

This command:
- Updates SSH config with secure cipher suites
- Disables weak algorithms
- Enables strict host key checking
- Disables dangerous features (agent forwarding, X11 forwarding)
- Creates server hardening recommendations file

#### check-permissions
Check and fix SSH file permissions.

```bash
# Check permissions
./ssh-config-manager.sh check-permissions

# Check with verbose output
./ssh-config-manager.sh -v check-permissions
```

Ensures:
- SSH directory: 700
- Private keys: 600
- Public keys: 644
- Config file: 600
- Authorized keys: 600
- Known hosts: 644

#### clean-known-hosts
Clean duplicate entries from known_hosts file.

```bash
# Clean known_hosts
./ssh-config-manager.sh clean-known-hosts

# Dry-run to see what would be removed
./ssh-config-manager.sh -n clean-known-hosts
```

#### test-connection
Test SSH connection to a host with diagnostics.

```bash
# Test connection to configured host
./ssh-config-manager.sh test-connection myserver

# Test with verbose output
./ssh-config-manager.sh -v test-connection myserver

# Test direct hostname
./ssh-config-manager.sh test-connection example.com
```

## Examples

### Complete Setup Workflow

```bash
# 1. Initialize SSH configuration
./ssh-config-manager.sh init

# 2. Generate SSH key
./ssh-config-manager.sh generate-key -t ed25519 -C "john@example.com"

# 3. Add server configurations
./ssh-config-manager.sh add-host webserver -H web.example.com -u deploy
./ssh-config-manager.sh add-host database -H db.example.com -u dbadmin -p 2222

# 4. Apply security hardening
./ssh-config-manager.sh harden

# 5. Create backup
./ssh-config-manager.sh backup initial-setup

# 6. Test connections
./ssh-config-manager.sh test-connection webserver
```

### Managing Multiple Environments

```bash
# Development environment
./ssh-config-manager.sh add-host dev-web -H dev.example.com -u developer -i ~/.ssh/id_dev

# Staging environment  
./ssh-config-manager.sh add-host stage-web -H stage.example.com -u deployer -i ~/.ssh/id_stage

# Production environment (with jump host)
./ssh-config-manager.sh add-host prod-jump -H jump.example.com -u admin
./ssh-config-manager.sh add-host prod-web -H 10.0.1.5 -u root -J prod-jump
```

### Key Rotation

```bash
# 1. Backup current configuration
./ssh-config-manager.sh backup pre-rotation

# 2. Generate new key
./ssh-config-manager.sh generate-key -t ed25519 -f id_ed25519_new

# 3. Update host to use new key
./ssh-config-manager.sh -f add-host myserver -H example.com -i ~/.ssh/id_ed25519_new

# 4. Test connection with new key
./ssh-config-manager.sh -v test-connection myserver

# 5. Remove old key (after confirming new key works)
rm ~/.ssh/id_ed25519.old ~/.ssh/id_ed25519.old.pub
```

## Security Features

### Hardened Default Configuration

The script applies these security settings:

**Algorithms:**
- Key Exchange: `curve25519-sha256`, `curve25519-sha256@libssh.org`
- Host Keys: `ssh-ed25519`, `rsa-sha2-512`, `rsa-sha2-256`
- Ciphers: `chacha20-poly1305@openssh.com`, `aes256-gcm@openssh.com`
- MACs: `hmac-sha2-512-etm@openssh.com`, `hmac-sha2-256-etm@openssh.com`

**Security Settings:**
- Password authentication disabled
- Strict host key checking enabled
- Known hosts hashing enabled
- Agent forwarding disabled
- X11 forwarding disabled

### Server Hardening Recommendations

When running `harden`, the script creates `~/.ssh/sshd_config_recommendations.txt` with server-side security recommendations.

## Best Practices

1. **Always backup before major changes**
   ```bash
   ./ssh-config-manager.sh backup pre-change
   ```

2. **Use ED25519 keys when possible**
   ```bash
   ./ssh-config-manager.sh generate-key -t ed25519
   ```

3. **Test changes with dry-run first**
   ```bash
   ./ssh-config-manager.sh -n add-host myserver -H example.com
   ```

4. **Regularly check permissions**
   ```bash
   ./ssh-config-manager.sh check-permissions
   ```

5. **Clean known_hosts periodically**
   ```bash
   ./ssh-config-manager.sh clean-known-hosts
   ```

## Troubleshooting

### Connection Issues

Use verbose mode to diagnose:
```bash
./ssh-config-manager.sh -v test-connection hostname
```

### Permission Denied Errors

Fix SSH file permissions:
```bash
./ssh-config-manager.sh check-permissions
```

### Backup Recovery

If something goes wrong:
```bash
# List available backups
./ssh-config-manager.sh restore

# Restore from specific backup
./ssh-config-manager.sh restore backup_name
```

## Platform Support

- **Linux**: Full support
- **macOS**: Full support
- **BSD**: Full support
- **Windows (WSL)**: Full support
- **Windows (Git Bash)**: Limited support

## Requirements

- Bash 4.0 or higher
- OpenSSH client
- Standard Unix utilities (awk, sed, grep, find)
- curl or wget (for remote execution)

## License

This script is part of the remote-script-runner collection and follows the same license terms.
