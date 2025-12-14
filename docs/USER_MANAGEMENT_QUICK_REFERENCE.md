# User Management Quick Reference

## Quick Commands

### Account Management

```bash
# Create user
sudo rsr usermgmt create -u john -c "John Doe" -g sudo,docker --generate

# Delete user
sudo rsr usermgmt delete -u john --remove-home

# Lock/unlock account
sudo rsr usermgmt lock -u john
sudo rsr usermgmt unlock -u john

# List users
rsr usermgmt list
rsr usermgmt list --sudo      # Only sudo users
rsr usermgmt list --all       # Including system users
```

### Password Management

```bash
# Reset password (interactive)
sudo rsr usermgmt password reset -u john

# Generate password
rsr usermgmt password generate
rsr usermgmt password generate --length 24

# Generate and set
sudo rsr usermgmt password generate -u john --set

# Force password change
sudo rsr usermgmt password expire -u john

# View policy
rsr usermgmt password policy
```

### Group Management

```bash
# Create group
sudo rsr usermgmt group create -g developers

# Add user to group
sudo rsr usermgmt group add -u john -g docker

# Remove from group
sudo rsr usermgmt group remove -u john -g docker

# List group members
rsr usermgmt group list -g docker

# Show user's groups
rsr usermgmt group show -u john
```

### Permission Management

```bash
# Set permissions
sudo rsr usermgmt permission set -p /var/www -m 755 -o www-data:www-data

# Recursive
sudo rsr usermgmt permission set -p /var/www -m 755 -R

# Apply template
sudo rsr usermgmt permission template -p /var/www -t web

# View permissions
rsr usermgmt permission get -p /var/www
```

**Available Templates:**

- `web` - 755, www-data:www-data
- `shared` - 775
- `private` - 700
- `service` - 644

### SSH Key Management

```bash
# Generate SSH key
sudo rsr usermgmt ssh generate -u john -t ed25519

# Generate RSA key
sudo rsr usermgmt ssh generate -u john -t rsa -b 4096

# Add key from file
sudo rsr usermgmt ssh add -u john -f ~/.ssh/id_rsa.pub

# Add key from string
sudo rsr usermgmt ssh add -u john -k "ssh-rsa AAAAB3... user@host"

# List keys
rsr usermgmt ssh list -u john

# List with fingerprints
rsr usermgmt ssh list -u john --fingerprints

# Remove key
sudo rsr usermgmt ssh remove -u john -i "user@hostname"

# Copy keys between users
sudo rsr usermgmt ssh copy -s alice -d bob

# Validate keys
rsr usermgmt ssh validate -u john

# Fix permissions
sudo rsr usermgmt ssh fix -u john
```

### Session Monitoring

```bash
# Active sessions
rsr usermgmt session list

# Login history
rsr usermgmt session history
rsr usermgmt session history -u john -n 50

# Failed logins
rsr usermgmt session failures
```

### Audit

```bash
# Full audit
sudo rsr usermgmt audit
```

## Common Workflows

### New Employee Onboarding

```bash
# Create user with all access
sudo rsr usermgmt create -u jane \
  -c "Jane Smith" \
  -s /bin/bash \
  -g sudo,docker \
  --generate \
  --force-change

# Set web directory permissions
sudo rsr usermgmt permission template -p /var/www -t web
```

### Employee Departure

```bash
# Lock account immediately
sudo rsr usermgmt lock -u john

# Review sessions
rsr usermgmt session list
rsr usermgmt session history -u john

# After data backup, delete
sudo rsr usermgmt delete -u john --remove-home
```

### Batch User Creation

```bash
# Create users.csv:
# john,John Doe,sudo
# jane,Jane Smith,docker
# mike,Mike Johnson,sudo,docker

while IFS=, read -r user name groups; do
    sudo rsr usermgmt create -u "$user" -c "$name" -g "$groups" --generate
done < users.csv
```

### Password Rotation

```bash
# Force all users to change password
for user in $(rsr usermgmt list | awk '{print $1}' | tail -n +2); do
    sudo rsr usermgmt password expire -u "$user"
done
```

### Security Audit

```bash
# List sudo users
rsr usermgmt list --sudo

# Check failed logins
rsr usermgmt session failures -n 100

# Full audit
sudo rsr usermgmt audit
```

### SSH Key Setup

```bash
# Setup new user with SSH key
sudo rsr usermgmt create -u deploy -c "Deploy User" --no-create-home
sudo rsr usermgmt ssh generate -u deploy -t ed25519
sudo rsr usermgmt ssh list -u deploy

# Add your public key to user
sudo rsr usermgmt ssh add -u deploy -f ~/.ssh/id_rsa.pub

# Copy keys from admin to new user
sudo rsr usermgmt ssh copy -s admin -d deploy

# Fix broken SSH permissions
sudo rsr usermgmt ssh fix -u deploy
```

### Server Access Management

```bash
# Grant user SSH access
sudo rsr usermgmt create -u contractor -g developers
sudo rsr usermgmt ssh add -u contractor -f /tmp/contractor_key.pub

# Revoke access (lock account)
sudo rsr usermgmt lock -u contractor

# Completely remove access
sudo rsr usermgmt ssh remove -u contractor -i "contractor@"
sudo rsr usermgmt delete -u contractor --remove-home
```

## Global Options

All commands support:

- `-h, --help` - Show help
- `-v, --verbose` - Verbose output
- `-d, --dry-run` - Preview changes
- `-y, --yes` - Auto-confirm
- `--no-interactive` - Disable interactive mode

## Safety Tips

1. **Always use dry-run first:**

   ```bash
   sudo rsr usermgmt delete -u john --remove-home --dry-run
   ```

2. **Generate strong passwords:**

   ```bash
   rsr usermgmt password generate --length 20
   ```

3. **Force password change for new users:**

   ```bash
   sudo rsr usermgmt create -u newuser --generate --force-change
   ```

4. **Regular audits:**

   ```bash
   sudo rsr usermgmt audit > /var/log/user-audit-$(date +%Y%m%d).log
   ```

## Troubleshooting

**"Permission denied"**
→ Use `sudo` for user management operations

**"User already exists"**
→ Check with `rsr usermgmt list | grep username`

**"Group doesn't exist"**
→ Create it first: `sudo rsr usermgmt group create -g groupname`

**macOS: "Operation not permitted"**
→ Grant Full Disk Access in System Preferences

## Files & Documentation

- Script: `scripts/bash/user-management.sh`
- Library: `lib/users.sh`
- Full Guide: `docs/USER_MANAGEMENT.md`
- Architecture: `docs/ARCHITECTURE.md`
- Registry: `scripts/registry.json` (id: "usermgmt")

## Support

- GitHub: <https://github.com/codefuturist/remote-script-runner>
- Issues: <https://github.com/codefuturist/remote-script-runner/issues>
- Docs: <https://codefuturist.github.io/remote-script-runner/>
