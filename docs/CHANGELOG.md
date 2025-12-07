# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-07-24

### Added
- Initial release of Remote Script Runner
- System health check script with CPU, memory, disk, network, services, and uptime checks
- Server setup script with user configuration and package installation simulation
- Support for multiple shell environments (bash, zsh, sh, fish)
- PowerShell wrapper for cross-platform compatibility
- User-friendly CLI scripts (`run-script.sh` and `run`)
- Remote execution capabilities without repository cloning
- One-liner installation script (`install.sh`)
- Standalone remote runner (`remote-runner.sh`)
- Comprehensive documentation and syntax guide
- Cross-shell compatibility testing
- JSON and text output formats
- Verbose and dry-run modes
- Timeout support for operations
- Logging capabilities

### Features
- ✅ Run scripts remotely with a single curl command
- ✅ Support for multiple command-line arguments and options
- ✅ Proper error handling and logging
- ✅ Cross-platform compatibility (macOS and Linux)
- ✅ Timeout support for long-running operations
- ✅ Multiple output formats (text, JSON)
- ✅ Comprehensive system health checking
- ✅ User-friendly CLI with interactive menu
- ✅ Shell-specific implementations (bash, zsh, sh, fish, PowerShell)
- ✅ Remote usage without repository cloning

### Documentation
- README.md with comprehensive usage examples
- SYNTAX_GUIDE.md with detailed execution patterns
- Shell-specific documentation in scripts/README.md
- PowerShell integration examples
- Security considerations and best practices
