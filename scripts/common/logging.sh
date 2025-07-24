#!/bin/bash
# Common logging functions for shell scripts
# Can be sourced by bash/sh scripts to reduce duplication

# Color codes for output (work in both bash and sh)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    # No colors if not in terminal
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Universal log function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Handle JSON output format
    if [ "${OUTPUT_FORMAT:-text}" = "json" ]; then
        printf '{"timestamp":"%s","level":"%s","message":"%s"}\n' \
            "$timestamp" "$level" "$message"
    else
        # Color output based on level
        case "$level" in
            "INFO")  printf "${BLUE}[INFO]${NC} %s\n" "$message" ;;
            "WARN")  printf "${YELLOW}[WARN]${NC} %s\n" "$message" ;;
            "ERROR") printf "${RED}[ERROR]${NC} %s\n" "$message" ;;
            "OK")    printf "${GREEN}[OK]${NC} %s\n" "$message" ;;
            *)       printf "[%s] %s\n" "$level" "$message" ;;
        esac
    fi
    
    # Log to file if specified
    if [ -n "${LOG_FILE:-}" ]; then
        printf "[%s] [%s] %s\n" "$timestamp" "$level" "$message" >> "$LOG_FILE"
    fi
}

# Check if command exists (POSIX compatible)
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get OS type in a portable way
get_os_type() {
    case "$(uname -s)" in
        Darwin*) echo "macos" ;;
        Linux*)  echo "linux" ;;
        *)       echo "unknown" ;;
    esac
}
