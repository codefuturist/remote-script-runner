#!/usr/bin/env bash
# =============================================================================
# Declutter Tool - Core Library
# Cross-platform file organization and cleanup utilities
# =============================================================================

# Prevent multiple inclusion
[[ -n "${_DECLUTTER_CORE_LOADED:-}" ]] && return 0
_DECLUTTER_CORE_LOADED=1

set -euo pipefail

# Version (only set if not already defined)
DECLUTTER_VERSION="${DECLUTTER_VERSION:-1.0.0}"

# =============================================================================
# PLATFORM DETECTION
# =============================================================================

detect_platform() {
    case "$(uname -s)" in
        Darwin*)  echo "macos" ;;
        Linux*)   echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)        echo "unknown" ;;
    esac
}

PLATFORM="${PLATFORM:-$(detect_platform)}"

# =============================================================================
# PATH UTILITIES (Cross-platform)
# =============================================================================

normalize_path() {
    local path="$1"
    if [[ "$PLATFORM" == "windows" ]]; then
        echo "$path" | sed 's|\\|/|g'
    else
        echo "$path"
    fi
}

get_home_dir() {
    if [[ -n "${HOME:-}" ]]; then
        echo "$HOME"
    elif [[ -n "${USERPROFILE:-}" ]]; then
        normalize_path "$USERPROFILE"
    else
        echo "$HOME"
    fi
}

get_trash_dir() {
    local home
    home="$(get_home_dir)"

    case "$PLATFORM" in
        macos)  echo "$home/.Trash" ;;
        linux)  echo "${XDG_DATA_HOME:-$home/.local/share}/Trash/files" ;;
        windows) echo "$home/Recycle.Bin" ;;
        *)      echo "$home/.trash" ;;
    esac
}

# =============================================================================
# LOGGING SYSTEM
# =============================================================================

declare -A LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3 [FATAL]=4) 2>/dev/null || true
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FILE="${LOG_FILE:-}"
LOG_TO_CONSOLE="${LOG_TO_CONSOLE:-true}"

# Colors (disabled on Windows or non-TTY)
C_RESET="${C_RESET:-}"
if [[ -z "$C_RESET" ]]; then
    if [[ -t 1 ]] && [[ "${PLATFORM:-}" != "windows" ]]; then
        C_RESET='\033[0m'
        C_RED='\033[0;31m'
        C_GREEN='\033[0;32m'
        C_YELLOW='\033[0;33m'
        C_BLUE='\033[0;34m'
        C_CYAN='\033[0;36m'
        C_GRAY='\033[0;90m'
        C_BOLD='\033[1m'
    else
        C_RESET='' C_RED='' C_GREEN='' C_YELLOW=''
        C_BLUE='' C_CYAN='' C_GRAY='' C_BOLD=''
    fi
fi

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    local level_num="${LOG_LEVELS[$level]:-1}"
    local current_level_num="${LOG_LEVELS[$LOG_LEVEL]:-1}"

    [[ $level_num -lt $current_level_num ]] && return 0

    local color=""
    case "$level" in
        DEBUG) color="$C_GRAY" ;;
        INFO)  color="$C_BLUE" ;;
        WARN)  color="$C_YELLOW" ;;
        ERROR) color="$C_RED" ;;
        FATAL) color="$C_RED$C_BOLD" ;;
    esac

    local formatted="[$timestamp] [$level] $message"

    if [[ "$LOG_TO_CONSOLE" == "true" ]]; then
        echo -e "${color}${formatted}${C_RESET}" >&2
    fi

    if [[ -n "$LOG_FILE" ]]; then
        echo "$formatted" >> "$LOG_FILE"
    fi
}

log_debug() { log DEBUG "$@"; }
log_info()  { log INFO "$@"; }
log_warn()  { log WARN "$@"; }
log_error() { log ERROR "$@"; }
log_fatal() { log FATAL "$@"; exit 1; }

# =============================================================================
# SIZE UTILITIES
# =============================================================================

human_readable_size() {
    local bytes="$1"
    local units=("B" "KB" "MB" "GB" "TB" "PB")
    local unit=0
    local size="$bytes"

    while (( $(echo "$size >= 1024" | bc -l) )) && (( unit < ${#units[@]} - 1 )); do
        size=$(echo "scale=2; $size / 1024" | bc)
        ((unit++))
    done

    printf "%.2f %s" "$size" "${units[$unit]}"
}

parse_size() {
    local size_str="$1"
    local number unit multiplier=1

    if [[ "$size_str" =~ ^([0-9.]+)([KMGTP]?[B]?)$ ]]; then
        number="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]^^}"

        case "$unit" in
            KB|K) multiplier=1024 ;;
            MB|M) multiplier=$((1024 * 1024)) ;;
            GB|G) multiplier=$((1024 * 1024 * 1024)) ;;
            TB|T) multiplier=$((1024 * 1024 * 1024 * 1024)) ;;
            PB|P) multiplier=$((1024 * 1024 * 1024 * 1024 * 1024)) ;;
        esac

        echo "$(echo "$number * $multiplier" | bc | cut -d. -f1)"
    else
        echo "$size_str"
    fi
}

# =============================================================================
# FILE OPERATIONS (Safe)
# =============================================================================

# Global dry-run mode
DRY_RUN="${DRY_RUN:-false}"

safe_delete() {
    local file="$1"
    local use_trash="${2:-true}"

    if [[ ! -e "$file" ]]; then
        log_warn "File not found: $file"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would delete: $file"
        return 0
    fi

    if [[ "$use_trash" == "true" ]]; then
        move_to_trash "$file"
    else
        rm -rf "$file"
        log_info "Permanently deleted: $file"
    fi
}

move_to_trash() {
    local file="$1"
    local trash_dir
    trash_dir="$(get_trash_dir)"

    mkdir -p "$trash_dir"

    local basename
    basename="$(basename "$file")"
    local dest="$trash_dir/$basename"

    # Handle name collisions
    local counter=1
    while [[ -e "$dest" ]]; do
        local name="${basename%.*}"
        local ext="${basename##*.}"
        if [[ "$name" == "$ext" ]]; then
            dest="$trash_dir/${name}_${counter}"
        else
            dest="$trash_dir/${name}_${counter}.${ext}"
        fi
        ((counter++))
    done

    mv "$file" "$dest"
    log_info "Moved to trash: $file -> $dest"
}

safe_move() {
    local src="$1"
    local dest="$2"

    if [[ ! -e "$src" ]]; then
        log_error "Source not found: $src"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would move: $src -> $dest"
        return 0
    fi

    local dest_dir
    dest_dir="$(dirname "$dest")"
    mkdir -p "$dest_dir"

    mv "$src" "$dest"
    log_info "Moved: $src -> $dest"
}

safe_copy() {
    local src="$1"
    local dest="$2"

    if [[ ! -e "$src" ]]; then
        log_error "Source not found: $src"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would copy: $src -> $dest"
        return 0
    fi

    local dest_dir
    dest_dir="$(dirname "$dest")"
    mkdir -p "$dest_dir"

    cp -r "$src" "$dest"
    log_info "Copied: $src -> $dest"
}

# =============================================================================
# HASH UTILITIES
# =============================================================================

get_file_hash() {
    local file="$1"
    local algorithm="${2:-sha256}"

    case "$algorithm" in
        md5)
            if command -v md5sum &>/dev/null; then
                md5sum "$file" | cut -d' ' -f1
            elif command -v md5 &>/dev/null; then
                md5 -q "$file"
            fi
            ;;
        sha256)
            if command -v sha256sum &>/dev/null; then
                sha256sum "$file" | cut -d' ' -f1
            elif command -v shasum &>/dev/null; then
                shasum -a 256 "$file" | cut -d' ' -f1
            fi
            ;;
        xxhash)
            if command -v xxhsum &>/dev/null; then
                xxhsum "$file" | cut -d' ' -f1
            else
                get_file_hash "$file" "sha256"
            fi
            ;;
    esac
}

# =============================================================================
# DEPENDENCY CHECKING
# =============================================================================

check_command() {
    local cmd="$1"
    command -v "$cmd" &>/dev/null
}

require_command() {
    local cmd="$1"
    local install_hint="${2:-}"

    if ! check_command "$cmd"; then
        log_error "Required command not found: $cmd"
        [[ -n "$install_hint" ]] && log_info "Install hint: $install_hint"
        return 1
    fi
}

check_czkawka() {
    if check_command "czkawka_cli"; then
        echo "czkawka_cli"
    elif check_command "czkawka"; then
        echo "czkawka"
    else
        echo ""
    fi
}

# =============================================================================
# CONFIGURATION
# =============================================================================

declare -A CONFIG

load_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        log_warn "Config file not found: $config_file"
        return 1
    fi

    while IFS='=' read -r key value; do
        [[ "$key" =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs | sed 's/^["'\'']//;s/["'\'']$//')
        CONFIG["$key"]="$value"
    done < "$config_file"
}

get_config() {
    local key="$1"
    local default="${2:-}"
    echo "${CONFIG[$key]:-$default}"
}

# =============================================================================
# PROGRESS INDICATOR
# =============================================================================

show_progress() {
    local current="$1"
    local total="$2"
    local label="${3:-Processing}"
    local width=40

    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "\r${C_CYAN}%s${C_RESET} [" "$label"
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%% (%d/%d)" "$percent" "$current" "$total"

    if [[ $current -eq $total ]]; then
        echo
    fi
}

# =============================================================================
# INTERACTIVE PROMPTS
# =============================================================================

confirm() {
    local message="$1"
    local default="${2:-n}"

    local prompt
    if [[ "$default" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    read -rp "${message} ${prompt}: " response
    response="${response:-$default}"

    [[ "${response,,}" == "y" || "${response,,}" == "yes" ]]
}

select_option() {
    local prompt="$1"
    shift
    local options=("$@")

    echo "$prompt"
    local i=1
    for opt in "${options[@]}"; do
        echo "  $i) $opt"
        ((i++))
    done

    local selection
    read -rp "Selection [1-${#options[@]}]: " selection

    if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#options[@]} )); then
        echo "${options[$((selection - 1))]}"
        return 0
    else
        return 1
    fi
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f detect_platform normalize_path get_home_dir get_trash_dir
export -f log log_debug log_info log_warn log_error log_fatal
export -f human_readable_size parse_size
export -f safe_delete move_to_trash safe_move safe_copy
export -f get_file_hash check_command require_command check_czkawka
export -f load_config get_config show_progress confirm select_option
