# Declutter Tool Architecture

## Overview

This document outlines the architecture for a modular, extensible file organization and cleanup tool following industry best practices.

---

## Design Principles

1. **Separation of Concerns** — Each feature is an independent module
2. **Plugin Architecture** — Easy to add new scanners and actions
3. **Configuration-Driven** — Behavior controlled via YAML/JSON configs
4. **Idempotent Operations** — Safe to run multiple times
5. **Audit Trail** — All actions logged for undo/review
6. **Fail-Safe Defaults** — Dry-run, trash-first, confirm destructive actions

---

## Directory Structure

```
declutter/
├── bin/
│   └── declutter                    # Main entry point CLI
├── lib/
│   ├── core/
│   │   ├── engine.sh                # Orchestration engine
│   │   ├── config.sh                # Configuration loader
│   │   ├── logger.sh                # Logging utilities
│   │   ├── ui.sh                    # User interface helpers
│   │   └── utils.sh                 # Common utilities
│   ├── scanners/                    # Feature modules (read-only analysis)
│   │   ├── duplicates.sh            # Duplicate detection
│   │   ├── large_files.sh           # Large file finder
│   │   ├── old_files.sh             # Old/unused file detection
│   │   ├── categorize.sh            # Smart categorization
│   │   ├── directory_analysis.sh    # Directory tree analysis
│   │   └── orphans.sh               # Orphaned file detection
│   ├── actions/                     # Operations (modify filesystem)
│   │   ├── delete.sh                # Safe delete (trash/rm)
│   │   ├── move.sh                  # Move files
│   │   ├── compress.sh              # Archive/compress
│   │   ├── rename.sh                # Rename with patterns
│   │   └── organize.sh              # Auto-organize by rules
│   ├── presets/                     # Pre-configured cleanup profiles
│   │   ├── dev.sh                   # Developer cleanup
│   │   ├── system.sh                # System cleanup
│   │   ├── media.sh                 # Media file cleanup
│   │   └── custom.sh                # User-defined rules loader
│   └── undo/
│       ├── journal.sh               # Action journaling
│       └── restore.sh               # Undo/restore operations
├── config/
│   ├── default.yaml                 # Default configuration
│   ├── rules/
│   │   ├── organize.yaml            # Organization rules
│   │   ├── ignore.yaml              # Ignore patterns
│   │   └── presets/
│   │       ├── dev.yaml
│   │       ├── system.yaml
│   │       └── custom.yaml
│   └── schemas/
│       └── config.schema.json       # Config validation schema
├── data/
│   ├── cache/                       # Scan result cache
│   ├── journal/                     # Action journal for undo
│   └── reports/                     # Generated reports
├── tests/
│   ├── unit/
│   ├── integration/
│   └── fixtures/
├── docs/
│   ├── ARCHITECTURE.md
│   ├── PLUGINS.md
│   └── CONFIG.md
├── install.sh
└── README.md
```

---

## Core Components

### 1. Engine (`lib/core/engine.sh`)

Central orchestrator that:
- Loads configuration
- Discovers and registers modules
- Executes scan → review → action pipeline
- Manages state and journaling

```bash
# Pseudo-interface
engine_init()           # Initialize engine with config
engine_register()       # Register scanner/action modules
engine_run_pipeline()   # Execute: scan → filter → review → action
engine_get_results()    # Retrieve scan results
```

### 2. Configuration System (`lib/core/config.sh`)

Hierarchical configuration loading:

```
Priority (highest to lowest):
1. CLI arguments
2. Environment variables (DECLUTTER_*)
3. Project config (.declutter.yaml)
4. User config (~/.config/declutter/config.yaml)
5. Default config (config/default.yaml)
```

**Configuration Schema:**

```yaml
# config/default.yaml
version: "1.0"

global:
  dry_run: false
  interactive: true
  trash_enabled: true
  journal_enabled: true
  log_level: info

scanners:
  duplicates:
    enabled: true
    hash_algorithm: xxhash       # md5, sha256, xxhash
    min_size: 1024               # Skip files smaller than 1KB
    include_hidden: false

  large_files:
    enabled: true
    thresholds:
      warning: 100MB
      critical: 1GB
    sort_by: size                # size, atime, mtime

  old_files:
    enabled: true
    age_days: 90
    use_atime: true              # Access time vs modify time

  categorization:
    enabled: true
    categories:
      documents: ["pdf", "doc", "docx", "txt", "md"]
      images: ["jpg", "jpeg", "png", "gif", "webp", "svg"]
      videos: ["mp4", "mkv", "avi", "mov", "webm"]
      audio: ["mp3", "flac", "wav", "aac", "ogg"]
      code: ["js", "ts", "py", "go", "rs", "java", "c", "cpp"]
      archives: ["zip", "tar", "gz", "7z", "rar"]

actions:
  delete:
    use_trash: true
    confirm_threshold: 10        # Confirm if deleting more than N files

  move:
    create_dirs: true
    overwrite: false

  compress:
    format: zstd                 # gzip, zstd, zip
    level: 3

presets:
  dev:
    patterns:
      - "node_modules"
      - "__pycache__"
      - "*.pyc"
      - ".pytest_cache"
      - ".mypy_cache"
      - "dist"
      - "build"
      - "target"
      - ".next"
      - ".nuxt"
    exclude:
      - ".git"

  system:
    patterns:
      - "*.log"
      - "*.tmp"
      - ".DS_Store"
      - "Thumbs.db"
      - "*.bak"
      - "*~"

organize:
  rules:
    - match: "Screenshot*.png"
      destination: "~/Screenshots"
    - match: "*.pdf"
      destination: "~/Documents/PDFs"
    - match: "*.{jpg,jpeg,png,gif}"
      destination: "~/Pictures/Unsorted"

ignore:
  paths:
    - ".git"
    - ".svn"
    - "node_modules"  # Scanned separately by dev preset
  patterns:
    - "*.swp"
    - ".DS_Store"
```

### 3. Logger (`lib/core/logger.sh`)

Structured logging with levels and output targets:

```bash
# Log levels: DEBUG, INFO, WARN, ERROR
log_debug "Scanning directory: $dir"
log_info "Found 42 duplicates"
log_warn "Large file detected: $file (2.5GB)"
log_error "Permission denied: $path"

# Output targets
# - Console (with colors)
# - File (~/.local/share/declutter/logs/)
# - JSON (for machine parsing)
```

### 4. Journal System (`lib/undo/journal.sh`)

Every destructive action is logged for undo:

```bash
# Journal entry structure
{
  "id": "uuid-v4",
  "timestamp": "2024-01-15T10:30:00Z",
  "action": "delete",
  "source": "/path/to/file.txt",
  "destination": "~/.local/share/Trash/files/file.txt",
  "metadata": {
    "size": 1024,
    "hash": "abc123",
    "permissions": "644"
  },
  "reversible": true
}
```

**Undo capabilities:**
- Restore from trash
- Reverse moves
- Decompress archived files
- Restore renamed files

---

## Feature Modules

### Feature 1: Duplicate Detection (`lib/scanners/duplicates.sh`)

**Architecture:**

```
┌─────────────────────────────────────────────────────────────┐
│                    Duplicate Scanner                         │
├─────────────────────────────────────────────────────────────┤
│  Phase 1: Size Grouping                                      │
│  ├── Group files by size (fast filter)                       │
│  └── Skip unique sizes                                       │
├─────────────────────────────────────────────────────────────┤
│  Phase 2: Partial Hash                                       │
│  ├── Hash first 4KB of files with matching sizes             │
│  └── Skip non-matching partial hashes                        │
├─────────────────────────────────────────────────────────────┤
│  Phase 3: Full Hash                                          │
│  ├── Hash entire file for remaining candidates               │
│  └── Group by full hash = exact duplicates                   │
├─────────────────────────────────────────────────────────────┤
│  Phase 4: Near-Duplicate Detection (optional)                │
│  ├── Fuzzy name matching (Levenshtein distance)              │
│  ├── Similar size detection (within 5%)                      │
│  └── Image perceptual hashing (pHash)                        │
└─────────────────────────────────────────────────────────────┘
```

**Interface:**

```bash
# Scanner interface
scan_duplicates() {
    local target_path="$1"
    local config="$2"
    # Returns: JSON array of duplicate groups
}

# Output format
{
  "scan_type": "duplicates",
  "timestamp": "...",
  "groups": [
    {
      "hash": "abc123",
      "size": 1048576,
      "files": [
        {"path": "/a/file.txt", "mtime": "...", "atime": "..."},
        {"path": "/b/file.txt", "mtime": "...", "atime": "..."}
      ],
      "recommendation": "keep_newest"
    }
  ],
  "stats": {
    "total_groups": 10,
    "total_duplicates": 25,
    "wasted_space": 104857600
  }
}
```

**External Tools:**
- `czkawka_cli dup` — Primary duplicate scanner
- `jdupes` — Alternative/verification
- `xxhash` — Fast hashing for large files

---

### Feature 2: Large File Finder (`lib/scanners/large_files.sh`)

**Interface:**

```bash
scan_large_files() {
    local target_path="$1"
    local threshold="$2"      # e.g., "100MB"
    local sort_by="$3"        # size|atime|mtime
    # Returns: JSON array of large files
}
```

**Output:**

```json
{
  "scan_type": "large_files",
  "threshold": "100MB",
  "files": [
    {
      "path": "/path/to/large.zip",
      "size": 2147483648,
      "size_human": "2.0 GB",
      "atime": "2024-01-01T00:00:00Z",
      "mtime": "2023-06-15T00:00:00Z",
      "type": "archive",
      "recommendations": ["compress", "archive", "delete"]
    }
  ],
  "stats": {
    "total_files": 15,
    "total_size": 10737418240
  }
}
```

**External Tools:**
- `czkawka_cli big` — Find largest files
- `dust` — Disk usage visualization
- `fd` — Fast file finding with size filter

---

### Feature 3: Old/Unused File Detection (`lib/scanners/old_files.sh`)

**Strategy:**

```
┌─────────────────────────────────────────────────────────────┐
│                    Age Detection Strategy                    │
├─────────────────────────────────────────────────────────────┤
│  1. Access Time (atime)                                      │
│     └── When file was last read                              │
│  2. Modify Time (mtime)                                      │
│     └── When file content changed                            │
│  3. Change Time (ctime)                                      │
│     └── When metadata changed                                │
├─────────────────────────────────────────────────────────────┤
│  Special Handling:                                           │
│  • Downloads folder: Flag files > 30 days                    │
│  • Cache dirs: Flag all contents                             │
│  • Project folders: Use mtime, not atime                     │
│  • System files: Exclude from scanning                       │
└─────────────────────────────────────────────────────────────┘
```

**External Tools:**
- `fd --changed-before` — Find files by age
- `find -atime/-mtime` — Standard Unix approach

---

### Feature 4: Smart Categorization (`lib/scanners/categorize.sh`)

**Category Detection:**

```yaml
detection_methods:
  1. Extension-based:     # Fast, primary method
     - Map extension → category

  2. MIME-type based:     # More accurate fallback
     - Use `file --mime-type`

  3. Content analysis:    # For extensionless files
     - Magic bytes detection
     - Text encoding detection
```

**Project Detection:**

```bash
# Detect project type by marker files
detect_project_type() {
    local dir="$1"

    [[ -f "$dir/package.json" ]] && echo "nodejs"
    [[ -f "$dir/Cargo.toml" ]] && echo "rust"
    [[ -f "$dir/go.mod" ]] && echo "go"
    [[ -f "$dir/requirements.txt" ]] && echo "python"
    [[ -f "$dir/Gemfile" ]] && echo "ruby"
    [[ -f "$dir/pom.xml" ]] && echo "java-maven"
    [[ -f "$dir/build.gradle" ]] && echo "java-gradle"
    [[ -f "$dir/*.sln" ]] && echo "dotnet"
    [[ -d "$dir/.git" ]] && echo "git-repo"
}
```

**Orphan Detection:**

```yaml
orphan_patterns:
  system:
    - ".DS_Store"
    - "Thumbs.db"
    - "desktop.ini"
    - "*.lnk"

  editor:
    - "*.swp"
    - "*.swo"
    - "*~"
    - ".*.un~"

  build:
    - "node_modules"        # If no package.json in parent
    - "__pycache__"         # If no .py files in parent
    - ".pytest_cache"
    - ".mypy_cache"
```

---

### Feature 5: Directory Analysis (`lib/scanners/directory_analysis.sh`)

**Output Structure:**

```json
{
  "scan_type": "directory_analysis",
  "root": "/path/to/scan",
  "tree": {
    "name": "root",
    "size": 10737418240,
    "file_count": 1500,
    "dir_count": 120,
    "children": [
      {
        "name": "node_modules",
        "size": 524288000,
        "percentage": 4.9,
        "is_bloated": true,
        "bloat_reason": "dev_dependency"
      }
    ]
  },
  "bloated_dirs": [
    {
      "path": "/path/to/node_modules",
      "size": 524288000,
      "reason": "Build artifacts"
    }
  ]
}
```

**Visualization:**

```
External tools for visualization:
├── dust          # Tree view with bars
├── ncdu          # Interactive TUI
├── gdu           # Fast Go alternative
└── Custom JSON → ASCII tree renderer
```

---

### Feature 6: Cleanup Presets (`lib/presets/`)

**Preset System:**

```yaml
# config/rules/presets/dev.yaml
name: "Developer Cleanup"
description: "Remove build artifacts and dependencies"

targets:
  - name: "Node.js"
    patterns: ["node_modules", "package-lock.json.bak"]
    marker: "package.json"
    safe_to_delete: true

  - name: "Python"
    patterns: ["__pycache__", "*.pyc", ".pytest_cache", ".mypy_cache", ".tox", "*.egg-info", "dist", "build"]
    marker: "setup.py|pyproject.toml|requirements.txt"
    safe_to_delete: true

  - name: "Rust"
    patterns: ["target"]
    marker: "Cargo.toml"
    safe_to_delete: true

  - name: "Go"
    patterns: ["vendor"]  # Only if go.mod exists
    marker: "go.mod"
    safe_to_delete: false  # Requires confirmation

  - name: "IDE"
    patterns: [".idea", ".vscode/settings.json.bak", "*.iml"]
    safe_to_delete: true

exclusions:
  - ".git"
  - ".gitignore"
  - "README*"
```

---

### Feature 7: Safe Operations (`lib/actions/` + `lib/undo/`)

**Operation Pipeline:**

```
┌─────────────────────────────────────────────────────────────┐
│                    Safe Operation Pipeline                   │
├─────────────────────────────────────────────────────────────┤
│  1. Pre-flight Checks                                        │
│     ├── Validate paths exist                                 │
│     ├── Check permissions                                    │
│     ├── Verify disk space (for moves/copies)                 │
│     └── Detect protected paths                               │
├─────────────────────────────────────────────────────────────┤
│  2. Dry Run (if enabled)                                     │
│     ├── Simulate all operations                              │
│     ├── Report what would happen                             │
│     └── Exit without changes                                 │
├─────────────────────────────────────────────────────────────┤
│  3. Journal Entry                                            │
│     ├── Record operation details                             │
│     ├── Store file metadata for restore                      │
│     └── Generate undo command                                │
├─────────────────────────────────────────────────────────────┤
│  4. Execute Operation                                        │
│     ├── Perform action (delete/move/rename)                  │
│     ├── Use trash for deletes                                │
│     └── Verify success                                       │
├─────────────────────────────────────────────────────────────┤
│  5. Post-Operation                                           │
│     ├── Update journal with result                           │
│     ├── Log action                                           │
│     └── Emit event for hooks                                 │
└─────────────────────────────────────────────────────────────┘
```

**Undo System:**

```bash
# Undo last operation
declutter undo

# Undo specific operation by ID
declutter undo --id abc123

# List recent operations
declutter history

# Undo all operations from a session
declutter undo --session 2024-01-15T10:30:00Z
```

---

### Feature 8: Organization Rules (`lib/actions/organize.sh`)

**Rule Engine:**

```yaml
# config/rules/organize.yaml
rules:
  # Pattern-based rules
  - name: "Screenshots to folder"
    match:
      pattern: "Screenshot*.png"
      location: "~/Desktop"
    action:
      type: move
      destination: "~/Pictures/Screenshots"
      rename: "{date}_{original}"

  # Extension-based rules
  - name: "PDFs to Documents"
    match:
      extensions: ["pdf"]
      location: "~/Downloads"
      age_days: 1  # Only files older than 1 day
    action:
      type: move
      destination: "~/Documents/PDFs/{year}/{month}"

  # Size-based rules
  - name: "Large videos to external"
    match:
      extensions: ["mp4", "mkv", "avi"]
      min_size: "1GB"
    action:
      type: move
      destination: "/Volumes/External/Videos"

  # Flatten nested folders
  - name: "Flatten downloads subfolders"
    match:
      type: directory
      location: "~/Downloads"
      max_depth: 3
      empty_after_move: true
    action:
      type: flatten
      destination: "~/Downloads"
      delete_empty_dirs: true
```

**Rename Patterns:**

```yaml
rename_templates:
  variables:
    - "{original}"      # Original filename
    - "{ext}"           # Extension
    - "{date}"          # YYYY-MM-DD
    - "{datetime}"      # YYYY-MM-DD_HH-MM-SS
    - "{year}"          # YYYY
    - "{month}"         # MM
    - "{day}"           # DD
    - "{counter}"       # Auto-increment
    - "{hash:8}"        # First 8 chars of hash

  examples:
    - pattern: "{date}_{original}"
      input: "photo.jpg"
      output: "2024-01-15_photo.jpg"

    - pattern: "{year}/{month}/{original}"
      input: "report.pdf"
      output: "2024/01/report.pdf"
```

---

## Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                        User Input                            │
│  CLI Command / Config File / Interactive Prompt              │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                      Configuration                           │
│  Load & merge: defaults → user → project → CLI args         │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                        Scanners                              │
│  Parallel execution of enabled scanners                      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐        │
│  │Duplicates│ │Large File│ │Old Files │ │Categorize│        │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘        │
└───────┼────────────┼────────────┼────────────┼──────────────┘
        │            │            │            │
        └────────────┴────────────┴────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                      Result Cache                            │
│  Store scan results as JSON for review/reuse                 │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                   Interactive Review                         │
│  fzf-based selection / automatic rules / confirmation        │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                       Dry Run?                               │
│              ┌────Yes────┐    └────No────┐                   │
│              ▼                           ▼                   │
│     Report & Exit              Continue to Actions           │
└────────────────────────────────────┬────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────┐
│                        Journal                               │
│  Record operation for undo capability                        │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                        Actions                               │
│  ┌──────┐ ┌──────┐ ┌────────┐ ┌──────┐ ┌────────┐           │
│  │Delete│ │ Move │ │Compress│ │Rename│ │Organize│           │
│  └──────┘ └──────┘ └────────┘ └──────┘ └────────┘           │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                        Report                                │
│  Summary of actions taken / space recovered / errors         │
└─────────────────────────────────────────────────────────────┘
```

---

## CLI Interface

```bash
# Main commands
declutter scan [type] [path]     # Run specific scanner
declutter clean [preset] [path]  # Run cleanup preset
declutter organize [path]        # Apply organization rules
declutter analyze [path]         # Directory analysis

# Scan types
declutter scan duplicates ~/Documents
declutter scan large --threshold 500MB ~/
declutter scan old --days 180 ~/Downloads
declutter scan categorize ~/Desktop
declutter scan orphans ~/Projects

# Cleanup presets
declutter clean dev ~/Projects
declutter clean system /
declutter clean media ~/Videos
declutter clean custom --rules ./my-rules.yaml

# Organization
declutter organize ~/Downloads
declutter organize --rules screenshots ~/Desktop
declutter organize --flatten ~/Downloads/extracted

# Analysis
declutter analyze ~/
declutter analyze --format json ~/Projects > report.json
declutter analyze --interactive ~/  # ncdu-like TUI

# History & Undo
declutter history
declutter history --since "1 week ago"
declutter undo
declutter undo --id abc123
declutter undo --all --session latest

# Configuration
declutter config show
declutter config edit
declutter config validate

# Global options
--dry-run, -n       # Preview without changes
--yes, -y           # Skip confirmations
--verbose, -v       # Detailed output
--quiet, -q         # Minimal output
--json              # JSON output
--config FILE       # Use custom config
--no-journal        # Skip journaling (dangerous)
```

---

## Implementation Phases

### Phase 1: Core Foundation
- [ ] Modular directory structure
- [ ] Configuration system (YAML loading, merging)
- [ ] Logger with levels and file output
- [ ] Basic CLI argument parsing
- [ ] Journal system for undo

### Phase 2: Scanners
- [ ] Refactor existing duplicate scanner
- [ ] Refactor large file scanner
- [ ] Refactor old file scanner
- [ ] Add categorization scanner
- [ ] Add directory analysis scanner
- [ ] Add orphan detection

### Phase 3: Actions
- [ ] Refactor delete action (trash integration)
- [ ] Add move action with journaling
- [ ] Add compress action
- [ ] Add rename action with patterns
- [ ] Add organize action with rules

### Phase 4: Presets & Rules
- [ ] Implement preset system
- [ ] Dev cleanup preset
- [ ] System cleanup preset
- [ ] Organization rule engine
- [ ] Custom rule support

### Phase 5: UX Enhancements
- [ ] Interactive TUI (directory analysis)
- [ ] Progress bars for long operations
- [ ] Colored, formatted output
- [ ] Report generation (HTML, JSON)

### Phase 6: Advanced Features
- [ ] Watch mode (real-time organization)
- [ ] Scheduled cleanup (cron integration)
- [ ] Cloud storage awareness (Dropbox, iCloud)
- [ ] Plugin system for custom scanners

---

## External Dependencies

| Tool | Purpose | Required |
|------|---------|----------|
| `czkawka_cli` | Duplicate/image scanning | Yes |
| `jq` | JSON processing | Yes |
| `fd` | Fast file finding | Recommended |
| `fzf` | Interactive selection | Recommended |
| `trash` | Safe deletion | Recommended |
| `dust` | Disk visualization | Optional |
| `yq` | YAML processing | Optional |
| `xxhash` | Fast hashing | Optional |

---

## Testing Strategy

```
tests/
├── unit/
│   ├── test_config.sh          # Config loading/merging
│   ├── test_logger.sh          # Logging functions
│   ├── test_journal.sh         # Journal read/write
│   └── test_utils.sh           # Utility functions
├── integration/
│   ├── test_scan_duplicates.sh
│   ├── test_scan_large.sh
│   ├── test_action_delete.sh
│   ├── test_action_move.sh
│   ├── test_undo.sh
│   └── test_presets.sh
└── fixtures/
    ├── sample_config.yaml
    ├── sample_files/           # Test file structure
    └── expected_outputs/       # Expected JSON outputs
```

**Testing approach:**
1. Unit tests for pure functions
2. Integration tests with fixture directories
3. Snapshot testing for JSON outputs
4. Manual testing checklist for interactive features

---

## Security Considerations

1. **Path Validation** — Prevent traversal attacks, validate all paths
2. **Protected Paths** — Never operate on `/`, `/etc`, `/usr`, etc.
3. **Privilege Escalation** — Never request sudo unless explicitly needed
4. **Sensitive Files** — Warn before deleting SSH keys, credentials, etc.
5. **Symlink Safety** — Don't follow symlinks outside target directory
6. **Race Conditions** — Check file existence immediately before operations
