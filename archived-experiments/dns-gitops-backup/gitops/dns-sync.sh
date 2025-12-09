#!/bin/bash
# DNS GitOps Sync Service
# Standalone service for syncing DNS zone files from Git to Pi-hole
# Can run independently without the main gitops-sync service

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Git repository
REPO_URL="${DNS_REPO_URL:-https://github.com/codefuturist/iac-catalog.git}"
REPO_BRANCH="${DNS_REPO_BRANCH:-develop}"
REPO_PATH="${DNS_REPO_PATH:-/opt/gitops/iac-catalog}"
ZONES_RELATIVE_PATH="${DNS_ZONES_PATH:-environments/global/configurations/dns-zones}"

# Paths
ZONES_DIR="$REPO_PATH/$ZONES_RELATIVE_PATH"
PIHOLE_TOML="${PIHOLE_TOML_PATH:-/etc/pihole/pihole.toml}"
CACHE_DIR="${DNS_CACHE_DIR:-/var/cache/gitops-dns}"
LOG_FILE="${DNS_LOG_FILE:-/var/log/dns-sync.log}"
LOCK_FILE="/var/run/dns-sync.lock"

# Zone parser script
SYNC_SCRIPT="$SCRIPT_DIR/sync-dns-zones.py"

# Logging
LOG_LEVEL="${DNS_LOG_LEVEL:-INFO}"

# =============================================================================
# Logging Functions
# =============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}][${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
}

log_warn() {
    log "WARN" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_debug() {
    if [[ "$LOG_LEVEL" == "DEBUG" ]]; then
        log "DEBUG" "$@"
    fi
}

# =============================================================================
# Lock Management
# =============================================================================

acquire_lock() {
    local max_wait=300  # 5 minutes
    local waited=0
    
    while [[ -f "$LOCK_FILE" ]]; do
        if [[ $waited -ge $max_wait ]]; then
            log_error "Lock file exists after ${max_wait}s, removing stale lock"
            rm -f "$LOCK_FILE"
            break
        fi
        
        log_debug "Waiting for lock file to be released..."
        sleep 5
        waited=$((waited + 5))
    done
    
    echo $$ > "$LOCK_FILE"
    log_debug "Acquired lock: $LOCK_FILE"
}

release_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
        log_debug "Released lock: $LOCK_FILE"
    fi
}

# Ensure lock is released on exit
trap release_lock EXIT INT TERM

# =============================================================================
# Git Operations
# =============================================================================

init_repo() {
    log_info "Initializing DNS repository..."
    
    if [[ ! -d "$REPO_PATH" ]]; then
        log_info "Cloning repository: $REPO_URL"
        
        local parent_dir
        parent_dir=$(dirname "$REPO_PATH")
        mkdir -p "$parent_dir"
        
        if git clone --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_PATH" 2>&1 | tee -a "$LOG_FILE"; then
            log_info "Repository cloned successfully"
            return 0
        else
            log_error "Failed to clone repository"
            return 1
        fi
    else
        log_debug "Repository already exists: $REPO_PATH"
        return 0
    fi
}

update_repo() {
    log_info "Updating DNS repository..."
    
    if [[ ! -d "$REPO_PATH/.git" ]]; then
        log_error "Repository not initialized: $REPO_PATH"
        return 1
    fi
    
    cd "$REPO_PATH" || return 1
    
    # Fetch updates
    log_debug "Fetching from remote..."
    if ! git fetch origin "$REPO_BRANCH" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Failed to fetch from remote"
        return 1
    fi
    
    # Check for changes
    local local_commit
    local remote_commit
    
    local_commit=$(git rev-parse HEAD)
    remote_commit=$(git rev-parse "origin/$REPO_BRANCH")
    
    if [[ "$local_commit" == "$remote_commit" ]]; then
        log_info "Repository already up to date"
        return 0
    fi
    
    log_info "New commits detected, updating..."
    log_debug "Local: $local_commit"
    log_debug "Remote: $remote_commit"
    
    # Reset to remote state
    if git reset --hard "origin/$REPO_BRANCH" 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Repository updated successfully"
        return 0
    else
        log_error "Failed to update repository"
        return 1
    fi
}

# =============================================================================
# DNS Sync Operations
# =============================================================================

validate_environment() {
    log_info "Validating environment..."
    
    # Check Python script exists
    if [[ ! -f "$SYNC_SCRIPT" ]]; then
        log_error "DNS sync script not found: $SYNC_SCRIPT"
        return 1
    fi
    
    # Check zones directory exists
    if [[ ! -d "$ZONES_DIR" ]]; then
        log_error "DNS zones directory not found: $ZONES_DIR"
        return 1
    fi
    
    # Check Pi-hole TOML exists
    if [[ ! -f "$PIHOLE_TOML" ]]; then
        log_error "Pi-hole TOML not found: $PIHOLE_TOML"
        return 1
    fi
    
    # Check for zone files
    local zone_count
    zone_count=$(find "$ZONES_DIR" -name "*.zone" -type f 2>/dev/null | wc -l)
    
    if [[ $zone_count -eq 0 ]]; then
        log_warn "No zone files found in $ZONES_DIR"
        return 0
    fi
    
    log_info "Environment validation passed"
    log_info "  Zones directory: $ZONES_DIR"
    log_info "  Zone files: $zone_count"
    log_info "  Pi-hole config: $PIHOLE_TOML"
    
    return 0
}

sync_dns() {
    log_info "Starting DNS zone synchronization..."
    log_info "=" | tr ' ' '=' | head -c 60
    echo ""
    
    # Run the Python sync script
    if sudo python3 "$SYNC_SCRIPT" "$ZONES_DIR" "$PIHOLE_TOML" 2>&1 | tee -a "$LOG_FILE"; then
        log_info "DNS sync completed successfully"
        
        # Record success
        echo "$(date -Iseconds)" > "$CACHE_DIR/last_dns_sync_success"
        
        # Restart Pi-hole FTL
        log_info "Restarting Pi-hole FTL service..."
        if sudo systemctl restart pihole-FTL 2>&1 | tee -a "$LOG_FILE"; then
            log_info "Pi-hole FTL restarted successfully"
        else
            log_warn "Failed to restart Pi-hole FTL"
        fi
        
        return 0
    else
        log_error "DNS sync failed"
        
        # Record failure
        echo "$(date -Iseconds)" > "$CACHE_DIR/last_dns_sync_failure"
        
        return 1
    fi
}

# =============================================================================
# Health Check
# =============================================================================

health_check() {
    log_info "Performing health check..."
    
    local status=0
    
    # Check if zones directory exists
    if [[ ! -d "$ZONES_DIR" ]]; then
        log_error "Zones directory missing: $ZONES_DIR"
        status=1
    fi
    
    # Check if Pi-hole is running
    if ! systemctl is-active --quiet pihole-FTL; then
        log_error "Pi-hole FTL is not running"
        status=1
    fi
    
    # Check last sync time
    if [[ -f "$CACHE_DIR/last_dns_sync_success" ]]; then
        local last_sync
        last_sync=$(cat "$CACHE_DIR/last_dns_sync_success")
        log_info "Last successful sync: $last_sync"
    else
        log_warn "No successful sync recorded"
    fi
    
    # Check for recent failures
    if [[ -f "$CACHE_DIR/last_dns_sync_failure" ]]; then
        local last_failure
        last_failure=$(cat "$CACHE_DIR/last_dns_sync_failure")
        log_warn "Last sync failure: $last_failure"
    fi
    
    if [[ $status -eq 0 ]]; then
        log_info "Health check passed"
    else
        log_error "Health check failed"
    fi
    
    return $status
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    local command="${1:-sync}"
    
    # Initialize logging
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$CACHE_DIR"
    
    log_info "=" | tr ' ' '=' | head -c 60
    echo ""
    log_info "DNS GitOps Sync Service Started"
    log_info "Command: $command"
    log_info "=" | tr ' ' '=' | head -c 60
    echo ""
    
    case "$command" in
        sync)
            acquire_lock
            
            # Initialize or update repository
            if ! init_repo; then
                log_error "Repository initialization failed"
                exit 1
            fi
            
            if ! update_repo; then
                log_error "Repository update failed"
                exit 1
            fi
            
            # Validate environment
            if ! validate_environment; then
                log_error "Environment validation failed"
                exit 1
            fi
            
            # Sync DNS
            if ! sync_dns; then
                log_error "DNS sync failed"
                exit 1
            fi
            
            log_info "=" | tr ' ' '=' | head -c 60
            echo ""
            log_info "DNS GitOps Sync Completed Successfully"
            log_info "=" | tr ' ' '=' | head -c 60
            echo ""
            ;;
            
        health)
            health_check
            exit $?
            ;;
            
        init)
            acquire_lock
            init_repo
            exit $?
            ;;
            
        update)
            acquire_lock
            update_repo
            exit $?
            ;;
            
        *)
            echo "Usage: $0 {sync|health|init|update}"
            echo ""
            echo "Commands:"
            echo "  sync    - Sync DNS zones from Git to Pi-hole (default)"
            echo "  health  - Check system health"
            echo "  init    - Initialize Git repository"
            echo "  update  - Update Git repository only"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
