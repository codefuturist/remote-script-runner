# SSH Key Management Guide

Complete guide to managing SSH keys with the Remote Script Runner user management system.

## Overview

The SSH key management functionality provides comprehensive tools for:

- **Generating** SSH key pairs (RSA, Ed25519, ECDSA)
- **Adding** public keys to authorized_keys
- **Removing** keys safely with backups
- **Listing** keys with fingerprints
- **Copying** keys between users
- **Validating** authorized_keys format
- **Fixing** SSH directory permissions

All operations work cross-platform on Linux and macOS.

## Quick Start

```bash
# Generate Ed25519 key for user
sudo rsr usermgmt ssh generate -u john -t ed25519

# Add public key
sudo rsr usermgmt ssh add -u john -f ~/.ssh/id_rsa.pub

# List keys with fingerprints
rsr usermgmt ssh list -u john --fingerprints

# Fix permissions
sudo rsr usermgmt ssh fix -u john
```

## Commands

### ssh generate

Generate SSH key pair for a user with automatic permission setting.

**Usage:**

```bash
rsr usermgmt ssh generate -u USERNAME [OPTIONS]
```

**Options:**

- `-u, --username USER` - Username (required)
- `-t, --type TYPE` - Key type: rsa, ed25519, ecdsa, dsa (default: rsa)
- `-b, --bits BITS` - Key size for RSA/DSA (default: 4096)
- `-c, --comment COMMENT` - Key comment (default: user@hostname)

**Examples:**

```bash
# Generate modern Ed25519 key (recommended)
sudo rsr usermgmt ssh generate -u john -t ed25519

# Generate RSA 4096-bit key (traditional, compatible)
sudo rsr usermgmt ssh generate -u john -t rsa -b 4096

# Generate with custom comment
sudo rsr usermgmt ssh generate -u john -t ed25519 -c "john@company.com"

# Generate RSA 2048-bit key (faster, less secure)
sudo rsr usermgmt ssh generate -u john -t rsa -b 2048
```

**Key Types:**

| Type | Security | Speed | Compatibility | Recommended Use |
|------|----------|-------|---------------|-----------------|
| **ed25519** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | Modern systems | **✅ Best choice for new keys** |
| **rsa 4096** | ⭐⭐⭐⭐ | ⭐⭐⭐ | Universal | Legacy system compatibility |
| **rsa 2048** | ⭐⭐⭐ | ⭐⭐⭐⭐ | Universal | Faster, minimum secure size |
| **ecdsa** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | Most systems | Alternative to Ed25519 |
| **dsa** | ⭐ | ⭐⭐⭐ | Universal | ⛔ Deprecated, avoid |

**Output:**

- Private key: `~/.ssh/id_TYPE`
- Public key: `~/.ssh/id_TYPE.pub`
- Permissions automatically set (600 for private, 644 for public)
- Ownership set to user

### ssh add

Add SSH public key to user's authorized_keys file.

**Usage:**

```bash
rsr usermgmt ssh add -u USERNAME (-f FILE | -k KEY)
```

**Options:**

- `-u, --username USER` - Username (required)
- `-f, --file FILE` - Path to public key file
- `-k, --key KEY` - Public key content as string

**Examples:**

```bash
# Add key from file
sudo rsr usermgmt ssh add -u john -f /tmp/john_key.pub

# Add key from your own public key
sudo rsr usermgmt ssh add -u john -f ~/.ssh/id_rsa.pub

# Add key from string
sudo rsr usermgmt ssh add -u john -k "ssh-rsa AAAAB3NzaC1yc2E... user@host"

# Add key from stdin
cat ~/.ssh/id_ed25519.pub | sudo rsr usermgmt ssh add -u john -k "$(cat)"

# Add multiple keys
for key in /tmp/keys/*.pub; do
    sudo rsr usermgmt ssh add -u john -f "$key"
done
```

**Validation:**

- Checks key format before adding
- Prevents duplicate keys
- Creates .ssh directory if needed
- Sets proper permissions automatically

**Safety Features:**

- Won't add invalid keys
- Won't add duplicate keys
- Creates directory with correct permissions (700)
- Sets authorized_keys to 600

### ssh remove

Remove SSH key from user's authorized_keys with automatic backup.

**Usage:**

```bash
rsr usermgmt ssh remove -u USERNAME -i IDENTIFIER
```

**Options:**

- `-u, --username USER` - Username (required)
- `-i, --identifier ID` - Key identifier (fingerprint, comment, or key fragment)

**Examples:**

```bash
# Remove by comment/hostname
sudo rsr usermgmt ssh remove -u john -i "john@laptop"

# Remove by fingerprint
sudo rsr usermgmt ssh remove -u john -i "SHA256:abcd1234..."

# Remove by key fragment
sudo rsr usermgmt ssh remove -u john -i "AAAAB3NzaC1yc2E"

# Remove old RSA keys
sudo rsr usermgmt ssh remove -u john -i "ssh-rsa"
```

**Safety:**

- Creates backup at `~/.ssh/authorized_keys.backup`
- Validates match before deletion
- Returns error if no match found
- Preserves other keys

### ssh list

List authorized SSH keys for a user.

**Usage:**

```bash
rsr usermgmt ssh list -u USERNAME [--fingerprints]
```

**Options:**

- `-u, --username USER` - Username (required)
- `-f, --fingerprints` - Show key fingerprints instead of full keys

**Examples:**

```bash
# List full key content
rsr usermgmt ssh list -u john

# List with fingerprints (more readable)
rsr usermgmt ssh list -u john --fingerprints

# Count keys
rsr usermgmt ssh list -u john | wc -l

# Find specific key
rsr usermgmt ssh list -u john | grep "laptop"

# Check if user has any keys
if rsr usermgmt ssh list -u john | grep -q ssh-; then
    echo "User has SSH keys"
fi
```

**Output Format:**

Without `--fingerprints`:

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... john@laptop
ssh-rsa AAAAB3NzaC1yc2EAAAADAQAB... john@desktop
```

With `--fingerprints`:

```
256 SHA256:abcd1234efgh5678ijkl... john@laptop (ED25519)
4096 SHA256:mnop9012qrst3456uvwx... john@desktop (RSA)
```

### ssh copy

Copy all SSH keys from one user to another.

**Usage:**

```bash
rsr usermgmt ssh copy -s SOURCE_USER -d DEST_USER
```

**Options:**

- `-s, --source USER` - Source username (required)
- `-d, --dest USER` - Destination username (required)

**Examples:**

```bash
# Copy keys from admin to new developer
sudo rsr usermgmt ssh copy -s admin -d developer

# Copy keys when migrating users
sudo rsr usermgmt ssh copy -s olduser -d newuser

# Setup service account with admin keys
sudo rsr usermgmt ssh copy -s admin -d deploy

# Grant contractor same access as employee
sudo rsr usermgmt ssh copy -s employee -d contractor
```

**Behavior:**

- Copies all valid keys from source
- Skips duplicates in destination
- Creates .ssh directory if needed
- Sets proper permissions
- Preserves key comments

**Use Cases:**

- Onboarding new team members
- Setting up service accounts
- Migrating between accounts
- Temporary access grants

### ssh validate

Validate authorized_keys file format and content.

**Usage:**

```bash
rsr usermgmt ssh validate -u USERNAME
```

**Examples:**

```bash
# Validate keys
rsr usermgmt ssh validate -u john

# Check if validation passes
if rsr usermgmt ssh validate -u john; then
    echo "All keys valid"
else
    echo "Invalid keys found"
fi

# Validate all users
for user in $(rsr usermgmt list | awk '{print $1}' | tail -n +2); do
    echo "Validating $user..."
    rsr usermgmt ssh validate -u "$user"
done
```

**Output:**

```
Line 3: Invalid key format
Valid keys: 2
Invalid keys: 1
```

**Checks:**

- Key format validation
- Line-by-line analysis
- Counts valid and invalid keys
- Skips comments and empty lines

### ssh fix

Fix SSH directory and file permissions.

**Usage:**

```bash
rsr usermgmt ssh fix -u USERNAME
```

**Examples:**

```bash
# Fix permissions for user
sudo rsr usermgmt ssh fix -u john

# Fix after manual edits
sudo rsr usermgmt ssh fix -u john

# Fix all users (script)
for user in $(rsr usermgmt list | awk '{print $1}' | tail -n +2); do
    sudo rsr usermgmt ssh fix -u "$user"
done
```

**What it fixes:**

| Path | Permission | Ownership |
|------|------------|-----------|
| `~/.ssh/` | 700 (drwx------) | user:group |
| `authorized_keys` | 600 (-rw-------) | user:group |
| `id_*` (private) | 600 (-rw-------) | user:group |
| `*.pub` (public) | 644 (-rw-r--r--) | user:group |
| `config` | 600 (-rw-------) | user:group |
| `known_hosts` | 644 (-rw-r--r--) | user:group |

**When to use:**

- After manual file edits
- Permission denied errors
- After copying files as root
- Troubleshooting SSH access issues
- After user migration

## Common Workflows

### New User with SSH Access

```bash
# Create user
sudo rsr usermgmt create -u developer -c "Developer User" -g developers

# Generate SSH key
sudo rsr usermgmt ssh generate -u developer -t ed25519

# Display public key for user to save
rsr usermgmt ssh list -u developer

# Or add your admin key
sudo rsr usermgmt ssh add -u developer -f ~/.ssh/id_rsa.pub
```

### Deploy User Setup

```bash
# Create deploy user (no home directory, no login)
sudo rsr usermgmt create -u deploy -c "Deploy User" --no-create-home

# Add deployment key
sudo rsr usermgmt ssh add -u deploy -f /tmp/deploy_key.pub

# Add to necessary groups
sudo rsr usermgmt group add -u deploy -g docker

# Verify key
rsr usermgmt ssh list -u deploy --fingerprints
```

### SSH Key Rotation

```bash
# List current keys
rsr usermgmt ssh list -u john --fingerprints

# Remove old key
sudo rsr usermgmt ssh remove -u john -i "old-laptop"

# Add new key
sudo rsr usermgmt ssh add -u john -f /tmp/new_key.pub

# Validate
rsr usermgmt ssh validate -u john
```

### Bulk User SSH Setup

```bash
#!/bin/bash
# Setup SSH for multiple users

ADMIN_KEY="/tmp/admin_key.pub"
USERS="alice bob charlie"

for user in $USERS; do
    echo "Setting up SSH for $user..."

    # Generate key
    sudo rsr usermgmt ssh generate -u "$user" -t ed25519

    # Add admin key for access
    sudo rsr usermgmt ssh add -u "$user" -f "$ADMIN_KEY"

    # Fix permissions
    sudo rsr usermgmt ssh fix -u "$user"

    echo "✓ $user setup complete"
done
```

### SSH Access Audit

```bash
#!/bin/bash
# Audit SSH access across all users

echo "SSH Access Audit Report"
echo "======================"
echo ""

for user in $(rsr usermgmt list | awk '{print $1}' | tail -n +2); do
    key_count=$(rsr usermgmt ssh list -u "$user" 2>/dev/null | wc -l)

    if [ "$key_count" -gt 0 ]; then
        echo "User: $user"
        echo "  Keys: $key_count"
        rsr usermgmt ssh list -u "$user" --fingerprints 2>/dev/null | sed 's/^/    /'
        echo ""
    fi
done
```

### Revoke SSH Access

```bash
# Method 1: Remove all keys
for key in $(rsr usermgmt ssh list -u contractor | grep -v '^$'); do
    identifier=$(echo "$key" | awk '{print $NF}')
    sudo rsr usermgmt ssh remove -u contractor -i "$identifier"
done

# Method 2: Lock account (prevents all access)
sudo rsr usermgmt lock -u contractor

# Method 3: Delete user completely
sudo rsr usermgmt delete -u contractor --remove-home
```

## Library Functions

The `lib/users.sh` library provides these SSH functions for custom scripts:

```bash
#!/bin/bash
source ./lib/users.sh

# Generate key
ssh_generate_key "username" --type ed25519

# Add key from file
ssh_add_key_file "username" "/path/to/key.pub"

# Add key from string
ssh_add_key "username" "ssh-ed25519 AAAA... user@host"

# Remove key
ssh_remove_key "username" "identifier"

# List keys
ssh_list_keys "username"

# Get fingerprints
ssh_get_fingerprints "username"

# Copy keys
ssh_copy_keys "source" "destination"

# Validate keys
ssh_validate_keys "username"

# Fix permissions
ssh_fix_permissions "username"

# Get SSH directory
ssh_dir=$(ssh_get_dir "username")

# Get public key content
pub_key=$(ssh_get_public_key "username")
```

## Troubleshooting

### Permission Denied

**Problem:** SSH login fails with "Permission denied"

**Solution:**

```bash
# Check permissions
ls -la /home/john/.ssh/

# Fix permissions
sudo rsr usermgmt ssh fix -u john

# Verify authorized_keys exists
rsr usermgmt ssh list -u john
```

### Invalid Key Format

**Problem:** Key addition fails with "Invalid SSH public key format"

**Solution:**

```bash
# Verify key format
cat key.pub | head -c 20

# Should start with: ssh-rsa, ssh-ed25519, ecdsa-sha2-, or ssh-dss

# Get public key from private key
ssh-keygen -y -f ~/.ssh/id_rsa > /tmp/correct_key.pub

# Add corrected key
sudo rsr usermgmt ssh add -u john -f /tmp/correct_key.pub
```

### Key Already Exists

**Problem:** "Key already exists in authorized_keys"

**Solution:**

```bash
# List existing keys
rsr usermgmt ssh list -u john --fingerprints

# If truly duplicate, no action needed
# If different key with same fingerprint, investigate

# To force replace, remove and re-add
sudo rsr usermgmt ssh remove -u john -i "old_identifier"
sudo rsr usermgmt ssh add -u john -f new_key.pub
```

### SSH Directory Missing

**Problem:** "No such file or directory: /home/user/.ssh"

**Solution:**

```bash
# Any ssh operation will create it, or manually:
sudo mkdir -p /home/john/.ssh
sudo rsr usermgmt ssh fix -u john
```

### Wrong Permissions

**Problem:** SSH warns about insecure permissions

**Solution:**

```bash
# Fix all SSH permissions
sudo rsr usermgmt ssh fix -u john

# Manually check
ls -la /home/john/.ssh/
```

### macOS Permission Issues

**Problem:** "Operation not permitted" on macOS

**Solution:**

```bash
# Grant Full Disk Access in System Preferences
# Or use sudo

# Check if running as root
if [ $(id -u) -ne 0 ]; then
    echo "Need sudo for SSH operations"
fi
```

## Best Practices

### Key Generation

1. **Use Ed25519** for new keys (faster, more secure, smaller)
2. **Use RSA 4096** only for legacy system compatibility
3. **Add meaningful comments** to identify keys later
4. **Protect private keys** - never share or commit to git

### Key Management

1. **One key per device** - easier to revoke when device lost
2. **Regular audits** - review who has access
3. **Remove old keys** - cleanup when users leave or devices retired
4. **Use key passphrases** - additional layer of security

### Access Control

1. **Principle of least privilege** - minimal necessary access
2. **Service accounts** - separate keys for automated systems
3. **Time-limited access** - revoke contractor/temp access
4. **Audit trails** - log key additions/removals

### Security

1. **Validate keys** - run validation regularly
2. **Fix permissions** - run fix after any manual changes
3. **Monitor failed logins** - detect brute force attempts
4. **Use fail2ban** - automated blocking of attackers

## Integration Examples

### CI/CD Pipeline

```yaml
# GitHub Actions
- name: Setup deploy user SSH key
  run: |
    echo "${{ secrets.DEPLOY_KEY }}" > /tmp/deploy_key.pub
    sudo rsr usermgmt ssh add -u deploy -f /tmp/deploy_key.pub
    rm /tmp/deploy_key.pub
```

### Ansible Playbook

```yaml
- name: Setup user SSH keys
  command: >
    rsr usermgmt ssh generate
    -u {{ username }}
    -t ed25519
    -c "{{ email }}"
  become: yes

- name: Add admin key
  command: >
    rsr usermgmt ssh add
    -u {{ username }}
    -f /tmp/admin_key.pub
  become: yes
```

### Terraform

```hcl
resource "null_resource" "user_ssh" {
  provisioner "remote-exec" {
    inline = [
      "sudo rsr usermgmt ssh generate -u deploy -t ed25519",
      "sudo rsr usermgmt ssh add -u deploy -f /tmp/key.pub"
    ]
  }
}
```

## See Also

- [User Management Guide](USER_MANAGEMENT.md) - Complete user management
- [Quick Reference](USER_MANAGEMENT_QUICK_REFERENCE.md) - Command cheat sheet
- [SSH Hardening Script](../scripts/bash/ssh-hardening.sh) - SSH server security
- [Security Audit Script](../scripts/bash/security-audit.sh) - System security auditing

## Support

For issues or questions:

- GitHub: <https://github.com/codefuturist/remote-script-runner/issues>
- Documentation: <https://codefuturist.github.io/remote-script-runner/>
