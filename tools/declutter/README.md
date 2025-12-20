# 🧹 Declutter

A modern, modular file organization and cleanup tool for **Windows**, **macOS**, and **Linux**.

## Features

### Scan Commands
- **Duplicates** - Find duplicate files using hash-based comparison (via czkawka)
- **Large Files** - Find files above configurable size thresholds
- **Old Files** - Find files not accessed in X days
- **Empty Items** - Find empty files and directories
- **Orphans** - Find junk files (.DS_Store, Thumbs.db, etc.)
- **Broken Symlinks** - Find and remove broken symbolic links
- **Directory Analysis** - Tree view with size breakdown

### Cleanup Presets
- **Quick** - Fast cleanup (empty, junk, symlinks)
- **Deep** - Comprehensive scan of all issues
- **Dev** - Developer cleanup (node_modules, __pycache__, build artifacts)
- **System** - System cleanup (caches, logs, temp files)

### Safe Operations
- 🔒 **Dry-run mode** - Preview changes without making them
- 🗑️ **Trash integration** - Move to trash instead of permanent delete
- ↩️ **Undo capability** - Journal-based action tracking
- 📝 **Detailed logging** - All actions are logged

### Organization
- Auto-organize files by type (documents, images, videos, etc.)
- Flatten nested directory structures
- Custom organization rules (via config)

## Installation

### Quick Install (Unix)
```bash
cd tools/declutter
./install.sh
```

### Windows Install
```powershell
# Option 1: Direct use
cd tools\declutter\bin\windows
.\declutter.ps1 help

# Option 2: Add to PATH
$env:PATH += ";$PWD\tools\declutter\bin\windows"

# Option 3: Create alias in PowerShell profile
Add-Content $PROFILE 'Set-Alias declutter "$HOME\path\to\declutter\bin\windows\declutter.ps1"'
```

### Manual Install (Unix)
```bash
# Install dependencies (macOS)
brew install czkawka jq fd fzf trash dust

# Add to PATH
ln -sf $(pwd)/bin/declutter ~/.local/bin/declutter
```

### Dependencies

| Tool | Purpose | Required | Windows | macOS | Linux |
|------|---------|----------|---------|-------|-------|
| `jq` | JSON processing | Yes (bash) | `scoop install jq` | `brew install jq` | `apt install jq` |
| `czkawka_cli` | Duplicate/similar detection | Recommended | `scoop install czkawka` | `brew install czkawka` | `cargo install czkawka_cli` |
| `fd` | Fast file finding | Optional | `scoop install fd` | `brew install fd` | `apt install fd-find` |
| `fzf` | Interactive selection | Optional | `scoop install fzf` | `brew install fzf` | `apt install fzf` |
| `trash` | Safe deletion | Optional | Built-in | `brew install trash` | `apt install trash-cli` |
| `dust` | Disk visualization | Optional | `scoop install dust` | `brew install dust` | `cargo install du-dust` |

## Usage

### Unix (Bash)
```bash
# Show help
declutter --help

# Quick cleanup
declutter quick ~/Downloads

# Find duplicates
declutter duplicates ~/Documents

# Developer cleanup (preview)
declutter dev --dry-run ~/Projects

# Find large files
declutter big ~/Videos 20

# Find old files (> 90 days)
declutter old ~/Downloads

# Analyze directory
declutter analyze ~/

# Show disk usage
declutter usage ~/
```

### Windows (PowerShell)
```powershell
# Show help
.\declutter.ps1 help

# Quick cleanup
.\declutter.ps1 quick ~\Downloads

# Find duplicates
.\declutter.ps1 duplicates ~\Documents

# Developer cleanup (preview)
.\declutter.ps1 dev -DryRun ~\Projects

# Find large files
.\declutter.ps1 large -Threshold 500MB ~\Videos

# Find old files
.\declutter.ps1 old -Days 30 ~\Downloads

# Disk usage analysis
.\declutter.ps1 analyze ~\
```

### Options

| Option | Description |
|--------|-------------|
| `-n, --dry-run` | Preview changes without making them |
| `-y, --yes` | Skip confirmation prompts |
| `-v, --verbose` | Show detailed output |
| `-q, --quiet` | Minimal output |
| `--json` | Output results as JSON |
| `--config FILE` | Use custom config file |

## Configuration

Configuration file location: `~/.config/declutter/config.yaml`

```yaml
global:
  dry_run: false
  interactive: true
  trash_enabled: true
  journal_enabled: true
  log_level: INFO

scanners:
  duplicates:
    hash_algorithm: md5
    min_size: 1
  large_files:
    threshold: 100MB
  old_files:
    age_days: 90

actions:
  delete:
    use_trash: true
    confirm_threshold: 10
```

## Architecture

The tool uses a modular architecture for extensibility and cross-platform support:

```
declutter/
├── declutter                  # Main CLI entry point (bash)
├── core/                      # Core functionality
│   ├── platform.sh            # Cross-platform utilities
│   ├── logger.sh              # Logging system
│   ├── config.sh              # Configuration management
│   └── safety.sh              # Undo/restore, safe operations
├── modules/                   # Feature modules
│   ├── duplicates.sh          # Duplicate detection (czkawka)
│   ├── large_files.sh         # Large file finder
│   ├── old_files.sh           # Old/unused file detection
│   ├── categorize.sh          # Smart categorization
│   ├── directory.sh           # Directory analysis
│   ├── presets.sh             # Cleanup presets
│   └── organize.sh            # Organization rules
├── adapters/                  # Platform adapters
│   ├── unix/                  # Unix/macOS specific
│   └── windows/               # Windows PowerShell
│       └── declutter.ps1      # Windows adapter
├── config/                    # Default configurations
├── tests/                     # Test suite
│   └── run_tests.sh
└── docs/                      # Documentation
```

### Module System

Each module is self-contained and can be loaded independently:

```bash
# Core modules provide:
- Platform detection (macOS/Linux/Windows)
- Logging with colors and levels
- Configuration (YAML-based)
- Safe operations with undo

# Feature modules provide:
- Specific functionality (duplicates, large files, etc.)
- Interactive workflows
- Batch operations
```

### Undo System

All destructive operations are tracked and can be undone:

```bash
# List undo sessions
declutter undo-list

# Undo a specific session
declutter undo session_20231214_120000
```

## Extended Commands

### Analysis Commands
| Command | Description |
|---------|-------------|
| `categories [path]` | Analyze file categories |
| `tree [path] [depth]` | Directory tree with sizes |
| `analyze [path]` | Directory size analysis |
| `bloated [path] [mb]` | Find large directories |
| `junk [path]` | Find junk files |
| `projects [path]` | Detect project folders |

### Organization Commands
| Command | Description |
|---------|-------------|
| `organize [path]` | Organize by category |
| `sort [source] [dest]` | Sort by extension rules |
| `rename [path] <style>` | Batch rename (lowercase, snake_case) |
| `flatten [path]` | Flatten nested directories |

### Safety Commands
| Command | Description |
|---------|-------------|
| `undo [session_id]` | Undo a previous operation |
| `undo-list` | List undo sessions |
| `history` | Show action history |

## Examples

### Developer Workflow
```bash
# Preview what would be cleaned
declutter dev --dry-run ~/Projects

# Clean build artifacts
declutter dev ~/Projects

# Clean specific project types
declutter dev --node ~/Projects      # Only node_modules
declutter dev --python ~/Projects    # Only __pycache__
```

### Finding Duplicates
```bash
# Scan for duplicates
declutter duplicates ~/Documents

# Interactive selection (requires fzf)
declutter duplicates ~/Pictures --interactive
```

### Organizing Downloads
```bash
# Quick cleanup first
declutter quick ~/Downloads

# Then organize by type
declutter organize ~/Downloads
```

### Undo Actions
```bash
# View recent actions
declutter history

# Undo last action
declutter undo

# Undo specific action
declutter undo <action-id>
```

## Data Locations

### Unix (macOS/Linux)
| Path | Purpose |
|------|---------|
| `~/.config/declutter/` | Configuration |
| `~/.local/share/declutter/journal/` | Action journal (for undo) |
| `~/.local/share/declutter/reports/` | Generated reports |
| `~/.cache/declutter/` | Scan result cache |

### Windows
| Path | Purpose |
|------|---------|
| `%LOCALAPPDATA%\declutter\config\` | Configuration |
| `%LOCALAPPDATA%\declutter\journal\` | Action journal (for undo) |
| `%LOCALAPPDATA%\declutter\reports\` | Generated reports |
| `%LOCALAPPDATA%\declutter\cache\` | Scan result cache |

## Cross-Platform Notes

The tool provides equivalent functionality on all platforms:

| Feature | Unix (Bash) | Windows (PowerShell) |
|---------|-------------|----------------------|
| Duplicate detection | ✅ czkawka + native | ✅ czkawka + native |
| Trash integration | ✅ `trash` command | ✅ Shell.Application COM |
| Large file scanning | ✅ fd/find | ✅ Get-ChildItem |
| Dry-run mode | ✅ `--dry-run` | ✅ `-DryRun` |
| Undo capability | ✅ Journal-based | ✅ Journal-based |
| JSON output | ✅ `--json` | ✅ `-JsonOutput` |

## License

MIT License - See LICENSE file for details.
