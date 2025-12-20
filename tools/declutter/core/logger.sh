#!/usr/bin/env bash
# ============================================================================
# Logging System
# Structured logging with levels, colors, and file output
# ============================================================================

set -euo pipefail

# Colors (only define if not already set)
[[ -z "${RED:-}" ]] && readonly RED='\033[0;31m'
[[ -z "${GREEN:-}" ]] && readonly GREEN='\033[0;32m'
[[ -z "${YELLOW:-}" ]] && readonly YELLOW='\033[1;33m'
[[ -z "${BLUE:-}" ]] && readonly BLUE='\033[0;34m'
[[ -z "${PURPLE:-}" ]] && readonly PURPLE='\033[0;35m'
[[ -z "${CYAN:-}" ]] && readonly CYAN='\033[0;36m'
[[ -z "${WHITE:-}" ]] && readonly WHITE='\033[1;37m'
[[ -z "${GRAY:-}" ]] && readonly GRAY='\033[0;90m'
[[ -z "${NC:-}" ]] && readonly NC='\033[0m'

# Log levels (only define if not already set)
[[ -z "${LOG_DEBUG:-}" ]] && readonly LOG_DEBUG=0
[[ -z "${LOG_INFO:-}" ]] && readonly LOG_INFO=1
[[ -z "${LOG_WARN:-}" ]] && readonly LOG_WARN=2
[[ -z "${LOG_ERROR:-}" ]] && readonly LOG_ERROR=3
[[ -z "${LOG_SUCCESS:-}" ]] && readonly LOG_SUCCESS=4

# Current log level (default: INFO)
LOG_LEVEL=${LOG_LEVEL:-${LOG_INFO:-1}}

# Log file path
DECLUTTER_LOG_DIR="${DECLUTTER_LOG_DIR:-$HOME/.declutter/logs}"
DECLUTTER_LOG_FILE="${DECLUTTER_LOG_FILE:-$DECLUTTER_LOG_DIR/declutter_$(date +%Y%m%d).log}"

# Ensure log directory exists
init_logging() {
    mkdir -p "$DECLUTTER_LOG_DIR"
    touch "$DECLUTTER_LOG_FILE"
}

# Internal log function
_log() {
    local level=$1
    local color=$2
    local prefix=$3
    shift 3
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Console output with color
    if [[ $level -ge $LOG_LEVEL ]]; then
        echo -e "${GRAY}[$timestamp]${NC} ${color}${prefix}${NC} $message" >&2
    fi

    # File output (always, no colors)
    echo "[$timestamp] $prefix $message" >> "$DECLUTTER_LOG_FILE"
}

# Public logging functions
log_debug() { _log $LOG_DEBUG "$GRAY" "[DEBUG]" "$@"; }
log_info()  { _log $LOG_INFO "$BLUE" "[INFO]" "$@"; }
log_warn()  { _log $LOG_WARN "$YELLOW" "[WARN]" "$@"; }
log_error() { _log $LOG_ERROR "$RED" "[ERROR]" "$@"; }
log_success() { _log $LOG_SUCCESS "$GREEN" "[OK]" "$@"; }

# Action logging (for audit trail)
log_action() {
    local action=$1
    local target=$2
    local details=${3:-""}
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local action_log="$DECLUTTER_LOG_DIR/actions_$(date +%Y%m%d).log"
    echo "[$timestamp] ACTION=$action TARGET=\"$target\" DETAILS=\"$details\"" >> "$action_log"
    log_info "Action: $action on $target"
}

# Progress indicator
show_progress() {
    local current=$1
    local total=$2
    local prefix=${3:-"Progress"}
    local percent=$((current * 100 / total))
    local bar_length=30
    local filled=$((percent * bar_length / 100))
    local empty=$((bar_length - filled))

    printf "\r${CYAN}%s${NC} [%s%s] %3d%% (%d/%d)" \
        "$prefix" \
        "$(printf '#%.0s' $(seq 1 $filled 2>/dev/null) || true)" \
        "$(printf '-%.0s' $(seq 1 $empty 2>/dev/null) || true)" \
        "$percent" "$current" "$total"
}

# Spinner for long operations
declare -a SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
SPINNER_PID=""

start_spinner() {
    local message=${1:-"Processing..."}
    (
        local i=0
        while true; do
            printf "\r${CYAN}%s${NC} %s" "${SPINNER_FRAMES[$i]}" "$message"
            i=$(( (i + 1) % ${#SPINNER_FRAMES[@]} ))
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
    disown
}

stop_spinner() {
    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
        printf "\r\033[K"
    fi
}

# Section headers
print_header() {
    local title="$1"
    local width=60
    echo ""
    echo -e "${PURPLE}$(printf '═%.0s' $(seq 1 $width))${NC}"
    echo -e "${WHITE}  $title${NC}"
    echo -e "${PURPLE}$(printf '═%.0s' $(seq 1 $width))${NC}"
    echo ""
}

print_subheader() {
    local title="$1"
    echo ""
    echo -e "${CYAN}── $title ──${NC}"
    echo ""
}

# Table formatting
print_table_row() {
    local col1="$1"
    local col2="$2"
    local col3="${3:-}"
    printf "  ${WHITE}%-40s${NC} ${GRAY}%-15s${NC} %s\n" "$col1" "$col2" "$col3"
}

export -f init_logging log_debug log_info log_warn log_error log_success
export -f log_action show_progress start_spinner stop_spinner
export -f print_header print_subheader print_table_row
export LOG_LEVEL DECLUTTER_LOG_DIR DECLUTTER_LOG_FILE
