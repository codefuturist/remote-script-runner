#!/bin/bash
# git-auto-sync.sh - Production-grade Git repository auto-sync with advanced features
# Part of Remote Script Runner collection
# Usage: curl -fsSL https://example.com/git-auto-sync.sh | bash -s -- [OPTIONS]

set -euo pipefail

# =============================================================================
# Configuration & Defaults
# =============================================================================

VERSION="1.0.0"
SCRIPT_NAME="git-auto-sync"
CONFIG_FILE="${GIT_SYNC_CONFIG:-}"
DEFAULT_SYNC_INTERVAL=300
DEFAULT_RETRY_ATTEMPTS=3
DEFAULT_RETRY_DELAY=5
DEFAULT_GIT_TIMEOUT=60
DEFAULT_LOG_LEVEL="INFO"

# Daemon control
DAEMON_MODE=false
LOCK_FILE="/tmp/git-auto-sync.lock"
PID_FILE="/tmp/git-auto-sync.pid"
METRICS_FILE="/tmp/git-auto-sync-metrics.json"

# Repository tracking
declare -a REPOS=()
declare -A REPO_PATHS=()
declare -A REPO_BRANCHES=()
declare -A REPO_REMOTES=()
declare -A REPO_MODES=()
declare -A REPO_LFS_ENABLED=()
declare -A REPO_HOOKS=()

# Statistics
TOTAL_SYNCS=0
SUCCESSFUL_SYNCS=0
FAILED_SYNCS=0
START_TIME=""

# Error recovery and validation
declare -A REPO_VALIDATORS=()
declare -A REPO_RETRY_COUNT=()
declare -A REPO_LAST_ERROR=()
declare -A REPO_VALIDATION_FAILED=()
MAX_VALIDATION_RETRIES=3
VALIDATION_ENABLED=true
ROLLBACK_ON_FAILURE=true

# =============================================================================
# Color Setup
# =============================================================================

setup_colors() {
    if [ -t 1 ]; then
        BLUE='\033[0;34m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        RED='\033[0;31m'
        CYAN='\033[0;36m'
        BOLD='\033[1m'
        DIM='\033[2m'
        NC='\033[0m'
    else
        BLUE=''
        GREEN=''
        YELLOW=''
        RED=''
        CYAN=''
        BOLD=''
        DIM=''
        NC=''
    fi
}

# =============================================================================
# Logging Functions
# =============================================================================

LOG_LEVEL="${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}"

log_with_timestamp() {
    local level="$1"
    shift
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf "[%s] [%s] %s\n" "$timestamp" "$level" "$*"
}

log_info() {
    [[ "$LOG_LEVEL" =~ ^(DEBUG|INFO)$ ]] && log_with_timestamp "INFO" "$@" || true
}

log_success() {
    log_with_timestamp "SUCCESS" "$@"
}

log_warn() {
    log_with_timestamp "WARN" "$@" >&2
}

log_error() {
    log_with_timestamp "ERROR" "$@" >&2
}

log_debug() {
    [[ "$LOG_LEVEL" == "DEBUG" ]] && log_with_timestamp "DEBUG" "$@" || true
}

log_fatal() {
    log_with_timestamp "FATAL" "$@" >&2
}

# =============================================================================
# Lock Management
# =============================================================================

create_lock() {
    local lockfile="$1"
    local max_wait=30
    local waited=0
    
    while [ -f "$lockfile" ]; do
        if [ $waited -ge $max_wait ]; then
            log_error "Lock file exists after ${max_wait}s. Another sync may be running."
            return 1
        fi
        log_debug "Waiting for lock to be released..."
        sleep 1
        ((waited++))
    done
    
    echo $$ > "$lockfile"
    log_debug "Lock acquired: $lockfile"
    return 0
}

remove_lock() {
    local lockfile="$1"
    if [ -f "$lockfile" ]; then
        rm -f "$lockfile"
        log_debug "Lock released: $lockfile"
    fi
}

# =============================================================================
# Signal Handlers
# =============================================================================

cleanup() {
    log_info "Cleaning up..."
    remove_lock "$LOCK_FILE"
    [ -f "$PID_FILE" ] && rm -f "$PID_FILE"
    exit 0
}

trap cleanup EXIT INT TERM

# =============================================================================
# Network Utilities
# =============================================================================

check_internet_connection() {
    local max_retries=5
    local retry_delay=2
    
    for ((i=1; i<=max_retries; i++)); do
        if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            log_debug "Internet connection verified"
            return 0
        fi
        
        if [ $i -lt $max_retries ]; then
            log_warn "No internet connection, retrying ($i/$max_retries)..."
            sleep $retry_delay
        fi
    done
    
    log_error "No internet connection detected after $max_retries attempts"
    return 1
}

# =============================================================================
# Validation Functions
# =============================================================================

# Generic file validator (can be overridden with custom validators)
validate_files() {
    local repo_path="$1"
    local validator="${2:-}"
    
    if [[ -z "$validator" ]]; then
        log_debug "No custom validator specified, using default checks"
        return 0
    fi
    
    if [[ ! -f "$validator" ]] && [[ ! -x "$validator" ]]; then
        log_warn "Validator not found or not executable: $validator"
        return 0
    fi
    
    log_info "Running validation: $validator"
    
    cd "$repo_path"
    
    if "$validator" "$repo_path"; then
        log_ok "Validation passed"
        return 0
    else
        log_error "Validation failed"
        return 1
    fi
}

# DNS zone file validator (example for DNS use case)
validate_dns_zones() {
    local repo_path="$1"
    local errors=0
    
    log_info "Validating DNS zone files..."
    
    # Check for common DNS files
    while IFS= read -r -d '' zone_file; do
        log_debug "Checking: $zone_file"
        
        # Check if named-checkzone is available
        if command -v named-checkzone >/dev/null 2>&1; then
            local zone_name
            zone_name=$(basename "$zone_file" .zone)
            
            if ! named-checkzone "$zone_name" "$zone_file" >/dev/null 2>&1; then
                log_error "Invalid zone file: $zone_file"
                ((errors++))
            fi
        else
            # Basic syntax check if named-checkzone not available
            if ! grep -q "SOA\|NS\|A\|AAAA" "$zone_file" 2>/dev/null; then
                log_warn "Suspicious zone file (no common records): $zone_file"
            fi
        fi
    done < <(find "$repo_path" -name "*.zone" -o -name "db.*" 2>/dev/null -print0)
    
    if [[ $errors -gt 0 ]]; then
        log_error "Found $errors invalid zone file(s)"
        return 1
    fi
    
    log_ok "All DNS zones are valid"
    return 0
}

# YAML validator
validate_yaml_files() {
    local repo_path="$1"
    local errors=0
    
    log_info "Validating YAML files..."
    
    while IFS= read -r -d '' yaml_file; do
        log_debug "Checking: $yaml_file"
        
        # Try python yaml validation first
        if command -v python3 >/dev/null 2>&1; then
            if ! python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))" 2>/dev/null; then
                log_error "Invalid YAML: $yaml_file"
                ((errors++))
            fi
        elif command -v yq >/dev/null 2>&1; then
            if ! yq eval '.' "$yaml_file" >/dev/null 2>&1; then
                log_error "Invalid YAML: $yaml_file"
                ((errors++))
            fi
        fi
    done < <(find "$repo_path" -name "*.yaml" -o -name "*.yml" 2>/dev/null -print0)
    
    if [[ $errors -gt 0 ]]; then
        log_error "Found $errors invalid YAML file(s)"
        return 1
    fi
    
    log_ok "All YAML files are valid"
    return 0
}

# JSON validator
validate_json_files() {
    local repo_path="$1"
    local errors=0
    
    log_info "Validating JSON files..."
    
    while IFS= read -r -d '' json_file; do
        log_debug "Checking: $json_file"
        
        if command -v jq >/dev/null 2>&1; then
            if ! jq empty "$json_file" 2>/dev/null; then
                log_error "Invalid JSON: $json_file"
                ((errors++))
            fi
        elif command -v python3 >/dev/null 2>&1; then
            if ! python3 -c "import json; json.load(open('$json_file'))" 2>/dev/null; then
                log_error "Invalid JSON: $json_file"
                ((errors++))
            fi
        fi
    done < <(find "$repo_path" -name "*.json" 2>/dev/null -print0)
    
    if [[ $errors -gt 0 ]]; then
        log_error "Found $errors invalid JSON file(s)"
        return 1
    fi
    
    log_ok "All JSON files are valid"
    return 0
}

# =============================================================================
# Git Utilities
# =============================================================================

is_git_repo() {
    local path="$1"
    [ -d "$path/.git" ]
}

get_current_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""
}

get_current_commit() {
    git rev-parse --short HEAD 2>/dev/null || echo ""
}

is_repo_clean() {
    git diff-index --quiet HEAD 2>/dev/null
}

has_git_lfs() {
    git lfs version >/dev/null 2>&1
}

is_lfs_enabled() {
    local path="$1"
    [ -f "$path/.gitattributes" ] && grep -q "filter=lfs" "$path/.gitattributes"
}

remote_exists() {
    local remote="$1"
    git remote get-url "$remote" >/dev/null 2>&1
}

get_repo_stats() {
    local path="$1"
    local file_count
    local size_kb
    
    file_count=$(git ls-files | wc -l | tr -d ' ')
    size_kb=$(du -sk "$path" 2>/dev/null | cut -f1 || echo "0")
    
    printf '{"files":%d,"size_kb":%d}' "$file_count" "$size_kb"
}

create_backup() {
    local repo_path="$1"
    local backup_dir="${repo_path}/.git-auto-sync-backups"
    local timestamp
    timestamp=$(date '+%Y%m%d-%H%M%S')
    
    mkdir -p "$backup_dir"
    
    cd "$repo_path"
    local current_commit
    current_commit=$(get_current_commit)
    
    # Store commit hash for rollback
    echo "$current_commit" > "$backup_dir/last-good-commit-${timestamp}"
    
    # Keep only last 5 backups
    ls -t "$backup_dir"/last-good-commit-* 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
    
    log_debug "Backup created: $current_commit"
}

rollback_to_backup() {
    local repo_path="$1"
    local backup_dir="${repo_path}/.git-auto-sync-backups"
    
    if [[ ! -d "$backup_dir" ]]; then
        log_error "No backup directory found"
        return 1
    fi
    
    cd "$repo_path"
    
    # Find most recent backup
    local latest_backup
    latest_backup=$(ls -t "$backup_dir"/last-good-commit-* 2>/dev/null | head -1)
    
    if [[ -z "$latest_backup" ]]; then
        log_error "No backup found for rollback"
        return 1
    fi
    
    local backup_commit
    backup_commit=$(cat "$latest_backup")
    
    log_warn "Rolling back to: $backup_commit"
    
    if git reset --hard "$backup_commit"; then
        log_ok "Rollback successful"
        return 0
    else
        log_error "Rollback failed"
        return 1
    fi
}

# =============================================================================
# Repository Sync Functions
# =============================================================================

sync_repository() {
    local repo_name="$1"
    local repo_path="${REPO_PATHS[$repo_name]}"
    local branch="${REPO_BRANCHES[$repo_name]:-main}"
    local remote="${REPO_REMOTES[$repo_name]:-origin}"
    local mode="${REPO_MODES[$repo_name]:-safe}"
    local use_lfs="${REPO_LFS_ENABLED[$repo_name]:-false}"
    local post_hook="${REPO_HOOKS[$repo_name]:-}"
    local validator="${REPO_VALIDATORS[$repo_name]:-}"
    
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Syncing repository: ${BOLD}$repo_name${NC}"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_debug "Path: $repo_path | Branch: $branch | Mode: $mode"
    
    # Check retry count
    local retry_count="${REPO_RETRY_COUNT[$repo_name]:-0}"
    if [[ $retry_count -ge $MAX_VALIDATION_RETRIES ]]; then
        log_error "Max retry attempts ($MAX_VALIDATION_RETRIES) reached for $repo_name"
        log_error "Last error: ${REPO_LAST_ERROR[$repo_name]:-Unknown}"
        log_warn "Manual intervention required. Fix the issue and retry."
        return 1
    fi
    
    # Verify repository exists
    if ! is_git_repo "$repo_path"; then
        log_error "Not a git repository: $repo_path"
        REPO_LAST_ERROR[$repo_name]="Not a git repository"
        return 1
    fi
    
    cd "$repo_path" || return 1
    
    # Create backup before sync
    if [[ "$ROLLBACK_ON_FAILURE" == "true" ]]; then
        create_backup "$repo_path"
    fi
    
    # Store initial state
    local old_commit
    old_commit=$(get_current_commit)
    
    # Verify remote exists
    if ! remote_exists "$remote"; then
        log_error "Remote '$remote' does not exist"
        return 1
    fi
    
    # Fetch with retry
    log_info "Fetching from $remote..."
    if ! retry_command $DEFAULT_RETRY_ATTEMPTS $DEFAULT_RETRY_DELAY \
        timeout "$DEFAULT_GIT_TIMEOUT" git fetch --quiet "$remote" "$branch"; then
        log_error "Failed to fetch from $remote"
        return 1
    fi
    
    # Handle local changes based on mode
    case "$mode" in
        safe)
            if ! is_repo_clean; then
                log_warn "Repository has uncommitted changes, stashing..."
                git stash push -m "Auto-stash by git-auto-sync at $(date '+%Y-%m-%d %H:%M:%S')" || true
            fi
            
            # Try fast-forward merge
            if git merge --ff-only "$remote/$branch" 2>/dev/null; then
                log_debug "Fast-forward merge successful"
            else
                log_warn "Fast-forward not possible, using reset"
                git reset --hard "$remote/$branch"
            fi
            ;;
            
        force)
            log_info "Force mode: resetting to $remote/$branch"
            git reset --hard "$remote/$branch"
            git clean -fdx
            ;;
            
        pull)
            log_info "Pull mode: pulling from $remote/$branch"
            git checkout -qf "$branch"
            git pull --ff-only "$remote" "$branch" || {
                log_warn "Pull failed, falling back to reset"
                git reset --hard "$remote/$branch"
            }
            ;;
            
        *)
            log_error "Unknown sync mode: $mode"
            return 1
            ;;
    esac
    
    # Git LFS sync
    if [ "$use_lfs" = "true" ] && has_git_lfs && is_lfs_enabled "$repo_path"; then
        log_info "Syncing Git LFS files..."
        if ! retry_command $DEFAULT_RETRY_ATTEMPTS $DEFAULT_RETRY_DELAY \
            timeout "$DEFAULT_GIT_TIMEOUT" git lfs fetch "$remote" "$branch"; then
            log_warn "Git LFS fetch failed"
        fi
        
        if ! git lfs pull; then
            log_warn "Git LFS pull failed"
        fi
    fi
    
    # Get new state
    local new_commit
    new_commit=$(get_current_commit)
    
    # Report changes
    local has_changes=false
    if [ "$old_commit" != "$new_commit" ]; then
        log_success "Repository updated: $old_commit → $new_commit"
        has_changes=true
        
        # Show commit log
        if [ "$LOG_LEVEL" = "DEBUG" ]; then
            git log --oneline "$old_commit..$new_commit" 2>/dev/null || true
        fi
    else
        log_info "Repository already up to date"
    fi
    
    # Validate repository contents if changes were made or validation previously failed
    if [[ "$VALIDATION_ENABLED" == "true" ]] && [[ "$has_changes" == "true" || "${REPO_VALIDATION_FAILED[$repo_name]:-false}" == "true" ]]; then
        log_info "Validating repository contents..."
        
        local validation_result=0
        
        # Run custom validator if specified
        if [[ -n "$validator" ]]; then
            if ! validate_files "$repo_path" "$validator"; then
                validation_result=1
            fi
        else
            # Run built-in validators based on file types
            if ! validate_json_files "$repo_path"; then
                validation_result=1
            fi
            
            if ! validate_yaml_files "$repo_path"; then
                validation_result=1
            fi
            
            # DNS-specific validation if zone files present
            if find "$repo_path" -name "*.zone" -o -name "db.*" 2>/dev/null | grep -q .; then
                if ! validate_dns_zones "$repo_path"; then
                    validation_result=1
                fi
            fi
        fi
        
        if [[ $validation_result -ne 0 ]]; then
            log_error "Validation failed for $repo_name"
            REPO_VALIDATION_FAILED[$repo_name]="true"
            REPO_LAST_ERROR[$repo_name]="Validation failed"
            REPO_RETRY_COUNT[$repo_name]=$((retry_count + 1))
            
            # Rollback if enabled
            if [[ "$ROLLBACK_ON_FAILURE" == "true" ]]; then
                log_warn "Rolling back changes due to validation failure..."
                if rollback_to_backup "$repo_path"; then
                    log_ok "Rollback completed, repository restored to known good state"
                else
                    log_error "Rollback failed! Manual intervention required"
                fi
            fi
            
            # Check if we should retry
            if [[ $((retry_count + 1)) -lt $MAX_VALIDATION_RETRIES ]]; then
                log_info "Will retry on next sync cycle (attempt $((retry_count + 2))/$MAX_VALIDATION_RETRIES)"
            else
                log_error "Max retries reached. Manual fix required."
            fi
            
            return 1
        else
            log_ok "Validation passed"
            REPO_VALIDATION_FAILED[$repo_name]="false"
            REPO_RETRY_COUNT[$repo_name]=0
            REPO_LAST_ERROR[$repo_name]=""
        fi
    fi
    
    # Execute post-sync hook (only if validation passed)
    if [ -n "$post_hook" ] && [ -x "$post_hook" ]; then
        log_info "Executing post-sync hook: $post_hook"
        if ! "$post_hook" "$repo_name" "$repo_path" "$old_commit" "$new_commit"; then
            log_warn "Post-sync hook failed"
            REPO_LAST_ERROR[$repo_name]="Post-sync hook failed"
            # Don't rollback for hook failures, just warn
        fi
    fi
    
    # Get statistics
    local stats
    stats=$(get_repo_stats "$repo_path")
    log_debug "Repository stats: $stats"
    
    return 0
}

# =============================================================================
# Retry Logic
# =============================================================================

retry_command() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local attempt=1
    
    while [ $attempt -le "$max_attempts" ]; do
        if "$@"; then
            return 0
        else
            if [ $attempt -lt "$max_attempts" ]; then
                log_debug "Attempt $attempt/$max_attempts failed, retrying in ${delay}s..."
                sleep "$delay"
                delay=$((delay * 2))
            fi
            ((attempt++))
        fi
    done
    
    return 1
}

# =============================================================================
# Configuration Management
# =============================================================================

load_config_file() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    log_info "Loading configuration from: $config_file"
    
    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is required to parse JSON configuration"
        return 1
    fi
    
    # Parse JSON configuration
    local repo_count
    repo_count=$(jq -r 'length' "$config_file")
    
    log_info "Found $repo_count repository/repositories in configuration"
    
    for ((i=0; i<repo_count; i++)); do
        local name path branch remote mode use_lfs post_hook validator
        
        name=$(jq -r ".[$i].name" "$config_file")
        path=$(jq -r ".[$i].path" "$config_file")
        branch=$(jq -r ".[$i].branch // \"main\"" "$config_file")
        remote=$(jq -r ".[$i].remote // \"origin\"" "$config_file")
        mode=$(jq -r ".[$i].mode // \"safe\"" "$config_file")
        use_lfs=$(jq -r ".[$i].use_lfs // false" "$config_file")
        post_hook=$(jq -r ".[$i].post_hook // \"\"" "$config_file")
        validator=$(jq -r ".[$i].validator // \"\"" "$config_file")
        
        add_repository "$name" "$path" "$branch" "$remote" "$mode" "$use_lfs" "$post_hook" "$validator"
    done
    
    # Load global validation settings if present
    if jq -e '.validation' "$config_file" >/dev/null 2>&1; then
        VALIDATION_ENABLED=$(jq -r '.validation.enabled // true' "$config_file")
        MAX_VALIDATION_RETRIES=$(jq -r '.validation.max_retries // 3' "$config_file")
        ROLLBACK_ON_FAILURE=$(jq -r '.validation.rollback_on_failure // true' "$config_file")
        log_debug "Validation settings: enabled=$VALIDATION_ENABLED, max_retries=$MAX_VALIDATION_RETRIES, rollback=$ROLLBACK_ON_FAILURE"
    fi
}

add_repository() {
    local name="$1"
    local path="$2"
    local branch="${3:-main}"
    local remote="${4:-origin}"
    local mode="${5:-safe}"
    local use_lfs="${6:-false}"
    local post_hook="${7:-}"
    local validator="${8:-}"
    
    REPOS+=("$name")
    REPO_PATHS[$name]="$path"
    REPO_BRANCHES[$name]="$branch"
    REPO_REMOTES[$name]="$remote"
    REPO_MODES[$name]="$mode"
    REPO_LFS_ENABLED[$name]="$use_lfs"
    REPO_HOOKS[$name]="$post_hook"
    REPO_VALIDATORS[$name]="$validator"
    REPO_RETRY_COUNT[$name]=0
    REPO_LAST_ERROR[$name]=""
    REPO_VALIDATION_FAILED[$name]="false"
    
    log_debug "Added repository: $name at $path"
}

# =============================================================================
# Metrics & Reporting
# =============================================================================

update_metrics() {
    local repo_name="$1"
    local status="$2"
    local commit="${3:-}"
    
    cat > "$METRICS_FILE" <<EOF
{
  "daemon": {
    "started_at": "$START_TIME",
    "pid": $$,
    "status": "running"
  },
  "sync_stats": {
    "total_runs": $TOTAL_SYNCS,
    "successful_runs": $SUCCESSFUL_SYNCS,
    "failed_runs": $FAILED_SYNCS,
    "last_run": "$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")"
  },
  "last_sync": {
    "repository": "$repo_name",
    "status": "$status",
    "commit": "$commit",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")"
  }
}
EOF
}

print_summary() {
    log_info ""
    log_info "╔════════════════════════════════════════════════════════╗"
    log_info "║              Sync Summary                              ║"
    log_info "╚════════════════════════════════════════════════════════╝"
    log_info "Total repositories: ${#REPOS[@]}"
    log_info "Successful: $SUCCESSFUL_SYNCS"
    log_info "Failed: $FAILED_SYNCS"
    log_info "Duration: $(($(date +%s) - $(date -j -f "%Y-%m-%dT%H:%M:%S" "${START_TIME%.*}" +%s 2>/dev/null || date +%s)))s"
}

# =============================================================================
# Main Sync Process
# =============================================================================

sync_all_repositories() {
    log_info "╔════════════════════════════════════════════════════════╗"
    log_info "║         Git Auto-Sync v$VERSION                         ║"
    log_info "╚════════════════════════════════════════════════════════╝"
    log_info "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
    
    START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
    TOTAL_SYNCS=$((TOTAL_SYNCS + 1))
    
    # Check internet connection first
    if ! check_internet_connection; then
        log_error "Cannot proceed without internet connection"
        FAILED_SYNCS=$((FAILED_SYNCS + 1))
        return 1
    fi
    
    # Acquire lock
    if ! create_lock "$LOCK_FILE"; then
        log_error "Failed to acquire lock"
        FAILED_SYNCS=$((FAILED_SYNCS + 1))
        return 1
    fi
    
    local failed_repos=()
    
    # Sync each repository
    for repo_name in "${REPOS[@]}"; do
        log_info ""
        if sync_repository "$repo_name"; then
            SUCCESSFUL_SYNCS=$((SUCCESSFUL_SYNCS + 1))
            update_metrics "$repo_name" "success" "$(cd "${REPO_PATHS[$repo_name]}" && get_current_commit)"
        else
            failed_repos+=("$repo_name")
            FAILED_SYNCS=$((FAILED_SYNCS + 1))
            update_metrics "$repo_name" "failed" ""
        fi
        
        # Small delay between repositories
        sleep 1
    done
    
    # Release lock
    remove_lock "$LOCK_FILE"
    
    # Print summary
    print_summary
    
    # Report failed repositories
    if [ ${#failed_repos[@]} -gt 0 ]; then
        log_error "Failed repositories: ${failed_repos[*]}"
        return 1
    fi
    
    log_success "All repositories synced successfully"
    return 0
}

# =============================================================================
# Daemon Mode
# =============================================================================

run_daemon() {
    local interval="${1:-$DEFAULT_SYNC_INTERVAL}"
    
    log_info "Starting daemon mode (interval: ${interval}s)"
    
    # Write PID file
    echo $$ > "$PID_FILE"
    
    # Continuous sync loop
    while true; do
        sync_all_repositories || log_warn "Sync cycle failed, continuing..."
        
        log_info "Waiting ${interval}s until next sync..."
        sleep "$interval"
    done
}

# =============================================================================
# Usage & Help
# =============================================================================

show_usage() {
    cat <<EOF
${BOLD}Git Auto-Sync v${VERSION}${NC}
Production-grade Git repository synchronization with validation & error recovery

${BOLD}USAGE:${NC}
    $0 [OPTIONS]

${BOLD}OPTIONS:${NC}
    -c, --config FILE       Configuration file (JSON format)
    -d, --daemon            Run in daemon mode (continuous sync)
    -i, --interval SECONDS  Sync interval for daemon mode (default: 300)
    -r, --repo PATH         Add repository to sync (can be used multiple times)
    -b, --branch NAME       Branch to sync (default: main)
    -m, --mode MODE         Sync mode: safe|force|pull (default: safe)
    -l, --lfs               Enable Git LFS support
    --remote NAME           Remote name (default: origin)
    --hook SCRIPT           Post-sync hook script
    --validator SCRIPT      Custom validation script
    -v, --verbose           Enable debug logging
    -h, --help              Show this help message
    --version               Show version information

${BOLD}SYNC MODES:${NC}
    safe    - Fast-forward merge, stash local changes (recommended)
    force   - Hard reset to remote, discard all local changes
    pull    - Standard git pull with fallback to reset

${BOLD}VALIDATION & ERROR RECOVERY:${NC}
    • Automatic validation of JSON, YAML, and DNS zone files
    • Custom validator scripts for domain-specific validation
    • Automatic rollback on validation failure
    • Retry mechanism with configurable attempts (default: 3)
    • Backup of last known good state
    • Manual intervention prompts when max retries reached

${BOLD}EXAMPLES:${NC}
    # Sync with validation
    $0 --config repos.json

    # DNS zone sync with validation
    $0 -r /etc/bind/zones --validator /usr/local/bin/validate-dns.sh

    # Daemon mode with automatic retry
    $0 --daemon --config repos.json --interval 300

    # Remote execution with validation
    curl -fsSL https://example.com/git-auto-sync.sh | bash -s -- --config /tmp/config.json

${BOLD}CONFIG FILE FORMAT:${NC}
    {
      "validation": {
        "enabled": true,
        "max_retries": 3,
        "rollback_on_failure": true
      },
      "repositories": [
        {
          "name": "dns-zones",
          "path": "/etc/bind/zones",
          "branch": "main",
          "remote": "origin",
          "mode": "safe",
          "use_lfs": false,
          "validator": "/usr/local/bin/validate-dns.sh",
          "post_hook": "/usr/local/bin/reload-bind.sh"
        }
      ]
    }

${BOLD}CUSTOM VALIDATORS:${NC}
    Validators receive the repository path as argument and should:
    • Exit 0 if validation passes
    • Exit 1 if validation fails
    • Output error messages to stderr

    Example validator:
      #!/bin/bash
      repo_path="\$1"
      find "\$repo_path" -name "*.zone" -exec named-checkzone {} \\;

${BOLD}DOCUMENTATION:${NC}
    https://github.com/yourusername/remote-script-runner
EOF
}

show_version() {
    echo "Git Auto-Sync v${VERSION}"
    echo "Part of Remote Script Runner"
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_arguments() {
    local repo_path=""
    local branch="main"
    local remote="origin"
    local mode="safe"
    local use_lfs="false"
    local post_hook=""
    local sync_interval="$DEFAULT_SYNC_INTERVAL"
    local repo_counter=0
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -d|--daemon)
                DAEMON_MODE=true
                shift
                ;;
            -i|--interval)
                sync_interval="$2"
                shift 2
                ;;
            -r|--repo)
                repo_path="$2"
                ((repo_counter++))
                add_repository "repo-$repo_counter" "$repo_path" "$branch" "$remote" "$mode" "$use_lfs" "$post_hook"
                shift 2
                ;;
            -b|--branch)
                branch="$2"
                shift 2
                ;;
            -m|--mode)
                mode="$2"
                shift 2
                ;;
            --remote)
                remote="$2"
                shift 2
                ;;
            -l|--lfs)
                use_lfs="true"
                shift
                ;;
            --hook)
                post_hook="$2"
                shift 2
                ;;
            -v|--verbose)
                LOG_LEVEL="DEBUG"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Load config file if provided
    if [ -n "$CONFIG_FILE" ]; then
        load_config_file "$CONFIG_FILE"
    fi
    
    # Validate we have at least one repository
    if [ ${#REPOS[@]} -eq 0 ]; then
        log_error "No repositories configured. Use -r or --config"
        show_usage
        exit 1
    fi
    
    # Run sync
    if [ "$DAEMON_MODE" = true ]; then
        run_daemon "$sync_interval"
    else
        sync_all_repositories
        exit $?
    fi
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
    setup_colors
    parse_arguments "$@"
}

main "$@"
