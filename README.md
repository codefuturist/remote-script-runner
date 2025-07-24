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

## Quick Start

Run the system health check script remotely:

```bash
# Run all health checks
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/yourusername/remote-script-runner/main/system-health-check.sh)" -- -a

# Run specific checks with verbose output
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/yourusername/remote-script-runner/main/system-health-check.sh)" -- -v -s cpu -s memory -s disk

# Run with custom timeout and log to file
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/yourusername/remote-script-runner/main/system-health-check.sh)" -- -t 30 -l /tmp/health-check.log -a

# Output in JSON format
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/yourusername/remote-script-runner/main/system-health-check.sh)" -- -f json -a
```

## Scripts

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
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/yourusername/remote-script-runner/main/system-health-check.sh)" -- -v -s cpu memory disk -t 5 >> /var/log/health-check.log 2>/dev/null
```

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
