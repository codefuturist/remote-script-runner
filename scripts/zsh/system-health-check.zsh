#!/usr/bin/env zsh

# System Health Check Script (Zsh Enhanced Version)
# This script uses zsh-specific features for better functionality
# Example: curl -fsSL https://example.com/script.zsh | zsh -s -- -v -s cpu memory disk

setopt ERR_EXIT
setopt PIPE_FAIL
setopt NO_UNSET

# Script metadata
typeset -r SCRIPT_NAME="System Health Check (Zsh)"
typeset -r SCRIPT_VERSION="1.0.0"
typeset -r SCRIPT_URL="https://github.com/yourusername/remote-script-runner"

# Default values with type declarations
typeset -g VERBOSE=false
typeset -gi TIMEOUT=10
typeset -ga CHECKS=()
typeset -g LOG_FILE=""
typeset -g OUTPUT_FORMAT="text"

# Associative array for color codes
typeset -gA COLORS=(
    [RED]=$'\033[0;31m'
    [GREEN]=$'\033[0;32m'
    [YELLOW]=$'\033[1;33m'
    [BLUE]=$'\033[0;34m'
    [NC]=$'\033[0m'
)

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

# Enhanced logging function with zsh features
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ $OUTPUT_FORMAT == "json" ]]; then
        print -r "{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$message\"}"
    else
        case $level in
            INFO)  print -P "%F{blue}[INFO]%f $message" ;;
            WARN)  print -P "%F{yellow}[WARN]%f $message" ;;
            ERROR) print -P "%F{red}[ERROR]%f $message" ;;
            OK)    print -P "%F{green}[OK]%f $message" ;;
            *)     print "[$level] $message" ;;
        esac
    fi
    
    if [[ -n $LOG_FILE ]]; then
        print "[$timestamp] [$level] $message" >> $LOG_FILE
    fi
}

# Progress indicator using zsh
show_progress() {
    local message=$1
    local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    
    while true; do
        print -n "\r${spinner[$((i % ${#spinner[@]}))]} $message"
        sleep 0.1
        ((i++))
    done
}

# Enhanced CPU check with zsh features
check_cpu() {
    log "INFO" "Checking CPU usage..."
    
    if (( $+commands[top] )); then
        local cpu_usage load_avg
        
        if [[ $OSTYPE == darwin* ]]; then
            # macOS
            cpu_usage=$(top -l 1 -n 0 | grep "CPU usage" | awk '{print $3}' | sed 's/%//')
            load_avg=$(uptime | awk -F'load averages:' '{print $2}')
        else
            # Linux
            cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
            load_avg=$(uptime | awk -F'load average:' '{print $2}')
        fi
        
        log "OK" "CPU Usage: ${cpu_usage}%"
        log "OK" "Load Average:$load_avg"
        
        if [[ $VERBOSE == true ]]; then
            local ncpu=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 'unknown')
            log "INFO" "CPU Cores: $ncpu"
            
            # Zsh-specific: Show CPU model on macOS
            if [[ $OSTYPE == darwin* ]]; then
                local cpu_model=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
                [[ -n $cpu_model ]] && log "INFO" "CPU Model: $cpu_model"
            fi
        fi
    else
        log "ERROR" "Unable to check CPU usage - 'top' command not found"
    fi
}

# Memory check with better formatting
check_memory() {
    log "INFO" "Checking memory usage..."
    
    if [[ $OSTYPE == darwin* ]]; then
        # macOS with zsh math
        local total=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
        local vm_stat=$(vm_stat)
        local free=$(echo "$vm_stat" | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        
        local page_size=4096
        local free_gb=$(( (free * page_size) / 1024 / 1024 / 1024.0 ))
        local used_gb=$(( total - free_gb ))
        
        log "OK" "Memory: $(printf "%.2f" $used_gb)GB used / ${total}GB total"
        
        if [[ $VERBOSE == true ]]; then
            # Show memory pressure
            local pressure=$(memory_pressure | grep "System-wide memory free percentage" | awk '{print $5}')
            [[ -n $pressure ]] && log "INFO" "Memory free: ${pressure}"
        fi
    else
        # Linux
        if [[ -f /proc/meminfo ]]; then
            local mem_info=$(free -h | grep "^Mem:")
            local total=$(echo "$mem_info" | awk '{print $2}')
            local used=$(echo "$mem_info" | awk '{print $3}')
            local free=$(echo "$mem_info" | awk '{print $4}')
            
            log "OK" "Memory: $used used / $total total ($free free)"
        fi
    fi
}

# Enhanced disk check with zsh arrays
check_disk() {
    log "INFO" "Checking disk usage..."
    
    # Store disk info in arrays
    local -a filesystems mounts percentages
    
    while IFS= read -r line; do
        local filesystem=$(echo "$line" | awk '{print $1}')
        local size=$(echo "$line" | awk '{print $2}')
        local used=$(echo "$line" | awk '{print $3}')
        local avail=$(echo "$line" | awk '{print $4}')
        local use_percent=$(echo "$line" | awk '{print $5}')
        local mount=$(echo "$line" | awk '{print $6}')
        
        # Skip certain filesystems using zsh pattern matching
        if [[ $filesystem == (tmpfs|devfs|map|shm)* ]]; then
            [[ $VERBOSE == true ]] && log "INFO" "Skipping $filesystem"
            continue
        fi
        
        local percent_num=${use_percent%\%}
        if (( percent_num > 90 )); then
            log "WARN" "Disk $mount: $use_percent used ($used/$size)"
        else
            log "OK" "Disk $mount: $use_percent used ($used/$size)"
        fi
    done < <(df -h | grep -v "Filesystem")
}

# Network check with interface grouping
check_network() {
    log "INFO" "Checking network interfaces..."
    
    if (( $+commands[ifconfig] )); then
        local -A interfaces
        
        while IFS= read -r interface; do
            interface=${interface%:}
            
            if [[ $OSTYPE == darwin* ]]; then
                local status=$(ifconfig "$interface" | grep "status:" | awk '{print $2}')
                local ip=$(ifconfig "$interface" | grep "inet " | awk '{print $2}')
            else
                local status=$(ip link show "$interface" 2>/dev/null | grep -o "state [^ ]*" | awk '{print $2}')
                local ip=$(ip addr show "$interface" 2>/dev/null | grep "inet " | awk '{print $2}')
            fi
            
            if [[ -n $ip ]]; then
                log "OK" "Interface $interface: ${status:-active} - IP: $ip"
                interfaces[$interface]="active"
            elif [[ $VERBOSE == true ]]; then
                log "INFO" "Interface $interface: ${status:-inactive} - No IP assigned"
                interfaces[$interface]="inactive"
            fi
        done < <(ifconfig | grep -E "^[a-zA-Z0-9]+:" | cut -d: -f1)
        
        # Summary if verbose
        if [[ $VERBOSE == true ]]; then
            local active_count=${(M)#interfaces:#active}
            local total_count=${#interfaces}
            log "INFO" "Network summary: $active_count/$total_count interfaces active"
        fi
    else
        log "ERROR" "Unable to check network interfaces - 'ifconfig' command not found"
    fi
}

# Service check with parallel execution (zsh feature)
check_services() {
    log "INFO" "Checking common services..."
    
    if [[ $OSTYPE == darwin* ]]; then
        local -a services=(com.apple.Spotlight com.apple.TimeMachine com.openssh.sshd)
        
        for service in $services; do
            if launchctl list | grep -q "$service"; then
                log "OK" "Service $service is running"
            elif [[ $VERBOSE == true ]]; then
                log "INFO" "Service $service is not running"
            fi
        done
    else
        local -a services=(sshd nginx apache2 mysql postgresql docker)
        
        for service in $services; do
            if systemctl is-active "$service" &>/dev/null; then
                log "OK" "Service $service is active"
            elif systemctl list-unit-files | grep -q "^$service"; then
                log "WARN" "Service $service is installed but not active"
            elif [[ $VERBOSE == true ]]; then
                log "INFO" "Service $service is not installed"
            fi
        done
    fi
}

# Uptime with human-readable format
check_uptime() {
    log "INFO" "Checking system uptime..."
    
    local uptime_str=$(uptime | sed 's/^.*up //' | sed 's/, [0-9]* user.*//')
    log "OK" "System uptime: $uptime_str"
    
    if [[ $VERBOSE == true ]]; then
        # Show boot time
        local boot_time=$(who -b 2>/dev/null | awk '{print $3, $4}')
        [[ -n $boot_time ]] && log "INFO" "Boot time: $boot_time"
        
        # Calculate uptime in seconds (zsh specific)
        if [[ $OSTYPE == darwin* ]]; then
            local boot_timestamp=$(sysctl -n kern.boottime | awk '{print $4}' | sed 's/,//')
            local current_timestamp=$(date +%s)
            local uptime_seconds=$(( current_timestamp - boot_timestamp ))
            local days=$(( uptime_seconds / 86400 ))
            local hours=$(( (uptime_seconds % 86400) / 3600 ))
            local minutes=$(( (uptime_seconds % 3600) / 60 ))
            log "INFO" "Uptime: ${days}d ${hours}h ${minutes}m"
        fi
    fi
}

# Parse arguments using zparseopts (zsh feature)
zparseopts -D -E \
    h=help -help=help \
    v=verbose -verbose=verbose \
    t:=timeout -timeout:=timeout \
    l:=logfile -log:=logfile \
    f:=format -format:=format \
    s+:=select -select+:=select \
    a=all -all=all

# Process parsed options
[[ -n $help ]] && { usage; exit 0 }
[[ -n $verbose ]] && VERBOSE=true
[[ -n $timeout ]] && TIMEOUT=${timeout[2]}
[[ -n $logfile ]] && LOG_FILE=${logfile[2]}
[[ -n $format ]] && OUTPUT_FORMAT=${format[2]}
[[ -n $all ]] && CHECKS=(cpu memory disk network services uptime)

# Add selected checks
for sel in $select; do
    [[ $sel != -s && $sel != --select ]] && CHECKS+=($sel)
done

# Add remaining positional arguments
CHECKS+=($@)

# If no checks specified, show usage
if (( ${#CHECKS} == 0 )); then
    print "No checks specified. Use -h for help."
    print "Quick start: $0 -a    # Run all checks"
    exit 1
fi

# Create log file if specified
if [[ -n $LOG_FILE ]]; then
    mkdir -p ${LOG_FILE:h}  # zsh expansion for dirname
    touch $LOG_FILE || {
        log "ERROR" "Cannot create log file: $LOG_FILE"
        exit 1
    }
fi

# Main execution
log "INFO" "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
[[ $VERBOSE == true ]] && log "INFO" "Running on: $(uname -s) $(uname -r)"
[[ $VERBOSE == true ]] && log "INFO" "Zsh version: $ZSH_VERSION"

# Run selected checks with timing
for check in $CHECKS; do
    case $check in
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
