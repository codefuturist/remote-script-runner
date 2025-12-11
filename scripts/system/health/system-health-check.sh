#!/bin/bash
# =============================================================================
# @id           health
# @name         system-health-check
# @displayName  System Health Check
# @description  Check system health: CPU, memory, disk usage, network status
# @category     monitoring
# @version      1.0.0
# @author       codefuturist
# @tags         health,monitoring,cpu,memory,disk,network,system
# @shells       bash,zsh,sh,fish
# =============================================================================

# This script can be run remotely with curl and accepts multiple arguments
# Example: /bin/bash -c "$(curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/bash/system-health-check.sh)" -- -v -s cpu memory disk -t 5

set -euo pipefail

# =============================================================================
# Load RSR Library
# =============================================================================

# Handle both local execution and piped execution
if [ -n "${BASH_SOURCE[0]:-}" ] && [ "${BASH_SOURCE[0]}" != "bash" ] && [ "${BASH_SOURCE[0]}" != "sh" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
else
    SCRIPT_DIR=""
fi

RSR_LIB_DIR="${SCRIPT_DIR}/../../../lib"

# Load the RSR library (core only for this script) - skip if piped execution
if [[ -n "$SCRIPT_DIR" ]] && [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    source "$RSR_LIB_DIR/rsr-lib.sh" validate
    # Also try to load interactive if available
    [[ -n "${BASH_VERSION:-}" ]] && source "$RSR_LIB_DIR/rsr-lib.sh" interactive 2>/dev/null || true
else
    # Fallback: define minimal functions if library not available
    rsr_log_info() { echo -e "\033[0;34m▸\033[0m $*"; }
    rsr_log_ok() { echo -e "\033[0;32m✓\033[0m $*"; }
    rsr_log_warn() { echo -e "\033[1;33m⚠\033[0m $*"; }
    rsr_log_error() { echo -e "\033[0;31m✗\033[0m $*" >&2; }
fi

# Script metadata
SCRIPT_NAME="System Health Check"
SCRIPT_VERSION="1.0.0"
SCRIPT_URL="https://github.com/codefuturist/remote-script-runner"

# Default values
VERBOSE=false
INTERACTIVE=auto
TIMEOUT=10
CHECKS=()
LOG_FILE=""
OUTPUT_FORMAT="text"

# Color codes (from RSR library or fallback)
RED="${RSR_COLOR_RED:-\033[0;31m}"
GREEN="${RSR_COLOR_GREEN:-\033[0;32m}"
YELLOW="${RSR_COLOR_YELLOW:-\033[1;33m}"
BLUE="${RSR_COLOR_BLUE:-\033[0;34m}"
NC="${RSR_COLOR_RESET:-\033[0m}"

# Function to display usage
usage() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

Usage: $0 [OPTIONS] [CHECKS...]

OPTIONS:
    -h, --help              Display this help message
    -v, --verbose           Enable verbose output
    -i, --interactive       Run in interactive mode (default when no args)
    --no-interactive        Disable interactive mode
    -t, --timeout SECONDS   Set timeout for each check (default: 10)
    -l, --log FILE         Log output to file
    -f, --format FORMAT    Output format: text, json, csv (default: text)
    -s, --select CHECKS    Select specific checks (can be used multiple times)
    -a, --all              Run all available checks

AVAILABLE CHECKS:
    cpu         CPU usage and load average
    memory      Memory usage statistics
    disk        Disk usage for all mounted filesystems
    network     Network interface statistics
    services    Check status of common services
    uptime      System uptime information

EXAMPLES:
    # Run specific checks with verbose output
    $0 -v -s cpu -s memory -s disk

    # Run all checks with 5 second timeout
    $0 -a -t 5

    # Log output to file in JSON format
    $0 -l /var/log/health-check.log -f json -a

EOF
}

# Function to log messages
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$message\"}"
    else
        case "$level" in
            "INFO") echo -e "${BLUE}[INFO]${NC} $message" ;;
            "WARN") echo -e "${YELLOW}[WARN]${NC} $message" ;;
            "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
            "OK") echo -e "${GREEN}[OK]${NC} $message" ;;
            *) echo "[$level] $message" ;;
        esac
    fi

    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
}

# Function to check CPU usage
check_cpu() {
    log "INFO" "Checking CPU usage..."

    if command -v top > /dev/null 2>&1; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            local cpu_usage=$(top -l 1 -n 0 | grep "CPU usage" | awk '{print $3}' | sed 's/%//')
            local load_avg=$(uptime | awk -F'load averages:' '{print $2}')
        else
            # Linux
            local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
            local load_avg=$(uptime | awk -F'load average:' '{print $2}')
        fi

        log "OK" "CPU Usage: ${cpu_usage}%"
        log "OK" "Load Average:$load_avg"

        if [[ "$VERBOSE" == true ]]; then
            log "INFO" "CPU Cores: $(sysctl -n hw.ncpu 2> /dev/null || nproc 2> /dev/null || echo 'unknown')"
        fi
    else
        log "ERROR" "Unable to check CPU usage - 'top' command not found"
    fi
}

# Function to check memory usage
check_memory() {
    log "INFO" "Checking memory usage..."

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        local total=$(sysctl -n hw.memsize | awk '{print $1/1024/1024/1024}')
        local vm_stat=$(vm_stat)
        local free=$(echo "$vm_stat" | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        local active=$(echo "$vm_stat" | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
        local inactive=$(echo "$vm_stat" | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')
        local speculative=$(echo "$vm_stat" | grep "Pages speculative" | awk '{print $3}' | sed 's/\.//')
        local wired=$(echo "$vm_stat" | grep "Pages wired" | awk '{print $3}' | sed 's/\.//')

        local page_size=4096
        local free_gb=$(echo "scale=2; ($free * $page_size) / 1024 / 1024 / 1024" | bc)
        local used_gb=$(echo "scale=2; $total - $free_gb" | bc)

        log "OK" "Memory: ${used_gb}GB used / ${total}GB total"
    else
        # Linux
        local mem_info=$(free -h | grep "^Mem:")
        local total=$(echo "$mem_info" | awk '{print $2}')
        local used=$(echo "$mem_info" | awk '{print $3}')
        local free=$(echo "$mem_info" | awk '{print $4}')

        log "OK" "Memory: $used used / $total total ($free free)"
    fi
}

# Function to check disk usage
check_disk() {
    log "INFO" "Checking disk usage..."

    df -h | grep -v "Filesystem" | while read -r line; do
        local filesystem=$(echo "$line" | awk '{print $1}')
        local size=$(echo "$line" | awk '{print $2}')
        local used=$(echo "$line" | awk '{print $3}')
        local avail=$(echo "$line" | awk '{print $4}')
        local use_percent=$(echo "$line" | awk '{print $5}')
        local mount=$(echo "$line" | awk '{print $6}')

        # Skip certain filesystems
        if [[ "$filesystem" =~ ^(tmpfs|devfs|map|shm).*$ ]]; then
            [[ "$VERBOSE" == true ]] && log "INFO" "Skipping $filesystem"
            continue
        fi

        local percent_num=$(echo "$use_percent" | sed 's/%//')
        if [[ "$percent_num" -gt 90 ]]; then
            log "WARN" "Disk $mount: $use_percent used ($used/$size)"
        else
            log "OK" "Disk $mount: $use_percent used ($used/$size)"
        fi
    done
}

# Function to check network interfaces
check_network() {
    log "INFO" "Checking network interfaces..."

    if command -v ifconfig > /dev/null 2>&1; then
        ifconfig | grep -E "^[a-zA-Z0-9]+:" | cut -d: -f1 | while read -r interface; do
            if [[ "$OSTYPE" == "darwin"* ]]; then
                local status=$(ifconfig "$interface" | grep "status:" | awk '{print $2}')
                local ip=$(ifconfig "$interface" | grep "inet " | awk '{print $2}')
            else
                local status=$(ip link show "$interface" 2> /dev/null | grep -o "state [^ ]*" | awk '{print $2}')
                local ip=$(ip addr show "$interface" 2> /dev/null | grep "inet " | awk '{print $2}')
            fi

            if [[ -n "$ip" ]]; then
                log "OK" "Interface $interface: ${status:-active} - IP: $ip"
            elif [[ "$VERBOSE" == true ]]; then
                log "INFO" "Interface $interface: ${status:-inactive} - No IP assigned"
            fi
        done
    else
        log "ERROR" "Unable to check network interfaces - 'ifconfig' command not found"
    fi
}

# Function to check common services
check_services() {
    log "INFO" "Checking common services..."

    # Define services to check based on OS
    local services=()
    if [[ "$OSTYPE" == "darwin"* ]]; then
        services=("com.apple.Spotlight" "com.apple.TimeMachine" "com.openssh.sshd")
    else
        services=("sshd" "nginx" "apache2" "mysql" "postgresql" "docker")
    fi

    for service in "${services[@]}"; do
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if launchctl list | grep -q "$service"; then
                log "OK" "Service $service is running"
            elif [[ "$VERBOSE" == true ]]; then
                log "INFO" "Service $service is not running"
            fi
        else
            if systemctl is-active "$service" > /dev/null 2>&1; then
                log "OK" "Service $service is active"
            elif systemctl list-unit-files | grep -q "^$service"; then
                log "WARN" "Service $service is installed but not active"
            elif [[ "$VERBOSE" == true ]]; then
                log "INFO" "Service $service is not installed"
            fi
        fi
    done
}

# Function to check system uptime
check_uptime() {
    log "INFO" "Checking system uptime..."

    local uptime_str=$(uptime | sed 's/^.*up //' | sed 's/, [0-9]* user.*//')
    log "OK" "System uptime: $uptime_str"

    if [[ "$VERBOSE" == true ]]; then
        log "INFO" "Boot time: $(who -b 2> /dev/null | awk '{print $3, $4}' || echo 'unknown')"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h | --help)
                usage
                exit 0
                ;;
            -v | --verbose)
                VERBOSE=true
                shift
                ;;
            -i | --interactive)
                INTERACTIVE=true
                shift
                ;;
            --no-interactive)
                INTERACTIVE=false
                shift
                ;;
            -t | --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            -l | --log)
                LOG_FILE="$2"
                shift 2
                ;;
            -f | --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -s | --select)
                CHECKS+=("$2")
                shift 2
                ;;
            -a | --all)
                CHECKS=("cpu" "memory" "disk" "network" "services" "uptime")
                shift
                ;;
            -*)
                echo "Unknown option $1"
                exit 1
                ;;
            *)
                CHECKS+=("$1")
                shift
                ;;
        esac
    done
}

# =============================================================================
# Interactive Mode
# =============================================================================

run_interactive() {
    print_interactive_header "$SCRIPT_NAME" "$SCRIPT_VERSION"

    echo ""

    # Check selection
    local check_scope
    check_scope=$(prompt_select "What would you like to check?" \
        "All checks (recommended)" \
        "Quick check (CPU, memory, disk)" \
        "Select specific checks")

    case "$check_scope" in
        "All checks (recommended)")
            CHECKS=("cpu" "memory" "disk" "network" "services" "uptime")
            ;;
        "Quick check (CPU, memory, disk)")
            CHECKS=("cpu" "memory" "disk")
            ;;
        "Select specific checks")
            echo ""
            local selected
            selected=$(prompt_multiselect "Select checks to run:" \
                "CPU usage and load" \
                "Memory statistics" \
                "Disk usage" \
                "Network interfaces" \
                "Service status" \
                "System uptime")

            CHECKS=()
            [[ "$selected" == *"CPU"* ]] && CHECKS+=("cpu")
            [[ "$selected" == *"Memory"* ]] && CHECKS+=("memory")
            [[ "$selected" == *"Disk"* ]] && CHECKS+=("disk")
            [[ "$selected" == *"Network"* ]] && CHECKS+=("network")
            [[ "$selected" == *"Service"* ]] && CHECKS+=("services")
            [[ "$selected" == *"uptime"* ]] && CHECKS+=("uptime")
            ;;
    esac

    if [[ ${#CHECKS[@]} -eq 0 ]]; then
        log "ERROR" "No checks selected"
        exit 1
    fi

    echo ""

    # Output options
    local output_choice
    output_choice=$(prompt_select "Output format:" \
        "Text (default)" \
        "JSON" \
        "Log to file")

    case "$output_choice" in
        "Text (default)") OUTPUT_FORMAT="text" ;;
        "JSON") OUTPUT_FORMAT="json" ;;
        "Log to file")
            OUTPUT_FORMAT="text"
            echo ""
            LOG_FILE=$(prompt_input "Log file path" "/var/log/health-check.log")
            ;;
    esac

    echo ""

    # Verbose option
    if prompt_yes_no "Enable verbose output?" "n"; then
        VERBOSE=true
    fi

    # Summary
    echo ""
    log "INFO" "Health check configuration:"
    echo -e "  • Checks: ${CHECKS[*]}"
    echo -e "  • Format: $OUTPUT_FORMAT"
    [[ -n "$LOG_FILE" ]] && echo -e "  • Log file: $LOG_FILE"
    [[ "$VERBOSE" == "true" ]] && echo -e "  • Verbose: enabled"
    echo ""

    if prompt_yes_no "Start health check?" "y"; then
        return 0
    else
        log "INFO" "Health check cancelled"
        exit 0
    fi
}

# Main function
main() {
    local original_args=("$@")
    parse_args "$@"

    # Determine if interactive mode should be enabled
    if [[ "$INTERACTIVE" == "auto" ]]; then
        if [[ ${#original_args[@]} -eq 0 ]] && [[ -t 0 ]] && [[ -t 1 ]]; then
            INTERACTIVE=true
        else
            INTERACTIVE=false
        fi
    fi

    # Run interactive mode if enabled
    if [[ "$INTERACTIVE" == "true" ]] && type -t rsr_is_interactive &>/dev/null && rsr_is_interactive; then
        run_interactive
    fi

    # If still no checks specified after interactive mode, show usage
    if [[ ${#CHECKS[@]} -eq 0 ]]; then
        echo "No checks specified. Use -h for help."
        echo "Quick start: $0 -a    # Run all checks"
        exit 1
    fi

    # Create log file if specified
    if [[ -n "$LOG_FILE" ]]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        touch "$LOG_FILE" || {
            log "ERROR" "Cannot create log file: $LOG_FILE"
            exit 1
        }
    fi

    # Main execution
    log "INFO" "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
    [[ "$VERBOSE" == true ]] && log "INFO" "Running on: $(uname -s) $(uname -r)"

    # Run selected checks with timeout
    for check in "${CHECKS[@]}"; do
        case "$check" in
            cpu) timeout "$TIMEOUT" bash -c "$(declare -f check_cpu log); check_cpu" || log "ERROR" "CPU check timed out" ;;
            memory) timeout "$TIMEOUT" bash -c "$(declare -f check_memory log); check_memory" || log "ERROR" "Memory check timed out" ;;
            disk) timeout "$TIMEOUT" bash -c "$(declare -f check_disk log); check_disk" || log "ERROR" "Disk check timed out" ;;
            network) timeout "$TIMEOUT" bash -c "$(declare -f check_network log); check_network" || log "ERROR" "Network check timed out" ;;
            services) timeout "$TIMEOUT" bash -c "$(declare -f check_services log); check_services" || log "ERROR" "Services check timed out" ;;
            uptime) timeout "$TIMEOUT" bash -c "$(declare -f check_uptime log); check_uptime" || log "ERROR" "Uptime check timed out" ;;
            *) log "WARN" "Unknown check: $check" ;;
        esac
    done

    log "INFO" "Health check completed"
}

main "$@"
