#!/bin/bash
# =============================================================================
# @id           dns-sync
# @name         dns-sync
# @displayName  DNS GitOps Sync Service
# @description  Sync DNS zone files from Git to Pi-hole with validation and rollback
# @category     networking
# @version      4.0.0
# @author       codefuturist
# @tags         dns,pihole,gitops,sync,networking,zone,bind,configuration
# @shells       bash
# @requires     git,python3
# @os           linux
# @sudo         optional
# =============================================================================

# DNS GitOps Sync Service - Sync DNS zone files from Git to Pi-hole
# Supports: SSH/HTTPS git, multi-zone filtering, backup/rollback, systemd integration
#
# Usage: dns-sync [command] [options]
# Run 'dns-sync help' for full documentation

set -euo pipefail

# =============================================================================
# Constants
# =============================================================================

readonly VERSION="4.0.0"
readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/${SCRIPT_NAME}"
readonly SCRIPT_URL="https://github.com/codefuturist/remote-script-runner"

# Exit codes
readonly E_OK=0
readonly E_ERROR=1
readonly E_ARGS=2
readonly E_DEPS=3
readonly E_LOCK=4
readonly E_ROLLBACK=5

# =============================================================================
# Default Configuration
# =============================================================================

# Git settings
CFG_REPO_URL="${DNS_REPO_URL:-}"
CFG_REPO_BRANCH="${DNS_REPO_BRANCH:-main}"
CFG_REPO_PATH="${DNS_REPO_PATH:-/opt/dns-sync/repo}"
CFG_ZONES_PATH="${DNS_ZONES_PATH:-zones}"
CFG_SSH_KEY="${DNS_SSH_KEY:-}"

# Pi-hole settings
CFG_PIHOLE_TOML="${PIHOLE_TOML_PATH:-/etc/pihole/pihole.toml}"

# Paths (set by setup_paths based on privileges)
CFG_CONFIG_FILE=""
CFG_CACHE_DIR=""
CFG_LOG_FILE=""
CFG_LOCK_FILE=""
CFG_BACKUP_DIR=""
CFG_HISTORY_FILE=""
CFG_METRICS_FILE=""

# Log rotation settings
CFG_LOG_MAX_SIZE="${DNS_LOG_MAX_SIZE:-10485760}"  # 10MB default
CFG_LOG_KEEP_COUNT="${DNS_LOG_KEEP_COUNT:-5}"     # Keep 5 rotated logs
CFG_BACKUP_KEEP_COUNT="${DNS_BACKUP_KEEP_COUNT:-10}"
CFG_HISTORY_KEEP_COUNT="${DNS_HISTORY_KEEP_COUNT:-100}"

# Notification settings
CFG_NOTIFY_WEBHOOK="${DNS_NOTIFY_WEBHOOK:-}"
CFG_NOTIFY_ON_SUCCESS="${DNS_NOTIFY_ON_SUCCESS:-false}"
CFG_NOTIFY_ON_FAILURE="${DNS_NOTIFY_ON_FAILURE:-true}"

# Runtime options
OPT_VERBOSE=false
OPT_QUIET=false
OPT_DRY_RUN=false
OPT_FORCE=false
OPT_NO_RESTART=false
OPT_JSON=false
OPT_ZONES=()  # Empty = all zones

# Watch mode settings
OPT_WATCH_INTERVAL="${DNS_WATCH_INTERVAL:-60}"  # Default 60 seconds
OPT_WATCH_QUICK_INTERVAL="${DNS_QUICK_INTERVAL:-15}"  # Quick check interval

# Sync script
SYNC_SCRIPT="${SCRIPT_PATH%/*}/sync-dns-zones.py"

# =============================================================================
# Color Setup
# =============================================================================

setup_colors() {
    if [[ -t 1 ]] && [[ "${NO_COLOR:-}" != "1" ]] && [[ "$OPT_JSON" != "true" ]]; then
        C_RED='\033[0;31m'
        C_GREEN='\033[0;32m'
        C_YELLOW='\033[1;33m'
        C_BLUE='\033[0;34m'
        C_CYAN='\033[0;36m'
        C_BOLD='\033[1m'
        C_DIM='\033[2m'
        C_NC='\033[0m'
    else
        C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN='' C_BOLD='' C_DIM='' C_NC=''
    fi
}

# =============================================================================
# Logging
# =============================================================================

_log_file() {
    [[ -n "${CFG_LOG_FILE:-}" ]] && [[ -w "${CFG_LOG_FILE%/*}" || -w "$CFG_LOG_FILE" ]] && \
        echo "[$(date '+%Y-%m-%d %H:%M:%S')][$1] $2" >> "$CFG_LOG_FILE" 2>/dev/null || true
}

log_debug() {
    [[ "$OPT_VERBOSE" == "true" ]] && echo -e "${C_DIM}  $*${C_NC}"
    _log_file "DEBUG" "$*"
}
log_info()  {
    [[ "$OPT_QUIET" != "true" ]] && [[ "$OPT_JSON" != "true" ]] && echo -e "${C_BLUE}▸${C_NC} $*"
    _log_file "INFO" "$*"
}
log_ok()    {
    [[ "$OPT_QUIET" != "true" ]] && [[ "$OPT_JSON" != "true" ]] && echo -e "${C_GREEN}✓${C_NC} $*"
    _log_file "OK" "$*"
}
log_warn()  {
    [[ "$OPT_JSON" != "true" ]] && echo -e "${C_YELLOW}⚠${C_NC} $*" >&2
    _log_file "WARN" "$*"
}
log_error() {
    [[ "$OPT_JSON" != "true" ]] && echo -e "${C_RED}✗${C_NC} $*" >&2
    _log_file "ERROR" "$*"
}

print_header() {
    [[ "$OPT_QUIET" == "true" ]] || [[ "$OPT_JSON" == "true" ]] && return
    echo ""
    echo -e "${C_BOLD}${C_CYAN}═══════════════════════════════════════════════════════════${C_NC}"
    echo -e "${C_BOLD}${C_CYAN}  $1${C_NC}"
    echo -e "${C_BOLD}${C_CYAN}═══════════════════════════════════════════════════════════${C_NC}"
    echo ""
}

# =============================================================================
# JSON Output
# =============================================================================

json_output() {
    local status="$1" message="$2"
    shift 2
    local extra=""
    while [[ $# -gt 0 ]]; do
        extra+=", \"$1\": $2"
        shift 2
    done
    echo "{\"status\": \"$status\", \"message\": \"$message\", \"timestamp\": \"$(date -Iseconds)\"$extra}"
}

# =============================================================================
# Path Setup
# =============================================================================

setup_paths() {
    if [[ $EUID -eq 0 ]]; then
        CFG_CONFIG_FILE="${DNS_CONFIG_FILE:-/etc/dns-sync/config.conf}"
        CFG_CACHE_DIR="${DNS_CACHE_DIR:-/var/cache/dns-sync}"
        CFG_LOG_FILE="${DNS_LOG_FILE:-/var/log/dns-sync.log}"
        CFG_LOCK_FILE="/var/run/dns-sync.lock"
        CFG_BACKUP_DIR="${DNS_BACKUP_DIR:-/var/backups/dns-sync}"
        CFG_HISTORY_FILE="${DNS_HISTORY_FILE:-/var/lib/dns-sync/history.json}"
        CFG_METRICS_FILE="${DNS_METRICS_FILE:-/var/lib/dns-sync/metrics.prom}"
    else
        local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
        local cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
        local state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
        local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"

        CFG_CONFIG_FILE="${DNS_CONFIG_FILE:-$config_home/dns-sync/config.conf}"
        CFG_CACHE_DIR="${DNS_CACHE_DIR:-$cache_home/dns-sync}"
        CFG_LOG_FILE="${DNS_LOG_FILE:-$state_home/dns-sync/sync.log}"
        CFG_LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/dns-sync-$UID.lock"
        CFG_BACKUP_DIR="${DNS_BACKUP_DIR:-$data_home/dns-sync/backups}"
        CFG_HISTORY_FILE="${DNS_HISTORY_FILE:-$state_home/dns-sync/history.json}"
        CFG_METRICS_FILE="${DNS_METRICS_FILE:-$state_home/dns-sync/metrics.prom}"
    fi
}

# =============================================================================
# Configuration Loading
# =============================================================================

load_config() {
    local config_file="${1:-$CFG_CONFIG_FILE}"

    [[ ! -f "$config_file" ]] && return 0

    log_debug "Loading config: $config_file"

    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        # Trim whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs | sed 's/^["'"'"']//;s/["'"'"']$//')

        case "$key" in
            repo_url)           [[ -z "$CFG_REPO_URL" ]] && CFG_REPO_URL="$value" ;;
            repo_branch)        CFG_REPO_BRANCH="$value" ;;
            repo_path)          CFG_REPO_PATH="$value" ;;
            zones_path)         CFG_ZONES_PATH="$value" ;;
            ssh_key)            [[ -z "$CFG_SSH_KEY" ]] && CFG_SSH_KEY="$value" ;;
            pihole_toml)        CFG_PIHOLE_TOML="$value" ;;
            log_file)           CFG_LOG_FILE="$value" ;;
            cache_dir)          CFG_CACHE_DIR="$value" ;;
            backup_dir)         CFG_BACKUP_DIR="$value" ;;
            log_max_size)       CFG_LOG_MAX_SIZE="$value" ;;
            log_keep_count)     CFG_LOG_KEEP_COUNT="$value" ;;
            backup_keep_count)  CFG_BACKUP_KEEP_COUNT="$value" ;;
            history_keep_count) CFG_HISTORY_KEEP_COUNT="$value" ;;
            notify_webhook)     CFG_NOTIFY_WEBHOOK="$value" ;;
            notify_on_success)  CFG_NOTIFY_ON_SUCCESS="$value" ;;
            notify_on_failure)  CFG_NOTIFY_ON_FAILURE="$value" ;;
        esac
    done < "$config_file"
}

# =============================================================================
# Dependency Checking
# =============================================================================

check_deps() {
    local missing=()

    for cmd in git python3; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_info "Install: sudo apt install ${missing[*]}  # Debian/Ubuntu"
        log_info "         sudo dnf install ${missing[*]}  # RHEL/Fedora"
        return $E_DEPS
    fi

    # Warn if systemctl not available
    if [[ "$OPT_NO_RESTART" != "true" ]] && ! command -v systemctl &>/dev/null; then
        log_warn "systemctl not found - service restart will be skipped"
        OPT_NO_RESTART=true
    fi

    return 0
}

# =============================================================================
# Lock Management
# =============================================================================

acquire_lock() {
    local max_wait=60 waited=0

    while [[ -f "$CFG_LOCK_FILE" ]]; do
        local lock_pid
        lock_pid=$(cat "$CFG_LOCK_FILE" 2>/dev/null || echo "")

        # Remove stale lock from dead process
        if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
            log_warn "Removing stale lock (PID: $lock_pid)"
            rm -f "$CFG_LOCK_FILE"
            break
        fi

        if [[ $waited -ge $max_wait ]]; then
            log_error "Lock timeout after ${max_wait}s (PID: $lock_pid)"
            return $E_LOCK
        fi

        log_debug "Waiting for lock (PID: $lock_pid)..."
        sleep 2
        waited=$((waited + 2))
    done

    mkdir -p "${CFG_LOCK_FILE%/*}" 2>/dev/null || true
    echo $$ > "$CFG_LOCK_FILE"
    log_debug "Lock acquired (PID: $$)"
}

release_lock() {
    [[ -f "$CFG_LOCK_FILE" ]] && [[ "$(cat "$CFG_LOCK_FILE" 2>/dev/null)" == "$$" ]] && rm -f "$CFG_LOCK_FILE"
}

trap 'release_lock' EXIT INT TERM

# =============================================================================
# Backup & Rollback
# =============================================================================

create_backup() {
    local file="$1"
    [[ ! -f "$file" ]] && return 0

    mkdir -p "$CFG_BACKUP_DIR"
    local backup="$CFG_BACKUP_DIR/$(basename "$file").$(date +%Y%m%d_%H%M%S).bak"

    if [[ "$OPT_DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would backup: $file → $backup"
        echo "$backup"
        return 0
    fi

    cp "$file" "$backup" && echo "$backup" || return 1
    log_debug "Backup created: $backup"
}

rollback() {
    local original="$1" backup="$2"
    [[ ! -f "$backup" ]] && return 1

    if [[ "$OPT_DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would rollback: $backup → $original"
        return 0
    fi

    cp "$backup" "$original" && log_ok "Rolled back: $original"
}

cleanup_backups() {
    local keep="${1:-10}"
    [[ ! -d "$CFG_BACKUP_DIR" ]] && return 0

    local count
    count=$(find "$CFG_BACKUP_DIR" -name "*.bak" -type f 2>/dev/null | wc -l)

    if [[ $count -gt $keep ]]; then
        log_debug "Cleaning old backups (keeping $keep)"
        find "$CFG_BACKUP_DIR" -name "*.bak" -type f -printf '%T@ %p\n' 2>/dev/null | \
            sort -n | head -n -"$keep" | cut -d' ' -f2- | xargs -r rm -f
    fi
}

# =============================================================================
# Log Rotation
# =============================================================================

rotate_logs() {
    [[ ! -f "$CFG_LOG_FILE" ]] && return 0

    local size
    size=$(stat -f%z "$CFG_LOG_FILE" 2>/dev/null || stat -c%s "$CFG_LOG_FILE" 2>/dev/null || echo 0)

    if [[ $size -ge $CFG_LOG_MAX_SIZE ]]; then
        log_debug "Rotating log file (size: $size bytes)"

        # Rotate existing logs
        for i in $(seq $((CFG_LOG_KEEP_COUNT - 1)) -1 1); do
            [[ -f "${CFG_LOG_FILE}.$i" ]] && mv "${CFG_LOG_FILE}.$i" "${CFG_LOG_FILE}.$((i + 1))"
        done

        # Rotate current log
        mv "$CFG_LOG_FILE" "${CFG_LOG_FILE}.1"

        # Remove oldest if exceeds keep count
        [[ -f "${CFG_LOG_FILE}.$((CFG_LOG_KEEP_COUNT + 1))" ]] && rm -f "${CFG_LOG_FILE}.$((CFG_LOG_KEEP_COUNT + 1))"

        log_debug "Log rotated successfully"
    fi
}

# =============================================================================
# Sync History
# =============================================================================

record_history() {
    local status="$1" message="$2" zones_synced="${3:-0}" duration="${4:-0}"

    mkdir -p "$(dirname "$CFG_HISTORY_FILE")"

    local entry
    entry=$(cat <<EOF
{"timestamp": "$(date -Iseconds)", "status": "$status", "message": "$message", "zones_synced": $zones_synced, "duration_ms": $duration, "commit": "$(get_local_hash 2>/dev/null | head -c7)", "branch": "$CFG_REPO_BRANCH"}
EOF
)

    # Append to history file
    if [[ -f "$CFG_HISTORY_FILE" ]]; then
        # Read existing, add new entry, keep last N entries
        local temp_file
        temp_file=$(mktemp)
        {
            echo "$entry"
            head -n "$((CFG_HISTORY_KEEP_COUNT - 1))" "$CFG_HISTORY_FILE"
        } > "$temp_file"
        mv "$temp_file" "$CFG_HISTORY_FILE"
    else
        echo "$entry" > "$CFG_HISTORY_FILE"
    fi
}

get_history() {
    local count="${1:-10}"
    [[ ! -f "$CFG_HISTORY_FILE" ]] && return 0
    head -n "$count" "$CFG_HISTORY_FILE"
}

# =============================================================================
# Prometheus Metrics
# =============================================================================

update_metrics() {
    local status="$1" duration="${2:-0}" zones="${3:-0}"

    mkdir -p "$(dirname "$CFG_METRICS_FILE")"

    local success=0 failure=0
    [[ "$status" == "success" ]] && success=1 || failure=1

    cat > "$CFG_METRICS_FILE" <<EOF
# HELP dns_sync_last_success_timestamp Unix timestamp of last successful sync
# TYPE dns_sync_last_success_timestamp gauge
dns_sync_last_success_timestamp $(date +%s)

# HELP dns_sync_last_run_success Whether the last sync was successful (1=yes, 0=no)
# TYPE dns_sync_last_run_success gauge
dns_sync_last_run_success $success

# HELP dns_sync_last_duration_seconds Duration of last sync in seconds
# TYPE dns_sync_last_duration_seconds gauge
dns_sync_last_duration_seconds $(echo "scale=3; $duration / 1000" | bc 2>/dev/null || echo "0")

# HELP dns_sync_zones_total Total number of zones synced
# TYPE dns_sync_zones_total gauge
dns_sync_zones_total $zones

# HELP dns_sync_total Total number of sync attempts
# TYPE dns_sync_total counter
dns_sync_total{status="success"} $(grep -c '"status": "success"' "$CFG_HISTORY_FILE" 2>/dev/null || echo 0)
dns_sync_total{status="failure"} $(grep -c '"status": "failure"' "$CFG_HISTORY_FILE" 2>/dev/null || echo 0)
EOF
}

# =============================================================================
# Notifications
# =============================================================================

send_notification() {
    local status="$1" message="$2" details="${3:-}"

    [[ -z "$CFG_NOTIFY_WEBHOOK" ]] && return 0

    # Check if we should notify based on status
    if [[ "$status" == "success" ]] && [[ "$CFG_NOTIFY_ON_SUCCESS" != "true" ]]; then
        return 0
    fi
    if [[ "$status" == "failure" ]] && [[ "$CFG_NOTIFY_ON_FAILURE" != "true" ]]; then
        return 0
    fi

    local color icon
    if [[ "$status" == "success" ]]; then
        color="good"
        icon="✅"
    else
        color="danger"
        icon="❌"
    fi

    local hostname
    hostname=$(hostname -f 2>/dev/null || hostname)

    # Build JSON payload (compatible with Slack, Mattermost, Discord webhooks)
    local payload
    payload=$(cat <<EOF
{
    "text": "$icon DNS Sync: $message",
    "username": "dns-sync",
    "attachments": [{
        "color": "$color",
        "fields": [
            {"title": "Host", "value": "$hostname", "short": true},
            {"title": "Status", "value": "$status", "short": true},
            {"title": "Branch", "value": "$CFG_REPO_BRANCH", "short": true},
            {"title": "Time", "value": "$(date '+%Y-%m-%d %H:%M:%S')", "short": true}
        ],
        "text": "$details"
    }]
}
EOF
)

    # Send notification (fire and forget)
    if command -v curl &>/dev/null; then
        curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$CFG_NOTIFY_WEBHOOK" >/dev/null 2>&1 &
        log_debug "Notification sent to webhook"
    fi
}

# =============================================================================
# Diff/Preview Functions
# =============================================================================

generate_diff() {
    local zones_dir="$CFG_REPO_PATH/$CFG_ZONES_PATH"

    [[ ! -d "$zones_dir" ]] && { log_error "Zones directory not found"; return 1; }
    [[ ! -f "$CFG_PIHOLE_TOML" ]] && { log_error "Pi-hole config not found"; return 1; }

    # Create temp file for new config
    local temp_toml
    temp_toml=$(mktemp)

    # Run sync script in dry-run mode to generate what would be written
    local sync_cmd="python3 $SYNC_SCRIPT $zones_dir $temp_toml --dry-run 2>/dev/null"
    eval "$sync_cmd" || true

    # Generate diff
    if [[ -f "$temp_toml" ]] && [[ -s "$temp_toml" ]]; then
        if command -v diff &>/dev/null; then
            diff -u "$CFG_PIHOLE_TOML" "$temp_toml" 2>/dev/null || true
        fi
    else
        # Fallback: show current records count vs new
        log_info "Current Pi-hole config: $CFG_PIHOLE_TOML"
        local current_count new_count
        current_count=$(grep -c "host\s*=" "$CFG_PIHOLE_TOML" 2>/dev/null || echo 0)
        new_count=$(find "$zones_dir" -name "*.zone" -exec grep -hcE '^[^;[:space:]].*IN\s+(A|AAAA|CNAME)' {} + 2>/dev/null | awk '{s+=$1} END {print s}' || echo 0)
        log_info "Current hosts entries: $current_count"
        log_info "Zone file records: $new_count"
    fi

    rm -f "$temp_toml"
}

# =============================================================================
# Backup Management
# =============================================================================

list_backups() {
    [[ ! -d "$CFG_BACKUP_DIR" ]] && { log_warn "No backup directory found"; return 0; }

    local backups=()
    while IFS= read -r -d '' backup; do
        backups+=("$backup")
    done < <(find "$CFG_BACKUP_DIR" -name "*.bak" -type f -print0 2>/dev/null | sort -rz)

    if [[ ${#backups[@]} -eq 0 ]]; then
        log_warn "No backups found"
        return 0
    fi

    if [[ "$OPT_JSON" == "true" ]]; then
        local json_backups="["
        local first=true
        for backup in "${backups[@]}"; do
            local size timestamp name
            name=$(basename "$backup")
            size=$(stat -f%z "$backup" 2>/dev/null || stat -c%s "$backup" 2>/dev/null || echo 0)
            timestamp=$(stat -f%m "$backup" 2>/dev/null || stat -c%Y "$backup" 2>/dev/null || echo 0)
            [[ "$first" != "true" ]] && json_backups+=","
            json_backups+="{\"name\": \"$name\", \"path\": \"$backup\", \"size\": $size, \"timestamp\": $timestamp}"
            first=false
        done
        json_backups+="]"
        json_output "ok" "Found ${#backups[@]} backups" "backups" "$json_backups" "count" "${#backups[@]}"
    else
        print_header "Available Backups"
        echo "Directory: $CFG_BACKUP_DIR"
        echo ""

        local i=1
        for backup in "${backups[@]}"; do
            local name size date_str
            name=$(basename "$backup")
            size=$(stat -f%z "$backup" 2>/dev/null || stat -c%s "$backup" 2>/dev/null || echo "?")
            date_str=$(stat -f%Sm -t"%Y-%m-%d %H:%M" "$backup" 2>/dev/null || stat -c%y "$backup" 2>/dev/null | cut -d. -f1 || echo "unknown")

            # Human readable size
            local hr_size
            if [[ $size -gt 1048576 ]]; then
                hr_size="$(echo "scale=1; $size / 1048576" | bc)MB"
            elif [[ $size -gt 1024 ]]; then
                hr_size="$(echo "scale=1; $size / 1024" | bc)KB"
            else
                hr_size="${size}B"
            fi

            printf "  ${C_CYAN}%2d.${C_NC} %s ${C_DIM}(%s, %s)${C_NC}\n" "$i" "$name" "$hr_size" "$date_str"
            ((i++))
        done
        echo ""
        log_info "Total: ${#backups[@]} backup(s)"
        log_info "Restore with: dns-sync restore <number> or dns-sync restore <filename>"
    fi
}

restore_backup() {
    local target="$1"

    [[ ! -d "$CFG_BACKUP_DIR" ]] && { log_error "No backup directory found"; return 1; }

    local backup_file=""

    # Check if target is a number (index) or filename
    if [[ "$target" =~ ^[0-9]+$ ]]; then
        # It's an index, get the nth backup
        local backups=()
        while IFS= read -r -d '' backup; do
            backups+=("$backup")
        done < <(find "$CFG_BACKUP_DIR" -name "*.bak" -type f -print0 2>/dev/null | sort -rz)

        if [[ $target -lt 1 ]] || [[ $target -gt ${#backups[@]} ]]; then
            log_error "Invalid backup index: $target (have ${#backups[@]} backups)"
            return 1
        fi

        backup_file="${backups[$((target - 1))]}"
    else
        # It's a filename
        if [[ -f "$target" ]]; then
            backup_file="$target"
        elif [[ -f "$CFG_BACKUP_DIR/$target" ]]; then
            backup_file="$CFG_BACKUP_DIR/$target"
        else
            log_error "Backup not found: $target"
            return 1
        fi
    fi

    log_info "Restoring from: $(basename "$backup_file")"

    if [[ "$OPT_DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would restore: $backup_file → $CFG_PIHOLE_TOML"
        return 0
    fi

    # Create backup of current config before restore
    local pre_restore_backup
    pre_restore_backup=$(create_backup "$CFG_PIHOLE_TOML")

    # Restore
    local restore_cmd="cp '$backup_file' '$CFG_PIHOLE_TOML'"
    [[ $EUID -ne 0 ]] && restore_cmd="sudo $restore_cmd"

    if eval "$restore_cmd"; then
        log_ok "Restored: $CFG_PIHOLE_TOML"

        # Restart Pi-hole if requested
        if [[ "$OPT_NO_RESTART" != "true" ]]; then
            restart_pihole
        fi

        record_history "restore" "Restored from $(basename "$backup_file")" 0 0
        return 0
    else
        log_error "Restore failed"
        return 1
    fi
}

# =============================================================================
# Config Validation
# =============================================================================

validate_config() {
    local errors=0
    local warnings=0

    print_header "Configuration Validation"

    # Check required settings
    if [[ -z "$CFG_REPO_URL" ]]; then
        log_error "repo_url is not configured"
        ((errors++))
    else
        log_ok "repo_url: $CFG_REPO_URL"
    fi

    # Validate repo URL format
    if [[ -n "$CFG_REPO_URL" ]]; then
        if [[ "$CFG_REPO_URL" =~ ^(https?://|git@) ]]; then
            log_ok "repo_url format: valid"
        else
            log_warn "repo_url format: unusual (expected https:// or git@)"
            ((warnings++))
        fi
    fi

    # Check SSH key if specified
    if [[ -n "$CFG_SSH_KEY" ]]; then
        if [[ -f "$CFG_SSH_KEY" ]]; then
            log_ok "ssh_key: $CFG_SSH_KEY (exists)"
        else
            log_error "ssh_key: $CFG_SSH_KEY (not found)"
            ((errors++))
        fi
    fi

    # Check Pi-hole config
    if [[ -f "$CFG_PIHOLE_TOML" ]]; then
        log_ok "pihole_toml: $CFG_PIHOLE_TOML (exists)"
    else
        log_warn "pihole_toml: $CFG_PIHOLE_TOML (not found - will be created on first sync)"
        ((warnings++))
    fi

    # Check directories
    for dir_var in CFG_CACHE_DIR CFG_BACKUP_DIR; do
        local dir_val="${!dir_var}"
        local dir_parent
        dir_parent=$(dirname "$dir_val")
        if [[ -d "$dir_parent" ]] || [[ -w "$(dirname "$dir_parent")" ]]; then
            log_ok "$dir_var: $dir_val (parent writable)"
        else
            log_error "$dir_var: $dir_val (parent not writable)"
            ((errors++))
        fi
    done

    # Check sync script
    if [[ -f "$SYNC_SCRIPT" ]]; then
        log_ok "sync_script: $SYNC_SCRIPT (exists)"
    else
        log_error "sync_script: $SYNC_SCRIPT (not found)"
        ((errors++))
    fi

    # Check webhook URL format if specified
    if [[ -n "$CFG_NOTIFY_WEBHOOK" ]]; then
        if [[ "$CFG_NOTIFY_WEBHOOK" =~ ^https?:// ]]; then
            log_ok "notify_webhook: configured"
        else
            log_warn "notify_webhook: invalid URL format"
            ((warnings++))
        fi
    fi

    echo ""
    if [[ $errors -gt 0 ]]; then
        log_error "Validation failed: $errors error(s), $warnings warning(s)"
        return 1
    elif [[ $warnings -gt 0 ]]; then
        log_warn "Validation passed with $warnings warning(s)"
        return 0
    else
        log_ok "Validation passed: configuration is valid"
        return 0
    fi
}

# =============================================================================
# Zone Validation (standalone)
# =============================================================================

validate_zones() {
    local zones_dir="$CFG_REPO_PATH/$CFG_ZONES_PATH"

    [[ ! -d "$zones_dir" ]] && { log_error "Zones directory not found: $zones_dir"; return 1; }

    print_header "Zone File Validation"
    log_info "Checking: $zones_dir"
    echo ""

    local total=0 valid=0 invalid=0
    local errors=()

    while IFS= read -r -d '' zone_file; do
        ((total++))
        local zone_name
        zone_name=$(basename "$zone_file" .zone)

        local zone_errors=()
        local record_count=0

        # Basic syntax checks
        while IFS= read -r line; do
            ((record_count++))

            # Check for common issues
            if [[ "$line" =~ [[:space:]]IN[[:space:]]+(A|AAAA)[[:space:]] ]]; then
                local ip
                ip=$(echo "$line" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}|([0-9a-fA-F:]+:+)+[0-9a-fA-F]+' | tail -1)
                if [[ -n "$ip" ]]; then
                    # Validate IP
                    if [[ "$line" =~ IN[[:space:]]+A[[:space:]] ]]; then
                        if ! [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                            zone_errors+=("Invalid IPv4: $ip")
                        fi
                    fi
                fi
            fi
        done < <(grep -v '^[[:space:]]*;' "$zone_file" | grep -v '^[[:space:]]*$')

        if [[ ${#zone_errors[@]} -eq 0 ]]; then
            ((valid++))
            echo -e "  ${C_GREEN}✓${C_NC} $zone_name ${C_DIM}($record_count records)${C_NC}"
        else
            ((invalid++))
            echo -e "  ${C_RED}✗${C_NC} $zone_name ${C_DIM}(${#zone_errors[@]} errors)${C_NC}"
            for err in "${zone_errors[@]}"; do
                echo -e "      ${C_DIM}└─ $err${C_NC}"
            done
            errors+=("$zone_name: ${zone_errors[*]}")
        fi
    done < <(find "$zones_dir" -maxdepth 1 -name "*.zone" -type f -print0 2>/dev/null | sort -z)

    echo ""
    if [[ $invalid -gt 0 ]]; then
        log_error "Validation failed: $valid/$total valid, $invalid with errors"
        return 1
    else
        log_ok "All zones valid: $valid/$total"
        return 0
    fi
}

# =============================================================================
# SSH Key Support
# =============================================================================

setup_ssh() {
    [[ -z "$CFG_SSH_KEY" ]] && return 0

    if [[ ! -f "$CFG_SSH_KEY" ]]; then
        log_error "SSH key not found: $CFG_SSH_KEY"
        return 1
    fi

    # Configure SSH to use the key
    export GIT_SSH_COMMAND="ssh -i $CFG_SSH_KEY -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null"
    log_debug "SSH key configured: $CFG_SSH_KEY"
}

# =============================================================================
# Efficient Change Detection
# =============================================================================
# Uses git ls-remote for lightweight remote hash checking without fetching.
# Caches last known hash to avoid redundant network calls.
# Typical ls-remote: ~200ms vs full fetch: ~2-5s

get_cached_hash() {
    local cache_file="$CFG_CACHE_DIR/last_remote_hash"
    [[ -f "$cache_file" ]] && cat "$cache_file" 2>/dev/null
}

set_cached_hash() {
    local hash="$1"
    mkdir -p "$CFG_CACHE_DIR" 2>/dev/null
    echo "$hash" > "$CFG_CACHE_DIR/last_remote_hash"
}

get_local_hash() {
    [[ ! -d "$CFG_REPO_PATH/.git" ]] && return 1
    git -C "$CFG_REPO_PATH" rev-parse HEAD 2>/dev/null
}

# Quick remote check - tries multiple methods for authenticated repos
get_remote_hash() {
    local hash

    setup_ssh

    # Method 1: Try ls-remote (fastest, but may fail for private repos without credentials)
    hash=$(timeout 10 git ls-remote "$CFG_REPO_URL" "refs/heads/$CFG_REPO_BRANCH" 2>/dev/null | cut -f1)

    if [[ -n "$hash" ]]; then
        log_debug "Got remote hash via ls-remote: ${hash:0:7}"
        echo "$hash"
        return 0
    fi

    # Method 2: Use existing repo's credentials via fetch --dry-run (still lightweight)
    if [[ -d "$CFG_REPO_PATH/.git" ]]; then
        log_debug "ls-remote failed, trying fetch --dry-run..."

        # Fetch updates to FETCH_HEAD without updating working tree
        if timeout 15 git -C "$CFG_REPO_PATH" fetch --dry-run origin "$CFG_REPO_BRANCH" 2>/dev/null; then
            # Get the remote ref after fetch
            hash=$(git -C "$CFG_REPO_PATH" ls-remote origin "refs/heads/$CFG_REPO_BRANCH" 2>/dev/null | cut -f1)

            if [[ -n "$hash" ]]; then
                log_debug "Got remote hash via fetch: ${hash:0:7}"
                echo "$hash"
                return 0
            fi
        fi

        # Method 3: Do a real fetch (last resort, slightly heavier but reliable)
        log_debug "fetch --dry-run failed, trying actual fetch..."
        if timeout 30 git -C "$CFG_REPO_PATH" fetch origin "$CFG_REPO_BRANCH" --depth 1 2>/dev/null; then
            hash=$(git -C "$CFG_REPO_PATH" rev-parse "origin/$CFG_REPO_BRANCH" 2>/dev/null)
            if [[ -n "$hash" ]]; then
                log_debug "Got remote hash via fetch: ${hash:0:7}"
                echo "$hash"
                return 0
            fi
        fi
    fi

    log_debug "All remote hash methods failed"
    return 1
}

# Check if remote has changes without fetching full content
# Returns: 0 = changes detected, 1 = no changes, 2 = error
check_for_changes() {
    local local_hash remote_hash cached_hash

    # Get local commit
    local_hash=$(get_local_hash)
    if [[ -z "$local_hash" ]]; then
        log_debug "No local repo, changes assumed"
        return 0  # No local repo = needs sync
    fi

    # Quick check: compare with cached remote hash first
    cached_hash=$(get_cached_hash)
    if [[ -n "$cached_hash" ]] && [[ "$local_hash" == "$cached_hash" ]]; then
        log_debug "Local matches cached remote hash, checking actual remote..."
    fi

    # Get remote hash
    remote_hash=$(get_remote_hash)
    if [[ -z "$remote_hash" ]]; then
        log_warn "Could not check remote, assuming no changes"
        return 2  # Error state
    fi

    # Update cache
    set_cached_hash "$remote_hash"

    # Compare
    if [[ "$local_hash" == "$remote_hash" ]]; then
        log_debug "No changes: local=${local_hash:0:7} remote=${remote_hash:0:7}"
        return 1  # No changes
    fi

    log_debug "Changes detected: local=${local_hash:0:7} remote=${remote_hash:0:7}"
    return 0  # Changes detected
}

# =============================================================================
# Git Operations
# =============================================================================

git_init() {
    log_info "Initializing repository..."

    if [[ "$OPT_DRY_RUN" == "true" ]]; then
        [[ -d "$CFG_REPO_PATH" ]] && log_info "[DRY-RUN] Repository exists: $CFG_REPO_PATH" \
                                  || log_info "[DRY-RUN] Would clone: $CFG_REPO_URL → $CFG_REPO_PATH"
        return 0
    fi

    if [[ ! -d "$CFG_REPO_PATH" ]]; then
        mkdir -p "${CFG_REPO_PATH%/*}"
        setup_ssh

        if git clone --branch "$CFG_REPO_BRANCH" --depth 1 "$CFG_REPO_URL" "$CFG_REPO_PATH" 2>&1 | tee -a "${CFG_LOG_FILE:-/dev/null}"; then
            log_ok "Repository cloned"
        else
            log_error "Clone failed"
            return 1
        fi
    else
        log_debug "Repository exists: $CFG_REPO_PATH"
    fi
}

git_update() {
    log_info "Updating repository..."

    if [[ "$OPT_DRY_RUN" == "true" ]]; then
        [[ -d "$CFG_REPO_PATH/.git" ]] && log_info "[DRY-RUN] Would pull: origin/$CFG_REPO_BRANCH" \
                                       || log_info "[DRY-RUN] Would update after clone"
        return 0
    fi

    [[ ! -d "$CFG_REPO_PATH/.git" ]] && { log_error "Not a git repo: $CFG_REPO_PATH"; return 1; }

    cd "$CFG_REPO_PATH" || return 1
    setup_ssh

    local local_hash remote_hash
    local_hash=$(git rev-parse HEAD 2>/dev/null)

    git fetch origin "$CFG_REPO_BRANCH" --depth 1 2>&1 | tee -a "${CFG_LOG_FILE:-/dev/null}" || { log_error "Fetch failed"; return 1; }

    remote_hash=$(git rev-parse "origin/$CFG_REPO_BRANCH" 2>/dev/null)

    if [[ "$local_hash" == "$remote_hash" ]] && [[ "$OPT_FORCE" != "true" ]]; then
        log_ok "Already up to date"
        return 0
    fi

    git reset --hard "origin/$CFG_REPO_BRANCH" 2>&1 | tee -a "${CFG_LOG_FILE:-/dev/null}" || { log_error "Reset failed"; return 1; }
    log_ok "Updated: ${local_hash:0:7} → ${remote_hash:0:7}"
}

# =============================================================================
# Zone Discovery & Filtering
# =============================================================================

discover_zones() {
    local zones_dir="$CFG_REPO_PATH/$CFG_ZONES_PATH"
    local zones=()

    [[ ! -d "$zones_dir" ]] && { log_error "Zones directory not found: $zones_dir"; return 1; }

    while IFS= read -r -d '' zone_file; do
        local zone_name="${zone_file##*/}"
        zone_name="${zone_name%.zone}"
        zones+=("$zone_name")
    done < <(find "$zones_dir" -maxdepth 1 -name "*.zone" -type f -print0 2>/dev/null | sort -z)

    if [[ ${#zones[@]} -eq 0 ]]; then
        log_warn "No zone files found in: $zones_dir"
        return 0
    fi

    # Filter if specific zones requested
    if [[ ${#OPT_ZONES[@]} -gt 0 ]]; then
        local filtered=()
        for z in "${zones[@]}"; do
            for filter in "${OPT_ZONES[@]}"; do
                [[ "$z" == "$filter" ]] && filtered+=("$z") && break
            done
        done
        zones=("${filtered[@]}")

        if [[ ${#zones[@]} -eq 0 ]]; then
            log_error "No matching zones found for filter: ${OPT_ZONES[*]}"
            return 1
        fi
    fi

    printf '%s\n' "${zones[@]}"
}

list_zones() {
    local zones_dir="$CFG_REPO_PATH/$CFG_ZONES_PATH"

    if [[ ! -d "$zones_dir" ]]; then
        if [[ "$OPT_JSON" == "true" ]]; then
            json_output "error" "Zones directory not found" "path" "\"$zones_dir\""
        else
            log_error "Zones directory not found: $zones_dir"
            log_info "Run 'dns-sync init' first to clone the repository"
        fi
        return 1
    fi

    local zones=()
    while IFS= read -r zone; do
        [[ -n "$zone" ]] && zones+=("$zone")
    done < <(discover_zones)

    if [[ "$OPT_JSON" == "true" ]]; then
        local json_zones
        json_zones=$(printf '"%s",' "${zones[@]}" | sed 's/,$//')
        json_output "ok" "Found ${#zones[@]} zones" "zones" "[$json_zones]" "count" "${#zones[@]}"
    else
        print_header "Available DNS Zones"
        echo "Directory: $zones_dir"
        echo ""
        if [[ ${#zones[@]} -eq 0 ]]; then
            log_warn "No zone files found"
        else
            for zone in "${zones[@]}"; do
                local zone_file="$zones_dir/${zone}.zone"
                local records
                records=$(grep -cE '^[^;[:space:]]' "$zone_file" 2>/dev/null || echo "0")
                echo -e "  ${C_CYAN}●${C_NC} $zone ${C_DIM}($records records)${C_NC}"
            done
            echo ""
            log_info "Total: ${#zones[@]} zone(s)"
        fi
    fi
}

# =============================================================================
# DNS Sync
# =============================================================================

validate_env() {
    log_info "Validating environment..."

    if [[ "$OPT_DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would validate: $SYNC_SCRIPT, zones, Pi-hole config"
        return 0
    fi

    [[ ! -f "$SYNC_SCRIPT" ]] && { log_error "Sync script not found: $SYNC_SCRIPT"; return 1; }
    [[ ! -d "$CFG_REPO_PATH/$CFG_ZONES_PATH" ]] && { log_error "Zones dir not found: $CFG_REPO_PATH/$CFG_ZONES_PATH"; return 1; }
    [[ ! -f "$CFG_PIHOLE_TOML" ]] && { log_error "Pi-hole config not found: $CFG_PIHOLE_TOML"; return 1; }

    local zone_count
    zone_count=$(find "$CFG_REPO_PATH/$CFG_ZONES_PATH" -name "*.zone" -type f 2>/dev/null | wc -l)
    log_ok "Validation passed ($zone_count zone files)"
}

sync_dns() {
    log_info "Syncing DNS zones..."

    local start_time zones_dir backup_file zone_count
    start_time=$(date +%s%3N 2>/dev/null || date +%s)000
    zones_dir="$CFG_REPO_PATH/$CFG_ZONES_PATH"
    backup_file=""
    zone_count=$(find "$zones_dir" -name "*.zone" -type f 2>/dev/null | wc -l)

    # Rotate logs if needed
    rotate_logs

    # Create backup
    backup_file=$(create_backup "$CFG_PIHOLE_TOML")

    if [[ "$OPT_DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would sync: $zones_dir → $CFG_PIHOLE_TOML"
        [[ "$OPT_NO_RESTART" != "true" ]] && log_info "[DRY-RUN] Would restart: pihole-FTL"
        return 0
    fi

    # Build zone filter args
    local zone_args=""
    if [[ ${#OPT_ZONES[@]} -gt 0 ]]; then
        zone_args="--zones $(IFS=,; echo "${OPT_ZONES[*]}")"
        log_info "Syncing zones: ${OPT_ZONES[*]}"
        zone_count=${#OPT_ZONES[@]}
    fi

    # Run sync
    local sync_cmd="python3 $SYNC_SCRIPT $zones_dir $CFG_PIHOLE_TOML $zone_args"
    [[ $EUID -ne 0 ]] && sync_cmd="sudo $sync_cmd"

    if eval "$sync_cmd" 2>&1 | tee -a "${CFG_LOG_FILE:-/dev/null}"; then
        local end_time duration
        end_time=$(date +%s%3N 2>/dev/null || date +%s)000
        duration=$((end_time - start_time))

        log_ok "DNS sync completed"

        # Record success
        mkdir -p "$CFG_CACHE_DIR"
        date -Iseconds > "$CFG_CACHE_DIR/last_success"

        # Record history and metrics
        record_history "success" "Sync completed successfully" "$zone_count" "$duration"
        update_metrics "success" "$duration" "$zone_count"

        # Send notification
        send_notification "success" "DNS sync completed" "Synced $zone_count zone(s) in ${duration}ms"

        # Restart Pi-hole
        [[ "$OPT_NO_RESTART" != "true" ]] && restart_pihole

        cleanup_backups "$CFG_BACKUP_KEEP_COUNT"
        return 0
    else
        local end_time duration
        end_time=$(date +%s%3N 2>/dev/null || date +%s)000
        duration=$((end_time - start_time))

        log_error "DNS sync failed"
        mkdir -p "$CFG_CACHE_DIR"
        date -Iseconds > "$CFG_CACHE_DIR/last_failure"

        # Record history and metrics
        record_history "failure" "Sync failed" 0 "$duration"
        update_metrics "failure" "$duration" 0

        # Send notification
        send_notification "failure" "DNS sync failed" "Check logs: $CFG_LOG_FILE"

        # Rollback
        if [[ -n "$backup_file" ]] && [[ -f "$backup_file" ]]; then
            log_warn "Attempting rollback..."
            if rollback "$CFG_PIHOLE_TOML" "$backup_file"; then
                record_history "rollback" "Rolled back after failure" 0 0
                return $E_ROLLBACK
            fi
        fi

        return $E_ERROR
    fi
}

restart_pihole() {
    command -v systemctl &>/dev/null || { log_warn "systemctl not available"; return 0; }

    log_info "Restarting Pi-hole FTL..."

    local cmd="systemctl restart pihole-FTL"
    [[ $EUID -ne 0 ]] && cmd="sudo $cmd"

    if $cmd 2>&1 | tee -a "${CFG_LOG_FILE:-/dev/null}"; then
        log_ok "Pi-hole FTL restarted"
    else
        log_warn "Failed to restart Pi-hole FTL"
    fi
}

# =============================================================================
# Health Check
# =============================================================================

cmd_health() {
    setup_paths
    load_config

    local status=0 passed=0 total=0 checks=()

    # Check 1: Dependencies
    total=$((total + 1))
    if check_deps 2>/dev/null; then
        passed=$((passed + 1))
        checks+=('{"name": "dependencies", "status": "ok", "message": "All dependencies available"}')
        [[ "$OPT_JSON" != "true" ]] && log_ok "Dependencies: OK"
    else
        status=1
        checks+=('{"name": "dependencies", "status": "error", "message": "Missing dependencies"}')
        [[ "$OPT_JSON" != "true" ]] && log_error "Dependencies: Missing"
    fi

    # Check 2: Repository
    total=$((total + 1))
    if [[ -d "$CFG_REPO_PATH/.git" ]]; then
        passed=$((passed + 1))
        local commit
        commit=$(cd "$CFG_REPO_PATH" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        checks+=("{\"name\": \"repository\", \"status\": \"ok\", \"message\": \"Initialized\", \"commit\": \"$commit\"}")
        [[ "$OPT_JSON" != "true" ]] && log_ok "Repository: $CFG_REPO_PATH ($commit)"
    else
        status=1
        checks+=('{"name": "repository", "status": "error", "message": "Not initialized"}')
        [[ "$OPT_JSON" != "true" ]] && log_error "Repository: Not initialized"
    fi

    # Check 3: Zones
    total=$((total + 1))
    local zones_dir="$CFG_REPO_PATH/$CFG_ZONES_PATH"
    if [[ -d "$zones_dir" ]]; then
        local zone_count
        zone_count=$(find "$zones_dir" -name "*.zone" -type f 2>/dev/null | wc -l)
        passed=$((passed + 1))
        checks+=("{\"name\": \"zones\", \"status\": \"ok\", \"count\": $zone_count}")
        [[ "$OPT_JSON" != "true" ]] && log_ok "Zones: $zone_count files in $zones_dir"
    else
        status=1
        checks+=('{"name": "zones", "status": "error", "message": "Directory not found"}')
        [[ "$OPT_JSON" != "true" ]] && log_error "Zones: Directory not found"
    fi

    # Check 4: Pi-hole config
    total=$((total + 1))
    if [[ -f "$CFG_PIHOLE_TOML" ]]; then
        passed=$((passed + 1))
        checks+=('{"name": "pihole_config", "status": "ok"}')
        [[ "$OPT_JSON" != "true" ]] && log_ok "Pi-hole config: $CFG_PIHOLE_TOML"
    else
        status=1
        checks+=('{"name": "pihole_config", "status": "error", "message": "Not found"}')
        [[ "$OPT_JSON" != "true" ]] && log_error "Pi-hole config: Not found"
    fi

    # Check 5: Pi-hole service
    total=$((total + 1))
    if command -v systemctl &>/dev/null && systemctl is-active --quiet pihole-FTL 2>/dev/null; then
        passed=$((passed + 1))
        checks+=('{"name": "pihole_service", "status": "ok", "message": "Running"}')
        [[ "$OPT_JSON" != "true" ]] && log_ok "Pi-hole FTL: Running"
    else
        checks+=('{"name": "pihole_service", "status": "warning", "message": "Not running or unavailable"}')
        [[ "$OPT_JSON" != "true" ]] && log_warn "Pi-hole FTL: Not running or unavailable"
    fi

    # Sync status
    local last_success="" last_failure=""
    [[ -f "$CFG_CACHE_DIR/last_success" ]] && last_success=$(cat "$CFG_CACHE_DIR/last_success")
    [[ -f "$CFG_CACHE_DIR/last_failure" ]] && last_failure=$(cat "$CFG_CACHE_DIR/last_failure")

    if [[ "$OPT_JSON" == "true" ]]; then
        local checks_json
        checks_json=$(IFS=,; echo "${checks[*]}")
        echo "{\"status\": \"$([[ $status -eq 0 ]] && echo ok || echo error)\", \"passed\": $passed, \"total\": $total, \"checks\": [$checks_json], \"last_success\": \"$last_success\", \"last_failure\": \"$last_failure\"}"
    else
        echo ""
        log_info "Sync Status:"
        [[ -n "$last_success" ]] && log_ok "  Last success: $last_success" || log_warn "  No successful sync recorded"
        [[ -n "$last_failure" ]] && log_warn "  Last failure: $last_failure"

        local backup_count=0
        [[ -d "$CFG_BACKUP_DIR" ]] && backup_count=$(find "$CFG_BACKUP_DIR" -name "*.bak" -type f 2>/dev/null | wc -l)
        log_info "  Backups: $backup_count"

        echo ""
        [[ $status -eq 0 ]] && log_ok "Health check passed ($passed/$total)" || log_error "Health check failed ($passed/$total)"
    fi

    return $status
}

# =============================================================================
# Status Command
# =============================================================================

cmd_status() {
    setup_paths
    load_config

    if [[ "$OPT_JSON" == "true" ]]; then
        local commit="" branch=""
        if [[ -d "$CFG_REPO_PATH/.git" ]]; then
            commit=$(cd "$CFG_REPO_PATH" && git rev-parse --short HEAD 2>/dev/null || echo "")
            branch=$(cd "$CFG_REPO_PATH" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        fi

        echo "{\"version\": \"$VERSION\", \"repo_url\": \"$CFG_REPO_URL\", \"repo_branch\": \"$CFG_REPO_BRANCH\", \"repo_path\": \"$CFG_REPO_PATH\", \"zones_path\": \"$CFG_ZONES_PATH\", \"pihole_toml\": \"$CFG_PIHOLE_TOML\", \"commit\": \"$commit\", \"current_branch\": \"$branch\"}"
        return 0
    fi

    print_header "DNS Sync Status"

    echo -e "${C_CYAN}Version:${C_NC} $VERSION"
    echo ""

    echo -e "${C_CYAN}Git Repository:${C_NC}"
    echo "  URL:    ${CFG_REPO_URL:-<not configured>}"
    echo "  Branch: $CFG_REPO_BRANCH"
    echo "  Path:   $CFG_REPO_PATH"
    [[ -n "$CFG_SSH_KEY" ]] && echo "  SSH:    $CFG_SSH_KEY"
    echo ""

    echo -e "${C_CYAN}Paths:${C_NC}"
    echo "  Zones:   $CFG_REPO_PATH/$CFG_ZONES_PATH"
    echo "  Pi-hole: $CFG_PIHOLE_TOML"
    echo "  Config:  $CFG_CONFIG_FILE"
    echo "  Cache:   $CFG_CACHE_DIR"
    echo "  Backups: $CFG_BACKUP_DIR"
    echo "  Log:     $CFG_LOG_FILE"
    echo ""

    if [[ -d "$CFG_REPO_PATH/.git" ]]; then
        echo -e "${C_CYAN}Repository:${C_NC}"
        cd "$CFG_REPO_PATH"
        echo "  Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
        echo "  Commit: $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
        echo "  Date:   $(git log -1 --format=%ci 2>/dev/null || echo unknown)"
    fi
}

# =============================================================================
# Install Command
# =============================================================================

cmd_install() {
    [[ $EUID -ne 0 ]] && { log_error "Install requires root privileges"; return 1; }

    print_header "Installing DNS Sync v${VERSION}"

    local install_path="/usr/local/bin/dns-sync"
    local systemd_dir="/etc/systemd/system"
    local config_dir="/etc/dns-sync"
    local log_dir="/var/log"
    local cache_dir="/var/cache/dns-sync"
    local backup_dir="/var/backups/dns-sync"
    local lib_dir="/var/lib/dns-sync"
    local repo_dir="/opt/dns-sync/repo"
    local logrotate_dir="/etc/logrotate.d"
    local completion_dir="/etc/bash_completion.d"

    if [[ "$OPT_DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install:"
        log_info "  Script:     $install_path"
        log_info "  Config:     $config_dir/config.conf"
        log_info "  Service:    $systemd_dir/dns-sync.service"
        log_info "  Timer:      $systemd_dir/dns-sync.timer"
        log_info "  Logrotate:  $logrotate_dir/dns-sync"
        log_info "  Completion: $completion_dir/dns-sync"
        log_info "  Directories: $cache_dir, $backup_dir, $lib_dir, $repo_dir"
        return 0
    fi

    # ==========================================================================
    # Step 1: Install scripts
    # ==========================================================================
    log_info "Installing scripts..."

    # Handle re-installation (when script is already at install location)
    if [[ "$(realpath "$SCRIPT_PATH" 2>/dev/null)" != "$(realpath "$install_path" 2>/dev/null)" ]]; then
        cp "$SCRIPT_PATH" "$install_path"
        chmod 755 "$install_path"
        log_ok "Installed: $install_path"
    else
        log_info "Script already at: $install_path (skipped)"
    fi

    if [[ -f "$SYNC_SCRIPT" ]]; then
        local target_sync="${install_path%/*}/sync-dns-zones.py"
        if [[ "$(realpath "$SYNC_SCRIPT" 2>/dev/null)" != "$(realpath "$target_sync" 2>/dev/null)" ]]; then
            cp "$SYNC_SCRIPT" "$target_sync"
            chmod 755 "$target_sync"
            log_ok "Installed: $target_sync"
        else
            log_info "Sync script already at: $target_sync (skipped)"
        fi
    else
        if [[ ! -f "${install_path%/*}/sync-dns-zones.py" ]]; then
            log_warn "Python sync script not found: $SYNC_SCRIPT"
            log_info "You may need to install it manually"
        else
            log_info "Sync script exists: ${install_path%/*}/sync-dns-zones.py"
        fi
    fi

    # ==========================================================================
    # Step 2: Create directories with proper permissions
    # ==========================================================================
    log_info "Creating directories..."

    mkdir -p "$config_dir" "$cache_dir" "$backup_dir" "$lib_dir" "$repo_dir"
    chmod 755 "$config_dir" "$cache_dir" "$backup_dir" "$lib_dir"
    chmod 755 "$repo_dir"

    log_ok "Created: $cache_dir (cache)"
    log_ok "Created: $backup_dir (backups)"
    log_ok "Created: $lib_dir (history, metrics)"
    log_ok "Created: $repo_dir (git repository)"

    # ==========================================================================
    # Step 3: Create configuration file
    # ==========================================================================
    log_info "Creating configuration..."

    if [[ ! -f "$config_dir/config.conf" ]]; then
        cat > "$config_dir/config.conf" << 'CONF'
# =============================================================================
# DNS Sync Configuration
# =============================================================================
# Run 'dns-sync help' for documentation
# Run 'dns-sync config-test' to validate this configuration

# =============================================================================
# Git Repository Settings (REQUIRED)
# =============================================================================

# Git repository URL containing DNS zone files
# Supports HTTPS and SSH URLs
#repo_url = https://github.com/your-org/dns-zones.git
#repo_url = git@github.com:your-org/dns-zones.git

# Branch to track (default: main)
repo_branch = main

# Local clone path
repo_path = /opt/dns-sync/repo

# Relative path to zones directory within the repository
zones_path = zones

# =============================================================================
# Authentication (for private repositories)
# =============================================================================

# SSH private key path (optional, for SSH URLs)
#ssh_key = /root/.ssh/dns-sync-key

# =============================================================================
# Pi-hole Settings
# =============================================================================

# Path to Pi-hole TOML configuration file
pihole_toml = /etc/pihole/pihole.toml

# =============================================================================
# Notification Settings (optional)
# =============================================================================

# Webhook URL for notifications (Slack, Mattermost, Discord compatible)
#notify_webhook = https://hooks.slack.com/services/xxx/yyy/zzz

# When to send notifications
notify_on_failure = true
notify_on_success = false

# =============================================================================
# Storage Settings (optional - defaults shown)
# =============================================================================

#log_file = /var/log/dns-sync.log
#cache_dir = /var/cache/dns-sync
#backup_dir = /var/backups/dns-sync

# =============================================================================
# Retention Settings (optional - defaults shown)
# =============================================================================

# Maximum log file size before rotation (bytes, default 10MB)
#log_max_size = 10485760

# Number of rotated log files to keep
#log_keep_count = 5

# Number of backups to keep
#backup_keep_count = 10

# Number of history entries to keep
#history_keep_count = 100
CONF
        chmod 644 "$config_dir/config.conf"
        log_ok "Created: $config_dir/config.conf"
    else
        log_info "Config exists: $config_dir/config.conf (preserved)"
    fi

    # ==========================================================================
    # Step 4: Create systemd service (smart check-then-sync)
    # ==========================================================================
    log_info "Creating systemd units..."

    cat > "$systemd_dir/dns-sync.service" << 'SERVICE'
[Unit]
Description=DNS GitOps Sync Service
Documentation=https://github.com/codefuturist/remote-script-runner
After=network-online.target pihole-FTL.service
Wants=network-online.target

[Service]
Type=oneshot

# Smart sync: only sync if changes detected
# 'check' returns 0 if changes found, 1 if no changes, 2 on error
ExecStart=/bin/bash -c '/usr/local/bin/dns-sync check -q && /usr/local/bin/dns-sync sync || exit 0'

StandardOutput=journal
StandardError=journal
SyslogIdentifier=dns-sync

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/etc/pihole /etc/dns-sync /var/log /var/cache/dns-sync /var/backups/dns-sync /var/lib/dns-sync /opt/dns-sync

# Resource limits
MemoryMax=256M
CPUQuota=50%
TasksMax=20
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
SERVICE
    log_ok "Created: $systemd_dir/dns-sync.service"

    # ==========================================================================
    # Step 5: Create systemd timer (every minute smart check)
    # ==========================================================================
    cat > "$systemd_dir/dns-sync.timer" << 'TIMER'
[Unit]
Description=DNS GitOps Sync Timer (Smart Check)
Documentation=https://github.com/codefuturist/remote-script-runner

[Timer]
# Run 1 minute after boot
OnBootSec=1min

# Run every minute (lightweight check, only syncs on changes)
OnCalendar=*:*

# Add randomized delay to prevent thundering herd
RandomizedDelaySec=10

# Catch up on missed runs
Persistent=true

[Install]
WantedBy=timers.target
TIMER
    log_ok "Created: $systemd_dir/dns-sync.timer"

    # ==========================================================================
    # Step 6: Create logrotate configuration
    # ==========================================================================
    log_info "Creating logrotate configuration..."

    if [[ -d "$logrotate_dir" ]]; then
        cat > "$logrotate_dir/dns-sync" << 'LOGROTATE'
/var/log/dns-sync.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    dateext
    dateformat -%Y%m%d
}
LOGROTATE
        chmod 644 "$logrotate_dir/dns-sync"
        log_ok "Created: $logrotate_dir/dns-sync"
    else
        log_warn "Logrotate directory not found, skipping"
    fi

    # ==========================================================================
    # Step 7: Install bash completion
    # ==========================================================================
    log_info "Installing shell completions..."

    if [[ -d "$completion_dir" ]]; then
        "$install_path" completions bash > "$completion_dir/dns-sync" 2>/dev/null
        chmod 644 "$completion_dir/dns-sync"
        log_ok "Created: $completion_dir/dns-sync"
    else
        log_info "Bash completion directory not found, skipping"
    fi

    # Also try to install zsh completion if available
    if [[ -d "/usr/share/zsh/site-functions" ]]; then
        "$install_path" completions zsh > "/usr/share/zsh/site-functions/_dns-sync" 2>/dev/null
        log_ok "Created: /usr/share/zsh/site-functions/_dns-sync"
    fi

    # ==========================================================================
    # Step 8: Reload systemd
    # ==========================================================================
    log_info "Reloading systemd..."
    systemctl daemon-reload
    log_ok "systemd reloaded"

    # ==========================================================================
    # Step 9: Summary and next steps
    # ==========================================================================
    echo ""
    echo -e "${C_BOLD}${C_GREEN}═══════════════════════════════════════════════════════════${C_NC}"
    echo -e "${C_BOLD}${C_GREEN}  Installation Complete!${C_NC}"
    echo -e "${C_BOLD}${C_GREEN}═══════════════════════════════════════════════════════════${C_NC}"
    echo ""

    echo -e "${C_CYAN}Installed Components:${C_NC}"
    echo "  • Script:      $install_path"
    echo "  • Config:      $config_dir/config.conf"
    echo "  • Service:     $systemd_dir/dns-sync.service"
    echo "  • Timer:       $systemd_dir/dns-sync.timer"
    echo "  • Logrotate:   $logrotate_dir/dns-sync"
    echo "  • Directories: cache, backup, history, metrics"
    echo ""

    echo -e "${C_YELLOW}Next Steps:${C_NC}"
    echo ""
    echo "  1. Configure repository URL:"
    echo -e "     ${C_DIM}nano $config_dir/config.conf${C_NC}"
    echo ""
    echo "  2. Validate configuration:"
    echo -e "     ${C_DIM}dns-sync config-test${C_NC}"
    echo ""
    echo "  3. Test sync (dry-run):"
    echo -e "     ${C_DIM}dns-sync sync --dry-run${C_NC}"
    echo ""
    echo "  4. Run initial sync:"
    echo -e "     ${C_DIM}dns-sync sync${C_NC}"
    echo ""
    echo "  5. Enable automatic sync timer:"
    echo -e "     ${C_DIM}systemctl enable --now dns-sync.timer${C_NC}"
    echo ""
    echo "  6. Verify timer is running:"
    echo -e "     ${C_DIM}systemctl list-timers dns-sync.timer${C_NC}"
    echo ""

    echo -e "${C_CYAN}Useful Commands:${C_NC}"
    echo "  dns-sync health        - Check system health"
    echo "  dns-sync check         - Quick check for changes"
    echo "  dns-sync zones         - List available zones"
    echo "  dns-sync history       - View sync history"
    echo "  dns-sync backups       - List backups"
    echo "  dns-sync help          - Full documentation"
    echo ""
}

cmd_uninstall() {
    [[ $EUID -ne 0 ]] && { log_error "Uninstall requires root privileges"; return 1; }

    print_header "Uninstalling DNS Sync"

    if [[ "$OPT_DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would remove:"
        log_info "  Scripts:    /usr/local/bin/dns-sync, sync-dns-zones.py"
        log_info "  Systemd:    dns-sync.service, dns-sync.timer"
        log_info "  Logrotate:  /etc/logrotate.d/dns-sync"
        log_info "  Completion: /etc/bash_completion.d/dns-sync"
        [[ "$OPT_FORCE" == "true" ]] && log_info "  Data:       config, cache, backups, history, logs, repo"
        return 0
    fi

    # Stop and disable timer
    log_info "Stopping services..."
    systemctl disable --now dns-sync.timer 2>/dev/null || true
    systemctl disable dns-sync.service 2>/dev/null || true
    log_ok "Services stopped"

    # Remove scripts
    log_info "Removing scripts..."
    rm -f /usr/local/bin/dns-sync /usr/local/bin/sync-dns-zones.py
    log_ok "Removed: scripts"

    # Remove systemd units
    log_info "Removing systemd units..."
    rm -f /etc/systemd/system/dns-sync.service /etc/systemd/system/dns-sync.timer
    systemctl daemon-reload
    log_ok "Removed: systemd units"

    # Remove logrotate config
    if [[ -f "/etc/logrotate.d/dns-sync" ]]; then
        rm -f /etc/logrotate.d/dns-sync
        log_ok "Removed: logrotate config"
    fi

    # Remove shell completions
    rm -f /etc/bash_completion.d/dns-sync 2>/dev/null
    rm -f /usr/share/zsh/site-functions/_dns-sync 2>/dev/null
    log_ok "Removed: shell completions"

    # Handle config and data based on --force flag
    if [[ "$OPT_FORCE" == "true" ]]; then
        log_info "Removing all data (--force)..."

        rm -rf /etc/dns-sync
        log_ok "Removed: /etc/dns-sync (config)"

        rm -rf /var/cache/dns-sync
        log_ok "Removed: /var/cache/dns-sync (cache)"

        rm -rf /var/backups/dns-sync
        log_ok "Removed: /var/backups/dns-sync (backups)"

        rm -rf /var/lib/dns-sync
        log_ok "Removed: /var/lib/dns-sync (history, metrics)"

        rm -f /var/log/dns-sync.log*
        log_ok "Removed: /var/log/dns-sync.log (logs)"

        if [[ -d "/opt/dns-sync" ]]; then
            rm -rf /opt/dns-sync
            log_ok "Removed: /opt/dns-sync (repository)"
        fi
    else
        echo ""
        log_info "Preserved (use --force to remove):"
        [[ -d "/etc/dns-sync" ]] && echo "  • /etc/dns-sync (config)"
        [[ -d "/var/cache/dns-sync" ]] && echo "  • /var/cache/dns-sync (cache)"
        [[ -d "/var/backups/dns-sync" ]] && echo "  • /var/backups/dns-sync (backups)"
        [[ -d "/var/lib/dns-sync" ]] && echo "  • /var/lib/dns-sync (history, metrics)"
        [[ -f "/var/log/dns-sync.log" ]] && echo "  • /var/log/dns-sync.log (logs)"
        [[ -d "/opt/dns-sync" ]] && echo "  • /opt/dns-sync (repository)"
    fi

    echo ""
    log_ok "Uninstall complete"
}

# =============================================================================
# Sync Command
# =============================================================================

# =============================================================================
# Check Command - Lightweight change detection
# =============================================================================

cmd_check() {
    setup_paths
    load_config

    [[ -z "$CFG_REPO_URL" ]] && { log_error "Repository URL not configured."; return 1; }

    local result=0
    check_for_changes || result=$?

    case $result in
        0)  # Changes detected
            if [[ "$OPT_JSON" == "true" ]]; then
                local local_h remote_h
                local_h=$(get_local_hash)
                remote_h=$(get_cached_hash)
                json_output "changes" "Remote changes detected" \
                    "local_hash" "\"${local_h:-null}\"" \
                    "remote_hash" "\"${remote_h:-null}\""
            else
                log_info "Changes detected - sync recommended"
            fi
            return 0
            ;;
        1)  # No changes
            if [[ "$OPT_JSON" == "true" ]]; then
                local h
                h=$(get_local_hash)
                json_output "ok" "No changes detected" "hash" "\"${h:-null}\""
            else
                log_ok "No changes detected"
            fi
            return 1
            ;;
        *)  # Error
            if [[ "$OPT_JSON" == "true" ]]; then
                json_output "error" "Failed to check for changes"
            else
                log_error "Failed to check for changes"
            fi
            return 2
            ;;
    esac
}

# =============================================================================
# Watch Command - Continuous monitoring with efficient polling
# =============================================================================

cmd_watch() {
    setup_paths
    load_config

    [[ -z "$CFG_REPO_URL" ]] && { log_error "Repository URL not configured."; return 1; }

    check_deps || return $?

    local interval="$OPT_WATCH_INTERVAL"
    local check_count=0
    local sync_count=0
    local last_sync=""
    local start_time
    start_time=$(date +%s)

    print_header "DNS Sync Watch Mode"
    log_info "Monitoring for changes every ${interval}s"
    log_info "Press Ctrl+C to stop"
    echo ""

    # Trap for clean shutdown
    trap 'echo ""; log_info "Watch stopped. Checks: $check_count, Syncs: $sync_count"; exit 0' INT TERM

    while true; do
        check_count=$((check_count + 1))
        local check_time
        check_time=$(date '+%H:%M:%S')

        # Quick check for changes
        if check_for_changes; then
            log_info "[$check_time] Changes detected, syncing..."

            # Acquire lock and sync
            if acquire_lock 2>/dev/null; then
                git_init >/dev/null 2>&1
                if git_update && validate_env 2>/dev/null && sync_dns; then
                    sync_count=$((sync_count + 1))
                    last_sync="$check_time"
                    log_ok "[$check_time] Sync #$sync_count completed"
                else
                    log_error "[$check_time] Sync failed"
                fi
                release_lock
            else
                log_warn "[$check_time] Could not acquire lock, skipping"
            fi
        else
            # No changes - show minimal output
            if [[ "$OPT_VERBOSE" == "true" ]]; then
                log_debug "[$check_time] No changes (check #$check_count)"
            else
                # Periodic status every 10 checks
                if [[ $((check_count % 10)) -eq 0 ]]; then
                    local uptime=$(($(date +%s) - start_time))
                    log_info "[$check_time] Watching... (${uptime}s, $check_count checks, $sync_count syncs)"
                fi
            fi
        fi

        sleep "$interval"
    done
}

# =============================================================================
# Sync Command
# =============================================================================

cmd_sync() {
    setup_paths
    load_config

    [[ -z "$CFG_REPO_URL" ]] && { log_error "Repository URL not configured. Set DNS_REPO_URL or edit config."; return 1; }

    print_header "DNS GitOps Sync"

    check_deps || return $?
    acquire_lock || return $?

    git_init || { log_error "Repository init failed"; return $E_ERROR; }
    git_update || { log_error "Repository update failed"; return $E_ERROR; }
    validate_env || { log_error "Validation failed"; return $E_ERROR; }

    local result
    sync_dns
    result=$?

    if [[ $result -eq 0 ]]; then
        echo ""
        [[ "$OPT_JSON" == "true" ]] && json_output "ok" "Sync completed successfully" || log_ok "DNS sync completed successfully"
    elif [[ $result -eq $E_ROLLBACK ]]; then
        echo ""
        [[ "$OPT_JSON" == "true" ]] && json_output "rollback" "Sync failed, rolled back" || log_warn "Sync failed but rollback succeeded"
    else
        echo ""
        [[ "$OPT_JSON" == "true" ]] && json_output "error" "Sync failed" || log_error "Sync failed"
    fi

    return $result
}

# =============================================================================
# Help
# =============================================================================

cmd_help() {
    cat << EOF
${C_BOLD}DNS GitOps Sync Service v${VERSION}${C_NC}

Sync DNS zone files from a Git repository to Pi-hole with validation,
backup/rollback support, notifications, and systemd integration.

${C_YELLOW}Usage:${C_NC}
    $SCRIPT_NAME <command> [options]

${C_BOLD}Commands:${C_NC}
  ${C_CYAN}Sync Operations:${C_NC}
    sync              Sync DNS zones from Git to Pi-hole (default)
    check             Quick check for remote changes (no sync)
    watch             Continuous monitoring with auto-sync
    diff              Preview changes without applying

  ${C_CYAN}Validation:${C_NC}
    validate          Validate zone files syntax
    config-test       Test configuration file

  ${C_CYAN}Backup & Restore:${C_NC}
    backups           List available backups
    restore <ref>     Restore from backup (number or filename)

  ${C_CYAN}Information:${C_NC}
    health            Check system health and sync status
    status            Show current configuration
    zones             List available DNS zones
    history           Show sync history
    metrics           Show/export Prometheus metrics

  ${C_CYAN}Repository:${C_NC}
    init              Initialize repository only
    update            Update repository only

  ${C_CYAN}Installation:${C_NC}
    install           Install as system service (requires root)
    uninstall         Remove system service (requires root)
    completions       Generate shell completions

  ${C_CYAN}Help:${C_NC}
    help              Show this help message
    version           Show version information

${C_BOLD}Options:${C_NC}
    -h, --help              Show help
    -v, --verbose           Verbose output
    -q, --quiet             Quiet mode (errors only)
    -n, --dry-run           Preview changes without applying
    -f, --force             Force operation
    --no-restart            Skip Pi-hole restart
    --json                  Output in JSON format
    --zone <name>           Sync specific zone(s), can repeat
    --config <file>         Use specific config file
    --repo-url <url>        Git repository URL
    --branch <name>         Git branch (default: main)
    --ssh-key <path>        SSH private key for git
    --interval <secs>       Watch mode check interval (default: 60)

${C_BOLD}Examples:${C_NC}
    ${C_DIM}# First-time setup${C_NC}
    sudo dns-sync install
    sudo nano /etc/dns-sync/config.conf
    sudo dns-sync config-test
    sudo dns-sync sync --dry-run
    sudo systemctl enable --now dns-sync.timer

    ${C_DIM}# Manual sync${C_NC}
    dns-sync sync

    ${C_DIM}# Preview changes before sync${C_NC}
    dns-sync diff

    ${C_DIM}# Quick check for changes (lightweight)${C_NC}
    dns-sync check
    dns-sync check --json    # For scripts/monitoring

    ${C_DIM}# Watch mode - continuous monitoring${C_NC}
    dns-sync watch                    # Check every 60s
    dns-sync watch --interval 30      # Check every 30s

    ${C_DIM}# Backup and restore${C_NC}
    dns-sync backups                  # List backups
    dns-sync restore 1                # Restore most recent
    dns-sync restore pihole.toml.20251210_120000.bak

    ${C_DIM}# Validation${C_NC}
    dns-sync validate                 # Validate zone files
    dns-sync config-test              # Validate config

    ${C_DIM}# Monitoring${C_NC}
    dns-sync health --json            # For monitoring systems
    dns-sync history                  # Show recent syncs
    dns-sync metrics                  # Prometheus metrics

    ${C_DIM}# Sync specific zones${C_NC}
    dns-sync sync --zone home.lan --zone office.lan

    ${C_DIM}# Force sync with verbose output${C_NC}
    dns-sync sync -v --force

    ${C_DIM}# Generate shell completions${C_NC}
    dns-sync completions bash >> ~/.bashrc
    dns-sync completions zsh >> ~/.zshrc

${C_BOLD}Notifications:${C_NC}
    Configure webhook notifications in config file:
      notify_webhook = https://hooks.slack.com/services/...
      notify_on_success = false
      notify_on_failure = true

${C_BOLD}Prometheus Metrics:${C_NC}
    Metrics are exported to: /var/lib/dns-sync/metrics.prom
    Configure your Prometheus node_exporter to collect from this file.

${C_BOLD}Configuration:${C_NC}
    Config file: /etc/dns-sync/config.conf (root) or ~/.config/dns-sync/config.conf

    Environment variables (override config):
      DNS_REPO_URL        Git repository URL
      DNS_REPO_BRANCH     Branch to track
      DNS_REPO_PATH       Local clone path
      DNS_ZONES_PATH      Relative path to zones in repo
      DNS_SSH_KEY         Path to SSH private key
      PIHOLE_TOML_PATH    Pi-hole config path
      DNS_NOTIFY_WEBHOOK  Webhook URL for notifications

${C_BOLD}Documentation:${C_NC}
    ${SCRIPT_URL}

EOF
}

# =============================================================================
# History Command
# =============================================================================

cmd_history() {
    setup_paths
    load_config

    local count="${1:-10}"

    if [[ ! -f "$CFG_HISTORY_FILE" ]]; then
        if [[ "$OPT_JSON" == "true" ]]; then
            json_output "ok" "No history available" "entries" "[]" "count" "0"
        else
            log_warn "No sync history found"
        fi
        return 0
    fi

    if [[ "$OPT_JSON" == "true" ]]; then
        local entries
        entries=$(head -n "$count" "$CFG_HISTORY_FILE" | paste -sd, - | sed 's/^/[/;s/$/]/')
        echo "{\"status\": \"ok\", \"entries\": $entries, \"count\": $(wc -l < "$CFG_HISTORY_FILE")}"
    else
        print_header "Sync History"

        local i=1
        while IFS= read -r line; do
            local ts status msg commit
            ts=$(echo "$line" | grep -oP '"timestamp":\s*"\K[^"]+' || echo "unknown")
            status=$(echo "$line" | grep -oP '"status":\s*"\K[^"]+' || echo "unknown")
            msg=$(echo "$line" | grep -oP '"message":\s*"\K[^"]+' || echo "")
            commit=$(echo "$line" | grep -oP '"commit":\s*"\K[^"]+' || echo "")

            local icon color
            case "$status" in
                success)  icon="✓"; color="$C_GREEN" ;;
                failure)  icon="✗"; color="$C_RED" ;;
                rollback) icon="↺"; color="$C_YELLOW" ;;
                restore)  icon="⟲"; color="$C_CYAN" ;;
                *)        icon="•"; color="$C_NC" ;;
            esac

            echo -e "  ${color}${icon}${C_NC} ${C_DIM}${ts}${C_NC} ${msg} ${C_DIM}(${commit})${C_NC}"
            ((i++))
        done < <(head -n "$count" "$CFG_HISTORY_FILE")

        local total
        total=$(wc -l < "$CFG_HISTORY_FILE")
        echo ""
        log_info "Showing $((i-1)) of $total entries"
    fi
}

# =============================================================================
# Metrics Command
# =============================================================================

cmd_metrics() {
    setup_paths
    load_config

    if [[ ! -f "$CFG_METRICS_FILE" ]]; then
        if [[ "$OPT_JSON" == "true" ]]; then
            json_output "error" "No metrics available"
        else
            log_warn "No metrics file found. Run a sync first."
            log_info "Metrics path: $CFG_METRICS_FILE"
        fi
        return 1
    fi

    if [[ "$OPT_JSON" == "true" ]]; then
        # Convert Prometheus format to JSON
        local metrics=()
        while IFS= read -r line; do
            [[ "$line" =~ ^# ]] && continue
            [[ -z "$line" ]] && continue
            local name value
            name=$(echo "$line" | cut -d' ' -f1)
            value=$(echo "$line" | cut -d' ' -f2)
            metrics+=("\"$name\": $value")
        done < "$CFG_METRICS_FILE"
        echo "{$(IFS=,; echo "${metrics[*]}")}"
    else
        print_header "Prometheus Metrics"
        echo "File: $CFG_METRICS_FILE"
        echo ""
        cat "$CFG_METRICS_FILE"
        echo ""
        log_info "Configure node_exporter to collect this file for Prometheus"
    fi
}

# =============================================================================
# Diff Command
# =============================================================================

cmd_diff() {
    setup_paths
    load_config

    [[ -z "$CFG_REPO_URL" ]] && { log_error "Repository URL not configured."; return 1; }

    print_header "DNS Changes Preview"

    # Ensure repo is initialized and updated
    if [[ ! -d "$CFG_REPO_PATH/.git" ]]; then
        log_info "Repository not initialized. Initializing..."
        git_init || return 1
    fi

    git_update || return 1

    generate_diff
}

# =============================================================================
# Completions Command
# =============================================================================

cmd_completions() {
    local shell="${1:-bash}"

    case "$shell" in
        bash)
            cat << 'BASH_COMPLETION'
# dns-sync bash completion
_dns_sync_completions() {
    local cur prev commands opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    commands="sync check watch diff validate config-test backups restore health status zones history metrics init update install uninstall completions help version"
    opts="-h --help -v --verbose -q --quiet -n --dry-run -f --force --no-restart --json --zone --config --repo-url --branch --ssh-key --interval"

    case "$prev" in
        --zone|--config|--repo-url|--branch|--ssh-key|--interval)
            return 0
            ;;
        restore)
            # Complete with backup files
            local backups
            backups=$(find /var/backups/dns-sync -name "*.bak" -type f 2>/dev/null | xargs -r basename -a)
            COMPREPLY=( $(compgen -W "$backups" -- "$cur") )
            return 0
            ;;
        completions)
            COMPREPLY=( $(compgen -W "bash zsh fish" -- "$cur") )
            return 0
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
    elif [[ ${COMP_CWORD} -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
    fi
}
complete -F _dns_sync_completions dns-sync
BASH_COMPLETION
            ;;
        zsh)
            cat << 'ZSH_COMPLETION'
#compdef dns-sync

_dns_sync() {
    local -a commands opts

    commands=(
        'sync:Sync DNS zones from Git to Pi-hole'
        'check:Quick check for remote changes'
        'watch:Continuous monitoring with auto-sync'
        'diff:Preview changes without applying'
        'validate:Validate zone files syntax'
        'config-test:Test configuration file'
        'backups:List available backups'
        'restore:Restore from backup'
        'health:Check system health'
        'status:Show current configuration'
        'zones:List available DNS zones'
        'history:Show sync history'
        'metrics:Show Prometheus metrics'
        'init:Initialize repository'
        'update:Update repository'
        'install:Install as system service'
        'uninstall:Remove system service'
        'completions:Generate shell completions'
        'help:Show help message'
        'version:Show version'
    )

    opts=(
        '-h[Show help]'
        '--help[Show help]'
        '-v[Verbose output]'
        '--verbose[Verbose output]'
        '-q[Quiet mode]'
        '--quiet[Quiet mode]'
        '-n[Dry run]'
        '--dry-run[Dry run]'
        '-f[Force operation]'
        '--force[Force operation]'
        '--no-restart[Skip Pi-hole restart]'
        '--json[JSON output]'
        '--zone[Sync specific zone]:zone:'
        '--config[Config file]:file:_files'
        '--repo-url[Git repository URL]:url:'
        '--branch[Git branch]:branch:'
        '--ssh-key[SSH key path]:file:_files'
        '--interval[Watch interval]:seconds:'
    )

    _arguments -C \
        '1:command:->command' \
        '*::arg:->args'

    case "$state" in
        command)
            _describe -t commands 'dns-sync commands' commands
            ;;
        args)
            _arguments $opts
            ;;
    esac
}

_dns_sync "$@"
ZSH_COMPLETION
            ;;
        fish)
            cat << 'FISH_COMPLETION'
# dns-sync fish completion
complete -c dns-sync -f

# Commands
complete -c dns-sync -n "__fish_use_subcommand" -a sync -d "Sync DNS zones"
complete -c dns-sync -n "__fish_use_subcommand" -a check -d "Quick change check"
complete -c dns-sync -n "__fish_use_subcommand" -a watch -d "Continuous monitoring"
complete -c dns-sync -n "__fish_use_subcommand" -a diff -d "Preview changes"
complete -c dns-sync -n "__fish_use_subcommand" -a validate -d "Validate zones"
complete -c dns-sync -n "__fish_use_subcommand" -a config-test -d "Test config"
complete -c dns-sync -n "__fish_use_subcommand" -a backups -d "List backups"
complete -c dns-sync -n "__fish_use_subcommand" -a restore -d "Restore backup"
complete -c dns-sync -n "__fish_use_subcommand" -a health -d "Health check"
complete -c dns-sync -n "__fish_use_subcommand" -a status -d "Show status"
complete -c dns-sync -n "__fish_use_subcommand" -a zones -d "List zones"
complete -c dns-sync -n "__fish_use_subcommand" -a history -d "Show history"
complete -c dns-sync -n "__fish_use_subcommand" -a metrics -d "Show metrics"
complete -c dns-sync -n "__fish_use_subcommand" -a init -d "Init repo"
complete -c dns-sync -n "__fish_use_subcommand" -a update -d "Update repo"
complete -c dns-sync -n "__fish_use_subcommand" -a install -d "Install service"
complete -c dns-sync -n "__fish_use_subcommand" -a uninstall -d "Uninstall service"
complete -c dns-sync -n "__fish_use_subcommand" -a help -d "Show help"

# Options
complete -c dns-sync -s h -l help -d "Show help"
complete -c dns-sync -s v -l verbose -d "Verbose output"
complete -c dns-sync -s q -l quiet -d "Quiet mode"
complete -c dns-sync -s n -l dry-run -d "Dry run"
complete -c dns-sync -s f -l force -d "Force"
complete -c dns-sync -l no-restart -d "Skip restart"
complete -c dns-sync -l json -d "JSON output"
complete -c dns-sync -l zone -d "Zone filter" -r
complete -c dns-sync -l config -d "Config file" -r -F
complete -c dns-sync -l interval -d "Watch interval" -r
FISH_COMPLETION
            ;;
        *)
            log_error "Unknown shell: $shell"
            log_info "Supported: bash, zsh, fish"
            return 1
            ;;
    esac
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    local positional=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)       cmd_help; exit 0 ;;
            -v|--verbose)    OPT_VERBOSE=true; shift ;;
            -q|--quiet)      OPT_QUIET=true; shift ;;
            -n|--dry-run)    OPT_DRY_RUN=true; shift ;;
            -f|--force)      OPT_FORCE=true; shift ;;
            --no-restart)    OPT_NO_RESTART=true; shift ;;
            --json)          OPT_JSON=true; shift ;;
            --zone)          OPT_ZONES+=("$2"); shift 2 ;;
            --config)        CFG_CONFIG_FILE="$2"; shift 2 ;;
            --repo-url)      CFG_REPO_URL="$2"; shift 2 ;;
            --branch)        CFG_REPO_BRANCH="$2"; shift 2 ;;
            --ssh-key)       CFG_SSH_KEY="$2"; shift 2 ;;
            --interval)      OPT_WATCH_INTERVAL="$2"; shift 2 ;;
            --version)       echo "dns-sync $VERSION"; exit 0 ;;
            -*)              log_error "Unknown option: $1"; echo "Try '$SCRIPT_NAME help'"; exit $E_ARGS ;;
            *)               positional+=("$1"); shift ;;
        esac
    done

    COMMAND="${positional[0]:-sync}"
    COMMAND_ARG="${positional[1]:-}"
}

# =============================================================================
# Main
# =============================================================================

main() {
    setup_colors
    parse_args "$@"

    case "$COMMAND" in
        # Sync operations
        sync)           cmd_sync ;;
        check)          cmd_check ;;
        watch)          cmd_watch ;;
        diff)           cmd_diff ;;

        # Validation
        validate)       setup_paths; load_config; validate_zones ;;
        config-test)    setup_paths; load_config; validate_config ;;

        # Backup & Restore
        backups)        setup_paths; load_config; list_backups ;;
        restore)        setup_paths; load_config; [[ -n "$COMMAND_ARG" ]] && restore_backup "$COMMAND_ARG" || { log_error "Usage: dns-sync restore <number|filename>"; exit $E_ARGS; } ;;

        # Information
        health)         cmd_health ;;
        status)         cmd_status ;;
        zones)          setup_paths; load_config; list_zones ;;
        history)        cmd_history "$COMMAND_ARG" ;;
        metrics)        cmd_metrics ;;

        # Repository
        init)           setup_paths; load_config; check_deps && acquire_lock && git_init ;;
        update)         setup_paths; load_config; check_deps && acquire_lock && git_init && git_update ;;

        # Installation
        install)        setup_paths; cmd_install ;;
        uninstall)      setup_paths; load_config; cmd_uninstall ;;
        completions)    cmd_completions "$COMMAND_ARG" ;;

        # Help
        help|--help|-h) cmd_help ;;
        version)        echo "dns-sync $VERSION"; exit 0 ;;

        *)              log_error "Unknown command: $COMMAND"; echo "Try '$SCRIPT_NAME help'"; exit $E_ARGS ;;
    esac
}

main "$@"

