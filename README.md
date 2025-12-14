# Remote Script Runner

A collection of scripts designed to be run remotely via curl with support for multiple arguments and options.

## Features

- ✅ Run scripts remotely with a single curl command
- ✅ Support for multiple command-line arguments and options
- ✅ Proper error handling and logging
- ✅ Cross-platform compatibility (macOS and Linux)
- ✅ Timeout support for long-running operations
- ✅ Multiple output formats (text, JSON)
- ✅ Comprehensive system health checking
- ✅ User-friendly CLI with interactive menu
- ✅ Universal `rsr` entry point (POSIX-compatible)

## Quick Start

### 🚀 **Using `rsr` (Recommended)**

The `rsr` command is a universal, POSIX-compatible entry point that works everywhere:

```bash
# Remote execution via curl
curl -fsSL https://codefuturist.github.io/remote-script-runner/rsr | sh -s -- health -a

# Or with bash -c form
/bin/sh -c "$(curl -fsSL https://codefuturist.github.io/remote-script-runner/rsr)" -- health -a
```

**Available commands:**

```bash
rsr health -a                    # Run all health checks
rsr health -s cpu -s memory      # Specific checks
rsr setup -d -u admin nginx      # Server setup (dry-run)
rsr list                         # List available scripts
rsr --help                       # Show help
```

### 🎯 **Direct Script Syntax** (see [SYNTAX_GUIDE.md](docs/SYNTAX_GUIDE.md) for full comparison)

```bash
# Pattern 1: Pipe Form (RECOMMENDED for most cases)
curl -fsSL https://example.com/script.sh | bash -s -- [ARGUMENTS]

# Pattern 2: bash -c Form (for restricted environments)
/bin/bash -c "$(curl -fsSL https://example.com/script.sh)" -- [ARGUMENTS]
```

**Always use the `--` separator** to clearly separate bash options from script arguments.

### Examples

```bash
# Run all health checks (using pipe form)
curl -fsSL https://codefuturist.github.io/remote-script-runner/system-health-check.sh | bash -s -- -a

# Run specific checks with verbose output
curl -fsSL https://codefuturist.github.io/remote-script-runner/system-health-check.sh | bash -s -- -v -s cpu -s memory -s disk

# Setup a server with nginx and docker (bash -c form for sudo environments)
/bin/bash -c "$(curl -fsSL https://codefuturist.github.io/remote-script-runner/server-setup.sh)" -- -u admin -p production -i nginx -i docker

# Dry run server setup with verbose output
curl -fsSL https://codefuturist.github.io/remote-script-runner/server-setup.sh | bash -s -- -d -v -u dev -p development nodejs git vim
```

## Scripts

### Available Versions

Each script is available in multiple shell-specific versions:

- **Root directory**: Original bash scripts with `#!/bin/bash` shebang
- **`scripts/bash/`**: Bash-specific versions
- **`scripts/zsh/`**: Zsh-enhanced versions with advanced features
- **`scripts/sh/`**: POSIX-compliant versions for maximum portability
- **`scripts/fish/`**: Fish shell versions with user-friendly syntax

See [`scripts/README.md`](scripts/README.md) for details on shell-specific features.

### User-Friendly CLI Scripts

#### For Local Use (after cloning repository)

**run-script.sh** - Interactive CLI with menu:

```bash
# Show interactive menu (default when no args)
./run-script.sh

# Direct command execution
./run-script.sh health-check -a
./run-script.sh server-setup -d -u admin -p production nginx
```

**run** - Simple CLI for quick access:

```bash
# Quick health check
./run health -a
./run health -s cpu -s memory

# Server setup
./run setup -d -u admin -p production nginx
```

#### For Remote Use (without cloning repository)

**🚀 One-liner Installation:**

```bash
# Install remote-runner to ~/.local/bin/remote-runner
curl -fsSL https://codefuturist.github.io/remote-script-runner/install.sh | bash

# Then use it anywhere:
remote-runner health -a
remote-runner setup -d -u admin -p production nginx
```

**⚡ Direct Execution (no installation):**

```bash
# Run health check directly
curl -fsSL https://codefuturist.github.io/remote-script-runner/remote-runner.sh | bash -s -- health -a

# Run server setup directly
curl -fsSL https://codefuturist.github.io/remote-script-runner/remote-runner.sh | bash -s -- setup -d -u admin -p production nginx

# Show help
curl -fsSL https://codefuturist.github.io/remote-script-runner/remote-runner.sh | bash -s -- -h
```

**📥 Download and Reuse:**

```bash
# Download once
curl -fsSL https://codefuturist.github.io/remote-script-runner/remote-runner.sh -o remote-runner.sh
chmod +x remote-runner.sh

# Use multiple times
./remote-runner.sh health -s cpu memory
./remote-runner.sh setup -h
```

### system-health-check.sh

A comprehensive system health monitoring script that can check:

- **CPU**: Usage percentage and load averages
- **Memory**: RAM usage statistics
- **Disk**: Storage usage for all mounted filesystems
- **Network**: Network interface status and IP addresses
- **Services**: Status of common system services
- **Uptime**: System uptime and boot information

#### Usage

```bash
./system-health-check.sh [OPTIONS] [CHECKS...]
```

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Display help message |
| `-v, --verbose` | Enable verbose output |
| `-t, --timeout SECONDS` | Set timeout for each check (default: 10) |
| `-l, --log FILE` | Log output to file |
| `-f, --format FORMAT` | Output format: text, json (default: text) |
| `-s, --select CHECKS` | Select specific checks (can be used multiple times) |
| `-a, --all` | Run all available checks |

#### Available Checks

- `cpu` - CPU usage and load average
- `memory` - Memory usage statistics
- `disk` - Disk usage for all mounted filesystems
- `network` - Network interface statistics
- `services` - Check status of common services
- `uptime` - System uptime information

#### Examples

```bash
# Local execution
./system-health-check.sh -v -s cpu -s memory -s disk
./system-health-check.sh -a -t 5
./system-health-check.sh -l /var/log/health-check.log -f json -a

# Remote execution
/bin/bash -c "$(curl -fsSL https://codefuturist.github.io/remote-script-runner/system-health-check.sh)" -- -v -s cpu memory disk -t 5 >> /var/log/health-check.log 2>/dev/null
```

### server-setup.sh

A server configuration script that simulates setting up a server environment with user configuration, profile application, and package installation.

#### Usage

```bash
./server-setup.sh [OPTIONS] [PACKAGES...]
```

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Display help message |
| `-u, --username USERNAME` | Set username for configuration (required) |
| `-p, --profile PROFILE` | Environment profile: development\|production (default: development) |
| `-i, --install PACKAGES` | Packages to install (can be used multiple times) |
| `-d, --dry-run` | Show what would be done without executing |
| `-v, --verbose` | Enable verbose output |

#### Available Packages

- `nginx` - Web server
- `docker` - Container platform
- `nodejs` - JavaScript runtime
- `python3` - Python programming language
- `git` - Version control system
- `curl` - Command line HTTP client
- `vim` - Text editor
- `htop` - Process monitor
- `fail2ban` - Intrusion prevention

#### Examples

```bash
# Local execution
./server-setup.sh -u admin -p production -i nginx -i docker
./server-setup.sh -u dev -p development nodejs git vim htop
./server-setup.sh -d -u admin -p production -i nginx -i docker  # Dry run

# Remote execution
/bin/bash -c "$(curl -fsSL https://codefuturist.github.io/remote-script-runner/server-setup.sh)" -- -u admin -p production -i nginx docker
/bin/bash -c "$(curl -fsSL https://codefuturist.github.io/remote-script-runner/server-setup.sh)" -- -d -v -u dev nodejs python3 git
```

### user-management.sh ✨ NEW

A comprehensive cross-platform user management system with support for Linux and macOS. Covers account lifecycle, password management, groups, permissions, and session monitoring.

**Full Documentation**: [`docs/USER_MANAGEMENT.md`](docs/USER_MANAGEMENT.md) | **Quick Reference**: [`docs/USER_MANAGEMENT_QUICK_REFERENCE.md`](docs/USER_MANAGEMENT_QUICK_REFERENCE.md)

#### Usage

```bash
./scripts/bash/user-management.sh <subcommand> [OPTIONS]
```

#### Subcommands

**Account Management:**

- `create` - Create user account with groups, passwords, custom settings
- `delete` - Delete user account with optional home removal
- `lock` / `unlock` - Disable/enable user login
- `list` - List users with filtering options

**Password Management:**

- `password reset` - Reset user password
- `password expire` - Force password change on next login
- `password generate` - Generate secure random passwords
- `password policy` - View password policy settings

**Group Management:**

- `group create` - Create new group
- `group add` - Add user to group
- `group remove` - Remove user from group
- `group list` - List group members
- `group show` - Show user's groups

**Permission Management:**

- `permission set` - Set file/folder permissions and ownership
- `permission get` - View current permissions
- `permission template` - Apply permission templates (web, shared, private, service)

**SSH Key Management:**

- `ssh generate` - Generate SSH key pair for user
- `ssh add` - Add public key to authorized_keys
- `ssh remove` - Remove key from authorized_keys
- `ssh list` - List authorized SSH keys
- `ssh copy` - Copy SSH keys between users
- `ssh validate` - Validate authorized_keys file
- `ssh fix` - Fix SSH directory permissions

**Session Monitoring:**

- `session list` - List active user sessions
- `session history` - View login history
- `session failures` - Show failed login attempts

**Audit:**

- `audit` - Run comprehensive user security audit

#### Quick Examples

```bash
# Create user with generated password
sudo rsr usermgmt create -u john -c "John Doe" -g sudo,docker --generate

# List sudo users
rsr usermgmt list --sudo

# Reset password
sudo rsr usermgmt password reset -u john

# Add user to group
sudo rsr usermgmt group add -u john -g docker

# Set web permissions
sudo rsr usermgmt permission template -p /var/www -t web

# Generate SSH key
sudo rsr usermgmt ssh generate -u john -t ed25519

# Add SSH key
sudo rsr usermgmt ssh add -u john -f ~/.ssh/id_rsa.pub

# List SSH keys
rsr usermgmt ssh list -u john --fingerprints

# View active sessions
rsr usermgmt session list

# Run audit
sudo rsr usermgmt audit

# Remote execution
/bin/bash -c "$(curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/bash/user-management.sh)" -- create -u john -c "John Doe" --generate
```

#### Features

✅ **Cross-Platform**: Full support for Linux, macOS, and Windows
✅ **Comprehensive**: Account, password, group, permission, SSH key, and session management
✅ **Safe**: Dry-run mode, confirmations, input validation
✅ **Modern**: Subcommand structure, colored output, helpful error messages
✅ **Scriptable**: Library functions (`lib/users.sh` and `lib/users.ps1`) for custom scripts
✅ **Documented**: Extensive guides and examples

**Platform-Specific:**

- **Linux/macOS**: Uses bash (`lib/users.sh`) with `useradd`, `dscl`, etc.
- **Windows**: Uses PowerShell (`lib/users.ps1`) with `New-LocalUser`, `Get-LocalUser`, etc.
- **Same Commands**: Identical syntax across all platforms

See [User Management Guide](docs/USER_MANAGEMENT.md) for complete documentation.

### ssh-server ✨ NEW

Complete SSH server management with installation, configuration, hardening, and monitoring across Linux, macOS, and Windows.

**Full Documentation**: [`docs/SSH_SERVER_MANAGEMENT.md`](docs/SSH_SERVER_MANAGEMENT.md)

#### Usage

```bash
./scripts/bash/ssh-server.sh <subcommand> [OPTIONS]

# Windows
.\scripts\powershell\SSHServer.ps1 <subcommand> [OPTIONS]
```

#### Subcommands

**Installation & Setup:**

- `install` - Install SSH server
- `enable` - Enable at boot
- `start` - Start service

**Service Control:**

- `start/stop/restart` - Service control
- `status` - Show comprehensive status
- `enable/disable` - Boot configuration

**Configuration:**

- `config get/set` - Get/set configuration values
- `config backup/restore` - Backup and restore
- `config validate` - Validate syntax

**Security & Hardening:**

- `harden` - Apply security hardening (integrates with ssh-hardening script)
- `audit` - Run security audit
- `score` - Show security score (0-100)

**Testing & Diagnostics:**

- `test [host] [port]` - Test SSH connection
- `connections` - Show active connections
- `logs [lines]` - Show SSH logs
- `failed` - Show failed login attempts

#### Quick Examples

```bash
# Install and enable SSH server
sudo rsr ssh-server install
sudo rsr ssh-server enable
sudo rsr ssh-server start

# Check status and security score
rsr ssh-server status
rsr ssh-server score

# Apply security hardening
sudo rsr ssh-server harden

# Change SSH port
sudo rsr ssh-server config set Port 2222
sudo rsr ssh-server restart

# Monitor failed logins
rsr ssh-server failed

# Test connection
rsr ssh-server test myserver.com

# Windows
.\rsr.ps1 ssh-server install
.\rsr.ps1 ssh-server harden
```

#### Features

✅ **Cross-Platform**: Full support for Linux, macOS, and Windows
✅ **Complete Management**: Install, configure, control, monitor SSH servers
✅ **Security Hardening**: Integrated with ssh-hardening script + security scoring
✅ **Safe Operations**: Automatic backups, validation, confirmations
✅ **Diagnostics**: Connection testing, log viewing, failed login tracking
✅ **Modern**: Subcommand structure, colored output, helpful messages

**Platform-Specific:**

- **Linux**: Package manager integration, systemd/init.d support
- **macOS**: Built-in SSH with launchd control
- **Windows**: OpenSSH Server via Windows Capability

**Integration:**

- Works with `rsr ssh-harden` for advanced hardening
- Compatible with `rsr usermgmt ssh` for user key management
- Supports Ansible, Docker, CI/CD workflows

See [SSH Server Management Guide](docs/SSH_SERVER_MANAGEMENT.md) for complete documentation.

## How It Works

The pattern for running scripts remotely with arguments is:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/username/repo/main/script.sh)" -- [SCRIPT_ARGUMENTS]
```

Key components:

1. **`curl -fsSL`**: Downloads the script content
   - `-f`: Fail silently on HTTP errors
   - `-s`: Silent mode (no progress bar)
   - `-S`: Show errors even in silent mode
   - `-L`: Follow redirects

2. **`/bin/bash -c "$(...)"`**: Executes the downloaded script

3. **`-- [ARGUMENTS]`**: The `--` separates bash options from script arguments

## Quick Reference

### Common Use Cases

```bash
# System monitoring in cron
*/5 * * * * /bin/bash -c "$(curl -fsSL https://codefuturist.github.io/remote-script-runner/system-health-check.sh)" -- -s cpu memory disk >> /var/log/health.log 2>&1

# Server provisioning
/bin/bash -c "$(curl -fsSL https://codefuturist.github.io/remote-script-runner/server-setup.sh)" -- -u $(whoami) -p production nginx docker python3

# Quick health check with timeout
/bin/bash -c "$(curl -fsSL https://codefuturist.github.io/remote-script-runner/system-health-check.sh)" -- -a -t 30

# Dry run before actual execution
/bin/bash -c "$(curl -fsSL https://codefuturist.github.io/remote-script-runner/server-setup.sh)" -- -d -v -u admin -p production nginx
```

### SSH Remote Execution

```bash
# Execute on remote server
ssh user@server '/bin/bash -c "$(curl -fsSL https://codefuturist.github.io/remote-script-runner/system-health-check.sh)" -- -a'

# Multiple servers
for server in web1 web2 db1; do
    echo "Checking $server..."
    ssh "user@$server" '/bin/bash -c "$(curl -fsSL https://codefuturist.github.io/remote-script-runner/system-health-check.sh)" -- -s cpu memory'
done
```

### zsh Examples (macOS Default Shell)

```bash
# Use zsh explicitly (pipe form)
curl -fsSL https://codefuturist.github.io/remote-script-runner/system-health-check.sh | zsh -s -- -v -s cpu memory

# Use zsh with bash -c form
zsh -c "$(curl -fsSL https://codefuturist.github.io/remote-script-runner/system-health-check.sh)" -- -s uptime

# Auto-detect current shell
curl -fsSL https://codefuturist.github.io/remote-script-runner/system-health-check.sh | "$SHELL" -s -- -a

# Cross-platform: use bash for consistency
curl -fsSL https://codefuturist.github.io/remote-script-runner/server-setup.sh | bash -s -- -d -u admin -p development nodejs
```

### PowerShell Examples (Windows/macOS/Linux)

```powershell
# Basic execution with PowerShell
Invoke-RestMethod -Uri 'https://codefuturist.github.io/remote-script-runner/system-health-check.sh' | bash -s -- -v -s cpu memory

# Save and execute
$script = Invoke-RestMethod -Uri 'https://codefuturist.github.io/remote-script-runner/server-setup.sh'
$script | bash -s -- -d -u admin -p production nginx docker

# One-liner from any shell
pwsh -Command "Invoke-RestMethod -Uri 'https://codefuturist.github.io/remote-script-runner/system-health-check.sh' | bash -s -- -a"

# Windows with WSL
Invoke-RestMethod -Uri 'https://codefuturist.github.io/remote-script-runner/system-health-check.sh' | wsl bash -s -- -s uptime
```

### Production Safety

```bash
# Pin to specific version (using GitHub raw URL for commit pinning)
COMMIT="d943416"
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/codefuturist/remote-script-runner/${COMMIT}/system-health-check.sh)" -- -a

# Download, review, then execute
curl -fsSL https://codefuturist.github.io/remote-script-runner/system-health-check.sh > /tmp/check.sh
less /tmp/check.sh  # Review first
chmod +x /tmp/check.sh && /tmp/check.sh -- -a
```

📖 **See [SYNTAX_GUIDE.md](docs/SYNTAX_GUIDE.md) for comprehensive syntax recommendations and advanced patterns.**

## Security Considerations

⚠️ **Important Security Notes:**

- Always review scripts before running them remotely
- Use HTTPS URLs to prevent man-in-the-middle attacks
- Consider pinning to specific commits/tags instead of `main` branch
- Validate the source and integrity of scripts
- Be cautious with scripts that require elevated privileges

### Safer Execution

For production use, consider:

```bash
# Download and review first
curl -fsSL https://raw.githubusercontent.com/username/repo/main/script.sh > script.sh
less script.sh  # Review the script
chmod +x script.sh
./script.sh -a  # Run locally after review

# Or pin to a specific commit
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/username/repo/abc123def/script.sh)" -- -a
```

## Creating Your Own Remote Scripts

Follow these patterns to create scripts that work well remotely:

### 1. Robust Argument Parsing

```bash
#!/bin/bash
set -euo pipefail

# Use getopt for robust argument parsing
TEMP=$(getopt -o hvs: --long help,verbose,select: -n "$0" -- "$@")
eval set -- "$TEMP"
```

### 2. Proper Error Handling

```bash
# Exit on errors
set -euo pipefail

# Handle missing dependencies
if ! command -v required_tool >/dev/null 2>&1; then
    echo "Error: required_tool is not installed"
    exit 1
fi
```

### 3. Flexible Output Options

```bash
# Support different output formats
log() {
    local level="$1"
    local message="$2"

    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "{\"level\":\"$level\",\"message\":\"$message\"}"
    else
        echo "[$level] $message"
    fi
}
```

### 4. Timeout Support

```bash
# Use timeout for potentially long-running operations
timeout "$TIMEOUT" some_long_operation || echo "Operation timed out"
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add your script following the established patterns
4. Update the README with usage examples
5. Submit a pull request

## License

MIT License - feel free to use these scripts in your own projects.
