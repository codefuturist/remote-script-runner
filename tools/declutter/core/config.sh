#!/usr/bin/env bash
# ============================================================================
# Configuration Management
# Load, save, and manage user configuration
# ============================================================================

set -euo pipefail

# Default configuration directory
DECLUTTER_CONFIG_DIR="${DECLUTTER_CONFIG_DIR:-$HOME/.declutter}"
DECLUTTER_CONFIG_FILE="${DECLUTTER_CONFIG_FILE:-$DECLUTTER_CONFIG_DIR/config.yaml}"
DECLUTTER_RULES_FILE="${DECLUTTER_RULES_FILE:-$DECLUTTER_CONFIG_DIR/rules.yaml}"

# Default configuration values
declare -A CONFIG=(
    [dry_run]="false"
    [use_trash]="true"
    [confirm_actions]="true"
    [large_file_threshold]="104857600"  # 100MB
    [old_file_days]="90"
    [log_level]="info"
    [parallel_jobs]="4"
    [exclude_hidden]="false"
    [follow_symlinks]="false"
)

# Initialize configuration
init_config() {
    mkdir -p "$DECLUTTER_CONFIG_DIR"

    if [[ ! -f "$DECLUTTER_CONFIG_FILE" ]]; then
        create_default_config
    fi

    if [[ ! -f "$DECLUTTER_RULES_FILE" ]]; then
        create_default_rules
    fi

    load_config
}

# Create default configuration file
create_default_config() {
    cat > "$DECLUTTER_CONFIG_FILE" << 'EOF'
# Declutter Configuration
# =======================

general:
  dry_run: false           # Preview changes without executing
  use_trash: true          # Move to trash instead of permanent delete
  confirm_actions: true    # Ask before destructive operations
  log_level: info          # debug, info, warn, error
  parallel_jobs: 4         # Number of parallel operations

thresholds:
  large_file_mb: 100       # Files larger than this are "large"
  old_file_days: 90        # Files older than this are "old"
  duplicate_min_size: 1024 # Min size (bytes) for duplicate detection

scan:
  exclude_hidden: false    # Skip hidden files/folders
  follow_symlinks: false   # Follow symbolic links
  exclude_patterns:
    - "*.swp"
    - "*.tmp"
    - ".git"
    - "node_modules"

paths:
  trash: "~/.declutter/trash"
  archive: "~/.declutter/archive"
  backup: "~/.declutter/backup"

czkawka:
  path: ""                 # Custom path to czkawka_cli (auto-detect if empty)
  hash_type: "Blake3"      # Blake3, XXH3, SHA256
  min_size: 1024           # Minimum file size for duplicate check
EOF
    log_info "Created default config at $DECLUTTER_CONFIG_FILE"
}

# Create default organization rules
create_default_rules() {
    cat > "$DECLUTTER_RULES_FILE" << 'EOF'
# Organization Rules
# ==================
# Define how files should be organized

categories:
  documents:
    extensions: [pdf, doc, docx, txt, rtf, odt, xls, xlsx, ppt, pptx, csv]
    target: "~/Documents/Organized"

  images:
    extensions: [jpg, jpeg, png, gif, bmp, svg, webp, ico, tiff, raw, heic]
    target: "~/Pictures/Organized"

  videos:
    extensions: [mp4, mkv, avi, mov, wmv, flv, webm, m4v]
    target: "~/Videos/Organized"

  audio:
    extensions: [mp3, wav, flac, aac, ogg, wma, m4a, opus]
    target: "~/Music/Organized"

  archives:
    extensions: [zip, tar, gz, rar, 7z, bz2, xz, tgz]
    target: "~/Downloads/Archives"

  code:
    extensions: [py, js, ts, go, rs, java, c, cpp, h, rb, php, sh, bash]
    target: "~/Code/Organized"

  data:
    extensions: [json, yaml, yml, xml, sql, db, sqlite]
    target: "~/Data/Organized"

cleanup_targets:
  dev_artifacts:
    patterns:
      - "node_modules"
      - "__pycache__"
      - ".pytest_cache"
      - "*.pyc"
      - ".tox"
      - "target"           # Rust/Java
      - "build"
      - "dist"
      - ".gradle"
      - ".maven"

  system_junk:
    patterns:
      - ".DS_Store"
      - "Thumbs.db"
      - "desktop.ini"
      - "*.bak"
      - "*.swp"
      - "*~"

  temp_files:
    patterns:
      - "*.tmp"
      - "*.temp"
      - "*.log"
      - "*.cache"

auto_organize:
  downloads:
    source: "~/Downloads"
    enabled: true
    rules:
      - match: "Screenshot*.png"
        target: "~/Pictures/Screenshots"
      - match: "*.pdf"
        target: "~/Documents/PDFs"
      - match: "*.dmg"
        target: "~/Downloads/Installers"
      - match: "*.exe"
        target: "~/Downloads/Installers"
EOF
    log_info "Created default rules at $DECLUTTER_RULES_FILE"
}

# Load configuration from file
load_config() {
    if [[ -f "$DECLUTTER_CONFIG_FILE" ]]; then
        # Parse YAML-like config (simple key: value parsing)
        while IFS=': ' read -r key value; do
            key=$(echo "$key" | tr -d ' ')
            value=$(echo "$value" | tr -d ' "'"'"'')
            if [[ -n "$key" && -n "$value" && ! "$key" =~ ^# ]]; then
                CONFIG["$key"]="$value"
            fi
        done < <(grep -E '^\s*\w+:' "$DECLUTTER_CONFIG_FILE" 2>/dev/null || true)
    fi
}

# Get configuration value
get_config() {
    local key=$1
    local default=${2:-""}
    echo "${CONFIG[$key]:-$default}"
}

# Set configuration value
set_config() {
    local key=$1
    local value=$2
    CONFIG["$key"]="$value"
}

# Check if dry run mode
is_dry_run() {
    [[ "$(get_config dry_run)" == "true" ]]
}

# Check if should use trash
use_trash() {
    [[ "$(get_config use_trash)" == "true" ]]
}

# Check if should confirm actions
should_confirm() {
    [[ "$(get_config confirm_actions)" == "true" ]]
}

export -f init_config load_config get_config set_config
export -f is_dry_run use_trash should_confirm
export DECLUTTER_CONFIG_DIR DECLUTTER_CONFIG_FILE DECLUTTER_RULES_FILE
