#!/usr/bin/env bash
#
# Declutter - Configuration System
# Hierarchical configuration loading and management
#

# Prevent multiple inclusion
[[ -n "${_DECLUTTER_CONFIG_LOADED:-}" ]] && return 0
readonly _DECLUTTER_CONFIG_LOADED=1

# =============================================================================
# Configuration Paths
# =============================================================================

# Default configuration locations (in priority order, lowest to highest)
DECLUTTER_CONFIG_SYSTEM="/etc/declutter/config.yaml"
DECLUTTER_CONFIG_USER="${XDG_CONFIG_HOME:-$HOME/.config}/declutter/config.yaml"
DECLUTTER_CONFIG_PROJECT=".declutter.yaml"
DECLUTTER_CONFIG_CUSTOM="${DECLUTTER_CONFIG:-}"

# Data directories
DECLUTTER_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/declutter"
DECLUTTER_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/declutter"

# =============================================================================
# Default Configuration
# =============================================================================

# Store configuration as associative arrays
declare -A CONFIG_GLOBAL=(
    [dry_run]="false"
    [interactive]="true"
    [trash_enabled]="true"
    [journal_enabled]="true"
    [log_level]="INFO"
    [parallel]="true"
)

declare -A CONFIG_SCANNERS=(
    [duplicates_enabled]="true"
    [duplicates_hash_algorithm]="md5"
    [duplicates_min_size]="1"
    [duplicates_include_hidden]="false"
    [large_files_enabled]="true"
    [large_files_threshold]="104857600"
    [large_files_sort_by]="size"
    [old_files_enabled]="true"
    [old_files_age_days]="90"
    [old_files_use_atime]="true"
    [categorization_enabled]="true"
    [orphans_enabled]="true"
)

declare -A CONFIG_ACTIONS=(
    [delete_use_trash]="true"
    [delete_confirm_threshold]="10"
    [move_create_dirs]="true"
    [move_overwrite]="false"
    [compress_format]="gzip"
    [compress_level]="6"
)

# Category definitions
declare -A FILE_CATEGORIES=(
    [documents]="pdf,doc,docx,txt,md,rtf,odt,pages,tex,epub"
    [images]="jpg,jpeg,png,gif,webp,svg,bmp,tiff,ico,heic,raw"
    [videos]="mp4,mkv,avi,mov,wmv,flv,webm,m4v"
    [audio]="mp3,flac,wav,aac,ogg,m4a,wma"
    [code]="js,ts,py,go,rs,java,c,cpp,h,rb,php,swift"
    [archives]="zip,tar,gz,bz2,xz,7z,rar"
    [data]="json,yaml,yml,xml,csv,sql,toml"
)

# Ignore patterns
declare -a IGNORE_PATHS=(
    ".git"
    ".svn"
    ".hg"
    "node_modules"
    "__pycache__"
    ".venv"
    "venv"
)

declare -a IGNORE_PATTERNS=(
    "*.swp"
    "*.swo"
    "*~"
    ".DS_Store"
    "Thumbs.db"
)

# =============================================================================
# Configuration Loading
# =============================================================================

# Check if yq is available for YAML parsing
_has_yq() {
    command -v yq &>/dev/null
}

# Parse YAML file using yq
_parse_yaml() {
    local file="$1"
    local prefix="${2:-}"

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    if _has_yq; then
        yq eval '.. | select(type == "!!str" or type == "!!int" or type == "!!bool") | path | join("_")' "$file" 2>/dev/null
    else
        # Fallback: basic YAML parsing for simple key: value pairs
        grep -E "^[a-zA-Z_][a-zA-Z0-9_]*:" "$file" 2>/dev/null | while read -r line; do
            local key="${line%%:*}"
            local value="${line#*:}"
            value="$(echo "$value" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"
            echo "${prefix}${key}=${value}"
        done
    fi
}

# Load configuration from YAML file
load_config_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    log_debug "Loading config from: $file"

    if _has_yq; then
        # Use yq for proper YAML parsing

        # Global settings
        local val
        val="$(yq eval '.global.dry_run // ""' "$file" 2>/dev/null)"
        [[ -n "$val" && "$val" != "null" ]] && CONFIG_GLOBAL[dry_run]="$val"

        val="$(yq eval '.global.interactive // ""' "$file" 2>/dev/null)"
        [[ -n "$val" && "$val" != "null" ]] && CONFIG_GLOBAL[interactive]="$val"

        val="$(yq eval '.global.trash_enabled // ""' "$file" 2>/dev/null)"
        [[ -n "$val" && "$val" != "null" ]] && CONFIG_GLOBAL[trash_enabled]="$val"

        val="$(yq eval '.global.journal_enabled // ""' "$file" 2>/dev/null)"
        [[ -n "$val" && "$val" != "null" ]] && CONFIG_GLOBAL[journal_enabled]="$val"

        val="$(yq eval '.global.log_level // ""' "$file" 2>/dev/null)"
        [[ -n "$val" && "$val" != "null" ]] && CONFIG_GLOBAL[log_level]="$val"

        # Scanner settings
        val="$(yq eval '.scanners.duplicates.enabled // ""' "$file" 2>/dev/null)"
        [[ -n "$val" && "$val" != "null" ]] && CONFIG_SCANNERS[duplicates_enabled]="$val"

        val="$(yq eval '.scanners.duplicates.hash_algorithm // ""' "$file" 2>/dev/null)"
        [[ -n "$val" && "$val" != "null" ]] && CONFIG_SCANNERS[duplicates_hash_algorithm]="$val"

        val="$(yq eval '.scanners.large_files.threshold // ""' "$file" 2>/dev/null)"
        [[ -n "$val" && "$val" != "null" ]] && CONFIG_SCANNERS[large_files_threshold]="$(parse_size "$val")"

        val="$(yq eval '.scanners.old_files.age_days // ""' "$file" 2>/dev/null)"
        [[ -n "$val" && "$val" != "null" ]] && CONFIG_SCANNERS[old_files_age_days]="$val"

        # Action settings
        val="$(yq eval '.actions.delete.use_trash // ""' "$file" 2>/dev/null)"
        [[ -n "$val" && "$val" != "null" ]] && CONFIG_ACTIONS[delete_use_trash]="$val"

        val="$(yq eval '.actions.delete.confirm_threshold // ""' "$file" 2>/dev/null)"
        [[ -n "$val" && "$val" != "null" ]] && CONFIG_ACTIONS[delete_confirm_threshold]="$val"

    else
        # Simple fallback parser
        while IFS='=' read -r key value; do
            key="$(echo "$key" | tr '.' '_')"
            case "$key" in
                global_*)
                    local gkey="${key#global_}"
                    CONFIG_GLOBAL[$gkey]="$value"
                    ;;
                scanners_*)
                    local skey="${key#scanners_}"
                    CONFIG_SCANNERS[$skey]="$value"
                    ;;
                actions_*)
                    local akey="${key#actions_}"
                    CONFIG_ACTIONS[$akey]="$value"
                    ;;
            esac
        done < <(_parse_yaml "$file")
    fi

    return 0
}

# Load all configuration files in priority order
load_config() {
    # Load in order: system → user → project → custom → env → cli

    # System config
    [[ -f "$DECLUTTER_CONFIG_SYSTEM" ]] && load_config_file "$DECLUTTER_CONFIG_SYSTEM"

    # User config
    [[ -f "$DECLUTTER_CONFIG_USER" ]] && load_config_file "$DECLUTTER_CONFIG_USER"

    # Project config (look in current directory and parents)
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/$DECLUTTER_CONFIG_PROJECT" ]]; then
            load_config_file "$dir/$DECLUTTER_CONFIG_PROJECT"
            break
        fi
        dir="$(dirname "$dir")"
    done

    # Custom config file
    [[ -n "$DECLUTTER_CONFIG_CUSTOM" && -f "$DECLUTTER_CONFIG_CUSTOM" ]] && \
        load_config_file "$DECLUTTER_CONFIG_CUSTOM"

    # Environment variables override
    [[ -n "${DECLUTTER_DRY_RUN:-}" ]] && CONFIG_GLOBAL[dry_run]="$DECLUTTER_DRY_RUN"
    [[ -n "${DECLUTTER_INTERACTIVE:-}" ]] && CONFIG_GLOBAL[interactive]="$DECLUTTER_INTERACTIVE"
    [[ -n "${DECLUTTER_LOG_LEVEL:-}" ]] && CONFIG_GLOBAL[log_level]="$DECLUTTER_LOG_LEVEL"
    [[ -n "${DECLUTTER_TRASH:-}" ]] && CONFIG_GLOBAL[trash_enabled]="$DECLUTTER_TRASH"

    log_debug "Configuration loaded"
}

# =============================================================================
# Configuration Getters
# =============================================================================

# Get global config value
config_get() {
    local key="$1"
    local default="${2:-}"
    echo "${CONFIG_GLOBAL[$key]:-$default}"
}

# Get scanner config value
config_scanner() {
    local key="$1"
    local default="${2:-}"
    echo "${CONFIG_SCANNERS[$key]:-$default}"
}

# Get action config value
config_action() {
    local key="$1"
    local default="${2:-}"
    echo "${CONFIG_ACTIONS[$key]:-$default}"
}

# Check if feature is enabled
is_enabled() {
    local value="$1"
    [[ "$value" == "true" || "$value" == "1" || "$value" == "yes" ]]
}

# Check if dry run mode
is_dry_run() {
    is_enabled "${CONFIG_GLOBAL[dry_run]}"
}

# Check if interactive mode
is_interactive() {
    is_enabled "${CONFIG_GLOBAL[interactive]}"
}

# Check if trash is enabled
is_trash_enabled() {
    is_enabled "${CONFIG_GLOBAL[trash_enabled]}"
}

# Check if journal is enabled
is_journal_enabled() {
    is_enabled "${CONFIG_GLOBAL[journal_enabled]}"
}

# =============================================================================
# Configuration Setters (for CLI overrides)
# =============================================================================

config_set() {
    local key="$1"
    local value="$2"
    CONFIG_GLOBAL[$key]="$value"
}

config_set_scanner() {
    local key="$1"
    local value="$2"
    CONFIG_SCANNERS[$key]="$value"
}

config_set_action() {
    local key="$1"
    local value="$2"
    CONFIG_ACTIONS[$key]="$value"
}

# =============================================================================
# Ignore Patterns
# =============================================================================

# Check if path should be ignored
should_ignore_path() {
    local path="$1"
    local basename
    basename="$(basename "$path")"

    # Check ignore paths
    for pattern in "${IGNORE_PATHS[@]}"; do
        [[ "$basename" == "$pattern" ]] && return 0
    done

    # Check ignore patterns (glob matching)
    for pattern in "${IGNORE_PATTERNS[@]}"; do
        # shellcheck disable=SC2053
        [[ "$basename" == $pattern ]] && return 0
    done

    return 1
}

# Add path to ignore list
add_ignore_path() {
    local path="$1"
    IGNORE_PATHS+=("$path")
}

# Add pattern to ignore list
add_ignore_pattern() {
    local pattern="$1"
    IGNORE_PATTERNS+=("$pattern")
}

# =============================================================================
# Configuration Display
# =============================================================================

# Print current configuration
print_config() {
    print_section "Global Configuration"
    for key in "${!CONFIG_GLOBAL[@]}"; do
        print_kv "$key" "${CONFIG_GLOBAL[$key]}"
    done

    print_section "Scanner Configuration"
    for key in "${!CONFIG_SCANNERS[@]}"; do
        print_kv "$key" "${CONFIG_SCANNERS[$key]}"
    done

    print_section "Action Configuration"
    for key in "${!CONFIG_ACTIONS[@]}"; do
        print_kv "$key" "${CONFIG_ACTIONS[$key]}"
    done
}

# Export configuration as JSON
export_config_json() {
    echo "{"
    echo '  "global": {'
    local first=true
    for key in "${!CONFIG_GLOBAL[@]}"; do
        [[ "$first" == "true" ]] || echo ","
        printf '    "%s": "%s"' "$key" "${CONFIG_GLOBAL[$key]}"
        first=false
    done
    echo ""
    echo "  },"
    echo '  "scanners": {'
    first=true
    for key in "${!CONFIG_SCANNERS[@]}"; do
        [[ "$first" == "true" ]] || echo ","
        printf '    "%s": "%s"' "$key" "${CONFIG_SCANNERS[$key]}"
        first=false
    done
    echo ""
    echo "  },"
    echo '  "actions": {'
    first=true
    for key in "${!CONFIG_ACTIONS[@]}"; do
        [[ "$first" == "true" ]] || echo ","
        printf '    "%s": "%s"' "$key" "${CONFIG_ACTIONS[$key]}"
        first=false
    done
    echo ""
    echo "  }"
    echo "}"
}

# =============================================================================
# Directory Setup
# =============================================================================

# Ensure data directories exist
ensure_data_dirs() {
    mkdir -p "$DECLUTTER_DATA_DIR"/{journal,reports}
    mkdir -p "$DECLUTTER_CACHE_DIR"/{scans,hashes}
}

# Get data directory
get_data_dir() {
    echo "$DECLUTTER_DATA_DIR"
}

# Get cache directory
get_cache_dir() {
    echo "$DECLUTTER_CACHE_DIR"
}

# Get journal directory
get_journal_dir() {
    echo "$DECLUTTER_DATA_DIR/journal"
}

# Get reports directory
get_reports_dir() {
    echo "$DECLUTTER_DATA_DIR/reports"
}
