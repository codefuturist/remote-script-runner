# User Management Guide

The Remote Script Runner (RSR) provides comprehensive cross-platform user management capabilities through the `user-management` script and `lib/users.sh` library.

## Overview

The user management system provides a unified interface for:

- **Account Lifecycle**: Create, delete, modify, lock/unlock user accounts
- **Password Management**: Reset passwords, enforce policies, manage expiration
- **Group Management**: Create groups, manage membership
- **Permission Management**: Set file/folder permissions, apply templates
- **Session Monitoring**: Track active sessions, login history, failed attempts
- **Auditing**: Comprehensive user security audits

## Cross-Platform Support

| Feature | Linux | macOS | Implementation |
|---------|-------|-------|----------------|
| User Creation | ✅ | ✅ | `useradd` / `sysadminctl`+`dscl` |
| User Deletion | ✅ | ✅ | `userdel` / `sysadminctl`+`dscl` |
| Password Management | ✅ | ✅ | `chpasswd` / `sysadminctl`+`dscl` |
| Group Management | ✅ | ✅ | `usermod`/`groupadd` / `dscl` |
| Permission Management | ✅ | ✅ | `chmod`/`chown` (universal) |
| Session Monitoring | ✅ | ✅ | `who`/`last` (universal) |
| Password Policies | ✅ | ⚠️ | `chage`/PAM / `pwpolicy` (limited) |

## Quick Start

### Installation

The user management functionality is included in RSR. No additional installation required.

```bash
# Clone the repository
git clone https://github.com/codefuturist/remote-script-runner.git
cd remote-script-runner

# Run directly
sudo ./scripts/bash/user-management.sh --help
```

### Basic Usage

```bash
# Create a user
sudo rsr usermgmt create -u john -c "John Doe" -s /bin/bash

# Add user to groups
sudo rsr usermgmt create -u jane -g sudo,docker --generate

# List all users
rsr usermgmt list

# List only sudo users
rsr usermgmt list --sudo

# Reset password
sudo rsr usermgmt password reset -u john

# Generate random password
rsr usermgmt password generate --length 20

# Add user to group
sudo rsr usermgmt group add -u john -g docker

# Set permissions
sudo rsr usermgmt permission set -p /var/www -m 755 -o www-data:www-data -R

# View active sessions
rsr usermgmt session list

# View login history
rsr usermgmt session history -u john

# Run audit
sudo rsr usermgmt audit
```

## Subcommands

### Account Management

#### create

Create a new user account with optional configuration.

```bash
# Basic user creation
sudo rsr usermgmt create -u username -c "Full Name"

# With specific shell and groups
sudo rsr usermgmt create -u username -s /bin/zsh -g sudo,docker

# With generated password
sudo rsr usermgmt create -u username --generate --force-change

# Custom UID and home directory
sudo rsr usermgmt create -u username --uid 1500 --home /custom/home

# No home directory
sudo rsr usermgmt create -u username --no-create-home
```

**Options:**

- `-u, --username USER` - Username (required)
- `-c, --comment TEXT` - Full name or GECOS field
- `-s, --shell SHELL` - Login shell (default: /bin/bash)
- `-g, --groups GROUPS` - Additional groups (comma-separated)
- `--uid UID` - Specific user ID
- `--gid GID` - Primary group ID
- `--home PATH` - Custom home directory
- `--no-create-home` - Don't create home directory
- `-p, --password PASS` - Set password directly
- `--generate` - Generate random password
- `--force-change` - Force password change on first login

#### delete

Delete a user account, optionally removing home directory.

```bash
# Delete user (keep home)
sudo rsr usermgmt delete -u username

# Delete user and remove home
sudo rsr usermgmt delete -u username --remove-home
```

**Options:**

- `-u, --username USER` - Username (required)
- `--remove-home` - Remove home directory and mail spool

#### lock / unlock

Disable or enable user login.

```bash
# Lock user account
sudo rsr usermgmt lock -u username

# Unlock user account
sudo rsr usermgmt unlock -u username
```

#### list

List user accounts with details.

```bash
# List human users (UID >= 1000)
rsr usermgmt list

# List all users including system
rsr usermgmt list --all

# List only users with sudo access
rsr usermgmt list --sudo
```

### Password Management

#### password reset

Reset a user's password interactively or with specified value.

```bash
# Interactive password reset
sudo rsr usermgmt password reset -u username

# Set specific password
sudo rsr usermgmt password reset -u username -p newpassword
```

#### password expire

Force password change on next login.

```bash
sudo rsr usermgmt password expire -u username
```

#### password generate

Generate secure random passwords.

```bash
# Generate 16-character password
rsr usermgmt password generate

# Generate 24-character password
rsr usermgmt password generate --length 24

# Generate and set for user
sudo rsr usermgmt password generate -u username --set
```

#### password policy

View password policy settings.

```bash
# System-wide policy
rsr usermgmt password policy

# User-specific policy (Linux only)
rsr usermgmt password policy -u username
```

### Group Management

#### group create

Create a new group.

```bash
# Create group with auto GID
sudo rsr usermgmt group create -g groupname

# Create with specific GID
sudo rsr usermgmt group create -g groupname --gid 2000
```

#### group add

Add user to a group.

```bash
sudo rsr usermgmt group add -u username -g groupname
```

#### group remove

Remove user from a group.

```bash
sudo rsr usermgmt group remove -u username -g groupname
```

#### group list

List members of a group.

```bash
rsr usermgmt group list -g groupname
```

#### group show

Show all groups a user belongs to.

```bash
rsr usermgmt group show -u username
```

### Permission Management

#### permission set

Set file or directory permissions and ownership.

```bash
# Set permissions
sudo rsr usermgmt permission set -p /path/to/file -m 644

# Set permissions and owner
sudo rsr usermgmt permission set -p /path/to/dir -m 755 -o user:group

# Recursive
sudo rsr usermgmt permission set -p /path/to/dir -m 755 -R
```

**Options:**

- `-p, --path PATH` - File or directory path (required)
- `-m, --mode MODE` - Permission mode (e.g., 755, 644)
- `-o, --owner OWNER` - Owner in format user:group
- `-R, --recursive` - Apply recursively

#### permission get

Display current permissions of a file or directory.

```bash
rsr usermgmt permission get -p /path/to/file
```

#### permission template

Apply predefined permission templates.

```bash
# Web server template (755, www-data:www-data)
sudo rsr usermgmt permission template -p /var/www -t web

# Shared directory template (775)
sudo rsr usermgmt permission template -p /shared -t shared

# Private directory template (700)
sudo rsr usermgmt permission template -p /private -t private

# Service file template (644)
sudo rsr usermgmt permission template -p /etc/service.conf -t service
```

**Available Templates:**

- `web` - Web server files (755, www-data:www-data)
- `shared` - Shared directories (775)
- `private` - Private directories (700)
- `service` - Service/config files (644)

### SSH Key Management

#### ssh generate

Generate SSH key pair for a user.

```bash
# Generate default RSA 4096-bit key
sudo rsr usermgmt ssh generate -u username

# Generate Ed25519 key (modern, recommended)
sudo rsr usermgmt ssh generate -u username -t ed25519

# Generate RSA key with custom bits
sudo rsr usermgmt ssh generate -u username -t rsa -b 2048

# With custom comment
sudo rsr usermgmt ssh generate -u username -t ed25519 -c "user@company.com"
```

**Key Types:**

- `rsa` - RSA keys (default 4096 bits)
- `ed25519` - Ed25519 keys (modern, faster, more secure)
- `ecdsa` - ECDSA keys
- `dsa` - DSA keys (legacy, not recommended)

#### ssh add

Add SSH public key to user's authorized_keys.

```bash
# Add key from file
sudo rsr usermgmt ssh add -u username -f /path/to/key.pub

# Add key from string
sudo rsr usermgmt ssh add -u username -k "ssh-rsa AAAAB3NzaC1yc2E... user@host"

# Add key from stdin
cat ~/.ssh/id_rsa.pub | sudo rsr usermgmt ssh add -u username -k "$(cat)"
```

**Features:**

- Validates key format before adding
- Checks for duplicate keys
- Sets proper permissions (600 for authorized_keys)
- Creates .ssh directory if needed

#### ssh remove

Remove SSH key from authorized_keys.

```bash
# Remove by key fingerprint
sudo rsr usermgmt ssh remove -u username -i "SHA256:abcd1234..."

# Remove by comment
sudo rsr usermgmt ssh remove -u username -i "user@hostname"

# Remove by part of key
sudo rsr usermgmt ssh remove -u username -i "AAAAB3NzaC1yc2E"
```

**Safety:**

- Creates backup (.authorized_keys.backup) before removal
- Validates match before deletion

#### ssh list

List authorized SSH keys for a user.

```bash
# List all keys (full content)
rsr usermgmt ssh list -u username

# List with fingerprints
rsr usermgmt ssh list -u username --fingerprints

# List and count
rsr usermgmt ssh list -u username | wc -l
```

#### ssh copy

Copy SSH keys from one user to another.

```bash
# Copy all keys from alice to bob
sudo rsr usermgmt ssh copy -s alice -d bob

# Useful for migrating users or setting up service accounts
sudo rsr usermgmt ssh copy -s admin -d deploy
```

#### ssh validate

Validate authorized_keys file format.

```bash
# Check if all keys are valid
rsr usermgmt ssh validate -u username

# Returns exit code 0 if all valid, 1 if any invalid
```

#### ssh fix

Fix SSH directory and file permissions.

```bash
# Fix all SSH permissions for user
sudo rsr usermgmt ssh fix -u username
```

**What it fixes:**

- `.ssh/` directory → 700
- `authorized_keys` → 600
- Private keys (`id_*`) → 600
- Public keys (`*.pub`) → 644
- `config` → 600
- `known_hosts` → 644
- Sets correct ownership

### Session Monitoring

#### session list

List currently active user sessions.

```bash
rsr usermgmt session list
```

#### session history

View login history for all users or specific user.

```bash
# Last 20 logins
rsr usermgmt session history

# Last 50 logins
rsr usermgmt session history -n 50

# History for specific user
rsr usermgmt session history -u username -n 20
```

#### session failures

View failed login attempts.

```bash
# Last 20 failures
rsr usermgmt session failures

# Last 100 failures
rsr usermgmt session failures -n 100
```

### Audit

Run comprehensive user security audit. This leverages the existing `user-audit.sh` script if available.

```bash
# Full audit
sudo rsr usermgmt audit

# With options (passed to user-audit.sh)
sudo rsr usermgmt audit -a
sudo rsr usermgmt audit -s sudo -s passwords
```

## Global Options

These options work with all subcommands:

- `-h, --help` - Display help message
- `-v, --verbose` - Enable verbose output
- `-d, --dry-run` - Show what would be done without executing
- `-y, --yes` - Auto-confirm all prompts (useful for automation)
- `-i, --interactive` - Run in interactive mode
- `--no-interactive` - Disable interactive mode

## Library Usage

The `lib/users.sh` library can be sourced in your own scripts:

```bash
#!/bin/bash

# Source the library
source ./lib/users.sh

# Use library functions
if user_exists "john"; then
    echo "User exists"
fi

# Create user programmatically
user_create "testuser" --shell /bin/bash --comment "Test User"

# Set password
password_set_string "testuser" "securepassword"

# Add to group
group_add_member "docker" "testuser"

# Check sudo access
if user_has_sudo "testuser"; then
    echo "User has sudo access"
fi
```

### Available Library Functions

**User Functions:**

- `user_exists "username"` - Check if user exists
- `user_get_info "username"` - Get user info (uid:gid:home:shell)
- `user_list_humans` - List human users (UID >= 500/1000)
- `user_list_all` - List all users
- `user_create "username" [options]` - Create user
- `user_delete "username" [--remove-home]` - Delete user
- `user_lock "username"` - Lock user account
- `user_unlock "username"` - Unlock user account
- `user_set_shell "username" "/bin/zsh"` - Change user shell
- `user_has_sudo "username"` - Check sudo access

**Password Functions:**

- `password_set "username"` - Set password (interactive)
- `password_set_string "username" "password"` - Set password (programmatic)
- `password_generate [length]` - Generate random password
- `password_expire_now "username"` - Force password change
- `password_get_expiry "username"` - Get expiry info (Linux)

**Group Functions:**

- `group_exists "groupname"` - Check if group exists
- `group_create "groupname" [--gid GID]` - Create group
- `group_add_member "groupname" "username"` - Add user to group
- `group_remove_member "groupname" "username"` - Remove user from group
- `group_list_members "groupname"` - List group members

**Permission Functions:**

- `permission_set "path" "mode" ["owner:group"]` - Set permissions
- `permission_set_recursive "path" "mode" ["owner:group"]` - Set recursively

**Session Functions:**

- `session_list` - List active sessions
- `session_list_detailed` - List with details
- `login_history ["username"] [lines]` - Get login history
- `login_failures [lines]` - Get failed login attempts

**SSH Key Functions:**

- `ssh_generate_key "username" [--type TYPE] [--bits BITS] [--comment COMMENT]` - Generate key pair
- `ssh_add_key "username" "public_key_content"` - Add key to authorized_keys
- `ssh_add_key_file "username" "/path/to/key.pub"` - Add key from file
- `ssh_remove_key "username" "identifier"` - Remove key by fingerprint/comment
- `ssh_list_keys "username"` - List authorized keys
- `ssh_get_fingerprints "username"` - Get key fingerprints
- `ssh_copy_keys "source_user" "dest_user"` - Copy keys between users
- `ssh_fix_permissions "username"` - Fix SSH directory permissions
- `ssh_validate_keys "username"` - Validate authorized_keys format
- `ssh_get_public_key "username" [key_file]` - Get public key content

## Best Practices

### Security

1. **Always use sudo** for user management operations
2. **Generate strong passwords** using the generate function
3. **Force password change** on first login for new users
4. **Regular audits** - run `rsr usermgmt audit` regularly
5. **Monitor failed logins** to detect brute force attempts

### Automation

```bash
# Batch create users from CSV
while IFS=, read -r username fullname groups; do
    sudo rsr usermgmt create -u "$username" -c "$fullname" -g "$groups" --generate
done < users.csv

# Automated password rotation
for user in $(rsr usermgmt list | awk '{print $1}' | tail -n +2); do
    sudo rsr usermgmt password expire -u "$user"
done
```

### Dry Run

Always test destructive operations with `--dry-run` first:

```bash
# Test before deleting
sudo rsr usermgmt delete -u username --remove-home --dry-run

# Review what would be done
sudo rsr usermgmt create -u newuser -g sudo,docker --dry-run
```

## Troubleshooting

### Common Issues

**"User already exists" error:**

```bash
# Check if user exists
rsr usermgmt list | grep username

# Use different username or delete existing user
sudo rsr usermgmt delete -u username
```

**Permission denied:**

```bash
# Most operations require root
sudo rsr usermgmt create -u username
```

**Group doesn't exist:**

```bash
# Create group first
sudo rsr usermgmt group create -g groupname

# Then add user
sudo rsr usermgmt group add -u username -g groupname
```

**macOS-specific issues:**

- Some operations require Full Disk Access in System Preferences
- `sysadminctl` requires authentication even with sudo
- Use `dscl` for programmatic access

**Linux distribution differences:**

- RHEL/CentOS use `wheel` group instead of `sudo`
- Alpine Linux uses `busybox` utilities
- Arch Linux may have different default paths

## Integration Examples

### With CI/CD

```yaml
# GitHub Actions example
- name: Create deployment user
  run: |
    sudo rsr usermgmt create -u deploy \
      -c "Deployment User" \
      -g docker \
      --generate > /tmp/deploy_password

    # Store password in secrets manager
    aws secretsmanager create-secret \
      --name deploy-password \
      --secret-string file:///tmp/deploy_password
```

### With Ansible

```yaml
- name: Manage users with RSR
  command: |
    rsr usermgmt create -u {{ username }} \
      -c "{{ full_name }}" \
      -g {{ groups | join(',') }} \
      --generate
  become: yes
  register: user_created
```

### With Docker

```dockerfile
# Use in Dockerfile
RUN curl -fsSL https://scripts.pandia.io/rsr | sh -s -- usermgmt create \
    -u appuser \
    -c "Application User" \
    --no-create-home
```

## Contributing

To extend the user management functionality:

1. Add functions to `lib/users.sh`
2. Update `scripts/bash/user-management.sh` subcommands
3. Add tests in `test/unit/user-management.bats`
4. Update registry in `scripts/registry.json`
5. Document in this README

## See Also

- [User Audit Script](../scripts/bash/user-audit.sh) - Comprehensive user auditing
- [SSH Hardening](../scripts/bash/ssh-hardening.sh) - SSH security configuration
- [Security Audit](../scripts/bash/security-audit.sh) - System security auditing
- [Firewall Setup](../scripts/bash/firewall-setup.sh) - Network access control

## Support

For issues, feature requests, or questions:

- GitHub Issues: <https://github.com/codefuturist/remote-script-runner/issues>
- Documentation: <https://codefuturist.github.io/remote-script-runner/>
