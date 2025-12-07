#!/bin/sh

# System Health Check Script (POSIX sh version)
# This script can be run remotely with curl and accepts multiple arguments
# Example: curl -fsSL https://example.com/script.sh | sh -s -- -v -s cpu memory disk -t 5

set -eu

# Script metadata
SCRIPT_NAME="System Health Check"
SCRIPT_VERSION="1.0.0"
SCRIPT_URL="https://github.com/yourusername/remote-script-runner"

# Default values
VERBOSE=false
TIMEOUT=10
CHECKS=""
LOG_FILE=""
OUTPUT_FORMAT="text"

# Function to display usage
usage() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

Usage: $0 [OPTIONS] [CHECKS...]

OPTIONS:
    -h, --help              Display this help message
    -v, --verbose           Enable verbose output
    -t, --timeout SECONDS   Set timeout for each check (default: 10)
    -l, --log FILE         Log output to file
    -f, --format FORMAT    Output format: text, json (default: text)
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
    level="$1"
    message="$2"
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ "$OUTPUT_FORMAT" = "json" ]; then
        printf '{"timestamp":"%s","level":"%s","message":"%s"}\n' "$timestamp" "$level" "$message"
    else
        case "$level" in
            "INFO")  printf '\033[0;34m[INFO]\033[0m %s\n' "$message" ;;
            "WARN")  printf '\033[1;33m[WARN]\033[0m %s\n' "$message" ;;
            "ERROR") printf '\033[0;31m[ERROR]\033[0m %s\n' "$message" ;;
            "OK")    printf '\033[0;32m[OK]\033[0m %s\n' "$message" ;;
            *)       printf '[%s] %s\n' "$level" "$message" ;;
        esac
    fi
    
    if [ -n "$LOG_FILE" ]; then
        printf '[%s] [%s] %s\n' "$timestamp" "$level" "$message" >> "$LOG_FILE"
    fi
}

# Function to check CPU usage
check_cpu() {
    log "INFO" "Checking CPU usage..."
    
    if command -v top >/dev/null 2>&1; then
        if [ "$(uname)" = "Darwin" ]; then
            # macOS
            cpu_usage=$(top -l 1 -n 0 | grep "CPU usage" | awk '{print $3}' | sed 's/%//')
            load_avg=$(uptime | awk -F'load averages:' '{print $2}')
        else
            # Linux/Unix
            cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
            load_avg=$(uptime | awk -F'load average:' '{print $2}')
        fi
        
        log "OK" "CPU Usage: ${cpu_usage}%"
        log "OK" "Load Average:$load_avg"
        
        if [ "$VERBOSE" = true ]; then
            ncpu=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 'unknown')
            log "INFO" "CPU Cores: $ncpu"
        fi
    else
        log "ERROR" "Unable to check CPU usage - 'top' command not found"
    fi
}

# Function to check memory usage (simplified for POSIX)
check_memory() {
    log "INFO" "Checking memory usage..."
    
    if [ "$(uname)" = "Darwin" ]; then
        # macOS
        total=$(sysctl -n hw.memsize | awk '{print int($1/1024/1024/1024)}')
        log "OK" "Total Memory: ${total}GB"
    else
        # Linux/Unix
        if [ -f /proc/meminfo ]; then
            total=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024/1024)}')
            free=$(grep MemFree /proc/meminfo | awk '{print int($2/1024/1024)}')
            used=$((total - free))
            log "OK" "Memory: ${used}GB used / ${total}GB total"
        else
            log "WARN" "Cannot read memory information"
        fi
    fi
}

# Function to check disk usage
check_disk() {
    log "INFO" "Checking disk usage..."
    
    df -h | grep -v "Filesystem" | while read -r line; do
        filesystem=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        used=$(echo "$line" | awk '{print $3}')
        avail=$(echo "$line" | awk '{print $4}')
        use_percent=$(echo "$line" | awk '{print $5}')
        mount=$(echo "$line" | awk '{print $6}')
        
        # Skip certain filesystems
        case "$filesystem" in
            tmpfs*|devfs*|map*|shm*) 
                [ "$VERBOSE" = true ] && log "INFO" "Skipping $filesystem"
                continue
                ;;
        esac
        
        percent_num=$(echo "$use_percent" | sed 's/%//')
        if [ "$percent_num" -gt 90 ]; then
            log "WARN" "Disk $mount: $use_percent used ($used/$size)"
        else
            log "OK" "Disk $mount: $use_percent used ($used/$size)"
        fi
    done
}

# Function to check network interfaces
check_network() {
    log "INFO" "Checking network interfaces..."
    
    if command -v ifconfig >/dev/null 2>&1; then
        ifconfig | grep -E "^[a-zA-Z0-9]+:" | cut -d: -f1 | while read -r interface; do
            if [ "$(uname)" = "Darwin" ]; then
                status=$(ifconfig "$interface" | grep "status:" | awk '{print $2}')
                ip=$(ifconfig "$interface" | grep "inet " | awk '{print $2}')
            else
                status="unknown"
                ip=$(ifconfig "$interface" | grep "inet " | awk '{print $2}')
            fi
            
            if [ -n "$ip" ]; then
                log "OK" "Interface $interface: ${status:-active} - IP: $ip"
            elif [ "$VERBOSE" = true ]; then
                log "INFO" "Interface $interface: ${status:-inactive} - No IP assigned"
            fi
        done
    else
        log "ERROR" "Unable to check network interfaces - 'ifconfig' command not found"
    fi
}

# Function to check services (simplified for POSIX)
check_services() {
    log "INFO" "Checking common services..."
    
    if [ "$(uname)" = "Darwin" ]; then
        # macOS services
        for service in com.apple.Spotlight com.openssh.sshd; do
            if launchctl list | grep -q "$service"; then
                log "OK" "Service $service is running"
            elif [ "$VERBOSE" = true ]; then
                log "INFO" "Service $service is not running"
            fi
        done
    else
        # Try ps-based check for common services
        for service in sshd nginx apache2 mysql; do
            if ps aux | grep -v grep | grep -q "$service"; then
                log "OK" "Process $service is running"
            elif [ "$VERBOSE" = true ]; then
                log "INFO" "Process $service is not found"
            fi
        done
    fi
}

# Function to check system uptime
check_uptime() {
    log "INFO" "Checking system uptime..."
    
    uptime_str=$(uptime | sed 's/^.*up //' | sed 's/, [0-9]* user.*//')
    log "OK" "System uptime: $uptime_str"
    
    if [ "$VERBOSE" = true ]; then
        boot_time=$(who -b 2>/dev/null | awk '{print $3, $4}' || echo 'unknown')
        log "INFO" "Boot time: $boot_time"
    fi
}

# Parse command line arguments
while [ $# -gt 0 ]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        -f|--format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -s|--select)
            CHECKS="$CHECKS $2"
            shift 2
            ;;
        -a|--all)
            CHECKS="cpu memory disk network services uptime"
            shift
            ;;
        -*)
            echo "Unknown option $1"
            exit 1
            ;;
        *)
            CHECKS="$CHECKS $1"
            shift
            ;;
    esac
done

# If no checks specified, show usage
if [ -z "$CHECKS" ]; then
    echo "No checks specified. Use -h for help."
    echo "Quick start: $0 -a    # Run all checks"
    exit 1
fi

# Create log file if specified
if [ -n "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE" || {
        log "ERROR" "Cannot create log file: $LOG_FILE"
        exit 1
    }
fi

# Main execution
log "INFO" "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
[ "$VERBOSE" = true ] && log "INFO" "Running on: $(uname -s) $(uname -r)"

# Run selected checks
for check in $CHECKS; do
    case "$check" in
        cpu)     check_cpu ;;
        memory)  check_memory ;;
        disk)    check_disk ;;
        network) check_network ;;
        services) check_services ;;
        uptime)  check_uptime ;;
        *)       log "WARN" "Unknown check: $check" ;;
    esac
done

log "INFO" "Health check completed"
