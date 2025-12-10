#!/usr/bin/env fish
# =============================================================================
# @id           health
# @name         system-health-check
# @displayName  System Health Check
# @description  Check system health: CPU, memory, disk usage, network status
# @category     monitoring
# @version      1.0.0
# @author       codefuturist
# @tags         health,monitoring,cpu,memory,disk,network,system
# @shells       fish
# =============================================================================

# System Health Check Script (Fish Shell Version)
# This script is written specifically for the Fish shell
# Example: curl -fsSL https://example.com/script.fish | fish

# Script metadata
set -g SCRIPT_NAME "System Health Check (Fish)"
set -g SCRIPT_VERSION "1.0.0"
set -g SCRIPT_URL "https://github.com/codefuturist/remote-script-runner"

# Default values
set -g VERBOSE false
set -g TIMEOUT 10
set -g CHECKS
set -g LOG_FILE ""
set -g OUTPUT_FORMAT "text"

# Function to display usage
function usage
    echo "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo ""
    echo "Usage: $argv[0] [OPTIONS] [CHECKS...]"
    echo ""
    echo "OPTIONS:"
    echo "    -h, --help              Display this help message"
    echo "    -v, --verbose           Enable verbose output"
    echo "    -t, --timeout SECONDS   Set timeout for each check (default: 10)"
    echo "    -l, --log FILE         Log output to file"
    echo "    -f, --format FORMAT    Output format: text, json (default: text)"
    echo "    -s, --select CHECKS    Select specific checks"
    echo "    -a, --all              Run all available checks"
    echo ""
    echo "AVAILABLE CHECKS:"
    echo "    cpu         CPU usage and load average"
    echo "    memory      Memory usage statistics"
    echo "    disk        Disk usage for all mounted filesystems"
    echo "    network     Network interface statistics"
    echo "    services    Check status of common services"
    echo "    uptime      System uptime information"
    echo ""
    echo "EXAMPLES:"
    echo "    # Run specific checks with verbose output"
    echo "    $argv[0] -v -s cpu -s memory -s disk"
    echo ""
    echo "    # Run all checks with 5 second timeout"
    echo "    $argv[0] -a -t 5"
end

# Function to log messages with Fish shell colors
function log
    set -l level $argv[1]
    set -l message $argv[2]
    set -l timestamp (date '+%Y-%m-%d %H:%M:%S')
    
    if test "$OUTPUT_FORMAT" = "json"
        echo "{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$message\"}"
    else
        switch $level
            case INFO
                set_color blue
                echo -n "[INFO]"
                set_color normal
                echo " $message"
            case WARN
                set_color yellow
                echo -n "[WARN]"
                set_color normal
                echo " $message"
            case ERROR
                set_color red
                echo -n "[ERROR]"
                set_color normal
                echo " $message"
            case OK
                set_color green
                echo -n "[OK]"
                set_color normal
                echo " $message"
            case '*'
                echo "[$level] $message"
        end
    end
    
    if test -n "$LOG_FILE"
        echo "[$timestamp] [$level] $message" >> $LOG_FILE
    end
end

# Function to check CPU usage
function check_cpu
    log INFO "Checking CPU usage..."
    
    if command -v top >/dev/null 2>&1
        if test (uname) = "Darwin"
            # macOS
            set -l cpu_usage (top -l 1 -n 0 | grep "CPU usage" | awk '{print $3}' | sed 's/%//')
            set -l load_avg (uptime | awk -F'load averages:' '{print $2}')
            
            log OK "CPU Usage: $cpu_usage%"
            log OK "Load Average:$load_avg"
        else
            # Linux
            set -l cpu_usage (top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
            set -l load_avg (uptime | awk -F'load average:' '{print $2}')
            
            log OK "CPU Usage: $cpu_usage%"
            log OK "Load Average:$load_avg"
        end
        
        if test "$VERBOSE" = "true"
            set -l ncpu (sysctl -n hw.ncpu 2>/dev/null; or nproc 2>/dev/null; or echo 'unknown')
            log INFO "CPU Cores: $ncpu"
        end
    else
        log ERROR "Unable to check CPU usage - 'top' command not found"
    end
end

# Function to check memory usage
function check_memory
    log INFO "Checking memory usage..."
    
    if test (uname) = "Darwin"
        # macOS
        set -l total (math (sysctl -n hw.memsize) / 1024 / 1024 / 1024)
        log OK "Total Memory: "$total"GB"
        
        if test "$VERBOSE" = "true"
            set -l pressure (memory_pressure | grep "System-wide memory free percentage" | awk '{print $5}')
            test -n "$pressure"; and log INFO "Memory free: $pressure"
        end
    else
        # Linux
        if test -f /proc/meminfo
            set -l total (grep MemTotal /proc/meminfo | awk '{print int($2/1024/1024)}')
            set -l free (grep MemFree /proc/meminfo | awk '{print int($2/1024/1024)}')
            set -l used (math $total - $free)
            log OK "Memory: "$used"GB used / "$total"GB total"
        else
            log WARN "Cannot read memory information"
        end
    end
end

# Function to check disk usage
function check_disk
    log INFO "Checking disk usage..."
    
    df -h | grep -v "Filesystem" | while read -l line
        set -l parts (string split -n " " $line)
        set -l filesystem $parts[1]
        set -l size $parts[2]
        set -l used $parts[3]
        set -l avail $parts[4]
        set -l use_percent $parts[5]
        set -l mount $parts[6]
        
        # Skip certain filesystems
        if string match -q -r '^(tmpfs|devfs|map|shm)' $filesystem
            test "$VERBOSE" = "true"; and log INFO "Skipping $filesystem"
            continue
        end
        
        set -l percent_num (string replace '%' '' $use_percent)
        if test $percent_num -gt 90
            log WARN "Disk $mount: $use_percent used ($used/$size)"
        else
            log OK "Disk $mount: $use_percent used ($used/$size)"
        end
    end
end

# Function to check network interfaces
function check_network
    log INFO "Checking network interfaces..."
    
    if command -v ifconfig >/dev/null 2>&1
        set -l interfaces (ifconfig | grep -E "^[a-zA-Z0-9]+:" | cut -d: -f1)
        
        for interface in $interfaces
            if test (uname) = "Darwin"
                set -l status (ifconfig $interface | grep "status:" | awk '{print $2}')
                set -l ip (ifconfig $interface | grep "inet " | awk '{print $2}')
                
                if test -n "$ip"
                    log OK "Interface $interface: $status - IP: $ip"
                else if test "$VERBOSE" = "true"
                    log INFO "Interface $interface: $status - No IP assigned"
                end
            else
                set -l ip (ifconfig $interface | grep "inet " | awk '{print $2}')
                
                if test -n "$ip"
                    log OK "Interface $interface: active - IP: $ip"
                else if test "$VERBOSE" = "true"
                    log INFO "Interface $interface: inactive - No IP assigned"
                end
            end
        end
    else
        log ERROR "Unable to check network interfaces - 'ifconfig' command not found"
    end
end

# Function to check services
function check_services
    log INFO "Checking common services..."
    
    if test (uname) = "Darwin"
        # macOS services
        set -l services com.apple.Spotlight com.openssh.sshd
        
        for service in $services
            if launchctl list | grep -q $service
                log OK "Service $service is running"
            else if test "$VERBOSE" = "true"
                log INFO "Service $service is not running"
            end
        end
    else
        # Linux services
        set -l services sshd nginx apache2 mysql
        
        for service in $services
            if ps aux | grep -v grep | grep -q $service
                log OK "Process $service is running"
            else if test "$VERBOSE" = "true"
                log INFO "Process $service is not found"
            end
        end
    end
end

# Function to check system uptime
function check_uptime
    log INFO "Checking system uptime..."
    
    set -l uptime_str (uptime | sed 's/^.*up //' | sed 's/, [0-9]* user.*//')
    log OK "System uptime: $uptime_str"
    
    if test "$VERBOSE" = "true"
        set -l boot_time (who -b 2>/dev/null | awk '{print $3, $4}'; or echo 'unknown')
        log INFO "Boot time: $boot_time"
    end
end

# Parse command line arguments
set -l argv_count (count $argv)
set -l i 1

while test $i -le $argv_count
    switch $argv[$i]
        case -h --help
            usage $argv
            exit 0
        case -v --verbose
            set VERBOSE true
        case -t --timeout
            set i (math $i + 1)
            set TIMEOUT $argv[$i]
        case -l --log
            set i (math $i + 1)
            set LOG_FILE $argv[$i]
        case -f --format
            set i (math $i + 1)
            set OUTPUT_FORMAT $argv[$i]
        case -s --select
            set i (math $i + 1)
            set -a CHECKS $argv[$i]
        case -a --all
            set CHECKS cpu memory disk network services uptime
        case '*'
            # Check if it starts with dash
            if string match -q -- '-*' $argv[$i]
                echo "Unknown option $argv[$i]"
                exit 1
            else
                set -a CHECKS $argv[$i]
            end
    end
    set i (math $i + 1)
end

# If no checks specified, show usage
if test (count $CHECKS) -eq 0
    echo "No checks specified. Use -h for help."
    echo "Quick start: $argv[0] -a    # Run all checks"
    exit 1
end

# Create log file if specified
if test -n "$LOG_FILE"
    set -l log_dir (dirname $LOG_FILE)
    mkdir -p $log_dir
    touch $LOG_FILE; or begin
        log ERROR "Cannot create log file: $LOG_FILE"
        exit 1
    end
end

# Main execution
log INFO "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
test "$VERBOSE" = "true"; and log INFO "Running on: "(uname -s)" "(uname -r)
test "$VERBOSE" = "true"; and log INFO "Fish version: $FISH_VERSION"

# Run selected checks
for check in $CHECKS
    switch $check
        case cpu
            check_cpu
        case memory
            check_memory
        case disk
            check_disk
        case network
            check_network
        case services
            check_services
        case uptime
            check_uptime
        case '*'
            log WARN "Unknown check: $check"
    end
end

log INFO "Health check completed"
