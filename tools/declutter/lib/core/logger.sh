#!/usr/bin/env bash
#
# Declutter - Logger
# Structured logging with levels, colors, and file output
#

# Prevent multiple inclusion
[[ -n "${_DECLUTTER_LOGGER_LOADED:-}" ]] && return 0
readonly _DECLUTTER_LOGGER_LOADED=1

# =============================================================================
# Configuration
# =============================================================================

# Log levels (higher = more verbose)
declare -A LOG_LEVELS=(
    [ERROR]=0
    [WARN]=1
    [INFO]=2
    [DEBUG]=3
    [TRACE]=4
)

# Current log level (default: INFO)
DECLUTTER_LOG_LEVEL="${DECLUTTER_LOG_LEVEL:-INFO}"

# Log file path
DECLUTTER_LOG_FILE="${DECLUTTER_LOG_FILE:-}"

# Enable/disable colors
DECLUTTER_LOG_COLORS="${DECLUTTER_LOG_COLORS:-true}"

# JSON output mode
DECLUTTER_LOG_JSON="${DECLUTTER_LOG_JSON:-false}"

# =============================================================================
# Colors
# =============================================================================

if [[ "$DECLUTTER_LOG_COLORS" == "true" ]] && [[ -t 1 ]]; then
    readonly LOG_RED='\033[0;31m'
    readonly LOG_GREEN='\033[0;32m'
    readonly LOG_YELLOW='\033[0;33m'
    readonly LOG_BLUE='\033[0;34m'
    readonly LOG_MAGENTA='\033[0;35m'
    readonly LOG_CYAN='\033[0;36m'
    readonly LOG_WHITE='\033[0;37m'
    readonly LOG_BOLD='\033[1m'
    readonly LOG_DIM='\033[2m'
    readonly LOG_RESET='\033[0m'
else
    readonly LOG_RED=''
    readonly LOG_GREEN=''
    readonly LOG_YELLOW=''
    readonly LOG_BLUE=''
    readonly LOG_MAGENTA=''
    readonly LOG_CYAN=''
    readonly LOG_WHITE=''
    readonly LOG_BOLD=''
    readonly LOG_DIM=''
    readonly LOG_RESET=''
fi

# =============================================================================
# Icons
# =============================================================================

readonly ICON_ERROR="✗"
readonly ICON_WARN="⚠"
readonly ICON_INFO="ℹ"
readonly ICON_SUCCESS="✓"
readonly ICON_DEBUG="⚙"
readonly ICON_TRACE="→"
readonly ICON_STEP="▶"
readonly ICON_BULLET="•"

# =============================================================================
# Core Logging Functions
# =============================================================================

# Check if log level is enabled
_log_level_enabled() {
    local level="$1"
    local current_level="${LOG_LEVELS[$DECLUTTER_LOG_LEVEL]:-2}"
    local check_level="${LOG_LEVELS[$level]:-2}"
    ((check_level <= current_level))
}

# Format log message
_format_log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp="$(date +"%Y-%m-%d %H:%M:%S")"

    if [[ "$DECLUTTER_LOG_JSON" == "true" ]]; then
        # JSON format
        printf '{"timestamp":"%s","level":"%s","message":"%s"}\n' \
            "$timestamp" "$level" "$(echo "$message" | sed 's/"/\\"/g')"
    else
        # Human-readable format
        local color icon
        case "$level" in
            ERROR) color="$LOG_RED"; icon="$ICON_ERROR" ;;
            WARN)  color="$LOG_YELLOW"; icon="$ICON_WARN" ;;
            INFO)  color="$LOG_BLUE"; icon="$ICON_INFO" ;;
            DEBUG) color="$LOG_CYAN"; icon="$ICON_DEBUG" ;;
            TRACE) color="$LOG_DIM"; icon="$ICON_TRACE" ;;
            *)     color="$LOG_WHITE"; icon="$ICON_BULLET" ;;
        esac

        echo -e "${color}${icon}${LOG_RESET}  ${message}"
    fi
}

# Write to log file if configured
_write_log_file() {
    local level="$1"
    local message="$2"

    if [[ -n "$DECLUTTER_LOG_FILE" ]]; then
        local timestamp
        timestamp="$(date +"%Y-%m-%d %H:%M:%S")"
        echo "[$timestamp] [$level] $message" >> "$DECLUTTER_LOG_FILE"
    fi
}

# Main log function
_log() {
    local level="$1"
    shift
    local message="$*"

    if _log_level_enabled "$level"; then
        _format_log "$level" "$message"
    fi

    # Always write to file if configured (regardless of level)
    _write_log_file "$level" "$message"
}

# =============================================================================
# Public Logging Functions
# =============================================================================

log_error() {
    _log "ERROR" "$@" >&2
}

log_warn() {
    _log "WARN" "$@" >&2
}

log_info() {
    _log "INFO" "$@" >&2
}

log_debug() {
    _log "DEBUG" "$@" >&2
}

log_trace() {
    _log "TRACE" "$@" >&2
}

log_success() {
    echo -e "${LOG_GREEN}${ICON_SUCCESS}${LOG_RESET}  $*" >&2
}

log_step() {
    echo -e "${LOG_MAGENTA}${ICON_STEP}${LOG_RESET}  ${LOG_BOLD}$*${LOG_RESET}" >&2
}

# =============================================================================
# UI Helpers
# =============================================================================

print_header() {
    local title="${1:-Declutter}"
    echo -e "\n${LOG_BOLD}${LOG_BLUE}╭─────────────────────────────────────────╮${LOG_RESET}"
    printf "${LOG_BOLD}${LOG_BLUE}│${LOG_RESET}  ${LOG_BOLD}🧹 %-36s${LOG_RESET} ${LOG_BOLD}${LOG_BLUE}│${LOG_RESET}\n" "$title"
    echo -e "${LOG_BOLD}${LOG_BLUE}╰─────────────────────────────────────────╯${LOG_RESET}\n"
}

print_divider() {
    echo -e "${LOG_DIM}─────────────────────────────────────────────${LOG_RESET}"
}

print_section() {
    local title="$1"
    echo -e "\n${LOG_BOLD}${title}${LOG_RESET}"
    print_divider
}

# Print a key-value pair
print_kv() {
    local key="$1"
    local value="$2"
    local width="${3:-20}"
    printf "  ${LOG_DIM}%-${width}s${LOG_RESET} ${LOG_CYAN}%s${LOG_RESET}\n" "$key:" "$value"
}

# Print a bullet point
print_bullet() {
    echo -e "  ${LOG_BULLET} $*"
}

# Print progress
print_progress() {
    local current="$1"
    local total="$2"
    local label="${3:-Progress}"
    local width=30
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "\r  %s: [" "$label"
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%% (%d/%d)" "$percent" "$current" "$total"

    if ((current >= total)); then
        echo ""
    fi
}

# =============================================================================
# Confirmation Prompts
# =============================================================================

# Ask yes/no question
confirm() {
    local message="${1:-Continue?}"
    local default="${2:-n}"

    local prompt
    if [[ "$default" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    read -rp "$(echo -e "${LOG_YELLOW}?${LOG_RESET}  ${message} ${prompt} ")" response
    response="${response:-$default}"

    [[ "$response" =~ ^[Yy]$ ]]
}

# Ask for input with default
prompt_input() {
    local message="$1"
    local default="${2:-}"
    local result

    if [[ -n "$default" ]]; then
        read -rp "$(echo -e "${LOG_BLUE}?${LOG_RESET}  ${message} [${default}]: ")" result
        echo "${result:-$default}"
    else
        read -rp "$(echo -e "${LOG_BLUE}?${LOG_RESET}  ${message}: ")" result
        echo "$result"
    fi
}

# =============================================================================
# Log File Management
# =============================================================================

# Initialize log file
init_log_file() {
    local log_dir="${1:-$HOME/.local/share/declutter/logs}"
    local log_name="${2:-declutter_$(date +%Y%m%d_%H%M%S).log}"

    mkdir -p "$log_dir"
    DECLUTTER_LOG_FILE="${log_dir}/${log_name}"

    # Write header
    {
        echo "=========================================="
        echo "Declutter Log - $(date)"
        echo "=========================================="
        echo ""
    } >> "$DECLUTTER_LOG_FILE"

    log_debug "Log file initialized: $DECLUTTER_LOG_FILE"
}

# Get log file path
get_log_file() {
    echo "$DECLUTTER_LOG_FILE"
}

# =============================================================================
# Timing
# =============================================================================

# Start a timer (returns start time)
timer_start() {
    date +%s
}

# End timer and print duration
timer_end() {
    local start_time="$1"
    local label="${2:-Operation}"
    local end_time
    end_time="$(date +%s)"
    local duration=$((end_time - start_time))

    if ((duration >= 60)); then
        local mins=$((duration / 60))
        local secs=$((duration % 60))
        log_info "${label} completed in ${mins}m ${secs}s"
    else
        log_info "${label} completed in ${duration}s"
    fi
}
